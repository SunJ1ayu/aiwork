#!/usr/bin/env bash
# 红检:把「连续失败停止轮换」的实现故意改坏,看 V44 咬不咬得住。
#
# 判据全绿只说明"现在没红",不说明"改坏了会红"。本机记过账的一整族病:
# 永远绿的瞎断言、锚点过期、靶子名过期(靶子打偏的表现和"断言是摆设"一模一样)。
#
# 每个变异点名**它该打红哪一条**;打不红 = 那条断言是摆设,当场报漏网。
# 变异一律用 heredoc 喂 python,不走 `python3 -c "..."`(嵌套引号会把注释里的
# 反引号交给 shell 真执行 —— 2026-08-19 实证)。
#
# 🔴 只跑 V44 那一段,不跑全量:全量一遍要好几分钟,6 个变异就是半小时,
#    而慢到没人跑的红检等于没有红检。
set -uo pipefail
export ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUITE="$ROOT/tests/test-review-tooling.sh"
TARGETS=("$ROOT/bin/panel-review")

# 只跑 V44 的临时运行器。必须**放在 tests/ 里** —— 套件用 BASH_SOURCE 的目录
# 去 source `_no-egress.sh`(判据进程不许有外网出口),放别处会 exit 78 裸退。
ORACLE="$ROOT/tests/.mutation-v44-runner.tmp.sh"
build_runner() {
  local last
  last="$(grep -n '^v0_parent_panel_env_is_scrubbed$' "$SUITE" | head -1 | cut -d: -f1)"
  [[ -n "$last" ]] || { echo "红检自己坏了:找不到注册区起点"; exit 2; }
  { sed -n "1,$((last-1))p" "$SUITE"
    echo 'v44_dead_leg_stops_rotating'
    echo 'echo "=== total: $PASS passed, $FAIL failed ==="'
    echo '[[ $FAIL -eq 0 ]]'
  } > "$ORACLE"
}

mutation_dead_leg_cleanup() { rm -f "$ORACLE"; }
MUTATION_GUARD_ON_FINISH=mutation_dead_leg_cleanup
. "$ROOT/tests/_mutation-guard.sh" || exit 2
mutation_guard_start "dead-leg-streak"

build_runner
BIT=0; MISS=0
BASELINE="$(bash "$ORACLE" 2>&1)"
if grep -q "FAIL:" <<<"$BASELINE"; then
  echo "🔴 基线就不是全绿 —— 先把判据弄绿再红检"; grep "FAIL:" <<<"$BASELINE"; exit 2
fi

mutate() {  # mutate <编号> <该打红的断言关键字>   (python 从 stdin 喂)
  local id="$1" target="$2" py out
  py="$(cat)"
  # 一律 grep -F(字面):断言名里有 `**` 这种 markdown 星号,当正则会静默匹配不上,
  # 于是一条**真咬住了**的变异被报成漏网(2026-08-23 撞过)。
  if ! grep "PASS:" <<<"$BASELINE" | grep -qF -- "$target"; then
    echo "  [漏网] $id 的靶子「$target」在基线里压根不是一条断言 —— **靶子名过期**"
    MISS=$((MISS+1)); return
  fi
  restore
  if ! printf '%s' "$py" | python3 - ; then
    echo "  [漏网] $id 的锚点没命中 —— **锚点过期本身就是问题**"; MISS=$((MISS+1)); restore; return
  fi
  out="$(bash "$ORACLE" 2>&1)"
  if grep "FAIL:" <<<"$out" | grep -qF -- "$target"; then
    echo "  [OK]   $id -> 靶子「$target」如期红了"; BIT=$((BIT+1))
  else
    echo "  [漏网] $id -> 改坏了,而「$target」还是绿的 ⇒ 那条断言是摆设"; MISS=$((MISS+1))
  fi
  restore
}

echo "== 红检开始(连续硬失败的腿停止轮换)=="

mutate M1 "V44a: 一轮硬失败之后 health.tsv 里有 streak 列且=1" <<'PY'
import os, pathlib, sys
# 「计数器永远不动」—— 最朴素的坏法。
# 锚点 2026-08-25 换过一次:加"跨冷却窗口才计数"之后,原来那行 `streak=$((prior_streak + 1))`
# 的缩进和位置都变了 ⇒ 红检自己报了「锚点过期」。**锚点过期本身就是问题**,不是噪音。
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '      first="$now"; streak=1'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, '      first="$now"; streak=0'))
PY

mutate M2 "V44h: 产出过东西的腿必须还在轮换里(这条红=我把好腿踢掉了)" <<'PY'
import os, pathlib, sys
# 🔴 这一单最容易做错的坏法:把 INCOMPLETE/DEGRADED(rc=0,腿产出了东西)
# 也算成连续失败 ⇒ 把正在干活的腿踢掉。设计里专门防的就是它。
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '  if [[ "$rc" -ne 0 ]]; then\n    if [[ "$prior_first" =~ ^[0-9]+$'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, '  if [[ "$status" != "PASS" ]]; then\n    if [[ "$prior_first" =~ ^[0-9]+$'))
PY

mutate M3 "V44c: 连续 3 轮失败之后不许再轮换到它(冷却已归零仍不许)" <<'PY'
import os, pathlib, sys
# 「dead 也受冷却管」—— 看起来很合理,实际等于什么都没修:冷却一过它照样复活,
# 而那正是 subkimi 循环 6 天的原因。
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '  (( streak >= HEALTH_DEAD_STREAK )) || return 1'
if s.count(old) != 1: sys.exit(1)
new = ('  local _at _now\n'
       '  _at="$(printf \'%s\' "$row" | cut -f3)"; _now="$(date +%s)"\n'
       '  [[ "$_at" =~ ^[0-9]+$ ]] && (( _now - _at < HEALTH_COOLDOWN )) || return 1\n'
       + old)
p.write_text(s.replace(old, new))
PY

mutate M4 "V44f: 提示里给出怎么把它放回来(不留死胡同)" <<'PY'
import os, pathlib, sys
# 「退化成又一句普通提示」—— 正是这一单要治的病:说了但没人能据此行动
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '    echo "     处理完强行放回:PANEL_HEALTH_OVERRIDE=$_leg=healthy(跑成功一次 streak 自动清零)"\n'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, ""))
PY

mutate M5 "V44j: 老三列 health.tsv 照跑不崩(缺第 4 列当 0)" <<'PY'
import os, pathlib, sys
# 「缺第 4 列当成已经死透」—— 格式升级最经典的坏法:老数据被新逻辑误判
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '  [[ "$streak" =~ ^[0-9]+$ ]] || return 1'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, '  [[ "$streak" =~ ^[0-9]+$ ]] || streak=999'))
PY

mutate M6 "V44k: PANEL_HEALTH_DEAD_STREAK=0 时机制整个关掉" <<'PY'
import os, pathlib, sys
# 「关不掉的开关」—— 写了参数、却不生效
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '[[ "$HEALTH_DEAD_STREAK" =~ ^[0-9]+$ && "$HEALTH_DEAD_STREAK" -gt 0 ]] || return 1'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, '[[ "$HEALTH_DEAD_STREAK" =~ ^[0-9]+$ ]] || return 1'))
PY

mutate M7 "V44l: 一次硬失败之后,冷却窗口内不许再派它(冷却没死)" <<'PY'
import os, pathlib, sys
# 回到那个真出过事的写法:`read` 把多余字段连分隔符塞进最后一个变量 ⇒ 冷却整个失效。
# 这条变异存在的意义:那个 bug 曾经**461 条判据全绿**地躺在树上。
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = "  status=\"$(printf '%s' \"$row\" | cut -f2)\"\n  at=\"$(printf '%s' \"$row\" | cut -f3)\""
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, "  IFS=$'\\t' read -r _ status at <<< \"$row\""))
PY

mutate M8 "V44o: PANEL_HEALTH_DEAD_STREAK=08 必须拒跑(fail-closed),不许静默失效" <<'PY'
import os, pathlib, sys
# 「安全旋钮的垃圾值静默失效」—— 我以为开着,其实关着
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
i = s.find('if [[ ! "$HEALTH_DEAD_STREAK" =~ ')
if i < 0: sys.exit(1)
j = s.index("\nfi\n", i) + 4
p.write_text(s[:i] + s[j:])
PY

mutate M9 "V44p: --all 照派,但那行「连续几轮」的提示照打" <<'PY'
import os, pathlib, sys
# 「加了一道防线却没接进主路」:dead 分支排到 SELECTED 后面 ⇒ --all 永远到不了
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '  if [[ -n "$(dead_health "$_leg" 2>/dev/null || true)" && "${LEG_HEALTH[$_leg]}" != "off" ]]; then'
if s.count(old) != 1: sys.exit(1)
new = '  if [[ "${LEG_SELECTED[$_leg]}" -eq 1 ]]; then\n    echo "  $_leg -> ${LEG_LOG[$_leg]}"\n  el' + old.lstrip()
p.write_text(s.replace(old, new))
PY

mutate M10 "V44n: dead 提示指的日志必须真的存在(不是本轮那个永远不会产生的)" <<'PY'
import os, pathlib, sys
# 「报警在"去哪看"这一格是断的」:不记上一轮日志 ⇒ 提示只能指向本轮那个不存在的文件
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '    lastlog="$log"'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, '    lastlog=""'))
PY

mutate M11 "V44r: 一个冷却窗口内的连发失败只算一次(--all 不许压缩掉定阈前提)" <<'PY'
import os, pathlib, sys
# 回到第二轮 subdeepseek F1 那个真缺口:对**任何**被派发的失败无条件 +1
# ⇒ --all 三连发在一秒内把 streak 顶到阈值,几分钟的共模抖动就能永久踢掉好腿。
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '      if (( now - first >= prior_streak * _cd )); then streak=$((prior_streak + 1))\n      else streak="$prior_streak"; fi'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, '      streak=$((prior_streak + 1))'))
PY

mutate M12 "V44s: 跨过冷却窗口的失败照样累计(修法不许是「干脆永远不计数」)" <<'PY'
import os, pathlib, sys
# 上一条的镜像:把"守住冷却窗口"修成"永远不再计数" —— 机制被整个关掉,
# 而只看 V44r 的话它是绿的。对照组存在的全部意义就是咬住这一种"修法"。
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '      if (( now - first >= prior_streak * _cd )); then streak=$((prior_streak + 1))\n      else streak="$prior_streak"; fi'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, '      streak="$prior_streak"'))
PY

mutate M13 "V44u: 派不满风险预算时说出这件事本身(不是只有一行数字)" <<'PY'
import os, pathlib, sys
# 「缺口只剩一行数字」:把那段响亮的话删掉,退回三方独立命中的那个静默。
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
i = s.find('if [[ "$SELECTED_COUNT" -lt "$RISK_BUDGET" ]]; then')
if i < 0: sys.exit(1)
tail = "\n  unset _missing _leg\nfi\n"
j = s.index(tail, i) + len(tail)
p.write_text(s[:i] + s[j:])
PY

mutate M14 "V44w: override 生效那一轮,提示改口(不再叫人去做已经做过的事)" <<'PY'
import os, pathlib, sys
# 「你处理完了它还在响」:去掉改口分支,又回到叫人去做他刚做完的那件事。
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '    case "${_health,,}" in healthy|pass|up|ok) LEG_OVERRIDE_OK[$_leg]=1 ;; *) LEG_HEALTH[$_leg]="$_health" ;; esac'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, '    case "${_health,,}" in healthy|pass|up|ok) : ;; *) LEG_HEALTH[$_leg]="$_health" ;; esac'))
PY

mutate M15 "V44c: 连续 3 轮失败之后不许再轮换到它(冷却已归零仍不许)" <<'PY'
import os, pathlib, sys
# 第二轮 subdeepseek F4 点名的红检缺口:M1-M10 谁都没变异过**选腿循环那道健康闸本身**。
# 把普通轮次里"非 healthy 就跳过"的 continue 删掉 ⇒ 死腿照样被派。
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '  if [[ "$FORCE_ALL" -ne 1 && "${LEG_HEALTH[$_leg]}" != "healthy" ]]; then continue; fi'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, '  :'))
PY

restore
echo "== 红检结束:咬住 $BIT,漏网 $MISS =="
for f in "${TARGETS[@]}"; do
  now="$(sha256sum "$f" | cut -d' ' -f1)"
  if [[ "$now" != "${BEFORE[$f]}" ]]; then echo "🔴 $f 没还原!"; exit 2; fi
done
echo "所有被变异的文件都逐字节还原了"
[[ "$MISS" -eq 0 ]]
