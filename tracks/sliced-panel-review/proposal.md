# Proposal: sliced-panel-review

- Date: 2026-09-13
- Status: open

## Goal

给 aiwork 加一种**单层多家族切片评审**:主 agent 把一次改动切成几片,每片直接派给一个
不同模型家族的现有评审腿(腿本身就是 worker,不再在腿里派子 agent);同时并行派一条
独立的 GPT 整体审查腿;交卷后主 agent 挑重要问题,换一个家族定点复核。所有调用有
显式会话预算、按任务/尝试落盘,状态能从盘上重建,问题记录只追加不覆盖。

## Motivation

现在 panel-review 每条腿都整任务全量看一遍。业主了解到 Grok Build 的做法是
「切片 → 专项 subagent 并行审 → 对抗验证 → 汇总」,想借这个编排,只把 subagent
换成我们不同家族的腿,并保底一次交叉验证。GPT 已出计划
(`tasks/sliced-panel-review-plan.md`)并经过一轮独立对抗评审
(`evidence/premise-attack.md`),业主 21:12 说「开始改吧」,GPT 额度耗尽后由主 agent 接手实现。

## 真问题(第一性)

- 用户原话:
  - 「我们现在的aiwork工作流审查腿是每次都全量看一遍,我了解到grok build的subagent审查是切片之后派子agent审查,所以我想说我们能不能借鉴这种方法,比如切片之后换成我们aiwork不同的腿审查片段,然后再保底一个交叉验证」
  - 「我们需要的是grok build这种比如生成5个sub agent 这五个来自我们不同的家族模型,然后分别审这些切片,不能起五个家族再起五个subagent这样花费感觉太大了」
  - 「切片b让glm抽查还是再来一个gpt全部大致走一遍?」→ 采纳「GPT 独立整体审 + 重要问题换家族复核」
- 真正要解决的是:**同样花 N 个会话,让每个会话审得更聚焦**,而切片带来的「大家各看各的都对、连起来是错的」
  由一条独立整体腿兜底,误报由换家族复核压下去 —— 且**会话数看得见、不会暗中翻倍**。
- 我在这中间翻译了什么:
  - 「保底交叉验证」翻译成两件事:并行的**独立整体腿**(补切片漏的)+ 交卷后**按需**定点复核(压误报),不是每片再配一腿。
  - 「不能起五个家族再起五个 subagent」翻译成机械约束:一个工作项 = 一次腿调用;腿内派子 agent 能关的关掉,
    关不掉的如实写成提示词级约束;agent→chat 自动回落在切片模式下关闭(那是暗中多一次调用)。
  - 「借鉴」**不等于**替代现行归档门槛:试点结果一律标成新契约版本,旧 high=两家族全量的归档闸不认它。
    这是对抗评审(evidence/premise-attack.md §1 第 2 点)和 GPT 计划 P3 的共同要求,业主也认可「先跑通再谈正式启用」。

## Scope

- in:
  - `bin/panel-slice`:`run` / `verify` / `retry` / `decide` / `status` 五个子命令 + `bin/_panel_slice.py` 纯函数核心。
  - 复用 `panel-review` 的整条派发链(反锚定闸、任务冻结、setsid 抗断线、typed 终态、健康池):
    每个工作项 = 一次钉住单腿的 `panel-review --scoped-review`。panel-review 只加最小开关。
  - 切片结果 `review_contract_version=2`,旧覆盖谓词天然不认;切片模式拒绝 `--track`、不写 observation。
  - `bin/subcodex`:只读 GPT 评审腿(review/explore),模型单源 `bin/codex-model`;作为**角色腿**,
    不进 panel-review 的普通轮换池(GPT 也是默认执行腿,进池会审到自家代码)。
  - 判据 + 变异红检 + 文档(panel skill / legs.md / README)。
- 真实最小运行:用真腿跑一次小切片评审,核实工具限制、终态和预算计数。

## Non-goals

- 不改 `high=两家族全量` 的归档语义,不让切片结果进入任何 track 的覆盖计数(GPT 计划的 P3 正式策略、P4 历史对照都留给后续单)。
- 不做自动切片器、动态任务图、递归 agent、每片默认双审、跨代码版本复用评审证据。
- 不把 GPT 放进普通 panel-review 轮换池。
- 不在本单处理 GPT 今天另两件未提交的活(Grok 接入、Kimi 换 K2.8):已原样 stash 到
  `stash@{0}` / 分支 `backup/gpt-grok-kimi-20260913`,本单归档后放回并重跑总闸。
