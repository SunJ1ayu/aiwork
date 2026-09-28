# Proposal: glm-leg-doc-truth

- Date: 2026-08-27
- Status: accepted

## Goal

让 aiwork 所有活文档、帮助文本与判据注释如实描述当前 GLM 路径：默认
`subglm-agent` 使用原生 OpenCode CLI，聊天腿只是回落，当前 agent 端点为
`/zen/go/v1`；同时保留 `glm-5.3-flash` 与 `ZHIPU_MODEL` 的既有行为。

## Motivation

上一单只验证了模型字符串与单一 override，未验证同一文档里关于底座、默认腿和端点的
叙述是否互相矛盾，因此测试全绿时仍存在会误导下一次维护的旧说明。

## 真问题(第一性)

- 用户原话:「那你开始吧」；承接上一轮检查出的 aiwork 文档残留。
- 真正要解决的是:让维护者从活文档得到的当前运行契约与代码实际执行路径一致。
- 我在这中间翻译了什么:不仅改 Markdown，也修正帮助文本和承重测试注释，并补机械防回归；
  历史 track、备份和沿革句不追改。

## Scope

- in:GLM 当前默认腿、底座、端点、override 的文档与注释；README 执行腿地图；
  workflow 员工枚举；对应文档一致性判据与部署副本同步。

## Non-goals

- 不改运行逻辑、模型、端点、认证、权限、评审预算或健康池。
- 不改历史 track、任务、日志和备份中的当时记录。
