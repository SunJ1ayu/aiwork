# Tasks: codex-worktree-delegation

- base-ref: a6d65f088544e3a27bb5b8efa22ba88787ba5693

> 当前只完成 Codex 独立方向落盘。实现任务必须等 Claude Code 对抗、用户收敛、
> 主 agent 写 oracle 并单独 commit 后再开始。

## Design convergence

- [x] T0 Claude Code 按 proposal 接手协议：先不读本 design 的技术方案，独立落一版方向到
      `/root/aiwork/logs/codex-worktree-delegation-claude-independent.md`。
      (08-11 15:24 写,断线丢盘,15:57 从会话记录逐字节取回;独立性成立。)
- [x] T1 Claude Code 重新检查当前 `delegate-codex`、delegate skill、track 约定和最近真实工件，
      对 design 的 12 条攻击清单逐条给代码/行为依据。
      (12 条见 design「六」;三条攻击有机器收据,见 `evidence/`。)
- [~] T2 把两份方向合并回 design 的“Claude Code 对抗与合并”，明确采纳、驳回、开放问题；
      与用户拍板最终范围、工具边界和是否包含 Phase C。
      **合并已写回 design;三条待拍板见 design「七」,用户没点头前 Status 保持 draft。**
- [x] T3 先建立耗时基线：从真实 verify/日志记录单腿执行、主 agent 验收、返工、集成各自耗时，
      不用印象宣称并行是瓶颈。
      (三个真实样本:note-source 100 分钟前置 / 4.5 分钟执行;owner-consent ≈12 分钟执行、
      收货跨夜;anydoc 22 分钟执行 / 53 分钟收货。原始时间戳在 `logs/` 与两仓 git log 里。)

> **T4 起的实现任务全部冻结**:范围由 design「五」改写过(只剩 Phase A,且多一条前置 P0),
> 下面的 T7–T21 是 Codex 原方案的分解,**不再是选定方向**,拍板后按新范围重写。
> 其中 **T17–T21(Phase C)已驳回**,理由见 design「二」。

## Oracle first

- [ ] T4 主 agent 亲写隔离、归因、恢复、集成、清理 oracle；判卷路径全部列入 protect。
- [ ] T5 对 oracle 做结构攻击和变异设计，回答“全绿但混了腿/丢了现场/复用了旧绿会怎样”。
- [ ] T6 oracle 单独 commit，并在实现不存在时红检；红必须落在目标断言，不是 build/环境错误。

## Phase A — serial isolation

- [ ] T7 实现唯一 job id、manifest 原子写、显式 base 和 worktree prepare/status。
- [ ] T8 以外层编排复用 `delegate-codex`，显式传 job worktree、唯一 log 和现有 attack/protect。
- [ ] T9 实现 receive：复用闸①，记录完整实际写集、diff hash 和 SCOPE_DRIFT，不自动判 VERIFIED。
- [ ] T10 实现崩溃恢复和保守 cleanup；未集成唯一工作、dirty/untracked、未知路径一律拒绝清理。
- [ ] T11 跑全套 oracle + 变异测试；主 agent 亲读 diff。
- [ ] T12 用若干真实任务做**串行隔离**试点，在各自 verify 写返工/自身错误/耗时原始事实。

## Phase B — integration artifacts

- [ ] T13 明确 candidate commit 由谁、在何时形成；执行腿仍不得 merge/push/归档。
- [ ] T14 实现 per-job lock、短 registry lock、per-repo integration lock及重复命令幂等/拒绝语义。
- [ ] T15 实现串行 integration，记录旧 base 与新 integration base；冲突停止并保留全部现场。
- [ ] T16 强制集成后用 runlog 重跑完整 oracle、回归、build；旧 worktree 的绿不得复用。

## Phase C — bounded parallel (only if evidence earns it)

- [ ] T17 根据基线账决定是否继续；若主 agent 验收才是瓶颈，记录结论并停止在串行隔离。
- [ ] T18 实现 batch 预检：同基线、无依赖、声明写集无交集、无共享副作用，并发硬上限 2。
- [ ] T19 用两个假 Codex 证明真实并发、独立失败、日志/receipt 不碰撞；全套变异测试转绿。
- [ ] T20 选两个低风险独立任务做真实试点，核对 `/usage` 前后、wall-clock、验收队列和集成成本。
- [ ] T21 只在真实收益为正且没有新增错归因/现场丢失时，决定是否把并行开放为常用选项。

## Verify and documentation

- [ ] T22 主 agent 独立自审先落盘，再走 `full` panel；失败腿、降级和 off 状态从 roster 原样引用。
- [ ] T23 对所有发现逐条仲裁；尤其审清 cleanup、路径验证、旧绿复用和控制面可写性。
- [ ] T24 更新 `delegate` skill、`/root/CLAUDE.md`（只有形成新的硬规矩才改）、
      `/root/aiwork/README.md`（只描述已经存在的机械能力），避免提前写未来状态。
- [ ] T25 最终部署验证：从 PATH 调到的真实入口打印预期版本/帮助，跑一次隔离 job 回显 manifest；
      PASS 后归档 track。

