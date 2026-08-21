#!/usr/bin/env bash
# delegate-codex typed observation oracle. Codex is a local stub; no network.
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DELEGATE="$ROOT/bin/delegate-codex"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

make_fixture() { # root
  local d="$1" repo="$1/repo" b="$1/bin"
  mkdir -p "$repo/tracks/current/evidence" "$repo/tests" "$repo/src" "$b"
  printf 'echo oracle\n' > "$repo/tests/oracle.sh"
  printf 'base\n' > "$repo/src/impl.txt"
  printf 'independent premise summary\n' > "$repo/tracks/current/evidence/premise.md"
  printf '# Verify\n' > "$repo/tracks/current/verify.md"
  cat > "$repo/tracks/current/decision.json" <<'EOF'
{
  "schema_version": 1,
  "track": "current",
  "impact": {"level": "high", "factors": ["new_write_surface"]},
  "design": {"uncertainty": "high", "premise_attack": {"status": "done", "evidence": ["evidence/premise.md"]}},
  "execution_plan": {"adapter": "delegate-codex", "model": "gpt-5.5"},
  "outcome": {"verdict": null}
}
EOF
  ( cd "$repo"; git init -q -b main; git config user.email t@t; git config user.name t
    git add -A; git commit -qm init )
  printf '# DELEGATE_TASK_SENTINEL\n' > "$d/task.md"
  printf 'independent attack outside repo\n' > "$d/attack.md"
  "$DELEGATE" --print-oracle-hash --repo "$repo" --protect tests/ >> "$d/attack.md"
  cat > "$b/codex" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' >> "$CODEX_TEST_CALLS"
exit "${CODEX_TEST_RC:-0}"
EOF
  chmod +x "$b/codex"
}

obs_count() { find "$1/repo/tracks/current/observations" -name '*.json' 2>/dev/null | wc -l; }

echo "=== delegate typed observation oracle ==="

echo "[D1] codex 完成只写 execution_finished；receive 后才写 received"
d="$(mktemp -d)"; make_fixture "$d"; receipt="$d/run.log.receipt.json"
out="$(PATH="$d/bin:$PATH" CODEX_TEST_CALLS="$d/calls" "$DELEGATE" \
  --task "$d/task.md" --repo "$d/repo" --attack-log "$d/attack.md" --protect tests/ \
  --track current --model gpt-5.5 --no-isolate --log "$d/run.log" 2>&1)"; rc=$?
check "D1: stub codex 成功时 delegate rc=0" $([[ $rc -eq 0 ]]; echo $?)
check "D1: codex 结束后恰有一份 observation" $([[ "$(obs_count "$d")" -eq 1 ]]; echo $?)
python3 - "$d/repo/tracks/current/observations" "$receipt" <<'PY'
import json, pathlib, sys
files=list(pathlib.Path(sys.argv[1]).glob("*.json")); assert len(files)==1
p=json.load(open(files[0], encoding="utf-8")); r=json.load(open(sys.argv[2], encoding="utf-8"))
assert p["controller"] == "delegate-codex" and p["event"] == "execution_finished"
assert p["exit_code"] == 0 and p["actual"]["work_exit_code"] == 0
assert p["actual"]["adapter"] == "delegate-codex" and p["actual"]["model"] == "gpt-5.5"
assert p["actual"]["risk"] is None and p["actual"]["degraded"] is False and p["actual"]["legs"] is None
assert p["usage"]["billing_mode"] == "subscription"
assert all(p["usage"][k] is None for k in ("input_tokens","output_tokens","total_tokens","api_cost"))
assert isinstance(p["duration_ms"], int) and p["duration_ms"] >= 0
assert r["run_id"] == p["run_id"] and r["codex_rc"] == 0
assert isinstance(r["duration_ms"], int) and r["finished_at"].endswith("Z")
raw=open(files[0], encoding="utf-8").read()
for forbidden in ("DELEGATE_TASK_SENTINEL", "attack_log", "protect", "/run.log", "transcript"):
    assert forbidden not in raw, forbidden
PY
check "D1: execution schema/receipt correlation/null usage 精确且无任务原文" $?

PATH="$d/bin:$PATH" CODEX_TEST_CALLS="$d/calls" "$DELEGATE" --receive "$receipt" >/dev/null 2>&1; rc=$?
check "D1: receive 闸通过" $([[ $rc -eq 0 ]]; echo $?)
check "D1: receive 后增加第二份事件" $([[ "$(obs_count "$d")" -eq 2 ]]; echo $?)
python3 - "$d/repo/tracks/current/observations" <<'PY'
import json, pathlib, sys
ps=[json.load(open(p, encoding="utf-8")) for p in pathlib.Path(sys.argv[1]).glob("*.json")]
assert {p["event"] for p in ps} == {"execution_finished","received"}
assert len({p["run_id"] for p in ps}) == 1
r=next(p for p in ps if p["event"]=="received")
assert r["exit_code"] == 0 and r["actual"]["work_exit_code"] == 0
assert r["usage"]["billing_mode"] == "subscription"
PY
check "D1: 两事件同 run_id，但 received 不冒充 execution_finished" $?
rm -rf "$d"

echo "[D2] codex 红也记录真实 rc；--no-track/dry-run 不伪造事件"
d="$(mktemp -d)"; make_fixture "$d"
out="$(PATH="$d/bin:$PATH" CODEX_TEST_CALLS="$d/calls" CODEX_TEST_RC=3 "$DELEGATE" \
  --task "$d/task.md" --repo "$d/repo" --attack-log "$d/attack.md" --protect tests/ \
  --track current --model gpt-5.5 --no-isolate --log "$d/red.log" 2>&1)"; rc=$?
check "D2: codex rc=3 原样透传" $([[ $rc -eq 3 ]]; echo $?)
python3 - "$(find "$d/repo/tracks/current/observations" -name '*.json' | head -1)" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); assert p["event"]=="execution_finished" and p["exit_code"]==3
PY
check "D2: 红事件也如实记 rc=3" $?
rm -rf "$d"

d="$(mktemp -d)"; make_fixture "$d"
PATH="$d/bin:$PATH" CODEX_TEST_CALLS="$d/calls" "$DELEGATE" \
  --task "$d/task.md" --repo "$d/repo" --attack-log "$d/attack.md" --protect tests/ \
  --no-track --no-isolate --log "$d/no-track.log" >/dev/null 2>&1
check "D2: --no-track 不写伪归属事件" $([[ "$(obs_count "$d")" -eq 0 ]]; echo $?)
PATH="$d/bin:$PATH" CODEX_TEST_CALLS="$d/calls" "$DELEGATE" \
  --task "$d/task.md" --repo "$d/repo" --attack-log "$d/attack.md" --protect tests/ \
  --track current --dry-run --log "$d/dry.log" >/dev/null 2>&1
check "D2: --dry-run 没执行，不写 execution_finished" $([[ "$(obs_count "$d")" -eq 0 ]]; echo $?)
rm -rf "$d"

echo "[D3] observation importer 失败明确报警，但不篡改 codex/receive rc"
d="$(mktemp -d)"; make_fixture "$d"; wrapper="$d/record-wrapper"
cat > "$wrapper" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == validate ]]; then exec "$ROOT/bin/track-record" "\$@"; fi
exit 7
EOF
chmod +x "$wrapper"
out="$(PATH="$d/bin:$PATH" CODEX_TEST_CALLS="$d/calls" CODEX_TEST_RC=3 TRACK_RECORD_BIN="$wrapper" \
  "$DELEGATE" --task "$d/task.md" --repo "$d/repo" --attack-log "$d/attack.md" --protect tests/ \
  --track current --model gpt-5.5 --no-isolate --log "$d/fail.log" 2>&1)"; rc=$?
check "D3: importer 失败时 codex rc=3 仍是 3" $([[ $rc -eq 3 ]]; echo $?)
grep -q 'OBSERVATION_WRITE_FAILED' <<<"$out"
check "D3: execution importer 失败明确报警" $?
check "D3: importer 失败不伪造事件" $([[ "$(obs_count "$d")" -eq 0 ]]; echo $?)

# 用真实 importer 先造一次成功执行，再只让 receive importer 失败。
PATH="$d/bin:$PATH" CODEX_TEST_CALLS="$d/calls" CODEX_TEST_RC=0 "$DELEGATE" \
  --task "$d/task.md" --repo "$d/repo" --attack-log "$d/attack.md" --protect tests/ \
  --track current --model gpt-5.5 --no-isolate --log "$d/ok.log" >/dev/null 2>&1
before="$(obs_count "$d")"
out="$(TRACK_RECORD_BIN="$wrapper" "$DELEGATE" --receive "$d/ok.log.receipt.json" 2>&1)"; rc=$?
check "D3: receive importer 失败时闸① rc=0 仍是 0" $([[ $rc -eq 0 ]]; echo $?)
grep -q 'OBSERVATION_WRITE_FAILED' <<<"$out"
check "D3: received importer 失败明确报警" $?
check "D3: receive importer 失败不伪造第二事件" $([[ "$(obs_count "$d")" -eq "$before" ]]; echo $?)
rm -rf "$d"

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
