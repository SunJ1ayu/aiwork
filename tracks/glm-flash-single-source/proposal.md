# Proposal: glm-flash-single-source

- Date: 2026-08-27
- Status: accepted

## Goal

把 GLM 评审腿默认切到 OpenCode Go 的 `glm-5.3-flash`，并让 agent 与 chat
两条执行路径都从同一个已解析变量 `MODEL` 取实际模型，使 `ZHIPU_MODEL` 真正成为
统一的运行时切换入口。

## Motivation

Go 已开放且真实工具调用通过的 Flash 档约为当前 5.3 七倍请求额度；现实现却让
opencode agent 路径绕过已经解析好的 `ZHIPU_MODEL`，继续读取第二个硬编码
`OC_MODEL_ID`。这使“切模型”在表面上有统一入口、实际主路径却不响应，是比多改几处
更危险的静默分叉。

## 真问题(第一性)

- 用户原话:「可以，你遵循第一性原理来吧」
- 真正要解决的是:模型选择只有一个运行时事实源；同一 provider/协议内换档时，不再联动
  端点、认证、权限或底座配置，也不出现 agent/chat 暗中跑不同模型。
- 我在这中间翻译了什么:结合上一轮已确认的建议，把“可以”解释为同时执行默认切换与
  单源修复；“第一性原理”解释为先消灭绕过已解析 `MODEL` 的第二事实源，而不是新增一层
  通用配置框架。

## Scope

- in: GLM agent/chat 默认模型、agent 对 `ZHIPU_MODEL` 的统一消费、对应行为判据、唯一文档源
  与部署副本。

## Non-goals

- 不改 OpenCode Go 端点、key、认证 header、provider 包、权限、沙箱、轮次或超时。
- 不抽象整个 provider 表、不新增运行时配置文件；两个独立入口保留各自的 standalone
  fallback，但运行时覆盖语义必须一致。
- 不改其他评审腿。
