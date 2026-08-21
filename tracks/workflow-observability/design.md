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

新 track 增加一个很小的 typed record。机器消费的字段只在这里出现：schema version、
impact risk、design uncertainty、premise 状态/证据、执行 Adapter/模型、最终 verdict、返工与
自身缺陷计数。Markdown 保留理由、发现与取舍，不再重复机器枚举。

validator 分 active / dispatch / archive 阶段运行，错误统一输出
`rule=<id> actual=<value> expected=<value> verdict=BLOCK`。旧 track 没有 record 时走 legacy
兼容，不重写历史。

### B. 观测靠近事实产生处

- runlog receipt 补 finished / duration，不另存一份相同命令结果。
- panel/delegate 在主控制端、任务结束后，将紧凑摘要写入主仓 track 的 observations；原始
  transcript 仍在 logs / 仓外，可按以后单独的 retention 决策清理。
- 每次观测独立成小文件，避免并发 append 与“一个写坏整本账”。字段缺失显式 null/unknown。

### C. Ledger 是派生视图

ledger 只读扫描 record、runlog receipt 和 observations，输出 JSON/Markdown；不修改源工件，
不解析自由叙述。历史没有 record 的 track 只报告 legacy/missing，不猜 lane、token 或成本。

### D. 删除顺序不变

track archive 先校验本 track 的持久记录，再沿用现有 worktree sweep，最后移动 track 目录。
观测不写入 worktree，因此 sweep 后仍在。worktree 的归属继续只由路径判定。

## Key trade-offs / risks

- 多一个 typed record 是额外 Interface；用“只存机器消费字段、旧 track fallback”控制宽度。
- panel/delegate 接线属于控制面，默认 high；必须证明失败时不会把一次正常评审/委派变成假成功。
- 持久观测会让仓库增长，但目标是每事件 KB 级；完整输出继续不入库。
- 自动采集不到的成本必须 unknown；短期 ledger 会稀疏，但稀疏真账优于完整假账。

## Alternatives considered

- 直接正则解析 verify/logs：拒绝；多代模板与自由文本会把解析器变成第二本烂账。
- 把完整 review transcript 归档：拒绝；当前 logs 已 527MB，会与磁盘目标直接冲突。
- 复用 worktree 路径承载全部记录：拒绝；路径只回答归属，且树会被安全回收。
- 一次性迁移 21 个历史 track：拒绝；缺失事实无法从文字可靠还原，必须显示 unknown。
- 立即全上 D2/D3：拒绝；先积累本机成本—质量样本，再验证新增刹车是否值回成本。

## Test strategy (oracle)

主 Agent 先补测试，至少覆盖：

1. 新 track record 的合法/非法枚举、unknown、high uncertainty 无 premise 证据及 rule trace。
2. legacy active/archive 不误伤；新 record 缺失或损坏在正确阶段 fail closed。
3. 模板、CONVENTION、workflow 不再出现旧 full/fast 语义，双轴与实现一致。
4. runlog duration 可由可控时钟/短命令验证，既有 receipt 一致性不回归。
5. panel/delegate 的 compact observation 在主仓 track，worktree sweep 后仍存在；观测写失败不得
   伪造成功或吞掉原命令 rc。
6. ledger 不读 raw logs、不猜 legacy 数值、unknown 缺失率准确、重复运行字节稳定。
7. 现有 worktree-sweep 全套判据逐字行为不回归；总工具链全绿。

**这个 oracle 能被什么骗过?**

最危险的假绿有三种：① record 和 Markdown 各存一份、测试只看其中一份；② observation
实际写进 worktree，测试没走 archive sweep；③ ledger 把 missing 当 0，表格看起来完整。
判据必须分别做冲突输入、真 sweep、显式 null/unknown 断言；并做一项变异，证明把 missing→0
或跳过 high-uncertainty premise rule 会红。
