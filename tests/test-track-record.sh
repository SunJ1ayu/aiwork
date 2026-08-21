#!/usr/bin/env bash
# typed track decision / lifecycle oracle. Implementation must not edit this file.
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECORD="${TRACK_RECORD_BIN:-$ROOT/bin/track-record}"
TRACK="${TRACK_BIN:-$ROOT/bin/track}"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

write_decision() { # dir track level factors uncertainty premise-status evidence adapter model verdict
  local d="$1" track="$2" level="$3" factors="$4" uncertainty="$5"
  local premise="$6" evidence="$7" adapter="$8" model="$9" verdict="${10}"
  mkdir -p "$d"
  cat > "$d/decision.json" <<EOF
{
  "schema_version": 1,
  "track": "$track",
  "impact": {"level": $level, "factors": $factors},
  "design": {
    "uncertainty": $uncertainty,
    "premise_attack": {"status": $premise, "evidence": $evidence}
  },
  "execution_plan": {"adapter": $adapter, "model": $model},
  "outcome": {"verdict": $verdict}
}
EOF
}

shape_decision() {
  write_decision "$1" "$2" null null null null '[]' null null null
}

low_decision() {
  write_decision "$1" "$2" '"self"' '[]' '"low"' '"not_required"' '[]' '"main"' null "$3"
}

write_observation() { # track-dir track run-id controller event rc
  mkdir -p "$1/observations"
  cat > "$1/observations/$3-$5.json" <<EOF
{
  "schema_version": 1, "track": "$2", "run_id": "$3",
  "controller": "$4", "event": "$5", "label": "$3",
  "started_at": "2026-08-21T01:00:00.000Z",
  "finished_at": "2026-08-21T01:00:01.000Z",
  "duration_ms": 100, "exit_code": $6,
  "actual": {"adapter": "$4", "model": null, "risk": null,
    "degraded": false, "work_exit_code": $6, "legs": null},
  "usage": {"input_tokens": null, "output_tokens": null, "total_tokens": null,
    "api_cost": null, "billing_mode": "local"}
}
EOF
}

echo "=== typed track record oracle ==="

if [[ ! -x "$RECORD" ]]; then
  bad "R0: bin/track-record 存在且可执行"
  echo "=== total: $PASS passed, $FAIL failed ==="
  exit 1
fi

echo "[R1] track new 生成唯一机器事实源；null 不冒充 false/空值"
d="$(mktemp -d)"
( cd "$d"; git init -q; git config user.email t@t; git config user.name t )
out="$($TRACK new typed-new "$d" 2>&1)"; rc=$?
check "R1: track new 成功" $([[ $rc -eq 0 ]]; echo $?)
check "R1: decision.json 被生成" $([[ -f "$d/tracks/typed-new/decision.json" ]]; echo $?)
python3 - "$d/tracks/typed-new/decision.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
assert set(p) == {"schema_version", "track", "impact", "design", "execution_plan", "outcome"}
assert p["schema_version"] == 1 and p["track"] == "typed-new"
assert p["impact"] == {"level": None, "factors": None}
assert p["design"]["uncertainty"] is None
assert p["design"]["premise_attack"] == {"status": None, "evidence": []}
assert p["execution_plan"] == {"adapter": None, "model": None}
assert p["outcome"] == {"verdict": None}
PY
check "R1: 初态字段精确、unknown=null 且不等于 false/[]" $?
rm -rf "$d"

echo "[R2] shape 只查结构/类型/枚举，并给可审计 rule trace"
d="$(mktemp -d)"; shape_decision "$d/t" t
out="$($RECORD validate --phase shape "$d/t" 2>&1)"; rc=$?
check "R2: 合法 null 初态通过 shape" $([[ $rc -eq 0 ]]; echo $?)
python3 - "$d/t/decision.json" <<'PY'
import json, sys
p=json.load(open(sys.argv[1])); del p["impact"]["level"]
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
out="$($RECORD validate --phase shape "$d/t" 2>&1)"; rc=$?
check "R2: 缺字段 fail closed" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=field.required' <<<"$out" && grep -q 'path=impact.level' <<<"$out" \
  && grep -q 'actual=.*missing' <<<"$out" && grep -q 'expected=' <<<"$out"
check "R2: trace 同时给 rule/path/actual/expected" $?
write_decision "$d/t" t '"medium"' '[]' '"low"' '"not_required"' '[]' '"main"' null null
out="$($RECORD validate --phase shape "$d/t" 2>&1)"; rc=$?
check "R2: 非法 impact 枚举被挡" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'path=impact.level' <<<"$out" && grep -q 'actual=.*medium' <<<"$out" \
  && grep -q 'self.*standard.*high' <<<"$out"
check "R2: 非法枚举 trace 点名实际值与合法集合" $?
rm -rf "$d"

echo "[R3] dispatch 才要求决策完整，并执行手写跨字段规则"
d="$(mktemp -d)"; shape_decision "$d/t" t
out="$($RECORD validate --phase dispatch "$d/t" 2>&1)"; rc=$?
check "R3: null 不能在 dispatch 默认为 false/self" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'path=impact.level' <<<"$out" && grep -q 'actual=null' <<<"$out"
check "R3: null 的 BLOCK trace 明确" $?
low_decision "$d/t" t null
$RECORD validate --phase dispatch "$d/t" >/dev/null 2>&1
check "R3: 完整 low/self 计划可 dispatch" $?
write_decision "$d/t" t '"standard"' '["permissions"]' '"low"' '"not_required"' '[]' '"main"' null null
out="$($RECORD validate --phase dispatch "$d/t" 2>&1)"; rc=$?
check "R3: 高危因子不许降成 standard" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=impact.high_factor' <<<"$out" && grep -q 'actual=.*standard' <<<"$out" \
  && grep -q 'expected=.*high' <<<"$out"
check "R3: 降档 trace 点名手写规则" $?
write_decision "$d/t" t '"high"' '["new_write_surface"]' '"high"' '"pending"' '[]' '"main"' null null
out="$($RECORD validate --phase dispatch "$d/t" 2>&1)"; rc=$?
check "R3: high uncertainty 没完成 premise attack 被挡" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=design.premise_required' <<<"$out"
check "R3: premise 规则可审计" $?
write_decision "$d/t" t '"high"' '["new_write_surface"]' '"high"' '"done"' '["evidence/attack.md"]' '"main"' null null
out="$($RECORD validate --phase dispatch "$d/t" 2>&1)"; rc=$?
check "R3: 只写一个不存在的 evidence 路径仍然被挡" $([[ $rc -ne 0 ]]; echo $?)
mkdir -p "$d/t/evidence"; printf 'independent premise attack\n' > "$d/t/evidence/attack.md"
$RECORD validate --phase dispatch "$d/t" >/dev/null 2>&1
check "R3: high uncertainty + 持久 evidence 后可 dispatch" $?
rm -rf "$d"

echo "[R4] archive 要求真实 outcome，保留 superseded 而不伪造 PASS"
d="$(mktemp -d)"; low_decision "$d/t" t null
out="$($RECORD validate --phase archive "$d/t" 2>&1)"; rc=$?
check "R4: outcome=null 时拒绝归档" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'path=outcome.verdict' <<<"$out" && grep -q 'actual=null' <<<"$out"
check "R4: outcome 缺失 trace 明确" $?
low_decision "$d/t" t '"PASS"'
out="$($RECORD validate --phase archive "$d/t" 2>&1)"; rc=$?
check "R4: PASS 但没有 execution observation 时拒绝归档" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=observation.required' <<<"$out"
check "R4: 缺覆盖的 rule trace 明确" $?
write_observation "$d/t" t run-1 runlog execution_finished 0
$RECORD validate --phase archive "$d/t" >/dev/null 2>&1
check "R4: PASS 且 execution coverage 完整才可归档" $?
rm -rf "$d/t/observations"
low_decision "$d/t" t '"ARCHIVED-SUPERSEDED"'
$RECORD validate --phase archive "$d/t" >/dev/null 2>&1
check "R4: ARCHIVED-SUPERSEDED 可归档且无需冒充 PASS" $?
write_decision "$d/t" t '"self"' '[]' '"low"' '"not_required"' '[]' '"main"' null '"DONE"'
out="$($RECORD validate --phase shape "$d/t" 2>&1)"; rc=$?
check "R4: 自造 verdict 枚举被挡" $([[ $rc -ne 0 ]]; echo $?)
rm -rf "$d"

echo "[R5] legacy 明示兼容；曾跟踪过的 decision 删除后不能降级逃闸"
d="$(mktemp -d)"; mkdir -p "$d/tracks/legacy"
out="$($RECORD validate --phase archive "$d/tracks/legacy" 2>&1)"; rc=$?
check "R5: 真 legacy track 不误伤" $([[ $rc -eq 0 ]]; echo $?)
grep -q 'status=legacy' <<<"$out"
check "R5: legacy 状态明确，不从 Markdown 猜字段" $?
( cd "$d"; git init -q; git config user.email t@t; git config user.name t )
low_decision "$d/tracks/typed" typed '"PASS"'
( cd "$d"; git add tracks/typed/decision.json; git commit -qm typed; rm tracks/typed/decision.json )
out="$($RECORD validate --phase archive "$d/tracks/typed" 2>&1)"; rc=$?
check "R5: 删除已跟踪 decision 不会伪装成 legacy" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=decision.required' <<<"$out"
check "R5: 删除逃闸有明确 rule trace" $?
rm -rf "$d"

echo "[R6] track archive 在任何 sweep/mv 前校验 typed facts；旧 track 仍走旧路"
d="$(mktemp -d)"; mkdir -p "$d/tracks" "$d/wt"
( cd "$d"; git init -q -b main; git config user.email t@t; git config user.name t
  printf 'x\n' > README.md; git add -A; git commit -qm init )
$TRACK new typed-life "$d" >/dev/null 2>&1
printf '# Verify\n- 无机器证据:fixture\n' > "$d/tracks/typed-life/verify.md"
DELEGATE_WORKTREE_ROOT="$d/wt" $TRACK archive typed-life "$d" >/dev/null 2>&1; rc=$?
check "R6: typed facts 未完成时 archive 被挡" $([[ $rc -ne 0 ]]; echo $?)
check "R6: 被挡时目录原地不动" $([[ -d "$d/tracks/typed-life" && ! -d "$d/tracks/archive/typed-life" ]]; echo $?)
low_decision "$d/tracks/typed-life" typed-life '"PASS"'
DELEGATE_WORKTREE_ROOT="$d/wt" $TRACK archive typed-life "$d" >/dev/null 2>&1; rc=$?
check "R6: typed PASS 缺 observation 时仍在 sweep/mv 前被挡" $([[ $rc -ne 0 ]]; echo $?)
check "R6: 缺 observation 被挡时目录原地不动" $([[ -d "$d/tracks/typed-life" && ! -d "$d/tracks/archive/typed-life" ]]; echo $?)
write_observation "$d/tracks/typed-life" typed-life run-1 runlog execution_finished 0
DELEGATE_WORKTREE_ROOT="$d/wt" $TRACK archive typed-life "$d" >/dev/null 2>&1; rc=$?
check "R6: typed outcome/coverage 完整后无需在 Markdown 复制 Verdict 即可归档" $([[ $rc -eq 0 ]]; echo $?)
check "R6: typed track 确实移入 archive" $([[ -d "$d/tracks/archive/typed-life" ]]; echo $?)
mkdir -p "$d/tracks/legacy-life"
printf '# Verify\n- Verdict: ARCHIVED-SUPERSEDED\n- 无机器证据:fixture\n' > "$d/tracks/legacy-life/verify.md"
DELEGATE_WORKTREE_ROOT="$d/wt" $TRACK archive legacy-life "$d" >/dev/null 2>&1; rc=$?
check "R6: 无 decision 的旧 track 仍按 legacy 规则归档" $([[ $rc -eq 0 ]]; echo $?)
rm -rf "$d"

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
