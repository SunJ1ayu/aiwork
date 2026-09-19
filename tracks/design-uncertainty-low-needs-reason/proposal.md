# Proposal: 填 low 不许零成本

- Date: 2026-09-19
- 业主原话：「能出现这种问题说明我们的 aiwork 还是有问题,这么多模型其实还是
  只管住了功能实现正确,没管方案设计的合理性」

0.98.7「启动时立即更新」发版后业主一用就发现打开软件要干等。查 decision.json:
`impact=high`(外审预算 2 真的走了)、**`design.uncertainty=low` + `premise_attack=not_required`
+ 空 evidence** ⇒ premise attack / 双出 / panel-explore 整条设计防线**被一个自述字段全关掉**。
规格里白纸黑字写着「检查超过 35 秒中断」,两家外审都看过、判据还专门验过它,
**没有一个人问过「让用户等 35 秒本身合理吗」** —— 因为评审问的是"实现对不对",
只有发散才会问"为什么不后台查"。

这是 [[self-narrated-fields-dont-guard]] 的第二次发作(第一次是 verify.md 的「派给:」,
四单复制同一句有洞的理由 ⇒ 模型分层整晚没运转)。同样是我自己填、没人查、一填就关掉一串动作。

## 改法

`track-record validate --phase dispatch`:`design.uncertainty=low` 时 evidence 不许为空,
且必须指向 track 内真实存在的工件 —— 填 low 要说得出"方向为什么是确定的"写在哪。
high 那一侧一行不动。

## 准入理由(对照 CLAUDE.md 的硬规矩准入标准)

刹车类:**真出过事**(0.98.7 已发版、业主实际受影响)+ **git 一眼可查**
(archive/opendesign-auto-update-countdown/decision.json 里 uncertainty=low)。够门槛。
