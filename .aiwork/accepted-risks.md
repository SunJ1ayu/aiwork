# 已接受风险

业主已经接受、评审时不当问题报的风险（见 [aiwork 的 REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md) 第二节）。在 `.aiwork/` 下，属于判卷面：加一条、改一条都要业主批准。

1. **放行关卡的结论只能「最终一致」**：上限和原因见 `gate/README.md`「已知限制」和「合并」两节。业主接受于 2026-10-12（aiwork 关卡验收，`gate/ACCEPTANCE.md`）。
2. **把 main 合进 PR 分支后，GitHub 会把业主之前的批准挪到新提交上**，关卡因此不要求业主在新提交上重新批准。改了内容的推送不会被挪；评审机器人的 PASS 不会被挪，新提交上仍要重新评审；合并 main 时手工解决冲突的情况没有测过。证据见 `gate/ACCEPTANCE.md`「发现」。业主接受于 2026-10-12。
