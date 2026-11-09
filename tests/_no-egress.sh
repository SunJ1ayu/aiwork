# shellcheck shell=bash
# Linux 无出口守卫。每个套件自己引入，手跑也不能误用真实模型额度。
# 使用 unshare -n 建独立网络命名空间，并启用 lo 供离线桩使用。
# 是否隔离由 /proc 的命名空间判断，不认环境标记；每次实测外网连接。
# 隔离不可用就拒跑(78)。这是防手滑的闸，root 仍能用 nsenter 主动绕过。

__noeg_die() {
  printf '🔴 无出口守卫:%s\n' "$1" >&2
  printf '   判据进程必须没有外网出口(不许在跑判据时把额度花出去)。\n' >&2
  printf '   来源:tests/_no-egress.sh,track no-egress-judging(2026-08-10)。\n' >&2
  exit 78
}

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
_test_review_unset="$(python3 "$_test_settings_py" clear-inherited-env)" || exit 78
eval "$_test_review_unset"
unset _test_review_unset
if ! python3 "$_test_settings_py" owned; then
  exec python3 "$_test_settings_py" "${BASH:-bash}" "$0" "$@"
fi
test_model_set() { python3 "$_test_settings_py" set-model "$@"; }
test_mktemp() { python3 "$_test_settings_py" mktemp "$@"; }
