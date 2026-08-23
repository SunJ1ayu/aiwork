#!/usr/bin/env bash
# 红检:把实现**故意改坏**,看 tests/test-panel-roster.sh 咬不咬得住。
#
# 判据全绿只说明"现在没红",不说明"改坏了会红"。本机记过账的是一整族病:
# 永远绿的瞎断言、锚点过期、拿文本位置冒充代码结构。
#
# 每个变异点名**它该打红哪一条**;打不红 = 那条断言是摆设,当场报漏网。
# **锚点没命中也算漏网** —— 锚点过期本身就是问题(本机记过 4 次)。
# 结束时逐文件比 sha256,证明原样还回去了。
#
# 变异用 heredoc 喂给 python,不走 `python3 -c "..."` —— 后者的嵌套引号
# 既容易写坏,又会把注释里的反引号交给 shell 真执行(08-19 实证)。
set -uo pipefail
export ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORACLE="$ROOT/tests/test-panel-roster.sh"
TARGETS=("$ROOT/bin/panel-review" "$ROOT/bin/_panel-roster-lib.sh")

declare -A BEFORE
for f in "${TARGETS[@]}"; do BEFORE["$f"]="$(sha256sum "$f" | cut -d' ' -f1)"; done
BACKUP="$(mktemp -d)"
for f in "${TARGETS[@]}"; do cp "$f" "$BACKUP/$(basename "$f")"; done
restore() { for f in "${TARGETS[@]}"; do cp -f "$BACKUP/$(basename "$f")" "$f"; done; }
trap restore EXIT

BIT=0; MISS=0
mutate() {  # mutate <编号> <该打红的断言关键字>  (python 从 stdin 喂)
  local id="$1" target="$2" py out
  py="$(cat)"
  restore
  if ! printf '%s' "$py" | python3 - ; then
    echo "  [漏网] $id 的锚点没命中 —— **锚点过期本身就是问题**"; MISS=$((MISS+1)); restore; return
  fi
  out="$(bash "$ORACLE" 2>&1)"
  if grep -q "FAIL:.*$target" <<<"$out"; then
    echo "  [OK]   $id -> 靶子「$target」如期红了"; BIT=$((BIT+1))
  else
    echo "  [漏网] $id -> 改坏了,而「$target」还是绿的 ⇒ 那条断言是摆设"; MISS=$((MISS+1))
  fi
  restore
}

echo "== 红检开始(花名册不依赖控制器存活)=="

mutate M1 "R2: state 由" <<'PY'
import os, pathlib, sys
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
# 锚点只贴不易变的那一小段(改过两次原子写,长锚点每次都过期)
i = s.find('printf "rc=%s')
if i < 0: sys.exit(1)
j = s.index("\n", i) + 1
p.write_text(s[:i] + s[j:])
PY

mutate M2 "R1: 控制器被砍之后" <<'PY'
import os, pathlib, sys
# 方案②「控制器增量写」—— 看起来对,实际修不好:把落盘从 setsid 里挪回控制器
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
i = s.find('printf "rc=%s')
if i < 0: sys.exit(1)
j = s.index("\n", i) + 1
s = s[:i] + s[j:]
old2 = '  wait "${LEG_PID[$name]}"; rc=$?\n  LEG_RC[$name]="$rc"\n'
if s.count(old2) != 1: sys.exit(1)
p.write_text(s.replace(old2, old2 + '  printf "rc=%s\\n" "$rc" > "${LEG_LOG[$name]%.log}.state"\n', 1))
PY

mutate M3 "R3: plan 在" <<'PY'
import os, pathlib, sys
# plan 改成跑完才写(而不是派发之前)
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
i = s.index('PLAN_FILE="${LOG_PREFIX}.plan"')
j = s.index('} > "$PLAN_FILE"\n') + len('} > "$PLAN_FILE"\n')
block = s[i:j]; s = s[:i] + s[j:]
k = s.index('ROSTER_FILE="${LOG_PREFIX}.roster"')
p.write_text(s[:k] + block + s[k:])
PY

mutate M4 "R7: 印成可识别的未收尾" <<'PY'
import os, pathlib, sys
# 缺 state 读成 PASS —— 这正是这道闸存在的理由
p = pathlib.Path(os.environ["ROOT"], "bin/_panel-roster-lib.sh"); s = p.read_text()
old = "未收尾(无 state:被砍或仍在跑)"
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, "PASS(verdict=UNKNOWN)", 1))
PY

mutate M5 "R5: 控制器正常收尾" <<'PY'
import os, pathlib, sys
# 悄悄改花名册格式(verify.md 里粘的那行是下游,变了会静默污染所有历史对账)
p = pathlib.Path(os.environ["ROOT"], "bin/_panel-roster-lib.sh"); s = p.read_text()
old = '  echo "# escalation=$esc"\n'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, '  echo "# escalation-reason=$esc"\n', 1))
PY

mutate M6 "R6: 底座腿那次的 state" <<'PY'
import os, pathlib, sys
# 回落时不归档底座腿的 state ⇒ 被聊天腿覆盖,"底座腿死于 rc 几"这件事丢了
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
old = '  [[ -e "${log%.log}.state" ]] && mv -f "${log%.log}.state" "${log%.log}.agent.state"\n'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, "", 1))
PY

mutate M7 "R8: 缺共享库时走的是 fail-closed" <<'PY'
import os, pathlib, sys
# 把 fail-closed 改回裸 source(= 我第一版那个真缺陷)
p = pathlib.Path(os.environ["ROOT"], "bin/panel-review"); s = p.read_text()
needle = '. "$BIN/_panel-roster-lib.sh" || {'
if s.count(needle) != 1: sys.exit(1)
i = s.index(needle); j = s.index("}\n", i) + 2
p.write_text(s[:i] + '. "$BIN/_panel-roster-lib.sh"\n' + s[j:])
PY

mutate M8 "R4: 两次输出逐字节相同" <<'PY'
import os, pathlib, sys
# 让渲染不再是纯函数(掺进每次都变的东西)
p = pathlib.Path(os.environ["ROOT"], "bin/_panel-roster-lib.sh"); s = p.read_text()
old = '  echo "# 日志:${prefix}.*.log"\n'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, '  echo "# 日志:${prefix}.*.log($RANDOM)"\n', 1))
PY

mutate M9 "R9a: 盘上有 state 的增补腿" <<'PY'
import os, pathlib, sys
# 拿掉"盘上有 state = 它真的跑过"这条规则 ⇒ 增补腿重新隐身(评审腿 F1 那个回归)
p = pathlib.Path(os.environ["ROOT"], "bin/_panel-roster-lib.sh"); s = p.read_text()
old = '  [[ -s "$state" ]] && selected=1\n'
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, "", 1))
PY

mutate M10 "R7d: 不许断言死因" <<'PY'
import os, pathlib, sys
# 标签改回"断言它死了" = 说一句盘上证据支持不了的话
p = pathlib.Path(os.environ["ROOT"], "bin/_panel-roster-lib.sh"); s = p.read_text()
old = "未收尾(无 state:被砍或仍在跑)"
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, "KILLED(未收尾,无 state)", 1))
PY

restore
echo
for f in "${TARGETS[@]}"; do
  now="$(sha256sum "$f" | cut -d' ' -f1)"
  if [[ "$now" != "${BEFORE[$f]}" ]]; then echo "🔴 $f 没还原回去!"; MISS=$((MISS+1)); fi
done
echo "被变异的 ${#TARGETS[@]} 个文件都已原样还回(哈希一致)"
echo "== 红检结束:咬住 $BIT 条 / 漏网 $MISS 条 =="
[[ "$MISS" -eq 0 ]]
