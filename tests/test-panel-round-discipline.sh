#!/usr/bin/env bash
# 评审轮次读数 oracle(track panel-round-discipline,2026-09-16)。
#
# 为什么有这套判据:09-16「查更新被限流」单跑了八轮外审,4~8 轮审的是我自己的判据措辞
# (产品代码零改动),当天烧光 Kimi 与 GLM 的额度。业主定「写成硬规矩,不是靠我记住」。
# 机器那半 = panel-review 在派活当场打印「这是第几轮 + 自上一轮以来到底改了什么」。
#
# 🔴 它是**读数不是闸**:只打印、不阻断、不改退出码(R6)。硬拦会在正当的第 4 轮
#    (产品真改了)误伤,而误伤一次就会被绕过去,从此没人看它。
#
# 🔴 下面三条是**先在真机器上量出来**才写进判据的,不是我拍脑袋设计的(2026-09-16):
#    ① `subject.source.head_oid` 是 schema 必填 ⇒ 「字段缺失」不是可达状态,不为它写分支;
#    ② 0 腿的自审轮(risk=self/budget 0)整份 observation **哪儿都没有 commit**;
#    ③ 腿没交卷(failure_kind=no_verdict)时 `subject.source` 是 **null**。
#    ⇒ ②③ 才是「上一轮的 commit 读不出来」的真实成因(R4),而基线必须**跳过**这种轮次,
#      取最近一份读得出 commit 的(R4b)—— 否则一轮死腿就把基线冲成"没得比"。
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 与 test-panel-observation.sh 同款隔离:选腿/开关全走环境变量,调用者环境里飘一个
# PANEL_*_LEG=off 就能把判卷防线悄悄关掉(08-26 subkimi 实证)。
if [[ "${PANEL_ROUND_ENV_SCRUBBED:-}" != "1" ]]; then
  exec env -u PANEL_MIMO_LEG -u PANEL_DEEPSEEK_LEG -u PANEL_GLM_LEG \
    -u PANEL_KIMI_LEG -u PANEL_GEMINI_LEG -u PANEL_GROK_LEG \
    -u PANEL_HEALTH_OVERRIDE -u PANEL_SELECTION_START -u PANEL_STATE_DIR \
    -u PANEL_STAGGER_MAX -u PANEL_IMPACT_RISK -u PANEL_REVIEW_BUDGET \
    -u PANEL_DIFF_BASE -u PANEL_INCLUDE -u PANEL_ORACLE_CMD \
    PANEL_ROUND_ENV_SCRUBBED=1 bash "$0" "$@"
fi
. "$ROOT/bin/_panel-roster-lib.sh"

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

check "R0: 入口已清掉外层 PANEL_ORACLE_CMD(否则桩 panel 递归跑总闸)" \
  $([[ -z "${PANEL_ORACLE_CMD:-}" ]]; echo $?)

# 健康桩:像真腿一样产 typed facts(含 head_oid)。腿名单从唯一源长出来,判据不抄第二份。
make_healthy_stubs() { # bindir
  local b="$1" leg bin_name
  for leg in "${PANEL_LEGS_ORDER[@]}"; do
    for bin_name in "$leg" "$leg-agent"; do
      cat > "$b/$bin_name" <<'EOF'
#!/usr/bin/env bash
printf 'Conclusion: PASS\n' > "$3"
case "${AIWORK_REVIEW_ADAPTER:?}" in
  submimo) model=xiaomi/mimo-v2-flash ;;
  subdeepseek-agent|subdeepseek) model=deepseek-chat ;;
  subglm-agent) model=go/glm-4.5 ;;  subglm) model=glm-4.5 ;;
  subkimi) model=kimi-code/k2.5 ;;   subgemini) model=gemini-2.5-pro ;;
  subgrok) model=grok-fixture ;;
esac
object_format="$(git -C "$4" rev-parse --show-object-format)"
head_oid="$(git -C "$4" rev-parse HEAD)"
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

# 死桩:退出 0 但一个字都不交 ⇒ failure_kind=no_verdict ⇒ subject.source 为 null。
make_dead_stubs() { # bindir
  local b="$1" leg bin_name
  for leg in "${PANEL_LEGS_ORDER[@]}"; do
    for bin_name in "$leg" "$leg-agent"; do
      printf '#!/usr/bin/env bash\nexit 0\n' > "$b/$bin_name"; chmod +x "$b/$bin_name"
    done
  done
}

make_fixture() { # root
  local d="$1" b="$1/bin" repo="$1/repo"
  mkdir -p "$b" "$repo/tracks/current" "$repo/tests" "$d/raw" "$d/state"
  cp "$ROOT/bin/panel-review" "$ROOT/bin/_panel-roster-lib.sh" \
     "$ROOT/bin/_review_result.py" "$ROOT/bin/track-record" "$b/"
  make_healthy_stubs "$b"
  printf '# PANEL_PROMPT_SENTINEL\n' > "$d/task.md"
  cat > "$repo/tracks/current/decision.json" <<'EOF'
{
  "schema_version": 2,
  "track": "current",
  "impact": {"level": "standard", "factors": []},
  "design": {"uncertainty": "low", "premise_attack": {"status": "not_required", "evidence": []}},
  "execution_plan": {"adapter": "main", "model": null},
  "outcome": {"verdict": null}
}
EOF
  printf '# Verify\n' > "$repo/tracks/current/verify.md"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  # 夹具仓不许继承本机 hooks:track-guard/track-commit-msg 会拦住夹具的提交。
  git -C "$repo" config core.hooksPath /dev/null
  printf 'x\n' > "$repo/app.txt"; printf 't\n' > "$repo/tests/t.txt"
  git -C "$repo" add -A; git -C "$repo" commit -qm init
}

commit_in() { git -C "$1/repo" add -A; git -C "$1/repo" commit -qm "$2"; }

OUTF=""
# 🔴 输出走文件、退出码走返回值:`out="$(run_panel ...)"` 会把函数塞进子 shell,
# 在里面设的变量传不回父 shell(R4/R6 会读到上一趟的过期值 ⇒ 假绿)。
run_panel() { # d 序号 extra-args...
  local d="$1" n="$2"; shift 2
  PANEL_STATE_DIR="$d/state-$n" PANEL_STAGGER_MAX=0 \
    bash "$d/bin/panel-review" --risk standard --budget 1 --no-my-review \
    "$@" "$d/task.md" "$d/repo" "$d/raw/$n" > "$OUTF" 2>&1
}

MARK='轮次读数'
echo "=== 评审轮次读数 oracle ==="

echo "[R1] 第一轮没有"上一轮"可比 ⇒ 一个字都不打印(打了就是噪音)"
d="$(mktemp -d)"; make_fixture "$d"; OUTF="$d/out.txt"
run_panel "$d" 1 --track current; rc1=$?
out="$(cat "$OUTF")"
grep -q "$MARK" <<<"$out"
check "R1: 零份 observation ⇒ 不打印轮次读数" $([[ $? -ne 0 ]]; echo $?)
check "R1: 这一趟本身是绿的(rc=$rc1),夹具可信" $([[ $rc1 -eq 0 ]]; echo $?)

echo "[R2] 上一轮之后只动了 tests/ ⇒ 第 2 轮,其它桶为 0"
C1="$(git -C "$d/repo" rev-parse HEAD)"
printf 't2\n' >> "$d/repo/tests/t.txt"; commit_in "$d" "只改判据"
run_panel "$d" 2 --track current; rc2=$?
out="$(cat "$OUTF")"
grep -q "$MARK" <<<"$out";                          check "R2: 打印了轮次读数" $?
grep -qE '第[[:space:]]*2[[:space:]]*轮' <<<"$out";  check "R2: 认出这是第 2 轮" $?
grep -qE 'tests/=1' <<<"$out";                      check "R2: tests/ 桶=1" $?
grep -qE '其它=0' <<<"$out";                         check "R2: 其它桶=0 —— 这一轮在审我自己的考卷" $?
grep -q "${C1:0:12}" <<<"$out";                     check "R2: 打印了上一轮的 commit" $?
check "R2: rc 不变(基线 $rc1 / 本趟 $rc2)" $([[ $rc2 -eq $rc1 ]]; echo $?)

echo "[R3] 上一轮之后动了产品文件 ⇒ 其它桶非 0 且**列出文件名**"
rm -rf "$d"; d="$(mktemp -d)"; make_fixture "$d"; OUTF="$d/out.txt"
run_panel "$d" 1 --track current
printf 'y\n' >> "$d/repo/app.txt"; printf 't2\n' >> "$d/repo/tests/t.txt"
commit_in "$d" "产品+判据都改"
run_panel "$d" 2 --track current
out="$(cat "$OUTF")"
grep -qE '其它=1' <<<"$out";   check "R3: 其它桶=1" $?
grep -q 'app.txt' <<<"$out";   check "R3: 列出了产品文件名(只给计数会漏掉搬进 tests/ 的产品逻辑)" $?
grep -qE 'tests/=1' <<<"$out"; check "R3: tests/ 桶同时=1" $?

echo "[R3b] **未跟踪**的产品文件也要算进去(本机反复栽在"working 有而 staged 没有")"
rm -rf "$d"; d="$(mktemp -d)"; make_fixture "$d"; OUTF="$d/out.txt"
run_panel "$d" 1 --track current
printf 'z\n' > "$d/repo/newfeature.py"      # 不 git add
run_panel "$d" 2 --track current
out="$(cat "$OUTF")"
grep -q 'newfeature.py' <<<"$out"; check "R3b: 未跟踪的新产品文件出现在读数里" $?
grep -qE '其它=1' <<<"$out";       check "R3b: 它算进"其它"桶" $?

echo "[R4] 上一轮的腿没交卷(subject.source=null)⇒ 明说读不出来,不静默、不改退出码"
rm -rf "$d"; d="$(mktemp -d)"; make_fixture "$d"; OUTF="$d/out.txt"
make_dead_stubs "$d/bin"
run_panel "$d" 1 --track current
make_healthy_stubs "$d/bin"
printf 'y\n' >> "$d/repo/app.txt"; commit_in "$d" "产品改了"
run_panel "$d" 2 --track current; rc4=$?
out="$(cat "$OUTF")"
grep -q "$MARK" <<<"$out";     check "R4: 仍然打印轮次读数(轮数本身数得出来)" $?
grep -q '读不出来' <<<"$out";   check "R4: 明说上一轮的 commit 读不出来(fail loud,不静默跳过)" $?
check "R4: 退出码不受影响(rc=$rc4)" $([[ $rc4 -eq 0 ]]; echo $?)

echo "[R4b] 中间那轮死了 ⇒ 基线要**跳过它**,取最近一份读得出 commit 的"
rm -rf "$d"; d="$(mktemp -d)"; make_fixture "$d"; OUTF="$d/out.txt"
run_panel "$d" 1 --track current                     # 第 1 轮:健康,记在 C1
C1="$(git -C "$d/repo" rev-parse HEAD)"
printf 'y\n' >> "$d/repo/app.txt"; commit_in "$d" "产品改了"
make_dead_stubs "$d/bin"
run_panel "$d" 2 --track current                     # 第 2 轮:全死,没有 commit
make_healthy_stubs "$d/bin"
printf 't2\n' >> "$d/repo/tests/t.txt"; commit_in "$d" "又改判据"
run_panel "$d" 3 --track current
out="$(cat "$OUTF")"
grep -qE '第[[:space:]]*3[[:space:]]*轮' <<<"$out"; check "R4b: 轮数把死掉那轮也数进去(它确实派过)" $?
grep -q "${C1:0:12}" <<<"$out";                     check "R4b: 基线回退到第 1 轮的 commit" $?
grep -q 'app.txt' <<<"$out";     check "R4b: 因此 C1 以来的产品改动没被死腿那轮吞掉" $?
grep -qE '其它=1' <<<"$out";     check "R4b: 其它桶=1(不是 0)" $?

echo "[R5] --no-track ⇒ 没有 track 就没有"轮次"这回事,一个字都不打印"
rm -rf "$d"; d="$(mktemp -d)"; make_fixture "$d"; OUTF="$d/out.txt"
run_panel "$d" 1 --track current
printf 'y\n' >> "$d/repo/app.txt"; commit_in "$d" "产品改了"
run_panel "$d" 2 --no-track
out="$(cat "$OUTF")"
grep -q "$MARK" <<<"$out"
check "R5: --no-track ⇒ 不打印" $([[ $? -ne 0 ]]; echo $?)

rm -rf "$d"
echo
echo "---- 合计 $((PASS+FAIL)) 条,$FAIL 条不合格 ----"
[[ "$FAIL" -eq 0 ]]
