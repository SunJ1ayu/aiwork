#!/usr/bin/env bash
# 判据:**panel-review 的花名册不许依赖控制器活着。**
#
# 立这道闸的两次真事故(track panel-roster-from-disk 的 proposal 里有全文):
#   · 08-23 11:49  控制器被 `timeout 120` 砍(活儿要跑 ~10 分钟)⇒ 整轮零记录;
#   · 08-19 12:18  控制器死因不明 ⇒ 同样零记录,而四条腿的日志全都跑完躺在盘上。
# 两次我都只能靠手工翻日志重建"派了谁、谁跑到哪儿";08-19 那次我没重建,
# 于是"原因不明"被写进了记忆。
#
# 根因(panel-review:541):`wait_leg` 里 `wait "$pid"; rc=$?` —— 退出码只有亲手起腿
# 的那个进程拿得到,是整套系统里**唯一不落盘的事实**,而花名册恰恰只需要它。
#
# ⚠️ 承重的是 R1/R2,而 R1 **必须走 run_leg 那条路**(subglm/subdeepseek):
# 08-23 真实挂掉的就是它。只测 submimo 那条直路会漏掉半个 bug。
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

# 假腿:睡 FAKE_SLEEP 秒 -> 写日志 -> 按 FAKE_RC 退出。
# 位置参数和真腿一致:$1=review $2=task $3=log $4=repo
make_leg() { # make_leg <path> <sleep> <rc>
  cat > "$1" <<EOF
#!/usr/bin/env bash
sleep $2
printf 'Conclusion: PASS\n' > "\$3"
exit $3
EOF
  chmod +x "$1"
}

make_fixture() { # make_fixture <dir> <sleep> <rc>
  local d="$1" sl="$2" rc="$3" b="$1/bin" repo="$1/repo"
  mkdir -p "$b" "$repo" "$d/raw" "$d/state"
  cp "$ROOT/bin/panel-review" "$b/panel-review"
  cp "$ROOT/bin/track-record" "$b/track-record"
  # panel-roster 是本单要造的东西;现在还不存在 ⇒ 判据必须因此红。
  [[ -x "$ROOT/bin/panel-roster" ]] && cp "$ROOT/bin/panel-roster" "$b/panel-roster"
  for leg in submimo subdeepseek subglm subkimi; do make_leg "$b/$leg" "$sl" "$rc"; done
  printf '# fake task\n' > "$d/task.md"
  ( cd "$repo"; git init -q -b main; git config user.email t@t; git config user.name t
    printf 'x\n' > app.txt; git add -A; git commit -qm init )
}

# 只留 subglm 一条腿(它走 run_leg 那条路 —— 08-23 真实挂掉的那条)
only_glm=(PANEL_MIMO_LEG=off PANEL_KIMI_LEG=off PANEL_DEEPSEEK_LEG=off)
# PANEL_SELECTION_START 必须钉死:不钉的话轮换每次挑不同的腿,
# R5 的格式基线就会自己抖起来(2026-08-23 生成基线时当场撞上,连取两遍就不一样)。
common_env=(PANEL_STAGGER_MAX=0 PANEL_SELECTION_START=0)

roster_cmd() { # roster_cmd <bindir> <prefix>
  "$1/panel-roster" "$2" 2>/dev/null
}

echo "=== 花名册不依赖控制器存活 ==="

# ---------------------------------------------------------------- R1 / R2 / R3
echo "[R1/R2/R3] 控制器死在第一条腿交卷之前 —— 复刻 08-23 的真实时间线"
d="$(mktemp -d)"; make_fixture "$d" 6 3        # 腿睡 6 秒后以 rc=3 退出
pre="$d/raw/killed"
env "${common_env[@]}" "${only_glm[@]}" PANEL_STATE_DIR="$d/state" \
  bash "$d/bin/panel-review" --no-track --no-my-review --risk standard --budget 1 \
  "$d/task.md" "$d/repo" "$pre" >"$d/ctl.out" 2>&1 &
ctl=$!
sleep 2                                        # 此刻:腿还在睡,一条都没交卷

check "R3: plan 在**任何一条腿交卷之前**就已落盘" \
  $([[ -s "$pre.plan" ]]; echo $?)
state_before_kill=0; [[ -e "$pre.subglm.state" ]] && state_before_kill=1

kill -TERM "$ctl" 2>/dev/null                  # 只打控制器(= timeout 的做法,已探针验过腿会活)
wait "$ctl" 2>/dev/null
sleep 8                                        # 等腿自己跑完(6 秒)+ 富余

check "R2: state 由**腿自己**写 —— 控制器死后它才出现" \
  $([[ "$state_before_kill" -eq 0 && -s "$pre.subglm.state" ]]; echo $?)
check "R1: 控制器被砍之后,花名册仍然算得出来,且退出码是真的(rc=3)" \
  $(roster_cmd "$d/bin" "$pre" | grep -q 'subglm=FAIL(rc=3)'; echo $?)
check "R1b: 走的确实是 run_leg 那条路(subglm 被选中,不是 submimo 顶包)" \
  $(grep -q 'subglm' "$pre.plan" 2>/dev/null; echo $?)

# ---------------------------------------------------------------- R4
echo "[R4] 花名册是纯函数:同样的盘上状态,连算两次逐字节相同"
a="$(roster_cmd "$d/bin" "$pre")"; b="$(roster_cmd "$d/bin" "$pre")"
check "R4: 两次输出逐字节相同" $([[ -n "$a" && "$a" == "$b" ]]; echo $?)

# ---------------------------------------------------------------- R7
echo "[R7] 腿也没留下 state(最坏情况)—— 必须说人话,不许印成 PASS、不许整行消失"
rm -f "$pre.subglm.state"
out7="$(roster_cmd "$d/bin" "$pre")"
check "R7: 那条腿仍然出现在花名册里(不许整行消失)" \
  $(grep -q 'subglm' <<<"$out7"; echo $?)
# ⚠️ 这一条单独看是"空输出也能绿"的瞎断言;它靠上下 R7a/R7c 两条正向断言兜住
#    (行必须在 + 必须印成未收尾),三条一起才咬得住。别单独引用它。
check "R7: 缺 state **绝不许**被读成 PASS" \
  $(! grep -qE 'subglm=PASS' <<<"$out7"; echo $?)
check "R7: 印成可识别的未收尾状态(KILLED/未收尾/NO_STATE 之一)" \
  $(grep -qE 'subglm=(KILLED|未收尾|NO_STATE)' <<<"$out7"; echo $?)

# ---------------------------------------------------------------- R5
echo "[R5] 正常路径下花名册**格式**不许变(verify.md 里粘的那行是下游)"
d5="$(mktemp -d)"; make_fixture "$d5" 0 0
pre5="$d5/raw/normal"
env "${common_env[@]}" PANEL_STATE_DIR="$d5/state" \
  bash "$d5/bin/panel-review" --no-track --no-my-review --risk standard --budget 1 \
  "$d5/task.md" "$d5/repo" "$pre5" >"$d5/ctl.out" 2>&1
golden="$ROOT/tests/fixtures/panel-roster-format.golden"
norm() {  # 抹掉天然会变的两样:时间戳、fixture 的 HEAD
  sed -E -e 's/^# panel-review 花名册\(.*\)task=.*$/# panel-review 花名册(<TS>)task=<TASK>/' \
         -e 's/^# snapshot=head:.*$/# snapshot=head:<HEAD>/' \
         -e 's@^# 日志:.*$@# 日志:<PREFIX>@' "$1"
}
if [[ -f "$golden" ]]; then
  check "R5: 控制器正常收尾写出的花名册,与格式基线逐字节一致" \
    $(diff -q <(norm "$pre5.roster") <(norm "$golden") >/dev/null; echo $?)
  check "R5b: panel-roster 事后算出的,与控制器当场写的**完全一样**" \
    $(diff -q <(norm "$pre5.roster") <(roster_cmd "$d5/bin" "$pre5" | norm /dev/stdin) >/dev/null; echo $?)
else
  bad "R5: 缺格式基线 tests/fixtures/panel-roster-format.golden(本单要生成)"
  bad "R5b: 同上,基线缺失无法比对"
fi

# ---------------------------------------------------------------- R6
echo "[R6] agent 腿挂了回落聊天腿:两份 state 各自归位,降级标记不丢"
d6="$(mktemp -d)"; make_fixture "$d6" 0 0
make_leg "$d6/bin/subglm-agent" 0 9            # 底座腿挂(rc=9)
make_leg "$d6/bin/subglm" 0 0                  # 聊天腿成
pre6="$d6/raw/fallback"
env "${common_env[@]}" "${only_glm[@]}" PANEL_STATE_DIR="$d6/state" \
  bash "$d6/bin/panel-review" --no-track --no-my-review --risk standard --budget 1 \
  "$d6/task.md" "$d6/repo" "$pre6" >"$d6/ctl.out" 2>&1
check "R6: 底座腿那次的 state 单独留档(.agent.state)" \
  $([[ -s "$pre6.subglm.agent.state" ]]; echo $?)
check "R6: 回落后聊天腿的 state 也在" $([[ -s "$pre6.subglm.state" ]]; echo $?)
check "R6: 花名册仍然标出降级(不许把降级腿说成健康腿)" \
  $(roster_cmd "$d6/bin" "$pre6" | grep -q '降级'; echo $?)

echo
echo "---- 合计 PASS=$PASS FAIL=$FAIL ----"
[[ "$FAIL" -eq 0 ]]
