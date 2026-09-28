# Design: sliced-panel-review

- Change: sliced-panel-review
- Status: draft

- 规划双出: GPT 在主 agent 接手**之前**独立写出的 `tasks/sliced-panel-review-plan.md`(对照组)
  + 它派的 sub codex 对抗评审 `evidence/premise-attack.md`。与本设计的差异见文末「与 GPT 计划的差异」。

## Approach

### 一句话

`panel-slice` 是一个**薄编排器**:主 agent 写清单 → 它按健康池给每片分一个不同家族的腿、
给整体腿分 GPT → **每个工作项调用一次钉住单腿的 `panel-review --scoped-review`** →
全部结果、预算占用、问题记录都落在一个仓外的 run 目录里,`status` 只读盘重建。

```text
主 agent: manifest(goal + 2..8 片 + overall + extra 预算) + 自审 my-review(仓外)
                │
      panel-slice run ── 健康探针:panel-review --scoped-review --risk self(不派腿、不动轮换游标)
                │        分配:各片家族互异;整体腿(默认 subcodex=openai)家族不与任何片重复
                │        先落 plan.json,再逐项落 reserved.json,再起进程
   ┌────────────┼──────────────┬──────────────┐
 片1:腿A      片2:腿B   …    片N:腿N       overall:subcodex
 (每项 = setsid panel-review --scoped-review --pin-leg X --budget 1 --no-track)
   └────────────┴──────────────┴──────────────┘
                │   各腿结果 review_contract_version=2 ⇒ 旧覆盖谓词一律 ineligible
      panel-slice status(纯读盘):覆盖 / 未收尾 / 未登记的 BLOCK / 源码是否同一份 / 预算
                │
   主 agent 读报告 → verify 清单(登记 finding + 指定复核)
      panel-slice verify:finding 追加入账;复核腿家族 ≠ 该 finding 出处的家族;占 extra 预算,all-or-nothing
      panel-slice retry:失败/无裁决的项,或想再看一遍的 done 项,重派一次;**每次都占 extra**,
                         最新尝试还是 unknown 的不许 retry;旧尝试的 BLOCK 不会被新 PASS 抹掉
      panel-slice abandon:unknown 且没有任何活进程命令行引用它的尝试 ⇒ 主 agent 带理由宣布放弃;
                         额度照记,之后可 retry;事后结果真落盘了,按结果算(2026-09-14 评审发现 A)
      panel-slice decide:主 agent 对 finding 的处置(confirmed/rejected/accepted-risk/inconclusive)只追加
                │
          主 agent 仲裁(run_state=clean 也只是事实汇总,不是 PASS)
```

### 为什么「每项调一次 panel-review」而不是新写一个派发器

对抗评审第 5 点:「一个新编排模块仍可能带来第二套生命周期系统」。panel-review 身上背着
一长串事故换来的保证 —— 反锚定闸、任务字节冻结、腿在 setsid 会话里自己落终态
(08-23 控制器先死)、typed result、健康/冷却/dead、花名册从盘上重建。重写一份就是
「同一件事写两处、只更新一处」。所以 panel-review 只加 4 个最小开关,其余全部复用:

| 开关 | 语义 | 为什么 |
|---|---|---|
| `--scoped-review` | 结果写 `review_contract_version=2`;不推进普通轮换游标;关闭 agent→chat 自动回落;角色腿可见;与 `--track` 互斥;`--budget>0` 时必须 `--pin-leg` | 切片结果不许被旧归档门槛计数;不许暗中多一次调用;不扰动普通池公平性 |
| `--pin-leg NAME` | 本轮只有这一条腿可选(其余视为 off) | 分配权在 panel-slice(家族互异是全局约束) |
| 角色腿表 `PANEL_ROLE_LEG_SPECS` | 与轮换池表同格式、同取值函数;只在 scoped 模式进 LEGS,花名册只在 plan 里出现时才印 | GPT 是默认执行腿(delegate-codex),进普通池会审到自家代码,也会吃掉今天刚耗尽的 codex 额度 |
| 探针 | 不新增模式:`--scoped-review --risk self`(预算 0)本来就只写 plan 不派腿 | 零新代码路径;health 规则只有 panel-review 里那一份 |

### 为什么切片结果标新契约版本而不是只靠「不写 observation」

`_review_result.py` 早有扩展点 `SUPPORTED_REVIEW_CONTRACTS={1}`,不认的版本 → `review_contract_unsupported`
→ 永不 eligible。只靠「panel-slice 不传 --track」是**流程**上的排除;有人手动
`track-record observe --leg-result <切片结果>` 就能把一个切片的 PASS 塞进 standard track 的 1 家族预算。
标版本是**数据**上的排除,两道都要。代价:这些腿在 health.tsv 里记成 `INELIGIBLE`
(不冷却、streak 清零),花名册印 `coverage=INELIGIBLE` —— 说的正是实话。

### run 目录(仓外;默认 `<tool-root>/logs/slice-<manifest>-<ts>/`)

```
manifest.json + input/{goal.md, slices/<id>.md, overall.md}   冻结副本 + sha256(plan.json 里)
plan.json            派发前原子写:items[id,role,leg,family,task_sha256], budget, source 指纹
items/<id>/task.md   该项完整任务书(角色说明 + goal + 本片 brief)
items/<id>/attempt-N/reserved.json   起进程之前 O_EXCL 落盘 = 占一个会话额度
items/<id>/attempt-N/panel.*          panel-review 的 LOG_PREFIX(plan/state/result.json/log/roster)
items/<id>/attempt-N/controller.exit  panel-slice 等到控制器退出后写(控制器被砍则没有 ⇒ unknown)
verify/round-N.json  复核轮次(引用父 plan 的 run_id,不改写 plan.json)
findings.jsonl       只追加:finding / check / decision 三种事件,文件锁串行
status.md            人读汇总(`status --json` 输出稳定、无时间戳)
```

### 项状态(每个尝试,纯读盘)

`done`(rc=0、PASS/BLOCK、非降级、证据完整、eligibility 理由**恰好只有** review_contract_unsupported)/
`needs_more_info` / `no_verdict` / `failed(kind)` / `degraded` / `ineligible(理由)` /
`not_dispatched`(控制器写了 plan 但腿没被选中,例如探针后健康变了)/ `launch_failed`(控制器 rc≠0 且无 plan)/
`unknown`(占了额度但没有终态 —— **不说它死了**,可能还在跑)/ `abandoned`(主 agent 用 abandon 宣布
永远不会结束;有结果落盘时让位给结果)/ `contract_violation`(契约版本不是 2)。

run_state:
- `incomplete`:任一初始项(片/overall)没有 `done` 的尝试;或有 unknown;或 done 的尝试之间源码指纹不一致;或 contract_violation。
- `attention`:齐了,但有未处置的 finding、未登记的 BLOCK/NMI(任一尝试,不止最后一次)、派出去没完成的复核。
  **登记对准一次尝试**:finding 的 `source` 写 `<item>#<n>`(或 `main`),只确认那一次尝试的 BLOCK/NMI;
  同一项两次 BLOCK 要各有一条 finding。第一版按项确认,给 s1 登记任意一条就把 s1 所有拦截裁决一笔勾销(评审发现 D)。
- `clean`:以上都没有。**只是事实汇总,永远不是 PASS。**

### 分配规则

- 候选 = 探针 plan 里 health=healthy 的腿;片默认只从轮换池选,顺序 = 池顺序按起点轮转(起点随机,判据用 `PANEL_SLICE_ASSIGN_START` 固定)。
- manifest 可给某片 `leg` 钉死;钉的腿必须健康、家族不重复。
- overall 默认 `subcodex`,可钉别的腿或 `auto`(第一个家族未被用的健康腿);家族不许与任何片相同。
- 凑不齐 ⇒ **派发前拒绝**、零调用,打印健康腿与家族,建议合片或钉腿。不静默重复家族。
- verify:复核腿家族 ∉ 被复核 finding 出处项**所有尝试**用过的家族;出处可为 `main`(主 agent 自己的发现)。
- retry:默认同腿(健康时);否则挑家族不与其他初始项冲突的健康腿;overall 仍不许与片同家族。

### 预算

`initial_sessions = 片数 + 1` 由清单决定;`extra_sessions` 清单给(默认 2,0..10),verify 与 retry 共用。
占额度 = 起进程之前落 `reserved.json`(文件锁内复查余量),与腿成败无关(失败也花过钱)。
verify/retry 的余量在登记任何东西之前整体检查,不够就整批拒绝(不半截派发)。
回落到聊天腿在 scoped 模式里关闭,不存在「一次预算两次调用」。

### 源码一致

plan 时记 `source`:HEAD + `git diff HEAD --binary` + 未跟踪文件清单与内容的 sha256(只读,不往源仓写对象)。
verify/retry 前重算,不同就拒绝(「代码变了,开新一轮」);status 另查各 done 尝试的 `subject.source` 是否同一份。

### 腿内「不许再派 agent」逐腿核实

| 腿 | 机械约束 | 依据 |
|---|---|---|
| submimo | 自建 `aiwork-review` agent:`task: False` + 权限 deny | bin/submimo 工具表 |
| subdeepseek-agent(claude 底座) | `--disallowedTools ... Task Agent` | bin/subagent |
| subglm-agent(opencode 底座) | 工具表 `task: False` | bin/subagent |
| subkimi | PreToolUse 守卫默认 DENY,Agent/AgentSwarm 不在白名单 | kimi-review-home/hooks/guard.mjs |
| subgemini(agy) | permissions 白名单只有 read_file + 只读 git,其余 headless auto-deny | bin/subgemini(**未实测 agy 是否有子 agent 工具**) |
| subcodex(新) | 覆盖 codex 模型目录去掉 `multi_agent_version` + 派发前 `codex debug prompt-input` 离线核验无 `<multi_agent_role>`;`-c web_search="disabled"` | **09-13 真跑证伪了第一版**:`--disable multi_agent/multi_agent_v2` 对 gpt-6-astra 无效(能力在模型目录里),腿身上有 `collaboration.spawn_agent` 和 `web__run`;改后两次真跑归因各开关,见 verify.md |

**共同的敞口(如实写,不宣称严格)**:所有 agent 腿都有 Bash 跑在可丢弃副本里,原则上能在 shell 里调用
另一个 AI CLI;所有腿也读得到宿主机上的其他文件(包括同伴日志)。这两条只有提示词约束 + 事后日志审计,
不是阻断。任务书不写 run 目录路径。

## Key trade-offs / risks

- **每项一个 panel-review 进程**:每项有自己的 run_id(不是一个逻辑 run 的多条腿)。切片结果本来就不进覆盖计数,
  run 级身份由 `plan.json` 的 run_id 串起来。多几个控制器进程,换来零重复的派发/终态代码。
- **探针与派发之间健康可能变**:被选中的腿恰好进了冷却 ⇒ 该项 `not_dispatched`,额度已占。宁可多占不少记。
- **提示词级隔离**(见上表敞口)。
- **契约 2 让 health.tsv 记 INELIGIBLE**:不冷却不判死,只是诊断字样。**health.tsv 是两种模式共享的账**:
  一次 scoped 成功会把该腿的连败清零(评审发现 I)。方向与一次普通成功相同 —— 腿进程确实跑完并给出了裁决,
  而且 scoped 关掉了聊天腿回落,证据只强不弱;但切片跑动会改变普通轮换看到的健康状态,这是有意的共享。
- **findings 由主 agent 登记**:不从模型自由文本里自动抽 finding(不可靠);代价是登记要手工,
  由「未登记的 BLOCK」这条 attention 兜住「看见 BLOCK 却不登记」。

## Alternatives considered

- **新写独立派发器(GPT 计划 P1 的「抽取共享会话执行逻辑」)**:要把 session_run/health 从 panel-review 挪进共享库,
  而 `tests/mutation-dead-leg-streak.sh` 等变异红检按字面锚在 panel-review 里 ⇒ 判卷防线要跟着大搬,
  收益只是少几个进程。没选。
- **把 GPT 加进普通轮换池**:见上表理由。没选。
- **只做「两条全量腿各有侧重」(对抗评审的最小替代)**:业主明确要的是「每个家族直接审一片」,
  且那种做法责任范围仍是全量,测不出切片本身的得失。没选,可作为以后对照组。
- **切片结果进 track 覆盖(新策略 sliced-v1)**:需要 P3 那套版本化任务身份 + P4 历史对照做依据,
  现在做就是「局部 PASS 冒充全量」。留后续单。

## Test strategy (oracle)

新判据 `tests/test-panel-slice.sh`(桩腿,无外网)+ `tests/test-subcodex.sh`(桩 codex,真 ro-repo-exec)
+ `tests/test_review_result.py` 增补。所有桩从 `_panel-roster-lib.sh` 两张表长出来,不抄腿名单;
桩的模型名从 `_review_result.py` 的 `ADAPTER_IDENTITIES` 前缀生成。

主干断言(完整清单在 tasks.md):
1. N 片 + overall ⇒ **恰好 N+1 次腿调用**,家族两两不同,overall 家族不在片里;每个桩启动那一刻 `plan.json` 与自己的 `reserved.json` 已在盘上。
2. 每项任务书只含自己那片的 brief 哨兵,不含别片哨兵,不含 run 目录路径;overall 含全部片标题。
3. 每份结果 `review_contract_version=2` 且 `eligible` 判否、理由含 review_contract_unsupported;fixture 仓的 typed track 下零 observation;普通轮换游标不动。
4. 家族凑不齐 / 不健康腿 / overall 与片同家族 / 清单非法 / my-review 缺失或在仓内 / run 目录在仓内 ⇒ 拒绝且零调用。
5. retry 与 verify 占 extra;超额整批拒绝、零调用、findings.jsonl 不变;复核腿家族不许等于出处家族。
6. 第 1 次尝试 BLOCK、第 2 次 PASS ⇒ run_state 不是 clean(BLOCK 未登记);登记 finding 并 decide rejected 后才 clean。
7. 源仓改过 ⇒ verify/retry 拒绝。
8. 控制器(panel-slice)被整组砍掉 ⇒ 立即 status 显示 unknown 不显示 failed;腿自己跑完后 status 重建为 done。
9. scoped 模式 agent 腿失败 ⇒ 不调用聊天腿(调用次数 = 1)。
10. panel-review:`--scoped-review --track` 拒绝;scoped 预算>0 不钉腿拒绝;普通 `--all` 不派角色腿、花名册不出现角色腿。
11. subcodex:argv 含单源模型 / `project_doc_max_bytes=0` / `--ignore-user-config` / `--ephemeral` / 禁 multi_agent;
    跑在 ro-repo-exec 里(桩试写源仓失败、写副本成功);无裁决 rc≠0;额度耗尽文本 ⇒ failure_kind=quota;fix 模式拒绝。
12. (09-14 评审后补)finding 出处必须点名一次尝试;同项两次 BLOCK 只登记第 2 次 ⇒ 第 1 次仍未登记、不 clean(S5/S10)。
13. (同上)unknown 尝试的 abandon:有活进程命令行引用就拒、无理由拒、非 unknown 拒;成功后额度照记、可 retry、
    事后落盘的结果优先(S11);默认并发下腿真的并行(S8)。
14. (同上)subcodex 检测器自检:目录声明子 agent 而不覆盖目录的基线渲染看不到 `<multi_agent_role>` ⇒ 拒跑;
    目录本来就不声明的模型不误拒(C6)。

每条判据先对当前 HEAD 红检(实现前必须红,且红在断言上不是红在语法/缺件崩溃上),判据单独 commit;
实现后跑 `tests/mutation-panel-slice.sh`:故意改坏关键谓词(契约版本回 1、放开家族互异、预算不查、
retry 覆盖旧 BLOCK、scoped 不关回落),每个变异必须打红点名的那条断言。

**这个 oracle 能被什么骗过?**

- 桩腿**永远乖**:真腿会在任务书之外乱读、在 shell 里调别的 AI CLI、偷看同伴日志 —— 判据一条都测不到。
  接住它靠:真跑一次后读各腿 stream/日志里的工具调用记录。
- 「家族互异」只证明**分配**互异,不证明各腿真的读了自己那片、真的审得更深。切片是否比全量审得好,
  这单**不回答**(GPT 计划 P4 的历史对照才回答)。汇报时不许说「切片评审更好」。
- run_state=clean 全绿,可能只是**主 agent 切片切错了** —— 所有片都在自己范围内正确、跨片时序缺陷没人审。
  overall 腿是唯一兜底;判据只能证明 overall 腿被派了、拿到了全部片标题,证明不了它真的兜住。
- subcodex 的桩只证明 argv 长这样。**这条 09-13 23:19 兑现了**:真跑发现 `--disable multi_agent` 对
  gpt-6-astra 无效、还带着联网工具,`--ignore-user-config` 也挡不住 `~/.codex/skills` 被列进提示。
  修法里子 agent 那件有派发前的真 codex 离线核验兜底;联网那件离线看不到工具表,换 codex 大版本要重跑真探针。
  仍敞着:skill 列表仍可见;每次 `codex exec` 往业主 `~/.codex/config.toml` 追加一条临时目录 trust 记录
  (09-14 核:config.toml 里恰好 4 条,对应 V2 三次 + V3 一次真跑,一次不差)。
  **不修的理由只排除了一种修法**(给 codex 复制一份凭证进独立 HOME ⇒ 刷新令牌轮换可能分叉,弄坏业主本机与 gateway 的登录)。
  评审发现 G 指出的更小候选**没评估过**:`CODEX_HOME=<私有目录>` + 私有 `auth.json` 软链到业主那份。
  它的风险也没排除:codex 若以「写临时文件再换名」的方式保存 auth.json,软链会被换成一份独立副本 —— 正是要避免的分叉;
  离线翻二进制字符串证明不了写法,要证明只能拿业主真登录做实验 ⇒ 不在本单,记后续单,动之前要业主点头。
- 预算计数的是 `reserved.json`;如果某条腿**自己**内部重试多次(adapter 层 429 backoff),那不在预算里
  —— 那是同一会话内的传输重试,计划里明确另算。

## 与 GPT 计划的差异

- GPT 计划 P1 要「必要时抽取共享会话执行逻辑」;本设计改为**整条复用 panel-review**,理由见上(变异锚点)。
- GPT 计划 P3 要版本化 task 身份并接入 track-record;本设计只做「数据上排除」(契约 2)+「流程上排除」(拒 --track),
  正式接入留后续单 —— 计划自己也写了「P1～P3 的实验运行始终不可贡献旧全量归档资格」。
- GPT 计划没有说 GPT 腿进不进普通池;本设计明确**不进**(角色腿表)。
- GPT 计划的 run_deadline / max_concurrency:本设计做 max_concurrency,不做整轮 deadline(单腿已有超时)。
- 新增 GPT 计划没写的:`decide` 追加式处置、「未登记的 BLOCK」、源码指纹闸、控制器被砍后的 unknown 语义。
