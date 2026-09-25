#!/usr/bin/env bash
# 冒烟:delegate-codex 不给 --model 时,默认模型取自 bin/codex-model(空跑,不建树不派活不调模型)
set -u
echo "bin/codex-model = $(cat /root/aiwork/bin/codex-model)"
/root/aiwork/bin/delegate-codex --task /tmp/claude-0/-root/a9cb8b30-9425-48d4-86a6-6ce1bda0ed4c/scratchpad/dry/task.md --repo /tmp/claude-0/-root/a9cb8b30-9425-48d4-86a6-6ce1bda0ed4c/scratchpad/dry/repo --attack-log /tmp/claude-0/-root/a9cb8b30-9425-48d4-86a6-6ce1bda0ed4c/scratchpad/dry/attack.log --protect a.txt --no-track --dry-run --log /tmp/claude-0/-root/a9cb8b30-9425-48d4-86a6-6ce1bda0ed4c/scratchpad/dry/run.log 2>&1 | grep -E 'model='
echo "--- 显式 --model 仍可覆盖:"
/root/aiwork/bin/delegate-codex --task /tmp/claude-0/-root/a9cb8b30-9425-48d4-86a6-6ce1bda0ed4c/scratchpad/dry/task.md --repo /tmp/claude-0/-root/a9cb8b30-9425-48d4-86a6-6ce1bda0ed4c/scratchpad/dry/repo --attack-log /tmp/claude-0/-root/a9cb8b30-9425-48d4-86a6-6ce1bda0ed4c/scratchpad/dry/attack.log --protect a.txt --no-track --dry-run --model gpt-5.6-sol --log /tmp/claude-0/-root/a9cb8b30-9425-48d4-86a6-6ce1bda0ed4c/scratchpad/dry/run2.log 2>&1 | grep -E 'model='
