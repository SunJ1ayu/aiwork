#!/usr/bin/env bash
# 部署现场验证:**用真 codex 真派一发**,证明隔离这条路在真实运行时里是通的。
#
# 为什么判据不够:tests/ 里的 codex 是**假的**(记调用、按 -C 写文件)。它证明得了
# "工具把 -C 指到了树上",证明不了"真 codex 在一棵 worktree 里跑得起来" ——
# worktree 的 `.git` 是**文件**不是目录,沙箱/工具链在这上面翻车是真实存在的形状。
# 本机吃过两次同型的亏(浏览器里跑 v2.9 而盘上是 v3.0;gateway 内存里 6.8 而 dist 6.10):
# **没被真正加载/运行过的新代码不算部署。**
#
# ⚠️ 这个脚本**会花 codex 额度,绝不许进 tests/、绝不许进总跑 SUITES**
#    (2026-08-10 的事故就是判据自己去叫模型,一上午烧光额度)。
#
# Run:  bash tracks/codex-worktree-delegation/smoke-real-codex.sh
set -uo pipefail
BIN=/root/aiwork/bin/delegate-codex
D="$(mktemp -d)"
trap 'echo "现场留在 $D(要收自己敲 rm -rf)"' EXIT

PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
bad(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
ck(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

mkdir -p "$D/repo/src" "$D/repo/tests" "$D/wt"
cd "$D/repo" || exit 2
git init -q -b main; git config user.email t@t; git config user.name t
printf '# 冒烟仓\n' > README.md
printf 'def add(a, b):\n    return a - b\n' > src/calc.py
cat > tests/oracle.py <<'EOF'
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from calc import add
assert add(2, 3) == 5, f"FAIL: add(2,3) 应该是 5,实际 {add(2,3)}"
print("ok - add 对了")
EOF
git add -A; git commit -qm "实现(有 bug)+ 判据"
cd "$D" || exit 2

cat > task.md <<'EOF'
# 任务:修 src/calc.py 的 add

`tests/oracle.py` 现在是红的。把 `src/calc.py` 里的 `add` 修对(应该是加法)。
只改 src/calc.py。改完自己跑一遍 `python3 tests/oracle.py`,把结果写进报告。
EOF
cat > attack.md <<'EOF'
# 攻题记录(冒烟用)

判据只考 add(2,3)==5:写死 `return 5` 也能全绿 —— 真派活时这条要补,本次是工具冒烟,接受。
EOF
"$BIN" --print-oracle-hash --repo "$D/repo" --protect tests/ >> attack.md \
  || { echo "🔴 --print-oracle-hash 挂了"; exit 2; }

echo "=== 真派一发(真 codex,默认隔离)==="
DELEGATE_WORKTREE_ROOT="$D/wt" timeout 600 "$BIN" \
  --task "$D/task.md" --repo "$D/repo" --attack-log "$D/attack.md" \
  --protect tests/ --log "$D/run.log" > "$D/dispatch.txt" 2>&1
ck "真 codex 跑完 rc=0" $?
tail -3 "$D/dispatch.txt" | sed 's/^/     /'

tree="$(python3 -c 'import json;print(json.load(open("'"$D"'/run.log.receipt.json"))["worktree"])')"
ck "回执里有隔离树" $([[ -n "$tree" && -d "$tree" ]]; echo $?)
ck "**真 codex 的改动落在树里**(不是主仓)" \
  $([[ -n "$(git -C "$tree" status --porcelain -uall)" ]]; echo $?)
ck "主工作树逐字节没被碰(git status 空)" \
  $([[ -z "$(git -C "$D/repo" status --porcelain -uall)" ]]; echo $?)
grep -q 'return a - b' "$D/repo/src/calc.py"
ck "主工作树里那个 bug 还在(证明腿没写主仓)" $?
grep -q 'return a + b' "$tree/src/calc.py"
ck "树里的 bug 被真腿修好了" $?

echo "=== 闸①(机械版)跑在那棵树上 ==="
"$BIN" --receive "$D/run.log.receipt.json" > "$D/receive.txt" 2>&1
ck "闸① 通过 rc=0" $?
grep -q 'src/calc.py' "$D/receive.txt"; ck "底账列出腿动的文件" $?
grep -q 'worktree remove' "$D/receive.txt"; ck "打印回收命令" $?
python3 - "$D/run.log.receipt.json" <<'EOF'
import json,sys
r=json.load(open(sys.argv[1]))
assert r["isolate"] is True and r["dry_run"] is False, r
assert r["actual_write_set"] == ["src/calc.py"], r["actual_write_set"]
assert len(r["oracle_sha256"]) == 64
EOF
ck "回执里机器写下的实际写集 == ['src/calc.py']" $?

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
