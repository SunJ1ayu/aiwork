# Verify: design-before-build

## 机械检查与真实限制

- workflow-docs:37 条通过;typed track:82 条通过;preflight:19 条通过。bin/tests/schema 未修改。
- 第一次 linked worktree 的判据绿,但 observe 回主树找不到 track;该收据不冒充完整 execution coverage。
- 独立 clone 的第一次运行被沙箱禁止 unshare(rc=78),没有跑判据;在宿主保留判据断网隔离后重跑全部通过。
- 这些是兼容与部署机制检查,不是方案正确率或返工收益证明。

runlog: workflow-compatibility rc=0 commit=65ec3fa dirty=yes final=yes at=2026-09-20T08:09:50Z file=tracks/design-before-build/evidence/20260920T080950Z-01-workflow-compatibility.txt
runlog: workflow-compatibility-clone rc=78 commit=db7eb70 dirty=no final=yes at=2026-09-20T08:13:19Z file=tracks/design-before-build/evidence/20260920T081319Z-01-workflow-compatibility-clone.txt
runlog: workflow-compatibility-host rc=0 commit=db7eb70 dirty=yes final=yes at=2026-09-20T08:13:51Z file=tracks/design-before-build/evidence/20260920T081351Z-01-workflow-compatibility-host.txt

## 第1轮独立实现审查

主 agent 自审在仓外 /root/panel-my-reviews/design-before-build-review-my-review.md,先于派发。
派发前 preflight:rc=3,BLOCK=0,PENDING=2,ERROR=0;本轮初审时 verify 只有脚手架。
工具反锚定警告点名 verify 模板和占位 track verify;没有喂给主 agent 的自审结论。
本轮 standard=1,实际 Cursor/Grok xai 家族;原报告 evidence/review-r1.txt。

```text
# panel-review 花名册(2026-09-20 16:21:02)task=design-before-build-review
# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
# impact-risk=standard requested-budget=1 selected-count=1
# selected=subcursor(xai/subcursor)
# escalation=none
# snapshot=head:e1cd009
# 日志:/root/aiwork/logs/panel-design-before-build-r1.*.log
submimo=off subdeepseek=off subglm=off subkimi=off subgemini=off subgrok=off subcursor=PASS(verdict=BLOCK)

```

| # | 发现/触发与影响 | 核实与处置 |
|---|---|---|
| R1-1 | panel §2 仍让 uncertainty 决定是否检查,可按 low 跳过新协议 | 成立,主 agent 也在终稿走读发现。必须修:改成先4c事实检查再记录轴 |
| R1-2 | panel 顶部旧路由把非开放分叉直接做,用户可能读不到4c | 成立,必须修:明确实施前入口,轻量路径以4c为准;主CLAUDE同类导航同步;convention澄清机器不强制工件不等于流程免检 |
| R1-3 | submimo explore 禁所有工具,却被描述成可读实现/调用方 | 成立,亲读bin/submimo:223。必须修:默认代码相关挑战用可读快照的subcursor;MiMo只在事实完整、无需查仓的题面探索使用,不得冒充源码核查 |

一次修复清单为上述三项。第2轮核修复及影响面;当前不写最终PASS。
