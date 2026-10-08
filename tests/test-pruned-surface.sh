#!/usr/bin/env bash
# 删评审腿、删 panel 之后，仓库里只留五条评审腿，不再点名已删除的命令。
# 本文件是这份判据自己的名单，扫描时排除自己。README 的 History 段是历史记录。
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

KEEP=(subdeepseek-agent subkimi submimo subcursor subcodex)
for name in "${KEEP[@]}"; do
  [[ -f "$ROOT/bin/$name" ]]
  check "留下 $name" $?
done

# 名字在判据里拼出来，避免本文件变成仓库里的残留引用。
piece() { printf '%s' "$1"; }
GONE_FILES=(
  "bin/$(piece sub)$(piece glm)"
  "bin/$(piece sub)$(piece glm)-agent"
  "bin/$(piece sub)$(piece gemini)"
  "bin/$(piece sub)$(piece gemini)-diag"
  "bin/$(piece sub)$(piece grok)"
  "bin/_$(piece grok)-stream.py"
  "bin/$(piece sub)$(piece deepseek)"
  "bin/$(piece sub)$(piece chat)"
  "bin/$(piece sub)$(piece mimo)-review"
  "bin/$(piece panel)-review"
  "bin/$(piece panel)-slice"
  "bin/_$(piece panel)_slice.py"
  "bin/$(piece panel)-explore"
  "bin/$(piece panel)-roster"
  "bin/$(piece panel)-candidates"
  "bin/_$(piece panel)_candidates.py"
  "bin/_$(piece panel)-roster-lib.sh"
  "bin/_my-review-gate.sh"
  "workflow/skills/$(piece panel)/SKILL.md"
)
for path in "${GONE_FILES[@]}"; do
  [[ ! -e "$ROOT/$path" ]]
  check "已删除 $path" $?
done

python3 - "$ROOT" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
names = [
    "subglm-agent", "subglm", "subgemini-diag", "subgemini", "subgrok",
    "_grok-stream", "panel-review", "panel-slice", "panel-explore",
    "panel-roster", "panel-candidates", "_panel_slice", "_panel_candidates",
    "_panel-roster-lib", "CHAT_LEGS", "route_task",
]
# 聊天版 subdeepseek 不是 subdeepseek-agent。
chat = re.compile(r"(?<![\w-])subdeepseek(?!-agent)")
skip = {"tests/test-pruned-surface.sh"}
hits = []
for path in root.rglob("*"):
    if not path.is_file() or ".git" in path.parts:
        continue
    rel = path.relative_to(root).as_posix()
    if rel in skip:
        continue
    text = path.read_text(encoding="utf-8", errors="replace")
    if rel == "README.md":
        parts = re.split(r"(?m)^## ", text)
        text = "".join(part for part in parts if not part.startswith("History"))
    for name in names:
        if name in text:
            hits.append(f"{rel}: {name}")
    if chat.search(text):
        hits.append(f"{rel}: subdeepseek")
if hits:
    print("\n".join(hits[:40]))
    sys.exit(1)
PY
check "除本判据和 README History 外，没有已删名字" $?

claude="$ROOT/workflow/CLAUDE.md"
grep -q 'Codex、Cursor、DeepSeek、Kimi、MiMo' "$claude" \
  && grep -q '每个通道都能写代码也能评审；同一个 PR 的评审要换一家，由关卡判断' "$claude" \
  && ! grep -q 'GLM' "$claude" \
  && ! grep -q "$(piece panel)-explore" "$claude"
check "通道说明是留下的五家，并写明换评审由关卡判断" $?

! grep -q '角色腿' "$ROOT/bin/subcodex" \
  && ! grep -q '不进轮换池' "$ROOT/bin/subcodex"
check "subcodex 开头不再写角色腿或不进轮换池" $?

grep -q '只查没登记进总跑的孤儿套件' "$ROOT/README.md"
check "README 的 coverage-only 说明是查孤儿套件" $?

! grep -R -n -E '只能评审|只能执行|review-only|role-only|角色腿' \
  --exclude-dir=.git --exclude=test-pruned-surface.sh "$ROOT" >/dev/null
check "仓库里不写某条腿只能执行或只能评审" $?

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
