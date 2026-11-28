# 已接受风险

业主已经接受、评审时不当问题报的风险（见 [aiwork 的 REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md) 第二节）。在 `.aiwork/` 下，属于判卷面：加一条、改一条都要业主批准。

1. **放行关卡的结论只能「最终一致」**：上限和原因见 [gate/README.md](https://github.com/SunJ1ayu/aiwork/blob/0e2b46067a17afb70a54fc4dbbc2aa6d03f41949/gate/README.md)「已知限制」和「合并」两节。业主接受于 2026-10-12（aiwork 关卡验收，[gate/ACCEPTANCE.md](https://github.com/SunJ1ayu/aiwork/blob/0e2b46067a17afb70a54fc4dbbc2aa6d03f41949/gate/ACCEPTANCE.md)，[PR #33 的业主批准](https://github.com/SunJ1ayu/aiwork/pull/33#pullrequestreview-5488563140)）。
2. **把 main 合进 PR 分支后，GitHub 会把业主之前的批准挪到新提交上**，关卡因此不要求业主在新提交上重新批准。改了内容的推送不会被挪；评审机器人的 PASS 不会被挪；关卡自动同步时是否沿用原评审，见 `gate/README.md`「合并」（[业主决定](https://github.com/SunJ1ayu/aiwork/issues/205#issuecomment-7088746460)）；合并 main 时手工解决冲突的情况没有测过。证据见 [gate/ACCEPTANCE.md](https://github.com/SunJ1ayu/aiwork/blob/0e2b46067a17afb70a54fc4dbbc2aa6d03f41949/gate/ACCEPTANCE.md)「发现」。业主接受于 2026-10-12（[PR #33 的业主批准](https://github.com/SunJ1ayu/aiwork/pull/33#pullrequestreview-5488563140)）。

4. **DeepSeek 腿在 Linux 服务器上跑的命令能上网、能使用这条腿的密钥**：Claude Code 的命令沙箱在这台服务器上起不来；本条只适用于 Linux 服务器。出处：[PR #56 的业主批准](https://github.com/SunJ1ayu/aiwork/pull/56#pullrequestreview-5556373830)及 [PR #71 的业主批准](https://github.com/SunJ1ayu/aiwork/pull/71#pullrequestreview-5649588696)。由业主合并本条的 PR 时批准。

7. **关卡写不了本轮新结论时，提交上可能保留上一次的放行**：App 发不出检查、策略不合法、开着的 PR 列不全，或运行在占位之前被取消、超时，都可能使旧 success 留在网页上。服务端已写成 success、但写回响应丢失时，网页也可能显示 success；已创建但尚未写完的 App 占位则停在 in_progress。本轮无法完成检查写回时不合并该 head。残留的旧放行借不来：main 只许 `aiwork-gate` App 通过 PR 更新，管理员不在绕过名单；关卡合并时按现状重算，不复用旧结论（流程见 `gate/README.md`「合并」）。这是[业主 2026-11-01 拆掉保险丝的决定](https://github.com/SunJ1ayu/aiwork/issues/111#issuecomment-6552793090)的直接后果；规则配置见[同日补记](https://github.com/SunJ1ayu/aiwork/issues/111#issuecomment-6552923695)。本条由业主在本任务单授权加入，合并本 PR 时批准。

8. **两个 PR 共用同一个 head 时，派发器可能把已合并的 PR 报成失败**：[PR #241](https://github.com/SunJ1ayu/aiwork/pull/241) 引入的派发器收尾判断中，关卡合并第一单后，合并第二单时遇到临时状态、把共享的关卡检查改回进行中，第一单的派发器收尾找不到「完成且成功」的检查，会在极少数情况下多发一条错误的失败通知，不会合错（[业主 2026-11-26 决定](https://github.com/SunJ1ayu/aiwork/issues/246#issuecomment-7243951745)）。出处写法按[业主 2026-11-28 决定](https://github.com/SunJ1ayu/aiwork/issues/246#issuecomment-7243962545)：由业主合并本条的 PR 时批准。
