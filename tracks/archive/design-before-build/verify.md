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

## 修复后的检查

runlog: workflow-docs-r2 rc=0 commit=32caeda dirty=no final=yes at=2026-09-20T08:23:23Z file=tracks/design-before-build/evidence/20260920T082323Z-01-workflow-docs-r2.txt

37条workflow文档检查通过,source-stable=yes。只改文字入口,旧typed82+preflight19的机器实现未变,
不为同一结论无意义重复全套。修复清单三项已完成,第2轮只核修复及影响面。

## 第2轮独立复审

派发前preflight:rc=3,BLOCK=0,PENDING=1,ERROR=0。复审可读上轮处置表,不算初审泄漏。
原始日志:/root/aiwork/logs/panel-design-before-build-r2.subcursor.log。以下保留完整正文,不新增承重文件。

```text
# panel-review 花名册(2026-09-20 16:28:35)task=design-before-build-review-r2
# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
# impact-risk=standard requested-budget=1 selected-count=1
# selected=subcursor(xai/subcursor)
# escalation=none
# snapshot=head:a54c294
# 日志:/root/aiwork/logs/panel-design-before-build-r2.*.log
submimo=off subdeepseek=off subglm=off subkimi=off subgemini=off subgrok=off subcursor=PASS(verdict=PASS)

```

I'll verify the three claimed fixes against the snapshot files and the specified diff, then judge only regressions or remaining blockers.
Diff is in; next I’ll read the three patched sections plus adjacent rules and the explore-tool contracts they now cite.
三项修复已对齐 4c：先做事实检查再记两轴，explore 能力与 adapter 一致，轻量路径与归档预算未被改成机器闸。

**Conclusion: PASS**

### 1. 顶部路由与 §2 已与 4c 同序
`workflow/skills/panel/SKILL.md:12-21` 删掉「两者都不是→直接做」。现为：先按 4c 选深度；未分叉但命中行为/契约/撤回代价 → 一次不同家族挑战；仅「4c 确认为轻量」才主 agent 自验。
`SKILL.md:53-56` 不再让 `design-uncertainty` 决定是否检查；改为先 4c、再记两轴，自报 low 不能免检。与 `SKILL.md:326-329`（uncertainty 是检查后判断）一致。

### 2. 导航/convention 不再等于免检
`workflow/CLAUDE.md:41-45,64-65`：先查方案再动手；不能因两种 panel 都不像而跳过命中检查。随身规矩仍指向 4c。
`track/CONVENTION.md:183-188`：机器不强制散文工件 ≠ 放弃 4c；轻量分类须按 4c，单方向或小 diff 本身不够。`192-201` 仍禁止自报 low/Jev 免检。

### 3. explore 能力写对，不足不能冒充完成
`bin/submimo:221-223`：explore **禁一切工具、只读题面**。
`bin/subcursor:12-14,97-104`：只读快照；Shell/Write 拒绝，且不得声称跑过测试。
`SKILL.md:307-317`：需查仓用 subcursor；MiMo 仅当 brief 已含事实、无需查仓；给了仓库路径 ≠ 已核源码；上下文不足须补事实或换腿，**不得宣布完成**。未新增 review 模式。

### 4. 影响面
轻量行仍在 `SKILL.md:20,295,329`。预算仍 self=0/standard=1/high=2；`--all` 仍是显式全池。切片仍 `review_contract_version=2`、永不计入归档覆盖、拒绑 track（`383-384`）。`SKILL.md:340` 与 convention `200`：无新语义机器闸。

未发现本轮实质阻断或修复引入的回归。

Conclusion: PASS


主 agent 核实:三项均已修,复审无新阻断。设计探索为MiMo+Grok两家,实现评审为Grok两轮,均不拿模型意见自动裁决。
复审时部署与实际建单验证尚待完成,outcome仍为空;下节记录完成后的最终裁决。


## 现场部署与最终裁决

主仓已 fast-forward 到 b0e02e2,执行 `bin/sync-workflow-docs --force` 同步主指令及 track/panel/delegate 三份 skill。
`bin/sync-workflow-docs --check` 确认部署副本与唯一源字节一致。

runlog: live-workflow-and-scaffold rc=0 commit=b0e02e2 dirty=no final=yes at=2026-09-20T08:29:26Z file=tracks/design-before-build/evidence/20260920T082926Z-01-live-workflow-and-scaffold.txt

现场37项文档检查通过;实际调用 `bin/track new` 新建临时 track,生成的 design 与模板替换结果逐字节一致,typed shape 校验通过。临时建单目录已清理,完整输出见 receipt;source-stable=yes。

主 agent 最终裁决:PASS。初始兼容性检查138项通过,修复后文档检查37项通过,现场文档检查37项及实际建单通过。
独立方案探索为两个外部模型家族,实现评审首轮BLOCK的三项均有修复与处置,第二轮PASS;无未解决阻断。
这次交付是工作流协议和模板调整,没有新增语义机器闸、Jev调用或切片覆盖资格。是否减少返工仍待约5个自然任务观察,不得把本次检查通过解释成效果已验证。
