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

declare -A BEFORE
for f in "${TARGETS[@]}"; do BEFORE["$f"]="$(sha256sum "$f" | cut -d' ' -f1)"; done
BACKUP="$(mktemp -d)"
for f in "${TARGETS[@]}"; do cp "$f" "$BACKUP/$(basename "$f")"; done
restore() { for f in "${TARGETS[@]}"; do cp -f "$BACKUP/$(basename "$f")" "$f"; done; }
cleanup() { restore; rm -f "$ORACLE"; }
trap cleanup EXIT

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
# 「计数器永远不动」—— 最朴素的坏法
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = "    streak=$((prior_streak + 1))"
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, "    streak=0"))
PY

mutate M2 "V44h: 产出过东西的腿必须还在轮换里(这条红=我把好腿踢掉了)" <<'PY'
import os, pathlib, sys
# 🔴 这一单最容易做错的坏法:把 INCOMPLETE/DEGRADED(rc=0,腿产出了东西)
# 也算成连续失败 ⇒ 把正在干活的腿踢掉。设计里专门防的就是它。
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '  if [[ "$rc" -ne 0 ]]; then\n    streak=$((prior_streak + 1))'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, '  if [[ "$status" != "PASS" ]]; then\n    streak=$((prior_streak + 1))'))
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

restore
echo "== 红检结束:咬住 $BIT,漏网 $MISS =="
for f in "${TARGETS[@]}"; do
  now="$(sha256sum "$f" | cut -d' ' -f1)"
  if [[ "$now" != "${BEFORE[$f]}" ]]; then echo "🔴 $f 没还原!"; exit 2; fi
done
echo "所有被变异的文件都逐字节还原了"
[[ "$MISS" -eq 0 ]]
