#!/usr/bin/env bash
# Per-leg writable review workspace.
#
# Source this file, then:
#   review_workspace_prepare SOURCE_REPO LEG_NAME
#   repo="$(review_workspace_repo)"
#   review_workspace_cleanup
#
# The source repository is never checked out or indexed through its own .git.
# A temporary index owned by the clone snapshots tracked dirty/deleted files and
# untracked non-ignored files.  Two complete scans must produce the same tree.

review_workspace__say() {
  printf 'review-workspace: %s\n' "$*" >&2
}

review_workspace__safe_leg() {
  printf '%s' "$1" | tr -cs 'A-Za-z0-9._-' '_'
}

review_workspace__scan_tree() { # index-path head
  local index_path="$1" head="$2"
  rm -f -- "$index_path" "$index_path.lock"
  GIT_INDEX_FILE="$index_path" \
    git --git-dir="$REVIEW_WORK_REPO/.git" --work-tree="$REVIEW_SOURCE_REPO" \
      read-tree "$head" >/dev/null \
    || return 1
  GIT_INDEX_FILE="$index_path" \
    git --git-dir="$REVIEW_WORK_REPO/.git" --work-tree="$REVIEW_SOURCE_REPO" \
      add -A -- :/ >/dev/null \
    || return 1
  GIT_INDEX_FILE="$index_path" \
    git --git-dir="$REVIEW_WORK_REPO/.git" --work-tree="$REVIEW_SOURCE_REPO" \
      write-tree
}

review_workspace_prepare() { # source-repo leg-name
  local source="${1:-}" leg="${2:-review}" top base safe_leg index1 index2
  local head tree1 tree2 snapshot_commit marker source_index tree_entries

  [[ -n "$source" && -d "$source" ]] \
    || { review_workspace__say "源仓不存在:$source"; return 78; }
  command -v git >/dev/null 2>&1 \
    || { review_workspace__say '找不到 git，建不了 review 副本'; return 78; }
  command -v mktemp >/dev/null 2>&1 \
    || { review_workspace__say '找不到 mktemp，建不了受控临时目录'; return 78; }

  top="$(git -C "$source" rev-parse --show-toplevel 2>/dev/null)" \
    || { review_workspace__say "不是 Git 工作树:$source"; return 78; }
  REVIEW_SOURCE_REPO="$(cd "$top" && pwd -P)" \
    || { review_workspace__say "源仓真路径解析失败:$top"; return 78; }
  head="$(git -C "$REVIEW_SOURCE_REPO" rev-parse --verify HEAD 2>/dev/null)" \
    || { review_workspace__say '源仓没有可派发的 HEAD；拒绝猜基线'; return 78; }
  source_index="$(git -C "$REVIEW_SOURCE_REPO" ls-files --stage)" || {
    review_workspace__say '读取源 index 失败；拒绝派发'
    return 78
  }
  if awk '$1 == "160000" { found=1 } END { exit(found ? 0 : 1) }' <<< "$source_index"; then
    review_workspace__say '源 index 包含 gitlink/submodule；首版隔离语义未定义，拒绝派发'
    return 78
  fi

  base="${REVIEW_WORKSPACE_BASE:-${TMPDIR:-/tmp}/aiwork-review-workspaces}"
  mkdir -p -m 700 -- "$base" \
    || { review_workspace__say "建不了 workspace 根:$base"; return 78; }
  REVIEW_WORKSPACE_BASE_REAL="$(cd "$base" && pwd -P)" \
    || { review_workspace__say "workspace 根真路径解析失败:$base"; return 78; }
  case "$REVIEW_WORKSPACE_BASE_REAL" in
    /|"$REVIEW_SOURCE_REPO"|"$REVIEW_SOURCE_REPO"/*)
      review_workspace__say "workspace 根不许落在源仓内:$REVIEW_WORKSPACE_BASE_REAL"
      return 78
      ;;
  esac

  safe_leg="$(review_workspace__safe_leg "$leg")"
  [[ -n "$safe_leg" ]] || safe_leg=review
  REVIEW_WORKSPACE_DIR="$(mktemp -d "$REVIEW_WORKSPACE_BASE_REAL/${safe_leg}.XXXXXXXX")" \
    || { review_workspace__say "mktemp 失败:$REVIEW_WORKSPACE_BASE_REAL"; return 78; }
  REVIEW_WORK_REPO="$REVIEW_WORKSPACE_DIR/repo"
  REVIEW_SNAPSHOT_TREE=""
  marker="$REVIEW_WORKSPACE_DIR/.aiwork-review-workspace"
  {
    printf 'source=%s\n' "$REVIEW_SOURCE_REPO"
    printf 'pid=%s\n' "$$"
  } > "$marker" || {
    review_workspace__say "写不了 workspace marker:$marker"
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }

  git clone --shared --no-checkout --quiet "$REVIEW_SOURCE_REPO" "$REVIEW_WORK_REPO" \
    || {
      review_workspace__say 'shared clone 失败；模型不会启动'
      review_workspace_cleanup >/dev/null 2>&1 || true
      return 78
    }
  git -C "$REVIEW_WORK_REPO" remote remove origin >/dev/null 2>&1 || {
    review_workspace__say '删除 clone origin 失败；拒绝留下可推送 remote'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }
  git -C "$REVIEW_WORK_REPO" config gc.auto 0 || {
    review_workspace__say '设置 clone gc.auto=0 失败'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }

  index1="$REVIEW_WORKSPACE_DIR/index.first"
  index2="$REVIEW_WORKSPACE_DIR/index.second"
  tree1="$(review_workspace__scan_tree "$index1" "$head")" || {
    review_workspace__say '第一次源视图扫描失败；模型不会启动'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }
  tree2="$(review_workspace__scan_tree "$index2" "$head")" || {
    review_workspace__say '第二次源视图扫描失败；模型不会启动'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }
  rm -f -- "$index1" "$index1.lock" "$index2" "$index2.lock"

  [[ "$tree1" == "$tree2" ]] || {
    review_workspace__say "复制窗口内源视图发生变化($tree1 != $tree2)，拒绝派发"
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }
  [[ "$(git -C "$REVIEW_SOURCE_REPO" rev-parse --verify HEAD 2>/dev/null)" == "$head" ]] || {
    review_workspace__say '复制窗口内源 HEAD 发生变化，拒绝派发'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }
  tree_entries="$(git --git-dir="$REVIEW_WORK_REPO/.git" ls-tree -r "$tree1")" || {
    review_workspace__say '读取 snapshot tree 失败；拒绝派发'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }
  if awk '$1 == "160000" { found=1 } END { exit(found ? 0 : 1) }' <<< "$tree_entries"; then
    review_workspace__say '源视图包含 gitlink/submodule；首版隔离语义未定义，拒绝派发'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  fi

  snapshot_commit="$(printf 'aiwork review snapshot\n' | \
    GIT_AUTHOR_NAME=aiwork GIT_AUTHOR_EMAIL=review@localhost \
    GIT_COMMITTER_NAME=aiwork GIT_COMMITTER_EMAIL=review@localhost \
    git --git-dir="$REVIEW_WORK_REPO/.git" commit-tree "$tree1" -p "$head")" || {
      review_workspace__say '生成临时 snapshot commit 失败'
      review_workspace_cleanup >/dev/null 2>&1 || true
      return 78
    }
  git -C "$REVIEW_WORK_REPO" reset --hard --quiet "$snapshot_commit" || {
    review_workspace__say '物化 snapshot tree 失败'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }
  git -C "$REVIEW_WORK_REPO" reset --mixed --quiet "$head" || {
    review_workspace__say '把 clone HEAD 恢复到源 HEAD 失败'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }

  REVIEW_SNAPSHOT_TREE="$tree1"
  export REVIEW_SOURCE_REPO REVIEW_WORKSPACE_BASE_REAL REVIEW_WORKSPACE_DIR
  export REVIEW_WORK_REPO REVIEW_SNAPSHOT_TREE
  return 0
}

review_workspace_repo() {
  [[ -n "${REVIEW_WORK_REPO:-}" && -d "$REVIEW_WORK_REPO" ]] || {
    review_workspace__say 'review workspace 尚未准备好'
    return 78
  }
  printf '%s\n' "$REVIEW_WORK_REPO"
}

review_workspace_cleanup() {
  local target="${REVIEW_WORKSPACE_DIR:-}" base="${REVIEW_WORKSPACE_BASE_REAL:-}"
  local marker
  [[ -n "$target" && -n "$base" ]] || return 0
  [[ "$target" != / && "$target" != "$base" && "$target" != "${REVIEW_SOURCE_REPO:-}" ]] || {
    review_workspace__say "拒绝清理不安全路径:$target"
    return 78
  }
  case "$target" in
    "$base"/*) ;;
    *) review_workspace__say "拒绝清理受控根之外的路径:$target"; return 78 ;;
  esac
  target="$(cd "$target" 2>/dev/null && pwd -P)" || {
    # Already gone is a successful idempotent cleanup.
    [[ ! -e "${REVIEW_WORKSPACE_DIR:-}" ]] && return 0
    review_workspace__say "cleanup 目标解析失败:${REVIEW_WORKSPACE_DIR:-}"
    return 78
  }
  case "$target" in
    "$base"/*) ;;
    *) review_workspace__say "cleanup 真路径逃出受控根:$target"; return 78 ;;
  esac
  marker="$target/.aiwork-review-workspace"
  [[ -f "$marker" ]] || {
    review_workspace__say "cleanup 目标没有 helper marker:$target"
    return 78
  }
  rm -rf -- "$target" || {
    review_workspace__say "workspace 清理失败:$target"
    return 78
  }
  REVIEW_WORKSPACE_DIR=""
  REVIEW_WORK_REPO=""
  REVIEW_SNAPSHOT_TREE=""
  return 0
}
