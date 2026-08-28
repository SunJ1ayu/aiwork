#!/usr/bin/env bash
# Per-leg writable review workspace.
#
# Source this file, then:
#   review_workspace_prepare SOURCE_REPO LEG_NAME
#   repo="$(review_workspace_repo)"
#   review_workspace_cleanup
#
# The source repository is never checked out or indexed through its own .git.
# Clone-owned temporary indexes preserve the source index and separately snapshot
# the worktree/untracked view. Two complete scans must produce the same pair.

review_workspace__say() {
  printf 'review-workspace: %s\n' "$*" >&2
}

review_workspace__safe_leg() {
  printf '%s' "$1" | tr -cs 'A-Za-z0-9._-' '_'
}

review_workspace__sync_ignores() {
  local source_info source_excludes clone_info
  clone_info="$REVIEW_WORK_REPO/.git/info"
  mkdir -p -- "$clone_info" || return 1

  source_info="$(git -C "$REVIEW_SOURCE_REPO" \
    rev-parse --path-format=absolute --git-path info/exclude 2>/dev/null)" || {
      source_info="$(git -C "$REVIEW_SOURCE_REPO" rev-parse --git-path info/exclude 2>/dev/null)" \
        || return 1
      case "$source_info" in
        /*) ;;
        *) source_info="$REVIEW_SOURCE_REPO/$source_info" ;;
      esac
    }
  if [[ -f "$source_info" ]]; then
    cp -- "$source_info" "$clone_info/exclude" || return 1
  else
    : > "$clone_info/exclude" || return 1
  fi

  source_excludes="$(git -C "$REVIEW_SOURCE_REPO" config --path --get core.excludesFile 2>/dev/null || true)"
  case "$source_excludes" in
    ""|/*) ;;
    *) source_excludes="$REVIEW_SOURCE_REPO/$source_excludes" ;;
  esac
  if [[ -n "$source_excludes" && -f "$source_excludes" ]]; then
    cp -- "$source_excludes" "$clone_info/source-core-excludes" || return 1
    git -C "$REVIEW_WORK_REPO" config core.excludesFile "$clone_info/source-core-excludes" \
      || return 1
  fi
}

review_workspace__scan_view() { # path-prefix
  local prefix="$1" source_index="$1.source" work_index="$1.work" entries="$1.entries"
  rm -f -- "$source_index" "$source_index.lock" "$work_index" "$work_index.lock" "$entries"

  GIT_INDEX_FILE="$source_index" \
    git --git-dir="$REVIEW_WORK_REPO/.git" read-tree --empty >/dev/null \
    || return 1
  git -C "$REVIEW_SOURCE_REPO" ls-files --stage -z > "$entries" || return 1
  GIT_INDEX_FILE="$source_index" \
    git --git-dir="$REVIEW_WORK_REPO/.git" update-index -z --index-info < "$entries" \
    || return 1
  REVIEW_SCAN_INDEX_TREE="$(GIT_INDEX_FILE="$source_index" \
    git --git-dir="$REVIEW_WORK_REPO/.git" write-tree)" || return 1

  cp -- "$source_index" "$work_index" || return 1
  GIT_INDEX_FILE="$work_index" \
    git --git-dir="$REVIEW_WORK_REPO/.git" --work-tree="$REVIEW_SOURCE_REPO" \
      add -A -- :/ >/dev/null \
    || return 1
  REVIEW_SCAN_WORKTREE_TREE="$(GIT_INDEX_FILE="$work_index" \
    git --git-dir="$REVIEW_WORK_REPO/.git" --work-tree="$REVIEW_SOURCE_REPO" \
      write-tree)" || return 1
  REVIEW_SCAN_SOURCE_INDEX="$source_index"
}

review_workspace_prepare() { # source-repo leg-name
  local source="${1:-}" leg="${2:-review}" top base base_preflight safe_leg scan1 scan2
  local head object_format tree1 tree2 index_tree1 index_tree2 snapshot_commit marker source_index
  local source_index1 source_index2 tree_entries tree_to_check

  [[ -n "$source" && -d "$source" ]] \
    || { review_workspace__say "源仓不存在:$source"; return 78; }
  command -v git >/dev/null 2>&1 \
    || { review_workspace__say '找不到 git，建不了 review 副本'; return 78; }
  command -v mktemp >/dev/null 2>&1 \
    || { review_workspace__say '找不到 mktemp，建不了受控临时目录'; return 78; }
  command -v realpath >/dev/null 2>&1 \
    || { review_workspace__say '找不到 realpath，无法在写入前校验 workspace 根'; return 78; }

  top="$(git -C "$source" rev-parse --show-toplevel 2>/dev/null)" \
    || { review_workspace__say "不是 Git 工作树:$source"; return 78; }
  REVIEW_SOURCE_REPO="$(cd "$top" && pwd -P)" \
    || { review_workspace__say "源仓真路径解析失败:$top"; return 78; }
  head="$(git -C "$REVIEW_SOURCE_REPO" rev-parse --verify HEAD 2>/dev/null)" \
    || { review_workspace__say '源仓没有可派发的 HEAD；拒绝猜基线'; return 78; }
  object_format="$(git -C "$REVIEW_SOURCE_REPO" rev-parse --show-object-format 2>/dev/null)" \
    || { review_workspace__say '读不到 Git object format；拒绝猜 OID 语义'; return 78; }
  case "$object_format" in
    sha1|sha256) ;;
    *) review_workspace__say "不支持的 Git object format:$object_format"; return 78 ;;
  esac
  source_index="$(git -C "$REVIEW_SOURCE_REPO" ls-files --stage)" || {
    review_workspace__say '读取源 index 失败；拒绝派发'
    return 78
  }
  if awk '$1 == "160000" { found=1 } END { exit(found ? 0 : 1) }' <<< "$source_index"; then
    review_workspace__say '源 index 包含 gitlink/submodule；首版隔离语义未定义，拒绝派发'
    return 78
  fi

  base="${REVIEW_WORKSPACE_BASE:-${TMPDIR:-/tmp}/aiwork-review-workspaces}"
  base_preflight="$(realpath -m -- "$base" 2>/dev/null)" \
    || { review_workspace__say "workspace 根预检失败:$base"; return 78; }
  case "$base_preflight" in
    /|"$REVIEW_SOURCE_REPO"|"$REVIEW_SOURCE_REPO"/*)
      review_workspace__say "workspace 根不许落在源仓内:$base_preflight"
      return 78
      ;;
  esac
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
  REVIEW_SNAPSHOT_HEAD=""
  REVIEW_SNAPSHOT_OBJECT_FORMAT=""
  REVIEW_SNAPSHOT_TREE=""
  REVIEW_SNAPSHOT_INDEX_TREE=""
  marker="$REVIEW_WORKSPACE_DIR/.aiwork-review-workspace"
  {
    printf 'source=%s\n' "$REVIEW_SOURCE_REPO"
    printf 'pid=%s\n' "$$"
  } > "$marker" || {
    review_workspace__say "写不了 workspace marker:$marker"
    rmdir -- "$REVIEW_WORKSPACE_DIR" >/dev/null 2>&1 || true
    REVIEW_WORKSPACE_DIR=""
    REVIEW_WORK_REPO=""
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
  review_workspace__sync_ignores || {
    review_workspace__say '同步源仓 ignore 语义失败；拒绝猜 untracked 边界'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }

  scan1="$REVIEW_WORKSPACE_DIR/scan.first"
  scan2="$REVIEW_WORKSPACE_DIR/scan.second"
  review_workspace__scan_view "$scan1" || {
    review_workspace__say '第一次源视图扫描失败；模型不会启动'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }
  index_tree1="$REVIEW_SCAN_INDEX_TREE"
  tree1="$REVIEW_SCAN_WORKTREE_TREE"
  source_index1="$REVIEW_SCAN_SOURCE_INDEX"
  review_workspace__scan_view "$scan2" || {
    review_workspace__say '第二次源视图扫描失败；模型不会启动'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }
  index_tree2="$REVIEW_SCAN_INDEX_TREE"
  tree2="$REVIEW_SCAN_WORKTREE_TREE"
  source_index2="$REVIEW_SCAN_SOURCE_INDEX"
  rm -f -- "$source_index1" "$source_index1.lock" \
    "$scan1.work" "$scan1.work.lock" "$scan1.entries" \
    "$scan2.work" "$scan2.work.lock" "$scan2.entries"

  [[ "$index_tree1" == "$index_tree2" && "$tree1" == "$tree2" ]] || {
    review_workspace__say "复制窗口内源 index/worktree 发生变化($index_tree1/$tree1 != $index_tree2/$tree2)，拒绝派发"
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }
  [[ "$(git -C "$REVIEW_SOURCE_REPO" rev-parse --verify HEAD 2>/dev/null)" == "$head" ]] || {
    review_workspace__say '复制窗口内源 HEAD 发生变化，拒绝派发'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }
  for tree_to_check in "$index_tree2" "$tree2"; do
    tree_entries="$(git --git-dir="$REVIEW_WORK_REPO/.git" ls-tree -r "$tree_to_check")" || {
      review_workspace__say '读取 snapshot tree 失败；拒绝派发'
      review_workspace_cleanup >/dev/null 2>&1 || true
      return 78
    }
    if awk '$1 == "160000" { found=1 } END { exit(found ? 0 : 1) }' <<< "$tree_entries"; then
      review_workspace__say '源视图包含 gitlink/submodule；首版隔离语义未定义，拒绝派发'
      review_workspace_cleanup >/dev/null 2>&1 || true
      return 78
    fi
  done

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
  git -C "$REVIEW_WORK_REPO" reset --soft --quiet "$head" || {
    review_workspace__say '把 clone HEAD 恢复到源 HEAD 失败'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }
  mv -f -- "$source_index2" "$REVIEW_WORK_REPO/.git/index" || {
    review_workspace__say '安装源 index 快照失败；拒绝派发'
    review_workspace_cleanup >/dev/null 2>&1 || true
    return 78
  }

  REVIEW_SNAPSHOT_HEAD="$head"
  REVIEW_SNAPSHOT_OBJECT_FORMAT="$object_format"
  REVIEW_SNAPSHOT_TREE="$tree1"
  REVIEW_SNAPSHOT_INDEX_TREE="$index_tree1"
  export REVIEW_SOURCE_REPO REVIEW_WORKSPACE_BASE_REAL REVIEW_WORKSPACE_DIR
  export REVIEW_WORK_REPO REVIEW_SNAPSHOT_HEAD REVIEW_SNAPSHOT_OBJECT_FORMAT
  export REVIEW_SNAPSHOT_TREE REVIEW_SNAPSHOT_INDEX_TREE
  return 0
}

review_workspace_repo() {
  [[ -n "${REVIEW_WORK_REPO:-}" && -d "$REVIEW_WORK_REPO" ]] || {
    review_workspace__say 'review workspace 尚未准备好'
    return 78
  }
  printf '%s\n' "$REVIEW_WORK_REPO"
}

review_workspace_write_facts() { # requested-model invoked-model [billing-mode]
  local requested="${1:-}" invoked="${2:-}" billing="${3:-subscription}"
  local output="${AIWORK_REVIEW_FACTS_PATH:-}" helper="${AIWORK_REVIEW_RESULT_BIN:-}"
  [[ -n "$output" ]] || return 0
  [[ -n "$helper" && -f "$helper" ]] \
    || { review_workspace__say 'typed facts producer 缺件'; return 78; }
  python3 "$helper" facts --output "$output" \
    --requested-model "$requested" --invoked-model "$invoked" \
    --git-object-format "$REVIEW_SNAPSHOT_OBJECT_FORMAT" \
    --head-oid "$REVIEW_SNAPSHOT_HEAD" --index-tree-oid "$REVIEW_SNAPSHOT_INDEX_TREE" \
    --worktree-tree-oid "$REVIEW_SNAPSHOT_TREE" \
    --view-delivery-state complete --view-mode full_snapshot --billing-mode "$billing"
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
  REVIEW_SNAPSHOT_HEAD=""
  REVIEW_SNAPSHOT_OBJECT_FORMAT=""
  REVIEW_SNAPSHOT_TREE=""
  REVIEW_SNAPSHOT_INDEX_TREE=""
  return 0
}
