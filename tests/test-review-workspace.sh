#!/usr/bin/env bash
# Oracle for per-review writable snapshots.  The implementation lives in
# bin/_review-workspace.sh; wrappers must fail closed when that helper cannot
# prepare a workspace.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh"

BIN="${REVIEW_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"
HELPER="$BIN/_review-workspace.sh"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check() { if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

new_repo() { # new_repo PATH
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name test
  printf 'committed\n' > "$repo/committed.txt"
  printf 'old-modified\n' > "$repo/modified.txt"
  printf 'old-staged\n' > "$repo/staged.txt"
  printf 'delete-me\n' > "$repo/deleted.txt"
  printf 'ignored.cache\n' > "$repo/.gitignore"
  git -C "$repo" add -A
  git -C "$repo" commit -qm base

  printf 'new-modified\n' > "$repo/modified.txt"
  printf 'staged-version\n' > "$repo/staged.txt"
  git -C "$repo" add staged.txt
  printf 'working-version\n' >> "$repo/staged.txt"
  rm "$repo/deleted.txt"
  printf 'untracked\n' > "$repo/untracked.txt"
  printf 'must-not-copy\n' > "$repo/ignored.cache"
}

test_snapshot_view() {
  echo '[RW1] snapshot carries the current source view, not ignored runtime state'
  local d repo before head work clone status_after
  d="$(mktemp -d)"; repo="$d/source"; new_repo "$repo"
  before="$(git -C "$repo" status --short)"
  head="$(git -C "$repo" rev-parse HEAD)"
  REVIEW_WORKSPACE_BASE="$d/workspaces"
  review_workspace_prepare "$repo" oracle-view >/dev/null 2>&1
  local rc=$?
  check 'RW1: helper prepares a workspace' "$rc"
  if [[ $rc -ne 0 ]]; then rm -rf "$d"; return; fi
  work="$REVIEW_WORKSPACE_DIR"; clone="$(review_workspace_repo)"

  [[ "$(git -C "$clone" rev-parse HEAD 2>/dev/null)" == "$head" ]]
  check 'RW1: clone HEAD stays at the source HEAD' $?
  cmp -s "$repo/committed.txt" "$clone/committed.txt" \
    && cmp -s "$repo/modified.txt" "$clone/modified.txt" \
    && cmp -s "$repo/staged.txt" "$clone/staged.txt" \
    && cmp -s "$repo/untracked.txt" "$clone/untracked.txt" \
    && [[ ! -e "$clone/deleted.txt" && ! -e "$clone/ignored.cache" ]]
  check 'RW1: committed/modified/staged-final/deleted/untracked match; ignored is absent' $?
  [[ -d "$clone/.git" && ! -f "$clone/.git" ]]
  check 'RW1: clone owns a real, independent .git directory' $?
  [[ -n "${REVIEW_SNAPSHOT_TREE:-}" \
     && -z "$(git -C "$clone" remote 2>/dev/null)" \
     && "$(git -C "$clone" config --get gc.auto 2>/dev/null)" == 0 ]]
  check 'RW1: snapshot tree is recorded; origin removed; auto-gc disabled' $?
  status_after="$(git -C "$repo" status --short)"
  [[ "$status_after" == "$before" ]]
  check 'RW1: preparing the view does not change source status' $?

  review_workspace_cleanup >/dev/null 2>&1
  [[ ! -e "$work" && -d "$repo" ]]
  check 'RW1: cleanup removes only the disposable workspace' $?
  rm -rf "$d"
}

test_write_boundary() {
  echo '[RW2] the leg can write/commit in its clone while source stays read-only'
  local d repo before_status before_head before_refs clone out work
  d="$(mktemp -d)"; repo="$d/source"; new_repo "$repo"
  before_status="$(git -C "$repo" status --short)"
  before_head="$(git -C "$repo" rev-parse HEAD)"
  before_refs="$(git -C "$repo" show-ref 2>/dev/null || true)"
  REVIEW_WORKSPACE_BASE="$d/workspaces"
  review_workspace_prepare "$repo" oracle-write >/dev/null 2>&1 || {
    bad 'RW2: helper prepares the writable clone'; rm -rf "$d"; return;
  }
  clone="$(review_workspace_repo)"; work="$REVIEW_WORKSPACE_DIR"; out="$d/result"

  "$BIN/ro-repo-exec" "$repo" -- bash -c '
    work=BLOCKED; source=BLOCKED; commit=BLOCKED
    if printf clone > "$1/leg-output.txt"; then work=WROTE; fi
    git -C "$1" add leg-output.txt >/dev/null 2>&1 \
      && git -C "$1" -c user.email=t@example.invalid -c user.name=t commit -qm leg \
      && git -C "$1" tag leg-tag \
      && commit=WROTE
    if printf source > "$2/SOURCE_LEAK" 2>/dev/null; then source=WROTE; fi
    printf "work=%s\nsource=%s\ncommit=%s\n" "$work" "$source" "$commit" > "$3"
  ' _ "$clone" "$repo" "$out" >/dev/null 2>&1
  local rc=$?
  [[ $rc -eq 0 && -s "$out" \
     && "$(sed -n 's/^work=//p' "$out")" == WROTE \
     && "$(sed -n 's/^source=//p' "$out")" == BLOCKED \
     && "$(sed -n 's/^commit=//p' "$out")" == WROTE ]]
  check 'RW2: same leg writes and commits in clone but cannot write source' $?
  [[ ! -e "$repo/SOURCE_LEAK" \
     && "$(git -C "$repo" status --short)" == "$before_status" \
     && "$(git -C "$repo" rev-parse HEAD)" == "$before_head" \
     && "$(git -C "$repo" show-ref 2>/dev/null || true)" == "$before_refs" ]]
  check 'RW2: source content, status, HEAD and refs are unchanged' $?
  review_workspace_cleanup >/dev/null 2>&1
  [[ ! -e "$work" ]]; check 'RW2: writable clone is discarded after the leg' $?
  rm -rf "$d"
}

test_parallel_isolation() {
  echo '[RW3] concurrent legs receive distinct clones with the same snapshot'
  local d repo release p1 p2 r1 r2 i
  d="$(mktemp -d)"; repo="$d/source"; new_repo "$repo"
  release="$d/release"; r1="$d/one"; r2="$d/two"
  _rw_worker() { # leg marker result ready
    local leg="$1" marker="$2" result="$3" ready="$4"
    (
      . "$HELPER"
      REVIEW_WORKSPACE_BASE="$d/workspaces"
      review_workspace_prepare "$repo" "$leg" >/dev/null 2>&1 || exit 20
      local clone; clone="$(review_workspace_repo)"
      printf '%s\n%s\n%s\n' "$clone" "$REVIEW_SNAPSHOT_TREE" "$REVIEW_WORKSPACE_DIR" > "$result"
      printf '%s\n' "$marker" > "$clone/$marker"
      : > "$ready"
      for i in $(seq 1 200); do [[ -e "$release" ]] && break; sleep 0.02; done
      review_workspace_cleanup >/dev/null 2>&1
    )
  }
  _rw_worker one ONLY_ONE "$r1" "$d/ready1" & p1=$!
  _rw_worker two ONLY_TWO "$r2" "$d/ready2" & p2=$!
  for i in $(seq 1 200); do
    [[ -e "$d/ready1" && -e "$d/ready2" ]] && break
    ! kill -0 "$p1" 2>/dev/null && break
    ! kill -0 "$p2" 2>/dev/null && break
    sleep 0.02
  done
  local c1 c2 t1 t2 w1 w2
  c1="$(sed -n '1p' "$r1" 2>/dev/null)"; t1="$(sed -n '2p' "$r1" 2>/dev/null)"; w1="$(sed -n '3p' "$r1" 2>/dev/null)"
  c2="$(sed -n '1p' "$r2" 2>/dev/null)"; t2="$(sed -n '2p' "$r2" 2>/dev/null)"; w2="$(sed -n '3p' "$r2" 2>/dev/null)"
  [[ -n "$c1" && -n "$c2" && "$c1" != "$c2" && "$t1" == "$t2" ]]
  check 'RW3: parallel paths differ and snapshot tree ids match' $?
  [[ -e "$c1/ONLY_ONE" && ! -e "$c1/ONLY_TWO" \
     && -e "$c2/ONLY_TWO" && ! -e "$c2/ONLY_ONE" \
     && ! -e "$repo/ONLY_ONE" && ! -e "$repo/ONLY_TWO" ]]
  check 'RW3: per-leg markers do not cross and never reach source' $?
  : > "$release"; wait "$p1"; local q1=$?; wait "$p2"; local q2=$?
  [[ $q1 -eq 0 && $q2 -eq 0 && ! -e "$w1" && ! -e "$w2" ]]
  check 'RW3: both parallel workers clean their own workspace' $?
  rm -rf "$d"
}

test_source_race_and_cleanup_guard() {
  echo '[RW4] a changing source and unsafe cleanup target both fail closed'
  local d repo fake real_git count rc actual
  d="$(mktemp -d)"; repo="$d/source"; new_repo "$repo"
  fake="$d/bin"; mkdir -p "$fake"; real_git="$(command -v git)"; count="$d/count"
  cat > "$fake/git" <<'GIT_STUB'
#!/usr/bin/env bash
set -u
if [[ " $* " == *" write-tree "* ]]; then
  out="$("$REAL_GIT" "$@")"; rc=$?
  n=0; [[ -f "$RACE_COUNT" ]] && read -r n < "$RACE_COUNT"
  n=$((n+1)); printf '%s\n' "$n" > "$RACE_COUNT"
  [[ $n -eq 1 ]] && printf 'changed-between-scans\n' >> "$RACE_SOURCE/modified.txt"
  printf '%s\n' "$out"; exit "$rc"
fi
exec "$REAL_GIT" "$@"
GIT_STUB
  chmod +x "$fake/git"
  REVIEW_WORKSPACE_BASE="$d/workspaces"
  PATH="$fake:$PATH" REAL_GIT="$real_git" RACE_COUNT="$count" RACE_SOURCE="$repo" \
    review_workspace_prepare "$repo" race >/dev/null 2>&1
  rc=$?
  [[ $rc -ne 0 && ! -e "${REVIEW_WORKSPACE_DIR:-/definitely/missing}" ]]
  check 'RW4: two different source tree ids abort dispatch and clean the partial clone' $?

  # Fresh success, then corrupt the remembered target.  Cleanup must validate
  # containment instead of trusting a mutable shell variable.
  REVIEW_WORKSPACE_BASE="$d/safe-workspaces"
  review_workspace_prepare "$repo" cleanup >/dev/null 2>&1
  rc=$?; actual="${REVIEW_WORKSPACE_DIR:-}"
  if [[ $rc -ne 0 ]]; then
    bad 'RW4: setup for cleanup containment succeeds'
  else
    REVIEW_WORKSPACE_DIR="$repo"
    review_workspace_cleanup >/dev/null 2>&1; rc=$?
    [[ $rc -ne 0 && -d "$repo" ]]
    check 'RW4: cleanup refuses a source/out-of-root target' $?
    REVIEW_WORKSPACE_DIR="$actual"
    review_workspace_cleanup >/dev/null 2>&1
  fi
  rm -rf "$d"
}

test_gitlink_fails_closed() {
  echo '[RW5] gitlinks/submodules are rejected until their isolation is defined'
  local d repo oid rc
  d="$(mktemp -d)"; repo="$d/source"; new_repo "$repo"
  oid="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" update-index --add --cacheinfo "160000,$oid,vendor/sub"
  REVIEW_WORKSPACE_BASE="$d/workspaces"
  review_workspace_prepare "$repo" gitlink >/dev/null 2>&1; rc=$?
  [[ $rc -ne 0 ]]
  check 'RW5: source containing a gitlink is refused' $?
  rm -rf "$d"
}

test_wrapper_helper_failure() {
  echo '[RW6] wrapper does not invoke a model when workspace preparation fails'
  local d b repo rc
  d="$(mktemp -d)"; b="$d/bin"; repo="$d/source"; mkdir -p "$b"; new_repo "$repo"
  cp "$BIN/submimo" "$BIN/_my-review-gate.sh" "$BIN/_review-home-guard.sh" "$b/"
  cat > "$b/_review-workspace.sh" <<'HELPER_STUB'
review_workspace_prepare() { return 78; }
review_workspace_repo() { return 78; }
review_workspace_cleanup() { return 0; }
HELPER_STUB
  cat > "$b/ro-repo-exec" <<'RO_STUB'
#!/usr/bin/env bash
repo="$1"; shift 2
exec "$@"
RO_STUB
  cat > "$b/mimo" <<'MODEL_STUB'
#!/usr/bin/env bash
printf called > "$MODEL_COUNT"
echo 'Conclusion: PASS'
MODEL_STUB
  chmod +x "$b/ro-repo-exec" "$b/mimo"
  printf '# review\n' > "$d/task.md"
  env PATH="$b:$PATH" MODEL_COUNT="$d/model-called" REVIEW_NO_MY_REVIEW=1 \
    MIMO_REVIEW_HOME="$d/mimo-home" \
    bash "$b/submimo" review "$d/task.md" "$d/out.log" "$repo" >/dev/null 2>&1
  rc=$?
  [[ $rc -ne 0 && ! -e "$d/model-called" ]]
  check 'RW6: helper failure returns nonzero and model call count stays zero' $?
  rm -rf "$d"
}

echo '=== review workspace oracle ==='
if [[ ! -f "$HELPER" ]]; then
  bad "RW1: helper exists ($HELPER)"
  bad 'RW2: writable isolated snapshot is available'
  bad 'RW3: concurrent review workspaces are isolated'
  bad 'RW4/RW5: race, cleanup and gitlink failures are closed'
else
  # shellcheck source=../bin/_review-workspace.sh
  . "$HELPER"
  test_snapshot_view
  test_write_boundary
  test_parallel_isolation
  test_source_race_and_cleanup_guard
  test_gitlink_fails_closed
fi
test_wrapper_helper_failure

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
