# shellcheck shell=bash
# Read-only legs cannot ask Git themselves. Preserve history and status as text.
review_reader_context() {
  local repo="$1" context
  [[ ! -e "$repo/aiwork-git-context.txt" && ! -L "$repo/aiwork-git-context.txt" ]] || {
    printf 'reader context path already exists ⇒ 拒绝派发\n' >&2; return 1;
  }
  context="$(mktemp "$repo/.aiwork-git-context-XXXXXX")" || return 1
  {
    printf '# Git status\n'
    git -C "$repo" status --short --branch &&
    printf '\n# Git history (available snapshot history, newest first)\n' &&
    git -C "$repo" log --format=fuller --stat
  } > "$context" || { rm -f -- "$context"; return 1; }
  mv -f -- "$context" "$repo/aiwork-git-context.txt"
}
