# Verify: workflow-observability

- Date: 2026-08-21

> 机器消费的 impact / uncertainty / execution plan / outcome 只认同目录的
> `decision.json`；这里不复制第二份枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再跑 panel-review 的全部评审腿,主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes
- [x] tests pass
- [x] no secrets / unsafe ops

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t workflow-observability -- <判据命令>
```

```
runlog: track-record-red rc=1 commit=ca6166f dirty=no at=2026-08-21T11:42:04Z file=tracks/workflow-observability/evidence/20260821T114204Z-01-track-record-red.txt
runlog: review-tooling-final rc=1 commit=7578a3c dirty=no final=yes at=2026-08-21T12:59:21Z file=tracks/workflow-observability/evidence/20260821T125921Z-01-review-tooling-final.txt
runlog: review-tooling-final-r2 rc=0 commit=4fd811d dirty=no final=yes at=2026-08-21T13:09:46Z file=tracks/workflow-observability/evidence/20260821T130946Z-01-review-tooling-final-r2.txt
runlog: review-tooling-final-r3 rc=0 commit=d112347 dirty=no final=yes at=2026-08-21T13:59:27Z file=tracks/workflow-observability/evidence/20260821T135927Z-01-review-tooling-final-r3.txt
runlog: review-tooling-final-r4 rc=0 commit=0c33338 dirty=no final=yes at=2026-08-21T14:05:56Z file=tracks/workflow-observability/evidence/20260821T140556Z-01-review-tooling-final-r4.txt
```

- `track-record-red` 是实现前的预期 TDD 红，目标断言随后转绿并进入 71/71。
- `review-tooling-final rc=1` 是受限沙箱无法创建 network namespace / 访问本地测试桩的环境红；
  在判据自身 no-egress 的允许环境中重跑 r2/r3/r4 均为绿色，最后以 r4 为准。

## Review

- 规格自查(读任何 panel 输出之前先答):规格最可能错在把“执行现场清理”与“持久账本清理”
  混成同一保留策略，或只在 panel 入口检查 0/1/2 预算却没有在 PASS 生命周期边界复核。
  我用真 archive+sweep 前后 ledger 同值判据发现前者，用 high+runlog-only 反例与变异/攻击复核
  发现后者；因此最终规则由 archive 与 ledger 同时从 compact observations 机械核对。
- 腿的花名册:
  `submimo=PASS(verdict=UNKNOWN) subdeepseek=PASS(verdict=UNKNOWN) subglm=FAIL(rc=1,降级:回落聊天腿也没成) subkimi=SKIP(rotation)`
  `submimo=SKIP(health:cooldown:INCOMPLETE) subdeepseek=SKIP(health:cooldown:INCOMPLETE) subglm=SKIP(health:cooldown:FAIL) subkimi=FAIL(rc=1)`
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - 主自审与 sub-Codex 两阶段攻击命中的 staged/working 混用、typed→legacy 降级、手工归档、
    active/archive 同名、secret 回显、事件大小、重复计费、fallback 少计、NaN/Infinity、主仓归属
    等绕过均已转成回归；sub-Codex 对最终窄 diff 给 `FINAL PASS`，相关 112/112 全绿。
  - MiMo 报告结论 PASS；DeepSeek 报告结论 BLOCK，复现 high track 只靠 runlog 也能归档。
    主裁接受该 finding，在 `b9897d0` 增加 archive/ledger 的 distinct-family 预算闸。
  - sub-Codex 随后复现“成功一家 + 失败一家”可拼预算，主裁再次接受，在 `d112347` 改为
    只从成功 panel events 汇总家族，并新增精确反例。最终全量 runner 所有套件 0 fail。
  - GLM agent→chat 与窄复核 Kimi 均失败；它们不是 PASS，也未被主裁当成判断材料。失败、降级
    与真实 dispatch 已进入 compact observations，原始原因保留在仓外 panel logs。
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): PASS。外部 BLOCK 的可复现缺陷及 sub-Codex 的二阶绕过都已修复并
  重新验证；最终源码身份 `0c33338` 的全量机器收据为 rc=0/dirty=no/final=yes，且 archive
  预算、执行覆盖、事件白名单和 worktree sweep 生命周期判据全部通过。
  > **归档时这一条和 `decision.json.outcome.verdict` 都不许还是占位符**,`track-guard` 会挡;
  > 没归档但已经合并上线的,`track list` 会打 ⚠️(stage-timer 就这么漏了两个月)。

## Accepted deviations

- 订阅模型拿不到可靠 token/API 现金成本时继续记 `null/unknown`，不估算、不补 0；这会降低
  成本横比覆盖率，但不会制造虚假低成本。
- 历史 track 不回填，明确标 legacy/missing；本轮只保证新 typed track。
- panel 的严格 verdict parser 将两份有正文结论的报告标为 UNKNOWN 并触发 spare；主裁读取了完整
  报告，且生命周期预算只证明不同家族的真实成功 dispatch，不把模型投票当自动裁决。
- `submimo` / `claude-worktree` 的执行观测尚未接各自 controller；ledger 明示
  `planned_adapter_observation:*`，不会把 runlog 冒充它们。
