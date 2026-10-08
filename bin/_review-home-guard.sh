# shellcheck shell=bash
# 「运行期 home 不许落在**被评审的仓**里」的**共享实现**
# (2026-08-19,track repo-write-audit 第二轮)。被 subkimi / submimo / subagent source。
#
# 为什么存在:评审腿的仓是只读挂载(bin/ro-repo-exec)。底座把自己的运行期状态
# (session / oauth / 索引 / 日志)写在它的 home 下 —— home 落在仓里,底座当场 EROFS。
# 2026-08-19 真 panel 撞过一次:kimi 腿死在
# `storage write failed: unrecognized I/O error` 上,花名册记 FAIL(rc=1),
# **和"额度耗尽"长得一模一样** —— 没人看得出是自家防线把这条腿弄死了。
# 防线把被保护的东西弄死、而且死得像别的病,是这一单最贵的失败形态之一。
#
# 为什么共享、不各写各的(第二轮四审命中):第一版只给 kimi 装了这道检查,
# opencode 腿的 OPENCODE_REVIEW_HOME、mimo 腿的 MIMO_REVIEW_HOME 照样指得进仓里。
# **默认值安全 ≠ 防线存在** —— 默认值只挡住"没设那个环境变量"的那一条路。
# 「一件事只在一条腿上做对了,而它本该处处成立」是这一单里犯过三次的同一个形状
# (V36①b opencode 腿在防线外、V37② 只抄一条 wrapper 的 argv、V38 拒跑只给 kimi 装),
# 三次都是我写的。共享实现是唯一治得住"下次再加一条腿又漏"的修法:
# 新腿要么 source 它,要么在判据 V40② 里当场露出来。

review_home_guard() {  # review_home_guard <腿名> <运行期 home> <被评审的仓> <环境变量名>
  local leg="$1" home="$2" repo="$3" var="${4:-REVIEW_HOME}"
  local h r
  # realpath 化再比:符号链接指进仓里也算仓内。解析不了(目录还没建)就按原样比,
  # 那种情况下还没有链接可言。
  h="$(cd "$home" 2>/dev/null && pwd -P)" || h="$home"
  r="$(cd "$repo" 2>/dev/null && pwd -P)" || r="$repo"
  [ -n "$h" ] && [ -n "$r" ] || return 0
  case "$h" in
    "$r"|"$r"/*) ;;
    *) return 0 ;;
  esac
  printf '%s: 运行期 home 在**被评审的仓内**(%s)⇒ 拒跑。\n' "$leg" "$h" >&2
  printf '  评审腿跑在"仓是只读的" mount namespace 里,底座往那儿写状态会当场 EROFS、\n' >&2
  printf '  腿起不来,而它吐的错误信息看不出是只读挂载(2026-08-19 真 panel 上就是这么死的)。\n' >&2
  printf '  把它放到**仓外**,例如 %s=$HOME/.local/share/aiwork/%s-review-home\n' "$var" "$leg" >&2
  return 1
}
