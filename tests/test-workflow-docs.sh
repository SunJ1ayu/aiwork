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
grep -q -- '--all.*current reviewer pool' "$ROOT/README.md" \
  && grep -q '全池评审' "$SOURCE/skills/panel/SKILL.md"
check "W3: README/panel skill 把 --all 表述为全池语义，不绑定四审或五审" $?

for f in "$SOURCE/CLAUDE.md" "$SOURCE/skills/track/SKILL.md" "$SOURCE/skills/panel/SKILL.md"; do
  grep -q 'impact-risk' "$f" && grep -q 'design-uncertainty' "$f" && grep -q 'high=2' "$f"
  check "W3: ${f#$SOURCE/} 使用两个正交轴且 high=2" $?
done

grep -q 'DEFAULT_MODEL="glm-5.3-flash"' "$ROOT/bin/subagent" \
  && ! grep -q 'OC_MODEL_ID=' "$ROOT/bin/subagent" \
  && grep -q '默认模型 `glm-5.3-flash`' "$SOURCE/skills/panel/references/legs.md"
check "W3: GLM 默认是 5.3 Flash，agent 没有第二模型源" $?
grep -q 'AGENT_BASE="opencode"' "$ROOT/bin/subagent" \
  && grep -q 'OC_BASE_URL="https://opencode.ai/zen/go/v1"' "$ROOT/bin/subagent" \
  && grep -q 'GLM_LEG="${PANEL_GLM_LEG:-agent}"' "$ROOT/bin/panel-explore" \
  && grep -q '当前 agent =' "$SOURCE/skills/panel/references/legs.md" \
  && grep -q '`opencode.ai/zen/go/v1`(OpenAI-compatible provider base)' "$SOURCE/skills/panel/references/legs.md" \
  && grep -q 'agent 腿(默认).*opencode CLI' "$SOURCE/skills/panel/references/legs.md"
check "W3: GLM 当前默认路径是 opencode agent，文档端点与实现一致" $?
! grep -Eq '就是 GLM 的默认腿|default=chat|默认档必须.*聊天腿|08-18 起不是了|GLM 跑在 Claude Code 壳上|底座腿那边的.*x-api-key' \
  "$ROOT/bin/subchat" "$ROOT/tests/test-review-tooling.sh" "$SOURCE/skills/panel/references/legs.md" \
  && ! grep -q 'agent = `opencode.ai/zen/go`' "$SOURCE/skills/panel/references/legs.md"
check "W3: 活文档和承重注释不再把聊天腿或 Claude 壳写成当前默认" $?
grep -q 'subdeepseek-agent' "$ROOT/README.md" \
  && grep -q 'subglm-agent' "$ROOT/README.md" \
  && bash "$ROOT/bin/subagent" -h 2>&1 | grep -q 'dormant for OpenCode GLM'
check "W3: README 列出默认 agent wrapper，帮助文本标清休眠变量" $?
grep -q 'Gemini' "$SOURCE/CLAUDE.md"
check "W3: 主工作流员工枚举包含 Gemini" $?
grep -q 'DEFAULT_MAX_TURNS=200' "$ROOT/bin/subagent" \
  && grep -q '轮次上限.*\*\*200\*\*' "$SOURCE/skills/panel/references/legs.md"
check "W3: DeepSeek 唯一源与实现都是 200 turns" $?
grep -q 'KIMI_TIMEOUT:-1500' "$ROOT/bin/subkimi" \
  && grep -q 'KIMI_TIMEOUT.*默认 1500' "$SOURCE/skills/panel/references/legs.md"
check "W3: Kimi 唯一源与实现都是 1500s" $?
grep -q 'DEFAULT_MODEL="xiaomi/mimo-v2.5-pro"' "$ROOT/bin/submimo" \
  && grep -q 'xiaomi/mimo-v2.5-pro' "$SOURCE/skills/panel/references/legs.md"
check "W3: MiMo 唯一源与实现模型一致" $?

echo "[W4] 唯一源与同步器本身属于 judging surface"
. "$ROOT/bin/_tooling-paths.sh"
is_judging_surface "bin/sync-workflow-docs"
check "W4: 同步写口受 track 归属守卫保护" $?
is_judging_surface "workflow/CLAUDE.md" \
  && is_judging_surface "workflow/skills/panel/SKILL.md"
check "W4: 唯一规范源受 track 归属守卫保护" $?

echo "[W5] typed decision 是新 track 唯一机器事实源，旧 lane 不再混进现行模板"
d="$(mktemp -d)"; mkdir -p "$d/typed-doc"
sed 's/__NAME__/typed-doc/g' "$ROOT/track/templates/decision.json" > "$d/typed-doc/decision.json"
"$ROOT/bin/track-record" validate --phase shape "$d/typed-doc" >/dev/null 2>&1
check "W5: decision 模板本身通过 shape validator" $?
rm -rf "$d"

! grep -qE '^-[[:space:]]*(Verdict|lane|派给):' "$ROOT/track/templates/verify.md"
check "W5: 新 verify 模板不复制 verdict/lane/派给" $?
grep -q 'decision.json' "$ROOT/track/CONVENTION.md" \
  && ! grep -q 'verify.md → panel-review.*, by lane' "$ROOT/track/CONVENTION.md" \
  && ! grep -q 'verify 那边会填 `lane: full`' "$ROOT/track/templates/design.md"
check "W5: convention/design 现行语义只讲双轴" $?
grep -q 'decision.json' "$SOURCE/skills/track/SKILL.md" \
  && grep -q 'track-record.*validate.*dispatch' "$SOURCE/skills/track/SKILL.md" \
  && ! grep -q '`lane:` 和 `派给:` 守卫仍查非空' "$SOURCE/CLAUDE.md"
check "W5: workflow 要求 dispatch 前填 decision 并机械校验" $?
! grep -q '唯一账本 = 各 track 的 `verify.md`' "$SOURCE/skills/delegate/SKILL.md" \
  && ! grep -q '只留原始事实.*返工 N 轮' "$SOURCE/skills/delegate/SKILL.md"
check "W5: delegate 不再要求手工返工账或 verify 第二事实源" $?

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
