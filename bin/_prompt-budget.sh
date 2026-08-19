# 提示词能有多大,由**它怎么传给底座**决定 —— 不由一个拍脑袋的常数决定。
# (2026-08-19,track deepseek-leg-bash-hole。sourced 库,别直接执行。)
#
# ── 为什么有这个文件:两起实事故,同一个根 ──────────────────────────────
#
# ① E2BIG(本 track 自己的四审跑出来的):opencode 腿和 kimi 腿双双 rc=126,
#    日志里只有一句 `/usr/bin/timeout: Argument list too long`。
#    这两条腿把**整个提示词当一个 argv 参数**传(opencode 是位置参数、kimi 是
#    `-p <prompt>`),而 Linux 对**单个参数**的硬上限是
#    MAX_ARG_STRLEN = 32 × PAGE_SIZE = 131072 字节。那天的 diff 是 132061 字节 ⇒ 必炸。
#    而当时的截断上限拍的是 200KB —— **比物理上限还大,所以它在最该保护的时候不保护**。
#    claude 腿没炸,只因为它的提示词走 stdin、根本不占 argv。
#    ⇒ 预算必须**按通道算**,而不是所有腿共用一个数。
#
# ② SIGPIPE 静默暴毙(写 ① 的判据时挖出来的,比 ① 更隐蔽):
#    `git diff | head -c N` 在 `set -e` + `pipefail` 下,diff 超过 N 时 head 读够就关管道
#    ⇒ git 吃 SIGPIPE ⇒ **整条 wrapper 静默死掉,rc=141,一个字都不留**。
#    subkimi 正是 `set -euo pipefail` ⇒ 实测直接死在这儿。
#    ⇒ 这里**一律不用 head 截断**:全读进来再按字节切。
#
# 两条都属于同一类病:**我按"想要多少"设上限,没按"通道装得下多少"设**。

# 单个 argv 参数的硬上限(execve 的 MAX_ARG_STRLEN = 32 × PAGE_SIZE)。
# 这是内核常量,不是可调项 —— 超了 execve 直接拒绝,轮不到底座程序说话。
PROMPT_ARGV_MAX=131072
# 留 2KB 余量:段头/截断说明/编码波动都在提示词里,别卡着线过。
PROMPT_ARGV_SAFE=129000
# 走 stdin 的通道不受 argv 限制,但仍要个上限 —— 巨型 diff 会把任务书挤没,
# 那比看不到 diff 更糟(腿会去评审一份它没读懂的东西)。
PROMPT_STDIN_DIFF_MAX=200000

# ── 哪些改动不该进腿的提示词 ────────────────────────────────────────────────
# 2026-08-19,业主一句「第一性原理别忘了」逼出来的:前面几版都在修"塞不下怎么办",
# 而实测昨天撑爆 argv 的那份 diff(4770 行)是 evidence 收据 4011 行(84%)、
# 判据 448 行、**代码 219 行(4%)**。腿不需要逐行读 runlog 打印的 PASS 清单,
# 而它们正把该看的代码挤出窗口(截断从尾部砍,代码落在哪一段全看运气)。
#
# 只省**正文**,不省**存在**:被省掉的文件名和行数照样给,腿想看能自己 Read。
# 静默省略比不省略更坏 —— 那会让腿以为自己看全了。
# 路径清单可以用 PANEL_DIFF_ARTIFACT_PATHS 覆盖(空格分隔的 git pathspec)。
#
# ⚠️ **往这个清单里加东西之前先过这条线**:省掉 84% 的内容本身就是一次信息取舍,
# 而做取舍的是我(主 agent),被蒙住眼睛的是评审腿 —— 这个方向天然容易滑向
# "我在挑给腿看什么"。所以边界是:
#     **只排除机器生成、且有独立来源可查得到全文的东西。**
# evidence 收据满足(git 里有全文、闸③ 看得见、腿自己能 Read)。
# 手写的文档、设计、任何人类判断过的内容**一律不许进这个清单**。
# **必须是数组**,不能是"字符串 + 无引号 for":后者会让 shell 在**当前工作目录**
# 做 pathname expansion —— 从 /root/aiwork 跑时 `tracks/*/evidence/*` 当场被展开成
# 本仓的真实文件名,pathspec 于是变成一串和被评审仓毫无关系的具体路径,
# 排除**静默失效**(第一版就是这样:代码在、判据红、看上去像没生效)。
if [[ -n "${PANEL_DIFF_ARTIFACT_PATHS:-}" ]]; then
  read -r -a PROMPT_ARTIFACT_PATHS <<< "$PANEL_DIFF_ARTIFACT_PATHS"
else
  PROMPT_ARTIFACT_PATHS=( 'tracks/*/evidence/*' '.mimocode/plans/*' )
fi

# 字节数,不是字符数。**`${#s}` 在 UTF-8 locale 下数的是字符** —— 中文注释和中文
# 任务书会让它比真实字节数小一大截,而 execve 卡的是字节。这个坑不写下来必再踩。
_bytes() { printf '%s' "$1" | wc -c; }

# _diff_budget <channel: argv|stdin> <骨架已占用的字节数>
# 返回 diff 段还能用多少字节。argv 通道下是"剩下的空间",可能是 0(任务书自己就撑满了)。
# 段头("--- 改动 (diff <base> → 工作区…) ---")和截断说明本身也在提示词里,
# 实测约 170 字节;基线名可能是长 sha 或长分支名,留 512 别卡着线过。
_DIFF_SECTION_OVERHEAD=512
_diff_budget() {
  local channel="$1" used="$2" left
  if [[ "$channel" == "argv" ]]; then
    left=$(( PROMPT_ARGV_SAFE - used - _DIFF_SECTION_OVERHEAD ))
    (( left < 0 )) && left=0
    printf '%s' "$left"
  else
    printf '%s' "$PROMPT_STDIN_DIFF_MAX"
  fi
}

# _diff_section <repo> <base> <budget>
# 打印整段(含段头);没有 diff、预算为 0、或 git 失败 ⇒ 打印空(并把原因写进 stderr)。
# 截断时**必须说出来**:静默丢掉一半 diff 比没有 diff 更坏 —— 腿会以为自己看全了。
_diff_section() {
  local repo="$1" base="$2" budget="$3" out
  # 基线解不开 ⇒ **硬失败**(2026-08-19,收四审 F4)。
  # 聊天腿的引擎早就把非法 PANEL_DIFF_BASE 当硬错误(V5),底座腿这边却是
  # `git diff "$base" 2>/dev/null` 一把吞掉 ⇒ 不注入、不报错。后果:基线打错一个字母,
  # 腿就在**没有 diff** 的情况下照常评审,而日志里看不出和正常跑有什么区别。
  # 静默变瞎的评审比没有评审更坏 —— 它还会给你一个 PASS。
  if ! git -C "$repo" rev-parse --verify --quiet "${base}^{commit}" >/dev/null 2>&1; then
    echo "  PANEL_DIFF_BASE='$base' 在 $repo 里解不开 —— 拒跑(基线打错字会让腿静默变瞎)" >&2
    return 1
  fi
  (( budget <= 0 )) && {
    echo "  (提示词的骨架已经占满 argv 预算,这次没有 diff 段可放)" >&2
    return 0
  }
  # 工件路径:正文排除在主 diff 之外,另给一段 --stat 摘要(见文件头的理由)。
  local -a ex=() only=()
  local pth
  for pth in "${PROMPT_ARTIFACT_PATHS[@]}"; do
    ex+=( ":(exclude)$pth" ); only+=( "$pth" )
  done

  # `if ! x="$(...)"` 而不是裸赋值:调用方可能开着 set -e,裸赋值失败会当场退出,
  # 连"为什么没有 diff"都来不及说。
  if ! out="$(git -C "$repo" diff "$base" -- . "${ex[@]}" 2>/dev/null | \
      DIFF_BASE="$base" DIFF_BUDGET="$budget" python3 -c '
import os, sys
b = sys.stdin.buffer.read()          # 全读:用 head 会给 git SIGPIPE(见文件头 ②)
if not b:
    sys.exit(0)
budget = int(os.environ["DIFF_BUDGET"])
base = os.environ["DIFF_BASE"]
# 按**字节**切,再按 utf-8 忽略残缺字节 —— 否则会切出半个汉字,喂给底座是无效 UTF-8。
text = b[:budget].decode("utf-8", "ignore")
out = "\n\n--- 改动 (diff %s → 工作区,含未提交) ---\n%s" % (base, text)
if len(b) > budget:
    # 文案对两个通道都得成立(stdin 通道也会截),所以别在这儿提 argv。
    out += ("\n(这份 diff 共 %d 字节,**已截断**到 %d —— 被截掉的部分请用 Read/Grep 自己去看。)"
            % (len(b), budget))
sys.stdout.write(out)
')"; then
    echo "  (算 diff 失败:基线 '$base' 在 $repo 上跑 git diff 出错)" >&2
    return 1
  fi
  # 工件摘要:只在**真的有**工件改动时才追加(没有就一个字都不加 —— 硬塞一段空摘要
  # 会让"省略要说出来"那条断言用一句永远打印的话就蒙混过关)。
  local stat
  stat="$(git -C "$repo" diff "$base" --stat -- "${only[@]}" 2>/dev/null)" || stat=""
  if [[ -n "$stat" ]]; then
    out="${out}

--- 机器写的工件(**已省略正文,只给摘要**;要看请自己 Read 这些文件)---
$stat"
  fi
  printf '%s' "$out"
}

# _assert_prompt_fits <channel> <prompt> <label>
# argv 通道下提示词放不下 ⇒ **响亮失败**。
# 这条闸的全部意义是失败形态:那次事故里 execve 吐的是 rc=126 + 一句 shell 天书,
# panel 只当"腿挂了"照常回落,真原因埋在 .err 里没人看。宁可在自己这边硬失败。
_assert_prompt_fits() {
  local channel="$1" prompt="$2" label="$3" n
  [[ "$channel" == "argv" ]] || return 0
  n="$(_bytes "$prompt")"
  if (( n > PROMPT_ARGV_MAX )); then
    {
      echo "$label: 提示词 ${n} 字节,超过单个 argv 参数的硬上限 ${PROMPT_ARGV_MAX}。"
      echo "  这条腿把整个提示词当一个命令行参数传给底座,execve 会直接拒绝(E2BIG)。"
      echo "  diff 段已经按预算截过了 ⇒ 撑爆的是**任务书本身**。把任务书拆小再派。"
    } >&2
    return 1
  fi
  return 0
}
