# Tasks: workflow-control-plane

- base-ref: 83477549d502b5697590e42882f91dd192f4c100

> 本轮修改的正是判卷/派活控制面，由主 Agent 直接实现；每组 oracle 先单独提交，再提交实现。

- [x] T1 为 `ro-repo-exec` judging-surface、具体 track 绑定和 ignored worktree 删除补红判据
- [x] T2 实现 T1，安装/验证 commit-msg 与历史审计入口
- [x] T3 为健康池轮换二审、风险档预算、失败升级和扩展 roster 补红判据
- [x] T4 实现 T3，并保持显式四审覆盖路径
- [x] T5 为 `runlog --final` 源码身份和秘密形状拦截补红判据
- [x] T6 实现 T5，不增加一次机械检查或模型调用
- [x] T7 把 CLAUDE/skills/README 迁入唯一规范源，增加同步/漂移红判据
- [x] T8 修复已知文档漂移，并安全部署到当前 `/root`、`/root/.claude`
- [x] T9 聚焦回归、全量防锈、主自审、健康池二审与仲裁
- [ ] T10 填 verify、归档；不删除现有 logs/out/用户未跟踪任务
