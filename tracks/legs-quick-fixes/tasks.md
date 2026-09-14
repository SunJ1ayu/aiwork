# Tasks: legs-quick-fixes

- base-ref: 799b8d4405bd24fec33880071e4187aa6c1af4eb

> 委托 submimo fix 时:主 agent 先写失败测试(oracle)并 commit,再把窄范围实现
> 交给它;oracle/测试文件对它 off-limits;~2 次红了收回主 agent。

- [x] T1 判据单独提交(`tests/test_leg_quick_fixes.py` + 套件注册),旧实现上红在七条目标、对照全绿(收据)
- [x] T2 A1 契约:subagent 任务书后重申、submimo 补上
- [x] T3 A2 失败归类:窗口限额=rate_limit 先于 auth;subkimi 抄 CLI error 行到诊断
- [x] T4 A3 连败计数:rate_limit 冷却但不计数
- [x] T5 A4 opencode `continue_loop_on_deny`;A5 OpenCode Go 会话头
- [ ] T6 判据转绿 + 全量回归 `runlog --final`
- [ ] T7 真跑冒烟:GLM 底座腿、GLM 聊天回落腿、Kimi 各一次(在使用现场验证)
- [ ] T8 预跑归档闸 → high 外审 → 主裁 → 归档
