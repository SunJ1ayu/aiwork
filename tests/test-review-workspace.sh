#!/usr/bin/env bash
# Oracle for per-review writable snapshots.  The implementation lives in
# bin/_review-workspace.sh; wrappers must fail closed when that helper cannot
# prepare a workspace.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

BIN="${TEST_REVIEW_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"
HELPER="${TEST_REVIEW_WORKSPACE_HELPER:-$BIN/_review-workspace.sh}"
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
  printf 'old-staged-only\n' > "$repo/staged-only.txt"
  printf 'delete-me\n' > "$repo/deleted.txt"
  printf 'ignored.cache\n' > "$repo/.gitignore"
  mkdir -p "$repo/nested"
  printf 'nested\n' > "$repo/nested/file.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm base

  printf 'new-modified\n' > "$repo/modified.txt"
  printf 'staged-version\n' > "$repo/staged.txt"
  git -C "$repo" add staged.txt
  printf 'working-version\n' >> "$repo/staged.txt"
  printf 'staged-only-version\n' > "$repo/staged-only.txt"
  git -C "$repo" add staged-only.txt
  git -C "$repo" show HEAD:staged-only.txt > "$repo/staged-only.txt"
  rm "$repo/deleted.txt"
  printf 'untracked\n' > "$repo/untracked.txt"
  printf 'must-not-copy\n' > "$repo/ignored.cache"
  printf 'info-only.cache\n' >> "$(git -C "$repo" rev-parse --path-format=absolute --git-path info/exclude)"
  printf 'must-not-copy\n' > "$repo/info-only.cache"
  printf 'global-only.cache\n' > "$repo/../source-global-excludes"
  # A repository-local relative core.excludesFile is resolved from the source
  # worktree by Git.  The helper must preserve that meaning even when its own
  # caller is somewhere else.
  git -C "$repo" config core.excludesFile ../source-global-excludes
  printf 'must-not-copy\n' > "$repo/global-only.cache"
}

test_snapshot_view() {
  echo '[RW1] snapshot carries the current source view, not ignored runtime state'
  local d repo before head work clone status_after
  d="$(mktemp -d)"; repo="$d/source"; new_repo "$repo"
  before="$(git -C "$repo" status --short)"
  head="$(git -C "$repo" rev-parse HEAD)"
  REVIEW_WORKSPACE_BASE="$d/workspaces"
  review_workspace_prepare "$repo/nested" oracle-view >/dev/null 2>&1
  local rc=$?
  check 'RW1: helper prepares a workspace' "$rc"
  if [[ $rc -ne 0 ]]; then rm -rf "$d"; return; fi
  work="$REVIEW_WORKSPACE_DIR"; clone="$(review_workspace_repo)"

  [[ "$(git -C "$clone" rev-parse HEAD 2>/dev/null)" == "$head" ]]
  check 'RW1: clone HEAD stays at the source HEAD' $?
  [[ "$REVIEW_SOURCE_REPO" == "$repo" ]]
  check 'RW1: a subdirectory input is normalized to the Git top-level' $?
  cmp -s "$repo/committed.txt" "$clone/committed.txt" \
    && cmp -s "$repo/modified.txt" "$clone/modified.txt" \
    && cmp -s "$repo/staged.txt" "$clone/staged.txt" \
    && cmp -s "$repo/staged-only.txt" "$clone/staged-only.txt" \
    && [[ "$(git -C "$clone" show :staged-only.txt 2>/dev/null)" == staged-only-version ]] \
    && [[ "$(git -C "$clone" diff --cached --name-only -- staged-only.txt)" == staged-only.txt ]] \
    && cmp -s "$repo/untracked.txt" "$clone/untracked.txt" \
    && [[ ! -e "$clone/deleted.txt" && ! -e "$clone/ignored.cache" \
       && ! -e "$clone/info-only.cache" && ! -e "$clone/global-only.cache" ]]
  check 'RW1: worktree plus staged-only index match; all source ignore channels stay absent' $?
  [[ -d "$clone/.git" && ! -f "$clone/.git" ]]
  check 'RW1: clone owns a real, independent .git directory' $?
  [[ "$REVIEW_SNAPSHOT_HEAD" == "$head" \
     && "$REVIEW_SNAPSHOT_OBJECT_FORMAT" == "$(git -C "$repo" rev-parse --show-object-format)" \
     && -n "${REVIEW_SNAPSHOT_TREE:-}" \
     && -n "${REVIEW_SNAPSHOT_INDEX_TREE:-}" \
     && -z "$(git -C "$clone" remote 2>/dev/null)" \
     && "$(git -C "$clone" config --get gc.auto 2>/dev/null)" == 0 ]]
  check 'RW1: full HEAD/object-format/index/worktree identity is exported; origin removed' $?
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

  REVIEW_WORKSPACE_BASE="$repo/in-source"
  review_workspace_prepare "$repo" unsafe-base >/dev/null 2>&1; rc=$?
  [[ $rc -ne 0 && ! -e "$repo/in-source" ]]
  check 'RW4: workspace base inside source is rejected before any source write' $?

  fake="$d/bin"; mkdir -p "$fake"; real_git="$(command -v git)"; count="$d/count"
  cat > "$fake/git" <<'GIT_STUB'
#!/usr/bin/env bash
set -u
if [[ " $* " == *" write-tree "* ]]; then
  out="$("$REAL_GIT" "$@")"; rc=$?
  n=0; [[ -f "$RACE_COUNT" ]] && read -r n < "$RACE_COUNT"
  n=$((n+1)); printf '%s\n' "$n" > "$RACE_COUNT"
  [[ $n -eq 2 ]] && printf 'changed-between-scans\n' >> "$RACE_SOURCE/modified.txt"
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
  echo '[RW6] no wrapper invokes a model when workspace preparation fails'
  local d b repo rc mimo_rc deepseek_rc glm_rc kimi_rc
  d="$(mktemp -d)"; b="$d/bin"; repo="$d/source"; mkdir -p "$b"; new_repo "$repo"
  cp "$BIN/submimo" "$BIN/_my-review-gate.sh" "$BIN/_review-home-guard.sh" "$BIN/_review-workspace.sh" "$BIN/_review_delivery.py" "$BIN/aiwork-config" "$BIN/_aiwork_config.py" "$BIN/_review_result.py"    "$BIN/subagent"    "$BIN/subdeepseek-agent" "$BIN/subglm-agent" \
     "$BIN/subkimi" "$BIN/_my-review-gate.sh" "$BIN/_review-home-guard.sh" "$b/"
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
printf mimo > "$MODEL_COUNT"
echo 'Conclusion: PASS'
MODEL_STUB
  cat > "$b/claude" <<'MODEL_STUB'
#!/usr/bin/env bash
printf claude > "$MODEL_COUNT"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Conclusion: PASS"}]}}'
MODEL_STUB
  cat > "$b/opencode" <<'MODEL_STUB'
#!/usr/bin/env bash
printf opencode > "$MODEL_COUNT"
echo 'Conclusion: PASS'
MODEL_STUB
  cat > "$b/kimi" <<'MODEL_STUB'
#!/usr/bin/env bash
printf kimi > "$MODEL_COUNT"
echo 'Conclusion: PASS'
MODEL_STUB
  cat > "$b/node" <<'MODEL_STUB'
#!/usr/bin/env bash
exit 2
MODEL_STUB
  chmod +x "$b/ro-repo-exec" "$b/mimo" "$b/claude" "$b/opencode" "$b/kimi" "$b/node"
  printf '# review\n' > "$d/task.md"

  env PATH="$b:$PATH" MODEL_COUNT="$d/model-called" REVIEW_NO_MY_REVIEW=1 \
    MIMO_REVIEW_HOME="$d/mimo-home" \
    bash "$b/submimo" review "$d/task.md" "$d/out.log" "$repo" >/dev/null 2>&1
  mimo_rc=$?
  [[ $mimo_rc -ne 0 && ! -e "$d/model-called" ]]
  check 'RW6: submimo helper failure is nonzero with zero model calls' $?

  env PATH="$b:$PATH" MODEL_COUNT="$d/model-called" REVIEW_NO_MY_REVIEW=1 \
    DEEPSEEK_API_KEY=test \
    bash "$b/subdeepseek-agent" review "$d/task.md" "$d/deepseek.log" "$repo" >/dev/null 2>&1
  deepseek_rc=$?
  [[ $deepseek_rc -ne 0 && ! -e "$d/model-called" ]]
  check 'RW6: Claude-base helper failure is nonzero with zero model calls' $?

  env PATH="$b:$PATH" MODEL_COUNT="$d/model-called" REVIEW_NO_MY_REVIEW=1 \
    ZHIPU_API_KEY=test OPENCODE_REVIEW_HOME="$d/opencode-home" \
    bash "$b/subglm-agent" review "$d/task.md" "$d/glm.log" "$repo" >/dev/null 2>&1
  glm_rc=$?
  [[ $glm_rc -ne 0 && ! -e "$d/model-called" ]]
  check 'RW6: OpenCode-base helper failure is nonzero with zero model calls' $?

  mkdir -p "$d/kimi-home/hooks" "$d/kimi-home/credentials"
  printf '[hooks]\n' > "$d/kimi-home/config.toml"
  printf 'guard\n' > "$d/kimi-home/hooks/guard.mjs"
  printf '{}\n' > "$d/kimi-home/credentials/kimi-code.json"
  env PATH="$b:$PATH" MODEL_COUNT="$d/model-called" REVIEW_NO_MY_REVIEW=1 \
    KIMI_REVIEW_HOME="$d/kimi-home" \
    bash "$b/subkimi" review "$d/task.md" "$d/kimi.log" "$repo" >/dev/null 2>&1
  kimi_rc=$?
  [[ $kimi_rc -ne 0 && ! -e "$d/model-called" ]]
  check 'RW6: Kimi helper failure is nonzero with zero model calls' $?
  rm -rf "$d"
}

test_mutation_sensitivity() {
  echo '[RW7] oracle rejects direct-source and shared-clone mutations'
  local d direct fake rc real_mktemp
  d="$(mktemp -d)"; direct="$d/direct-source.sh"; fake="$d/bin"; mkdir -p "$fake"

  # Mutation 1: preparation appears successful but reports SOURCE as the model
  # repo. RW2 must reject it because the "work" write is blocked together with
  # the source write.
  sed '/^  REVIEW_SNAPSHOT_TREE="\$tree1"$/a\  REVIEW_WORK_REPO="$REVIEW_SOURCE_REPO"' \
    "$HELPER" > "$direct"
  TEST_REVIEW_WORKSPACE_CASE=write-boundary TEST_REVIEW_WORKSPACE_HELPER="$direct" \
    bash "$0" > "$d/direct.out" 2>&1
  rc=$?
  [[ $rc -ne 0 ]] && grep -q 'FAIL: RW2: same leg writes and commits' "$d/direct.out"
  check 'RW7: mutation direct-source makes the write-boundary oracle red' $?

  # Mutation 2: force every helper mktemp call to return one shared directory.
  # At least one parallel leg collides and RW3 must go red; a green result would
  # mean the oracle cannot detect cross-leg reuse.
  real_mktemp="$(command -v mktemp)"
  cat > "$fake/mktemp" <<'MKTEMP_STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == -d && "${2:-}" == *XXXXXXXX ]]; then
  mkdir -p "$MUT_SHARED"
  printf '%s\n' "$MUT_SHARED"
  exit 0
fi
exec "$REAL_MKTEMP" "$@"
MKTEMP_STUB
  chmod +x "$fake/mktemp"
  PATH="$fake:$PATH" REAL_MKTEMP="$real_mktemp" MUT_SHARED="$d/shared" \
    TEST_REVIEW_WORKSPACE_CASE=parallel-isolation TEST_REVIEW_WORKSPACE_HELPER="$HELPER" \
    bash "$0" > "$d/shared.out" 2>&1
  rc=$?
  [[ $rc -ne 0 ]] && grep -q 'FAIL: RW3:' "$d/shared.out"
  check 'RW7: mutation shared-clone makes the parallel-isolation oracle red' $?
  rm -rf "$d"
}

_review_workspace_summary() {
  echo "=== total: $PASS passed, $FAIL failed ==="
  [[ $FAIL -eq 0 ]]
}

case "${TEST_REVIEW_WORKSPACE_CASE:-all}" in
  write-boundary)
    . "$HELPER"
    test_write_boundary
    _review_workspace_summary
    exit $?
    ;;
  parallel-isolation)
    . "$HELPER"
    test_parallel_isolation
    _review_workspace_summary
    exit $?
    ;;
  all) ;;
  *) echo "unknown TEST_REVIEW_WORKSPACE_CASE:${TEST_REVIEW_WORKSPACE_CASE}" >&2; exit 2 ;;
esac

test_delivery_binding() {
  echo '[RW8] 绑定 track 的评审必须带上交付指纹,且与工作树侧同解'
  local d repo rc facts result digest
  d="$(mktemp -d)"; repo="$d/source"; new_repo "$repo"
  mkdir -p "$repo/tracks/example"
  printf '# design\n' > "$repo/tracks/example/design.md"
  printf '# pending\n' > "$repo/tracks/example/verify.md"
  REVIEW_WORKSPACE_BASE="$d/workspaces"
  export AIWORK_REVIEW_TRACK=example
  review_workspace_prepare "$repo" oracle-delivery >/dev/null 2>&1
  rc=$?
  check 'RW8: 绑定 track 时仍能准备工作副本' "$rc"
  if [[ $rc -ne 0 ]]; then unset AIWORK_REVIEW_TRACK; rm -rf "$d"; return; fi

  # 交付视图有**两套扫描实现**:这里的 __scan_view(shell)和归档闸用的
  # delivery_fingerprint(python)。两边一旦不同解,binding 永远对不上 ⇒ 每一次归档
  # 都 BLOCK,而且要等两条腿派完才发现。所以在这里当场对一次账,别留给归档时才炸。
  digest="$(python3 "$BIN/_review_delivery.py" --repo "$repo" --track example --source working)"
  [[ -n "${REVIEW_DELIVERY_DIGEST:-}" && "$REVIEW_DELIVERY_DIGEST" == "$digest" ]]
  check 'RW8: 快照侧指纹 == 工作树侧指纹(两套扫描不许各走各的)' $?

  facts="$d/facts.json"; result="$d/result.json"
  AIWORK_REVIEW_FACTS_PATH="$facts" AIWORK_REVIEW_RESULT_BIN="$BIN/_review_result.py" \
    review_workspace_write_facts m m subscription >/dev/null 2>&1
  check 'RW8: 带 track 时 facts 写得出来' $?
  python3 "$BIN/_review_result.py" emit --result "$result" --facts "$facts" \
    --run-id rw8 --name submimo --family xiaomi --adapter submimo --exit-code 0 \
    --task-sha256 "sha256:$(printf 'task' | sha256sum | cut -d' ' -f1)" \
    --log "$facts" --duration-ms 1 >/dev/null 2>&1
  check 'RW8: 腿结果落盘' $?
  python3 - "$result" "$digest" <<'RW8PY'
import json, sys
subject = json.load(open(sys.argv[1], encoding="utf-8"))["subject"]
assert subject["manifest_version"] == 2, subject["manifest_version"]
assert subject["delivery"] == {"policy_version": 1, "track": "example",
                               "digest": sys.argv[2]}, subject
RW8PY
  check 'RW8: 指纹一路带到 subject 上(评审证据真绑住了交付内容)' $?

  # RW9:交付指纹必须**跨进程**可见,不能只在 sourced shell 里恰好看得见。
  # 现在 prepare 与 write_facts 由同一个 sourced shell 先后调用,所以
  # REVIEW_DELIVERY_DIGEST 即使没进 export 清单也照常工作 —— 那是"恰好可见",
  # 不是不变量(同族 6 个 REVIEW_SNAPSHOT_*/REVIEW_WORK_REPO 全都导出了,就它没有)。
  # 哪天某个 wrapper 把写 facts 挪进子进程,这条链会**静默**产出 v1 subject
  # (带 source、照样计入 coverage),归档端要等到比较时才响,而观测侧那时已经是
  # "看起来健康、其实没绑定" —— 正是本单要消灭的那一类失败。
  # 🔴 必须用**新 bash 进程**问它:subshell 不行 —— fork 会把非导出变量一起带过去,
  # 那样这条判据永远绿 = 白写。2026-09-09 由一条评审腿指出,主裁复核后钉住。
  local xfacts="$d/facts-xproc.json"
  env AIWORK_REVIEW_FACTS_PATH="$xfacts" AIWORK_REVIEW_RESULT_BIN="$BIN/_review_result.py" \
    bash -c '. "$1"; review_workspace_write_facts m m subscription' _ "$HELPER" >/dev/null 2>&1
  check 'RW9: 跨进程也写得出 facts(先钉住红不在别处)' $?
  python3 - "$xfacts" "$digest" <<'RW9PY'
import json, sys
facts = json.load(open(sys.argv[1], encoding="utf-8"))
assert facts.get("delivery") == {"policy_version": 1, "track": "example",
                                 "digest": sys.argv[2]}, facts.get("delivery")
RW9PY
  check 'RW9: 交付指纹跨进程可见(不许只靠 sourced shell 的全局变量)' $?

  unset AIWORK_REVIEW_TRACK
  review_workspace_cleanup >/dev/null 2>&1
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
  test_delivery_binding
fi
test_wrapper_helper_failure
[[ -f "$HELPER" ]] && test_mutation_sensitivity

_review_workspace_summary
