#!/usr/bin/env bash
# Review and execution tooling requires Linux.
review_platform_is_linux() {
  [[ "$(uname -s)" == Linux ]]
}

review_platform_check() {
  review_platform_is_linux && return 0
  printf '%s: 仅支持 Linux；请在 Linux 虚拟机里运行 ⇒ 拒绝派发\n' "$1" >&2
  return 78
}

review_platform_ro_exec() {
  local entry="${2:-$(basename "$0")}"
  RO_EXEC=()
  [[ -x "$BIN_DIR/ro-repo-exec" ]] || {
    printf '%s: 少了 %s ⇒ 拒绝派发（不在可写的仓里跑评审腿）\n' "$entry" "$BIN_DIR/ro-repo-exec" >&2
    return 78
  }
  RO_EXEC=("$BIN_DIR/ro-repo-exec" "$1" --)
}
