#!/usr/bin/env bash
# Read-only cost/quality ledger oracle. No network and no raw-log parsing.
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECORD="${TRACK_RECORD_BIN:-$ROOT/bin/track-record}"
TRACK="${TRACK_BIN:-$ROOT/bin/track}"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

write_decision() { # dir track adapter model verdict
  mkdir -p "$1"
  cat > "$1/decision.json" <<EOF
{
  "schema_version": 1,
  "track": "$2",
  "impact": {"level": "self", "factors": []},
  "design": {"uncertainty": "low", "premise_attack": {"status": "not_required", "evidence": []}},
  "execution_plan": {"adapter": "$3", "model": $4},
  "outcome": {"verdict": "$5"}
}
EOF
}

observe() { # repo track run event adapter model duration rc billing [tokens]
  local repo="$1" track="$2" run="$3" event="$4" adapter="$5" model="$6"
  local duration="$7" rc="$8" billing="$9" tokens="${10:-}"
  local args=(observe --repo "$repo" --track "$track" --run-id "$run"
    --controller "$([[ "$adapter" == delegate-codex ]] && echo delegate-codex || echo runlog)"
    --event "$event" --label "$run" --started-at 2026-08-21T01:00:00.000Z
    --finished-at 2026-08-21T01:00:01.000Z --duration-ms "$duration"
    --exit-code "$rc" --adapter "$adapter" --work-exit-code "$rc" --degraded false
    --billing-mode "$billing")
  [[ "$model" == null ]] || args+=(--model "$model")
  if [[ -n "$tokens" ]]; then
    args+=(--input-tokens "$tokens" --output-tokens 5 --total-tokens "$((tokens+5))")
  fi
  "$RECORD" "${args[@]}" >/dev/null
}

echo "=== read-only cost/quality ledger oracle ==="
d="$(mktemp -d)"; repo="$d/repo"
mkdir -p "$repo/tracks/archive" "$repo/logs"
( cd "$repo"; git init -q -b main; git config user.email t@t; git config user.name t )

# Successful delegate task: one paid execution plus a separate receive gate.
write_decision "$repo/tracks/delegated" delegated delegate-codex '"gpt-5.5"' PASS
observe "$repo" delegated delegate-1 execution_finished delegate-codex gpt-5.6-sol 100 0 subscription
observe "$repo" delegated delegate-1 received delegate-codex gpt-5.6-sol 20 0 subscription

# Successful main task with known local token counters, archived already.
write_decision "$repo/tracks/archive/local-pass" local-pass main null PASS
observe "$repo" local-pass local-1 execution_finished runlog null 200 0 local 10

# PASS without controller coverage must be listed missing, never silently aggregated.
write_decision "$repo/tracks/missing-pass" missing-pass main null PASS

# High PASS with execution but no two-family panel evidence is under-reviewed.
write_decision "$repo/tracks/under-reviewed" under-reviewed main null PASS
python3 - "$repo/tracks/under-reviewed/decision.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["impact"]={"level":"high","factors":["judging_control"]}
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
observe "$repo" under-reviewed under-1 execution_finished runlog null 40 0 local

# Planned delegate execution cannot be substituted by an unrelated green runlog.
write_decision "$repo/tracks/delegate-missing" delegate-missing delegate-codex '"gpt-5.5"' PASS
observe "$repo" delegate-missing unrelated execution_finished runlog null 50 0 local

# A failed outcome may be reported but must not enter successful-task cost.
write_decision "$repo/tracks/blocked" blocked main null BLOCK
observe "$repo" blocked blocked-1 execution_finished runlog null 300 1 local

# Legacy prose deliberately lies; ledger must not parse any of it.
mkdir -p "$repo/tracks/archive/legacy"
cat > "$repo/tracks/archive/legacy/verify.md" <<'EOF'
- Verdict: PASS
- lane: high
- token: 999999
- API cost: 123.45
EOF

( cd "$repo"; git add tracks; git commit -qm fixtures )
printf 'RAW_LOG_SENTINEL token=777 cost=88\n' > "$repo/logs/raw.log"
printf '{"fake":"receipt","total_tokens":888}\n' > "$repo/logs/raw.receipt.json"

echo "[L1] JSON 只从 decision/observations 派生，legacy/null/missing/mismatch 都诚实"
before_status="$(git -C "$repo" status --porcelain -uall)"
before_hash="$(find "$repo/tracks" -type f \( -name decision.json -o -path '*/observations/*.json' \) -print0 | sort -z | xargs -0 sha256sum)"
out1="$($RECORD ledger --repo "$repo" --format json)"; rc=$?
check "L1: ledger JSON 成功" $([[ $rc -eq 0 ]]; echo $?)
python3 -c 'import json,sys; json.loads(sys.stdin.read())' <<<"$out1"
check "L1: 输出是合法 JSON" $?
LEDGER="$out1" python3 - <<'PY'
import json, os
p=json.loads(os.environ["LEDGER"])
assert p["schema_version"] == 1
assert p["source"] == ["decision.json", "observations/*.json"]
tracks={x["track"]:x for x in p["tracks"]}
assert list(tracks) == sorted(tracks), list(tracks)

d=tracks["delegated"]
assert d["record_status"] == "typed" and d["outcome"] == "PASS"
assert d["coverage"]["execution_finished"] == 1 and d["coverage"]["received"] == 1
assert d["quality"]["controller_runs"] == 1 and d["quality"]["failed_controller_runs"] == 0
assert d["cost"]["execution_duration_ms"] == 100
assert d["cost"]["receive_duration_ms"] == 20
assert d["cost"]["total_tokens"]["value"] is None
assert d["cost"]["total_tokens"]["known_total"] is None
assert d["cost"]["total_tokens"]["unknown_events"] == 1
assert d["cost"]["api_cost"]["value"] is None
assert d["cost"]["billing_modes"] == ["subscription"]
assert d["mismatch"] == {"adapter": False, "model": True}
assert d["successful_cost_eligible"] is True

local=tracks["local-pass"]
assert local["location"] == "archive" and local["cost"]["total_tokens"]["value"] == 15
assert local["cost"]["api_cost"]["value"] is None

missing=tracks["missing-pass"]
assert missing["successful_cost_eligible"] is False
assert "execution_finished" in missing["missing"]
assert missing["cost"]["execution_duration_ms"] is None

delegate_missing=tracks["delegate-missing"]
assert delegate_missing["successful_cost_eligible"] is False
assert "delegate_execution_finished" in delegate_missing["missing"]

under=tracks["under-reviewed"]
assert under["successful_cost_eligible"] is False
assert "review_budget:2" in under["missing"]
assert under["quality"]["panel_families"] == []

legacy=tracks["legacy"]
assert legacy["record_status"] == "legacy"
assert legacy["impact_level"] is None and legacy["outcome"] is None
assert legacy["planned"] == {"adapter": None, "model": None}
assert legacy["cost"]["total_tokens"]["value"] is None
assert legacy["successful_cost_eligible"] is False

assert tracks["blocked"]["successful_cost_eligible"] is False
s=p["summary"]
assert s["tracks_total"] == 7 and s["typed_tracks"] == 6 and s["legacy_tracks"] == 1
assert s["successful_tracks"] == 5 and s["successful_cost_eligible"] == 2
assert s["successful_cost_missing"] == ["delegate-missing", "missing-pass", "under-reviewed"]
assert s["successful_cost"]["execution_duration_ms"] == 300
assert s["successful_cost"]["total_tokens"]["value"] is None
assert s["successful_cost"]["total_tokens"]["known_total"] == 15
assert s["successful_cost"]["total_tokens"]["unknown_events"] == 1
assert s["successful_cost"]["by_billing_mode"]["subscription"]["execution_duration_ms"] == 100
assert s["successful_cost"]["by_billing_mode"]["local"]["execution_duration_ms"] == 200
PY
check "L1: legacy 不猜、missing 不进成功聚合、null 不当 0、planned/actual mismatch 可见" $?

after_status="$(git -C "$repo" status --porcelain -uall)"
after_hash="$(find "$repo/tracks" -type f \( -name decision.json -o -path '*/observations/*.json' \) -print0 | sort -z | xargs -0 sha256sum)"
check "L1: ledger 前后 git status 不变" $([[ "$before_status" == "$after_status" ]]; echo $?)
check "L1: ledger 前后机器源逐字节不变" $([[ "$before_hash" == "$after_hash" ]]; echo $?)

echo "[L2] 输出稳定且完全不依赖 raw logs/receipt"
out2="$($RECORD ledger --repo "$repo" --format json)"
check "L2: 同一输入重复运行字节稳定" $([[ "$out1" == "$out2" ]]; echo $?)
rm -f "$repo/logs/raw.log" "$repo/logs/raw.receipt.json"
out3="$($RECORD ledger --repo "$repo" --format json)"
check "L2: 删除 raw log/receipt 后 ledger 一字不变" $([[ "$out1" == "$out3" ]]; echo $?)
grep -q '777\|888\|123.45\|999999' <<<"$out3"
check "L2: raw/legacy 里的伪成本从未渗入" $([[ $? -ne 0 ]]; echo $?)

echo "[L3] Markdown 只是同一事实视图，unknown 明示"
md="$($RECORD ledger --repo "$repo" --format markdown)"; rc=$?
check "L3: Markdown 输出成功" $([[ $rc -eq 0 ]]; echo $?)
grep -q 'delegated' <<<"$md" && grep -q 'legacy' <<<"$md" && grep -q 'unknown' <<<"$md"
check "L3: Markdown 含 typed/legacy 与 unknown，不粉饰缺失" $?

echo "[L4] 真 archive+sweep 只回收执行现场，持久成本质量事实不丢"
printf '# Verify\n- 无机器证据:fixture 只验证 archive/sweep 生命周期。\n' > "$repo/tracks/delegated/verify.md"
( cd "$repo"; git add tracks/delegated/verify.md; git commit -qm verify )
wt="$d/wt/delegated/ledger-job"
mkdir -p "$(dirname "$wt")"
git -C "$repo" worktree add -q -b delegate/delegated/ledger-job "$wt" main
before_lifecycle="$($RECORD ledger --repo "$repo" --format json)"
archive_out="$(DELEGATE_WORKTREE_ROOT="$d/wt" "$TRACK" archive delegated "$repo" 2>&1)"; rc=$?
check "L4: typed facts/coverage 完整时真归档成功" $([[ $rc -eq 0 ]]; echo $?)
check "L4: 原机械闸确实收掉已进主线的干净 worktree" $([[ ! -d "$wt" ]]; echo $?)
check "L4: observations 随 track 持久移入 archive" \
  $([[ -d "$repo/tracks/archive/delegated/observations" && ! -d "$repo/tracks/delegated" ]]; echo $?)
after_lifecycle="$($RECORD ledger --repo "$repo" --format json)"
BEFORE="$before_lifecycle" AFTER="$after_lifecycle" python3 - <<'PY'
import copy, json, os
before=json.loads(os.environ["BEFORE"]); after=json.loads(os.environ["AFTER"])
def delegated(data):
    item=next(x for x in data["tracks"] if x["track"]=="delegated")
    location=item.pop("location")
    return location, item
bl, bi=delegated(before); al, ai=delegated(after)
assert bl=="active" and al=="archive"
assert bi==ai
assert before["summary"]==after["summary"]
PY
check "L4: 除 lifecycle location 外，逐项成本/质量与总聚合不变" $?

echo "[L5] 同一 controller/event/run_id 重复导入不许双计成本"
source_obs="$(find "$repo/tracks/archive/local-pass/observations" -name '*.json' | head -1)"
cp "$source_obs" "$repo/tracks/archive/local-pass/observations/duplicate.json"
dupe_ledger="$($RECORD ledger --repo "$repo" --format json)"; rc=$?
check "L5: 重复事件不会让 ledger 崩溃" $([[ $rc -eq 0 ]]; echo $?)
LEDGER="$dupe_ledger" python3 - <<'PY'
import json, os
p=json.loads(os.environ["LEDGER"])
t=next(x for x in p["tracks"] if x["track"]=="local-pass")
assert t["coverage"]["invalid_observations"] == 1
assert t["coverage"]["execution_finished"] == 1
assert t["cost"]["execution_duration_ms"] == 200
assert t["successful_cost_eligible"] is False
assert "valid_observations" in t["missing"]
PY
check "L5: 重复事件标 invalid/missing，第一份只算一次" $?
out="$($RECORD validate --phase archive "$repo/tracks/archive/local-pass" 2>&1)"; rc=$?
check "L5: PASS archive validator 同样拒绝重复事件" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=observation.duplicate' <<<"$out"
check "L5: duplicate trace 明确" $?

echo "[L6] observe 写口拒绝 NaN/Infinity，不产出非标准 JSON"
before_count="$(find "$repo/tracks/archive/local-pass/observations" -name '*.json' | wc -l)"
out="$($RECORD observe --repo "$repo" --track local-pass --run-id nonfinite --controller runlog \
  --event execution_finished --label nonfinite --started-at 2026-08-21T00:00:00Z \
  --finished-at 2026-08-21T00:00:01Z --duration-ms 1 --exit-code 0 \
  --adapter runlog --work-exit-code 0 --api-cost nan 2>&1)"; rc=$?
check "L6: --api-cost nan 在写盘前被拒" $([[ $rc -ne 0 ]]; echo $?)
after_count="$(find "$repo/tracks/archive/local-pass/observations" -name '*.json' | wc -l)"
check "L6: 拒绝后没有半份 observation" $([[ "$before_count" -eq "$after_count" ]]; echo $?)

rm -rf "$d"
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
