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

write_panel_observation() { # track-dir track run-id family1 family2
  python3 - "$ROOT" "$1" "$2" "$3" "$4" "$5" <<'PY'
import json, pathlib, sys
root, track_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
track, run_id, family1, family2 = sys.argv[3:]
sys.path.insert(0, str(root / "bin"))
from _review_result import evidence_ref, sha256_bytes, sha256_file, subject_digest

identities = {
    "xiaomi": ("submimo", "xiaomi/mimo-v2.5-pro"),
    "deepseek": ("subdeepseek-agent", "deepseek-v4-flash"),
    "zhipu": ("subglm-agent", "go/glm-5.3-flash"),
    "moonshot": ("subkimi", "kimi-code/k3"),
    "google": ("subgemini", "gemini-3.7-flash-high"),
}
subject = {
    "manifest_version": 1,
    "task_sha256": sha256_bytes(b"task\n"),
    "source": {"git_object_format": "sha1", "head_oid": "1" * 40,
               "index_tree_oid": "2" * 40, "worktree_tree_oid": "3" * 40},
    "digest": None,
}
subject["digest"] = subject_digest(subject)
evidence_dir = track_dir / "review-evidence"
observation_dir = track_dir / "observations"
evidence_dir.mkdir(parents=True, exist_ok=True)
observation_dir.mkdir(parents=True, exist_ok=True)
legs = []
for index, family in enumerate((family1, family2), 1):
    adapter, model = identities[family]
    log = evidence_dir / f"{run_id}-leg{index}.log"
    log.write_text("Conclusion: PASS\n", encoding="utf-8")
    legs.append({
        "schema_version": 2, "review_contract_version": 1, "run_id": run_id,
        "name": f"leg{index}", "family": family, "adapter": adapter,
        "process": {"state": "exited", "exit_code": 0},
        "model": {"requested": model, "invoked": model, "reported": None},
        "subject": subject, "view": {"delivery_state": "complete", "mode": "full_snapshot"},
        "verdict": "PASS", "degraded": False,
        "evidence": {"completeness": "complete", "ref": evidence_ref(log), "digest": sha256_file(log)},
        "normalizer_version": 1, "duration_ms": 1,
        "usage": {"input_tokens": None, "output_tokens": None, "total_tokens": None,
                  "api_cost": None, "billing_mode": None},
        "failure_kind": "none",
    })
observation = {
    "schema_version": 2, "track": track, "run_id": run_id,
    "controller": "panel-review", "event": "execution_finished", "label": run_id,
    "started_at": "2026-08-21T01:00:00.000Z", "finished_at": "2026-08-21T01:00:01.000Z",
    "duration_ms": 100, "exit_code": 0,
    "actual": {"adapter": "panel-review", "model": None, "risk": "high",
               "degraded": False, "work_exit_code": 0, "legs": legs},
    "usage": {"input_tokens": None, "output_tokens": None, "total_tokens": None,
              "api_cost": None, "billing_mode": None},
}
(observation_dir / f"{run_id}-panel.json").write_text(json.dumps(observation), encoding="utf-8")
PY
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
# 模板停在 v1 = 新建的 track 全是 legacy-unbound，交付绑定那道闸对新交付
# 永远不生效。这里钉的是"新 track 默认受绑定"，不是某个数字。
assert p["schema_version"] == 2 and p["track"] == "typed-new"
assert p["impact"] == {"level": None, "factors": None}
assert p["design"]["uncertainty"] is None
assert p["design"]["premise_attack"] == {"status": None, "evidence": []}
assert p["execution_plan"] == {"adapter": None, "model": None}
assert p["outcome"] == {"verdict": None}
PY
check "R1: 初态字段精确、unknown=null 且不等于 false/[]" $?
rm -rf "$d"

d="$(mktemp -d)"; mkdir -p "$d/tracks/archive/reused"
( cd "$d"; git init -q; git config user.email t@t; git config user.name t )
out="$($TRACK new reused "$d" 2>&1)"; rc=$?
check "R1: archived 名称全生命周期唯一，不能新建同名 active 污染迟到回执" $([[ $rc -ne 0 ]]; echo $?)
check "R1: 同名拒绝时 archived 现场原样保留" $([[ -d "$d/tracks/archive/reused" && ! -d "$d/tracks/reused" ]]; echo $?)
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
write_decision "$d/t" t '"self"' '[]' '"low"' '"not_required"' '[]' '"delegate_codxe"' null null
out="$($RECORD validate --phase shape "$d/t" 2>&1)"; rc=$?
check "R2: execution adapter 拼错不能作为任意 token 混过去" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'path=execution_plan.adapter' <<<"$out" && grep -q 'delegate_codxe' <<<"$out"
check "R2: adapter enum trace 点名实际拼错值" $?
rm -rf "$d"

d="$(mktemp -d)"; mkdir -p "$d/t" "$d/outside"
shape_decision "$d/outside" t
ln -s "$d/outside/decision.json" "$d/t/decision.json"
out="$($RECORD validate --phase shape "$d/t" 2>&1)"; rc=$?
check "R2: working decision.json 不许是指向仓外可变事实的 symlink" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=decision.boundary' <<<"$out"
check "R2: decision symlink 边界 trace 明确" $?
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
write_decision "$d/t" t '"self"' '[]' '"low"' '"done"' '[]' '"main"' null null
out="$($RECORD validate --phase dispatch "$d/t" 2>&1)"; rc=$?
check "R3: low uncertainty 也不许把无 evidence 的 premise 标成 done" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=design.premise_evidence' <<<"$out"
check "R3: done 无 evidence 的 trace 明确" $?
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

echo "[R3b] staged dispatch 的 premise evidence 只认 index，不让 working 文件替提交应试"
d="$(mktemp -d)"; mkdir -p "$d/tracks/t"
( cd "$d"; git init -q; git config user.email t@t; git config user.name t )
write_decision "$d/tracks/t" t '"high"' '["new_write_surface"]' '"high"' '"done"' \
  '["premise.md"]' '"main"' null null
printf 'staged premise\n' > "$d/tracks/t/premise.md"
( cd "$d"; git add tracks/t/decision.json )
out="$($RECORD validate --phase dispatch --source staged "$d/tracks/t" 2>&1)"; rc=$?
check "R3b: 仅 working/untracked 的 premise evidence 不能冒充 staged" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=evidence.staged' <<<"$out"
check "R3b: 未 staged evidence 的 trace 明确" $?
( cd "$d"; git add tracks/t/premise.md; rm tracks/t/premise.md )
$RECORD validate --phase dispatch --source staged "$d/tracks/t" >/dev/null 2>&1; rc=$?
check "R3b: evidence 已 staged、working 已删仍按 index 放行" $([[ $rc -eq 0 ]]; echo $?)
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
python3 - "$d/t/observations/run-1-execution_finished.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["transcript"]="SECRET_SHOULD_NEVER_BE_ACCEPTED"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
out="$($RECORD validate --phase archive "$d/t" 2>&1)"; rc=$?
check "R4: observation 顶层夹带 transcript/额外字段时 archive fail closed" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=field.unknown' <<<"$out"
check "R4: observation 白名单违规给结构化 rule trace" $?
! grep -q 'SECRET_SHOULD_NEVER_BE_ACCEPTED' <<<"$out" && grep -q 'actual="<redacted>"' <<<"$out"
check "R4: 拒绝 secret/transcript 时 trace 只报字段、不回显内容" $?
write_observation "$d/t" t run-1 runlog execution_finished 0
python3 - "$d/t/observations/run-1-execution_finished.json" <<'PY'
import sys
with open(sys.argv[1], "a", encoding="utf-8") as f: f.write(" " * 70000)
PY
out="$($RECORD validate --phase shape "$d/t" 2>&1)"; rc=$?
check "R4: 单 observation 超过 64 KiB 即使只是合法 JSON whitespace 也拒绝" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=observation.size' <<<"$out"
check "R4: 超限 trace 只报字节数" $?
write_observation "$d/t" t run-1 runlog execution_finished 0
python3 - "$d/t/observations/run-1-execution_finished.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["usage"]["api_cost"]=float("inf")
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
out="$($RECORD validate --phase archive "$d/t" 2>&1)"; rc=$?
check "R4: observation 的 Infinity/NaN 非有限成本被拒绝" $([[ $rc -ne 0 ]]; echo $?)
write_observation "$d/t" t run-1 runlog execution_finished 0
printf 'FULL_TRANSCRIPT_SHOULD_NOT_LIVE_HERE\n' > "$d/t/observations/transcript.txt"
out="$($RECORD validate --phase archive "$d/t" 2>&1)"; rc=$?
check "R4: observations 目录夹带非 JSON transcript 时拒绝归档" $([[ $rc -ne 0 ]]; echo $?)
rm "$d/t/observations/transcript.txt"
write_observation "$d/t" t run-1 panel-review execution_finished 0
python3 - "$d/t/observations/run-1-execution_finished.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["actual"]["adapter"]="panel-review"; p["actual"]["legs"]=["not-an-object"]
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
out="$($RECORD validate --phase archive "$d/t" 2>&1)"; rc=$?
check "R4: malformed panel leg 被干净阻断而不是让 ledger 崩溃" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=field.type' <<<"$out"
check "R4: malformed leg trace 点名类型错误" $?
mapfile -t pool_legs < <( . "$ROOT/bin/_panel-roster-lib.sh"; printf '%s\n' "${PANEL_LEGS_ORDER[@]}" )
python3 - "$d/t/observations/run-1-execution_finished.json" "${pool_legs[@]}" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["actual"]["legs"]=[{
  "name":name,"family":name.removeprefix("sub"),"adapter":"agent","model":None,"state":"completed",
  "exit_code":0,"verdict":"PASS","degraded":False,"duration_ms":None,
  "usage":{"input_tokens":None,"output_tokens":None,"total_tokens":None,"api_cost":None,"billing_mode":None}
} for name in sys.argv[2:]]
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
out="$($RECORD validate --phase shape "$d/t" 2>&1)"; rc=$?
check "R4: 当前花名册全池可写进 compact observation，容量只由字节上限约束" $([[ $rc -eq 0 ]]; echo $?)
rm -rf "$d/t/observations"
low_decision "$d/t" t '"ARCHIVED-SUPERSEDED"'
$RECORD validate --phase archive "$d/t" >/dev/null 2>&1
check "R4: ARCHIVED-SUPERSEDED 可归档且无需冒充 PASS" $?
write_decision "$d/t" t '"self"' '[]' '"low"' '"not_required"' '[]' '"main"' null '"DONE"'
out="$($RECORD validate --phase shape "$d/t" 2>&1)"; rc=$?
check "R4: 自造 verdict 枚举被挡" $([[ $rc -ne 0 ]]; echo $?)
rm -rf "$d"

echo "[R4b] PASS archive 机械核对 impact-risk 的 0/1/2 外审家族预算"
d="$(mktemp -d)"
write_decision "$d/t" t '"high"' '["judging_control"]' '"low"' '"not_required"' '[]' '"main"' null '"PASS"'
write_observation "$d/t" t run-1 runlog execution_finished 0
out="$($RECORD validate --phase archive "$d/t" 2>&1)"; rc=$?
check "R4b: high PASS 只有 runlog、零外审腿 ⇒ archive BLOCK" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=observation.review_budget' <<<"$out" && grep -q 'required.*2' <<<"$out"
check "R4b: 外审缺口 trace 点名 required=2" $?
write_panel_observation "$d/t" t panel-1 xiaomi deepseek
$RECORD validate --phase archive "$d/t" >/dev/null 2>&1; rc=$?
check "R4b: high PASS 有成功 panel + 两个不同模型家族才可归档" $([[ $rc -eq 0 ]]; echo $?)
python3 - "$d/t/observations/panel-1-panel.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["actual"]["legs"][1]["family"]="xiaomi"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
out="$($RECORD validate --phase archive "$d/t" 2>&1)"; rc=$?
check "R4b: high 的两腿来自同一 family 仍不算双家族" $([[ $rc -ne 0 ]]; echo $?)
cp "$d/t/observations/panel-1-panel.json" "$d/t/observations/panel-2-failed.json"
python3 - "$d/t/observations/panel-2-failed.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["run_id"]="panel-2"; p["label"]="panel-2"
p["exit_code"]=1; p["actual"]["work_exit_code"]=1
p["actual"]["legs"]=p["actual"]["legs"][:1]
leg=p["actual"]["legs"][0]; leg["run_id"]="panel-2"; leg["family"]="deepseek"
leg["process"]={"state":"exited","exit_code":1}; leg["verdict"]="BLOCK"; leg["failure_kind"]="runtime"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
out="$($RECORD validate --phase archive "$d/t" 2>&1)"; rc=$?
check "R4b: 失败 panel 的第二 family 不能与成功单家族拼成 high 双家族" $([[ $rc -ne 0 ]]; echo $?)
rm "$d/t/observations/panel-2-failed.json"
python3 - "$d/t/observations/panel-1-panel.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); leg=p["actual"]["legs"][1]
leg["family"]="deepseek"; leg["process"]={"state":"exited","exit_code":1}
leg["verdict"]="BLOCK"; leg["failure_kind"]="runtime"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
out="$($RECORD validate --phase archive "$d/t" 2>&1)"; rc=$?
check "R4b: 成功 panel event 内的失败腿也不能补足第二家证据" $([[ $rc -ne 0 ]]; echo $?)
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

echo "[R7] delegate receive 可失败后重试；execution 仍不许重复计费"
d="$(mktemp -d)"
write_decision "$d/t" t '"self"' '[]' '"low"' '"not_required"' '[]' '"delegate-codex"' '"gpt-5.5"' '"PASS"'
write_observation "$d/t" t delegate-1 delegate-codex execution_finished 0
write_observation "$d/t" t delegate-1 delegate-codex received 1
mv "$d/t/observations/delegate-1-received.json" "$d/t/observations/delegate-1-received-first.json"
write_observation "$d/t" t delegate-1 delegate-codex received 0
$RECORD validate --phase archive "$d/t" >/dev/null 2>&1; rc=$?
check "R7: 同 run_id 的 received fail→pass 合法，任一成功即可收货" $([[ $rc -eq 0 ]]; echo $?)
cp "$d/t/observations/delegate-1-execution_finished.json" "$d/t/observations/duplicate-execution.json"
out="$($RECORD validate --phase archive "$d/t" 2>&1)"; rc=$?
check "R7: 同 execution_finished 重复导入仍拒绝双计" $([[ $rc -ne 0 ]]; echo $?)
grep -q 'rule=observation.duplicate' <<<"$out"
check "R7: 重复 execution trace 明确" $?
rm -rf "$d"

echo "[R8] observation writer 自己不制造 reader 随后会拒绝的记录"
d="$(mktemp -d)"; mkdir -p "$d/tracks/t"
common_obs=(observe --repo "$d" --track t --run-id r1 --event execution_finished --label r1 \
  --started-at 2026-08-21T00:00:00Z --finished-at 2026-08-21T00:00:01Z \
  --duration-ms 1 --exit-code 0 --work-exit-code 0)
out="$($RECORD "${common_obs[@]}" --controller runlog --adapter foo 2>&1)"; rc=$?
check "R8: controller/adapter mismatch 在写盘前拒绝" $([[ $rc -ne 0 ]]; echo $?)
check "R8: adapter mismatch 不留下 observation" $([[ ! -d "$d/tracks/t/observations" ]]; echo $?)
legs=()
for name in "${pool_legs[@]}"; do
  printf 'Conclusion: PASS\n' > "$d/$name.log"
  "$ROOT/bin/_review_result.py" emit --result "$d/$name.result.json" --run-id r1 \
    --name "$name" --family "${name#sub}" --adapter "$name" --exit-code 0 \
    --task-sha256 "sha256:$(printf task | sha256sum | cut -d' ' -f1)" --log "$d/$name.log" >/dev/null
  legs+=(--leg-result "$d/$name.result.json")
done
out="$($RECORD "${common_obs[@]}" --controller panel-review --adapter panel-review "${legs[@]}" 2>&1)"; rc=$?
check "R8: writer 接受运行时花名册全池，不另设固定腿数上限" $([[ $rc -eq 0 ]]; echo $?)
check "R8: 全池 observation 已真实落盘" \
  $(find "$d/tracks/t/observations" -maxdepth 1 -type f -name '*.json' -print -quit 2>/dev/null | grep -q .; echo $?)
rm -rf "$d/tracks/t/observations"
out="$($RECORD "${common_obs[@]}" --controller runlog --adapter runlog \
  --leg-result "$d/${pool_legs[0]}.result.json" 2>&1)"; rc=$?
check "R8: 非 panel controller 带 --leg-result 给结构化 BLOCK、不是 traceback" \
  $([[ $rc -ne 0 && "$out" == *'rule=observation.leg_controller'* && "$out" != *Traceback* ]]; echo $?)
out="$($RECORD "${common_obs[@]}" --controller panel-review --adapter panel-review \
  --leg x,family,agent,0,PASS,false 2>&1)"; rc=$?
check "R8: v1 --leg writer 已关闭，旧 observation 只读" \
  $([[ $rc -ne 0 && "$out" == *'rule=observation.v1_writer_disabled'* ]]; echo $?)
rm -rf "$d"

echo "[R9] ReviewLegResult v2 reader 保持严格兼容"
d="$(mktemp -d)"; mkdir -p "$d/tracks/v2/observations" "$d/logs"
( cd "$d"; git init -q; git config user.email t@t; git config user.name t )
low_decision "$d/tracks/v2" v2 null
printf 'finding\nConclusion: PASS\n' > "$d/logs/leg.log"
python3 - "$ROOT" "$d" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1]); repo=pathlib.Path(sys.argv[2])
sys.path.insert(0, str(root/'bin'))
from _review_result import evidence_ref, sha256_bytes, sha256_file, subject_digest
subject={
  "manifest_version":1,
  "task_sha256":sha256_bytes(b"task\n"),
  "source":{"git_object_format":"sha1","head_oid":"1"*40,
            "index_tree_oid":"2"*40,"worktree_tree_oid":"3"*40},
  "digest":None,
}
subject["digest"]=subject_digest(subject)
leg={
  "schema_version":2,"review_contract_version":1,"run_id":"v2-panel","name":"subkimi",
  "family":"moonshot","adapter":"subkimi","process":{"state":"exited","exit_code":0},
  "model":{"requested":"kimi-code/k3","invoked":"kimi-code/k3","reported":None},
  "subject":subject,"view":{"delivery_state":"complete","mode":"full_snapshot"},
  "verdict":"PASS","degraded":False,
  "evidence":{"completeness":"complete","ref":evidence_ref(repo/'logs/leg.log'),
              "digest":sha256_file(repo/'logs/leg.log')},
  "normalizer_version":1,"duration_ms":1,
  "usage":{"input_tokens":None,"output_tokens":None,"total_tokens":None,
           "api_cost":None,"billing_mode":None},"failure_kind":"none",
}
obs={
  "schema_version":2,"track":"v2","run_id":"v2-panel","controller":"panel-review",
  "event":"execution_finished","label":"v2-panel",
  "started_at":"2026-08-21T01:00:00Z","finished_at":"2026-08-21T01:00:01Z",
  "duration_ms":100,"exit_code":0,
  "actual":{"adapter":"panel-review","model":None,"risk":"self","degraded":False,
            "work_exit_code":0,"legs":[leg]},
  "usage":{"input_tokens":None,"output_tokens":None,"total_tokens":None,
           "api_cost":None,"billing_mode":None},
}
(repo/'tracks/v2/observations/v2-panel.json').write_text(json.dumps(obs), encoding='utf-8')
PY
ledger="$($RECORD ledger --repo "$d" --format json)"; rc=$?
LEDGER="$ledger" python3 - <<'PY'
import json,os
p=json.loads(os.environ['LEDGER']); t=next(x for x in p['tracks'] if x['track']=='v2')
assert t['coverage']['invalid_observations']==0
assert t['quality']['panel_legs']==1 and t['quality']['failed_panel_legs']==0
PY
assert_rc=$?
check "R9: ledger 严格读取 v2 leg，且旧 consumer 不因嵌套 process 形状崩溃" \
  $([[ $rc -eq 0 && $assert_rc -eq 0 ]]; echo $?)
python3 - "$d/tracks/v2/observations/v2-panel.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p['schema_version']=3
json.dump(p, open(sys.argv[1],'w'))
PY
ledger="$($RECORD ledger --repo "$d" --format json)"
LEDGER="$ledger" python3 - <<'PY'
import json,os
p=json.loads(os.environ['LEDGER']); t=next(x for x in p['tracks'] if x['track']=='v2')
assert t['coverage']['invalid_observations']==1
PY
check "R9: 未知未来 observation schema fail closed，不猜成 v2" $?
rm -rf "$d"

echo "[R10] archive/ledger 共用 v2 coverage predicate；跨对象/跨 run/v1 都不拼放行"
d="$(mktemp -d)"; cases="$d/tracks"; mkdir -p "$cases"
coverage_case() { # name
  write_decision "$cases/$1" "$1" '"high"' '["judging_control"]' '"low"' '"not_required"' '[]' '"main"' null '"PASS"'
  write_observation "$cases/$1" "$1" runlog-1 runlog execution_finished 0
  write_panel_observation "$cases/$1" "$1" panel-1 xiaomi deepseek
}

coverage_case unknown
python3 - "$cases/unknown/observations/panel-1-panel.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["actual"]["legs"][0]["verdict"]="UNKNOWN"
p["actual"]["legs"][0]["failure_kind"]="no_verdict"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
out="$($RECORD validate --phase archive "$cases/unknown" 2>&1)"; rc=$?
check "R10: rc=0 + UNKNOWN 不是 coverage" $([[ $rc -ne 0 ]]; echo $?)

coverage_case degraded
python3 - "$cases/degraded/observations/panel-1-panel.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["actual"]["legs"][0]["degraded"]=True
p["actual"]["degraded"]=True
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
out="$($RECORD validate --phase archive "$cases/degraded" 2>&1)"; rc=$?
check "R10: degraded 的明确结论仍不算 coverage" $([[ $rc -ne 0 ]]; echo $?)

coverage_case timeout
python3 - "$cases/timeout/observations/panel-1-panel.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); leg=p["actual"]["legs"][0]
leg["process"]={"state":"timed_out","exit_code":124}; leg["failure_kind"]="timeout"
leg["evidence"]["completeness"]="partial"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
out="$($RECORD validate --phase archive "$cases/timeout" 2>&1)"; rc=$?
check "R10: timeout 保留 PASS 也不能提升成 coverage" $([[ $rc -ne 0 ]]; echo $?)

coverage_case different-subject
python3 - "$ROOT" "$cases/different-subject/observations/panel-1-panel.json" <<'PY'
import json,pathlib,sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "bin"))
from _review_result import subject_digest
p=json.load(open(sys.argv[2])); subject=p["actual"]["legs"][1]["subject"]
subject["source"]["worktree_tree_oid"]="4"*40; subject["digest"]=subject_digest(subject)
json.dump(p, open(sys.argv[2], "w"), indent=2)
PY
out="$($RECORD validate --phase archive "$cases/different-subject" 2>&1)"; rc=$?
check "R10: 同一 run 的不同 subject 不能拼双家族" $([[ $rc -ne 0 ]]; echo $?)

coverage_case cross-run
write_panel_observation "$cases/cross-run" cross-run panel-2 xiaomi deepseek
python3 - "$cases/cross-run/observations/panel-1-panel.json" "$cases/cross-run/observations/panel-2-panel.json" <<'PY'
import json,sys
first=json.load(open(sys.argv[1])); first["actual"]["legs"]=first["actual"]["legs"][:1]
json.dump(first, open(sys.argv[1], "w"), indent=2)
second=json.load(open(sys.argv[2])); second["actual"]["legs"]=second["actual"]["legs"][1:]
json.dump(second, open(sys.argv[2], "w"), indent=2)
PY
out="$($RECORD validate --phase archive "$cases/cross-run" 2>&1)"; rc=$?
check "R10: 同 subject 跨 run 双家族只能 shadow、不能 archive" $([[ $rc -ne 0 ]]; echo $?)

write_decision "$cases/same-family" same-family '"high"' '["judging_control"]' '"low"' '"not_required"' '[]' '"main"' null '"PASS"'
write_observation "$cases/same-family" same-family runlog-1 runlog execution_finished 0
write_panel_observation "$cases/same-family" same-family panel-1 xiaomi xiaomi
out="$($RECORD validate --phase archive "$cases/same-family" 2>&1)"; rc=$?
check "R10: 同 family 的重试次数不冒充家族数" $([[ $rc -ne 0 ]]; echo $?)

coverage_case conflict
python3 - "$cases/conflict/observations/panel-1-panel.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["actual"]["legs"][1]["verdict"]="BLOCK"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
out="$($RECORD validate --phase archive "$cases/conflict" 2>&1)"; rc=$?
check "R10: 同 run 同 subject 的 PASS/BLOCK 冲突阻断资格" $([[ $rc -ne 0 ]]; echo $?)

write_decision "$cases/v1-history" v1-history '"high"' '["judging_control"]' '"low"' '"not_required"' '[]' '"main"' null '"PASS"'
write_observation "$cases/v1-history" v1-history runlog-1 runlog execution_finished 0
write_observation "$cases/v1-history" v1-history panel-1 panel-review execution_finished 0
python3 - "$cases/v1-history/observations/panel-1-execution_finished.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["actual"]["legs"]=[
  {"name":name,"family":family,"adapter":"agent","model":None,"state":"completed",
   "exit_code":0,"verdict":"PASS","degraded":False,"duration_ms":None,
   "usage":{"input_tokens":None,"output_tokens":None,"total_tokens":None,
            "api_cost":None,"billing_mode":None}}
  for name,family in (("old-1","xiaomi"),("old-2","deepseek"))]
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
out="$($RECORD validate --phase archive "$cases/v1-history" 2>&1)"; rc=$?
check "R10: v1 observation 可读但不再产生 authoritative coverage" $([[ $rc -ne 0 ]]; echo $?)

ledger="$($RECORD ledger --repo "$d" --format json)"; rc=$?
LEDGER="$ledger" python3 - <<'PY'
import json,os
tracks={item["track"]:item for item in json.loads(os.environ["LEDGER"])["tracks"]}
assert tracks["unknown"]["quality"]["process_successful_panel_legs"] == 2
assert tracks["unknown"]["quality"]["substantive_panel_legs"] == 1
assert tracks["unknown"]["quality"]["coverage_eligible_panel_legs"] == 1
assert tracks["timeout"]["quality"]["process_successful_panel_legs"] == 1
assert tracks["timeout"]["quality"]["substantive_panel_legs"] == 2
assert tracks["timeout"]["quality"]["coverage_eligible_panel_legs"] == 1
assert tracks["different-subject"]["quality"]["coverage_eligible_panel_legs"] == 2
assert tracks["different-subject"]["quality"]["authoritative_family_count"] == 1
assert tracks["cross-run"]["quality"]["authoritative_family_count"] == 1
assert tracks["cross-run"]["quality"]["same_subject_shadow_family_count"] == 2
assert tracks["same-family"]["quality"]["authoritative_family_count"] == 1
assert tracks["conflict"]["quality"]["coverage_eligible_panel_legs"] == 2
assert tracks["conflict"]["quality"]["authoritative_family_count"] == 0
assert tracks["conflict"]["quality"]["authoritative_conflicting_groups"] == 1
assert tracks["v1-history"]["quality"]["process_successful_panel_legs"] == 2
assert tracks["v1-history"]["quality"]["substantive_panel_legs"] == 2
assert tracks["v1-history"]["quality"]["coverage_eligible_panel_legs"] == 0
assert tracks["v1-history"]["quality"]["authoritative_family_count"] == 0
PY
assert_rc=$?
check "R10: ledger 分列 process/substantive/eligible，并把跨 run 家族只报 shadow" \
  $([[ $rc -eq 0 && $assert_rc -eq 0 ]]; echo $?)
rm -rf "$d"

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
