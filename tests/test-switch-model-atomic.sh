#!/usr/bin/env bash
# 验 `~/.claude/switch-model.sh` 的原子写(2026-09-01,第三轮评审 kimi F1)。
#
# 它是**仓外**文件,而且写的是业主正在用的 settings.json —— 所以这里把脚本复制一份、
# 把它写的路径全改到临时目录,再跑两个分支。**一个字节都不碰活配置**(结尾会核对)。
#
# 问四件事:
#   ① mimo 档写完之后,盘上是真 key、且**没有**残留占位符
#   ② claude 档写完之后是合法 JSON、且不含 key
#   ③ 读不到源头 key 时**拒绝写**,原文件一字未动(fail-closed)
#   ④ 不留 settings.json.XXXXXX 临时文件
set -uo pipefail

# 判卷面的不变量:跑判据的进程不许有外网出口。
# (09-01 搬进 tests/ 时才被 no-egress 判据抓到缺这行 —— 它住在 track 目录里的时候,
#  没有任何东西要求它满足判卷面的规矩,一直带着网在跑。)
. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78   # source 失败=裸跑,必须硬退
# 靶子可换,好让红检拿改动**之前**那一版跑一遍对照组(证明这道闸咬得动,不是恒真)。
SW="${SWITCH_MODEL_SH:-/root/.claude/switch-model.sh}"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
bad(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
echo "=== switch-model.sh 原子写检查 ==="

LIVE=/root/.claude/settings.json
live_before="$(md5sum "$LIVE" | cut -d' ' -f1)"

d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
sed -e "s|SETTINGS=~/.claude/settings.json|SETTINGS=$d/settings.json|" \
    -e "s|~/.bashrc|$d/bashrc|g" \
    "$SW" > "$d/sw.sh"
printf '{"env":{}}\n' > "$d/settings.json"; chmod 600 "$d/settings.json"
: > "$d/bashrc"

bash "$d/sw.sh" mimo >/dev/null 2>&1
if grep -qE 'tp-[a-z0-9]{40,60}' "$d/settings.json"; then ok "① mimo 档写进了真 key"; else bad "① mimo 档没写进 key"; fi
if grep -q '__MIMO_KEY__' "$d/settings.json"; then bad "① 盘上残留了没替换的占位符"; else ok "① 没有残留占位符"; fi
if [[ "$(stat -c %a "$d/settings.json")" == "600" ]]; then ok "① 原权限位保留(600)"; else bad "① 权限位没保留(变成 $(stat -c %a "$d/settings.json"))"; fi

bash "$d/sw.sh" claude >/dev/null 2>&1
if python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$d/settings.json" 2>/dev/null; then ok "② claude 档是合法 JSON"; else bad "② claude 档不是合法 JSON"; fi
if grep -qE 'tp-[a-z0-9]{40,60}' "$d/settings.json"; then bad "② claude 档里还带着 key"; else ok "② claude 档不含 key"; fi

# ③ 源头读不到 ⇒ 必须拒绝写。把源头路径指到一个不存在的文件。
sed -i "s|/root/.local/share/mimocode/auth.json|$d/nope.json|g" "$d/sw.sh"
cp "$d/settings.json" "$d/expect.json"
bash "$d/sw.sh" mimo >/dev/null 2>&1; rc=$?
if [[ $rc -ne 0 ]]; then ok "③ 读不到源头 key 时拒绝(rc=$rc)"; else bad "③ 读不到源头 key 居然还写了(rc=0)"; fi
if cmp -s "$d/settings.json" "$d/expect.json"; then ok "③ 被拒时 settings 一字未动"; else bad "③ 被拒时 settings **被改了** —— 不是 fail-closed"; fi

# ⑤ 结构:settings 只许由 write_settings 落盘。
# 光看"写完之后内容对不对"**证明不了原子性** —— 老那版 truncate-then-write 写完之后
# 内容也是对的,区别只在被砍的那一瞬间。所以这里直接查那条写法还在不在。
# ⚠️ 必须**跳过注释行**:脚本顶部的说明里就写着那串字面量,不跳过的话这条断言
# 永远红在自己的注释上(本仓第 N 次:误报是我自己造的)。
code_only="$(grep -v '^[[:space:]]*#' "$SW")"
if printf '%s' "$code_only" | grep -q 'cat > "$SETTINGS"'; then
  bad "⑤ 代码里还有 truncate-then-write 的写法"
else
  ok "⑤ 代码里没有 truncate-then-write 的写法了"
fi
if printf '%s' "$code_only" | grep -q 'mv -f "$tmp" "$SETTINGS"'; then
  ok "⑤ 落盘走的是同目录临时文件 + mv"
else
  bad "⑤ 找不到临时文件 + mv 那条路径"
fi

# ⑥ 动态:**替换失败时,盘上不许出现带占位符的 settings**。
# 把内存里那步 sed 换成 cat(模拟"占位符没被换掉"),守卫必须拒绝写、原文件一字未动。
SW="$SW" python3 - "$d" <<'PYEOF'
import io,os,sys
d=sys.argv[1]
s=io.open(os.environ["SW"],encoding="utf-8").read()
s=s.replace("SETTINGS=~/.claude/settings.json","SETTINGS=%s/s6.json"%d)
s=s.replace("~/.bashrc","%s/bashrc"%d)
s=s.replace('| sed "s|__MIMO_KEY__|$MIMO_KEY|" |','| cat |')
io.open("%s/sw6.sh"%d,"w",encoding="utf-8").write(s)
PYEOF
printf '{"env":{"old":true}}\n' > "$d/s6.json"
cp "$d/s6.json" "$d/s6.expect"
bash "$d/sw6.sh" mimo >/dev/null 2>&1; rc6=$?
if [[ $rc6 -ne 0 ]]; then ok "⑥ 占位符没被替换时拒绝写(rc=$rc6)"; else bad "⑥ 占位符没被替换却照写(rc=0)"; fi
if cmp -s "$d/s6.json" "$d/s6.expect"; then ok "⑥ 那一刻盘上还是旧内容(没出现带占位符的中间态)"; else bad "⑥ **盘上被写成了带占位符的样子**"; fi

n="$(find "$d" \( -name 'settings.json.*' -o -name 's6.json.*' \) | wc -l)"
if [[ "$n" -eq 0 ]]; then ok "④ 没留下临时文件"; else bad "④ 留下了 $n 个 settings.json.* 临时文件"; fi

live_after="$(md5sum "$LIVE" | cut -d' ' -f1)"
if [[ "$live_before" == "$live_after" ]]; then ok "全程没碰业主的活配置($LIVE)"; else bad "**碰了活配置** —— 这个检查自己就是事故"; fi

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
