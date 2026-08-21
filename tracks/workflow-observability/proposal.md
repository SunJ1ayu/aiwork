# Proposal: workflow-observability

- Date: 2026-08-21
- Status: open

## Goal

把 aiwork 的 track 决策事实与运行观测收拢为一条可机械校验、可在 worktree / 原始日志
清理后继续汇总的紧凑记录链；修复当前 `impact-risk` / `design-uncertainty` 新规范与旧
`lane=full|fast|self` 模板、守卫之间的语义漂移，并提供只读 ledger。

## Motivation

最新 Wiki 给出了“质量约束下比较每成功任务成本”的方法，但现有 21 个归档 track 只有
13 个引用 runlog、8 个带 roster、1 个显式写新双轴；runlog 没有耗时，review/delegate
的 usage 与结果也没有稳定落进 track。直接解析自由文本会造出第二本不可信的账。

同时，`workflow/CLAUDE.md` 已迁到双轴，`track/templates/verify.md`、CONVENTION 和 guards
仍沿用旧 lane。先消除这个漂移，机器记录才有稳定语义。

## 真问题(第一性)

- 用户原话:「ok那你先列计划然后拉subcodex合并，最后按步骤执行」；前文确认新记录不能与
  worktree 自动回收冲突。
- 真正要解决的是:留下足够小、足够可信、不会随执行现场消失的原始事实，使后续成本—质量
  选择不再靠手工计数或原始日志常驻磁盘。
- 我在这中间翻译了什么:把“做记录”翻译为“机器事实 + 可再生成视图”，而不是保存完整现场；
  把“拉 subcodex 合并”翻译为主 Agent 先独立落盘方案，再让 sub-Codex 攻方案并由主 Agent
  合并有效发现，不把规划和裁决外包。

## 承重前提

- worktree-sweep 删除的是已安全合入的隔离树，不删除 `tracks/archive/<name>/`；记录必须由
  主控制端写入主仓 track，不能只存在于执行树。
- worktree 路径继续是归属事实的唯一来源；新 record 不复制 worktree registry。
- 原始 `logs/` 是可清理流水；ledger 不得以它们长期存在为前提。
- usage、现金费用、订阅额度拿不到时必须记 unknown，不能默认为 0。

## Scope

- in: 统一双轴在 workflow / templates / convention / guards / tests 中的语义。
- in: 新 track 的紧凑 typed record、分阶段 validator 与可审计 rule trace。
- in: runlog/panel/delegate 在主控制端产生的紧凑观测事实；不保存完整 transcript。
- in: 从归档 record / receipt 生成只读 ledger，显示缺失率而非猜历史。
- in: 旧 track / 旧 archive 向后兼容，不批量伪造迁移数据。

## Non-goals

- 不改变 worktree-sweep 的删除资格、顺序、`--keep-trees` / `--discard-ignored` 语义。
- 不实现 LLM 自动编译安全规则；规则仍由人写、由判据钉住。
- 不在本轮全局上线 D2 threat actor 或 D3 premise panel；只实现 D1 所需最小触发与 trace。
- 不计算单一“总成本分”；wall time、usage、现金/订阅成本分别呈现。
- 不把 527MB 现有原始 logs 搬进 Git，也不在本轮删除它们。
