#!/usr/bin/env bash
# Oracle for `submimo fix --oracle CMD [--protect PATH...]` — the goal-based
# bounded-retry loop. Owned by the main agent; submimo/mimo must NOT edit it.
#
# Contract:
#   G1  --oracle green on first try  -> exit 0, one mimo attempt
#   G2  --oracle red then green      -> exit 0, exactly two attempts
#   G3  --oracle red forever         -> non-zero, capped at 2 attempts (AGENTS.md ≤2)
#   G4  --protect file mutated       -> hard fail (non-zero) even if oracle green,
#                                       with a loud "protected file changed" message
#   G5  each attempt's `git diff` is archived into the log
#   G6  no --oracle                  -> single-shot behavior unchanged (one attempt, exit 0)
set -uo pipefail

# 判卷面的不变量:**跑判据的进程不许有外网出口**(2026-08-10,track no-egress-judging)。
# 这一行把整个套件 exec 进一个没有出口的网络命名空间;做不到就拒跑。
. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78   # source 失败=裸跑,必须硬退
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
chk() { if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

# Stub `mimo`: on `run`, append a line to target.txt in --dir. A per-repo counter
# file drives how the "fix" behaves so we can script red→green across attempts.
make_stub_mimo() {
  local b="$1"
  cat > "$b/mimo" <<'PYEOF'
#!/usr/bin/env bash
[[ "$1" == "run" ]] || exit 0
dir="."; while [[ $# -gt 0 ]]; do [[ "$1" == "--dir" ]] && { dir="$2"; shift; }; shift; done
n=0; [[ -f "$dir/.attempts" ]] && n=$(cat "$dir/.attempts"); n=$((n+1)); echo "$n" > "$dir/.attempts"
echo "fix attempt $n" >> "$dir/target.txt"
xc=0
# honor a scripted action per attempt: touch the sentinel the oracle wants
case "$(cat "$dir/.plan" 2>/dev/null)" in
  greenfirst) echo pass > "$dir/state" ;;
  redthengreen) [[ $n -ge 2 ]] && echo pass > "$dir/state" || echo fail > "$dir/state" ;;
  redforever) echo fail > "$dir/state" ;;
  mutate) echo pass > "$dir/state"; echo tampered >> "$dir/judge.txt" ;;
  crash_green) echo pass > "$dir/state"; xc=124 ;;              # mimo 非零退出但已修好
  crash_redthengreen) [[ $n -ge 2 ]] && echo pass > "$dir/state" || echo fail > "$dir/state"; xc=124 ;;
esac
echo "stub mimo done (attempt $n, exit $xc)"
exit $xc
PYEOF
  chmod +x "$b/mimo"
}

newrepo() { # plan -> echoes repo path
  local d; d="$(mktemp -d)"; ( cd "$d"; git init -q; git config user.email t@t; git config user.name t
    echo start > target.txt; echo judge > judge.txt; git add -A; git commit -qm init )
  echo "$1" > "$d/.plan"; echo "$d"
}

ORACLE='test "$(cat state 2>/dev/null)" = pass'  # green when file `state` says pass

run_fix() { # repo logfile extra-args...
  local repo="$1" log="$2"; shift 2
  local t; t="$(mktemp)"; printf '# fix target.txt\nallowed: target.txt\n' > "$t"
  PATH="$STUBDIR:$PATH" MIMO_CLI_MODEL=stub \
    bash "$BIN/submimo" fix "$t" "$log" "$repo" "$@"
  local rc=$?; rm -f "$t"; return $rc
}

echo "=== submimo fix --oracle oracle ==="
STUBDIR="$(mktemp -d)/bin"; mkdir -p "$STUBDIR"; make_stub_mimo "$STUBDIR"

# G1 green first
r=$(newrepo greenfirst); run_fix "$r" "$r/log" --oracle "$ORACLE" >/dev/null 2>&1
chk "G1 green-first exits 0" $?
[[ "$(cat "$r/.attempts")" == 1 ]]; chk "G1 exactly one attempt" $?

# G2 red then green
r=$(newrepo redthengreen); run_fix "$r" "$r/log" --oracle "$ORACLE" >/dev/null 2>&1
chk "G2 red-then-green exits 0" $?
[[ "$(cat "$r/.attempts")" == 2 ]]; chk "G2 exactly two attempts" $?

# G3 red forever
r=$(newrepo redforever); run_fix "$r" "$r/log" --oracle "$ORACLE" >/dev/null 2>&1
[[ $? -ne 0 ]]; chk "G3 red-forever exits non-zero" $?
[[ "$(cat "$r/.attempts")" == 2 ]]; chk "G3 capped at two attempts" $?

# G4 protected file mutated -> hard fail despite oracle green
r=$(newrepo mutate); run_fix "$r" "$r/log" --oracle "$ORACLE" --protect judge.txt >"$r/out" 2>&1
[[ $? -ne 0 ]]; chk "G4 protected mutation exits non-zero" $?
grep -qi "protected" "$r/out"; chk "G4 loud protected-file message" $?

# G5 diff archived
r=$(newrepo greenfirst); run_fix "$r" "$r/log" --oracle "$ORACLE" >/dev/null 2>&1
grep -q "fix attempt 1" "$r/log"; chk "G5 attempt diff archived in log" $?

# G6 fix WITHOUT --oracle and WITHOUT --no-oracle -> REFUSE (default-on: forgetting stops you)
r=$(newrepo redforever); run_fix "$r" "$r/log" >/dev/null 2>&1
[[ $? -ne 0 ]]; chk "G6 bare fix (no oracle flag) refuses" $?
[[ ! -f "$r/.attempts" ]]; chk "G6 refused before running mimo" $?

# G6b explicit --no-oracle -> single shot runs (the conscious opt-out)
r=$(newrepo redforever); run_fix "$r" "$r/log" --no-oracle >/dev/null 2>&1
chk "G6b --no-oracle single shot exits 0" $?
[[ "$(cat "$r/.attempts")" == 1 ]]; chk "G6b --no-oracle one attempt only" $?

# G7 mimo exits non-zero but fix is good -> oracle still evaluated, exit 0
# (regression for CONFIRMED-1: set -e + pipefail must not abort before the oracle)
r=$(newrepo crash_green); run_fix "$r" "$r/log" --oracle "$ORACLE" --protect judge.txt >/dev/null 2>&1
chk "G7 mimo-crash-but-green: oracle still runs, exit 0" $?
grep -q "oracle GREEN" "$r/log"; chk "G7 handback/verdict logic reached despite crash" $?

# G8 mimo exits non-zero every attempt; fix lands on attempt 2 -> retry survives crash
r=$(newrepo crash_redthengreen); run_fix "$r" "$r/log" --oracle "$ORACLE" >/dev/null 2>&1
chk "G8 crash-red-then-green exits 0" $?
[[ "$(cat "$r/.attempts")" == 2 ]]; chk "G8 retry survives mimo non-zero exit" $?

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
