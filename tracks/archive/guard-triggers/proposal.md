# Proposal: guard-triggers

- Date: 2026-08-06
- Status: open

## Goal

把当天自查暴露的三个"没有守卫的地方"补成机械的:
① `track-guard` 只在 bump 版本号时触发,而 `/root/aiwork` 没有版本号 ⇒ 那个仓的改动
永远不会被要求挂 track;② fast lane 的反锚定没有闸(`panel-review` 有,`submimo review` 没有);
③ **`/root/aiwork` 压根没装 pre-commit hook** —— 守卫住在这个仓里,却从没在这个仓生效过。

## Motivation

用户当天原话:「这不是昨天优化的工作流吗 还是没用啊 还是会漏东西对吧」。
拆开看:当天新装的**机械**件全都响了(花名册抓到超时腿、反锚定第三臂点名 verify.md、
恢复自证抓到混合树、清单驱动暴露孤儿脚本);而漏掉的四条**没有一条在守卫覆盖内**
(lane 没被问 / fast lane 没先落自审 / 新入口没真派过 / stash 先斩)。
⇒ 不是"工作流没用",是**守卫边界没动**,而我当天优化的恰好是自己没走的那条路。

## 真问题(第一性)

- 用户原话:「还是会漏东西对吧」。
- 真正要解决的是:**让"我这次走的这条路"也有闸**,而不是再加三条要我记得的约定。
- 我在这中间翻译了什么:把"下次记得"翻译成"三个触发器"。风险:触发器选错门(前两例
  都是这么栽的),所以每条都配红检,而且第③条专门用来查"门上到底有没有锁"。

## Scope

- in: `track-guard` 规矩4(动评审/派活工具与判据 ⇒ 要挂 track);
  `bin/_my-review-gate.sh` 共享闸 + submimo/subchat/subagent 三条躯干接上;
  `/root/aiwork` 装 hook;`tests/test-hooks-installed.sh` 定期问"锁还在吗"。

## Non-goals

- 不给"新入口没真派过"和"stash 先斩"加规矩:它们和上面那些是同一类自觉物,
  再加三条只会稀释现有的。前者靠下一次真派活兑现,后者记进教训即可。
