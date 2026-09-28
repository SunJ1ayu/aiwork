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

for var in MIMO_KEY_SOURCE MIMO_KEY_COPIES MIMO_KEY_CONDITIONAL_COPIES MIMO_KEY_ENDPOINT_FIELDS MIMO_KEY_FORBIDDEN MIMO_KEY_SCAN_DIRS; do
  if declare -p "$var" >/dev/null 2>&1; then ok "清单定义了 $var"; else bad "清单没定义 $var"; fi
done

# ── 取源头的值 ────────────────────────────────────────────────────────────
key_shape() { [[ "$1" =~ ^tp-[a-z0-9]{40,60}$ ]]; }

# 判据**刻意不调**清单里的 mimo_key_read_source():判据依赖被测实现的 helper,
# helper 自己坏了就没人看得见。代价是取值路径在这里手抄了第二份 ——
# 所以把这份手抄**钉在清单上**,漂了红在它自己身上,而不是红在"副本不一致"那种
# 指错方向的地方(本单要治的病就是"抄了第二份没人对账")。
if [[ "${MIMO_KEY_SOURCE_SELECTOR:-}" == "xiaomi.key" ]]; then
  ok "清单的取值路径和判据手抄的那份一致(xiaomi.key)"
else
  bad "清单取值路径漂了:清单写 ${MIMO_KEY_SOURCE_SELECTOR:-<空>},判据手抄的是 xiaomi.key"
fi

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
  # 🔴 "没有 key"和"key 还没被写进去"长得一样,但只有前者合法。
  # `switch-model.sh` 先 heredoc 写占位符、再 sed 换成真 key ——
  # 砍在这两步中间,盘上就躺着字面 `__MIMO_KEY__`:grep 找不到 tp-…,
  # 老断言判"没有 key(合法)"⇒ **绿**,而 mimo 档的认证必败。
  if grep -q '__MIMO_KEY__' "$path" 2>/dev/null; then
    bad "条件式副本里躺着**没被替换的占位符**:$path(写到一半被砍的样子,不是「没有 key」)"
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
    0)   ok "cron 任务表里没有 LLM_API_KEY=" ;;
    ERR) bad "读不出 cron 任务表($CRON_DB)—— 读不出就不许当通过" ;;
    *)   bad "**cron 任务表里有 $hits 行出现 LLM_API_KEY=**(扫的是整张表,含 last_error/job_json 等历史列;先去看是哪一行再下结论)" ;;
  esac
else
  bad "cron 任务库不存在:$CRON_DB(读不出就不许当通过)"
fi

# ── ④b cron 库里也不许躺着**字面 key** ────────────────────────────────────
# ④ 只问了"有没有人往提示词里塞 LLM_API_KEY=",那是 09-01 那次的具体形状。
# 但第 10 处正是在这个 sqlite 里发现的,而这个库**不在⑤的扫描面里**(它是二进制库,
# 不是配置文件)⇒ 今天谁把一把真 `tp-…` 粘进任何一条 cron 提示词,④不红、⑤也不红。
# 这条补的就是那个夹缝。
if [[ -f "$CRON_DB" ]]; then
  khits="$(python3 -c '
import sqlite3,sys,re
try:
    c=sqlite3.connect("file:%s?mode=ro"%sys.argv[1],uri=True)
    n=0
    for r in c.execute("select * from cron_jobs"):
        s=" ".join(str(x) for x in r)
        if re.search(r"tp-[a-z0-9]{40,60}", s): n+=1
    print(n)
except Exception:
    print("ERR")' "$CRON_DB" 2>/dev/null)"
  case "$khits" in
    0)   ok "cron 任务表里没有字面 key" ;;
    ERR) bad "读不出 cron 任务表($CRON_DB)—— 读不出就不许当通过" ;;
    *)   bad "**cron 任务表里有 $khits 行躺着字面 key**(库不在扫描面里,只有这条查得到;扫的是整张表)" ;;
  esac
fi

# ── ④c 决定"这把 key 打到哪去"的字段不许缺席 ──────────────────────────────
# 见清单里 MIMO_KEY_ENDPOINT_FIELDS 那段的理由:key 对了但被送错地方,
# 和 key 错了一样是 401,区别只在于**没有任何东西会红**。
for entry in "${MIMO_KEY_ENDPOINT_FIELDS[@]:-}"; do
  [[ -n "$entry" ]] || continue
  IFS='|' read -r epath f1 f2 <<< "$entry"
  if [[ ! -f "$epath" ]]; then
    bad "端点配置文件不存在:$epath"
    continue
  fi
  vals="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print("\t".join(str(d.get(k,"")) for k in sys.argv[2:]))
print(str(d.get("api_key","")))' "$epath" "$f1" "$f2" 2>/dev/null)"
  IFS=$'\t' read -r v1 v2 <<< "$(printf '%s' "$vals" | head -1)"
  akey="$(printf '%s' "$vals" | sed -n '2p')"
  if [[ -z "$v1" || -z "$v2" ]]; then
    bad "**端点字段缺席**:$epath 的 $f1/$f2 至少有一个空 —— 它会**静默**回落到别家默认端点"
  elif [[ "$akey" == tp-* && "$v1" == *api.openai.com* ]]; then
    bad "**key 和端点对不上**:$epath 带的是小米的 key,却指向 $v1 —— 那是必定 401 的组合"
  else
    ok "端点字段齐备且和 key 对得上:$epath [$f1=$v1 $f2=$v2]"
  fi
done

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

scan_args=(); scan_missing=()
for d in "${MIMO_KEY_SCAN_DIRS[@]}"; do
  if [[ -e "$d" ]]; then scan_args+=("$d"); else scan_missing+=("$d"); fi
done

# 🔴 **扫描面缩水必须响。** 逐项丢弃"盘上没有"的位置,等于覆盖面无声变小,
# 而下面那句结论还大大方方印着"扫了 N 个位置" —— 11 变 10 没有任何人会去比那个数。
# 我在⑤里防了清单**漏列**,却没防清单**指空**:同一种病的另一半。
if [[ ${#scan_missing[@]} -eq 0 ]]; then
  ok "扫描面完整:清单里 ${#MIMO_KEY_SCAN_DIRS[@]} 个位置都在盘上"
else
  bad "**扫描面缩水了 ${#scan_missing[@]} 处**(清单里有、盘上没有):${scan_missing[*]}"
fi

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
    # 🔴 钉死 **rc=2**(工具给"形状不对"留的专用码),不许只问"非零"。
    # 「非零就算拒绝成功」近似恒真:清单读不到(rc=64)、脚本语法错、工具被换成
    # `exit 1` 的空壳 —— 统统会被记成"它拒绝了坏 key"。那是"匹配到别处"换了个马甲。
    # 再钉一条理由:输出里得说得出"形状",否则它可能是因为**别的毛病**才非零的。
    if [[ $rc -eq 2 ]] && grep -q '形状不对' <<< "$out"; then
      ok "工具用专用码拒绝形状不对的 key(rc=2,且理由是形状)"
    elif [[ $rc -eq 0 ]]; then
      bad "工具**接受**了形状不对的 key(rc=0)"
    elif [[ $rc -eq 2 ]]; then
      bad "rc=2 对,但输出里没说「形状不对」—— 可能是拿别的失败凑出的 2"
    else
      bad "工具非零退出,但**不是形状拒绝的 rc=2**(拿到 rc=$rc)—— 更像它自己坏了"
    fi
    if [[ "$before" == "$after" ]]; then ok "被拒时源头文件没被动过"; else bad "被拒时源头文件**被改了** —— 不是 fail-closed"; fi
  fi
fi

# ── ⑦ 写/恢复的原语必须单独成文件,并且**恢复路径也得是原子的** ──────────
# 由来(自审抓到的):前进路径专门做了临时文件+fsync+replace,理由白纸黑字写着
# 「断线是常态,截断的 JSON 比垃圾备份坏得多」;而**回滚**当时用的是
# `printf … | base64 -d > "$f"` —— 正是它要避免的 truncate-then-write。
# 回滚是**恢复**路径,断在这里比断在前进路径更难看。
# 而且这条路径当时**没有任何自动覆盖**:dry-run 跳过写、真跑要联网+网关+cron,
# 判卷面又不许有外网出口 ⇒ 它永远测不到。把原语拆出来,就能在 /tmp 上单独跑一遍。
IO="$REPO/bin/_mimo-key-io.sh"
if [[ ! -f "$IO" ]]; then
  bad "写/恢复原语没有单独成文件:$IO(回滚路径就没法在不联网的情况下被测)"
else
  ok "写/恢复原语单独成文件:bin/_mimo-key-io.sh"
  iodir="$(mktemp -d)"
  (
    set +e
    # shellcheck source=/dev/null
    . "$IO" || exit 90
    f="$iodir/t.json"
    printf '{"a":{"b":"OLD"},"keep":"是"}\n' > "$f"
    chmod 600 "$f"
    before="$(md5sum "$f" | cut -d' ' -f1)"

    mimo_key_write_json "$f" "a.b" "NEW" || exit 91
    [[ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["a"]["b"])' "$f")" == "NEW" ]] || exit 92
    after="$(md5sum "$f" | cut -d' ' -f1)"
    [[ "$after" != "$before" ]] || exit 92      # 写了却一字没变 = 没写
    [[ "$(stat -c %a "$f")" == "600" ]] || exit 93
    [[ -z "$(find "$iodir" -name '.rotate-*' -print -quit)" ]] || exit 94

    # 快照 → 改坏 → 恢复,必须**逐字节回到快照那一刻**。
    # ⚠️ 第一版我把期望写成了紧凑 JSON 字面量,而写出来的是 indent=2 的多行 —— 红的是
    # **我的期望值**,不是实现。先查量具再改实现,这次量具坏在我手里。
    snap="$(mimo_key_snapshot "$f")" || exit 95
    printf 'garbage' > "$f"
    mimo_key_restore "$f" "$snap" || exit 96
    [[ "$(md5sum "$f" | cut -d' ' -f1)" == "$after" ]] || exit 97

    # 🔴 空快照必须**拒绝恢复**:snapshot 读失败时给空串,而
    # `> "$f"` 会先截断 —— 那会把一份好文件写成 0 字节,还一声不吭。
    keepmd5="$(md5sum "$f" | cut -d' ' -f1)"
    mimo_key_restore "$f" "" 2>/dev/null && exit 98   # 它拒绝时的抱怨不必印进收据
    [[ "$(md5sum "$f" | cut -d' ' -f1)" == "$keepmd5" ]] || exit 99
    exit 0
  )
  iorc=$?
  rm -rf "$iodir"
  case "$iorc" in
    0)  ok "写/恢复原语:原子写 + 权限保留 + 恢复逐字节 + 空快照拒绝恢复(全过)" ;;
    90) bad "写/恢复原语 source 失败:$IO" ;;
    91|92) bad "写/恢复原语:写进去的值不对(rc=$iorc)" ;;
    93) bad "写/恢复原语:**权限位没保留**(600 的凭证被写成别的)" ;;
    94) bad "写/恢复原语:留下了 .rotate-* 临时文件" ;;
    95|96) bad "写/恢复原语:快照/恢复自己失败(rc=$iorc)" ;;
    97) bad "写/恢复原语:**恢复出来的内容和原样不一致**" ;;
    98) bad "写/恢复原语:**空快照居然被接受**了 —— 那会把好文件截成 0 字节" ;;
    99) bad "写/恢复原语:拒绝了空快照,但**文件已经被动过**(不是 fail-closed)" ;;
    *)  bad "写/恢复原语:未预期的 rc=$iorc" ;;
  esac
fi

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
