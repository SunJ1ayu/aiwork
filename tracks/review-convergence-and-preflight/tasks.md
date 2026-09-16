# Tasks: review-convergence-and-preflight

- base-ref: 06cf95ffb527146cfcc13d1fdfaa11115b4155f2

> 委托 submimo fix 时:主 agent 先写失败测试(oracle)并 commit,再把窄范围实现
> 交给它;oracle/测试文件对它 off-limits;~2 次红了收回主 agent。

- [ ] 开工:补交 tasks/ 下 9 份未跟踪简报;proposal(轮次预算 2)/ design(预检语义 + 走读 + 判据表)/ decision
- [ ] 判据先行:`tests/test_track_preflight.py` P1~P14 + 登记进 `bin/rust-check-review-tooling`;旧实现下红,单独 commit
- [ ] 实现 D:`track-record validate --phase preflight`;`bin/track preflight`;worktree 清理的 preflight 模式
- [ ] 红检 + 变异自攻(删分类 / 短路 / ERROR 降格 / 预检里真删树)
- [ ] 相关回归:track-record / worktree-sweep / evidence-lifetime / track-guard / review-delivery
- [ ] 协议 A/B/C:panel 4b 改写;track SKILL / CONVENTION 入口;模板(review-task / proposal / verify);sync-workflow-docs
- [ ] 总跑 `bin/rust-check-review-tooling`
- [ ] 派评审前自己跑 `track preflight`(dogfood);主 agent 自审落盘
- [ ] panel-review(high,预算 2 轮)→ 按新 4b 处置 → 仲裁 → 归档
