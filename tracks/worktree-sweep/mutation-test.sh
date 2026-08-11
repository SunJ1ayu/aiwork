#!/usr/bin/env bash
# 变异测试:把 worktree-sweep 的每一道安全闸逐个拆掉,判据必须红在指定断言上。
# 用法与形状同 tracks/archive/codex-worktree-delegation/mutation-test.sh
# (那份里两次"漏网"都是脚本自己坏了 —— 所以这里对"套件输出为空"硬报错。)
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2
FILE=bin/track
SUITE=tests/test-worktree-sweep.sh
TMP="$(mktemp -d)"
restore() { git checkout -- "$FILE" 2>/dev/null; }
trap 'restore; rm -rf "$TMP"' EXIT INT TERM
[[ -z "$(git status --porcelain -- "$FILE")" ]] || { echo "🔴 $FILE 有未提交改动,先收拾干净"; exit 2; }

PASS=0; FAIL=0
mutate() {  # mutate <名字> <期望红的断言> <原文> <替换> [...]
  local name="$1" want="$2"; shift 2
  python3 - "$FILE" "$@" <<'PY' || { echo "  🔴 [$name] 变异没贴上(原文对不上)"; FAIL=$((FAIL+1)); return; }
import sys
p, *pairs = sys.argv[1:]
s = open(p, encoding="utf-8").read()
for a, b in zip(pairs[::2], pairs[1::2]):
    assert s.count(a) == 1, f"命中 {s.count(a)} 次,要求恰好 1 次:{a[:40]}"
    s = s.replace(a, b)
open(p, "w", encoding="utf-8").write(s)
PY
  local out="$TMP/${name//[^A-Za-z0-9_-]/_}.txt"
  bash "$SUITE" > "$out" 2>&1
  restore
  [[ -s "$out" ]] || { echo "  🔴 [$name] 套件输出是空的 —— 是**这个脚本**坏了,不是判据的事"; FAIL=$((FAIL+1)); return; }
  if grep -qF "FAIL: $want" "$out"; then
    echo "  ✅ [$name] 判据红在该红的地方:$want"; PASS=$((PASS+1))
  else
    echo "  🔴 [$name] **判据没咬住**:$want"
    grep -E '^  FAIL|total:' "$out" | sed 's/^/       /' | head -6; FAIL=$((FAIL+1))
  fi
}

echo "=== 变异测试(worktree-sweep):拆掉每一道安全闸,判据必须红 ==="

# W1 的靶子第一版指错了:干净判据被拆之后,`git worktree remove` 自己会拒(树里有未跟踪文件),
# 所以"归档被拦"照样成立 —— 变的是**说清是哪一条**。这正好证明了那道 remove 是有效的兜底。
mutate "W1-不查树干净不干净" \
  "S2: 说清卡在哪一条(树里有东西)" \
  '    elif [[ -n "$status_out" ]]; then
      dirty_reason="树里有没保存的改动/未跟踪文件"' \
  '    elif false; then
      dirty_reason="树里有没保存的改动/未跟踪文件"'

mutate "W2-不查合没合进主线" \
  "S3: 归档被拦(rc≠0)" \
  '    elif ! mb_out="$(git -C "$repo" merge-base --is-ancestor "$head" "$mainline" 2>&1)"; then' \
  '    elif false; then'

mutate "W3-主线判不出来就当它合过了(fail open)" \
  "S6: 说不清主线是哪条 ⇒ 拒绝清理(fail closed,不许当它合过了)" \
  '    elif ! mainline="$(_wt_default_branch "$repo")"; then
      mainline_reason="主线判不出来(找不到 origin/HEAD、main、master)"' \
  '    elif ! mainline="$(_wt_default_branch "$repo")"; then
      mainline="HEAD"'

# W4 同理:S2 那一幕有 git 的拒绝兜底,真正只靠这道闸的是 S3(干净但没合进主线 ——
# 那种树 git 会痛快地删掉)。
mutate "W4-blocked 了也照样归档(不拦)" \
  "S3: **树还在**(里面那个提交是唯一的一份)" \
  '  if [[ "$blocked" -ne 0 ]]; then' '  if false; then'

mutate "W5-把整个根都当成自己的树扫" \
  "S4: 归档成功" \
  '    [[ "$base" == "$track" ]] && continue
    outsiders+=("$entry")' \
  '    [[ "$base" == "$track" ]] && continue
    owned+=("$entry")'

# 原 W6(偷偷加 --force)删掉了:实测 `git worktree remove` 对**被 ignore** 的文件根本不拒,
# 而 modified/untracked 那种在干净判据那一步就被拦了 ⇒ 正常流程里 --force 与否**观察不到**。
# 它的价值只剩"干净判据被拆时的兜底",那正是 W1 覆盖的那一幕。
# 换成:把我自己那行 rmdir 的 `|| true` 拆掉(set -e 会让归档静默死掉)。
mutate "W6-rmdir 失败时静默把归档搞死(拆掉 || true)" \
  "S9: 归档照常完成(rc=0)" \
  'rmdir "$track_dir" 2>/dev/null || true' \
  'rmdir "$track_dir" 2>/dev/null'

mutate "W7---keep-trees 变成只跳过脏的" \
  "S5: --keep-trees 下连干净的树也不动" \
  '  if [[ "$keep" -eq 1 ]]; then
    echo "  --keep-trees: 本次只报告,不清理,也不阻断归档。"
    return 0
  fi' \
  '  if [[ "$keep" -eq 1 ]] && [[ "$blocked" -ne 0 ]]; then
    echo "  --keep-trees: 本次只报告,不清理,也不阻断归档。"
    return 0
  fi'

echo "=== 变异测试:$PASS 处被咬住,$FAIL 处漏网 ==="
[[ -z "$(git status --porcelain -- "$FILE")" ]] || { echo "🔴 收尾没恢复干净"; exit 3; }
echo "✅ 收尾:$FILE 已恢复(git 说的)"
[[ $FAIL -eq 0 ]]
