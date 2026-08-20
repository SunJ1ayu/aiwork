#!/usr/bin/env bash
# 唯一规范源 + 部署副本判据(workflow-control-plane T7)。
# Run: bash /root/aiwork/tests/test-workflow-docs.sh
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/workflow"
DEPLOY_ROOT="${WORKFLOW_DEPLOY_ROOT:-/root}"
SYNC="$ROOT/bin/sync-workflow-docs"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

MAPPINGS=(
  "CLAUDE.md|CLAUDE.md"
  "skills/track/SKILL.md|.claude/skills/track/SKILL.md"
  "skills/panel/SKILL.md|.claude/skills/panel/SKILL.md"
  "skills/panel/references/legs.md|.claude/skills/panel/references/legs.md"
  "skills/delegate/SKILL.md|.claude/skills/delegate/SKILL.md"
)

echo "=== workflow docs oracle ==="
echo "[W1] Git 内唯一源与当前部署副本逐字节一致"
for spec in "${MAPPINGS[@]}"; do
  src="${spec%%|*}"; dst="${spec#*|}"
  cmp -s "$SOURCE/$src" "$DEPLOY_ROOT/$dst"
  check "W1: $src == 部署 $dst" $?
done

echo "[W2] 同步器只管固定清单，漂移默认拒绝、显式 force 才覆盖"
if [[ -x "$SYNC" ]]; then
  d="$(mktemp -d)"; outside="$(mktemp)"; printf 'outside\n' > "$outside"
  "$SYNC" --target-root "$d" --check >/dev/null 2>&1; rc=$?
  check "W2: 空部署根 --check 必须报漂移" $([[ $rc -ne 0 ]]; echo $?)

  "$SYNC" --target-root "$d" >/dev/null 2>&1; rc=$?
  check "W2: 缺失的受管文件可安全首次安装" $([[ $rc -eq 0 ]]; echo $?)
  for spec in "${MAPPINGS[@]}"; do
    src="${spec%%|*}"; dst="${spec#*|}"
    cmp -s "$SOURCE/$src" "$d/$dst" || rc=1
  done
  check "W2: 首次安装后所有受管文件逐字节一致" "$rc"

  mkdir -p "$d/.claude"; printf 'settings-sentinel\n' > "$d/.claude/settings.json"
  printf 'local-edit\n' >> "$d/CLAUDE.md"
  "$SYNC" --target-root "$d" >/dev/null 2>&1; rc=$?
  check "W2: 已有副本漂移时默认拒绝覆盖" $([[ $rc -ne 0 ]]; echo $?)
  grep -q 'local-edit' "$d/CLAUDE.md"
  check "W2: 拒绝后现场改动仍在" $?

  "$SYNC" --target-root "$d" --force >/dev/null 2>&1; rc=$?
  check "W2: 显式 --force 才更新已漂移受管文件" $([[ $rc -eq 0 ]]; echo $?)
  cmp -s "$SOURCE/CLAUDE.md" "$d/CLAUDE.md"
  check "W2: force 后回到唯一源字节" $?
  grep -qx 'settings-sentinel' "$d/.claude/settings.json"
  check "W2: settings 等非清单现场零触碰" $?
  "$SYNC" --target-root "$d" --check >/dev/null 2>&1; rc=$?
  check "W2: 同步后的 --check 通过" $([[ $rc -eq 0 ]]; echo $?)

  rm -f "$d/CLAUDE.md"; ln -s "$outside" "$d/CLAUDE.md"
  "$SYNC" --target-root "$d" --force >/dev/null 2>&1; rc=$?
  check "W2: 受管目标是符号链接时即使 force 也拒绝" $([[ $rc -ne 0 ]]; echo $?)
  grep -qx 'outside' "$outside"
  check "W2: 不会沿链接覆盖清单外文件" $?
  rm -rf "$d"; rm -f "$outside"
else
  bad "W2: bin/sync-workflow-docs 存在且可执行"
fi

echo "[W3] 文档说的默认预算、模型和 agent 档与实现一致"
grep -q -- '--risk self|standard|high' "$ROOT/README.md"
check "W3: README 公开 self/standard/high 风险档" $?
grep -q -- '--all' "$ROOT/README.md" && ! grep -q 'all three' "$ROOT/README.md"
check "W3: README 说明健康池二审与显式全审，不再声称固定三审" $?

for f in "$SOURCE/CLAUDE.md" "$SOURCE/skills/track/SKILL.md" "$SOURCE/skills/panel/SKILL.md"; do
  grep -q 'impact-risk' "$f" && grep -q 'design-uncertainty' "$f" && grep -q 'high=2' "$f"
  check "W3: ${f#$SOURCE/} 使用两个正交轴且 high=2" $?
done

grep -q 'OC_MODEL_ID="glm-5.3"' "$ROOT/bin/subagent" \
  && grep -q '默认模型 `glm-5.3`' "$SOURCE/skills/panel/references/legs.md"
check "W3: GLM 唯一源与实现都是 5.3" $?
grep -q 'DEFAULT_MAX_TURNS=200' "$ROOT/bin/subagent" \
  && grep -q '轮次上限.*\*\*200\*\*' "$SOURCE/skills/panel/references/legs.md"
check "W3: DeepSeek 唯一源与实现都是 200 turns" $?
grep -q 'KIMI_TIMEOUT:-1500' "$ROOT/bin/subkimi" \
  && grep -q 'KIMI_TIMEOUT.*默认 1500' "$SOURCE/skills/panel/references/legs.md"
check "W3: Kimi 唯一源与实现都是 1500s" $?
grep -q 'DEFAULT_MODEL="xiaomi/mimo-v2.5-pro"' "$ROOT/bin/submimo" \
  && grep -q 'xiaomi/mimo-v2.5-pro' "$SOURCE/skills/panel/references/legs.md"
check "W3: MiMo 唯一源与实现模型一致" $?

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
