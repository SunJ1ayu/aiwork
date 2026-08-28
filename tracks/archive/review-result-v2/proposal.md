# Proposal: review-result-v2

- Date: 2026-08-27
- Status: open

## Goal

建立唯一 ReviewLegResult v2 contract、normalizer 与 coverage predicate，消灭
`rc=0 + UNKNOWN` 等假 coverage，同时保留 Claude 的最终裁决权。

## Motivation

现有 panel、archive、ledger、health 与 metrics 会分别解释进程码、日志和 verdict；
37 条历史腿中只有 14 条明确且非 degraded，继续扩 reviewer 不会修复证据语义。

## 真问题(第一性)

- 用户原话:「P0 第一目标是消灭假 coverage，而不是让数字好看。」
- 真正要解决的是:只有完成可信审查的腿才能计入 family coverage。
- 我在这中间翻译了什么:进程状态、裁决、对象、证据完整性和模型调用必须分别记录，
  coverage 只能由同一机械 predicate 推导。

## Scope

- in: v2 typed result、v1 只读兼容、subject digest、持久 locator、各现有 adapter
  最小迁移、同 run 同 subject coverage。

## Non-goals

- aiwork-core 重构、Skill/Plugin/MCP、reviewer 扩池、跨-run archive 放行。
