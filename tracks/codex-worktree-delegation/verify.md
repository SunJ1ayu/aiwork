# Verify: codex-worktree-delegation

- Date: 2026-08-11
- Verdict: NEEDS_MORE_INFO

> 当前只完成 Codex 独立方向草案，尚未完成 Claude Code 对抗、oracle、实现或机器验证。
> 此处的 NEEDS_MORE_INFO 是真实状态，不代表 BLOCK，也不代表方案已选定。

## Design gate

- [x] Codex 独立方向先落盘
- [x] Claude Code 独立方向落盘（读 Codex design 之前）
      —— `/root/aiwork/logs/codex-worktree-delegation-claude-independent.md`
- [x] Claude Code 对抗清单逐条完成（design「六」12 条；三条攻击带机器收据）
- [ ] 两份方向合并并由用户确认 —— **合并已写回 design，待用户拍板 design「七」三条**
- [x] 最终 design 明确 Phase C 是本单范围还是后续独立 track
      —— **两者都不是:驳回**。上游供给被 oracle 铁律堵死，要重开先证明供给约束变了。

## Mechanical checks

- [ ] oracle 在实现前红检
- [ ] serial-isolation oracle passes
- [ ] recovery/cleanup oracle passes
- [ ] integration oracle passes
- [ ] bounded-parallel oracle passes（若 Phase C 入本单）
- [ ] mutation tests pass
- [ ] existing review-tooling regression passes
- [ ] no secrets / unsafe ops

实现判据仍然一条都没有(实现没开始)。但**设计期的三条前提已经用机器答过**,收据如下
(设计探针,不是 oracle —— 别把它当验收):

```
runlog: probe-design-assumptions rc=0 commit=a6d65f0 dirty=yes at=2026-08-11T08:54:30Z file=tracks/codex-worktree-delegation/evidence/20260811T085430Z-01-probe-design-assumptions.txt
runlog: live-gate1-on-real-run rc=0 commit=a6d65f0 dirty=yes at=2026-08-11T08:54:59Z file=tracks/codex-worktree-delegation/evidence/20260811T085459Z-01-live-gate1-on-real-run.txt
```

- P1 新建 worktree 被「攻题记录过期」闸**恒真拒发**(主树 rc=0 / worktree rc=2)⇒ Phase A 前置。
- P2 `--repo /root/aiwork` + 默认日志被「卷宗不许进仓」闸拒发 ⇒ 本单实现不能派给 codex。
- P3 派活后主 agent 改判据 ⇒ 闸① 判红且红在主 agent 头上;**今天真单上就是这个状态**。

可重跑:`tracks/codex-worktree-delegation/probe-isolation-assumptions.sh`(全在临时仓,
只对 `/root/aiwork` 和 design-studio 做只读/拒发路径的探测,不花额度、不写真仓)。

## Expected review

- lane: **full**
  - 理由:新增执行入口、git worktree/分支生命周期、控制面状态和清理动作；
    它同时影响判卷可信度与文件安全，针孔再薄也不能降档。
- 派给: **主 agent 直接干(08-11 对抗后定)**
  - oracle 必须由主 agent 亲写;
  - **实现也不派 codex**:P2 实测 `--repo /root/aiwork` 走现有入口直接拒发(卷宗落仓内),
    而绕开它就等于让"被改的执行入口"自己当验收边界。这条和本单原来的顾虑同向,现在有实测。
  - 状态机与 cleanup 已驳回(design 四·2/四·4),没有"要不要外包"的问题了。
- 规格自查:
  - 规格可能错在把“执行腿慢”当作瓶颈；真实账可能显示主 agent 验收才是瓶颈；
  - 规格可能错在把“文件不相交”当作独立；共享协议、缓存、端口和生成物可产生语义冲突；
  - 规格可能错在状态机过重，仪式成本超过串行隔离收益；
  - 规格也可能过松：worktree 隔离了写入，却没隔离共享外部副作用或控制面读取；
  - 接法:基线耗时账、真实 sandbox 探针、并发临时仓 oracle、集成后全量判据、保守 cleanup 变异。
- 腿的花名册: 待实际 panel 生成 roster 后原样粘贴
- findings: 实现期的 full 审待跑。**设计期的对抗已做完**,三条带收据的发现在 design「一」;
  其中「规格可能错在把执行腿慢当瓶颈」这条自查**已被耗时账坐实**(三个真实样本,tasks T3)。
  注意 A3 是**两份方向都没有、由现场实测抓到**的 —— 印证"孤发现"往往来自跑一遍,不是读一遍。
- arbitrated verdict: 待实现与 full review 后由主 agent填写

## Pilot acceptance thresholds

上线有界并行之前至少满足：

- serial isolation 真实任务中没有混合 diff、主工作树污染或现场丢失；
- 崩溃/失败/范围漂移均能从 job id 恢复和单独处理；
- 两任务试点无日志/receipt 碰撞，无自动清理，无旧绿复用；
- 集成后全量判据覆盖最终 commit；
- 并行的总 wall-clock 在计入主 agent 验收与集成后仍有明确正收益；
- 没有为了提速降低 protect、attack、红检、review lane 或断网强度。

若最后一条收益不成立，允许结论为：**Phase A/B PASS，Phase C 不采用**。
这不是失败，而是用证据避免给工作流增加无收益的调度复杂度。

## Accepted deviations

- None。目前尚未进入实现，任何偏离都必须在最终 verify 重新记账。
