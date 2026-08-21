# Tasks: workflow-observability

- base-ref: ead89def8f9e4948d645200735ecf3884a1658be

> 委托 submimo fix 时:主 agent 先写失败测试(oracle)并 commit,再把窄范围实现
> 交给它;oracle/测试文件对它 off-limits;~2 次红了收回主 agent。

- [x] T1 主 Agent 独立方案 commit 后，请 sub-Codex 两阶段攻题并合并有效发现
- [x] T2 先补 schema / rule trace / legacy 双读 / superseded 红判据并确认红在目标断言
- [x] T3 实现共享 `track-record` Module 与 `decision.json` 模板
- [x] T4 接入 track new / guard / commit-msg / archive，确保 typed 与 legacy 路径不互相猜
- [x] T5 更新 workflow、templates、CONVENTION 和同步判据，删除旧 lane 现行语义
- [x] T6 先接 runlog observation，钉住 rc、无 transcript、原子同秒写与 raw-log 独立性
- [x] T7 接 panel：显式 track 归属、risk 一致性、实际腿/降级/时长/可得 usage
- [ ] T8 接 delegate：仓外 receipt、execution_finished / received 分离、旧 receipt 兼容
- [ ] T9 实现只读 ledger，覆盖 legacy/null/missing/mismatch、稳定输出和零写入
- [ ] T10 真 archive+sweep 端到端、聚焦回归、变异、总工具链；主自审后 high 复核并仲裁
