# Proposal: glm-5-3-default

- Date: 2026-08-20
- Status: accepted

## Goal

把 aiwork 的 GLM agent 腿与 chat fallback 默认模型从 GLM-5.2 切到 OpenCode Go 已开放的 GLM-5.3。

## Motivation

当前 Go 订阅 key 的 `/models` 已返回 `glm-5.3`，官方 Go 文档也已列出该模型；继续固定 5.2
会让后续评审腿错过已可用的新默认档。

## 真问题(第一性)

- 用户原话:「你帮我切换吧」
- 真正要解决的是:后续 GLM agent/chat 默认调用实际使用 5.3，而不只是证明端点里看得到它。
- 我在这中间翻译了什么:「切换」解释为同时切 agent 与 chat fallback 的默认值；显式
  `ZHIPU_MODEL` override 仍保持原语义。

## Scope

- in: `bin/subagent`、`bin/subchat` 的 GLM 默认模型与对应判据。

## Non-goals

- 不改 OpenCode Go 端点、认证、权限、轮次上限或其他模型腿。
