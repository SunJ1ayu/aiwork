# Proposal: subchat-merge

- Date: 2026-07-05
- Status: open

## Goal

把 `bin/subsense`(88 行)与 `bin/subglm`(94 行)这对 >90% 同构的复制粘贴合并为一个
provider 参数化的 `bin/subchat <provider> review TASK LOG [REPO]`;`subsense`/`subglm`
保留为两行 exec 兼容垫片,对外接口、env 变量名、日志标签全部不变。

## Motivation

- 双胞胎已经咬过人:V2 的 `set -f` 修复被迫在两个文件里各写一遍;以后每个 bug 都要双写,
  漏一边就是隐患(review-tooling debt queue #2,用户 07-04 拍板 07-05 做)。
- 未来加第 4 家 chat-completions reviewer 时只需在 provider 表加一行。

## Scope

- in: 新建 `bin/subchat`(provider 表:sensenova / zhipu);`bin/subsense`、`bin/subglm`
  改为 exec 垫片;oracle 相应调整(V2 拷贝垫片时需连带 subchat)+ 新增 subchat 自身用例。

## Non-goals

- 不动 `submimo`(不同底座,agent 模式,不是同构对)。
- 不动引擎 `bin/submimo-review`、`panel-review`、`panel-explore`、CLAUDE.md——垫片保证零改动。
- 不做 fix 支持(维持 review-only,fix 路线另见 panel-reviewer-agent-base-idea)。
- 不改任何 env 变量名 / 默认模型 / auth 文件路径(纯重构,行为特征化保持)。
