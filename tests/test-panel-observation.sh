#!/usr/bin/env bash
# panel-review typed ownership/risk/observation oracle. External legs are stubs.
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 腿名单的**唯一源**。判据自己也不许抄第二份 —— 抄了就会像 08-26 那样:
# 名单上五条腿,判据只问得出四条。
. "$ROOT/bin/_panel-roster-lib.sh"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

make_leg_stubs() { # bindir —— 每条腿铺一个健康桩(两种命名都铺)
  local b="$1" leg bin_name
  for leg in "${PANEL_LEGS_ORDER[@]}"; do
    for bin_name in "$leg" "$leg-agent"; do
      cat > "$b/$bin_name" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$0")" >> "$PANEL_TEST_CALLS"
printf 'Conclusion: PASS\n' > "$3"
exit 0
EOF
      chmod +x "$b/$bin_name"
    done
  done
}

make_fixture() { # root
  local d="$1" b="$1/bin" repo="$1/repo"
  mkdir -p "$b" "$repo/tracks/current" "$d/raw" "$d/state"
  cp "$ROOT/bin/panel-review" "$b/panel-review"
  cp "$ROOT/bin/_panel-roster-lib.sh" "$b/"  # 花名册渲染的共享库,panel-review 缺它会 fail closed
  cp "$ROOT/bin/track-record" "$b/track-record"
  # 🔴 桩腿名单**从唯一源长出来**,不在这里再抄一份(2026-08-26 subgemini 四审 F8)。
  # 这里原本硬编码 `for leg in submimo subdeepseek subglm subkimi`,是全仓第五份腿名单:
  # 加第五条腿时它没跟上 ⇒ 新腿在这套判据里静默 off ⇒ **P 系列永远问不到它**,
  # 而 P 系列正是"派发真的发生了吗"的唯一行为级判据。名单漏一处,闸就瞎一只眼。
  # 两种命名都铺桩(<腿名> 和 <腿名>-agent):底座腿/聊天腿哪个存在由实现决定,
  # 判据不猜、也不因此长出对实现的第二份知识。
  make_leg_stubs "$b"
  printf '# PANEL_PROMPT_SENTINEL\n' > "$d/task.md"
  cat > "$repo/tracks/current/decision.json" <<'EOF'
{
  "schema_version": 1,
  "track": "current",
  "impact": {"level": "high", "factors": []},
  "design": {"uncertainty": "low", "premise_attack": {"status": "not_required", "evidence": []}},
  "execution_plan": {"adapter": "main", "model": null},
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

out="$(PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state" PANEL_STAGGER_MAX=0 \
  bash "$d/bin/panel-review" --track current --risk high --budget 0 \
  "${common[@]}" "$d/raw/under-budget" 2>&1)"; rc=$?
check "P1: typed high 显式 --budget 0 也不许绕空两条评审腿" $([[ $rc -ne 0 ]]; echo $?)
check "P1: typed budget 降档仍在任何腿调用前拒绝" $([[ ! -s "$calls" ]]; echo $?)
grep -q 'below impact-risk=high minimum=2' <<<"$out"
check "P1: budget 降档报警给 actual risk/minimum" $?

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
python3 - "$d/repo/tracks/current/decision.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["impact"]["level"]="standard"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
cat > "$d/bin/subdeepseek-agent" <<'EOF'
#!/usr/bin/env bash
printf 'agent failed\n' >&2
exit 7
EOF
chmod +x "$d/bin/subdeepseek-agent"
: > "$calls"
PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state-2" PANEL_STAGGER_MAX=0 PANEL_SELECTION_START=1 \
  bash "$d/bin/panel-review" --track current --risk standard --budget 1 \
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
  TRACK_RECORD_BIN="$wrapper" bash "$d/bin/panel-review" --track current --risk standard --budget 1 \
  "${common[@]}" "$d/raw/writer-fail" 2>&1)"; rc=$?
check "P4: writer 失败不把原本 rc=0 的 panel 改红" $([[ $rc -eq 0 ]]; echo $?)
grep -q 'OBSERVATION_WRITE_FAILED' <<<"$out"
check "P4: writer 失败明确报警" $?
check "P4: writer 失败不伪造事件" $([[ "$(obs_count "$d")" -eq "$before" ]]; echo $?)

echo "[P5] self budget=0 有 controller event，但 external dispatch_count 必须为 0"
python3 - "$d/repo/tracks/current/decision.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["impact"]["level"]="self"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state-4" PANEL_STAGGER_MAX=0 \
  bash "$d/bin/panel-review" --track current --risk self --budget 0 \
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

echo "[P6] task basename 过长也不许让成功 controller 丢 observation"
long="$(printf 'x%.0s' {1..160})"
printf '# long label\n' > "$d/$long.md"
PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state-5" PANEL_STAGGER_MAX=0 \
  bash "$d/bin/panel-review" --track current --risk self --budget 0 --no-my-review \
  "$d/$long.md" "$d/repo" "$d/raw/long-label" >/dev/null 2>&1; rc=$?
f="$(latest_obs "$d")"
python3 - "$f" <<'PY'
import json,sys
p=json.load(open(sys.argv[1], encoding="utf-8"))
assert len(p["label"]) == 128 and set(p["label"]) == {"x"}
PY
check "P6: panel label 在 producer 端截到 schema 的 128 字节上限" $?


# ── P7 ────────────────────────────────────────────────────────────────────
# 🔴 2026-08-26,subgemini 那一单的四审(两条腿各自独立命中,我自己去核也成立):
#   `launch_leg` 的 case 里没有第五条腿的分支 ⇒ 选中它时**什么都不启动**,
#   紧接着的 `LEG_PID[$name]=$!` 拿到的是**上一条腿**的 pid ⇒ `wait` 返回那条腿的
#   退出码 ⇒ 花名册给它记 PASS、observation 记一条成功的腿 —— 而它一次都没跑。
#   这是"看起来跑完了、其实没审"的终极形态,比腿失败危险得多。
#
#   当时专门为这件事写的断言是 `grep -q subgemini bin/panel-review`:
#   **拿文本出现过冒充派发接上了**。补一行 LEG_CMD 映射它就变绿,而派发一直是断的。
#
# 所以这一段:① 问行为(桩腿到底有没有被执行),不 grep 源码;
#             ② 对**名单上的每一条腿**各问一遍 —— 加第六条腿时判据自动跟着覆盖,
#                不用"记得回来改判据"(那从来靠不住)。
# 🔴 桩腿是按"腿名 / 腿名-agent"两种命名无条件铺的,所以**表里把二进制名写错时
# P7 照样全绿**,而生产环境里 `-x "$BIN/<那个名字>"` 为假 ⇒ 那条腿被静默标成 off、
# 永远不派。判据绿、腿不在 —— 正是这一单从头到尾在治的那种病。
# (2026-08-26 subgemini 腿自己真链跑出来的发现;我自审只把它当"错误信息会指错地方",
#  它指出更狠的一面:**这是假绿**。)
# ⇒ 先问一句真实世界的:表里声明的二进制,在**真的 bin/ 里**存不存在、可不可执行。
echo "[P7pre] 腿表里声明的二进制必须在真实 bin/ 里存在(桩腿铺得再全也不算数)"
for leg in "${PANEL_LEGS_ORDER[@]}"; do
  agent="$(panel_leg_agent "$leg")"; chat="$(panel_leg_chat "$leg")"
  check "P7pre[$leg]: 底座腿 bin/$agent 存在且可执行" \
    $([[ -n "$agent" && -x "$ROOT/bin/$agent" ]]; echo $?)
  if [[ -n "$chat" ]]; then
    check "P7pre[$leg]: 聊天腿 bin/$chat 存在且可执行" $([[ -x "$ROOT/bin/$chat" ]]; echo $?)
  fi
done

echo "[P7] 花名册上的每条腿都必须真的派得出去,且家族记账不空"
# 夹具复位:P3 把 subdeepseek-agent 换成了失败桩、P5 把 decision.json 改成了 self。
# 不复位 ⇒ P7 量到的是那些残留而不是派发本身(第一版全 26 红,**误报是我自己造的**)。
make_leg_stubs "$d/bin"
python3 - "$d/repo/tracks/current/decision.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1])); p["impact"]["level"] = "standard"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
declare -A P7_FAMILY=()
for leg in "${PANEL_LEGS_ORDER[@]}"; do
  : > "$calls"
  ov=""
  for other in "${PANEL_LEGS_ORDER[@]}"; do
    [[ "$other" == "$leg" ]] && continue
    ov+="${ov:+,}$other=cooldown:P7"
  done
  prefix="$d/raw/p7-$leg"
  PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state-p7-$leg" PANEL_STAGGER_MAX=0 \
    PANEL_HEALTH_OVERRIDE="$ov" \
    bash "$d/bin/panel-review" --track current --risk standard --budget 1 \
    "${common[@]}" "$prefix" >/dev/null 2>&1
  sel="$(sed -n 's/^selected=//p' "$prefix.plan" 2>/dev/null)"
  entry="$(tr ',' '\n' <<<"$sel" | grep -F "$leg(" || true)"
  check "P7[$leg]: 轮换真的选中了它(plan 的 selected 里有它)" $([[ -n "$entry" ]]; echo $?)
  family="${entry#*(}"; family="${family%%/*}"
  adapter="${entry##*/}"; adapter="${adapter%)}"
  P7_FAMILY[$leg]="$family"
  # 家族不能空:归档闸数的"覆盖了 N 个不同模型家族"就是从这里来的。
  # 空 family 会让那条腿在覆盖核对里静默不算数 —— 一句读起来完全正常的假话。
  check "P7[$leg]: 有模型家族(归档闸的家族覆盖核对靠它)—— 实际='$family'" \
    $([[ "$family" =~ ^[a-z][a-z0-9_-]*$ ]]; echo $?)
  # **真的被执行了**:桩腿被调用时会把自己的名字写进 calls。
  check "P7[$leg]: 适配器 $adapter 真的被执行了(不是只出现在名单里)" \
    $(grep -qxF "$adapter" "$calls" 2>/dev/null; echo $?)
  # 退出码落盘:花名册/健康池全靠它,没有它这条腿在事后是查不到死活的。
  check "P7[$leg]: 它自己的 state 落盘且 rc=0" \
    $([[ -s "$prefix.$leg.state" ]] && grep -qx 'rc=0' "$prefix.$leg.state"; echo $?)
  f="$(latest_obs "$d")"
  python3 - "$f" "$leg" "$family" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
legs = {x["name"]: x for x in p["actual"]["legs"]}
leg = legs[sys.argv[2]]
assert leg["family"], "observation 里这条腿的 family 是空的:%r" % (leg,)
assert leg["family"] == sys.argv[3], (leg["family"], sys.argv[3])
PY
  check "P7[$leg]: observation 里的 family 非空且与 plan 一致" $?
done
# 家族两两不同,否则"两个不同家族的腿"这句话可以被两条同家族的腿满足 ——
# 而那正是 impact-risk=high 的全部意义所在。
check "P7: 各腿的模型家族两两不同(重了 ⇒ 归档闸数出来的覆盖是假的)" \
  $([[ "$(printf '%s\n' "${P7_FAMILY[@]}" | sort -u | wc -l)" -eq "${#P7_FAMILY[@]}" ]]; echo $?)

rm -rf "$d"
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
