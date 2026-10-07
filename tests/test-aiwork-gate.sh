#!/usr/bin/env bash
# 关卡逻辑（假事件、假 API）和接入 workflow 的形状。从仓库内容推导 policy 清单的用例留在 OpenDesign。
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/_no-egress.sh" || exit 78
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT" || exit 78
out="$(node --test "$ROOT"/tests/test_aiwork_gate*.mjs 2>&1)"
rc=$?
printf '%s\n' "$out"
pass="$(printf '%s\n' "$out" | sed -n 's/^# pass \([0-9][0-9]*\)$/\1/p' | tail -1)"
fail="$(printf '%s\n' "$out" | sed -n 's/^# fail \([0-9][0-9]*\)$/\1/p' | tail -1)"
echo "total: ${pass:-0} passed, ${fail:-0} failed"
exit "$rc"
