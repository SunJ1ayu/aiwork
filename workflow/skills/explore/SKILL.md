---
name: explore
description: 大改动方向未定时，让几条腿各自对同一份题面提方案。
---

# explore

评审与修复规则见 [REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md)。
这里只说明 `explore` 怎么用。方案不发到 GitHub，也不自动比较或挑选。

## 用法

```bash
explore BRIEF --repo DIR --leg subdeepseek-agent --leg submimo
```

`BRIEF` 写目标、已有事实、约束，以及还待核实的前提。`--repo` 是目标仓库；每条腿只读它本地 main（不会先 fetch）的一份快照。`--leg` 可重复，被点名的腿并行跑。

先写下自己的判断，再看各家方案。方案要用代码或小实验核实，不按票数采纳。

每条腿的最后一条消息写到本机数据目录 `explore/<题面名>-<时间>/<腿>.md`（`aiwork-config data-path`）。命令结束时打印这些路径。某一条腿失败时，其余腿已经写好的文件保留，退出码非零，并写明是哪条腿、什么原因。

## 五条腿

超时没设时，`explore` 给该腿 2400 秒。下面的环境变量若已设置，用那个值。

失败时先看命令打出的那一行原因：`timeout` 是到点，`auth` 是凭证，`quota` / `rate_limit` 是额度或窗口，`runtime` 后面带该腿 stderr 的末尾。没有报告文件时，原因是腿没有交出最后一条消息。

- `subdeepseek-agent explore TASK LOG REPO` — Claude Code headless。凭证 `~/.config/deepseek/auth.json`。超时 `DEEPSEEK_TIMEOUT`。
- `subkimi explore TASK LOG REPO` — `kimi -p`。凭证 `~/.local/share/aiwork/kimi-review-home/credentials/kimi-code.json`。超时 `KIMI_TIMEOUT`。
- `submimo explore TASK LOG REPO` — `mimo run`。凭证 `~/.local/share/mimocode/auth.json`。超时 `MIMO_CLI_TIMEOUT`。
- `subcursor explore TASK LOG REPO` — `cursor-agent`。凭证 `~/.config/cursor/auth.json`。超时 `CURSOR_TIMEOUT`。
- `subcodex explore TASK LOG REPO` — `codex exec`。凭证 `~/.codex/auth.json`。超时 `SUBCODEX_TIMEOUT`。
