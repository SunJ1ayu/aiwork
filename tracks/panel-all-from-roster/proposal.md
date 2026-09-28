# Proposal: panel-all-from-roster

- Date: 2026-08-26
- Status: completed (kept active because external-review coverage was explicitly skipped)

## Goal

让 `panel-review --all` 始终派出当前花名册中所有已启用、可执行的评审腿，且帮助、规范与证据链不再把评审池大小写死为某个数字。

## Motivation

新增第五条腿后，花名册已经有五条，但 `--all` 仍把预算写死为 4；README、帮助和 panel skill 也沿用“所有评审/四审”的旧说法。数字同时散落在派发与 observation schema，导致加减腿必须多处同步，并且命令名与实际行为不一致。

## 真问题(第一性)

- 用户原话:“对我们现在也不是四审了 是五审 我觉得这个数量没必要一直改 有没有什么办法表示一下，不然我们加一条腿或者少一条腿都要回来改这个数字吧”
- 真正要解决的是:评审数量是花名册的派生属性，不应成为独立配置或文档事实；`--all` 的稳定语义应是“全池评审”。
- 我在这中间翻译了什么:把“不要再改四/五”落实为单一真源——派发数量从 `PANEL_LEGS_ORDER` 派生，observation 只受字节上限约束，用户文档只描述全池语义。

## Scope

- in: `--all` 动态预算、动态帮助、observation 去数字上限、相关契约测试与现行文档措辞。

## Non-goals

- 不改变 self/standard/high 的 0/1/2 默认风险预算及条件追加一条 spare 的行为。
- 不重跑外部评审；本轮按用户要求只做主审与机械验证。
