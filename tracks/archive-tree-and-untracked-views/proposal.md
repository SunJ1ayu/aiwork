# Proposal: archive-tree-and-untracked-views

- Date: 2026-09-09
- Status: open

## Goal

把 `review-delivery-binding` 归档时留下的两笔账(D15/D16)一起还掉:
① 已归档 track 的复验不再锁在**第一次**归档那棵树上;
② 「评审看 working、归档闸看 staged」这条语义差不再以**一句指错方向的 BLOCK**
收场 —— 要么提前响亮拒绝,要么把真原因说出来。

## Motivation

两笔都不是推理,是我这一轮**亲手复现**的(收据:
`evidence/20260909T065614Z-01-probe-d15-d16.txt`):

- **D15**:夹具里 归档#1 → 手工取回 → **改掉被交付的 `source.py`** → 归档#2,
  中间没有任何新评审,`track-record validate --phase archive --source staged`
  仍然 **rc=0**。也就是**一轮旧评审授权了一份新交付** —— 这正是这道闸存在的理由。
  根因在 `bin/track-record:465-470`:`git log --reverse --diff-filter=A` 取**首行**,
  锁定的是 decision.json 第一次被 add 的那次提交。
- **D16**:评审时仓里只要有未跟踪文件,评审绑定的 working 指纹就含它,而归档那次
  commit 的 hook 校验 staged(不含)⇒ 必然 BLOCK。**比账本里写的更难看的一点**:
  这道闸打印的药方是 "rerun panel-review after content changes",我照着做了一次 ——
  重跑之后 **rc 仍然是 1**。药方无效,而每转一圈烧掉一整轮 panel(2 条腿)。
  消息里既没提未跟踪文件,也没给另一视图的指纹,操作者没有任何线索。

## 真问题(第一性)

- 用户原话:「在优化aiwork」/ 对"开 D15/D16 那一单吗"答「ok的」。
- 真正要解决的是:**这道判卷防线现在两头都会骗人** —— 一头(D15)对真drift说 PASS,
  一头(D16)对没drift的正常收口说 BLOCK 还指错方向。两头都会侵蚀"闸说的话可信"。
- 我在这中间翻译了什么:业主说的是"优化 aiwork",我把它翻译成"还 WORKFLOW-DEBT
  最新那一条",而不是"重构工作流"。依据是账本自己写着「合并开一单」,
  且这两笔是**唯一有现场收据**的账。**没翻译的部分**:D1~D14 还敞着,本单不碰。

## Scope

- in: `bin/track-record` 归档复验取树、`bin/_review_delivery.py` 视图语义、
  `bin/track archive` 的前置拒绝、`tests/test_review_delivery.py` 判据、
  `tests/mutation-review-delivery.sh` 红检。
- in: 把两视图的语义差**写成判据**(现在只在干净夹具上平凡满足)。

## Non-goals

- 不动 delivery 投影的策略版本(policy 1)、不改评审腿看到的快照语义。
- 不还 D1~D14。
- 不改 panel 花名册/预算/腿的任何行为。
- 归档**之后**对仓内**其它**文件的提交修改,本单不试图纳入复验(理由与边界写在 design)。
