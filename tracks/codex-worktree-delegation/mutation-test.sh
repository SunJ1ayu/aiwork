#!/usr/bin/env bash
# 变异测试:往 bin/delegate-codex 里逐个塞入"看起来合理、实际把闸拆了"的改动,
# 要求 tests/test-delegate-isolate.sh **每次都红在指定的那条断言上**。
#
# 为什么要做:判据全绿只说明"这份实现让它绿了",不说明"换个错的实现它会红"。
# 08-08 那一单的教训写得很清楚 —— 证明判据咬得动,靠的是变异测试,不是通过率。
#
# 每一处变异都必须**确认真的替换上了**(count==1),否则"没红"会被误读成判据没用,
# 而真相是变异压根没生效(假报警和假绿一样坏)。
#
# Run:  bash tracks/codex-worktree-delegation/mutation-test.sh
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2
FILE=bin/delegate-codex
SUITE=tests/test-delegate-isolate.sh
TMP="$(mktemp -d)"
restore() { git checkout -- "$FILE" 2>/dev/null; }
trap 'restore; rm -rf "$TMP"' EXIT INT TERM

[[ -z "$(git status --porcelain -- "$FILE")" ]] || { echo "🔴 $FILE 有未提交改动,先收拾干净再变异"; exit 2; }

PASS=0; FAIL=0
mutate() {  # mutate <名字> <期望红的断言(grep -F)> <原文> <替换> [<原文2> <替换2> ...]
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
  local out="$TMP/$name.txt"
  bash "$SUITE" > "$out" 2>&1
  restore
  if grep -qF "FAIL: $want" "$out"; then
    echo "  ✅ [$name] 判据红在该红的地方:$want"
    PASS=$((PASS+1))
  else
    echo "  🔴 [$name] **判据没咬住** —— 拆了这道闸它居然还绿(或红在别处):$want"
    grep -E '^  FAIL|total:' "$out" | sed 's/^/       /' | head -8
    FAIL=$((FAIL+1))
  fi
}

echo "=== 变异测试:拆掉每一道闸,判据必须红 ==="

mutate "M1-默认不隔离" \
  "I1: codex 的 -C 落在 worktree 根下" \
  'ISOLATE=1; PRINTHASH=0' 'ISOLATE=0; PRINTHASH=0'

mutate "M2-哈希只看有没有那一行不比对值" \
  "H1: 判卷改了、攻题记录没跟上 ⇒ 拒发(攻的是上一版考卷)" \
  'grep -Fq "$HASH_LINE" "$ATTACK"' 'grep -q "oracle-sha256:" "$ATTACK"'

mutate "M3-闸①第一臂退回主树" \
  "R2: 隔离下 ⇒ 闸①放行(误报消失)" \
  'diff_out="$(git -C "$tree" diff "$head"' 'diff_out="$(git -C "$repo" diff "$head"'

mutate "M4-底账退回主树" \
  'R2: 底账里**没有**我自己改的判据文件' \
  'writeset="$( { git -C "$tree" diff --name-only "$head"' 'writeset="$( { git -C "$repo" diff --name-only "$head"'

# M5 第一版只拆了 note() 里那道,判据没红 —— 追下去不是"判据没咬住",是**变异没拆干净**:
# 实现里有两道冗余的 __pycache__ 排除(note() 按路径成分、walk() 按目录名剪枝),
# 拆一道另一道还拦着 ⇒ 行为根本没变,判据当然不该红。问"这道闸没了会怎样"就得两道一起拆。
mutate "M5-哈希不排除__pycache__(两道冗余排除一起拆)" \
  "H2: __pycache__ 内容变了 ⇒ 哈希不变、照发" \
  '    if "__pycache__" in rel.split("/"):
        return' '    if False:
        return' \
  '        if os.path.basename(rel) == "__pycache__":
            return' '        if False:
            return'

mutate "M6-卷宗放宽过头(不查被跟踪的攻题记录)" \
  "I4: 攻题记录被 git 跟踪 ⇒ 拒发(它会被 checkout 进树)" \
  'if git -C "$REPO" ls-files --error-unmatch -- "$_arel" >/dev/null 2>&1; then' 'if false; then'

mutate "M7-判卷脏也照派" \
  "I2: 判卷路径有未提交改动 ⇒ 拒发" \
  'if [[ -n "$_dirty_protect" ]]; then' 'if false; then'

echo "=== 变异测试:$PASS 处被咬住,$FAIL 处漏网 ==="
[[ -z "$(git status --porcelain -- "$FILE")" ]] || { echo "🔴 收尾没恢复干净"; exit 3; }
echo "✅ 收尾:$FILE 已恢复(git 说的)"
[[ $FAIL -eq 0 ]]
