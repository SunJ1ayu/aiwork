# Verify: sliced-panel-review

- Date: 2026-09-13

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再按 impact-risk 预算跑 panel-review；只有特殊控制面
> 才显式 `--all` 做全池评审。最后仍由主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes(bash -n / python 语法随判据跑)
- [x] tests pass:全量离线总闸 25 套件全绿(最后一次改代码之后跑的,见最后一行收据)
- [x] no secrets / unsafe ops:runlog 前后扫秘密形状;判据断网跑;真跑只在仓外一次性小仓

**机器打印的**(逐字节,红的一份不藏):

```
runlog: redcheck-review-result rc=1 commit=eaaea75 dirty=yes at=2026-09-13T14:22:36Z file=tracks/sliced-panel-review/evidence/20260913T142236Z-01-redcheck-review-result.txt
runlog: redcheck-subcodex rc=1 commit=eaaea75 dirty=yes at=2026-09-13T14:22:37Z file=tracks/sliced-panel-review/evidence/20260913T142237Z-01-redcheck-subcodex.txt
runlog: redcheck-subcodex rc=1 commit=eaaea75 dirty=yes at=2026-09-13T14:25:03Z file=tracks/sliced-panel-review/evidence/20260913T142503Z-01-redcheck-subcodex.txt
runlog: redcheck-panel-slice rc=1 commit=eaaea75 dirty=yes at=2026-09-13T14:25:03Z file=tracks/sliced-panel-review/evidence/20260913T142503Z-02-redcheck-panel-slice.txt
runlog: redcheck-panel-slice rc=1 commit=eaaea75 dirty=yes at=2026-09-13T14:26:09Z file=tracks/sliced-panel-review/evidence/20260913T142609Z-01-redcheck-panel-slice.txt
runlog: redcheck-subcodex-catalog rc=1 commit=74f39d5 dirty=yes at=2026-09-13T15:31:52Z file=tracks/sliced-panel-review/evidence/20260913T153152Z-01-redcheck-subcodex-catalog.txt
runlog: mutation-panel-slice rc=1 commit=60480ee dirty=yes at=2026-09-13T15:35:33Z file=tracks/sliced-panel-review/evidence/20260913T153533Z-01-mutation-panel-slice.txt
runlog: mutation-panel-slice rc=0 commit=eca7b4a dirty=yes at=2026-09-13T15:52:31Z file=tracks/sliced-panel-review/evidence/20260913T155231Z-01-mutation-panel-slice.txt
runlog: full-regression rc=0 commit=eca7b4a dirty=yes at=2026-09-13T16:07:37Z file=tracks/sliced-panel-review/evidence/20260913T160737Z-01-full-regression.txt
runlog: redcheck-round2-subcodex rc=1 commit=c7a5e31 dirty=yes at=2026-09-13T16:37:27Z file=tracks/sliced-panel-review/evidence/20260913T163727Z-01-redcheck-round2-subcodex.txt
runlog: redcheck-round2-panel-slice rc=1 commit=c7a5e31 dirty=yes at=2026-09-13T16:37:33Z file=tracks/sliced-panel-review/evidence/20260913T163733Z-01-redcheck-round2-panel-slice.txt
runlog: redcheck-round2-panel-slice-fixture rc=1 commit=bfac8cc dirty=yes at=2026-09-13T16:42:20Z file=tracks/sliced-panel-review/evidence/20260913T164220Z-01-redcheck-round2-panel-slice-fixture.txt
runlog: round2-fix-panel-slice rc=0 commit=8844c9b dirty=yes at=2026-09-14T01:28:03Z file=tracks/sliced-panel-review/evidence/20260914T012803Z-01-round2-fix-panel-slice.txt
runlog: round2-fix-subcodex rc=0 commit=8844c9b dirty=yes at=2026-09-14T01:28:53Z file=tracks/sliced-panel-review/evidence/20260914T012853Z-01-round2-fix-subcodex.txt
runlog: round2-fix-review-result rc=0 commit=8844c9b dirty=yes at=2026-09-14T01:28:59Z file=tracks/sliced-panel-review/evidence/20260914T012859Z-01-round2-fix-review-result.txt
runlog: round2-mutation-panel-slice rc=1 commit=9c980fb dirty=no at=2026-09-14T01:29:33Z file=tracks/sliced-panel-review/evidence/20260914T012933Z-01-round2-mutation-panel-slice.txt
runlog: round2-mutation-panel-slice-rerun rc=0 commit=0cc6c66 dirty=no at=2026-09-14T02:05:36Z file=tracks/sliced-panel-review/evidence/20260914T020536Z-01-round2-mutation-panel-slice-rerun.txt
runlog: round2-full-regression rc=0 commit=0cc6c66 dirty=yes at=2026-09-14T02:41:26Z file=tracks/sliced-panel-review/evidence/20260914T024126Z-01-round2-full-regression.txt
```

每份红收据是什么:
- 前五份:判据先行对 base `eaaea75` 红检(review-result 2 红;subcodex 30 红 1 绿;panel-slice 两轮,
  第二轮收紧了「零调用拒绝」要求 `REFUSED <rule>` 标记 —— 二进制不存在时 rc≠0 且零调用会空转成绿)。判据 commit `74f39d5`。
- `redcheck-subcodex-catalog rc=1`:V2 真跑证伪 `--disable multi_agent` 后补的 C5,对第一版实现红 5 条 / 绿 32。
  同一份判据对仓外候选修复 37/0。判据 commit `60480ee`。
- `mutation-panel-slice rc=1`(咬住 30 / 漏网 1):漏网的 M4 报「靶子名不在基线里」,**实际在**。
  量具自己的毛病:pipefail 下 `grep PASS | grep -qF` 吃 SIGPIPE,200 次随机漏 2~3 次(关 pipefail 0/200)。
  改成单条 grep 后 300 次零漏零误中,单独 commit `eca7b4a`,第二轮 31/0。
  **同一写法还在** mutation-dead-leg-streak / mutation-panel-roster / mutation-subgemini 里(方向都是误报漏网,不会假绿),不在本单修。

第二轮(第一轮评审 A~I 之后)的红收据是什么:
- `redcheck-round2-subcodex rc=1` / `redcheck-round2-panel-slice rc=1`:A/D/E/F 的判据先行,对 `c7a5e31` 红在新断言上;判据 commit `bfac8cc`。
- `redcheck-round2-panel-slice-fixture rc=1`:S11 占位进程被 bash exec 成 `sleep 30`、命令行里没有尝试路径 ⇒ 夹具前提断言自己红;
  改成 `bash -c 'sleep 30; :' _ "$att/panel"` 单独 commit `8844c9b`。
- `round2-mutation-panel-slice rc=1`(咬住 34 / 漏网 3):C11 是**真判据缺口**(E 修复加的 `next(...)` 在模型缺席时自己崩,
  盖住了「恰好一次」计数 ⇒ 删计数全绿),补 C5「出现两次 ⇒ 拒跑」;M11/M12 是锚点过期。`0cc6c66`,重跑 37/0。
- 最后一份 `round2-full-regression rc=0` 跑在 `0cc6c66`,**那是最后一次改代码的提交**;之后 `e5ea7e9`/`42168d1`/`0762d47`
  只动了 `tasks/`、`observations/` 和两份 runlog 收据(`e5ea7e9` 入库的变异重跑与总闸收据),`bin/`/`tests/` 零改动。`dirty=yes` 是当时还没入库的变异收据与 observation(`e5ea7e9` 才提交),`bin/` 已还原。

真跑(不是 runlog 收据,原始报告与事件流入库):
- V2 subcodex 三次:`evidence/v2-live-subcodex/`(README 里有表)。第一版不合格(子 agent 工具 + web__run 在),
  修后两次各去掉一个开关做归因。仓内修复与验证过的副本逐行一致(注释行除外,只差一句报错文案)。

- V3 切片评审机制真跑(09-14 00:15,原始记录 `evidence/v3-live-slice/`):一次性练习仓,改动里埋了
  片内缺陷(`store.py` 用 `"w"` 截断)和跨片契约错位(写 `ts` 字符串 / 读 `timestamp` 转 int)。
  - 分配:store→submimo(xiaomi)、report→subdeepseek(deepseek)、overall→subcodex(openai),家族两两不同;
    每项花名册 `selected-count=1`、`escalation=none`、`coverage=INELIGIBLE`,其余腿 off。
  - 三份结果 `review_contract_version=2`,不合格理由**只有** `review_contract_unsupported` ⇒ 状态 done 名副其实;
    普通轮换游标 mtime 仍是 09-11 15:52(没被推);health.tsv 三条腿记 INELIGIBLE、连败 0。
    **这两句是当时看本机活状态(`logs/.panel-state/`,被 .gitignore 忽略)得来的,仓里没有副本、事后复核不了**;
    它们要支撑的「契约 2 不推游标、记 INELIGIBLE」由判据 S1/S9 的收据承重。
  - 腿内工具:subdeepseek 只用了 Bash×5 / Read×3;subcodex 事件只有 command_execution 与 agent_message;
    submimo 日志无子 agent / 联网调用。**这只说明这一轮没用,不说明腿做不到**(除 subcodex 已机械关掉)。
  - 三条腿都报出了两处埋的缺陷(练习仓太小,**不能**据此说切片评审更好)。
  - verify:登记 F1~F3,复核 F3(出处 deepseek)⇒ 自动派给 submimo(xiaomi),任务书只写出处切片、不写腿名;
    复核腿自己跑复现后判 CONFIRMED。extra 1/1。
  - extra 用完后 `retry store` ⇒ `REFUSED budget` rc=3,reserved.json 仍 4 份、没有 attempt-2;
    `decide` 未登记的 F9 ⇒ 拒绝;F1~F3 记 accepted-risk(理由:练习仓故意埋的)后 run_state=clean、problems 空。
  - 合计会话 = 3 初始 + 1 复核 = 4 = reserved.json 份数。

## Review

- 规格自查(读任何 panel 输出之前先答,全文在仓外 `/root/aiwork-my-reviews/sliced-panel-review-review-my-review.md`
  与 `…-round2-my-review.md`):
  1. 「腿内不许派子 agent」逐腿核实表是读代码推出来的,只有 subcodex 真跑过 —— 而它真跑后当场证伪(F1,已修)。
     其余腿的表项仍是读出来的,V3 真跑只说明**那一轮没用**,不说明做不到。
  2. 「一个工作项 = 一次会话」数的是 `reserved.json`;腿 adapter 内部的 429 重试不在里面(设计已写明)。
  3. 本单**不回答**「切片评审更好」;V3 三条腿都报出埋的缺陷只因练习仓太小。
  4. 第二轮最该怀疑的是我第一轮自审的定级:A(我的 F3,定 low)、D(我的 F6,定 info)被评审腿按「run_state=clean
     会被当门禁」升到中 —— 实现不合 design 第 83 行「任一尝试」,我把「不合规格」写成了「可接受的取舍」。
- 腿的花名册(原样粘自 `.roster`):
  - 第一轮 `panel-sliced-panel-review-review-20260914-002213`(审 `c7a5e31`):
    `submimo=PASS(verdict=PASS) subdeepseek=PASS(verdict=PASS) subglm=SKIP(health:dead:FAIL:3) subkimi=SKIP(health:dead:FAIL:3) subgemini=SKIP(health:dead:FAIL:6)`
  - 第二轮第 1 次 `panel-sliced-panel-review-round2-review-20260914-104926`(审 `e5ea7e9`,**作废**):
    `submimo=FAIL(rc=124) subdeepseek=FAIL(rc=1,降级:回落聊天腿也没成) subglm=SKIP(health:dead:FAIL:3) subkimi=SKIP(health:dead:FAIL:3) subgemini=SKIP(health:dead:FAIL:6)`
  - 第二轮第 2 次 `panel-sliced-panel-review-round2-review-20260914-114834`(审 `42168d1`,**作废**):
    `submimo=FAIL(rc=124) subdeepseek=PASS(verdict=PASS,降级:回落聊天腿,只看得见 diff) subglm=SKIP(health:dead:FAIL:3) subkimi=SKIP(health:dead:FAIL:3) subgemini=SKIP(health:dead:FAIL:6)`
  - 第二轮第 3 次 `panel-sliced-panel-review-round2-review-20260914-121829`(审 `0762d47`,**本单取证轮**):
    `submimo=PASS(verdict=PASS) subdeepseek=PASS(verdict=PASS) subglm=SKIP(health:dead:FAIL:3) subkimi=SKIP(health:dead:FAIL:3) subgemini=SKIP(health:dead:FAIL:6)`
  > 前两次为什么零有效腿(查的是底座自己的会话库,不是腿日志尾巴):DeepSeek 第 1 次 `402 Insufficient Balance`(业主已充值);
  > 小米两次都死在 `bash tests/mutation-panel-slice.sh` 上(MiMoCode 会话库里该工具调用停在 running,工具等待自设 600s/2400s,
  > 腿墙钟 900s/1500s)—— 任务书红字写了不要跑,但 Q4 同时问「变异咬不咬得住」,**题面自相矛盾**;
  > DeepSeek 第 2 次事件流停在「now let me write the final review」时到 900s。`0762d47` 只改 Q4 的验法与时限说明,五个问题不变。
  > 健康池只剩这两家(glm/kimi/gemini 连败停轮换),两次重派都用了 `PANEL_HEALTH_OVERRIDE` 放回冷却中的这两条腿。
- findings:
  - 第一轮(subdeepseek A~I;submimo 无阻断发现):A/D/E 修(判据先行 `bfac8cc`,修复 `8dd49d7`),F 补判据(S8 并行 + M21),
    B 改帮助/设计文案,G 如实写「CODEX_HOME 软链没评估过」只记账,H 驳回(质疑的是「每次追加 trust」没证据 ——
    `~/.codex/config.toml` 恰好 4 条 = 4 次真跑),I 设计点名 health.tsv 共享。
  - 第二轮取证轮 submimo:无发现;亲手做了 M23/C11/C12 三处单点变异,都红在点名断言上。
  - 第二轮取证轮 subdeepseek(五条,逐条对代码核过):
    1. [low] launch 子 shell 在 reserve→exec 之间命令行不带尝试目录 ⇒ abandon 理论上能放弃仍会跑完的尝试。
       **= 我的 R1**,docstring 已写;晚到的结果仍优先(`classify_attempt` 结果判在 abandoned 之前)。接受。
    2. [low] `cmd_verify`/`cmd_retry` 对解析不出的 source 静默跳过家族排除(`bin/_panel_slice.py:933`、`:1004` 核实属实)。
       新账本入口已拒绝这种写法(除 `main`),只有改格式前的旧账会走到。**成立,记后续**:改成非 `main` 且解析不出就拒。
       不在本单修:切片结果契约 2 不进任何归档覆盖,且改源码要重派整轮 high。
    3. [info] source 指向别项的已存在尝试即可通过 ⇒ 可绕开该项家族排除。source 由主 agent 写,是受信输入。接受。
    4. [low] 「H 的证据不证明增长有界,驳回措辞过强」。**驳回**:H 质疑的是「每次追加」这句话有没有证据,不是增长是否有界;
       「每次追加、不回收」本来就在 `design.md:191` 的「仍敞着」和 `legs.md` 里。
    5. [info] subcodex 目录字段名 + 渲染标记名同时改的盲区。**= 我的 R4**,注释已写。接受。
  - 我自己第二轮的 R3(读不了的 `/proc/*/cmdline` 跳过)、R6(retry 执行时不提示在重派已完成项)两腿没有反驳,维持 low、记账。
- arbitrated verdict (主裁): 通过。取证轮两个不同家族(xiaomi / deepseek)都给出非降级 PASS、无 BLOCK/NMI、与我两轮自审无冲突;
  第一轮三条中危按判据先行修掉且有红收据与 37/0 变异;第二轮新发现里唯一成立的是只影响旧账本的 low。
  **这不证明规格对**:切片评审是否更好本单不回答,逐腿「不派子 agent」除 subcodex 外仍是读出来的。

- 归档前增量评审(证据寿命闸要求给三行临时路径标 `[仓外不承重]`,证据属交付内容 ⇒ 重审):
  `panel-sliced-panel-review-archive-delta-review-20260914-123815`(审 `0eb7254`,题面只问 `0762d47..HEAD` 的范围与三处标记):
  `submimo=PASS(verdict=PASS) subdeepseek=PASS(verdict=PASS) subglm=SKIP(health:dead:FAIL:3) subkimi=SKIP(health:dead:FAIL:3) subgemini=SKIP(health:dead:FAIL:6)`
  - 两腿都指出范围里多一份 `tasks/sliced-panel-review-archive-delta-review.md`(题面本身,我在题里漏列了)。接受。
  - subdeepseek [low] 本文件「之后三个提交只动了 tasks/ 与 observations/」漏了 `e5ea7e9` 入库的两份收据 —— 核实属实,已改。
  - subdeepseek [low] V3 那两句游标/health.tsv 的事实仓里无副本 —— 属实,已在该处写明是活状态观察、由 S1/S9 收据承重。
  - 两腿都核了三处标记不承重(V3 run 目录内容已全量入库;trust 记录的四个工作区名在仓内日志里可复算;探针路径无结论引用)。
  - 仲裁:增量不改变任何承重结论,维持通过。**这次重审是我造成的**:派取证轮之前没把 `track archive` 预跑一遍,
    证据寿命闸排在交付绑定之后、派发前就能跑到。

## Accepted deviations

- 后续欠账(不阻断本单):verify/retry 对非 `main` 且解析不出的 source 应当拒绝而非静默跳过家族排除;
  retry 重派已完成项时执行期不提示;`processes_referencing` 跳过读不了的 cmdline(单用户 root 下无碍);
  subcodex 仍可见 `~/.codex/skills`、每次 `codex exec` 往业主 config.toml 追加 trust 记录(独立 HOME 会分叉刷新令牌,未评估)。
- 评审流程上的欠账(另开修腿单):腿墙钟把「在跑长命令 / 正在写报告」和「卡死」混为一谈,本单两次零有效腿都死在墙钟上;
  底座腿单条工具命令的等待上限可以超过腿墙钟。
