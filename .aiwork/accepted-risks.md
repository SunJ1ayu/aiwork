# 已接受风险

业主已经接受、评审时不当问题报的风险（见 [aiwork 的 REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md) 第二节）。在 `.aiwork/` 下，属于判卷面：加一条、改一条都要业主批准。

1. **放行关卡的结论只能「最终一致」**：上限和原因见 `gate/README.md`「已知限制」和「合并」两节。业主接受于 2026-10-12（aiwork 关卡验收，`gate/ACCEPTANCE.md`）。
2. **把 main 合进 PR 分支后，GitHub 会把业主之前的批准挪到新提交上**，关卡因此不要求业主在新提交上重新批准。改了内容的推送不会被挪；评审机器人的 PASS 不会被挪，新提交上仍要重新评审；合并 main 时手工解决冲突的情况没有测过。证据见 `gate/ACCEPTANCE.md`「发现」。业主接受于 2026-10-12。

3. **Mac 上测试的断网保护挡不住经本机服务出网的几条路**：Mac 没有独立的网络命名空间，沙箱只管测试进程自己发出的连接，本机 127.0.0.1 上的代理等服务和整台机器共用。哪几条挡住了、哪几条挡不住，见 `tests/_no_egress.py` 文件头「Mac 上出网的路」。这道闸本来只堵手滑，不堵故意。Linux 上没有这条。业主接受于 2026-10-16（[PR #53](https://github.com/SunJ1ayu/aiwork/pull/53)）。

4. **DeepSeek 腿在 Linux 服务器上跑的命令能上网、能使用这条腿的密钥**：Claude Code 的命令沙箱在这台服务器上起不来；此风险持续到搬去 Mac、由 Claude Code 自带沙箱接管为止。出处：[#39「逐条腿实测表」及 2026-10-17「方案 A」](https://github.com/SunJ1ayu/aiwork/issues/39)。由业主合并本条的 PR 时批准。

5. **Mac 上 Kimi、MiMo 的 review / explore 没有系统级只读保护**：按 [#39「业主 2026-10-18 定（选 2）」](https://github.com/SunJ1ayu/aiwork/issues/39)，这两条腿只配置只读工具；跑完由 `bin/_reader_tools.py` 核对实际工具记录，证明不了只用了只读工具就不发评审；`review-pr` 每次重试重建快照和任务文件（`bin/_leg_session.py`）。这些措施不能阻止 CLI 本身、配置失效或未记录的行为写文件，也不能撤销已经发生的写入；HOME、凭证等快照外路径仍不受系统级保护。不经过 `review-pr`、`explore`，直接拿真仓库调用 `subkimi`、`submimo` 时，Mac 上真仓库也没有写保护。Linux 上继续经过 `ro-repo-exec`。本条由业主在本任务单授权加入，合并本 PR 时批准。
