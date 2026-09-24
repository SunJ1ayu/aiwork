# Proposal: drop-dead-best-authoritative

- Date: 2026-09-24
- Status: open

## Goal

删掉 `bin/track-record` 里 `panel_review_coverage` 的 `best_authoritative`(计算 + 返回键):
`arbiter-resolves-split-review` 修第 1 轮 #3 时 ledger 改用自己的权威组选择,它从此没有读者(该单 verify.md #8 延期)。

## 真问题(第一性)

- 用户原话(09-24):「你确定是没人用的死代码还需要开评审吗」;更早:「不要留下屎山」。
- 核实:`grep -rn best_authoritative /root/aiwork`(除 logs/ 与已归档记录)只剩定义(1241)与返回(1279);
  track-record 被其它工具当命令调用,输出里不含这个键;design-studio 与 skills 零引用。
- impact=self:行为不变的删除,外部评审预算 0;证据 = 零读者 + 断网离线总闸全绿。

## Scope / Non-goals

- in:只删这一段与返回键。不改任何行为、判据、文档。
