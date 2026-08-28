# Verify: review-result-v2

- Date: 2026-08-27

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再按 impact-risk 预算跑 panel-review；只有特殊控制面
> 才显式 `--all` 做全池评审。最后仍由主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes（无独立编译产物；Python/Shell 入口由总闸逐项加载和执行）
- [x] tests pass
- [x] no secrets / unsafe ops

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t review-result-v2 -- <判据命令>
```

```
runlog: full-regression rc=0 commit=b4ce427 dirty=no final=yes at=2026-08-28T10:39:50Z file=tracks/review-result-v2/evidence/20260828T103950Z-01-full-regression.txt
```

## Review

- 规格自查(读任何 panel 输出之前先答):如果规格错了，最危险的两种错法是把
  “完成了一次有效审查”偷换成“审查结论自动批准收货”，或让 subject identity 混入
  review protocol、导致同一源码对象因协议变化无法比较。当前设计用两个独立事实防止它们：
  `coverage_eligible` 只判腿是否完成可信审查，最终裁决仍只在 `decision.json.outcome`；
  `subject_digest` 只含任务原始字节与实际 Git snapshot，`review_contract_version` 独立记录。
  false-coverage 矩阵再从反面验证 UNKNOWN、NMI、timeout、degraded、v1、不同 subject、
  跨 run 和冲突都不能补归档预算。若这些边界任一在 archive 与 ledger 输出不一致，
  consumer parity 判据会直接暴露，而不是靠 panel 一致 PASS 猜规格正确。
- 腿的花名册: 待 panel-review 收尾后粘贴机器生成行。
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > **控制器没活到收尾时它压根不存在** —— 那时跑 `panel-roster <日志前缀>` 从盘上重建,
  > 与控制器自己写的**归一化后一致**(判据 R5b 守着;抬头有渲染时间戳,不是字面逐字节)。**一轮零记录的评审也粘得出这一行**,
  > 所以"那轮被砍了所以没有花名册"不再是理由(2026-08-23,track panel-roster-from-disk)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - `ReviewLegResult v2` 已成为唯一 executable contract、normalizer 与 eligibility predicate；
    adapter 只提供 invocation/process/snapshot/view/evidence 事实。
  - production observation writer 已关闭 v1 `--leg` 写口；v1 仍可读，但不再产生
    authoritative coverage，也不会从 raw log 回填升级。
  - archive 与 ledger 只认可同一次成功 panel、同一 subject digest 的 eligible family；
    同 subject 跨 run 只输出 shadow 指标，未启用 P1 放行。
  - Kimi/Gemini 的 timeout verdict 和 Gemini salvage 仍保留为 partial evidence，
    但 timeout/degraded 不能计 coverage；provider-specific auth/home/lock/sandbox 与 raw log
    按原计划保留，不做 adapter 大重构。
  - 第一次完整总闸发现 `tests/test_review_result.py` 未接无出口守卫，16/18 BLOCK；
    这是真控制面遗漏，已在 `b4ce427` 修复。专门 no-egress 判据 18/18、最终完整总闸全绿。
    该次失败发生在 runlog 收据轮之前，未伪装成机器收据；最终收据记录的是修复后的稳定快照。
  - 规范源、README、track/panel skill 与 Claude 部署副本已统一改成 coverage-eligible 语义，
    不再描述成“进程成功的不同家族腿”。
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): 待读取 panel 证据后裁决；当前主审未发现阻断性问题。
  > 这里写理由；最终枚举写进 `decision.json.outcome.verdict`。归档时仍为空会被
  > `track-record validate --phase archive` 挡住，`track list` 也会打 ⚠️。

## Accepted deviations

- consumer oracle 是从额度中断留下的 dirty worktree 恢复的；提交图仍保持
  `eb0c01f`（测试矩阵）先于 `1adda64`（实现），因此 checkout 测试提交本身会红，
  但本窗口没有重新制造一遍人工红跑收据。影响仅限开发过程证据，不影响最终行为判据。
