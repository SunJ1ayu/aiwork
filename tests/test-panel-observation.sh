#!/usr/bin/env bash
# panel-review typed ownership/risk/observation oracle. External legs are stubs.
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 🔴 **这套判据必须是隔离的**:panel-review 的选腿/开关全走环境变量,而这套判据
# 恰恰在测选腿与派发。调用者环境里飘着一个 `PANEL_GEMINI_LEG=off`,整段就变成
# 50/5 —— 也就是说**判卷防线能被一个环境变量悄悄关掉**,而红绿看起来像代码的问题。
# 2026-08-26 第二轮四审的 subkimi 腿实测出来的(它自己没来得及给裁决行,
# 但这条是那一轮最值钱的发现之一)。tests/test-review-tooling.sh 早就有这道 scrub,
# 这份没有 —— 又一次「守卫要守对门」:同一道闸,只装在了一扇门上。
# 本机为"判据里飘着的全局 export"记过账(08-18,一天五条假绿)。
if [[ "${PANEL_OBS_ENV_SCRUBBED:-}" != "1" ]]; then
  exec env -u PANEL_MIMO_LEG -u PANEL_DEEPSEEK_LEG -u PANEL_GLM_LEG \
    -u PANEL_KIMI_LEG -u PANEL_GEMINI_LEG \
    -u PANEL_HEALTH_OVERRIDE -u PANEL_SELECTION_START -u PANEL_STATE_DIR \
    -u PANEL_STAGGER_MAX -u PANEL_IMPACT_RISK -u PANEL_REVIEW_BUDGET \
    -u PANEL_DIFF_BASE -u PANEL_INCLUDE -u PANEL_ORACLE_CMD \
    PANEL_OBS_ENV_SCRUBBED=1 bash "$0" "$@"
fi
# 腿名单的**唯一源**。判据自己也不许抄第二份 —— 抄了就会像 08-26 那样:
# 名单上五条腿,判据只问得出四条。
. "$ROOT/bin/_panel-roster-lib.sh"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

# P0:这套判据会在外层 panel 的 PANEL_ORACLE_CMD 里被调用。若入口不清掉它,
# 下面每个桩 panel 又会递归启动整套总闸,最终把 P2/P5 的腿数与 observation 污染掉。
# 2026-08-28 第二轮真派发前的 oracle 实证为 V43 两红 + P2/P5 三红；脱离外层
# PANEL_ORACLE_CMD 单跑则 68/0。这里直接问入口环境,不靠那五条远端症状猜根因。
check "P0: 套件入口清理外层 PANEL_ORACLE_CMD，桩 panel 不递归跑总闸" \
  $([[ -z "${PANEL_ORACLE_CMD:-}" ]]; echo $?)

make_leg_stubs() { # bindir —— 每条腿铺一个健康桩(两种命名都铺)
  local b="$1" leg bin_name
  for leg in "${PANEL_LEGS_ORDER[@]}"; do
    for bin_name in "$leg" "$leg-agent"; do
      cat > "$b/$bin_name" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$0")" >> "$PANEL_TEST_CALLS"
if [[ -n "${PANEL_TEST_TASKS:-}" ]]; then
  printf '%s\t%s\n' "$2" "$(sha256sum "$2" | cut -d' ' -f1)" >> "$PANEL_TEST_TASKS"
fi
printf 'Conclusion: PASS\n' > "$3"
# 健康桩要**像真腿**:五条 adapter 都已经产 typed facts,只给裁决不给 facts 的腿
# 在新契约下是"决定性但不可计数",调度器会为它补一条腿 —— 那时这套判据数出来的
# 腿数就不是它想问的东西了(2026-08-28:P2/P5 就是这样红的)。
case "${AIWORK_REVIEW_ADAPTER:?}" in
  submimo) model=xiaomi/mimo-v2-flash ;;
  subdeepseek-agent|subdeepseek) model=deepseek-chat ;;
  subglm-agent) model=go/glm-4.5 ;;
  subglm) model=glm-4.5 ;;
  subkimi) model=kimi-code/k2.5 ;;
  subgemini) model=gemini-2.5-pro ;;
esac
object_format="$(git -C "$4" rev-parse --show-object-format)"
head_oid="$(git -C "$4" rev-parse HEAD)"
# fixture 仓是 clean/static；并发桩只读 HEAD tree，不能用 write-tree 争 index.lock。
tree_oid="$(git -C "$4" rev-parse 'HEAD^{tree}')"
python3 "${AIWORK_REVIEW_RESULT_BIN:?}" facts --output "${AIWORK_REVIEW_FACTS_PATH:?}" \
  --requested-model "$model" --invoked-model "$model" --reported-model "$model" \
  --git-object-format "$object_format" --head-oid "$head_oid" \
  --index-tree-oid "$tree_oid" --worktree-tree-oid "$tree_oid" \
  --view-delivery-state complete --view-mode full_snapshot --evidence-completeness complete
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
  cp "$ROOT/bin/_panel-roster-lib.sh" "$ROOT/bin/_review_result.py" "$b/"
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
task_uses="$d/task-uses"; task_hash="$(sha256sum "$d/task.md" | cut -d' ' -f1)"
PANEL_TEST_TASKS="$task_uses" PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state" PANEL_STAGGER_MAX=0 PANEL_SELECTION_START=0 \
  bash "$d/bin/panel-review" --track current --risk high --budget 2 \
  "${common[@]}" "$d/raw/matched" >/dev/null 2>&1; rc=$?
check "P2: 匹配的 typed panel 正常成功" $([[ $rc -eq 0 ]]; echo $?)
f="$(latest_obs "$d")"
check "P2: 主仓 track 下恰有一份 observation" \
  $([[ -n "$f" && "$(obs_count "$d")" -eq 1 ]]; echo $?)
awk -F '\t' -v source="$d/task.md" -v digest="$task_hash" '
  $1 == source || $2 != digest {exit 1}
  NR == 1 {path=$1}
  $1 != path {exit 1}
  END {exit NR == 2 ? 0 : 1}
' "$task_uses"
check "P2: 所有腿读取同一份冻结 task，且字节 digest 与源文件一致" $?
[[ -f "$d/raw/matched.task.md" ]] && cmp -s "$d/task.md" "$d/raw/matched.task.md"
check "P2: 冻结 task 与 panel artifacts 同位置持久落盘" $?
python3 - "$f" <<'PY'
import json, sys
p=json.load(open(sys.argv[1], encoding="utf-8"))
assert p["schema_version"] == 2
assert p["track"] == "current" and p["controller"] == "panel-review"
assert p["event"] == "execution_finished" and p["exit_code"] == 0
assert p["label"] == "task" and isinstance(p["duration_ms"], int) and p["duration_ms"] >= 0
a=p["actual"]
assert a["adapter"] == "panel-review" and a["risk"] == "high" and a["degraded"] is False
assert a["model"] is None and a["work_exit_code"] == 0
assert len(a["legs"]) == 2 and {x["name"] for x in a["legs"]} == {"submimo","subdeepseek"}
for leg in a["legs"]:
    assert leg["schema_version"] == 2 and leg["process"] == {"state":"exited","exit_code":0}
    assert leg["verdict"] == "PASS" and leg["degraded"] is False
    assert leg["evidence"]["ref"].startswith("file://") and leg["evidence"]["digest"].startswith("sha256:")
    assert leg["normalizer_version"] == 1
assert all(v is None for v in p["usage"].values())
raw=open(sys.argv[1], encoding="utf-8").read()
for forbidden in ("PANEL_PROMPT_SENTINEL", "Conclusion: PASS", "transcript"):
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
assert leg["degraded"] is True and leg["process"] == {"state":"exited","exit_code":0}
assert leg["verdict"] == "PASS"
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
  # 🔴 **二进制得是这条腿自己的**。只问"存在"挡不住**交叉接线**:把某条腿的底座腿
  # 指到**另一条腿已经存在的**二进制上(例如 subgemini 的底座腿写成 subkimi)——
  # 文件存在、桩跑得起来、P7 全绿,而生产环境里那条腿跑的是**别人家的模型**,
  # 花名册和归档闸却照旧按它自己的家族记账。**"覆盖两个不同家族"当场变成假话。**
  # 第三轮四审 subdeepseek(M1)与第二轮 subkimi 各自独立指到这处;
  # 我自审时把它判成"错误信息会指错地方"而**决定不加** —— 判错了,这里改判。
  # 约定:二进制名必须是腿名本身或以"腿名-"开头(现有五条腿都是 subX / subX-agent)。
  for bin_name in "$agent" ${chat:+"$chat"}; do
    check "P7pre[$leg]: $bin_name 是这条腿自己的二进制(不许交叉接到别条腿上)" \
      $([[ "$bin_name" == "$leg" || "$bin_name" == "$leg-"* ]]; echo $?)
  done
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

echo "[P8] --all 的派发与 compact observation 都覆盖运行时花名册全池"
: > "$calls"
before="$(obs_count "$d")"
prefix="$d/raw/p8-all"
out="$(PANEL_TEST_CALLS="$calls" PANEL_STATE_DIR="$d/state-p8" PANEL_STAGGER_MAX=0 \
  bash "$d/bin/panel-review" --track current --risk standard --all \
  "${common[@]}" "$prefix" 2>&1)"; rc=$?
check "P8: track-bound --all 正常成功" $([[ $rc -eq 0 ]]; echo $?)
check "P8: --all 真实调用数等于花名册长度" \
  $([[ "$(wc -l < "$calls")" -eq "${#PANEL_LEGS_ORDER[@]}" ]]; echo $?)
check "P8: 全池结果写成一份 observation，不因腿数变化丢证据" \
  $([[ "$(obs_count "$d")" -eq $((before + 1)) ]]; echo $?)
f="$(latest_obs "$d")"
python3 - "$f" "${PANEL_LEGS_ORDER[@]}" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
assert {leg["name"] for leg in p["actual"]["legs"]} == set(sys.argv[2:])
PY
check "P8: observation 腿名单等于运行时花名册，不抄固定数量" $?

rm -rf "$d"
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
