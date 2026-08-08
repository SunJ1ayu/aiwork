# shellcheck shell=bash
# runlog 收据的读取与校验逻辑 —— **唯一一份**(2026-08-08,track machine-evidence-gate)。
#
# 谁用它:
#   - `track-guard` 规矩5:提交时查 verify.md 里粘的数是不是机器写的数;
#   - `track archive`:归档**命令本身**查同一件事(守卫要守在动作发生那一刻,
#     不是它的痕迹被提交那一刻 —— G3 的教训,`archive` 会先把目录搬走)。
#
# 为什么只准有一份:同一段逻辑写两处,迟早只更新其中一个。本机为这条债记过好几笔
# (底座腿合并躯干、规矩1/4 的逃生口合并、`_tooling-paths.sh` 的名单合并)。
#
# ⚠️ 强度声明,别高估:这几条只保证「粘过来的数 = 收据文件里的数」。
# 手改一份收据文件仍然骗得过去 —— 那是**蓄意伪造**(要多改一个进了 git 的文件,
# 会出现在闸③亲读的 diff 里),不是这道闸的射程。它堵的是**顺手四舍五入**。

# 一份收据文件的「收据行」= 文件里最后一行 `runlog: …`
ev_receipt_line_of() {  # <收据文件>
  grep -a '^runlog: ' "$1" 2>/dev/null | tail -1
}

# 某 track 目录下的收据文件,字典序 = 时间序(文件名以 UTC 时间戳打头,runlog 保证)
ev_files() {  # <trackdir>
  local f
  for f in "$1"/evidence/*.txt; do
    [ -e "$f" ] || continue
    printf '%s\n' "$f"
  done
}

# verify.md 里**声称**的收据行。markdown 里怎么粘都算数:裸行、围栏代码块、
# `- \`runlog: …\`` 列表项、引用。剥掉行首的列表/引用/反引号和行尾的反引号空白,
# 剩下的必须整行以 `runlog: ` 打头 —— 剥完再比,所以「换个形状粘」绕不过去。
# 行首行尾**对称**地剥:只剥装饰(空白、列表符、引用符、反引号、强调符),
# 剥完必须整行就是收据行。四审 subdeepseek L6:第一版行尾只剥反引号和空白,
# `**\`runlog: …\`**` 这种老实粘贴反而被挡 —— 误报,而误报是这道闸的死法。
ev_claimed_lines() {  # <verify.md 路径>
  # 先剥掉编号列表的 `1. ` / `1) `,再剥其余装饰。二轮四审 subdeepseek:数字和点
  # 不在字符类里 ⇒ 老实用编号列表粘的收据行在 claimed 里是**隐形的**,
  # 归档时 5b 反过来说"你没贴" —— 又一个误报,和 L6 同根。
  sed -E 's/^[[:space:]]*[0-9]+[.)][[:space:]]*/ /' "$1" 2>/dev/null \
    | sed -n 's/^[[:space:]>*_`-]*\(runlog: .*\)$/\1/p' | sed 's/[[:space:]*_`]*$//'
}

# 主检查。问题逐条打印到 stderr;返回 0 = 干净,非 0 = 有问题。
#   ev_check <trackdir> <内容文件> <mode: always|archive> <每行前缀> [报错里显示的名字]
# 内容文件与显示名分开,是因为 pre-commit 要查的是**暂存版本**(`git show :path`),
# 而报错里该说的是那份 verify.md 的路径。
ev_check() {
  local dir="$1" src="$2" mode="$3" tag="${4:-规矩5}" v="${5:-$2}"
  local bad=0
  local claimed receipts last f line

  [ -f "$src" ] || return 0

  claimed="$(ev_claimed_lines "$src")"
  receipts=""
  last=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    line="$(ev_receipt_line_of "$f")"
    [ -n "$line" ] || continue
    receipts="${receipts}${line}"$'\n'
    last="$line"
  done <<< "$(ev_files "$dir")"

  # ---- 5a 一致性:粘过来的每一行,必须与某份收据逐字节相同 ----
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if ! printf '%s' "$receipts" | grep -qxF "$line"; then
      bad=1
      printf '%s: 🔴 5a:%s 里这一行收据在 evidence/ 里找不到一模一样的:\n' "$tag" "$v" >&2
      printf '%s:      %s\n' "$tag" "$line" >&2
      printf '%s:    (机器写的数和你粘的数对不上 —— 别改这一行,重跑 runlog 再粘)\n' "$tag" >&2
    fi
  done <<< "$claimed"

  [ "$mode" = archive ] || { [ "$bad" -eq 0 ]; return; }

  # ---- 5c 存在性:归档时一份收据都没有,就得白纸黑字说为什么 ----
  if [ -z "$last" ]; then
    if ! grep -qE '^[[:space:]]*[-*][[:space:]]*无机器证据(:|:)[[:space:]]*[^[:space:]]' "$src"; then
      bad=1
      printf '%s: 🔴 5c:%s 在归档,但这一单一份机器证据都没有。\n' "$tag" "$v" >&2
      printf '%s:    要么用 `runlog -t <track> -- <判据命令>` 跑一遍再把收据行粘进来,\n' "$tag" >&2
      printf '%s:    要么写一行「- 无机器证据:<理由>」认账(沉默不算理由)。\n' "$tag" >&2
    fi
    [ "$bad" -eq 0 ]; return
  fi

  # ---- 5b' 红的一份都不许藏 ----
  # 四审 subdeepseek M4:跑砸一遍之后补跑一条 `-- true`,最后一份就变绿了,难看的
  # 那一遍从此不用贴 —— **全程没动任何收据文件**,不属于"蓄意伪造"那条免责。
  # 红的那几遍恰恰是一单里最值钱的部分(红检、修复前后的对照),藏不得。
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in *" rc=0 "*) continue ;; esac
    if ! printf '%s\n' "$claimed" | grep -qxF "$line"; then
      bad=1
      printf '%s: 🔴 5b:%s 在归档,但这一份**跑红了**的收据没有被引用:\n' "$tag" "$v" >&2
      printf '%s:      %s\n' "$tag" "$line" >&2
      printf '%s:    (红的那几遍是这一单最值钱的部分,不许只贴好看的。)\n' "$tag" >&2
      printf '%s:    这一份如果是误跑/环境噪音:**照样贴上去,旁边写一句为什么不算数** ——\n' "$tag" >&2
      printf '%s:    删掉它才是造假,贴出来说清楚不是。\n' "$tag" >&2
    fi
  done <<< "$receipts"

  # ---- 5b 完整性:最后跑的那一遍必须被引用(不许只贴早先那份好看的)----
  if ! printf '%s\n' "$claimed" | grep -qxF "$last"; then
    bad=1
    printf '%s: 🔴 5b:%s 在归档,但**最后一份**收据没有被引用:\n' "$tag" "$v" >&2
    printf '%s:      %s\n' "$tag" "$last" >&2
    printf '%s:    (最后那一遍才是结论所依据的那一遍。它难看也要贴。)\n' "$tag" >&2
  fi

  [ "$bad" -eq 0 ]
}
