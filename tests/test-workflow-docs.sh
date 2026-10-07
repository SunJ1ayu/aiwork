#!/usr/bin/env bash
# 唯一规范源 + 部署副本判据(workflow-control-plane T7)。
# Run: bash /root/aiwork/tests/test-workflow-docs.sh
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/workflow"
SYNC="$ROOT/bin/sync-workflow-docs"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

MAPPINGS=(
  "CLAUDE.md|CLAUDE.md"
  "skills/panel/SKILL.md|.claude/skills/panel/SKILL.md"
  "skills/panel/references/legs.md|.claude/skills/panel/references/legs.md"
  "skills/delegate/SKILL.md|.claude/skills/delegate/SKILL.md"
)

echo "=== workflow docs oracle ==="
# 家目录里那份部署副本是本机状态。同步器对临时目录的行为由下面 W2 问;
# 这台机器的副本是否跟上,不在仓库判据里。

echo "[W2] 同步器只管固定清单，漂移默认拒绝、显式 force 才覆盖"
if [[ -x "$SYNC" ]]; then
  d="$(mktemp -d)"; outside="$(mktemp)"
  mkdir -p "$d/.claude/skills/track"
  printf 'retired deployed skill: cleanup after merge\n' > "$d/.claude/skills/track/SKILL.md"
  printf 'outside\n' > "$outside"
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
  grep -qx 'retired deployed skill: cleanup after merge' "$d/.claude/skills/track/SKILL.md"
  check "W2: 退役 track 部署副本留给合并后清理，同步器不删除它" $?
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

echo "[W3] 流程规则只有一个来源:说明文档指向 REVIEW-RULES.md,且没有任何文档要求自定风险等级或评审预算"
for f in "$ROOT/README.md" "$SOURCE/CLAUDE.md" "$SOURCE"/skills/*/SKILL.md "$SOURCE"/skills/*/references/*.md; do
  grep -q 'REVIEW-RULES.md' "$f"
  check "W3: ${f#$ROOT/} 指向 REVIEW-RULES.md" $?
done
for f in "$ROOT/README.md" "$SOURCE/CLAUDE.md" "$SOURCE"/skills/*/SKILL.md "$SOURCE"/skills/*/references/*.md; do
  ! grep -qE 'impact-risk|design-uncertainty|--risk |self/standard/high|self=0|standard=1|high=2|评审预算|decision\.json|lane:|必须挂.*track|--track NAME' "$f"
  check "W3: ${f#$ROOT/} 没有自定风险等级/评审预算的旧流程" $?
done
[[ ! -e "$SOURCE/skills/track/SKILL.md" ]] && ! grep -q 'skills/track' "$ROOT/bin/sync-workflow-docs"
check "W3: track skill 已退役,且不在 sync-workflow-docs 清单里" $?
grep -q -- '--all.*current reviewer pool' "$ROOT/README.md" \
  && grep -q '全池评审' "$SOURCE/skills/panel/SKILL.md"
check "W3: README/panel skill 把 --all 表述为全池语义，不绑定四审或五审" $?

echo "[W3] 文档说的默认模型和 agent 档与实现一致"

# 🔴 2026-09-04(track gemini-leg-38,DeepSeek F1 抓到的):W3 给 glm / mimo 都钉了
# 「文档说的默认档 == 代码里的默认档」,**唯独 gemini 没钉** ⇒ 3.7→3.8 那天
# `workflow/skills/panel/references/legs.md` 还写着 3.7、还引着 3.7 的选型实测,
# 而 W3 照样 36/36 全绿。文档是代码的第二份拷贝,没有闸盯着它就一定会过期。
grep -q 'model gemini' "$ROOT/bin/subgemini" \
  && grep -q 'models.env.*gemini' "$SOURCE/skills/panel/references/legs.md"
check "W3: Gemini 默认模型只指向本机设置，文档不复制版本号" $?

grep -q 'model glm' "$ROOT/bin/subagent" \
  && ! grep -q 'OC_MODEL_ID=' "$ROOT/bin/subagent" \
  && grep -q 'models.env.*glm' "$SOURCE/skills/panel/references/legs.md"
check "W3: GLM 默认模型来自本机设置，agent 没有第二模型源" $?
grep -q 'AGENT_BASE="opencode"' "$ROOT/bin/subagent" \
  && grep -q 'OC_BASE_URL="https://opencode.ai/zen/go/v1"' "$ROOT/bin/subagent" \
  && grep -q 'GLM_LEG="${PANEL_GLM_LEG:-agent}"' "$ROOT/bin/panel-explore" \
  && grep -q '当前 agent =' "$SOURCE/skills/panel/references/legs.md" \
  && grep -q '`opencode.ai/zen/go/v1`(OpenAI-compatible provider base)' "$SOURCE/skills/panel/references/legs.md" \
  && grep -q 'agent 腿(默认)' "$SOURCE/skills/panel/references/legs.md" \
  && grep -q '底座是 opencode CLI' "$SOURCE/skills/panel/references/legs.md"
check "W3: GLM 当前默认路径是 opencode agent，文档端点与实现一致" $?
! grep -Eq '就是 GLM 的默认腿|default=chat|默认档必须.*聊天腿|08-18 起不是了|GLM 跑在 Claude Code 壳上|底座腿那边的.*x-api-key' \
  "$ROOT/bin/subchat" "$ROOT/tests/test-review-tooling.sh" "$SOURCE/skills/panel/references/legs.md" \
  && ! grep -q 'agent = `opencode.ai/zen/go`' "$SOURCE/skills/panel/references/legs.md"
check "W3: 活文档和承重注释不再把聊天腿或 Claude 壳写成当前默认" $?
grep -q 'subdeepseek-agent' "$ROOT/README.md" \
  && grep -q 'subglm-agent' "$ROOT/README.md" \
  && bash "$ROOT/bin/subagent" -h 2>&1 | grep -q 'dormant for OpenCode GLM' \
  && bash "$ROOT/bin/subagent" -h 2>&1 | grep -q 'DeepSeek ~/.config/deepseek/auth.json' \
  && bash "$ROOT/bin/subagent" -h 2>&1 | grep -q 'OpenCode GLM ~/.config/opencode-go/auth.json' \
  && ! grep -q 'fix-capable base would be Claude Code' "$ROOT/bin/subchat"
check "W3: README 列出默认 agent wrapper，帮助文本标清休眠变量" $?
grep -q 'Gemini' "$SOURCE/CLAUDE.md"
check "W3: 主工作流员工枚举包含 Gemini" $?
grep -q 'DEFAULT_MAX_TURNS=200' "$ROOT/bin/subagent" \
  && grep -q '轮次上限.*\*\*200\*\*' "$SOURCE/skills/panel/references/legs.md"
check "W3: DeepSeek 唯一源与实现都是 200 turns" $?
grep -q 'KIMI_TIMEOUT:-1500' "$ROOT/bin/subkimi" \
  && grep -q 'KIMI_TIMEOUT.*默认 1500' "$SOURCE/skills/panel/references/legs.md"
check "W3: Kimi 唯一源与实现都是 1500s" $?
grep -q 'aiwork-config.*model mimo' "$ROOT/bin/submimo" \
  && ! grep -q 'DEFAULT_MODEL="xiaomi/' "$ROOT/bin/submimo" \
  && grep -q 'models.env.*mimo' "$SOURCE/skills/panel/references/legs.md"
check "W3: MiMo 默认模型来自本机设置，文档不复制版本号" $?

echo "[W4] 操作流程与保留的方法"
grep -q '最新 main' "$SOURCE/CLAUDE.md" \
  && grep -q 'tests/' "$SOURCE/CLAUDE.md" \
  && grep -q '机器人' "$SOURCE/CLAUDE.md" \
  && grep -q '停下' "$SOURCE/CLAUDE.md"
check "W4: 任务通过分支、实现、全测、机器人 PR 收尾" $?
grep -q '另一家族' "$SOURCE/CLAUDE.md" \
  && grep -q 'review-pr.*沙箱外' "$SOURCE/CLAUDE.md" \
  && grep -q 'review-pr' "$SOURCE/skills/panel/SKILL.md"
check "W4: 正式评审在 PR 上使用沙箱外 review-pr" $?
grep -q '不改考卷让自己及格' "$SOURCE/CLAUDE.md" \
  && grep -q '不信执行腿的自述' "$SOURCE/CLAUDE.md"
check "W4: 保留判据核实与收货方法" $?
grep -q -- '--no-track' "$SOURCE/skills/delegate/SKILL.md" \
  && grep -q -- '--receive' "$SOURCE/skills/delegate/SKILL.md"
check "W4: 委托保留隔离收货，用 --no-track" $?
grep -q '~/.config/aiwork/' "$SOURCE/CLAUDE.md" \
  && grep -q '~/.local/share/aiwork/' "$SOURCE/CLAUDE.md"
check "W4: 设置与运行数据的本机目录明确" $?

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
