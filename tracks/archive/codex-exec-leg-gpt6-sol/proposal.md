# Proposal: codex-exec-leg-gpt6-sol

- Date: 2026-09-25
- Status: open

## Goal

codex 干活腿(delegate-codex)默认模型换成 gpt-6-sol,并与评审腿 subcodex 共用一处单源 `bin/codex-model`。

## 真问题(第一性)

- 用户原话:09-25「顺便把我们codez腿换到gpt6sol吧」「用该改一个模型名就行了对吧」。
- 事实:09-23(track codex-leg-gpt6-sol)已把 `bin/codex-model` 换成 gpt-6-sol,但那只管评审腿 subcodex;
  干活腿 delegate-codex 在自己脚本里写死 `MODEL="gpt-5.5"`,派活说明书也三处写着 gpt-5.5 ⇒ 当时漏了它。
- 我在中间翻译了什么:「改一个模型名」→ 改成读同一处单源(两处各写一份正是这次漏掉的原因);`--model` 仍可单次覆盖。

## Scope / Non-goals

- in:`bin/delegate-codex` 默认模型读 `bin/codex-model`;`workflow/skills/delegate/SKILL.md` 三处 gpt-5.5 说法(+ 部署副本同步)。
- 不做:不改 subcodex、不改 `bin/codex-model`(已是 gpt-6-sol)、不改 delegate-codex 的任何闸。
