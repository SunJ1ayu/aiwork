#!/usr/bin/env bash
# panel-review typed ownership/risk/observation oracle. External legs are stubs.
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

make_fixture() { # root
  local d="$1" b="$1/bin" repo="$1/repo"
  mkdir -p "$b" "$repo/tracks/current" "$d/raw" "$d/state"
  cp "$ROOT/bin/panel-review" "$b/panel-review"
  cp "$ROOT/bin/track-record" "$b/track-record"
  for leg in submimo subdeepseek subglm subkimi; do
    cat > "$b/$leg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$0")" >> "$PANEL_TEST_CALLS"
printf 'Conclusion: PASS\n' > "$3"
exit 0
EOF
    chmod +x "$b/$leg"
  done
  printf '# PANEL_PROMPT_SENTINEL\n' > "$d/task.md"
  cat > "$repo/tracks/current/decision.json" <<'EOF'
{
  "schema_version": 1,
  "track": "current",
  "impact": {"level": "high", "factors": []},
  "design": {"uncertainty": "low", "premise_attack": {"status": "not_required", "evidence": []}},
  "execution_plan": {"adapter": "panel-review", "model": null},
  "outcome": {"verdict": null}
}
EOF
  printf '# Verify\n' > "$repo/tracks/current/verify.md"
  ( cd "$repo"; git init -q -b main; git config user.email t@t; git config user.name t
    printf 'x\n' > app.txt; git add -A; git commit -qm init )
}

obs_count() { find "$1/repo/tracks/current/observations" -name '*.json' 2>/dev/null | wc -l; }
latest_obs() { find "$1/repo/tracks/current/observations" -name '*.json' 2>/dev/null | sort | tail -1; }

echo "=== panel typed observation oracle ==="
d="$(mktemp -d)"; make_fixture "$d"; calls="$d/calls"
common=(--no-my-review "$d/task.md" "$d/repo")

echo "[P1] typed active track 存在时归属必须显式，且 risk 在派腿前机械一致"
out="$(PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state" PANEL_STAGGER_MAX=0 \
  bash "$d/bin/panel-review" --risk high "${common[@]}" "$d/raw/no-owner" 2>&1)"; rc=$?
check "P1: 未给 --track/--no-track ⇒ 拒绝" $([[ $rc -ne 0 ]]; echo $?)
check "P1: 拒绝发生在任何腿调用前" $([[ ! -s "$calls" ]]; echo $?)
grep -q -- '--track' <<<"$out" && grep -q -- '--no-track' <<<"$out"
check "P1: 错误告诉调用者两个显式选择" $?

out="$(PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state" PANEL_STAGGER_MAX=0 \
  bash "$d/bin/panel-review" --track current --risk standard --budget 1 \
  "${common[@]}" "$d/raw/mismatch" 2>&1)"; rc=$?
check "P1: decision=high 但 CLI=standard ⇒ 拒绝" $([[ $rc -ne 0 ]]; echo $?)
check "P1: risk 不一致仍在任何腿调用前" $([[ ! -s "$calls" ]]; echo $?)
grep -q 'rule=impact.expected' <<<"$out" && grep -q 'actual=.*high' <<<"$out" \
  && grep -q 'expected=.*standard' <<<"$out"
check "P1: risk mismatch 给 rule/actual/expected trace" $?

PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state" PANEL_STAGGER_MAX=0 \
  bash "$d/bin/panel-review" --no-track --risk standard --budget 1 \
  "${common[@]}" "$d/raw/no-track" >/dev/null 2>&1; rc=$?
check "P1: 显式 --no-track 仍可评审" $([[ $rc -eq 0 ]]; echo $?)
check "P1: --no-track 不伪造归属 observation" $([[ "$(obs_count "$d")" -eq 0 ]]; echo $?)

echo "[P2] 匹配 track 的 panel 在全部腿结束后写实际腿/降级/耗时/null usage"
: > "$calls"
PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state" PANEL_STAGGER_MAX=0 PANEL_SELECTION_START=0 \
  bash "$d/bin/panel-review" --track current --risk high --budget 2 \
  "${common[@]}" "$d/raw/matched" >/dev/null 2>&1; rc=$?
check "P2: 匹配的 typed panel 正常成功" $([[ $rc -eq 0 ]]; echo $?)
f="$(latest_obs "$d")"
check "P2: 主仓 track 下恰有一份 observation" \
  $([[ -n "$f" && "$(obs_count "$d")" -eq 1 ]]; echo $?)
python3 - "$f" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding="utf-8"))
assert p["track"] == "current" and p["controller"] == "panel-review"
assert p["event"] == "execution_finished" and p["exit_code"] == 0
assert p["label"] == "task" and isinstance(p["duration_ms"], int) and p["duration_ms"] >= 0
a=p["actual"]
assert a["adapter"] == "panel-review" and a["risk"] == "high" and a["degraded"] is False
assert a["model"] is None and a["work_exit_code"] == 0
assert len(a["legs"]) == 2 and {x["name"] for x in a["legs"]} == {"submimo","subdeepseek"}
for leg in a["legs"]:
    assert set(leg) == {"name","family","adapter","model","state","exit_code","verdict",
                        "degraded","duration_ms","usage"}
    assert leg["state"] == "completed" and leg["exit_code"] == 0 and leg["verdict"] == "PASS"
    assert leg["model"] is None and leg["degraded"] is False and leg["duration_ms"] is None
    assert all(v is None for v in leg["usage"].values())
assert all(v is None for v in p["usage"].values())
raw=open(sys.argv[1], encoding="utf-8").read()
for forbidden in ("PANEL_PROMPT_SENTINEL", "Conclusion: PASS", "/raw/", "transcript"):
    assert forbidden not in raw, forbidden
PY
check "P2: schema 只含 compact actual facts，不复制 prompt/log" $?

echo "[P3] agent→chat 回落必须在 observation 中降级，不只留在实时 stdout"
cat > "$d/bin/subdeepseek-agent" <<'EOF'
#!/usr/bin/env bash
printf 'agent failed\n' >&2
exit 7
EOF
chmod +x "$d/bin/subdeepseek-agent"
: > "$calls"
PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state-2" PANEL_STAGGER_MAX=0 PANEL_SELECTION_START=1 \
  bash "$d/bin/panel-review" --track current --risk high --budget 1 \
  "${common[@]}" "$d/raw/degraded" >/dev/null 2>&1; rc=$?
check "P3: 回落聊天腿后 controller 仍成功" $([[ $rc -eq 0 ]]; echo $?)
f="$(latest_obs "$d")"
python3 - "$f" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding="utf-8")); a=p["actual"]
assert a["degraded"] is True and len(a["legs"]) == 1
leg=a["legs"][0]
assert leg["name"] == "subdeepseek" and leg["adapter"] == "subdeepseek"
assert leg["degraded"] is True and leg["state"] == "completed" and leg["verdict"] == "PASS"
PY
check "P3: actual adapter/降级资格跟着结论落盘" $?

echo "[P4] observation writer 失败可见，但不改 panel 原有 rc"
wrapper="$d/record-wrapper"
cat > "$wrapper" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == validate ]]; then exec "$ROOT/bin/track-record" "\$@"; fi
exit 7
EOF
chmod +x "$wrapper"
before="$(obs_count "$d")"
out="$(PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state-3" PANEL_STAGGER_MAX=0 \
  TRACK_RECORD_BIN="$wrapper" bash "$d/bin/panel-review" --track current --risk high --budget 0 \
  "${common[@]}" "$d/raw/writer-fail" 2>&1)"; rc=$?
check "P4: writer 失败不把原本 rc=0 的 panel 改红" $([[ $rc -eq 0 ]]; echo $?)
grep -q 'OBSERVATION_WRITE_FAILED' <<<"$out"
check "P4: writer 失败明确报警" $?
check "P4: writer 失败不伪造事件" $([[ "$(obs_count "$d")" -eq "$before" ]]; echo $?)

echo "[P5] self budget=0 有 controller event，但 external dispatch_count 必须为 0"
PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state-4" PANEL_STAGGER_MAX=0 \
  bash "$d/bin/panel-review" --track current --risk high --budget 0 \
  "${common[@]}" "$d/raw/self" >/dev/null 2>&1; rc=$?
check "P5: self/no-external-review 正常成功" $([[ $rc -eq 0 ]]; echo $?)
ledger="$($ROOT/bin/track-record ledger --repo "$d/repo" --format json)"
LEDGER="$ledger" python3 - <<'PY'
import json, os
p=json.loads(os.environ["LEDGER"])
t=next(x for x in p["tracks"] if x["track"]=="current")
assert t["quality"]["controller_runs"] == 3
assert t["quality"]["panel_legs"] == 3
assert t["quality"]["fallback_dispatches"] == 1
assert t["quality"]["dispatch_count"] == 4
PY
check "P5: 空 legs 的 panel run 不被伪记成一次外腿 dispatch" $?

rm -rf "$d"
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
