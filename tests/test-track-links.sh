#!/usr/bin/env bash
# 关键 commit 与具体 track 的绑定判据。主 agent 拥有，执行腿不许修改。
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

BIN="${TRACK_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"
LINK="$BIN/track-commit-msg"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

newrepo() {
  local d; d="$(mktemp -d)"
  (
    cd "$d"
    git init -q -b main
    git config user.email t@t
    git config user.name t
    mkdir -p bin tracks/current
    printf '#!/usr/bin/env bash\necho safe\n' > bin/ro-repo-exec
    printf '# Verify\n- Verdict: PASS\n- lane: high\n- 派给: 主 agent\n' > tracks/current/verify.md
    printf 'hello\n' > README.md
    git add -A
    git commit -qm init
  )
  printf '%s\n' "$d"
}

message() {  # message <path> [track]
  printf 'test commit\n' > "$1"
  [[ -n "${2:-}" ]] && printf '\nTrack: %s\n' "$2" >> "$1"
}

g1_ro_repo_exec_is_protected() {
  echo '[G1] ro-repo-exec 是判卷/隔离保护面'
  # shellcheck source=/root/aiwork/bin/_tooling-paths.sh
  . "$BIN/_tooling-paths.sh"
  is_judging_surface bin/ro-repo-exec
  check 'G1: ro-repo-exec 被 judging-surface 名单覆盖' $?
}

g2_commit_message_binds_exact_track() {
  echo '[G2] 关键 commit 必须通过 Track trailer 绑定到具体 active track'
  local d msg rc
  d="$(newrepo)"; msg="$d/msg"
  printf '# changed\n' >> "$d/bin/ro-repo-exec"
  git -C "$d" add bin/ro-repo-exec

  message "$msg"
  (cd "$d" && bash "$LINK" "$msg" >/dev/null 2>&1); rc=$?
  check 'G2: 没有 Track trailer ⇒ 拒绝' $([[ $rc -ne 0 ]]; echo $?)

  message "$msg" missing
  (cd "$d" && bash "$LINK" "$msg" >/dev/null 2>&1); rc=$?
  check 'G2: Track 指向不存在的轮次 ⇒ 拒绝' $([[ $rc -ne 0 ]]; echo $?)

  message "$msg" current
  (cd "$d" && bash "$LINK" "$msg" >/dev/null 2>&1); rc=$?
  check 'G2: Track 指向 active 轮次且 verify 已填 ⇒ 放行' $([[ $rc -eq 0 ]]; echo $?)
  rm -rf "$d"
}

g3_recent_verify_is_not_a_global_pass() {
  echo '[G3] 最近七天改过任意 verify 不能给无关关键 commit 发通行证'
  local d msg rc
  d="$(newrepo)"; msg="$d/msg"
  printf '\nrecent\n' >> "$d/tracks/current/verify.md"
  git -C "$d" add tracks/current/verify.md
  git -C "$d" commit -qm 'recent verify'
  printf '# changed after recent verify\n' >> "$d/bin/ro-repo-exec"
  git -C "$d" add bin/ro-repo-exec
  message "$msg"
  (cd "$d" && bash "$LINK" "$msg" >/dev/null 2>&1); rc=$?
  check 'G3: 有 recent verify 但没有 Track trailer ⇒ 仍然拒绝' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"
}

g4_unrelated_commit_is_quiet() {
  echo '[G4] 普通 commit 不要求 track，避免守卫噪音'
  local d msg rc
  d="$(newrepo)"; msg="$d/msg"
  printf 'world\n' >> "$d/README.md"
  git -C "$d" add README.md
  message "$msg"
  (cd "$d" && bash "$LINK" "$msg" >/dev/null 2>&1); rc=$?
  check 'G4: 普通 README 改动无 trailer ⇒ 放行' $([[ $rc -eq 0 ]]; echo $?)
  rm -rf "$d"
}

g5_history_audit_catches_bypass() {
  echo '[G5] 历史审计能发现用 --no-verify 留下的无 Track 关键 commit'
  local d rc
  d="$(newrepo)"
  printf '# bypassed\n' >> "$d/bin/ro-repo-exec"
  git -C "$d" add bin/ro-repo-exec
  git -C "$d" commit -qm 'bypassed guard'
  (cd "$d" && bash "$LINK" --audit HEAD^..HEAD >/dev/null 2>&1); rc=$?
  check 'G5: 无 trailer 的历史关键 commit ⇒ 审计红' $([[ $rc -ne 0 ]]; echo $?)

  git -C "$d" commit --amend -qm $'linked commit\n\nTrack: current'
  (cd "$d" && bash "$LINK" --audit HEAD^..HEAD >/dev/null 2>&1); rc=$?
  check 'G5: 历史关键 commit 有有效 Track trailer ⇒ 审计绿' $([[ $rc -eq 0 ]]; echo $?)
  rm -rf "$d"
}

g6_history_audit_catches_bypass_merge() {
  echo '[G6] 历史审计不能跳过 merge commit'
  local d rc
  d="$(newrepo)"
  git -C "$d" switch -qc feature
  printf '# feature\n' >> "$d/bin/ro-repo-exec"
  git -C "$d" add bin/ro-repo-exec
  git -C "$d" commit -qm 'feature changes judging surface'
  git -C "$d" switch -q main
  printf 'main\n' >> "$d/README.md"
  git -C "$d" add README.md
  git -C "$d" commit -qm 'main moves too'
  git -C "$d" merge -q --no-ff feature -m 'bypassed merge guard'

  (cd "$d" && bash "$LINK" --audit 'HEAD^!' >/dev/null 2>&1); rc=$?
  check 'G6: 无 trailer 的关键 merge commit ⇒ 审计红' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"
}

echo '=== track-link oracle ==='
g1_ro_repo_exec_is_protected
g2_commit_message_binds_exact_track
g3_recent_verify_is_not_a_global_pass
g4_unrelated_commit_is_quiet
g5_history_audit_catches_bypass
g6_history_audit_catches_bypass_merge
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
