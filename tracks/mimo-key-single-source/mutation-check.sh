#!/usr/bin/env bash
# 变异测试:证明 tests/test-mimo-key-single-source.sh **咬得动**(2026-09-01)。
#
# 为什么不能只看它绿:绿的判据什么也没证明。本仓踩过好几次「断言恒真 / 匹配到别处 /
# 前置太弱,旧实现照样绿」—— 判据必须先被证明会红,红的位置还得对。
#
# 做法:把判据、清单、工具全复制到仓外夹具目录,让清单指向**夹具文件**而不是本机真配置,
# 这样每种破坏都能安全地造出来,不碰业主的活配置。
# 每条变异都声明"期望红在哪句话上" —— 只红不问红在哪,等于没红检(08-04「红在 TypeError
# 上等于没红检过」那笔账)。
#
# 两条**对照组**是刻意的:m0(不变异必须全绿)和 m6(合法状态不许被判红)。
# 误报和假绿一样坏 —— 带误报的闸会逼出绕开它的习惯。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MUT="${MUT_DIR:-/tmp/claude-0/-root/54dc85e2-a141-47df-b226-9e40554f26c7/scratchpad/mut}"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

KEY_GOOD="tp-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
KEY_OTHER="tp-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

build_fixture() {
  rm -rf "$MUT"; mkdir -p "$MUT/bin" "$MUT/tests" "$MUT/fx/scan"
  cp "$REPO/tests/test-mimo-key-single-source.sh" "$MUT/tests/"
  cp "$REPO/tests/_no-egress.sh"                  "$MUT/tests/"
  cp "$REPO/bin/rotate-mimo-key"                  "$MUT/bin/"

  printf '{"xiaomi":{"type":"api","key":"%s"}}\n' "$KEY_GOOD" > "$MUT/fx/source.json"
  printf '{"models":{"providers":{"x":{"apiKey":"%s"}}}}\n'  "$KEY_GOOD" > "$MUT/fx/copy1.json"
  printf '{"api_key":"%s"}\n'                                "$KEY_GOOD" > "$MUT/fx/copy2.json"
  printf '{"env":{"ANTHROPIC_AUTH_TOKEN":"%s"}}\n'           "$KEY_GOOD" > "$MUT/fx/settings.json"
  printf 'export FOO=1\n'                                                > "$MUT/fx/bashrc"
  printf 'echo hi\n'                                                     > "$MUT/fx/scan/plain.sh"

  # 空的 cron 库(没有任何 LLM_API_KEY= 的任务)
  python3 - "$MUT/fx/cron.sqlite" <<'PY'
import sqlite3,sys
c=sqlite3.connect(sys.argv[1])
c.execute("create table cron_jobs(id text, payload text)")
c.execute("insert into cron_jobs values('j1','python3 watch.py check')")
c.commit()
PY

  cat > "$MUT/bin/_mimo-key-locations.sh" <<EOF
MIMO_KEY_SOURCE="$MUT/fx/source.json"
MIMO_KEY_SOURCE_SELECTOR="xiaomi.key"
MIMO_KEY_COPIES=(
  "json|$MUT/fx/copy1.json|models.providers.x.apiKey"
  "json|$MUT/fx/copy2.json|api_key"
)
MIMO_KEY_CONDITIONAL_COPIES=( "$MUT/fx/settings.json" )
MIMO_KEY_FORBIDDEN=( "$MUT/fx/bashrc" )
MIMO_KEY_SCAN_DIRS=( "$MUT/fx" )
MIMO_KEY_SCAN_EXCLUDES=( "*.log" )
MIMO_KEY_SCAN_EXCLUDE_DIRS=( ".git" )
mimo_key_shape_ok() { [[ "\${1:-}" =~ ^tp-[a-z0-9]{40,60}\$ ]]; }
mimo_key_read_source() {
  python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));[d:=d[k] for k in sys.argv[2].split(".")];print(d)' "\$MIMO_KEY_SOURCE" "\$MIMO_KEY_SOURCE_SELECTOR" 2>/dev/null
}
EOF
}

# run_case <名字> <期望:green|red> <红时必须出现的正则> <变异命令...>
run_case() {
  local name="$1" expect="$2" needle="$3"; shift 3
  build_fixture
  "$@" >/dev/null 2>&1
  local out rc
  out="$(MIMO_KEY_CRON_DB="$MUT/fx/cron.sqlite" bash "$MUT/tests/test-mimo-key-single-source.sh" 2>&1)"; rc=$?
  if [[ "$expect" == "green" ]]; then
    if [[ $rc -eq 0 ]]; then ok "$name:未变异/合法状态 → 绿(没有误报)"
    else bad "$name:**误报** —— 合法状态被判红:$(grep 'FAIL:' <<< "$out" | head -2 | tr '\n' ' ')"; fi
    return
  fi
  if [[ $rc -eq 0 ]]; then
    bad "$name:变异后判据**仍然绿** —— 这条断言咬不动"
  elif grep -qE "$needle" <<< "$out"; then
    ok "$name:红了,且红在该红的地方($needle)"
  else
    bad "$name:红了但**红错了地方** —— 期望 /$needle/,实际:$(grep 'FAIL:' <<< "$out" | head -2 | tr '\n' ' ')"
  fi
}

echo "=== mimo-key 判据 变异测试 ==="

# m0 对照组:不动任何东西必须全绿(证明夹具本身是好的,后面的红不是夹具坏了造出来的)
run_case "m0 对照组" green "" true

# m1 副本漂了
run_case "m1 副本与源头不一致" red "副本与源头.*不一致" \
  bash -c "printf '{\"api_key\":\"$KEY_OTHER\"}\n' > \"$MUT/fx/copy2.json\""

# m2 禁止内嵌的文件里被塞了 key
run_case "m2 禁止内嵌处出现 key" red "不该内嵌 key 的文件里有 key" \
  bash -c "printf 'export T=\"$KEY_GOOD\"\n' >> \"$MUT/fx/bashrc\""

# m3 扫描面里冒出清单外的副本(这条就是"名单会腐烂"的解药,必须咬得动)
run_case "m3 冒出清单外的游离副本" red "清单外的 key" \
  bash -c "printf 'k=$KEY_GOOD\n' > \"$MUT/fx/scan/newthing.conf\""

# m4 cron 提示词里内嵌 LLM_API_KEY=
run_case "m4 cron 提示词内嵌 LLM_API_KEY" red "内嵌 LLM_API_KEY" \
  bash -c "python3 -c \"
import sqlite3,sys
c=sqlite3.connect('$MUT/fx/cron.sqlite')
c.execute(\\\"insert into cron_jobs values('j2','export LLM_API_KEY=*** && python3 watch.py')\\\")
c.commit()\""

# m5 条件式副本带的是另一把 key
run_case "m5 settings 里的 key 与源头不同" red "条件式副本与源头.*不一致" \
  bash -c "printf '{\"env\":{\"ANTHROPIC_AUTH_TOKEN\":\"$KEY_OTHER\"}}\n' > \"$MUT/fx/settings.json\""

# m6 对照组:切在 claude 档(settings 里没有 key)是**合法**的,不许判红
run_case "m6 对照组:settings 无 key" green "" \
  bash -c "printf '{\"env\":{}}\n' > \"$MUT/fx/settings.json\""

# m7 源头里的 key 形状不对
run_case "m7 源头 key 形状不对" red "形状" \
  bash -c "printf '{\"xiaomi\":{\"key\":\"garbage\"}}\n' > \"$MUT/fx/source.json\""

# m8 工具自己抄了第二份位置清单(不 source 共享的那份)
run_case "m8 工具不 source 共享清单" red "没有 source 共享清单" \
  bash -c "sed -i 's|_mimo-key-locations.sh|_other-list.sh|g' \"$MUT/bin/rotate-mimo-key\""

# m9 工具接受形状不对的 key(fail-closed 塌了)
run_case "m9 工具接受坏 key" red "接受.*形状不对" \
  bash -c "sed -i 's|^mimo_key_shape_ok \"\$NEW_KEY\" .*|true|' \"$MUT/bin/rotate-mimo-key\""

# m10 新补(自审修完 fail-open 之后加的):扫描**超时**必须硬红。
# 不加这条,那段修复就只有我的说法、没有机器证明 —— 而它修的正是"空结果被当成干净"。
# ⚠️ 用 0.001 不用 0:coreutils 里 `timeout 0` 是**取消超时**,第一版我写的 0,
# m10 当场"没红" —— 那一红是**我的量具坏了**,不是实现有洞。先查量具再改实现。
build_fixture
out="$(MIMO_KEY_CRON_DB="$MUT/fx/cron.sqlite" MIMO_KEY_SCAN_TIMEOUT=0.001 bash "$MUT/tests/test-mimo-key-single-source.sh" 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && grep -q "扫描\*\*超时\*\*" <<< "$out"; then
  ok "m10 扫描超时:红了,且红在该红的地方(不是把空结果当干净)"
else
  bad "m10 扫描超时:**没红或红错地方**(rc=$rc)—— fail-open 还在"
fi

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
