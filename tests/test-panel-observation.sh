#!/usr/bin/env bash
# panel-review dispatch oracle. External legs are stubs.
# Asks whether each roster leg actually runs, and whether budget 0 dispatches none.
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Test fixtures use a stable model independently of the operator's model choice.
export CURSOR_MODEL=composer-2.5
# 腿名单的唯一源。判据自己也不许抄第二份。
. "$ROOT/bin/_panel-roster-lib.sh"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

# 这套判据会在外层 panel 的 PANEL_ORACLE_CMD 里被调用。入口不清掉它，
# 下面每个桩 panel 又会递归启动整套总闸。
check "P0: 套件入口清理外层 PANEL_ORACLE_CMD，桩 panel 不递归跑总闸" \
  $([[ -z "${PANEL_ORACLE_CMD:-}" ]]; echo $?)

make_leg_stubs() { # bindir —— 每条腿铺一个健康桩(两种命名都铺)
  local b="$1" leg bin_name
  for leg in "${PANEL_LEGS_ORDER[@]}"; do
    for bin_name in "$leg" "$leg-agent"; do
      cat > "$b/$bin_name" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$0")" >> "$PANEL_TEST_CALLS"
if [[ -n "${PANEL_TEST_TASKS:-}" ]]; then
  printf '%s\t%s\n' "$2" "$(sha256sum "$2" | cut -d' ' -f1)" >> "$PANEL_TEST_TASKS"
fi
printf 'Conclusion: PASS\n' > "$3"
# 健康桩要像真腿:只给裁决不给 facts 的腿在契约下不可计数，调度器会为它补一条腿。
case "${AIWORK_REVIEW_ADAPTER:?}" in
  submimo) model=xiaomi/mimo-v2-flash ;;
  subdeepseek-agent|subdeepseek) model=deepseek-chat ;;
  subglm-agent) model=go/glm-4.5 ;;
  subglm) model=glm-4.5 ;;
  subkimi) model=kimi-code/k2.5 ;;
  subgemini) model=gemini-2.5-pro ;;
  subgrok) model=grok-fixture ;;
  subcursor) model=composer-2.5 ;;
esac
object_format="$(git -C "$4" rev-parse --show-object-format)"
head_oid="$(git -C "$4" rev-parse HEAD)"
tree_oid="$(git -C "$4" rev-parse 'HEAD^{tree}')"
python3 "${AIWORK_REVIEW_RESULT_BIN:?}" facts --output "${AIWORK_REVIEW_FACTS_PATH:?}" \
  --requested-model "$model" --invoked-model "$model" --reported-model "$model" \
  --git-object-format "$object_format" --head-oid "$head_oid" \
  --index-tree-oid "$tree_oid" --worktree-tree-oid "$tree_oid" \
  --view-delivery-state complete --view-mode full_snapshot --evidence-completeness complete
exit 0
EOF
      chmod +x "$b/$bin_name"
    done
  done
}

make_fixture() { # root
  local d="$1" b="$1/bin" repo="$1/repo"
  mkdir -p "$b" "$repo" "$d/raw" "$d/state"
  cp "$ROOT/bin/panel-review" "$b/panel-review"
  cp "$ROOT/bin/_panel-roster-lib.sh" "$ROOT/bin/aiwork-config" "$ROOT/bin/_aiwork_config.py" "$ROOT/bin/_review_result.py" "$b/"
  make_leg_stubs "$b"
  printf '# PANEL_PROMPT_SENTINEL\n' > "$d/task.md"
  ( cd "$repo"; git init -q -b main; git config user.email t@t; git config user.name t
    printf 'x\n' > app.txt; git add -A; git commit -qm init )
}

echo "=== panel dispatch oracle ==="
d="$(mktemp -d)"; make_fixture "$d"; calls="$d/calls"
common=(--no-my-review "$d/task.md" "$d/repo")

echo "[P5] self budget=0 不派外腿"
: > "$calls"
PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state" PANEL_STAGGER_MAX=0 \
  bash "$d/bin/panel-review" --risk self --budget 0 \
  "${common[@]}" "$d/raw/self" >/dev/null 2>&1; rc=$?
check "P5: self/budget 0 正常成功" $([[ $rc -eq 0 ]]; echo $?)
check "P5: budget 0 的 external dispatch_count 为 0" $([[ ! -s "$calls" ]]; echo $?)

echo "[P7pre] 腿表里声明的二进制必须在真实 bin/ 里存在(桩腿铺得再全也不算数)"
for leg in "${PANEL_LEGS_ORDER[@]}"; do
  agent="$(panel_leg_agent "$leg")"; chat="$(panel_leg_chat "$leg")"
  check "P7pre[$leg]: 底座腿 bin/$agent 存在且可执行" \
    $([[ -n "$agent" && -x "$ROOT/bin/$agent" ]]; echo $?)
  if [[ -n "$chat" ]]; then
    check "P7pre[$leg]: 聊天腿 bin/$chat 存在且可执行" $([[ -x "$ROOT/bin/$chat" ]]; echo $?)
  fi
  for bin_name in "$agent" ${chat:+"$chat"}; do
    check "P7pre[$leg]: $bin_name 是这条腿自己的二进制(不许交叉接到别条腿上)" \
      $([[ "$bin_name" == "$leg" || "$bin_name" == "$leg-"* ]]; echo $?)
  done
done

echo "[P7] 花名册上的每条腿都必须真的派得出去,且家族记账不空"
make_leg_stubs "$d/bin"
declare -A P7_FAMILY=()
for leg in "${PANEL_LEGS_ORDER[@]}"; do
  : > "$calls"
  ov=""
  for other in "${PANEL_LEGS_ORDER[@]}"; do
    [[ "$other" == "$leg" ]] && continue
    ov+="${ov:+,}$other=cooldown:P7"
  done
  prefix="$d/raw/p7-$leg"
  PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state-p7-$leg" PANEL_STAGGER_MAX=0 \
    PANEL_HEALTH_OVERRIDE="$ov" \
    bash "$d/bin/panel-review" --risk standard --budget 1 \
    "${common[@]}" "$prefix" >/dev/null 2>&1
  sel="$(sed -n 's/^selected=//p' "$prefix.plan" 2>/dev/null)"
  entry="$(tr ',' '\n' <<<"$sel" | grep -F "$leg(" || true)"
  check "P7[$leg]: 轮换真的选中了它(plan 的 selected 里有它)" $([[ -n "$entry" ]]; echo $?)
  family="${entry#*(}"; family="${family%%/*}"
  adapter="${entry##*/}"; adapter="${adapter%)}"
  P7_FAMILY[$leg]="$family"
  check "P7[$leg]: 有模型家族—— 实际='$family'" \
    $([[ "$family" =~ ^[a-z][a-z0-9_-]*$ ]]; echo $?)
  check "P7[$leg]: 适配器 $adapter 真的被执行了(不是只出现在名单里)" \
    $(grep -qxF "$adapter" "$calls" 2>/dev/null; echo $?)
  check "P7[$leg]: 它自己的 state 落盘且 rc=0" \
    $([[ -s "$prefix.$leg.state" ]] && grep -qx 'rc=0' "$prefix.$leg.state"; echo $?)
done
check "P7: 各腿的模型家族两两不同" \
  $([[ "$(printf '%s\n' "${P7_FAMILY[@]}" | sort -u | wc -l)" -eq "${#P7_FAMILY[@]}" ]]; echo $?)

echo "[P8] --all 的派发覆盖运行时花名册全池"
: > "$calls"
prefix="$d/raw/p8-all"
PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state-p8" PANEL_STAGGER_MAX=0 \
  bash "$d/bin/panel-review" --risk standard --all \
  "${common[@]}" "$prefix" >/dev/null 2>&1; rc=$?
check "P8: --all 正常成功" $([[ $rc -eq 0 ]]; echo $?)
check "P8: --all 真实调用数等于花名册长度" \
  $([[ "$(wc -l < "$calls")" -eq "${#PANEL_LEGS_ORDER[@]}" ]]; echo $?)

rm -rf "$d"
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
