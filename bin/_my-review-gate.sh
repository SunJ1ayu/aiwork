# shellcheck shell=bash
# 反锚定闸的**共享实现**(2026-08-06)。被 submimo / subchat / subagent 三个躯干 source。
#
# 为什么共享而不是抄三份:底座腿曾是 95% 相同的两份拷贝,每条修法都得改两遍,
# 而历史证明**总有一份会落下**(subagent 的文件头自己写着这段账)。
#
# 为什么要有这道闸(2026-08-06 当天自查抓到的):
#   `panel-review` 早就强制"先写自己的一遍再派发"(forgetting stops you),
#   但 **fast lane 走的是另一条命令**(`submimo review` 直接调),那条路上没有任何闸。
#   当天实证:我给 full lane 规规矩矩先落盘自审再派四审;轮到 fast lane 那一单,
#   就变成先发出评审、后写 verify —— 自己的 findings 和腿的结论同一次写下去,
#   **反锚定在 fast lane 上等于没执行**。同一条规矩,两条路,一条有闸一条没有。
#
# 约定路径与 panel-review 完全一致:<data-dir>/tasks/<taskname>-my-review.md
# 显式退出:`REVIEW_NO_MY_REVIEW=1`(清醒的选择,比如给别人的仓做一次性评审)。
# panel-review 派发各腿时在**命令行**上带 `--panel-dispatch` —— 它在自己那层已经查过,
# 这里不再重复挡(否则四审整个派不出去)。
# **为什么是命令行而不是环境变量**(2026-08-06 四审两腿都点名):环境变量在 shell 里
# `export` 一次,之后每条命令都自动带着、而且不留痕 —— 那是"想跳过时最省事的路",
# 等于给自己留了个随手可按的后门。命令行标记必须每次亲手敲,不会被继承。

my_review_gate() {  # my_review_gate <mode> <task_file> <repo_dir> <label>
  local mode="$1" task="$2" repo="$3" label="${4:-review}"
  [[ "$mode" == "review" ]] || return 0
  local gate_bin tasks_dir
  gate_bin="$(dirname "${BASH_SOURCE[0]}")"
  if [[ "${GATE_PANEL_DISPATCH:-0}" == "1" ]]; then
    # panel-review 已在自己那层查过,这里不重复拦;但自审文件确实不存在时留一行痕。
    tasks_dir="$("$gate_bin/aiwork-config" data-path tasks)" || return 1
    local _mr="${REVIEW_MY_REVIEW:-$tasks_dir/$(basename "${task%.*}")-my-review.md}"
    [[ -f "$_mr" ]] || echo "$label: 注意 —— --panel-dispatch 跳过了反锚定闸,而 $_mr 并不存在。" >&2
    return 0
  fi
  [[ "${REVIEW_NO_MY_REVIEW:-0}" == "1" ]] && return 0

  tasks_dir="$("$gate_bin/aiwork-config" data-path tasks)" || return 1
  local mr="${REVIEW_MY_REVIEW:-$tasks_dir/$(basename "${task%.*}")-my-review.md}"
  if [[ ! -f "$mr" ]]; then
    echo "$label: 先写你自己的一遍 —— 找不到 $mr" >&2
    echo "  评审腿是第二意见,**永远不能替代主 agent 自己的第一遍**;先读腿会锚定判断。" >&2
    echo "  写好再派;或显式 REVIEW_NO_MY_REVIEW=1 清醒地跳过。" >&2
    return 1
  fi
  if [[ ! -s "$mr" ]]; then
    echo "$label: 自审文件是空的:$mr(空文件不算写过)" >&2
    return 1
  fi
  # 必须在仓外:引擎会把未跟踪文件内联进腿的提示词 —— 自己的 findings 进了仓,
  # "独立的第二意见"就变成了照着我的答案抄(07-21 实事故,panel-review 那层同源)。
  # realpath 不可用 ⇒ **拒跑**,不是放行。
  # 2026-08-06 四审 subkimi 指出:`panel-review` 原来那层对 realpath 不带任何逃生,
  # 而我下沉成共享件时顺手写了 `|| return 0` —— **重构悄悄把检查改松了**。
  # 少了它,"自审文件在仓内"这条核心检查会在没有 realpath 的环境里整体静默失效。
  local rp mrv
  command -v realpath >/dev/null 2>&1 || {
    echo "$label: 系统里没有 realpath,无法判断自审文件在不在仓内 —— 拒跑(fail closed)" >&2
    return 1
  }
  rp="$(realpath "$repo" 2>/dev/null)" || {
    echo "$label: realpath 解析不了仓库路径 $repo —— 拒跑(fail closed)" >&2
    return 1
  }
  for mrv in "$(realpath "$mr" 2>/dev/null)" "$(realpath -s "$mr" 2>/dev/null)"; do
    case "$mrv" in
      "$rp"/*)
        echo "$label: 自审文件在被评审的仓里:$mrv" >&2
        echo "  引擎会把它内联进评审腿的提示词 ⇒ 腿照着我的答案抄。挪到仓外。" >&2
        return 1 ;;
    esac
  done
  return 0
}

# 从参数里摘掉 `--panel-dispatch`(panel-review 派发时才会带),其余参数原样交回。
# 各躯干在**解析位置参数之前**调:gate_strip_flags "$@"; set -- "${GATE_ARGS[@]}"
gate_strip_flags() {
  GATE_PANEL_DISPATCH=0
  GATE_ARGS=()
  local a
  for a in "$@"; do
    if [[ "$a" == "--panel-dispatch" ]]; then GATE_PANEL_DISPATCH=1; else GATE_ARGS+=("$a"); fi
  done
}
