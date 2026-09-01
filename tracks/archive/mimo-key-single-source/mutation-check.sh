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
# 夹具目录用 mktemp,不写死路径:第一版写死了**某一次会话的 scratchpad id**,
# 那个 id 随会话消失,留下的只是一条会误导下一个人的死路径。
MUT="${MUT_DIR:-$(mktemp -d)}"
trap 'rm -rf "$MUT"' EXIT
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
  cp "$REPO/bin/_mimo-key-io.sh"                  "$MUT/bin/" 2>/dev/null || true

  printf '{"xiaomi":{"type":"api","key":"%s"}}\n' "$KEY_GOOD" > "$MUT/fx/source.json"
  printf '{"models":{"providers":{"x":{"apiKey":"%s"}}}}\n'  "$KEY_GOOD" > "$MUT/fx/copy1.json"
  printf '{"api_key":"%s","api_base":"https://token-plan-cn.xiaomimimo.com/v1","model":"mimo-v2.5"}\n' "$KEY_GOOD" > "$MUT/fx/copy2.json"
  printf '{"env":{"ANTHROPIC_AUTH_TOKEN":"%s"}}\n'           "$KEY_GOOD" > "$MUT/fx/settings.json"
  printf 'export FOO=1\n'                                                > "$MUT/fx/bashrc"
  printf 'echo hi\n'                                                     > "$MUT/fx/scan/plain.sh"
  mkdir -p "$MUT/fx/scan2"; printf 'echo hi2\n'                          > "$MUT/fx/scan2/plain.sh"

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
MIMO_KEY_ENDPOINT_FIELDS=( "$MUT/fx/copy2.json|api_base|model" )
MIMO_KEY_FORBIDDEN=( "$MUT/fx/bashrc" )
MIMO_KEY_SCAN_DIRS=( "$MUT/fx" "$MUT/fx/scan2" )
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
# ⚠️ 断言的措辞改了(从"提示词里"改成"任务表里",因为扫的确实是整张表),
# 这里的靶子跟着改 —— **措辞和行号一样,都不是断言的身份**,改一处就得对一次账。
run_case "m4 cron 任务表里出现 LLM_API_KEY=" red "cron 任务表里有.*LLM_API_KEY" \
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

# ── 断线后补的五条(m11~m15):对应 09-01 自审新抓到的四个洞 ────────────────
# 它们防的都是**同一种病的另一半**:前十条问的是"坏事发生了会不会红",
# 这五条问的是"这道闸自己缩水/自己被别的失败凑出绿,会不会有人知道"。

# m11 扫描面**缩水**:清单里列了、盘上没有 ⇒ 覆盖面无声变小,而结论那句话照印
run_case "m11 扫描面缩水" red "扫描面缩水" \
  bash -c "rm -rf \"$MUT/fx/scan2\""

# m12 工具因**别的毛病**非零退出。老断言只问 `rc != 0`,这种情况会被记成
# "它拒绝了坏 key" —— 恒真断言的经典形状。
run_case "m12 工具因别的原因非零" red "不是形状拒绝的 rc=2" \
  bash -c "sed -i '0,/^DRY=/s|^DRY=|exit 64\n&|' \"$MUT/bin/rotate-mimo-key\""

# m13 cron 库里躺着**字面 key**(不是 LLM_API_KEY= 那种形状)。
# 第 10 处就是在这个库里发现的,而这个库不在⑤的扫描面里。
run_case "m13 cron 库里躺着字面 key" red "躺着字面 key" \
  bash -c "python3 -c \"
import sqlite3
c=sqlite3.connect('$MUT/fx/cron.sqlite')
c.execute(\\\"insert into cron_jobs values('j3','python3 watch.py --key $KEY_GOOD')\\\")
c.commit()\""

# m14 清单的取值路径漂了,而判据手抄的是另一份 ⇒ 必须红在**它自己**身上
run_case "m14 清单取值路径漂了" red "取值路径漂了" \
  bash -c "sed -i 's|MIMO_KEY_SOURCE_SELECTOR=\"xiaomi.key\"|MIMO_KEY_SOURCE_SELECTOR=\"xiaomi.apikey\"|' \"$MUT/bin/_mimo-key-locations.sh\""

# m15 恢复原语接受**空快照**:那会把一份好文件截成 0 字节,还一声不吭。
# 这是这一轮里唯一一条"改坏实现"的变异 —— 因为回滚路径此前根本没有任何自动覆盖。
# ⚠️ 第一版只删 bash 那道守卫,判据**仍然绿** —— 不是断言咬不动,是**原语有两道**:
# bash 的 `[[ -n "$snap" ]]` 和 python 的 `if not data`,删一道另一道照样挡住。
# 变异要证明"防线没了会不会被发现",就得把防线**整个**拿掉;只删一半等于没变异。
run_case "m15 恢复原语接受空快照" red "空快照居然被接受" \
  bash -c "sed -i -e '/拒绝恢复/d' -e '/if not data:/,+1d' \"$MUT/bin/_mimo-key-io.sh\""

# ── 第三轮补的三条(m16~m18):panel 两条腿各自命中的两处 ──────────────────

# m16 条件式副本里躺着**没被替换的占位符**。老断言 grep 不到 tp-… 就判"没有 key(合法)",
# 而那正是 switch-model.sh 写到一半被砍的样子 —— 绿着,但 mimo 档认证必败。
run_case "m16 占位符没被替换" red "没被替换的占位符" \
  bash -c "printf '{\"env\":{\"ANTHROPIC_AUTH_TOKEN\":\"__MIMO_KEY__\"}}\n' > \"$MUT/fx/settings.json\""

# m17 端点字段缺席 ⇒ watch.py 会**静默**回落到别家默认端点。
# 这是本单起因(silent-401)的同一个形状,而此前没有任何断言守着它。
run_case "m17 端点字段缺席" red "端点字段缺席" \
  bash -c "printf '{\"api_key\":\"$KEY_GOOD\"}\n' > \"$MUT/fx/copy2.json\""

# m18 key 和端点对不上:带着小米的 key 指向 OpenAI = 必定 401 的组合
run_case "m18 key 和端点对不上" red "key 和端点对不上" \
  bash -c "printf '{\"api_key\":\"$KEY_GOOD\",\"api_base\":\"https://api.openai.com/v1\",\"model\":\"gpt-4o-mini\"}\n' > \"$MUT/fx/copy2.json\""

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
