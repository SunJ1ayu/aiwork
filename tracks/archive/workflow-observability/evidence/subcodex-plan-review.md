# sub-Codex 规划攻题仲裁（2026-08-21）

## 方法

sub-Codex 严格分两阶段：先不读本 track，从现有 workflow、track、guards、runlog、panel、
delegate 与测试独立出方案；锁定后再读主 Agent 的 commit `a25f008` 做差异审查。全程只读。

## 接受

- 唯一机器事实源命名为 `decision.json`；Markdown 不复制 verdict/lane/派给。
- validator 使用 shape / dispatch / archive，而不是 active / dispatch / archive。
- v1 删除“返工轮数 / 自身错误数”；只记录可观察的 dispatch_count、rc 与实际 Adapter。
- runlog 文本 receipt 只做证据，ledger 只读 decision + typed observations。
- 三个 controller 共享一个 observation writer；写失败明确报警但不篡改既有 rc。
- planned 与 actual 分开；panel 显式绑定 track 并核对 risk；delegate 的 finished 与 received 分开。
- legacy 不回填、不从旧 lane 猜双轴；保留 ARCHIVED-SUPERSEDED。
- usage 首版只采真实可得值；订阅腿和现金费用拿不到均为 null，不查价格表估算。
- D1 的机械承诺限于真实 dispatch seam；主 Agent 直接实现路径不冒充已全局覆盖。

## 未接受 / 延后

- 未接受“本轮拆成只修文档”的极小切片：用户明确要求按计划执行，且没有观测事实就无法验证
  typed record 的实际 Leverage。本轮仍做一个端到端 tracer bullet，但逐 Adapter 单独 commit/验收。
- 延后历史回填、质量归因、统一 token、价格估算、因果实验、logs retention、D2/D3、数据库与 dashboard。

## 合并后顺序

schema/规则红判据 → record Module → track 生命周期 → 文档同步 → runlog Adapter → panel Adapter →
delegate Adapter → ledger → 真 archive/sweep 与全量复核。
