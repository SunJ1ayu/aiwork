# Proposal: opencode-go-leg

- Date: 2026-08-18
- Status: open

## Goal

把**第三条评审腿(GLM 腿)**的后端从智谱开放平台 bigmodel 换到 **OpenCode Go**
($10/月订阅,业主 08-18 买的),模型 `glm-4.6v` → `glm-5.2`。壳不换、kimi 腿不动。

## Motivation

bigmodel 那把 key 欠费(1113 / 429),这条腿 **2026-08-04 起在 panel-review 里默认关着** ——
"四审"实际长期只有三腿,已经两周。业主买了 OpenCode Go 订阅,GLM-5.2 在它上面
每 5 小时约 880 次请求,评审腿这种用量绰绰有余。

## 真问题(第一性)

- 用户原话:「把我们第四条评审腿挂opencode go上 这是api key:… 用GLM 5.2」
  → 追加澄清:「不是建新的腿」「就把我们额度过期的智谱腿换成这个不就好了吗」
  「不能不换壳只走api key吗」「kimi 腿别动」「是glm的那个腿」
  「你先找一下glm有没有官方的底座 如果有就按mimo kimi一样包自己的底座就好了」
- 真正要解决的是:**那条腿没钱了,给它换个有钱的入口**,不是扩编、不是换工具链。
- 我在这中间翻译错过一次:头一版我把"第四条腿"读成了"新建一条挂 opencode CLI 的腿",
  已经装了 opencode、起了 review home ——**被业主连纠三次掰回来**。记在这里是因为
  这次转译错的代价是真金白银的时间,而线索一开始就有(他说的是"额度过期的那条")。

## Scope

- in: `subagent` / `subchat` 供应商表里 zhipu 那一格(端点、key 文件、默认模型、
  **认证 header 风格**);`panel-review` 把 GLM 腿默认开回来;判据;legs.md 文档。
- in: 官方底座调研结论(业主点名要查)—— 结论写进 design.md。

## Non-goals

- 不建新腿、不换壳(Claude Code 仍是 GLM 底座腿的壳)。
- **不碰 kimi 腿**(业主明令),也不碰 deepseek/mimo 两条腿。
- 不把别的腿也搬到 OpenCode Go(Go 上确实有 kimi/deepseek/mimo,但那是另一单,
  要单独算账:一把订阅额度被四条腿分,和现在各走各的账不是一回事)。
