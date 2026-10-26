#!/usr/bin/env bash
# Review-leg platform routing. No environment or argument override: tests replace
# the probe in their own disposable deployment instead of weakening this one.
review_platform_is_macos() {
  [[ "$(uname -s)" == Darwin ]]
}

review_platform_check() {
  review_platform_is_macos || return 0
  local pending
  case "$1" in
    subkimi|submimo|subcodex|subagent|subdeepseek-agent) return 0 ;;
    subcursor) pending='Cursor 收残留进程' ;;
    *) printf '%s: 未登记的评审腿 ⇒ 拒绝派发\n' "$1" >&2; return 78 ;;
  esac
  printf '%s: Mac 上暂不运行，等待 %s的 PR ⇒ 拒绝派发\n' "$1" "$pending" >&2
  return 78
}

# The outer repository wrapper is Linux-only; Mac legs use native or reader protection.
# Pending legs are refused above before loading settings or making a clone.
review_platform_ro_exec() {
  local entry="${2:-$(basename "$0")}"
  RO_EXEC=()
  if review_platform_is_macos; then
    return 0
  fi
  [[ -x "$BIN_DIR/ro-repo-exec" ]] || {
    printf '%s: 少了 %s ⇒ 拒绝派发（不在可写的仓里跑评审腿）\n' "$entry" "$BIN_DIR/ro-repo-exec" >&2
    return 78
  }
  RO_EXEC=("$BIN_DIR/ro-repo-exec" "$1" --)
}

# Provider capability changes are confined to this platform routing module.
review_platform_claude_mode() {
  CLAUDE_SANDBOX=0
  if review_platform_is_macos; then
    CLAUDE_SANDBOX=1
    READ_ONLY=0
  fi
}
