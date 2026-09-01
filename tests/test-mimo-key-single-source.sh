#!/usr/bin/env bash
# 判据:mimo key 只许有**一个源头**,其余位置要么不存在、要么由一个工具写(2026-09-01)。
#
# 出处:09-01 业主账号过期换 key。那把 key 当时抄在 **9 处**,没有任何唯一源头。
# 我手工换了一轮,**漏掉 3 处**,靠业主一句「submimo 腿一起改」才捞回来;
# 其中一处(`/root/.local/share/mimocode/auth.json`)是 submimo 的 canonical home,
# 每次派活都会把凭证**重播**进隔离树 —— 只改隔离树的话,下一次就被旧 key 覆盖回去,
# 而且不报错、只 401。
#
# 更难看的是同一趟查出的第 10 处:GitHub-Watch 那条 cron 的**提示词里内嵌了
# `export LLM_API_KEY=***`**(字面三个星号,不是真 key)。而 watch.py 的取值顺序是
# 「环境变量优先,空了才读配置文件」⇒ `***` 非空 ⇒ 它**永远读不到那份真配置**,
# 每次调 AI 都 401,而代码 `except: return ""` **静默回退**。
# 于是那份日报的 AI 摘要坏了不知道多久,没有任何东西红过。
#
# 这份判据问的三件事(都不需要外网,key 有效性不在此处判):
#   ① 源头唯一且形状对;所有**已知副本**与源头逐字节一致
#   ② **不许有游离副本** —— 扫描面里冒出清单外的 key,红
#   ③ 清单只有一份 —— 工具和判据共享 `bin/_mimo-key-locations.sh`,不许两处手抄
#
# 为什么不在这里验 key 真的能用:判卷面**不许有外网出口**(track no-egress-judging)。
# 「这把 key 小米认不认」由 `bin/rotate-mimo-key` 在换的当下验,那是运维不是判卷。
set -uo pipefail

# 判卷面的不变量:跑判据的进程不许有外网出口。
. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78   # source 失败=裸跑,必须硬退

PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCATIONS="$REPO/bin/_mimo-key-locations.sh"
ROTATE="$REPO/bin/rotate-mimo-key"

echo "=== mimo key single-source oracle ==="

# ── ① 清单文件本身 ────────────────────────────────────────────────────────
# 先问"清单在不在",因为后面每一条都靠它。清单缺席时必须硬红并停,
# 否则下面的循环会 0 次迭代、然后 FAIL=0 报绿 —— 那是假绿的经典形状。
if [[ -f "$LOCATIONS" ]]; then
  ok "清单文件存在:bin/_mimo-key-locations.sh"
else
  bad "清单文件**不存在**:$LOCATIONS(工具和判据共享的唯一一份)"
  echo "=== total: $PASS passed, $FAIL failed ==="
  exit 1
fi

# shellcheck source=/dev/null
if . "$LOCATIONS"; then
  ok "清单文件可 source"
else
  bad "清单文件 source 失败"
  echo "=== total: $PASS passed, $FAIL failed ==="
  exit 1
fi

for var in MIMO_KEY_SOURCE MIMO_KEY_COPIES MIMO_KEY_CONDITIONAL_COPIES MIMO_KEY_FORBIDDEN MIMO_KEY_SCAN_DIRS; do
  if declare -p "$var" >/dev/null 2>&1; then ok "清单定义了 $var"; else bad "清单没定义 $var"; fi
done

# ── 取源头的值 ────────────────────────────────────────────────────────────
key_shape() { [[ "$1" =~ ^tp-[a-z0-9]{40,60}$ ]]; }

SRC_KEY=""
if [[ -n "${MIMO_KEY_SOURCE:-}" && -f "${MIMO_KEY_SOURCE}" ]]; then
  ok "源头文件存在:$MIMO_KEY_SOURCE"
  SRC_KEY="$(python3 -c '
import json,sys
try:
    print(json.load(open(sys.argv[1]))["xiaomi"]["key"])
except Exception:
    pass' "$MIMO_KEY_SOURCE" 2>/dev/null)"
  if key_shape "$SRC_KEY"; then
    ok "源头里的 key 形状对(tp- + 40~60 位)"
  else
    bad "源头里取不到形状正确的 key(取到:${SRC_KEY:0:6}…,长度 ${#SRC_KEY})"
  fi
else
  bad "源头文件不存在:${MIMO_KEY_SOURCE:-<未定义>}"
fi

# ── ② 已知副本必须与源头逐字节一致 ────────────────────────────────────────
copies_checked=0
if [[ -n "$SRC_KEY" ]]; then
  for entry in "${MIMO_KEY_COPIES[@]}"; do
    IFS='|' read -r kind path selector <<< "$entry"
    [[ -f "$path" ]] || { bad "副本文件不存在:$path"; continue; }
    copies_checked=$((copies_checked+1))
    case "$kind" in
      json)
        got="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d=d[k]
print(d)' "$path" "$selector" 2>/dev/null)"
        ;;
      *) bad "清单里出现未知的副本类型:$kind($path)"; continue ;;
    esac
    if [[ "$got" == "$SRC_KEY" ]]; then
      ok "副本与源头一致:$path [$selector]"
    else
      bad "副本与源头**不一致**:$path [$selector](副本 ${got:0:9}… vs 源头 ${SRC_KEY:0:9}…)"
    fi
  done
fi
# 0 份副本 = 这段什么都没问过,不许算通过(和 hooks-installed 那条同型)
if [[ $copies_checked -eq 0 ]]; then
  bad "一份副本都没查到 —— 这段判据什么都没问,不许算通过"
fi

# ── ②b 条件式副本:**有 key 的时候**必须与源头一致 ────────────────────────
# `~/.claude/settings.json` 切到 claude 档时根本没有这个字段 —— 那是合法状态,
# 不许当红。问的是"它带的那把是不是源头那把",不是"它带没带"。
for path in "${MIMO_KEY_CONDITIONAL_COPIES[@]}"; do
  if [[ ! -f "$path" ]]; then
    ok "条件式副本不存在(合法):$path"
    continue
  fi
  found="$(grep -oE 'tp-[a-z0-9]{40,60}' "$path" 2>/dev/null | sort -u)"
  if [[ -z "$found" ]]; then
    ok "条件式副本里没有 key(合法,例如切在 claude 档):$path"
  elif [[ -z "$SRC_KEY" ]]; then
    bad "条件式副本里有 key,但源头读不出来,无法比对:$path"
  elif [[ "$(printf '%s\n' "$found" | wc -l)" -ne 1 ]]; then
    bad "条件式副本里有**多把不同的 key**:$path"
  elif [[ "$found" == "$SRC_KEY" ]]; then
    ok "条件式副本与源头一致:$path"
  else
    bad "条件式副本与源头**不一致**:$path(${found:0:9}… vs ${SRC_KEY:0:9}…)"
  fi
done

# ── ③ 明令禁止内嵌 key 的文件 ─────────────────────────────────────────────
# 这些位置的正确做法是**运行时去源头读**,不是存一份字面量。
for path in "${MIMO_KEY_FORBIDDEN[@]}"; do
  if [[ ! -e "$path" ]]; then
    ok "禁止内嵌的位置不存在(等价于没内嵌):$path"
  elif grep -qE 'tp-[a-z0-9]{40,60}' "$path" 2>/dev/null; then
    bad "**不该内嵌 key 的文件里有 key**:$path(应改成运行时读源头)"
  else
    ok "没有内嵌 key:$path"
  fi
done

# ── ④ cron 提示词里不许内嵌 LLM_API_KEY ───────────────────────────────────
# 09-01 实测:提示词里那个 `LLM_API_KEY=***` 非空,把 watch.py 的配置文件回落路径
# 整条挡死。这条断言问的是"有没有人往提示词里塞凭证变量",不是"塞的是不是真 key" ——
# 塞 `***` 造成的破坏比塞真 key 还大(真 key 至少能用)。
CRON_DB="${MIMO_KEY_CRON_DB:-/root/.openclaw/state/openclaw.sqlite}"
if [[ -f "$CRON_DB" ]]; then
  hits="$(python3 -c '
import sqlite3,sys,re
try:
    c=sqlite3.connect("file:%s?mode=ro"%sys.argv[1],uri=True)
    n=0
    for r in c.execute("select * from cron_jobs"):
        s=" ".join(str(x) for x in r)
        if re.search(r"LLM_API_KEY\s*=", s): n+=1
    print(n)
except Exception:
    print("ERR")' "$CRON_DB" 2>/dev/null)"
  case "$hits" in
    0)   ok "没有 cron 任务在提示词里内嵌 LLM_API_KEY=" ;;
    ERR) bad "读不出 cron 任务表($CRON_DB)—— 读不出就不许当通过" ;;
    *)   bad "**有 $hits 条 cron 任务的提示词里内嵌 LLM_API_KEY=**(会盖掉配置文件回落路径)" ;;
  esac
else
  bad "cron 任务库不存在:$CRON_DB(读不出就不许当通过)"
fi

# ── ⑤ 不许有游离副本 ─────────────────────────────────────────────────────
# 名单是手列的 ⇒ 新冒出一处就漏,而且漏的时候没人知道(规矩4 那条老账)。
# 这段就是把"还有没有别处藏着 key"从**我的记性**换成**机器扫一遍**。
known=()
[[ -n "${MIMO_KEY_SOURCE:-}" ]] && known+=("$MIMO_KEY_SOURCE")
for entry in "${MIMO_KEY_COPIES[@]}"; do
  IFS='|' read -r _ path _ <<< "$entry"
  known+=("$path")
done
# 条件式副本是**已知**位置,不是游离副本(上面 ②b 已经单独查过它对不对)
for path in "${MIMO_KEY_CONDITIONAL_COPIES[@]}"; do known+=("$path"); done

scan_args=()
for d in "${MIMO_KEY_SCAN_DIRS[@]}"; do [[ -e "$d" ]] && scan_args+=("$d"); done

if [[ ${#scan_args[@]} -eq 0 ]]; then
  bad "扫描面是空的 —— 这段判据什么都没扫,不许算通过"
else
  ex=()
  for pat in "${MIMO_KEY_SCAN_EXCLUDES[@]:-}"; do [[ -n "$pat" ]] && ex+=(--exclude="$pat"); done
  exd=()
  for pat in "${MIMO_KEY_SCAN_EXCLUDE_DIRS[@]:-}"; do [[ -n "$pat" ]] && exd+=(--exclude-dir="$pat"); done

  # 🔴 扫描**必须知道自己有没有跑完**:超时的 grep 输出为空,而空输出长得和
  # 「一处游离副本都没有」一模一样 —— 那就是 fail-open,是这道闸最不该有的形态。
  # 所以先把结果落到文件、单独取 grep 的 rc:124=超时 ⇒ 硬红,不许当通过。
  scan_out="$(mktemp)"
  timeout "${MIMO_KEY_SCAN_TIMEOUT:-120}" grep -rIlE 'tp-[a-z0-9]{40,60}' "${ex[@]}" "${exd[@]}" "${scan_args[@]}" > "$scan_out" 2>/dev/null
  scan_rc=$?
  if [[ $scan_rc -eq 124 ]]; then
    bad "游离副本扫描**超时**(${MIMO_KEY_SCAN_TIMEOUT:-120}s)—— 空结果和「干净」分不出来,不许当通过"
    rm -f "$scan_out"; scan_out=""
  elif [[ $scan_rc -gt 1 ]]; then
    bad "游离副本扫描异常退出(grep rc=$scan_rc)—— 不许当通过"
    rm -f "$scan_out"; scan_out=""
  fi

  strays=()
  if [[ -n "$scan_out" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    hit=0
    for k in "${known[@]}"; do [[ "$f" == "$k" ]] && { hit=1; break; }; done
    [[ $hit -eq 0 ]] && strays+=("$f")
  done < "$scan_out"
  rm -f "$scan_out"

  if [[ ${#strays[@]} -eq 0 ]]; then
    ok "扫描面里没有清单外的 key 副本(扫了 ${#scan_args[@]} 个位置)"
  else
    bad "**扫描面里有 ${#strays[@]} 处清单外的 key**:${strays[*]}"
  fi
  fi
fi

# ── ⑥ 换 key 的工具 ──────────────────────────────────────────────────────
if [[ -x "$ROTATE" ]]; then
  ok "换 key 工具存在且可执行:bin/rotate-mimo-key"
else
  bad "换 key 工具不存在/不可执行:$ROTATE"
fi

# 工具必须**用同一份清单**,不许自己再抄一遍位置。
if [[ -f "$ROTATE" ]]; then
  if grep -q '_mimo-key-locations.sh' "$ROTATE"; then
    ok "工具 source 了共享清单(位置只有一份)"
  else
    bad "工具没有 source 共享清单 —— 位置抄了第二份,清单会漂"
  fi
  # 形状不对的 key 必须被拒,且**一个字节都不许写**(fail-closed)。
  if [[ -x "$ROTATE" ]]; then
    before="$(md5sum "${MIMO_KEY_SOURCE:-/dev/null}" 2>/dev/null | cut -d' ' -f1)"
    out="$(MIMO_KEY_DRY_RUN=1 "$ROTATE" "not-a-key" 2>&1)"; rc=$?
    after="$(md5sum "${MIMO_KEY_SOURCE:-/dev/null}" 2>/dev/null | cut -d' ' -f1)"
    if [[ $rc -ne 0 ]]; then ok "工具拒绝形状不对的 key(rc=$rc)"; else bad "工具**接受**了形状不对的 key(rc=0)"; fi
    if [[ "$before" == "$after" ]]; then ok "被拒时源头文件没被动过"; else bad "被拒时源头文件**被改了** —— 不是 fail-closed"; fi
  fi
fi

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
