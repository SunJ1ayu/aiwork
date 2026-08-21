# Tasks: workflow-observability

- base-ref: ead89def8f9e4948d645200735ecf3884a1658be

> 委托 submimo fix 时:主 agent 先写失败测试(oracle)并 commit,再把窄范围实现
> 交给它;oracle/测试文件对它 off-limits;~2 次红了收回主 agent。

- [ ] T1 主 Agent 独立方案 commit 后，请 sub-Codex 攻前提、范围和最小 Interface，合并有效发现
- [ ] T2 先补双轴 schema / D1 trace / legacy 兼容红判据并确认红在目标断言
- [ ] T3 实现 typed record validator，接入 track new / guard / commit-msg / archive
- [ ] T4 更新 workflow、templates、CONVENTION 和同步判据，删除旧 lane 语义漂移
- [ ] T5 为 runlog / panel / delegate 补紧凑 controller-side observation 与失败语义判据
- [ ] T6 实现只读 ledger，覆盖 unknown、legacy、稳定输出和不依赖 raw logs
- [ ] T7 跑聚焦回归、变异、总工具链；主自审后按 high 控制面预算复核并仲裁
- [ ] T8 填最终 record / verify，确认 worktree sweep 无回归后归档
