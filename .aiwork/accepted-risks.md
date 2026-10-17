# 已接受风险

业主已经接受、评审时不当问题报的风险（见 [aiwork 的 REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md) 第二节）。在 `.aiwork/` 下，属于判卷面：加一条、改一条都要业主批准。

1. **放行关卡的结论只能「最终一致」**：上限和原因见 `gate/README.md`「已知限制」和「合并」两节。业主接受于 2026-10-12（aiwork 关卡验收，`gate/ACCEPTANCE.md`）。
2. **把 main 合进 PR 分支后，GitHub 会把业主之前的批准挪到新提交上**，关卡因此不要求业主在新提交上重新批准。改了内容的推送不会被挪；评审机器人的 PASS 不会被挪，新提交上仍要重新评审；合并 main 时手工解决冲突的情况没有测过。证据见 `gate/ACCEPTANCE.md`「发现」。业主接受于 2026-10-12。

3. **Mac 上测试的断网保护挡不住经本机服务出网的几条路**：Mac 没有独立的网络命名空间，沙箱只管测试进程自己发出的连接，本机 127.0.0.1 上的代理等服务和整台机器共用。哪几条挡住了、哪几条挡不住，见 `tests/_no_egress.py` 文件头「Mac 上出网的路」。这道闸本来只堵手滑，不堵故意。Linux 上没有这条。业主接受于 2026-10-16（[PR #53](https://github.com/SunJ1ayu/aiwork/pull/53)）。

4. **DeepSeek 腿在 Linux 服务器上跑的命令能上网、能使用这条腿的密钥**：Claude Code 的命令沙箱在这台服务器上起不来；此风险持续到搬去 Mac、由 Claude Code 自带沙箱接管为止。出处：[#39「逐条腿实测表」及 2026-10-17「方案 A」](https://github.com/SunJ1ayu/aiwork/issues/39)。由业主合并本条的 PR 时批准。
