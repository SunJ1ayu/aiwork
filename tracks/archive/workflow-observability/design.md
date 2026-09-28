# Design: workflow-observability

- Change: workflow-observability
- Status: draft

> Panel hook — 仅当这是真·开放架构分叉(多个站得住的方向、风险=隧道视野)时,
> 先跑 `panel-explore`,把方向谱折叠进这里。否则直接写方向就行。
> 主 agent 在读任何 panel 输出之前,先落自己的方向(反锚定)。

- 规划双出: 待执行 `/root/aiwork/logs/workflow-observability-subcodex-plan.md`；本文件先独立落盘并
  commit，sub-Codex 只能读本 commit 后的 brief/代码，输出是待仲裁证据。
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

### A. 一个机器决策事实源

新 track 增加唯一机器事实源 `decision.json`。机器消费的字段只在这里出现：schema version、
track、impact level/factors、design uncertainty、premise attack、计划执行 Adapter/模型与最终
verdict。返工轮数、自身缺陷数不进 v1：controller 客观拥有的是 dispatch 次数与 rc，把它们
归因为“返工/谁的错”仍是人为判断。Markdown 保留理由、发现与取舍，不再重复机器枚举。

validator 分 shape / dispatch / archive 阶段运行：shape 允许新建时的 null，只查字段和类型；
dispatch 在真实 controller 入口要求本次行动所需决策完整；archive 要求最终事实完整。错误统一
输出 `rule=<id> actual=<value> expected=<value> verdict=BLOCK`。有 decision 只走新 schema，
旧 track 没有 decision 时走 legacy 兼容，不重写历史；ledger 一律标 legacy/unknown。

planned 与 actual 分开：`decision.execution_plan` 记录计划，observation 记录实际 controller、
模型和降级；不一致由 ledger 明示 mismatch，不让一方覆盖另一方。verdict 保留现有
`ARCHIVED-SUPERSEDED` 语义。

### B. 观测靠近事实产生处

- 一个 stdlib Python `track-record` Module 统一提供 validate / observe / ledger。三个 controller
  只调用该 Interface，不各写路径检查、原子创建、schema、secret 白名单与同秒碰撞逻辑。
- runlog 保留原有文本 receipt 作为机器证据；同一次运行另写 KB 级 typed observation，
  不复制命令输出、完整 argv 或 transcript。
- panel/delegate 在主控制端、任务结束后，将紧凑摘要写入主仓 track 的 observations；原始
  transcript 仍在 logs / 仓外，可按以后单独的 retention 决策清理。
- 每次观测独立成小文件，避免并发 append 与“一个写坏整本账”。字段缺失显式 null/unknown。
- “紧凑”有机械边界：单事件最多 64 KiB、panel 最多 4 条 legs；writer 写前复用 reader schema，
  active/archive 的 staged 机器源持续校验，未知字段 trace 不回显可能的 secret/transcript 内容。
- observation 写失败必须打印 `OBSERVATION_WRITE_FAILED`、不得伪造事件、不得改变 controller
  已有 rc 语义；typed track 在 archive 时因计划需要的观测缺失而 BLOCK。
- panel 增加显式 `--track NAME|--no-track`，不从 task 名猜；dispatch 前机械核对
  `decision.impact.level == --risk`，typed track 的显式 budget 不得低于 risk 的 0/1/2 下限；
  PASS archive 与 ledger 再从成功 panel observation 核对 0/1/2 个成功的不同模型家族腿，
  未绑定事件或失败腿不算。
- delegate 继续先写仓外 receipt；Codex 结束记录 `execution_finished`，`--receive` 后再记录
  `received`，两者不互相冒充。事件只从 receipt 白名单字段导入主仓。

### C. Ledger 是派生视图

ledger 只读扫描 `decision.json` 与 `observations/*.json`，输出 JSON/Markdown；不修改源工件，
不解析 runlog 文本 receipt、raw logs 或自由叙述。历史没有 decision 的 track 只报告
legacy/missing，不猜 lane、token 或成本。ledger 报 dispatch_count，不把它命名为返工率；
PASS 但覆盖不完整的任务不进入“成功任务成本”聚合，只进入缺失清单。

### D. 删除顺序不变

track archive 先校验本 track 的持久记录，再沿用现有 evidence / ephemeral 检查与 worktree
sweep，最后移动 track 目录。
观测不写入 worktree，因此 sweep 后仍在。worktree 的归属继续只由路径判定。

### E. D1 的诚实射程

委派路径存在真实 dispatch seam，可在花成本前机械挡住 high uncertainty 缺 premise 证据。
主 Agent 直接实现没有“开始写代码”入口；skill 要求显式 validate，但最早的不可绕机械检查仍在
commit。v1 不宣称 D1 已全局解决。

## Key trade-offs / risks

- 多一个 typed record 是额外 Interface；用“只存机器消费字段、旧 track fallback”控制宽度。
- panel/delegate 接线属于控制面，默认 high；必须证明失败时不会把一次正常评审/委派变成假成功。
- 持久观测会让仓库增长，但目标是每事件 KB 级；完整输出继续不入库。
- 自动采集不到的成本必须 unknown；短期 ledger 会稀疏，但稀疏真账优于完整假账。
- `track new` 的 null 是合法初态；若 shape 阶段误要求完整，会把轻量 track 偷偷改成状态机。

## Alternatives considered

- 直接正则解析 verify/logs：拒绝；多代模板与自由文本会把解析器变成第二本烂账。
- 把完整 review transcript 归档：拒绝；当前 logs 已 527MB，会与磁盘目标直接冲突。
- 复用 worktree 路径承载全部记录：拒绝；路径只回答归属，且树会被安全回收。
- 一次性迁移 21 个历史 track：拒绝；缺失事实无法从文字可靠还原，必须显示 unknown。
- 立即全上 D2/D3：拒绝；先积累本机成本—质量样本，再验证新增刹车是否值回成本。
- 返工/自身错误 typed 字段：拒绝；dispatch 次数是事实，归因不是 controller 能机械观察的事实。
- ledger 解析 runlog 文本：拒绝；receipt 混合元数据与完整命令输出，只继续承担证据职责。

## Test strategy (oracle)

主 Agent 先补测试，至少覆盖：

1. 新 track decision 的合法/非法枚举、null/missing、high uncertainty 无 premise 证据及 rule trace；
   high-risk factors 降档必须红，superseded 可归档。
2. legacy active/archive 不误伤；新 record 缺失或损坏在正确阶段 fail closed。
3. 模板、CONVENTION、workflow 不再出现旧 full/fast 语义，双轴与实现一致。
4. runlog observation 的 finished/duration 可由可控时钟/短命令验证，既有 receipt 一致性和
   命令 rc 原样透传不回归；事件不含 stdout/stderr、prompt、secret 或完整 argv。
5. panel/delegate 的 compact observation 在主仓 track，worktree sweep 后仍存在；观测写失败不得
   伪造成功或吞掉原命令 rc。
6. ledger 只读 decision/observations，不读 raw logs/receipt、不猜 legacy 数值、unknown 缺失率
   准确、重复运行字节稳定，运行前后 git status 与源哈希不变。
7. typed record 损坏时在 sweep 前 BLOCK；现有 worktree-sweep 全套判据逐字行为不回归；
   删除 raw logs 后 ledger 字节不变；真 sweep + archive 后仅 lifecycle location 改变，成本/质量
   指标与总聚合不变；总工具链全绿。

**这个 oracle 能被什么骗过?**

最危险的假绿有三种：① record 和 Markdown 各存一份、测试只看其中一份；② observation
实际写进 worktree，测试没走 archive sweep；③ ledger 把 missing 当 0，表格看起来完整。
判据必须分别做冲突输入、真 sweep、显式 null/unknown 断言；并做一项变异，证明把 missing→0
或跳过 high-uncertainty premise rule 会红。
