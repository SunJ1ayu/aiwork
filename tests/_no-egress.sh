# shellcheck shell=bash
# 无出口守卫(bash 版)—— 2026-08-10,track no-egress-judging。
#
# 不变量只有一句:**跑判据的进程不许有外网出口。**
#
# 用法(判据套件顶部,越靠前越好,`set` 之后第一件事):
#   . "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh"
#
# 它做的事:发现自己还没隔离 ⇒ 把整个脚本 `exec` 进隔离里重跑(Linux 是 `unshare -n` 的
# 命名空间、把 `lo` 拉起来;macOS 是只禁外网的沙箱;本机连接都留着,桩服务器还要用);
# 做不到就**拒跑**。
#
# 为什么守卫要待在**套件里**而不是总跑入口里:手跑单个套件是开发时的日常,
# 只包总跑就等于守错了门(08-04「守卫要守对门」那笔账)。
#
# 三个刻意的设计,每一个都对应本机踩过的坑:
#   1. **fail-closed**:隔离做不到就退出,绝不静默往下跑。
#      (V23⑤:我把共享件下沉时顺手加过一个 fail-open,重构悄悄把检查改松了。)
#   2. **不认环境变量**:是否已隔离,问内核(Linux 比 /proc/self/ns/net 与 /proc/1/ns/net,
#      macOS 问 sandbox_check)。
#      环境变量只用来打断"试过一次仍没隔离"的死循环,**不用来判定已隔离** ——
#      V24 刚封过同一形状的后门:export 一次,零成本、不留痕。
#   3. **每次都实测一次出口**,而不是"相信隔离有效"。在隔离里这是一次
#      立刻失败的 connect,零成本;哪天内核/容器行为变了,它当场就红。
#
# 强度声明:**这不是安全边界。** 本机是 root,
# 一行 `nsenter -t 1 -n` 就能出去 —— 本单的判据自己就在这么干(它需要真出口才问得出
# "守卫切断了出口";macOS 上它在引守卫之前先换成一个沙箱外的代跑进程)。
# 这道闸堵的是**手滑**:考卷不小心真去叫了模型、把额度花掉。
# 它堵不住蓄意外呼,也不打算堵。真要防蓄意,得换层级(凭证隔离 / 独立账号)。
#
# **这是指定的分平台处。** 平台判断只许出现在这里、python 版 `_no_egress.py` 和它们的判据
# `test-no-egress.sh`;别的套件不分平台。两个平台守的是同一句不变量,只是手段不同:
#   Linux:独立网络命名空间(`unshare -n`),"已隔离" = 本进程和 1 号进程的 net 命名空间不同。
#   macOS:系统自带的 `/usr/bin/sandbox-exec` 带一份「只禁外网」的规则重跑自己;
#          "已隔离" = 内核的 sandbox_check 说本进程在沙箱里。规则、问内核、实测出口、拒跑的话
#          只在 python 版 `_no_egress.py` 里定义,细节写在那边;本文件在 Mac 上一律问它。

__noeg_die() {
  printf '🔴 无出口守卫:%s\n' "$1" >&2
  printf '   判据进程必须没有外网出口(不许在跑判据时把额度花出去)。\n' >&2
  printf '   来源:tests/_no-egress.sh,track no-egress-judging(2026-08-10)。\n' >&2
  exit 78
}

if [[ "$(uname -s)" == Darwin ]]; then
  # macOS 的规则、问内核在不在沙箱里、实测出口、拒跑的话都只在 python 版里定义一次,
  # 这里一律问它(bash 调不了 C 函数,本来就要借 python3)。
  __noeg_py="$(dirname "${BASH_SOURCE[0]}")/_no_egress.py"

  __noeg_py_failed() {  # python 版拒跑时自己说清了原因(78);别的失败是它根本没跑起来
    [[ "$1" -eq 78 ]] && exit 78
    __noeg_die "调不起 python 版守卫($__noeg_py),做不到网络隔离 ⇒ 拒跑"
  }

  { IFS= read -r __noeg_not_isolated_msg; IFS= read -r __noeg_leak_msg; } \
    < <(python3 -I "$__noeg_py" messages 2>/dev/null)
  : "${__noeg_not_isolated_msg:=拒跑(python 版守卫调不起来,给不出原因)}"
  : "${__noeg_leak_msg:=拒跑(python 版守卫调不起来,给不出原因)}"

  __noeg_isolated() {
    local v
    v="$(python3 -I "$__noeg_py" sandboxed)" || __noeg_py_failed $?
    case "$v" in
      1) return 0 ;;
      0) return 1 ;;
      *) __noeg_py_failed 1 ;;
    esac
  }

  __noeg_egress_open() {  # 只有明确连不上才算没有出口(检查本身坏了也当连得出去)
    [[ "$(python3 -I "$__noeg_py" egress 2>/dev/null)" != closed ]]
  }

  __noeg_prepare() {  # python 版探过规则套得上,才给出沙箱程序和规则
    local out
    out="$(python3 -I "$__noeg_py" prepare)" || __noeg_py_failed $?
    __noeg_sbx="${out%%$'\n'*}"
    __noeg_profile="${out#*$'\n'}"
    [[ -n "$__noeg_sbx" && "$__noeg_profile" != "$out" ]] || __noeg_py_failed 1
  }

  __noeg_reexec() {
    exec "$__noeg_sbx" -p "$__noeg_profile" "${BASH:-bash}" "$0" "$@"
  }
else
  __noeg_not_isolated_msg="已经自举过一次,却仍然不在独立的网络命名空间里(unshare 没生效?)"
  __noeg_leak_msg="已经进了命名空间,却**仍然连得出去** ⇒ 拒跑(这道闸没生效,别当它生效了)"

  __noeg_isolated() {  # 已经在独立网络命名空间里?
    local self host
    self="$(readlink /proc/self/ns/net 2>/dev/null)" || return 1
    host="$(readlink /proc/1/ns/net    2>/dev/null)" || return 1
    [[ -n "$self" && -n "$host" && "$self" != "$host" ]]
  }

  __noeg_egress_open() {  # 还连得出去?(bash 自带 /dev/tcp,不依赖 python)
    timeout 3 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' 2>/dev/null
  }

  __noeg_prepare() {
    command -v unshare >/dev/null 2>&1 \
      || __noeg_die "找不到 unshare,做不到网络隔离 ⇒ 拒跑"
    unshare -n -- true 2>/dev/null \
      || __noeg_die "unshare -n 用不了(没权限?内核不支持?)⇒ 拒跑"
  }

  __noeg_reexec() {  # 把 lo 拉起来,桩服务器还要用
    exec unshare -n -- bash -c 'ip link set lo up 2>/dev/null || true; exec "$0" "$@"' \
         "${BASH:-bash}" "$0" "$@"
  }
fi

if ! __noeg_isolated; then
  if [[ -n "${AIWORK_NO_EGRESS_TRIED:-}" ]]; then
    __noeg_die "$__noeg_not_isolated_msg"
  fi
  # 先探一下再 exec:直接 exec 的话,隔离失败会把本进程替换掉,
  # 于是退出码是它的、**一句解释都留不下**(判据 N4 就是查这个)。
  __noeg_prepare

  export AIWORK_NO_EGRESS_TRIED=1
  # 用 exec 重跑自己:退出码 / stdin / 参数全部原样(判据 N7 查这三样)。
  __noeg_reexec "$@"
fi

# 隔离成功了就把"试过一次"的标记摘掉:它是**给本进程打断死循环**用的,
# 不是身份牌。留着它会被子进程继承 —— 子进程要是又回到了主命名空间
# (判据自己就会这么干),会被误判成"自举失败"而拒跑。
# 08-10 实测:不摘的话 N1/N2/N7 全红,而 N5 会因为**错误的原因**变绿。
unset AIWORK_NO_EGRESS_TRIED

if __noeg_egress_open; then
  __noeg_die "$__noeg_leak_msg"
fi

# Test model defaults are disposable fixtures, never the owner's machine settings.
_test_settings_py="$(dirname "${BASH_SOURCE[0]}")/_test_settings.py"
_test_review_unset="$(python3 "$_test_settings_py" clear-review-env)" || exit 78
eval "$_test_review_unset"
unset _test_review_unset
if [[ -z "${AIWORK_CONFIG_DIR:-}" || -z "${AIWORK_DATA_DIR:-}" ]]; then
  exec python3 "$_test_settings_py" "${BASH:-bash}" "$0" "$@"
fi
test_model_set() { python3 "$_test_settings_py" set-model "$@"; }
