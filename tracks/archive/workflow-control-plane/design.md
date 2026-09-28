# Design: workflow-control-plane

- Change: workflow-control-plane
- Status: draft

> Panel hook — 仅当这是真·开放架构分叉(多个站得住的方向、风险=隧道视野)时,
> 先跑 `panel-explore`,把方向谱折叠进这里。否则直接写方向就行。
> 主 agent 在读任何 panel 输出之前,先落自己的方向(反锚定)。

- 规划双出: 不适用：方向已经由业主与主 Agent 收敛，并由独立 sub-Codex 对上一版分析做过
  反向复核；本轮不是开放架构分叉，而是把已拍板的策略机械化。为避免依赖会话证据，关键
  取舍和驳回项全部重述在本文件。
  > **只剩一个触发条件:新写面 / 开放方向且这单我自己干**(动档案格式、写口语义扩张、
  > 新增参数……即 verify 那边会填 `lane: full` 的同一批面)。
  > **"要外包给执行腿"那半句 08-06 退场** —— 它升级成了 `delegate-codex --attack-log`:
  > 派活时给不出攻题记录就发不出去,不再靠我在这一格里自评(08-05 我就是在这格里
  > 用一句括号把它绕过去的)。
  > 做法:主 agent **先落盘**,再让 `gpt-5.6-sol` 对**同一份需求**独立出一版
  > (明令不许读本 track 的工件),然后对差异。抓的是**"我以为理所当然"的地方** ——
  > 那正是"我出方案、它来审"照不到的死角(审查只会在我的框子里挑毛病)。
  > 史料:08-02 due-writer 单它点破了我判卷题的一个洞(`fef253c`);
  > 08-06 delegate-entry 单它点破三处(攻题记录会过期 / 闸①没给闸③底账 /
  > 红检没区分"红在 build 上")—— 两次都是**结构性的洞,不是措辞**。

## Approach

### 1. 两个正交轴，不再让 `full` 同时承担风险与人数语义

- `impact-risk`: self / standard / high，决定需要多少独立证据；
- `design-uncertainty`: low / high，决定是否做 premise attack / 双出 / panel-explore。

默认评审预算：self=0 条外腿，standard=1 条，high=2 条。high 从健康池选择不同模型家族并
轮换组合；失败、降级、冲突、NEEDS_MORE_INFO 或主 Agent 仍不确定时再追加第三腿。四审只在
判卷工具、沙箱、权限边界或二审不能收敛时显式启用。

### 2. 现有 roster 扩展，不另造第二套清单

roster 记录选择、跳过原因、实际模型/agent-chat 资格、是否给出有效裁决和审查快照。
archive 按风险档检查“有效证据数”，不按进程启动数或全票结果检查。

### 3. 具体 track 绑定取代七天通行证

受保护 commit 使用 `Track: <name>` trailer，由 commit-msg hook 校验。pre-commit 继续保护暂存
内容，但不再用“任意 verify 七天内更新”替代归属。历史审计检查受保护路径 commit 的 trailer。
`bin/ro-repo-exec` 明确加入 judging surface。

### 4. 删除动作默认保守

worktree clean 只证明 tracked/untracked non-ignored 已保存；ignored 文件另算。发现非白名单
ignored 文件时默认 BLOCK，只有显式 `--discard-ignored` 才允许删除，`--keep-trees` 继续保留。

### 5. final evidence 复用最后一次机械检查

`runlog --final` 在原命令前后记录完整 HEAD 和被测源码视图身份；receipt 自身是允许新增项，
实现/判据内容不得在运行期间变化。archive 的 high 风险轨迹要求最后一个裁决性检查带 final
身份。命令/输出在入库前经过秘密形状扫描，命中时拒绝形成可提交收据并提示改用脱敏输出。

### 6. 唯一规范源

规范源进入 aiwork Git；`/root/CLAUDE.md` 与 `/root/.claude/skills/...` 是部署副本。同步命令只
更新已纳管的工作流文件，不触碰 settings、memory、credentials 等用户现场。总回归逐字比较
源与部署副本。第一轮迁移先导入当前有效内容，再修已知漂移。

## Key trade-offs / risks

- 两审降低单轮覆盖面；用跨家族选择、轮换和冲突升级补偿，而不是假装二等于四。
- 健康检查若需要真实供应商调用会消耗额度；首版只消费最近 roster/明确配置状态，未知视为可尝试，
  不增加专门探活请求。
- commit trailer 仍可被 `--no-verify` 绕过；历史审计负责让绕过可见，不能宣称是强安全边界。
- final 源码视图身份若扫整个 1GB 工作目录会很慢；只覆盖 Git tracked + non-ignored untracked，
  并显式排除本次 evidence 文件，不能退化成只记 `dirty=yes/no`。
- 规范部署涉及 `/root/.claude` 的现有未提交内容；同步必须逐文件、拒绝覆盖非预期差异。

## Alternatives considered

- 固定四审全通过：拒绝；额度或单腿故障不等于实现不合格，且本机资源不适合常态四并发。
- 纯随机二审：拒绝；可能抽到失效腿、同质腿或两个降级 chat 腿。
- 所有 high lane 强制规划双出：拒绝；影响风险与方向不确定性不是同一个轴。
- final 额外重跑一次：拒绝；只给原本最后一遍增加身份，不制造仪式性重复。
- 只修 README 文案：拒绝；多份规范还会继续漂移，必须先建立唯一源和漂移判据。

## Test strategy (oracle)

- track guard：`ro-repo-exec` 属于保护面；无/错 Track trailer 的受保护 commit 被历史审计指出；
  任意七天 verify 不再给无关改动通行。
- archive：含 ignored 唯一文件的 worktree 默认 BLOCK；显式 discard 才删除；普通缓存白名单不误报。
- panel：健康池只选可用且跨家族的 N 条腿；high 默认 2；失败/降级/分歧触发追加；roster 记录资格。
- runlog：final 收据绑定完整代码视图；运行中改实现会红；只新增 receipt 能绿；秘密形状拒绝入库。
- docs：源文件与部署副本任一字节漂移，总回归红；已知腿数、模型和 agent 模式断言与实现一致。
- 全量 `bin/rust-check-review-tooling` 通过，且新增测试全部进入 SUITES。

**这个 oracle 能被什么骗过?**

仍可能被这些情况骗过：供应商“健康”在选择后立刻耗尽额度；两个不同模型家族仍共享同一盲点；
秘密扫描只能识别已知形状；用户用 `--no-verify` 和手改 evidence 可绕机械闸。接法分别是运行期
失败自动换腿、主 Agent 独立审与条件升级、最小化证据内容、历史审计与亲读 diff。
