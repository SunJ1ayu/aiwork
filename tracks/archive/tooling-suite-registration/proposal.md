# Proposal: tooling-suite-registration

- Date: 2026-08-18
- Status: open

## Goal

把 `tests/test-evidence-lifetime.sh` 挂进 `bin/rust-check-review-tooling` 的 `SUITES` 名单,
让本仓总跑真的会跑它。**改动是一行**,但它补的是一个**五天的空窗**。

## Motivation

`test-evidence-lifetime.sh` 由 `25c5394`(track `evidence-lifetime-gate`,08-13)建成并归档,
**但从来没被挂进任何总跑名单**。已核实,不是推测:

- `git show ef6a7ab:bin/rust-check-review-tooling`(该单归档时的版本)里,`SUITES` 最后一条是
  `no-egress`,**没有 evidence-lifetime**;
- 该单的 `verify.md` 里 grep `rust-check|SUITES|总跑|名单`,**零命中**。

⇒ 08-13 到 08-17 的五天里,这条判据**一次都没被跑过**。它守的是"归档时拦下引用会话临时目录
的工件"这道闸 —— 一条没人跑的闸,和没有这条闸的区别只在心理上。

## 真问题(第一性)

- 用户原话:「一起收掉」(指 `/root/aiwork` 里那个 08-17 一直没提交的小改动)。
- 真正要解决的是:**不是"提交一行未提交的改动"**,而是"这一行为什么会存在" ——
  它是 08-17 我发现空窗后顺手加的补丁,加完没跑没提交就搁下了。
  真问题是:**新判据建成 ≠ 判据在跑**,而这两件事之间目前只靠人记得。
- 我在这中间翻译了什么:用户说的是"收掉那个改动"(一个 git 卫生动作),
  我把它读成"补一道五天没人看的闸"(一个防线动作)。**这次转译我认为站得住**,
  理由是那一行改的位置就是判卷防线的注册表;但要记账:如果转译错了,
  代价是为一行 git 卫生动作起了一个 track,成本大于收益。

## Scope

- in: `bin/rust-check-review-tooling` 的 `SUITES` 加一行 evidence-lifetime。
- in: 亲跑总跑,确认这条**真的被跑到**(不是名字在名单里而整块 SKIP —— 老教训:
  「`pytest 全绿` 那句话里不含整块 SKIP 的闸」)。

## Non-goals

- **不动 `test-evidence-lifetime.sh` 本身**(它今天上午刚被 `b033029` 收窄过规则,已过判据)。
- **不去修"名单是手列的"这个结构病**。文件头 08-06 已经写明:硬堵会把运维脚本
  拖进来造成误报,所以当时的决定是「只报不拦」(总跑每次列一次 `bin/` 里的漏网可执行文件)。
  本单不推翻那个决定 —— 但**记一笔明账**:那个漏网报告只看 `bin/`,
  **看不见 `tests/` 里新建却没被注册的判据**,所以它结构上不可能报出本单这个空窗。
  这是同一种病(孤儿脚本)的第三次复发,值得单独一单去想触发器,不在这单里做。
