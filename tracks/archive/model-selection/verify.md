# Verify: model-selection

实现完成，独立评审进行中；最终裁决见 decision.json。

## 接手时核实的事实

- 原实现提交 4847497；判据先行提交 42e33fc。断线文档尚写待实施，按代码和原始收据重建状态。
- 接手补查：缺失调用事实会覆盖额度/认证/窗口限额原因。三种离线复现均先红；f34cfb5 保留真实失败原因，同家族跑错具体模型仍不计覆盖。
- 15 项候选选择、20 项结果契约、37 项流程与部署夹具检查通过；最终收据源码前后稳定。
- 原有双 Cursor 真实发散均 rc=0；精确 reported model 为 null，只证明请求/调用和家族一致。真实日志早于 no_verdict 归类修复，最终正常发散健康状态由离线端到端覆盖。
- 先前全量 runner 未全绿：基线已遗留 test-low-uncertainty-reason.sh 孤儿套件，且未引入无出口守卫。基线内容哈希及注册缺失见 evidence/orphan-baseline.txt。部署差异在候选隔离环境用规范部署夹具验证；本单不恢复已撤回旧闸。

## 运行记录与失败说明

- candidates-red / resume-candidates-red：未实现新入口，预期红。
- candidates-green rc=78：沙箱禁止无网络命名空间；宿主保留无出口隔离后通过。
- full-regression 第一遍：私有命名空间未启用 loopback，HTTP 夹具失败；修正后只余既有孤儿/no-egress 和未部署规范差异。
- focused-regression：选择、结果、observation、roster、slice 通过；文档断言尚未匹配修订，后续 final-check 已修正通过。
- final-check rc=65：命令 rc=0，但同时有回归进程写仓，source-stable=no，明确作废。
- resume-health-red：三类错误全部被错误写成 identity_mismatch。
- resume-candidates-green 第一遍仍红：测试自造 authentication failed 不属既有识别词；改用真实协议形状 401 Unauthorized，未扩张生产错误分类规则。
- resume-final-check：串行检查，rc=0、dirty=no、source-stable=yes。

```text
runlog: result-baseline rc=0 commit=e9fafc8 dirty=yes at=2026-09-20T15:10:06Z file=tracks/model-selection/evidence/20260920T151006Z-01-result-baseline.txt
runlog: candidates-red rc=1 commit=2d625b4 dirty=yes at=2026-09-20T15:14:48Z file=tracks/model-selection/evidence/20260920T151448Z-01-candidates-red.txt
runlog: resume-candidates-red rc=1 commit=2d625b4 dirty=yes at=2026-09-21T01:54:08Z file=tracks/model-selection/evidence/20260921T015408Z-01-resume-candidates-red.txt
runlog: candidates-green rc=78 commit=42e33fc dirty=yes at=2026-09-21T02:00:10Z file=tracks/model-selection/evidence/20260921T020010Z-01-candidates-green.txt
runlog: candidates-green rc=0 commit=42e33fc dirty=yes at=2026-09-21T02:08:09Z file=tracks/model-selection/evidence/20260921T020809Z-01-candidates-green.txt
runlog: full-regression rc=1 commit=42e33fc dirty=yes at=2026-09-21T02:28:19Z file=tracks/model-selection/evidence/20260921T022819Z-01-full-regression.txt
runlog: full-regression rc=1 commit=42e33fc dirty=yes at=2026-09-21T02:46:05Z file=tracks/model-selection/evidence/20260921T024605Z-01-full-regression.txt
runlog: focused-regression rc=1 commit=42e33fc dirty=yes at=2026-09-21T02:47:09Z file=tracks/model-selection/evidence/20260921T024709Z-01-focused-regression.txt
runlog: final-check rc=65 commit=4847497 dirty=yes final=yes at=2026-09-21T02:51:25Z file=tracks/model-selection/evidence/20260921T025125Z-01-final-check.txt
runlog: resume-health-red rc=1 commit=4847497 dirty=yes at=2026-09-21T06:58:04Z file=tracks/model-selection/evidence/20260921T065804Z-01-resume-health-red.txt
runlog: resume-candidates-green rc=1 commit=72b82f6 dirty=yes at=2026-09-21T06:58:27Z file=tracks/model-selection/evidence/20260921T065827Z-01-resume-candidates-green.txt
runlog: resume-candidates-green rc=0 commit=72b82f6 dirty=yes at=2026-09-21T06:58:56Z file=tracks/model-selection/evidence/20260921T065856Z-01-resume-candidates-green.txt
runlog: resume-final-check rc=0 commit=f34cfb5 dirty=no final=yes at=2026-09-21T06:59:28Z file=tracks/model-selection/evidence/20260921T065928Z-01-resume-final-check.txt
```

## 独立评审

- 第 1 轮：主仓旧调度器，MiMo(xiaomi)、DeepSeek(deepseek)、Cursor/Grok(xai)。原生 GLM/Grok/Gemini 已有鉴权或连续失败，Kimi 窗口限额，本轮显式关闭；无新增探活请求。
- 评审前自审保存在仓外；verify 在初审派发时仍为占位文本。任务禁止读 verify/self-review/其他报告。
- 日志前缀：/root/aiwork/logs/panel-model-selection-resume-r1-20260921。
- 预算最多 2 轮实质评审；基础设施重试另记。

## 处置

| 来源 | 发现 / 处置 | 依据 |
|---|---|---|
| Cursor #1 | 延期：GLM legacy chat 仍有 inline default。当前默认相等，显式成员禁止 chat fallback；本单新入口不受影响。未来调整 GLM 默认仍须同步 legacy chat 或显式 ZHIPU_MODEL；不声称全通道模型默认已唯一化。 | subchat:102；panel-review 显式 roster 的 chat 为空。 |
| Cursor #2 | 已知边界：保留，不伪造精确服务端身份。 | subcursor 的 invoked 记录 CLI 参数，reported=null；workflow 明确同样限制。 |
| Cursor #3a | 驳回缺少覆盖：测试分层位置不影响实际覆盖；不重复写同一断言。 | candidate E2E 直接 assert contract 3 PASS 不合格及 wrong-model 不合格。 |
| Cursor #3b | 已核实当前 CLI 输出：216 个已知家族精确 ID，GPT/Claude/GLM/Grok/Composer 等均被现行 first-token 解析识别。未来格式漂移是边界。 | logs/model-selection-resume-live-models.txt；只调用 models，不调用生成。 |
| Cursor #3c | 驳回必须断言诊断措辞：额度故障后同模型拒绝派发、另一模型可派已有行为断言。 | test_health_is_separate_for_cursor_models。 |
| Cursor #4 | 接受现有契约：env budget 也是显式预算，与 --members 冲突时拒绝；调用方 unset PANEL_REVIEW_BUDGET。暂无必须改写其优先级的需求。 | panel-review:104,153。 |
| Cursor #5 | 延期：全目录发现遇坏配置会整体拒绝。当前配置/发现可用；可用 --adapter 缩到需要的池。保留清晰错误，不推测不存在的候选。 | _panel_candidates.py main 的异常处理。 |
| MiMo #1/#2 | 延期：每项重读很小的 health 文件、错误文案细化。没有可复现的性能/正确性阻断。 | health_rows/describe。 |
| MiMo #3 | 驳回：explore usage 已有 [--members ID[,ID...]]，不是隐藏支持。 | panel-explore:25。 |
| MiMo 总结 | 文字 PASS，但最后为 Markdown 标题，现有严格解析得 UNKNOWN，不计归档覆盖。报告对 legacy 的“全部改动受 members 守卫”说法过宽；config 与结果 producer 的共享变化已由主 agent 独立验收。 | typed result + 原始 log；不手改裁决或 sidecar。 |
| DeepSeek | agent 超时，chat 回退无完整裁决；保留部分输入/排查为线索，不计覆盖。其 legacy 测试受继承 AIWORK_REVIEW_TRACK 污染后开始清环境复跑，未完成；主 agent 的无该变量回归已有记录。无最终具体存活 finding。 | agent.log、agent.log.err、log、log.err。 |

## 第 1 轮机器记录与重试决定

- 初审派发约 19 分 32 秒；Cursor 合格 PASS；MiMo rc=0 但 verdict=UNKNOWN；DeepSeek agent rc=124，chat rc=1。主控制器 rc=0 不代表 high 覆盖已满足，机械检查只认 1 家族。
- 源码零新增改动。基础设施重试一次：MiMo + Cursor/Composer，两家族同轮完整审查；禁止重复跑测试，末行明确要求裸裁决。用现有旧调度器，显式关闭 DeepSeek 等失败通道。最多这一次取证重试；若还不足，保持未完成，不放宽判卷规则。

```text
# panel-review 花名册(2026-09-21 15:22:05)task=model-selection-review
# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
# impact-risk=high requested-budget=7 selected-count=3
# selected=submimo(xiaomi/submimo),subdeepseek(deepseek/subdeepseek-agent),subcursor(xai/subcursor)
# escalation=none
# snapshot=head:a95cee4
# 日志:/root/aiwork/logs/panel-model-selection-resume-r1-20260921.*.log
submimo=PASS(verdict=UNKNOWN) subdeepseek=FAIL(rc=1,降级:回落聊天腿也没成) subglm=off subkimi=off subgemini=off subgrok=off subcursor=PASS(verdict=PASS)
```

## 2026-09-22 接续与合并验收

- 6028c98 合入主仓 1ddd7a4。MiMo 2.6 Pro 与 Cursor Grok 4.7 默认值保留；MiMo 包装器采用今日主仓原样实现，新目录与包装器读取同一个模型文件。
- 合并后串行检查：候选 15、结果 20、适配器 17、评审工具 562、工作区隔离 31、规范部署 37，全部通过；最终收据 source-stable=yes。最初沙箱不允许 unshare，失败收据保留；宿主保留断网与隔离后重跑通过。
- 主 agent 重新审过选择、冻结参数、结果身份、发散不可计覆盖、健康隔离和合并冲突；未发现新增阻断。自审原文在仓外 model-selection-sep22.md，先于本轮报告。
- 第 2 轮实质评审：源内容因合并今日默认值变化，按完整增量重新审查。使用主仓旧调度器避免新实现自证；选 MiMo 2.6 Pro 与 Cursor/Composer 2.5，两种家族、两个通道。保留昨天其他通道失败证据，不为补覆盖反复探活。昨天准备的覆盖重试未实际派出，本次为接续后的第二轮。

```text
runlog: sep22-merged-check rc=1 commit=6028c98 dirty=no final=yes at=2026-09-22T01:21:42Z file=tracks/model-selection/evidence/20260922T012142Z-01-sep22-merged-check.txt
runlog: sep22-merged-check rc=0 commit=6028c98 dirty=yes final=yes at=2026-09-22T01:23:03Z file=tracks/model-selection/evidence/20260922T012303Z-01-sep22-merged-check.txt
```

## 2026-09-22 Claude 接手(GPT 09:41 额度用光,停在第 2 轮等 MiMo)

对我来说 GPT 是执行腿,它的自述与自审不作数;本单判据也是它写的,所以补偿控制是
我亲跑全量 + 基线对照 + 变异测试,不读它的汇总。自审原文在仓外
`/root/panel-my-reviews/model-selection-claude-takeover.md`,写于派重试之前(读过第 2 轮
Composer 报告与 MiMo 半截日志,两份都无具体发现,已在自审里交代)。

- 全量总跑 31 套(断网 + 私有挂载):唯一的红是孤儿套件 `test-low-uncertainty-reason.sh`
  及其缺断网守卫的 no-egress N3a/N3c;**在基线 003563c 上红得一模一样** ⇒ 本单零新增失败。
  这个孤儿是 09-19 我自己那单 revert 后留下的判据,不在本单范围。
- 变异 19 个:15 个被咬住(红在对的用例上);存活 4 个(M6/M7/M16/M18)逐个核过都有第二道挡,
  是「挡不住任意未来错误实现」,延期。明细在自审里。

```text
runlog: claude-takeover-full rc=1 commit=1a68bf1 dirty=yes final=yes at=2026-09-22T02:09:21Z file=tracks/model-selection/evidence/20260922T020921Z-01-claude-takeover-full.txt
runlog: baseline-orphan-same-red rc=0 commit=1a68bf1 dirty=yes at=2026-09-22T02:19:37Z file=tracks/model-selection/evidence/20260922T021937Z-01-baseline-orphan-same-red.txt
runlog: shared-health-oracle-red rc=1 commit=1a68bf1 dirty=yes at=2026-09-22T02:45:25Z file=tracks/model-selection/evidence/20260922T024525Z-01-shared-health-oracle-red.txt
runlog: shared-health-full rc=143 commit=0e6b8ae dirty=yes final=yes at=2026-09-22T02:47:03Z file=tracks/model-selection/evidence/20260922T024703Z-01-shared-health-full.txt
```

- `claude-takeover-full rc=1`:红只在上面那个基线同款孤儿上,见基线对照那份。
- `baseline-orphan-same-red rc=0`:脚本末条是 echo;实际内容是基线上 coverage-only rc=1、no-egress 16/2。
- `shared-health-oracle-red rc=1`:新判据先行、按预期红,16 条里只红新加的那条(红在「旧入口撞额度后显式成员没被拦」)。
- `shared-health-full rc=143`:**我主动中断的**,不算数 —— 跑到一半想起 transport_history 失去写入方,
  要先删掉它再跑最终那遍(否则那遍审的不是最终内容)。

### 轮次记录(接续)

| 轮 | 类型 | 派发前 `track preflight` | 日志前缀 | 新增有效阻断 |
|---|---|---|---|---|
| 2 | 基础设施重试(MiMo 上次 GPT 把时限压到 600s 被砍;本次 1500s) | BLOCK=0 PENDING=2 | `/root/aiwork/logs/panel-model-selection-sep22-r2retry` | 1(Grok F1) |

```text
submimo=PASS(verdict=PASS) subdeepseek=off subglm=off subkimi=PASS(verdict=PASS) subgemini=off subgrok=off subcursor=PASS(verdict=BLOCK)
```

三家都 coverage-eligible,但 PASS/BLOCK 冲突 ⇒ 这一轮不能满足归档。选腿:业主要求加 MiMo 2.6 Pro;
另选 Kimi 与 Cursor/Grok 4.7(能读仓、最近成功过);不选 GPT 家族(作者)与 Claude 家族(主裁)。
用主仓旧调度器派发,不用候选的新入口给自己打分。

### 第 2 轮重试的发现与处置

| # | 发现:触发条件与影响 | 核实证据 | 处置 | 理由 |
|---|---|---|---|---|
| G1 | Grok(High):旧轮换把 Cursor 失败记在 `subcursor`、显式成员记在 `subcursor.<model>`,同一模型一边撞额度另一边照派;`--members subcursor` 是旧入口别名却不看旧入口冷却 | 已核 `panel-review` recent_health/dead_health/record_health 都按腿名取行;我写判据复现两个方向都红(`shared-health-oracle-red`) | **本单必须修** → `f6aa79a` 判据 / `0e6b8ae` 修 / `537b438` 清理 | 本单文档自己承诺「冷却中的成员会在调用前拒绝」;Cursor 掉登录这类整账号故障会让每个模型各白打一次,连败停用机制当初正是为治这个。修法按根因:同一件事只留一个键 `subcursor.<本轮模型>`,不整通道冷却(判据对照组钉住) |
| K1 | Kimi(Low):同 G1,另提 `PANEL_HEALTH_OVERRIDE=subcursor=healthy` 够不着显式成员 | 已核 override 按腿名精确匹配 | 同模型部分随 G1 修;override 按成员名 **驳回** | 显式成员就用 `subcursor.<model>=healthy`,文档写着;按通道一键放回会把不同模型一起放回,违背「各模型各自冷却」 |
| K2 | Kimi(Low):没有 GLM 显式成员的端到端;`go/` 前缀在 CAPABILITIES 与 subagent OC_PROVIDER 两处各写一份,今天一致 | 已核 `_panel_candidates.py:21` 与 `subagent` OC_PROVIDER="go";我自审第 4 条同一处 | 延期 | 会长成:以后有人改 GLM 的 opencode provider 前缀而没改目录,显式选 GLM 的评审会一直被判 INELIGIBLE(花名册上看得见),方向是漏计不是误计 |
| M1 | MiMo:PASS,无具体发现 | — | — | — |
| 清理 | 修完 G1 后 `transport_history` 失去写入方,会永远显示一条过期记录 | 修复后全仓只剩它读无模型 `subcursor` 行 | 已删(`537b438`) | 没人维护的字段伪装成有内容,是当年「当前状态」字段永久摆设的同一种病 |

### 追加一轮(派发前写明)

- 具体阻断:G1(已修)。旧的两轮实质评审 + 本次重试都审的是修复之前的内容,且重试有冲突,归档条件不可能满足。
- 追加目的:核验 G1 修复及其影响面(旧入口健康/冷却/连败的原有判据),并在无冲突的同一轮拿到 ≥2 家族覆盖。
- 新的有限预算:**只加 1 轮实质评审**(即第 3 轮)。仍用 MiMo + Kimi + Cursor/Grok,用主仓旧调度器。
  这一轮若再出「本单必须修」:停下,本单保持未完成,向业主报告,不再续轮。基础设施重试照记。

第 3 轮派发前,最终内容(537b438)全量总跑:红只在基线同款孤儿上,其余 30 套全绿(含旧入口健康/冷却/连败的 V44 系列),source-stable=yes。

```text
runlog: shared-health-final rc=1 commit=537b438 dirty=yes final=yes at=2026-09-22T02:49:43Z file=tracks/model-selection/evidence/20260922T024943Z-01-shared-health-final.txt
```

### 第 3 轮(实质,追加的最后一轮)

| 轮 | 类型 | 派发前 `track preflight` | 日志前缀 | 新增有效阻断 |
|---|---|---|---|---|
| 3 | 实质(核验 G1 修复 + 全量 delta) | BLOCK=0 PENDING=1 | `/root/aiwork/logs/panel-model-selection-r3` | 0 |

```text
submimo=FAIL(rc=124) subdeepseek=off subglm=off subkimi=PASS(verdict=PASS) subgemini=off subgrok=off subcursor=PASS(verdict=PASS)
```

| # | 发现:触发条件与影响 | 核实证据 | 处置 | 理由 |
|---|---|---|---|---|
| R3-Grok | 逐处确认 health_key 接进四处读、一处写;override 仍按腿名;scoped 与 --all 同键;新判据两个方向 + 对照组都在;无缺陷 | 与我自审第 3 轮补充一致 | — | — |
| R3-K1 | Kimi(nit):修复前留下的无模型 `subcursor` 行永远留在 health.tsv 里 | 已核:修复后全仓无读者 | 延期 | 会长成:业主翻 `logs/.panel-state/health.tsv` 时看到一条永不更新的 subcursor 行,纯噪音;那是仓外运行状态,不值得为它写迁移 |
| R3-K2 | Kimi(nit):cursor-model 缺失且 CURSOR_MODEL 未设时键退化成 `subcursor.` | 已核 `subcursor:40` 此时直接 die('cannot read bin/cursor-model'),roster 家族记 unknown | 驳回 | 那种状态下 Cursor 腿本来就跑不起来,退化键只记下这次失败,不影响别的模型 |
| R3-K3 | Kimi(note):MiMo 运行时登记离线验证不了 | 今天 MiMo 真跑 3 次,typed result 的 invoked 都是 `xiaomi/mimo-v2.6-pro`,重试轮交了完整报告 | 驳回(已有线上实证) | 离线判据只管「submimo 传没传、只含 provider 段」,「CLI 认不认」由真跑回答,今天回答了 3 次 |
| R3-MiMo | 1501s 超时,无报告 | 半截日志:只写了开头一句,29 条命令全在查修复相关的读写点,无任何疑点 | 不计覆盖;不补派(业主定) | 慢不是坏:平均近 1 分钟一步。以后派 MiMo 2.6 Pro 审大单,时限给 35 分钟或拆小题面 |

## 主裁(Claude,2026-09-22)

**PASS。**

- 目标达成:主裁可用 `panel-candidates` 看候选,`--members` 点名派发,同一轮可放多个 Cursor 模型;
  显式名单不轮换、不偷换、不回落;发散结果永不计评审覆盖;花名册断线可按冻结名单重建。
- 证据链不依赖执行腿自述:我亲跑的最终全量(537b438)只红基线同款孤儿;19 个变异 15 个咬住、4 个核过有第二道挡;
  G1 由我写判据先红后修。
- 覆盖:第 3 轮同一次 panel、同一 subject,Kimi(moonshot)+ Grok 4.7(xai)两家合格 PASS、无冲突;
  预算 2 轮 + 声明过的追加 1 轮,用完即止。
- 留下的边界(都已在上面各表写明):一个 Cursor 账号可单独凑满两个家族(外壳同一套,主裁选人时自己权衡);
  K2 GLM 前缀两处各写一份;变异存活的 4 条与「原生成员失败不回落聊天腿」无专门用例。都是延期,不自动开新单。
- 没有做到/不承诺:孤儿套件 `test-low-uncertainty-reason.sh` 仍红(09-19 那单的遗留,不在本单范围)。
