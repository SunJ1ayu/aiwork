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

unset ZHIPU_INCLUDE DEEPSEEK_INCLUDE

# Test fixtures use a stable model independently of the operator's model choice.
export CURSOR_MODEL=composer-2.5
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
if [[ "$3" -eq 0 ]]; then
  case "\${AIWORK_REVIEW_ADAPTER:?}" in
    submimo) model=xiaomi/mimo-v2-flash ;;
    subdeepseek-agent|subdeepseek) model=deepseek-chat ;;
    subglm-agent) model=go/glm-4.5 ;;
    subglm) model=glm-4.5 ;;
    subkimi) model=kimi-code/k2.5 ;;
    subgemini) model=gemini-2.5-pro ;;
    subgrok) model=grok-fixture ;;
    subcursor) model=composer-2.5 ;;
  esac
  object_format="\$(git -C "\$4" rev-parse --show-object-format)"
  head_oid="\$(git -C "\$4" rev-parse HEAD)"
  # fixture 仓保持 clean/static；只读冻结 tree，不用 write-tree 争共享 index.lock。
  tree_oid="\$(git -C "\$4" rev-parse 'HEAD^{tree}')"
  python3 "\${AIWORK_REVIEW_RESULT_BIN:?}" facts --output "\${AIWORK_REVIEW_FACTS_PATH:?}" \
    --requested-model "\$model" --invoked-model "\$model" --reported-model "\$model" \
    --git-object-format "\$object_format" --head-oid "\$head_oid" \
    --index-tree-oid "\$tree_oid" --worktree-tree-oid "\$tree_oid" \
    --view-delivery-state complete --view-mode full_snapshot --evidence-completeness complete
fi
exit $3
EOF
  chmod +x "$1"
}

# 全部腿名 —— 唯一源是 bin/_panel-roster-lib.sh 的 PANEL_LEGS_ORDER。
mapfile -t _ALL_LEGS < <(. "$ROOT/bin/_panel-roster-lib.sh"; printf '%s\n' "${PANEL_LEGS_ORDER[@]}")

make_fixture() { # make_fixture <dir> <sleep> <rc>
  local d="$1" sl="$2" rc="$3" b="$1/bin" repo="$1/repo"
  mkdir -p "$b" "$repo" "$d/raw" "$d/state"
  cp "$ROOT/bin/panel-review" "$b/panel-review"
  # 花名册渲染的共享库:panel-review 和 panel-roster 都 source 它(只许有一份)。
  # 真实 bin/ 里本来就在,夹具得跟上 —— 这是管线,不是断言。
  if [[ -f "$ROOT/bin/_panel-roster-lib.sh" ]]; then
    cp "$ROOT/bin/_panel-roster-lib.sh" "$ROOT/bin/aiwork-config" "$ROOT/bin/_aiwork_config.py" "$ROOT/bin/_review_result.py"  "$b/"
  fi
  # panel-roster 是本单要造的东西;现在还不存在 ⇒ 判据必须因此红。
  [[ -x "$ROOT/bin/panel-roster" ]] && cp "$ROOT/bin/panel-roster" "$b/panel-roster"
  # 腿列表**从唯一源读**,不在夹具里抄第三份。2026-08-26 加第五条腿时,
  # 这里漏了 ⇒ 夹具只造四条假腿 ⇒ 第五条在花名册里印成 off 而不是 SKIP(rotation)
  # ⇒ R5 的格式基线对不上,而红的原因跟被测行为无关。
  for leg in "${_ALL_LEGS[@]}"; do make_leg "$b/$leg" "$sl" "$rc"; done
  printf '# fake task\n' > "$d/task.md"
  ( cd "$repo"; git init -q -b main; git config user.email t@t; git config user.name t
    printf 'x\n' > app.txt; git add -A; git commit -qm init )
}

# 腿名 → 开关名是机械规律:sub<X> ⇒ PANEL_<X大写>_LEG。**别再手抄第四份名单**
# (2026-08-26:花名册/panel-review/夹具/这里各存了一份"当前有几条腿",加腿漏了三处)。
_leg_off_var() { printf 'PANEL_%s_LEG' "$(printf '%s' "${1#sub}" | tr '[:lower:]' '[:upper:]')"; }
_all_off=(); for _l in "${_ALL_LEGS[@]}"; do _all_off+=("$(_leg_off_var "$_l")=off"); done
# 只留 subglm 一条腿(它走 run_leg 那条路 —— 08-23 真实挂掉的那条)
only_glm=(); for _l in "${_ALL_LEGS[@]}"; do
  [[ "$_l" == subglm ]] || only_glm+=("$(_leg_off_var "$_l")=off"); done
# PANEL_SELECTION_START 必须钉死:不钉的话轮换每次挑不同的腿,
# R5 的格式基线就会自己抖起来(2026-08-23 生成基线时当场撞上,连取两遍就不一样)。
common_env=(PANEL_STAGGER_MAX=0 PANEL_SELECTION_START=0)

# 等一个文件出现,**别用固定 sleep**:机器一忙,`sleep 2` 就可能不够(假红),
# 而 `sleep 8` 等腿跑完同理。评审腿 subglm 指出这一条 —— 本机"判据自己会造抖动"
# 已经记过账,而抖动最舒服的解释永远是"它只是抖",顺着走下一步就是调钝报警器。
wait_for() {  # wait_for <文件> [最多秒]
  local f="$1" max="${2:-30}" i=0
  while [[ ! -s "$f" ]] && (( i < max * 5 )); do sleep 0.2; i=$((i+1)); done
  [[ -s "$f" ]]
}

roster_cmd() { # roster_cmd <bindir> <prefix>
  "$1/panel-roster" "$2" 2>/dev/null
}

echo "=== 花名册不依赖控制器存活 ==="

# ---------------------------------------------------------------- R1 / R2 / R3
echo "[R1/R2/R3] 控制器死在第一条腿交卷之前 —— 复刻 08-23 的真实时间线"
d="$(mktemp -d)"; make_fixture "$d" 6 3        # 腿睡 6 秒后以 rc=3 退出
pre="$d/raw/killed"
env "${common_env[@]}" "${only_glm[@]}" PANEL_STATE_DIR="$d/state" \
  bash "$d/bin/panel-review" --no-my-review --risk standard --budget 1 \
  "$d/task.md" "$d/repo" "$pre" >"$d/ctl.out" 2>&1 &
ctl=$!
wait_for "$pre.plan" 30                        # 等 plan 落盘(腿还在睡 6 秒,一条都没交卷)

# 「在任何一条腿交卷之前」不是靠掐表证明的,是靠**此刻盘上还没有任何 state** 证明的。
check "R3: plan 在**任何一条腿交卷之前**就已落盘" \
  $([[ -s "$pre.plan" && ! -e "$pre.subglm.state" ]]; echo $?)
state_before_kill=0; [[ -e "$pre.subglm.state" ]] && state_before_kill=1

kill -TERM "$ctl" 2>/dev/null                  # 只打控制器(= timeout 的做法,已探针验过腿会活)
wait "$ctl" 2>/dev/null
wait_for "$pre.subglm.state" 30                # 等腿自己跑完(睡 6 秒)——轮询,不掐表

check "R2: state 由**腿自己**写 —— 控制器死后它才出现" \
  $([[ "$state_before_kill" -eq 0 && -s "$pre.subglm.state" ]]; echo $?)
python3 "$d/bin/_review_result.py" validate "$pre.subglm.result.json"
check "R2b: 控制器死后 detached 腿仍留下合法 typed terminal result" $?
out_result="$(python3 "$d/bin/_review_result.py" eligible "$pre.subglm.result.json" 2>/dev/null)"; result_rc=$?
check "R2c: shadow result 缺对象事实时保守 ineligible，不从 rc=0 猜 coverage" \
  $([[ "$result_rc" -ne 0 && "$out_result" == *subject_unknown* && "$out_result" == *view_incomplete* ]]; echo $?)
check "R1: 控制器被砍之后,花名册仍然算得出来,且退出码是真的(rc=3)" \
  $(roster_cmd "$d/bin" "$pre" | grep -q 'subglm=FAIL(rc=3)'; echo $?)
check "R1b: 走的确实是 run_leg 那条路(subglm 被选中,不是 submimo 顶包)" \
  $(grep -q 'subglm' "$pre.plan" 2>/dev/null; echo $?)

# ---------------------------------------------------------------- R4
echo "[R4] 花名册是纯函数:同样的盘上状态,连算两次逐字节相同"
# ⚠️ 必须抹掉渲染时间戳再比:`render_roster` 里嵌了秒级 `date`,
#    那一行语义上是"这份花名册是什么时候渲染的",**不属于**盘上状态的函数。
#    第一版直接比原文 ⇒ 两次调用跨过秒边界就红。评审腿(subdeepseek F2)的
#    全套跑里它**真的红了**,而我自己那次绿是运气。
strip_ts() { sed -E 's/^# panel-review 花名册\(.*\)task=/# panel-review 花名册(<TS>)task=/'; }
a="$(roster_cmd "$d/bin" "$pre" | strip_ts)"; b="$(roster_cmd "$d/bin" "$pre" | strip_ts)"
check "R4: 两次输出逐字节相同(抹掉渲染时间戳之后)" $([[ -n "$a" && "$a" == "$b" ]]; echo $?)

# ---------------------------------------------------------------- R7
echo "[R7] 腿也没留下 state(最坏情况)—— 必须说人话,不许印成 PASS、不许整行消失"
rm -f "$pre.subglm.state"
out7="$(roster_cmd "$d/bin" "$pre")"
check "R7: 那条腿仍然出现在花名册里(不许整行消失)" \
  $(grep -q 'subglm' <<<"$out7"; echo $?)
# ⚠️ 这一条单独看是"空输出也能绿"的瞎断言;它靠紧随其后的两条 R7 断言兜住
#    (不许印成 PASS + 必须印成未收尾),三条一起才咬得住。别单独引用它。
#    (2026-08-23:原文写的是"上下 R7a/R7c",而这份判据里从来没有叫 R7a/R7c 的断言。)
check "R7: 缺 state **绝不许**被读成 PASS" \
  $(! grep -qE 'subglm=PASS' <<<"$out7"; echo $?)
# ⚠️ 这里**不许**再把 KILLED 列成合格写法:R7d 专门禁止它(盘上证据说不了死因)。
# 列着它 = 同一份判据里两条断言自相矛盾,而矛盾的那一半迟早被人拿去当依据。
check "R7: 印成可识别的未收尾状态(未收尾/NO_STATE 之一)" \
  $(grep -qE 'subglm=(未收尾|NO_STATE)' <<<"$out7"; echo $?)
# R7d:**也不许反过来断言它死了**。盘上信息区分不了"被砍"和"还在跑",
# 而 2026-08-23 派全员评审时,进行中的花名册把两条活着的腿印成了 KILLED ——
# 这道闸自己犯了它要防的病:说了一句盘上证据支持不了的话。
check "R7d: 不许断言死因(没有证据说明它是被砍的还是还在跑)" \
  $(! grep -q 'subglm=KILLED' <<<"$out7"; echo $?)

# ---------------------------------------------------------------- R5
echo "[R5] 正常路径下花名册**格式**不许变(verify.md 里粘的那行是下游)"
d5="$(mktemp -d)"; make_fixture "$d5" 0 0
pre5="$d5/raw/normal"
env "${common_env[@]}" PANEL_STATE_DIR="$d5/state" \
  bash "$d5/bin/panel-review" --no-my-review --risk standard --budget 1 \
  "$d5/task.md" "$d5/repo" "$pre5" >"$d5/ctl.out" 2>&1
golden="$ROOT/tests/fixtures/panel-roster-format.golden"
norm() {  # 抹掉天然会变的两样:时间戳、fixture 的 HEAD
  # 这里是**整行替换**,看着像"抹过头了、键名回归就抓不到" —— 评审腿 subglm
  # 第一轮就是这么报的,我也照着收紧过一版(只抹值、留键名)。
  # **对照组证伪了它**:整行替换只在**匹配旧格式**时才发生,键名一改就不匹配、
  # 原样留下、diff 当场红。两种写法的检出能力一样,所以退回原样,别留
  # "我修了个洞"的假象。真正值钱的是这条发现逼出来的红检 M12(改键名 -> R5 红),
  # 它现在守着这件事本身。
  sed -E -e 's/^# panel-review 花名册\(.*\)task=.*$/# panel-review 花名册(<TS>)task=<TASK>/' \
         -e 's/^# snapshot=head:.*$/# snapshot=head:<HEAD>/' \
         -e 's@^# 日志:.*$@# 日志:<PREFIX>@' "$1"
}
if [[ -f "$golden" ]]; then
  check "R5: 控制器正常收尾写出的花名册,与格式基线**归一化后一致**" \
    $(diff -q <(norm "$pre5.roster") <(norm "$golden") >/dev/null; echo $?)
  check "R5b: panel-roster 事后算出的,与控制器当场写的**归一化后一致**" \
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
  bash "$d6/bin/panel-review" --no-my-review --risk standard --budget 1 \
  "$d6/task.md" "$d6/repo" "$pre6" >"$d6/ctl.out" 2>&1
check "R6: 底座腿那次的 state 单独留档(.agent.state)" \
  $([[ -s "$pre6.subglm.agent.state" ]]; echo $?)
check "R6: 回落后聊天腿的 state 也在" $([[ -s "$pre6.subglm.state" ]]; echo $?)
python3 "$d6/bin/_review_result.py" validate "$pre6.subglm.agent.result.json" \
  && python3 "$d6/bin/_review_result.py" validate "$pre6.subglm.result.json"
check "R6: primary/fallback 两次 attempt 都留下合法 terminal result" $?
check "R6: 花名册仍然标出降级(不许把降级腿说成健康腿)" \
  $(roster_cmd "$d6/bin" "$pre6" | grep -q '降级'; echo $?)

# ---------------------------------------------------------------- R8
echo "[R8] 共享库缺失必须 fail closed(2026-08-23 自己踩出来的)"
# 实现第一版是裸 `.` source。脚本没开 set -e ⇒ 缺文件只打一行错就往下跑 ⇒
# render_roster/verdict_of 全不存在 ⇒ 花名册静默变空、observation 一份不写,
# **而退出码还是 0**。我就是这么一次打红了 21 条既有判据才发现的。
# 静默放过 = 假绿,和 `env '=key'` rc=0 那次是同一种病。
d8="$(mktemp -d)"; mkdir -p "$d8/bin"
cp "$ROOT/bin/panel-review" "$d8/bin/panel-review"     # 故意**不**复制共享库
out8="$(bash "$d8/bin/panel-review" --no-my-review /dev/null 2>&1)"; rc8=$?
# ⚠️ 这两条第一版是**为了错误的理由绿的**(红检 M7 当场照出来):
#    改回裸 source 之后脚本照样非零退出(后面别的原因),而 bash 自己那句
#    "No such file" 里也含库名 ⇒ 两条都撞对了,却没一条在问我要保证的事。
#    改成只认 fail-closed 分支**独有**的证据:专用退出码 70 + 我自己那句话。
check "R8: 缺共享库时走的是 fail-closed 那条路(专用退出码 70)" \
  $([[ "$rc8" -eq 70 ]]; echo $?)
check "R8: 而且是**我们自己**拒绝的,不是 bash 顺带报的错" \
  $(grep -q '拒绝空跑' <<<"$out8"; echo $?)

# ---------------------------------------------------------------- R9
echo "[R9] 升级追加的增补腿不许隐身(评审腿 subdeepseek F1 抓到的真回归)"
# .plan 写在派发之前,而升级追加腿时只翻内存里的 LEG_SELECTED、**没更新 plan**
# ⇒ 一条真跑过的腿被印成 SKIP(rotation);它要是跑失败了,失败也一起消失 ——
# **正是这个功能存在要防的那种数据丢失**,而且改动前的老代码是对的。
# 原则:**盘上有 state = 它真的跑过**,plan 只说明"原本打算派谁"。
d9="$(mktemp -d)"; mkdir -p "$d9/bin" "$d9/raw"
cp "$ROOT/bin/_panel-roster-lib.sh" "$ROOT/bin/aiwork-config" "$ROOT/bin/_aiwork_config.py" "$ROOT/bin/_review_result.py"  "$ROOT/bin/panel-roster" "$d9/bin/"
cat > "$d9/raw/esc.plan" <<'PLAN'
task=t
impact-risk=high
requested-budget=2
selected-count=2
selected=submimo(xiaomi/submimo),subdeepseek(deepseek/subdeepseek)
snapshot-head=abc123
leg	submimo	1	healthy
leg	subdeepseek	1	healthy
leg	subglm	0	healthy
leg	subkimi	0	off
PLAN
printf 'rc=3\n'  > "$d9/raw/esc.submimo.state"
printf 'rc=0\n'  > "$d9/raw/esc.subdeepseek.state"
printf 'rc=5\n'  > "$d9/raw/esc.subglm.state"     # 增补腿真跑了、而且**失败**了
printf 'Conclusion: PASS\n' > "$d9/raw/esc.subdeepseek.log"
out9="$("$d9/bin/panel-roster" "$d9/raw/esc" 2>/dev/null)"
check "R9a: 盘上有 state 的增补腿,绝不许印成 SKIP(rotation)" \
  $(! grep -q 'subglm=SKIP' <<<"$out9"; echo $?)
check "R9b: 而且它的失败要印出来(rc=5 不许隐身)" \
  $(grep -q 'subglm=FAIL(rc=5)' <<<"$out9"; echo $?)
check "R9c: 没派也没 state 的腿仍然照实印 off" \
  $(grep -q 'subkimi=off' <<<"$out9"; echo $?)

# ---------------------------------------------------------------- R10
echo "[R10] 一条腿都没派(全 off)也要照实印,不许炸(评审腿 F4 的覆盖缺口)"
d10="$(mktemp -d)"; mkdir -p "$d10/bin" "$d10/raw"
cp "$ROOT/bin/_panel-roster-lib.sh" "$ROOT/bin/aiwork-config" "$ROOT/bin/_aiwork_config.py" "$ROOT/bin/_review_result.py"  "$ROOT/bin/panel-roster" "$d10/bin/"
{
  printf '%s\n' 'task=t' 'impact-risk=self' 'requested-budget=0' \
    'selected-count=0' 'selected=none' 'snapshot-head=abc123'
  for leg in "${_ALL_LEGS[@]}"; do printf 'leg\t%s\t0\toff\n' "$leg"; done
} > "$d10/raw/none.plan"
out10="$("$d10/bin/panel-roster" "$d10/raw/none" 2>&1)"; rc10=$?
check "R10: 全 off 时正常退出" $([[ "$rc10" -eq 0 ]]; echo $?)
check "R10: 花名册全池都印 off" \
  $([[ "$(grep -o '=off' <<<"$out10" | wc -l)" -eq "${#_ALL_LEGS[@]}" ]]; echo $?)

# ---------------------------------------------------------------- R11
echo "[R11] 杀法二:SIGTERM 打**整个进程组**(断线的杀法,不是 timeout 的)"
# 为什么必须单独有这一条:R1/R2 用 `kill -TERM $ctl` 只打控制器**本身**,于是
# `run_leg` 的后台子 shell 活了下来。把落盘从 setsid 里挪进那个子 shell,
# **R1~R10 二十一条全绿放行**(2026-08-23 亲手跑过对照组)。
# 而 panel-review 的规格白纸黑字写着"也不能在 run_leg 的后台子 shell 里",
# 只是**没人守** —— 又一次「该问的写进了规格却没写进判据」。
# 08-19 断线那次正是组信号(断线 SIGTERM 打整个进程组),前提探针实验 B 验过腿能活;
# 这条把那次一次性的探针变成常驻的闸。红检 M11 咬它。
d11="$(mktemp -d)"; make_fixture "$d11" 6 3
pre11="$d11/raw/grpkill"
setsid env "${common_env[@]}" "${only_glm[@]}" PANEL_STATE_DIR="$d11/state" \
  bash "$d11/bin/panel-review" --no-my-review --risk standard --budget 1 \
  "$d11/task.md" "$d11/repo" "$pre11" >"$d11/ctl.out" 2>&1 &
ctl11=$!
wait_for "$pre11.plan" 30
state11_before=0; [[ -e "$pre11.subglm.state" ]] && state11_before=1
pgid11="$(ps -o pgid= -p "$ctl11" 2>/dev/null | tr -d ' ')"
mypgid="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
# ⚠️ fail closed:拿不到 pgid、或者它跟判据自己同组,**绝不开枪** —— 那是自杀。
# (08-18 用 `pkill -f` 干过一次,把判据自己打死了。宁可这条红。)
if [[ -n "$pgid11" && -n "$mypgid" && "$pgid11" != "$mypgid" ]]; then
  kill -TERM -"$pgid11" 2>/dev/null; killed11=$?
else
  killed11=1
fi
wait "$ctl11" 2>/dev/null
wait_for "$pre11.subglm.state" 30              # 轮询,不掐表
check "R11a: 控制器自成进程组,组信号打得出去(且没打在判据自己身上)" "$killed11"
check "R11b: **整组**吃了 SIGTERM 之后,腿仍然把 state 写成了" \
  $([[ "$state11_before" -eq 0 && -s "$pre11.subglm.state" ]]; echo $?)
check "R11c: 花名册照样算得出真退出码(rc=3)" \
  $(roster_cmd "$d11/bin" "$pre11" | grep -q 'subglm=FAIL(rc=3)'; echo $?)

# ---------------------------------------------------------------- R12
echo "[R12] 第二轮评审的发现:说盘上证据支持不了的话(本单自己那条原则)"
# R12a:usage 文本必须和实际输出对得上。
# `bin/panel-roster` 的帮助里还写着"印成 KILLED",而 R7d **专门禁止**这个词 ——
# 两条腿(submimo F-1 / subdeepseek F1)独立命中同一处。文档留在上一版行为上,
# 读它的人会被误导,而判据只看输出、看不见文档。
check "R12a: panel-roster 的帮助文本里不许再出现 KILLED(与 R7d 实际行为一致)" \
  $(! grep -q 'KILLED' "$ROOT/bin/panel-roster"; echo $?)
# ⚠️ 只看**会被打印出来的**行:第一版连注释都查,于是库里那句讲历史的
# "两条腿被印成 KILLED" 也算残留 —— **误报**,而带误报的闸会逼出绕开它的习惯。
check "R12b: 共享库**印得出来的**字里不许有 KILLED 残留(注释讲历史不算)" \
  $(! grep -vE '^[[:space:]]*#' "$ROOT/bin/_panel-roster-lib.sh" | grep -q 'KILLED'; echo $?)

# R12f:**注释也要守,但只对"现在时"的那种。**
# 2026-08-23 评审腿 subdeepseek 在 `bin/panel-review:601` 抓到一句**现在时**、
# 描述现行行为的注释:"只把那条腿标成 KILLED(未收尾)" —— 与 R7d 和实际输出矛盾。
# 而我那次"全盘搜一遍"**根本没扫到它**:我用了 `--include=*.md --include=*.sh`,
# 而 `bin/` 下的工具**全是无扩展名脚本** ⇒ 半个仓没进搜索范围。
# ⇒ 机械化的判法:bin/ 里凡是出现 KILLED 的行,**上下两行内必须有四位年份**
#   (历史记账都带日期;而"这就是现在的行为"那种话不会带)。
#   **它守的是日期邻近,不是时态**(2026-08-23 评审腿 subdeepseek/submimo 各自实测):
#   一句带日期的现在时陈述照样过得去,一句不带日期的历史陈述反而被误伤。
#   所以它是**启发式代理指标**,不是"现在时陈述"的判据 —— 别让它许诺给不了的东西。
#   误报边界:真要写一句不带日期的历史陈述,补个日期即可 —— 成本一行,而它换来的是
#   "陈述过期"这类病第一次有了机器在查。
r12f_bad=0
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  grep -q 'KILLED' "$f" 2>/dev/null || continue
  # 取出每个命中行号,检查 ±2 行窗口里有没有 20xx 年份
  while IFS=: read -r ln _; do
    lo=$(( ln > 2 ? ln - 2 : 1 )); hi=$(( ln + 2 ))
    sed -n "${lo},${hi}p" "$f" | grep -qE '20[0-9]{2}' || { r12f_bad=1; echo "    ↳ 无日期的 KILLED 陈述:$f:$ln"; }
  done < <(grep -n 'KILLED' "$f")
done < <(find "$ROOT/bin" -maxdepth 1 -type f)
check "R12f: bin/ 里的 KILLED 行,上下两行内必须有四位年份(历史记账都带日期)" "$r12f_bad"

# R12c/R12d:`.final` 缺失时的两句头,都不许把"没有证据"说成"有证据".
#   · escalation 原话 "unknown(控制器没活到收尾)" —— 第二轮评审进行中就被印出来过,
#     而那个控制器活得好好的、只是在等腿(subdeepseek F4)。
#     **这道闸对腿守了 R7d,对控制器自己没守。**
#   · selected/selected-count 在 .final 缺失时取的是**派发前**的 plan 快照,
#     升级追加的腿不在里面,而头里读起来像事实(subdeepseek F2)。
d12="$(mktemp -d)"; mkdir -p "$d12/raw"
cat > "$d12/raw/nofinal.plan" <<'PLAN'
task=t
impact-risk=high
requested-budget=2
selected-count=2
selected=submimo(xiaomi/submimo),subdeepseek(deepseek/subdeepseek)
snapshot-head=abc123
leg	submimo	1	healthy
leg	subdeepseek	1	healthy
leg	subglm	0	healthy
leg	subkimi	0	off
PLAN
printf 'rc=0\nstarted=..\nfinished=..\n' > "$d12/raw/nofinal.submimo.state"
printf 'rc=0\nstarted=..\nfinished=..\n' > "$d12/raw/nofinal.subdeepseek.state"
printf 'rc=5\nstarted=..\nfinished=..\n' > "$d12/raw/nofinal.subglm.state"   # 升级追加的腿,跑了还失败了
out12="$("$ROOT/bin/panel-roster" "$d12/raw/nofinal" 2>&1)"
check "R12c: 没有 .final 时,不许断言控制器死了(它也可能还在跑)" \
  $(! grep -qE '^# escalation=unknown\(控制器没活到收尾\)$' <<<"$out12"; echo $?)
check "R12c2: 但也必须说清楚这一轮**没有**收尾记录(不许假装正常)" \
  $(grep -qE '^# escalation=.*(没有|无) \.final' <<<"$out12"; echo $?)
check "R12d: 没有 .final 时,selected 那行必须标明它是**派发前**的快照" \
  $(grep -qE '^# selected=.*派发前' <<<"$out12"; echo $?)
check "R12e: 而腿那行照旧靠 state 说真话(升级腿的失败不许隐身)" \
  $(grep -q 'subglm=FAIL(rc=5)' <<<"$out12"; echo $?)

# ---------------------------------------------------------------- R13
echo "[R13] 全 off 的**控制器路径**(R10 只测了渲染路径 —— subdeepseek F3:只堵了一半)"
d13="$(mktemp -d)"; make_fixture "$d13" 0 0
pre13="$d13/raw/alloff"
env "${common_env[@]}" "${_all_off[@]}" \
  PANEL_STATE_DIR="$d13/state" \
  bash "$d13/bin/panel-review" --no-my-review --risk standard --budget 1 \
  "$d13/task.md" "$d13/repo" "$pre13" >"$d13/ctl.out" 2>&1
rc13=$?
check "R13a: 一条腿都派不出去时,控制器**响亮地失败**(budget>=1 却 0 条 ⇒ 非零)" \
  $([[ "$rc13" -ne 0 ]]; echo $?)
check "R13b: 而且仍然留下了 plan(不是连派发都没走到就静默退出)" \
  $([[ -s "$pre13.plan" ]]; echo $?)
# 腿数**从唯一源读**,不在这里硬编码。2026-08-26 加第五条腿(subgemini)时,
# 这里原本写死 `-eq 4` ⇒ 加腿就红,而红的原因跟被测的行为无关。
# 判据里抄一份"当前有几条腿",本身就是"同一个事实存两处"。
_nlegs="$(. "$ROOT/bin/_panel-roster-lib.sh"; echo "${#PANEL_LEGS_ORDER[@]}")"
check "R13c: 也仍然写了花名册,每条腿照实印 off(共 $_nlegs 条)" \
  $([[ -s "$pre13.roster" ]] && [[ "$(grep -o '=off' "$pre13.roster" | wc -l)" -eq "$_nlegs" ]]; echo $?)

# ── R14:裁决行解析的契约 ────────────────────────────────────────────────
# 🔴 2026-08-26 实事故:第三轮四审三条腿全被记成 `verdict=UNKNOWN`,于是控制器
# 判"这轮没结论"、多派了一条腿。翻日志才发现**两条腿都下了结论**:
#   submimo 写的是 `**Conclusion: PASS**`(markdown 粗体),
#   subdeepseek 写的是 `` `Conclusion: PASS` ``(反引号包着)。
# `verdict_of` 的正则要求裁决**独占一行、前后什么都不许有**,于是把真裁决扔了。
#
# 严格是有理由的:提示词里原样含着 "Conclusion: PASS | BLOCK | NEEDS_MORE_INFO",
# 宽松匹配会把"没交卷"记成 PASS。但**加粗和反引号不是那种歧义** ——
# 那一行的内容仍然只有一个裁决值,而那个例子行里有竖线,永远不会撞上。
# ⇒ 契约钉在这里:**装饰要认,歧义不认**。
# 这条是整套系统里最贵的一个函数(花名册/健康池/升级/observation 四处用它),
# 而它在此之前**没有任何一份判据钉过它的行为**——今天之前它扔掉过多少条真裁决,
# 我查不出来了。
echo "[R14] 裁决行解析的契约:装饰要认,歧义不认"
_vd() {  # _vd <一行文本> ; 打印 verdict_of 的判定
  local f; f="$(mktemp)"; printf '%s\n' "$1" > "$f"
  ( . "$ROOT/bin/_panel-roster-lib.sh"; verdict_of "$f" ); rm -f "$f"
}
check "R14a: 裸的 'Conclusion: PASS' ⇒ PASS"            $([[ "$(_vd 'Conclusion: PASS')" == PASS ]]; echo $?)
check "R14b: markdown 粗体 '**Conclusion: PASS**' ⇒ PASS(真事故)" \
  $([[ "$(_vd '**Conclusion: PASS**')" == PASS ]]; echo $?)
check "R14c: 反引号包裹 '\`Conclusion: BLOCK\`' ⇒ BLOCK(真事故)" \
  $([[ "$(_vd '`Conclusion: BLOCK`')" == BLOCK ]]; echo $?)
check "R14d: 全角冒号 '结论:BLOCK' ⇒ BLOCK"             $([[ "$(_vd '结论:BLOCK')" == BLOCK ]]; echo $?)
check "R14e: 提示词里那行(含竖线)⇒ UNKNOWN(不许把没交卷记成 PASS)" \
  $([[ "$(_vd 'Conclusion: PASS | BLOCK | NEEDS_MORE_INFO')" == UNKNOWN ]]; echo $?)
check "R14f: 行里还有别的话 ⇒ UNKNOWN(那不是裁决,是提到了裁决)" \
  $([[ "$(_vd 'Conclusion: PASS 但我保留意见')" == UNKNOWN ]]; echo $?)
check "R14g: 正文里顺口提一句 ⇒ UNKNOWN" \
  $([[ "$(_vd 'just a mention: Conclusion: BLOCK')" == UNKNOWN ]]; echo $?)

echo
echo "---- 合计 PASS=$PASS FAIL=$FAIL ----"
[[ "$FAIL" -eq 0 ]]
