#!/usr/bin/env bash
# panel-slice oracle —— 单层多家族切片评审(track sliced-panel-review)。外部腿全是桩。
#
# 这份判据问的是「调度器有没有照契约办事」,不问「切片审得好不好」:
#   · N 片 + 1 条整体腿 ⇒ 恰好 N+1 次腿调用,家族两两不同(不许暗中多一次调用);
#   · 起进程之前 plan.json 与本次尝试的 reserved.json 已在盘上(控制器随时会死);
#   · 切片结果在**数据上**标成新契约,旧覆盖谓词不认;不写任何 track observation;
#   · 预算、换家族复核、只追加的问题账、旧 BLOCK 不被新 PASS 抹掉、源码变了拒绝;
#   · 控制器被整组砍掉时说「不知道」(unknown),不说「失败了」。
# 桩腿永远乖 —— 真腿在任务书之外乱读、在 shell 里调别的 AI CLI,这份判据一条都测不到
# (design.md「这个 oracle 能被什么骗过」)。
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 腿开关、健康覆盖、分配起点……全走环境变量。调用者环境里飘着一个 `PANEL_KIMI_LEG=off`
# 就能让整段判据问不到某条腿(2026-08-26 实测过同一种病),所以先清干净再跑。
# 要清哪些开关从唯一源长出来,不在这里抄腿名单。
if [[ "${PANEL_SLICE_ENV_SCRUBBED:-}" != "1" ]]; then
  . "$ROOT/bin/_panel-roster-lib.sh"
  _unset=()
  for _spec in "${PANEL_LEG_SPECS[@]}" ${PANEL_ROLE_LEG_SPECS[@]+"${PANEL_ROLE_LEG_SPECS[@]}"}; do
    _unset+=(-u "${_spec##*|}")
  done
  exec env "${_unset[@]}" -u PANEL_HEALTH_OVERRIDE -u PANEL_SELECTION_START -u PANEL_STATE_DIR \
    -u PANEL_STAGGER_MAX -u PANEL_IMPACT_RISK -u PANEL_REVIEW_BUDGET -u PANEL_DIFF_BASE \
    -u PANEL_INCLUDE -u PANEL_ORACLE_CMD -u PANEL_SLICE_ASSIGN_START -u PANEL_SLICE_RUN_ROOT \
    -u REVIEW_MY_REVIEW -u REVIEW_NO_MY_REVIEW -u AIWORK_REVIEW_TRACK \
    PANEL_SLICE_ENV_SCRUBBED=1 bash "$0" "$@"
fi
. "$ROOT/bin/_panel-roster-lib.sh"

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

echo "=== panel-slice oracle ==="

echo "[S0] 角色腿表:GPT 整体腿有身份,但不在普通轮换池"
declare -p PANEL_ROLE_LEG_SPECS >/dev/null 2>&1 && declare -p PANEL_ROLE_LEGS_ORDER >/dev/null 2>&1
check "S0: _panel-roster-lib.sh 定义了 PANEL_ROLE_LEG_SPECS / PANEL_ROLE_LEGS_ORDER" $?
ROLE_LEGS=(${PANEL_ROLE_LEGS_ORDER[@]+"${PANEL_ROLE_LEGS_ORDER[@]}"})
_has_codex=1
for _r in ${ROLE_LEGS[@]+"${ROLE_LEGS[@]}"}; do
  [[ "$_r" == subcodex && "$(panel_leg_family subcodex 2>/dev/null)" == openai ]] && _has_codex=0
done
check "S0: 角色腿含 subcodex(family=openai),取值函数查得到" "$_has_codex"
_in_pool=0
for _l in "${PANEL_LEGS_ORDER[@]}"; do [[ "$_l" == subcodex ]] && _in_pool=1; done
check "S0: subcodex 不在普通轮换池 PANEL_LEGS_ORDER 里" "$_in_pool"
POOL=("${PANEL_LEGS_ORDER[@]}")
P="${#POOL[@]}"

# ── 桩腿 ────────────────────────────────────────────────────────────────
# 行为由 $SLICE_TEST_MODES/<item>.<attempt> → <item> → leg-<二进制名> 依次决定;默认 pass。
# 起跑那一刻记一行(含 plan.json / reserved.json 在不在),收尾再记一行结束时间。
STUB="$TMP_ROOT/stub.sh"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
self="$(basename "$0")"; task="$2"; log="$3"; repo="$4"
attempt_dir="$(cd "$(dirname "$task")" && pwd)"
item="$(basename "$(dirname "$attempt_dir")")"
attempt="$(basename "$attempt_dir")"; attempt="${attempt#attempt-}"
run_dir="$(cd "$attempt_dir/../../.." && pwd)"
plan_ok=0; [[ -s "$run_dir/plan.json" ]] && plan_ok=1
res_ok=0; [[ -s "$attempt_dir/reserved.json" ]] && res_ok=1
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$self" "$item" "$attempt" "$task" "$plan_ok" "$res_ok" \
  "$(date +%s%N)" >> "$SLICE_TEST_CALLS"
mode=pass
for key in "$item.$attempt" "$item" "leg-$self"; do
  if [[ -f "$SLICE_TEST_MODES/$key" ]]; then mode="$(cat "$SLICE_TEST_MODES/$key")"; break; fi
done
case "$mode" in sleep:*) sleep "${mode#sleep:}"; mode=pass ;; esac
rc=0; verdict=""
case "$mode" in
  pass) verdict='Conclusion: PASS' ;;
  block) verdict='Conclusion: BLOCK' ;;
  nmi) verdict='Conclusion: NEEDS_MORE_INFO' ;;
  noverdict) verdict='I read some files.' ;;
  fail) rc=7 ;;
esac
if [[ -n "$verdict" ]]; then printf 'stub report %s %s\n%s\n' "$self" "$item" "$verdict" > "$log"; fi
if [[ "$rc" -eq 0 ]]; then
  model="$(python3 - "$AIWORK_REVIEW_RESULT_BIN" "$AIWORK_REVIEW_ADAPTER" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
ident = rr.ADAPTER_IDENTITIES.get(sys.argv[2])
print(ident[1] + "fixture" if ident else "unknown-fixture")
PY
)"
  tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
  python3 "$AIWORK_REVIEW_RESULT_BIN" facts --output "$AIWORK_REVIEW_FACTS_PATH" \
    --requested-model "$model" --invoked-model "$model" \
    --git-object-format "$(git -C "$repo" rev-parse --show-object-format)" \
    --head-oid "$(git -C "$repo" rev-parse HEAD)" --index-tree-oid "$tree" --worktree-tree-oid "$tree" \
    --view-delivery-state complete --view-mode full_snapshot --evidence-completeness complete
fi
printf '%s\t%s\t%s\n' "$item" "$attempt" "$(date +%s%N)" >> "$SLICE_TEST_CALLS.end"
exit "$rc"
EOF
chmod +x "$STUB"

make_fixture() {  # make_fixture <root>
  local d="$1" b="$1/bin" spec name family agent chat switch f
  mkdir -p "$b" "$d/repo/tracks/current" "$d/state" "$d/tasks" "$d/modes" "$d/runs"
  for f in panel-slice _panel_slice.py panel-review _panel-roster-lib.sh _review_result.py track-record; do
    [[ -e "$ROOT/bin/$f" ]] && cp "$ROOT/bin/$f" "$b/"
  done
  # 桩名单从两张表长出来(底座腿 + 聊天腿两种二进制都铺)。
  for spec in "${PANEL_LEG_SPECS[@]}" ${PANEL_ROLE_LEG_SPECS[@]+"${PANEL_ROLE_LEG_SPECS[@]}"}; do
    IFS='|' read -r name family agent chat switch <<<"$spec"
    for f in $agent $chat; do cp "$STUB" "$b/$f"; chmod +x "$b/$f"; done
  done
  cat > "$d/repo/tracks/current/decision.json" <<'EOF'
{
  "schema_version": 1,
  "track": "current",
  "impact": {"level": "high", "factors": []},
  "design": {"uncertainty": "low", "premise_attack": {"status": "not_required", "evidence": []}},
  "execution_plan": {"adapter": "main", "model": null},
  "outcome": {"verdict": null}
}
EOF
  printf '# Verify\n' > "$d/repo/tracks/current/verify.md"
  ( cd "$d/repo" && git init -q -b main && git config user.email t@t && git config user.name t \
    && printf 'x\n' > app.txt && git add -A && git commit -qm init )
  printf 'my own review first\n' > "$d/tasks/manifest-my-review.md"
  : > "$d/calls"
}

write_manifest() {  # write_manifest <fixture> <n_slices> [extra|-] [overall_leg|-] [max_concurrency|-]
  python3 - "$@" <<'PY'
import json, pathlib, sys
d = pathlib.Path(sys.argv[1]) / "m"; n = int(sys.argv[2])
arg = lambda i: sys.argv[i] if len(sys.argv) > i and sys.argv[i] != "-" else None
d.mkdir(parents=True, exist_ok=True)
(d / "goal.md").write_text("# Goal\nGOAL_SENTINEL_7f3\n")
slices = []
for i in range(n):
    sid = f"s{i+1}"
    (d / f"{sid}.md").write_text(f"# brief {sid}\nSLICE_SENTINEL_{sid}_x\n")
    slices.append({"id": sid, "title": f"Title-{sid}", "brief": f"{sid}.md"})
m = {"version": 1, "goal": "goal.md", "slices": slices, "budget": {"extra_sessions": int(arg(3) or 2)}}
if arg(4):
    m["overall"] = {"leg": arg(4)}
if arg(5):
    m["budget"]["max_concurrency"] = int(arg(5))
(d / "manifest.json").write_text(json.dumps(m, indent=2))
PY
}

slice() {  # slice <fixture> <panel-slice args...>
  local d="$1"; shift
  SLICE_TEST_CALLS="$d/calls" SLICE_TEST_MODES="$d/modes" PANEL_STATE_DIR="$d/state" \
    PANEL_STAGGER_MAX=0 PANEL_SLICE_ASSIGN_START=0 bash "$d/bin/panel-slice" "$@"
}
# 拒绝一律要说出机器可读的理由:`panel-slice: REFUSED <rule>`。只看「rc≠0 且零调用」的话,
# 程序根本不存在(rc=127)也会满足 —— 实现前红检时一整批拒绝断言就是这样恒绿的(2026-09-13 实测)。
refused() { grep -q "panel-slice: REFUSED $1" <<<"$2"; }
ncalls() { [[ -f "$1/calls" ]] && wc -l < "$1/calls" | tr -d ' ' || echo 0; }
status_json() {  # status_json <fixture> <run> -> $1/st.json
  slice "$1" status "$2" --json > "$1/st.json" 2>"$1/st.err"
}
jq_py() {  # jq_py <json-file> <python expr over `s`>  —— 真返回 0,假/异常返回 1
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    s = json.load(open(sys.argv[1], encoding="utf-8"))
    sys.exit(0 if eval(sys.argv[2], {"s": s}) else 1)
except Exception as exc:
    print(f"    (jq_py: {type(exc).__name__}: {exc})", file=sys.stderr)
    sys.exit(1)
PY
}

# ═══════════════════════════════════════════════════════════════════════
echo "[S1] 池里每条健康腿各审一片 + GPT 整体腿 ⇒ 恰好 P+1 次调用、家族两两不同"
d="$TMP_ROOT/s1"; make_fixture "$d"; write_manifest "$d" "$P"
printf '3\n' > "$d/state/cursor"
run="$d/runs/r1"
out="$(slice "$d" run "$d/m/manifest.json" "$d/repo" "$run" 2>&1)"; rc=$?; s1rc=$rc
check "S1: run 正常结束(rc=0)" $([[ $rc -eq 0 ]]; echo $?)
[[ $rc -eq 0 ]] || printf '%s\n' "$out" | tail -15 | sed 's/^/    | /'
check "S1: 恰好 $((P+1)) 次腿调用(P=$P 片 + 1 条整体腿,零暗中加调用)" \
  $([[ "$(ncalls "$d")" -eq $((P+1)) ]]; echo $?)
python3 - "$d/calls" "$ROOT/bin/_panel-roster-lib.sh" <<'PY'
import subprocess, sys
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
def family(binname):
    # 二进制名 → 腿名 → 家族,全部问唯一源
    out = subprocess.run(["bash", "-c", '. "$1"; for s in "${PANEL_LEG_SPECS[@]}" ${PANEL_ROLE_LEG_SPECS[@]+"${PANEL_ROLE_LEG_SPECS[@]}"}; do IFS="|" read -r n f a c w <<<"$s"; [[ "$2" == "$a" || "$2" == "$c" ]] && echo "$f"; done', "_", sys.argv[2], binname], capture_output=True, text=True).stdout.split()
    return out[0] if out else None
fams = [family(r[0]) for r in rows]
assert None not in fams, fams
assert len(set(fams)) == len(fams), fams
overall = [f for r, f in zip(rows, fams) if r[1] == "overall"]
assert overall == ["openai"], overall
assert sum(1 for r in rows if r[1] != "overall") == len(rows) - 1
PY
check "S1: 各项家族两两不同,整体腿是 openai(subcodex)且不与任何片同家族" $?
awk -F'\t' '$5 != 1 || $6 != 1 {bad=1} END {exit bad ? 1 : (NR > 0 ? 0 : 1)}' "$d/calls"
check "S1: 每条腿启动那一刻 plan.json 与自己的 reserved.json 都已落盘" $?
python3 - "$d/calls" "$run" "$P" <<'PY'
import sys
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
run, n = sys.argv[2], int(sys.argv[3])
ids = [f"s{i+1}" for i in range(n)]
assert len(rows) == n + 1, ("对零行做循环会恒绿", len(rows))
for r in rows:
    text = open(r[3], encoding="utf-8").read()
    assert "GOAL_SENTINEL_7f3" in text, r[1]
    assert run not in text, ("run dir leaked into task", r[1])
    if r[1] == "overall":
        assert all(f"Title-{i}" in text for i in ids), "overall misses slice titles"
    else:
        assert f"SLICE_SENTINEL_{r[1]}_x" in text, r[1]
        others = [i for i in ids if i != r[1] and f"SLICE_SENTINEL_{i}_x" in text]
        assert not others, (r[1], others)
PY
check "S1: 片任务书只含本片 brief、不含别片;整体腿含全部片标题;任何任务书不含 run 目录路径" $?
_contract=0; _nres=0
while IFS= read -r -d '' _res; do
  _nres=$((_nres+1))
  _elig="$(python3 "$d/bin/_review_result.py" eligible "$_res" 2>/dev/null)"; _erc=$?
  python3 - "$_res" "$_elig" "$_erc" <<'PY' || _contract=1
import json, sys
r = json.load(open(sys.argv[1]))
assert r["review_contract_version"] == 2, r["review_contract_version"]
assert sys.argv[3] != "0"
assert json.loads(sys.argv[2])["reasons"] == ["review_contract_unsupported"], sys.argv[2]
PY
done < <(find "$run" -name '*.result.json' -print0 2>/dev/null)
check "S1: 每份腿结果契约版本=2,旧覆盖谓词判否且理由恰好是 review_contract_unsupported($_nres 份)" \
  $([[ $_contract -eq 0 && $_nres -eq $((P+1)) ]]; echo $?)
check "S1: fixture 仓的 typed track 下零 observation(切片结果不进归档覆盖)" \
  $([[ $s1rc -eq 0 && -z "$(find "$d/repo/tracks" -path '*/observations/*' -type f 2>/dev/null)" ]]; echo $?)
check "S1: 普通轮换游标没被切片派发推动" $([[ $s1rc -eq 0 && "$(cat "$d/state/cursor" 2>/dev/null)" == 3 ]]; echo $?)
status_json "$d" "$run"
jq_py "$d/st.json" "s['run_state'] == 'clean' and s['budget']['initial_sessions'] == $((P+1)) and s['budget']['initial_used'] == $((P+1)) and s['budget']['extra_used'] == 0 and all(i['covered'] for i in s['items']) and all(a['state'] == 'done' for i in s['items'] for a in i['attempts'])"
check "S1: status 从盘上重建:全部 done、run_state=clean、预算账对得上" $?
cp "$d/st.json" "$d/st1.json"; status_json "$d" "$run"
check "S1: status --json 重复调用逐字节相同(无时间戳,纯读盘)" \
  $(jq_py "$d/st1.json" "s['items']" && cmp -s "$d/st.json" "$d/st1.json"; echo $?)
grep -q '不是裁决\|not a verdict' <<<"$(slice "$d" status "$run" 2>&1)"
check "S1: 人读 status 明说 run_state 不是裁决" $?

# ═══════════════════════════════════════════════════════════════════════
echo "[S2] 派发前拒绝:家族凑不齐 / 不健康 / 整体腿撞家族 / GPT 腿不可用 —— 一律零调用"
d="$TMP_ROOT/s2"; make_fixture "$d"
if [[ "$P" -lt 8 ]]; then
  write_manifest "$d" $((P+1))
  out="$(slice "$d" run "$d/m/manifest.json" "$d/repo" "$d/runs/too-many" 2>&1)"; rc=$?
  check "S2: $((P+1)) 片 > 健康家族数 $P ⇒ 拒绝(REFUSED families)" $([[ $rc -ne 0 ]] && refused families "$out"; echo $?)
  check "S2: 家族不够的拒绝发生在任何腿调用之前" $(refused families "$out" && [[ "$(ncalls "$d")" -eq 0 ]]; echo $?)
  check "S2: 拒绝时一份 reserved.json 都没有(没占额度)" \
    $(refused families "$out" && [[ -z "$(find "$d/runs" -name reserved.json 2>/dev/null)" ]]; echo $?)
  grep -qi 'famil\|家族' <<<"$out"
  check "S2: 拒绝理由说出是家族不够" $?
fi
write_manifest "$d" "$P"
out="$(PANEL_HEALTH_OVERRIDE="${POOL[0]}=quota" slice "$d" run "$d/m/manifest.json" "$d/repo" "$d/runs/unhealthy" 2>&1)"; rc=$?
check "S2: ${POOL[0]} 标 quota 后 $P 片凑不齐 ⇒ 拒绝且零调用" \
  $([[ $rc -ne 0 && "$(ncalls "$d")" -eq 0 ]] && refused families "$out"; echo $?)
write_manifest "$d" $((P-1))
out="$(PANEL_HEALTH_OVERRIDE="${POOL[0]}=quota" slice "$d" run "$d/m/manifest.json" "$d/repo" "$d/runs/skip-unhealthy" 2>&1)"; rc=$?
_agent0="$(panel_leg_agent "${POOL[0]}")"
check "S2: $((P-1)) 片时照常派发,且不健康的 ${POOL[0]} 一次都没被调用" \
  $([[ $rc -eq 0 && "$(ncalls "$d")" -eq $P ]] && ! cut -f1 "$d/calls" | grep -qx "$_agent0"; echo $?)
: > "$d/calls"
write_manifest "$d" 2 - "$(printf '%s' "${POOL[0]}")"
python3 - "$d/m/manifest.json" "${POOL[0]}" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])); m["slices"][0]["leg"] = sys.argv[2]
json.dump(m, open(sys.argv[1], "w"))
PY
out="$(slice "$d" run "$d/m/manifest.json" "$d/repo" "$d/runs/overall-clash" 2>&1)"; rc=$?
check "S2: 整体腿与某片钉同一家族 ⇒ 拒绝且零调用" $([[ $rc -ne 0 && "$(ncalls "$d")" -eq 0 ]] && refused families "$out"; echo $?)
write_manifest "$d" 2
out="$(PANEL_CODEX_LEG=off slice "$d" run "$d/m/manifest.json" "$d/repo" "$d/runs/no-gpt" 2>&1)"; rc=$?
check "S2: 默认整体腿 subcodex 被关掉 ⇒ 拒绝且零调用(不静默换成别的腿)" \
  $([[ $rc -ne 0 && "$(ncalls "$d")" -eq 0 ]] && refused overall-leg "$out"; echo $?)
grep -q 'subcodex' <<<"$out"
check "S2: 拒绝理由点名 subcodex" $?

# ═══════════════════════════════════════════════════════════════════════
echo "[S3] 输入闸:清单非法 / my-review 缺失或在仓内 / run 目录在仓内 —— 一律零调用"
d="$TMP_ROOT/s3"; make_fixture "$d"; write_manifest "$d" 2
bad_manifest() {  # bad_manifest <label> <python mutation over m>
  write_manifest "$d" 2
  python3 - "$d/m/manifest.json" "$2" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])); exec(sys.argv[2]); json.dump(m, open(sys.argv[1], "w"))
PY
  local out rc
  out="$(slice "$d" run "$d/m/manifest.json" "$d/repo" "$d/runs/bad-$RANDOM" 2>&1)"; rc=$?
  check "S3: 清单非法($1)⇒ 拒绝且零调用" $([[ $rc -ne 0 && "$(ncalls "$d")" -eq 0 ]] && refused manifest "$out"; echo $?)
}
bad_manifest "未知字段" 'm["surprise"] = 1'
bad_manifest "只有 1 片" 'm["slices"] = m["slices"][:1]'
bad_manifest "片 id 重复" 'm["slices"][1]["id"] = m["slices"][0]["id"]'
bad_manifest "片 id 用了保留字 overall" 'm["slices"][0]["id"] = "overall"'
bad_manifest "brief 文件不存在" 'm["slices"][0]["brief"] = "missing.md"'
bad_manifest "version 不是 1" 'm["version"] = 2'
write_manifest "$d" 2
rm -f "$d/tasks/manifest-my-review.md"
out="$(slice "$d" run "$d/m/manifest.json" "$d/repo" "$d/runs/no-mr" 2>&1)"; rc=$?
check "S3: 约定位置没有自审文件 ⇒ 拒绝且零调用(反锚定闸默认开)" \
  $([[ $rc -ne 0 && "$(ncalls "$d")" -eq 0 ]] && refused my-review "$out"; echo $?)
printf 'mine\n' > "$d/repo/mine-my-review.md"
out="$(slice "$d" run --require-my-review "$d/repo/mine-my-review.md" "$d/m/manifest.json" "$d/repo" "$d/runs/mr-in-repo" 2>&1)"; rc=$?
check "S3: 自审文件在被评审仓内 ⇒ 拒绝且零调用" $([[ $rc -ne 0 && "$(ncalls "$d")" -eq 0 ]] && refused my-review "$out"; echo $?)
printf 'mine\n' > "$d/tasks/manifest-my-review.md"
out="$(slice "$d" run "$d/m/manifest.json" "$d/repo" "$d/repo/slice-run" 2>&1)"; rc=$?
check "S3: run 目录在被评审仓内 ⇒ 拒绝且零调用(同伴报告不许进腿的快照)" \
  $([[ $rc -ne 0 && "$(ncalls "$d")" -eq 0 ]] && refused run-dir "$out"; echo $?)
out="$(slice "$d" run "$d/m/manifest.json" "$d/repo" "$d/runs/twice" 2>&1)"; rc1=$?
n1="$(ncalls "$d")"
out="$(slice "$d" run "$d/m/manifest.json" "$d/repo" "$d/runs/twice" 2>&1)"; rc2=$?
check "S3: 同一个 run 目录不许 run 第二次(不覆盖已有证据)" \
  $([[ $rc1 -eq 0 && $rc2 -ne 0 && "$(ncalls "$d")" -eq "$n1" ]] && refused run-dir "$out"; echo $?)

# ═══════════════════════════════════════════════════════════════════════
echo "[S4] retry:占 extra、超额整批拒绝、旧尝试的 BLOCK 不会被新 PASS 抹掉"
d="$TMP_ROOT/s4"; make_fixture "$d"; write_manifest "$d" 2 2
printf 'block\n' > "$d/modes/s1.1"; printf 'fail\n' > "$d/modes/s2.1"
run="$d/runs/r"
slice "$d" run "$d/m/manifest.json" "$d/repo" "$run" >/dev/null 2>&1; rc=$?
check "S4: 有腿失败时 run 仍 rc=0(进程层面有证据)" $([[ $rc -eq 0 ]]; echo $?)
status_json "$d" "$run"
jq_py "$d/st.json" "s['run_state'] == 'incomplete' and [a['state'] for i in s['items'] if i['id']=='s2' for a in i['attempts']] == ['failed'] and {'item':'s1','attempt':1,'verdict':'BLOCK'} in s['unacknowledged']"
check "S4: s2 失败 ⇒ incomplete;s1 的 BLOCK 进「未登记」清单" $?
n0="$(ncalls "$d")"
slice "$d" retry "$run" s2 >/dev/null 2>&1; rc=$?
check "S4: retry s2 成功且恰好多 1 次调用" $([[ $rc -eq 0 && "$(ncalls "$d")" -eq $((n0+1)) ]]; echo $?)
tail -1 "$d/calls" | awk -F'\t' '$2=="s2" && $3=="2" && $5==1 && $6==1 {ok=1} END{exit ok?0:1}'
check "S4: 重派是 s2 的第 2 次尝试,起跑前 reserved.json 已在盘上" $?
status_json "$d" "$run"
jq_py "$d/st.json" "s['budget']['extra_used'] == 1 and [i for i in s['items'] if i['id']=='s2'][0]['covered'] and s['run_state'] == 'attention'"
check "S4: retry 计入 extra(1/2);s2 已覆盖;s1 的 BLOCK 未登记 ⇒ attention" $?
slice "$d" retry "$run" s1 >/dev/null 2>&1; rc=$?
status_json "$d" "$run"
jq_py "$d/st.json" "$rc == 0 and [a['verdict'] for i in s['items'] if i['id']=='s1' for a in i['attempts']] == ['BLOCK','PASS'] and {'item':'s1','attempt':1,'verdict':'BLOCK'} in s['unacknowledged'] and s['run_state'] != 'clean'"
check "S4: s1 第 2 次 PASS 之后,第 1 次的 BLOCK 仍在「未登记」里,run_state 不是 clean" $?
n0="$(ncalls "$d")"
out="$(slice "$d" retry "$run" s2 2>&1)"; rc=$?
check "S4: extra 用完(2/2)再 retry ⇒ 拒绝、零调用、没有第 3 次尝试目录" \
  $([[ $rc -ne 0 && "$(ncalls "$d")" -eq "$n0" && ! -e "$run/items/s2/attempt-3" ]] && refused budget "$out"; echo $?)
grep -q 'extra_sessions' <<<"$out"
check "S4: 拒绝理由点名 extra_sessions(是预算拒的,不是别的原因)" $?
out="$(slice "$d" retry "$run" nosuch 2>&1)"; rc=$?
check "S4: retry 不存在的项 ⇒ 拒绝" $([[ $rc -ne 0 ]] && refused item "$out"; echo $?)

# ═══════════════════════════════════════════════════════════════════════
echo "[S5] verify:登记 finding + 换家族复核;all-or-nothing;只追加的问题账;decide"
d="$TMP_ROOT/s5"; make_fixture "$d"; write_manifest "$d" 2 2
printf 'block\n' > "$d/modes/s1.1"
run="$d/runs/r"
slice "$d" run "$d/m/manifest.json" "$d/repo" "$run" >/dev/null 2>&1
s1_leg="$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print([i for i in p["items"] if i["id"]=="s1"][0]["leg"])' "$run/plan.json" 2>/dev/null)"
s1_family="$(panel_leg_family "$s1_leg" 2>/dev/null)"
check "S5: plan.json 记下了 s1 的腿与家族($s1_leg/$s1_family)" $([[ -n "$s1_leg" && -n "$s1_family" ]]; echo $?)
vman() {  # vman <file> <json>
  printf '%s\n' "$2" > "$1"
}
F1='{"id":"F1","source":"s1#1","severity":"high","claim":"CLAIM_SENTINEL_F1 retry drops block","evidence":"bin/x:1"}'
vman "$d/v-pin.json" "{\"version\":1,\"findings\":[$F1],\"checks\":[{\"id\":\"c1\",\"findings\":[\"F1\"],\"leg\":\"$s1_leg\"}]}"
n0="$(ncalls "$d")"
out="$(slice "$d" verify "$run" "$d/v-pin.json" 2>&1)"; rc=$?
check "S5: 复核钉回出处同一家族 ⇒ 拒绝、零调用、问题账没被写" \
  $([[ $rc -ne 0 && "$(ncalls "$d")" -eq "$n0" && ! -s "$run/findings.jsonl" ]] && refused family-exclusion "$out"; echo $?)
vman "$d/v-over.json" "{\"version\":1,\"findings\":[$F1],\"checks\":[{\"id\":\"c1\",\"findings\":[\"F1\"]},{\"id\":\"c2\",\"findings\":[\"F1\"]},{\"id\":\"c3\",\"findings\":[\"F1\"]}]}"
out="$(slice "$d" verify "$run" "$d/v-over.json" 2>&1)"; rc=$?
check "S5: 3 个复核 > extra 余量 2 ⇒ 整批拒绝、零调用、问题账没被写(不半截派发)" \
  $([[ $rc -ne 0 && "$(ncalls "$d")" -eq "$n0" && ! -s "$run/findings.jsonl" ]] && refused budget "$out"; echo $?)
grep -q 'extra_sessions' <<<"$out"
check "S5: 整批拒绝理由点名 extra_sessions" $?
vman "$d/v-ok.json" "{\"version\":1,\"findings\":[$F1],\"checks\":[{\"id\":\"c1\",\"findings\":[\"F1\"]}]}"
out="$(slice "$d" verify "$run" "$d/v-ok.json" 2>&1)"; rc=$?
check "S5: 合法复核 ⇒ rc=0 且恰好多 1 次调用" $([[ $rc -eq 0 && "$(ncalls "$d")" -eq $((n0+1)) ]]; echo $?)
[[ $rc -eq 0 ]] || printf '%s\n' "$out" | tail -8 | sed 's/^/    | /'
c1_bin="$(tail -1 "$d/calls" | cut -f1)"; c1_item="$(tail -1 "$d/calls" | cut -f2)"
c1_family=""
for _spec in "${PANEL_LEG_SPECS[@]}" ${PANEL_ROLE_LEG_SPECS[@]+"${PANEL_ROLE_LEG_SPECS[@]}"}; do
  IFS='|' read -r _n _f _a _c _w <<<"$_spec"
  [[ "$c1_bin" == "$_a" || "$c1_bin" == "$_c" ]] && c1_family="$_f"
done
check "S5: 复核腿($c1_bin/$c1_family)与出处 s1 家族($s1_family)不同" \
  $([[ "$c1_item" == c1 && -n "$c1_family" && "$c1_family" != "$s1_family" ]]; echo $?)
grep -q 'CLAIM_SENTINEL_F1' "$run/items/c1/task.md" 2>/dev/null && grep -q 'GOAL_SENTINEL_7f3' "$run/items/c1/task.md"
check "S5: 复核任务书带着 finding 原文与改动目标" $?
[[ -n "$s1_leg" && -s "$run/items/c1/task.md" ]] && ! grep -q -- "$s1_leg" "$run/items/c1/task.md"
check "S5: 复核任务书不透露原评审腿是谁(不给附和的锚)" $?
check "S5: 问题账恰好 2 行(finding + check)" $([[ "$(wc -l < "$run/findings.jsonl" 2>/dev/null)" -eq 2 ]]; echo $?)
status_json "$d" "$run"
jq_py "$d/st.json" "[i['role'] for i in s['items'] if i['id']=='c1'] == ['verify'] and [f['status'] for f in s['findings'] if f['id']=='F1'] == ['open'] and s['unacknowledged'] == [] and s['run_state'] == 'attention' and s['budget']['extra_used'] == 1"
check "S5: status:c1 是 verify 项、F1 未处置 ⇒ attention;s1 的 BLOCK 已被 F1 登记;extra 1/2" $?
cp "$run/findings.jsonl" "$d/ledger.before"
vman "$d/v-dup.json" '{"version":1,"findings":[{"id":"F1","source":"s1#1","severity":"low","claim":"something else"}],"checks":[]}'
out="$(slice "$d" verify "$run" "$d/v-dup.json" 2>&1)"; rc=$?
check "S5: 同 id 不同内容的 finding ⇒ 拒绝,问题账逐字节不变(只追加不改写)" \
  $([[ $rc -ne 0 ]] && refused finding "$out" && cmp -s "$d/ledger.before" "$run/findings.jsonl"; echo $?)
vman "$d/v-src.json" '{"version":1,"findings":[{"id":"F2","source":"nosuch","severity":"low","claim":"x"}],"checks":[]}'
out="$(slice "$d" verify "$run" "$d/v-src.json" 2>&1)"; rc=$?
check "S5: finding 出处不是本轮的项 ⇒ 拒绝,问题账不变" \
  $([[ $rc -ne 0 ]] && refused finding "$out" && cmp -s "$d/ledger.before" "$run/findings.jsonl"; echo $?)
vman "$d/v-bare.json" '{"version":1,"findings":[{"id":"F4","source":"s2","severity":"low","claim":"x"}],"checks":[]}'
out="$(slice "$d" verify "$run" "$d/v-bare.json" 2>&1)"; rc=$?
check "S5: finding 出处只写项名(s2)不写第几次尝试 ⇒ 拒绝,问题账不变(登记必须对准一次尝试)" \
  $([[ $rc -ne 0 ]] && refused finding "$out" && cmp -s "$d/ledger.before" "$run/findings.jsonl"; echo $?)
vman "$d/v-noatt.json" '{"version":1,"findings":[{"id":"F5","source":"s2#9","severity":"low","claim":"x"}],"checks":[]}'
out="$(slice "$d" verify "$run" "$d/v-noatt.json" 2>&1)"; rc=$?
check "S5: finding 出处指向不存在的尝试(s2#9)⇒ 拒绝,问题账不变" \
  $([[ $rc -ne 0 ]] && refused finding "$out" && cmp -s "$d/ledger.before" "$run/findings.jsonl"; echo $?)
out="$(slice "$d" decide "$run" F9 rejected --reason nope 2>&1)"; rc=$?
check "S5: decide 一个没登记过的 finding ⇒ 拒绝,问题账不变" \
  $([[ $rc -ne 0 ]] && refused finding "$out" && cmp -s "$d/ledger.before" "$run/findings.jsonl"; echo $?)
out="$(slice "$d" decide "$run" F1 rejected 2>&1)"; rc=$?
check "S5: decide 不给理由 ⇒ 拒绝" $([[ $rc -ne 0 ]] && refused reason "$out"; echo $?)
slice "$d" decide "$run" F1 rejected --reason "stub says refuted" >/dev/null 2>&1; rc=$?
_prefix_ok=1
[[ $rc -eq 0 ]] && cmp -s "$d/ledger.before" <(head -c "$(stat -c %s "$d/ledger.before")" "$run/findings.jsonl") \
  && [[ "$(wc -l < "$run/findings.jsonl")" -eq 3 ]] && _prefix_ok=0
check "S5: decide 成功 ⇒ 问题账原有字节原样保留、只多 1 行" "$_prefix_ok"
status_json "$d" "$run"
jq_py "$d/st.json" "[f['status'] for f in s['findings'] if f['id']=='F1'] == ['closed'] and s['run_state'] == 'clean'"
check "S5: F1 rejected 后关闭;复核已完成、无其他信号 ⇒ clean" $?
vman "$d/v-main.json" '{"version":1,"findings":[{"id":"M1","source":"main","severity":"medium","claim":"main agent own finding"}],"checks":[]}'
slice "$d" verify "$run" "$d/v-main.json" >/dev/null 2>&1; rc=$?
status_json "$d" "$run"
jq_py "$d/st.json" "$rc == 0 and [f['status'] for f in s['findings'] if f['id']=='M1'] == ['open'] and s['run_state'] == 'attention'"
check "S5: 主 agent 自己的 finding(source=main)可登记,未处置 ⇒ attention" $?
slice "$d" decide "$run" F1 confirmed --reason "reproduced after all" >/dev/null 2>&1
status_json "$d" "$run"
jq_py "$d/st.json" "[f['status'] for f in s['findings'] if f['id']=='F1'] == ['open'] and [f['decision'] for f in s['findings'] if f['id']=='F1'] == ['confirmed']"
check "S5: 后来的 decide 生效(confirmed ⇒ 重新 open),历史仍在账里" $?

echo "[S6] 源码变了 ⇒ verify / retry 拒绝(开新一轮,不拿旧代码上的评审继续)"
printf 'changed\n' >> "$d/repo/app.txt"
n0="$(ncalls "$d")"; cp "$run/findings.jsonl" "$d/ledger.before"
vman "$d/v-src2.json" '{"version":1,"findings":[{"id":"F3","source":"s2#1","severity":"low","claim":"x"}],"checks":[{"id":"c9","findings":["F3"]}]}'
out="$(slice "$d" verify "$run" "$d/v-src2.json" 2>&1)"; rc=$?
check "S6: 仓里改过已跟踪文件 ⇒ verify 拒绝、零调用、问题账不变" \
  $([[ $rc -ne 0 && "$(ncalls "$d")" -eq "$n0" ]] && refused source-changed "$out" && cmp -s "$d/ledger.before" "$run/findings.jsonl"; echo $?)
out="$(slice "$d" retry "$run" s2 2>&1)"; rc=$?
check "S6: 同样情况下 retry 拒绝、零调用" $([[ $rc -ne 0 && "$(ncalls "$d")" -eq "$n0" ]] && refused source-changed "$out"; echo $?)
( cd "$d/repo" && git checkout -q -- app.txt )
printf 'new untracked\n' > "$d/repo/untracked.txt"
out="$(slice "$d" retry "$run" s2 2>&1)"; rc=$?
check "S6: 新增未跟踪文件也算源码变了 ⇒ retry 拒绝" $([[ $rc -ne 0 && "$(ncalls "$d")" -eq "$n0" ]] && refused source-changed "$out"; echo $?)
rm -f "$d/repo/untracked.txt"

# ═══════════════════════════════════════════════════════════════════════
echo "[S7] 控制器被整组砍掉 ⇒ 说 unknown 不说 failed;腿自己跑完后能从盘上重建"
d="$TMP_ROOT/s7"; make_fixture "$d"; write_manifest "$d" 2 2
for _i in s1 s2 overall; do printf 'sleep:4\n' > "$d/modes/$_i"; done
run="$d/runs/r"
SLICE_TEST_CALLS="$d/calls" SLICE_TEST_MODES="$d/modes" PANEL_STATE_DIR="$d/state" \
  PANEL_STAGGER_MAX=0 PANEL_SLICE_ASSIGN_START=0 \
  setsid bash "$d/bin/panel-slice" run "$d/m/manifest.json" "$d/repo" "$run" >"$d/run.out" 2>&1 &
ctl=$!
for _ in $(seq 1 100); do [[ "$(ncalls "$d")" -ge 3 ]] && break; sleep 0.1; done
check "S7: 三条腿都已起跑" $([[ "$(ncalls "$d")" -ge 3 ]]; echo $?)
kill -TERM -- "-$ctl" 2>/dev/null; wait "$ctl" 2>/dev/null
status_json "$d" "$run"
jq_py "$d/st.json" "s['run_state'] == 'incomplete' and not any(a['state'] == 'failed' for i in s['items'] for a in i['attempts']) and any(a['state'] == 'unknown' for i in s['items'] for a in i['attempts'])"
check "S7: 砍掉之后立刻看:有 unknown、没有一条被说成 failed" $?
n0="$(ncalls "$d")"
out="$(slice "$d" retry "$run" s1 2>&1)"; rc=$?
check "S7: 还是 unknown 的项不许 retry(它可能还在跑,补派会多花一次)" \
  $([[ $rc -ne 0 && "$(ncalls "$d")" -eq "$n0" ]] && refused unknown-attempt "$out"; echo $?)
for _ in $(seq 1 150); do
  status_json "$d" "$run"
  jq_py "$d/st.json" "s['run_state'] == 'clean'" 2>/dev/null && break
  sleep 0.1
done
jq_py "$d/st.json" "s['run_state'] == 'clean' and all(a['state'] == 'done' for i in s['items'] for a in i['attempts'])"
check "S7: 腿在自己的会话里跑完 ⇒ status 从盘上重建为全部 done / clean" $?

# ═══════════════════════════════════════════════════════════════════════
echo "[S8] max_concurrency=1 ⇒ 同一时刻只有一条腿在跑"
d="$TMP_ROOT/s8"; make_fixture "$d"; write_manifest "$d" 2 2 - 1
for _i in s1 s2 overall; do printf 'sleep:0.4\n' > "$d/modes/$_i"; done
slice "$d" run "$d/m/manifest.json" "$d/repo" "$d/runs/r" >/dev/null 2>&1; rc=$?
python3 - "$d/calls" "$d/calls.end" <<'PY'
import sys
starts = {(r.split("\t")[1], r.split("\t")[2]): int(r.rstrip("\n").split("\t")[6]) for r in open(sys.argv[1]) if r.strip()}
ends = {(r.split("\t")[0], r.split("\t")[1]): int(r.rstrip("\n").split("\t")[2]) for r in open(sys.argv[2]) if r.strip()}
spans = sorted((starts[k], ends[k]) for k in starts)
assert len(spans) == 3, spans
assert all(a[1] <= b[0] for a, b in zip(spans, spans[1:])), spans
PY
_iv=$?
check "S8: run 正常结束" $([[ $rc -eq 0 ]]; echo $?)
check "S8: 三次调用的运行区间互不重叠" "$_iv"
d="$TMP_ROOT/s8b"; make_fixture "$d"; write_manifest "$d" 2 2
for _i in s1 s2 overall; do printf 'sleep:1.5\n' > "$d/modes/$_i"; done
slice "$d" run "$d/m/manifest.json" "$d/repo" "$d/runs/r" >/dev/null 2>&1; rc=$?
python3 - "$d/calls" "$d/calls.end" <<'PY2'
import sys
starts = {(r.split("\t")[1], r.split("\t")[2]): int(r.rstrip("\n").split("\t")[6]) for r in open(sys.argv[1]) if r.strip()}
ends = {(r.split("\t")[0], r.split("\t")[1]): int(r.rstrip("\n").split("\t")[2]) for r in open(sys.argv[2]) if r.strip()}
spans = sorted((starts[k], ends[k]) for k in starts)
sys.exit(0 if len(spans) == 3 and any(a[1] > b[0] for a, b in zip(spans, spans[1:])) else 1)
PY2
_ov=$?
check "S8: 不给 max_concurrency(默认=初始项数)⇒ 至少两条腿的运行区间重叠(真的并行派发)" \
  $([[ $rc -eq 0 && $_ov -eq 0 ]]; echo $?)

# ═══════════════════════════════════════════════════════════════════════
echo "[S9] panel-review 的 scoped 开关:拒绝规则、不回落聊天腿、角色腿不进普通池、不推游标"
d="$TMP_ROOT/s9"; make_fixture "$d"
printf 'scoped task\n' > "$d/task.md"
pr() {  # pr <prefix-leaf> <panel-review args...>
  local leaf="$1"; shift
  SLICE_TEST_CALLS="$d/calls" SLICE_TEST_MODES="$d/modes" PANEL_STATE_DIR="$d/state" PANEL_STAGGER_MAX=0 \
    bash "$d/bin/panel-review" "$@" "$d/task.md" "$d/repo" "$d/p/$leaf/items/x/attempt-1/panel"
}
mkdir -p "$d/p"
for _leaf in a b c g; do mkdir -p "$d/p/$_leaf/items/x/attempt-1"; done
out="$(pr a --scoped-review --track current --no-my-review --risk standard --budget 1 --pin-leg "${POOL[0]}" 2>&1)"; rc=$?
check "S9: --scoped-review 与 --track 同时给 ⇒ 拒绝且零调用" $([[ $rc -ne 0 && "$(ncalls "$d")" -eq 0 ]] && grep -q -- '--scoped-review' <<<"$out" && grep -q -- '--track' <<<"$out"; echo $?)
out="$(pr b --scoped-review --no-track --no-my-review --risk standard --budget 1 2>&1)"; rc=$?
check "S9: scoped 且预算>0 却没钉腿 ⇒ 拒绝且零调用" $([[ $rc -ne 0 && "$(ncalls "$d")" -eq 0 ]] && grep -q -- '--pin-leg' <<<"$out"; echo $?)
out="$(pr c --scoped-review --no-track --no-my-review --risk standard --budget 1 --pin-leg nosuch 2>&1)"; rc=$?
check "S9: 钉一条表里没有的腿 ⇒ 拒绝且零调用" $([[ $rc -ne 0 && "$(ncalls "$d")" -eq 0 ]] && grep -q 'nosuch' <<<"$out"; echo $?)
out="$(pr g --no-track --no-my-review --risk standard --budget 1 --pin-leg "${POOL[0]}" 2>&1)"; rc=$?
check "S9: 非 scoped 模式不许 --pin-leg(内部开关不外露成普通评审的后门)" \
  $([[ $rc -ne 0 && "$(ncalls "$d")" -eq 0 ]] && grep -q -- '--pin-leg' <<<"$out" && grep -q -- '--scoped-review' <<<"$out"; echo $?)
mkdir -p "$d/p/all/items/x/attempt-1"
pr all --no-track --no-my-review --all >/dev/null 2>&1; rc=$?
_role_called=1
for _r in ${ROLE_LEGS[@]+"${ROLE_LEGS[@]}"}; do
  cut -f1 "$d/calls" | grep -qx "$(panel_leg_agent "$_r")" && _role_called=0
done
check "S9: 普通 --all 派满整个池,但角色腿一次都没被派" \
  $([[ $rc -eq 0 && "$(ncalls "$d")" -eq $P && $_role_called -eq 1 && ${#ROLE_LEGS[@]} -gt 0 ]]; echo $?)
[[ ${#ROLE_LEGS[@]} -gt 0 && -s "$d/p/all/items/x/attempt-1/panel.roster" ]] \
  && ! grep -q 'subcodex=' "$d/p/all/items/x/attempt-1/panel.roster"
check "S9: 普通花名册里不出现角色腿" $?
: > "$d/calls"; printf '3\n' > "$d/state/cursor"
mkdir -p "$d/p/ctl/items/x/attempt-1"
pr ctl --no-track --no-my-review --risk standard --budget 1 >/dev/null 2>&1
check "S9: 对照组:普通预算 1 评审会推动游标(证明下一条能测出'没推')" \
  $([[ "$(cat "$d/state/cursor")" != 3 ]]; echo $?)
printf '3\n' > "$d/state/cursor"; : > "$d/calls"
mkdir -p "$d/p/codex/items/x/attempt-1"
pr codex --scoped-review --no-track --no-my-review --risk standard --budget 1 --pin-leg subcodex >/dev/null 2>&1; rc=$?
check "S9: scoped 钉 subcodex ⇒ 恰好 1 次调用且是 subcodex" \
  $([[ $rc -eq 0 && "$(ncalls "$d")" -eq 1 && "$(cut -f1 "$d/calls")" == subcodex ]]; echo $?)
check "S9: scoped 评审不推动普通轮换游标" $([[ $rc -eq 0 && "$(cat "$d/state/cursor")" == 3 ]]; echo $?)
grep -q 'subcodex=PASS(verdict=PASS,coverage=INELIGIBLE)' "$d/p/codex/items/x/attempt-1/panel.roster"
check "S9: 钉住的角色腿出现在它那一轮的花名册里,且如实标 coverage=INELIGIBLE" $?
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["review_contract_version"] == 2' \
  "$d/p/codex/items/x/attempt-1/panel.subcodex.result.json" 2>/dev/null
check "S9: scoped 结果契约版本=2" $?
# 不回落:先证明普通模式下这个桩组合**会**回落(否则下一条是瞎断言)
printf 'fail\n' > "$d/modes/leg-subdeepseek-agent"
: > "$d/calls"; mkdir -p "$d/p/fb/items/x/attempt-1"
_off=()
for _spec in "${PANEL_LEG_SPECS[@]}"; do
  IFS='|' read -r _n _f _a _c _w <<<"$_spec"; [[ "$_n" == subdeepseek ]] || _off+=("$_w=off")
done
env "${_off[@]}" SLICE_TEST_CALLS="$d/calls" SLICE_TEST_MODES="$d/modes" PANEL_STATE_DIR="$d/state" PANEL_STAGGER_MAX=0 \
  bash "$d/bin/panel-review" --no-track --no-my-review --risk standard --budget 1 \
  "$d/task.md" "$d/repo" "$d/p/fb/items/x/attempt-1/panel" >/dev/null 2>&1
check "S9: 对照组:普通模式 agent 腿失败会回落聊天腿(2 次调用)" \
  $([[ "$(ncalls "$d")" -eq 2 ]] && cut -f1 "$d/calls" | grep -qx subdeepseek; echo $?)
: > "$d/calls"; mkdir -p "$d/p/nofb/items/x/attempt-1"
PANEL_HEALTH_OVERRIDE=subdeepseek=healthy SLICE_TEST_CALLS="$d/calls" SLICE_TEST_MODES="$d/modes" \
  PANEL_STATE_DIR="$d/state" PANEL_STAGGER_MAX=0 \
  bash "$d/bin/panel-review" --scoped-review --no-track --no-my-review --risk standard --budget 1 \
  --pin-leg subdeepseek "$d/task.md" "$d/repo" "$d/p/nofb/items/x/attempt-1/panel" >/dev/null 2>&1
check "S9: scoped 模式 agent 腿失败 ⇒ 不调聊天腿(恰好 1 次调用,不暗中多花一次)" \
  $([[ "$(ncalls "$d")" -eq 1 && "$(cut -f1 "$d/calls")" == subdeepseek-agent ]]; echo $?)

# ═══════════════════════════════════════════════════════════════════════
# S10/S11:2026-09-14 panel-review 高风险评审(subdeepseek)发现 D / A 后补的判据。
echo "[S10] 登记对准一次尝试:同一项两次 BLOCK,只登记第 2 次不会顺带确认第 1 次"
d="$TMP_ROOT/s10"; make_fixture "$d"; write_manifest "$d" 2 3
printf 'block\n' > "$d/modes/s1.1"; printf 'block\n' > "$d/modes/s1.2"
run="$d/runs/r"
slice "$d" run "$d/m/manifest.json" "$d/repo" "$run" >/dev/null 2>&1
slice "$d" retry "$run" s1 >/dev/null 2>&1; rc=$?
status_json "$d" "$run"
jq_py "$d/st.json" "$rc == 0 and [a['verdict'] for i in s['items'] if i['id']=='s1' for a in i['attempts']] == ['BLOCK','BLOCK']"
check "S10: 夹具就绪:s1 两次尝试都是 BLOCK" $?
printf '%s\n' '{"version":1,"findings":[{"id":"G2","source":"s1#2","severity":"high","claim":"second block reason"}],"checks":[]}' > "$d/v2.json"
out="$(slice "$d" verify "$run" "$d/v2.json" 2>&1)"; rc=$?
status_json "$d" "$run"
jq_py "$d/st.json" "$rc == 0 and {'item':'s1','attempt':1,'verdict':'BLOCK'} in s['unacknowledged'] and {'item':'s1','attempt':2,'verdict':'BLOCK'} not in s['unacknowledged']"
check "S10: 只登记 s1#2 ⇒ s1#1 的 BLOCK 仍在「未登记」里(不按项一笔勾销)" $?
slice "$d" decide "$run" G2 rejected --reason "stub" >/dev/null 2>&1; rc=$?
status_json "$d" "$run"
jq_py "$d/st.json" "$rc == 0 and [f['status'] for f in s['findings'] if f['id']=='G2'] == ['closed'] and s['run_state'] == 'attention'"
check "S10: G2 处置关闭之后 run_state 仍是 attention(s1#1 的 BLOCK 没人登记)" $?
printf '%s\n' '{"version":1,"findings":[{"id":"G1","source":"s1#1","severity":"high","claim":"first block reason"}],"checks":[]}' > "$d/v1.json"
slice "$d" verify "$run" "$d/v1.json" >/dev/null 2>&1; rc=$?
slice "$d" decide "$run" G1 rejected --reason "stub" >/dev/null 2>&1; rc2=$?
status_json "$d" "$run"
jq_py "$d/st.json" "$rc == 0 and $rc2 == 0 and s['unacknowledged'] == [] and s['run_state'] == 'clean'"
check "S10: s1#1 也登记并处置后 ⇒ 未登记清单为空、clean" $?

echo "[S11] 占了额度却永远等不到终态的尝试:abandon 出口(有活进程引用就拒)"
d="$TMP_ROOT/s11"; make_fixture "$d"; write_manifest "$d" 2 2
run="$d/runs/r"
slice "$d" run "$d/m/manifest.json" "$d/repo" "$run" >/dev/null 2>&1
s1_leg="$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print([i for i in p["items"] if i["id"]=="s1"][0]["leg"])' "$run/plan.json" 2>/dev/null)"
s1_family="$(panel_leg_family "$s1_leg" 2>/dev/null)"
# 模拟控制器在 reserve 之后、起子进程之前被砍:盘上只有 reserved.json,没有 plan / state / controller.exit。
python3 "$d/bin/_panel_slice.py" reserve --run-dir "$run" --item s1 --attempt 2 \
  --leg "$s1_leg" --family "$s1_family" --category extra 2>/dev/null
att="$run/items/s1/attempt-2"
status_json "$d" "$run"
jq_py "$d/st.json" "[a['state'] for i in s['items'] if i['id']=='s1' for a in i['attempts']] == ['done','unknown'] and s['run_state'] == 'incomplete'"
check "S11: 夹具就绪:s1#2 只有 reserved.json ⇒ unknown / incomplete" $?
out="$(slice "$d" retry "$run" s1 2>&1)"; rc=$?
check "S11: 对照组:unknown 的项照旧不许 retry" $([[ $rc -ne 0 ]] && refused unknown-attempt "$out"; echo $?)
# 占位进程必须**自己**带着这个路径活着:`bash -c 'sleep 30'` 会被 bash 直接 exec 成 `sleep 30`,
# 命令行里就没有路径了(2026-09-14 实测:第一版夹具就是这样没造出前提,S11 红在夹具上不在实现上)。
bash -c 'sleep 30; :' _ "$att/panel" & _holder=$!
sleep 0.3
tr '\0' '\n' < "/proc/$_holder/cmdline" 2>/dev/null | grep -qxF -- "$att/panel"
check "S11: 夹具前提:占位进程的命令行里确实带着这次尝试的路径" $?
out="$(slice "$d" abandon "$run" 's1#2' --reason "controller killed before launch" 2>&1)"; rc=$?
check "S11: 还有进程的命令行引用这次尝试的目录 ⇒ abandon 拒绝(REFUSED alive),不写 abandoned.json" \
  $([[ $rc -ne 0 && ! -e "$att/abandoned.json" ]] && refused alive "$out"; echo $?)
kill "$_holder" 2>/dev/null; wait "$_holder" 2>/dev/null
out="$(slice "$d" abandon "$run" 's1#2' 2>&1)"; rc=$?
check "S11: abandon 不给理由 ⇒ 拒绝" $([[ $rc -ne 0 && ! -e "$att/abandoned.json" ]] && refused reason "$out"; echo $?)
out="$(slice "$d" abandon "$run" 's2#1' --reason "x" 2>&1)"; rc=$?
check "S11: abandon 一个已有终态(done)的尝试 ⇒ 拒绝(只收 unknown)" \
  $([[ $rc -ne 0 && ! -e "$run/items/s2/attempt-1/abandoned.json" ]] && refused abandon "$out"; echo $?)
out="$(slice "$d" abandon "$run" 's1#2' --reason "controller killed before launch" 2>&1)"; rc=$?
status_json "$d" "$run"
jq_py "$d/st.json" "$rc == 0 and [a['state'] for i in s['items'] if i['id']=='s1' for a in i['attempts']] == ['done','abandoned'] and s['budget']['extra_used'] == 1 and s['run_state'] == 'clean'"
_st=$?
check "S11: 无活进程时 abandon 成功:状态 abandoned(不再是 unknown)、额度照记 1、run 不再卡在 incomplete" \
  $([[ $_st -eq 0 && -s "$att/abandoned.json" && -s "$att/reserved.json" ]]; echo $?)
n0="$(ncalls "$d")"
slice "$d" retry "$run" s1 >/dev/null 2>&1; rc=$?
check "S11: abandon 之后允许 retry:恰好多 1 次调用,是第 3 次尝试" \
  $([[ $rc -eq 0 && "$(ncalls "$d")" -eq $((n0+1)) && -s "$run/items/s1/attempt-3/reserved.json" ]]; echo $?)
cp "$run/items/s1/attempt-1/panel.$s1_leg.result.json" "$att/" 2>/dev/null
status_json "$d" "$run"
jq_py "$d/st.json" "[a['state'] for i in s['items'] if i['id']=='s1' for a in i['attempts']][1] == 'done'"
check "S11: 被 abandon 的尝试事后落了结果(腿其实还活着)⇒ 按结果算 done,abandon 不掩盖真实结果" $?

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
