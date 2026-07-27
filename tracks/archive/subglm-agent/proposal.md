# Proposal: subglm-agent

- Date: 2026-07-05
- Status: open

## Goal

给 panel 的 GLM 腿升级 agent 底座:新建 `bin/subglm-agent`(Claude Code 壳 ×
智谱 Anthropic 兼容端点),让 GLM reviewer 自主 Read/Grep 仓库做 review,
根治 chat 腿的盲评/手动喂料之痛;panel-review 默认换用 agent 腿,chat 腿保留可切回。

## Motivation

- panel-reviewer-agent-base-idea 记忆里挂起的债,今天(subchat-merge 收口时)又复发
  一次:aiwork 非 git 仓,diff 为空,只能手动 export INCLUDE 喂文件。
- 已查证:ZCode 是智谱官方桌面 ADE(GUI,无无头模式),npm 的 zcode-cli 是占名壳;
  Claude Code 是智谱官方 coding-plan 支持工具 → 壳选 Claude Code。
- 活体 spike 已通过:按量付费 key + `ANTHROPIC_BASE_URL=open.bigmodel.cn/api/anthropic`
  + `claude -p --model sonnet` + `ANTHROPIC_DEFAULT_SONNET_MODEL=glm-4.6` → 正常应答。

## Scope

- in: `bin/subglm-agent`(review-only,读写硬隔离)、panel-review GLM 腿默认切 agent
  (`PANEL_GLM_LEG=chat` 回退)、oracle 新增 V9。

## Non-goals

- 不动 subsense 腿(SenseNova 无 Anthropic 端点;弱模型上 agent 循环性价比存疑)。
- 不做 fix 能力(review-only 语义不变;fix 仍归 submimo fix)。
- 不改 `~/.claude/settings.json`(智谱 env 只随 wrapper 进程注入,绝不落到主 harness 配置)。
- 不删 chat 版 subglm/subchat(保留为回退腿)。
- 引擎侧"diff 空自动 INCLUDE"折中:agent 腿落地后 GLM 侧痛点消失,本 track 不做,
  留给 subsense 复发时再议。
