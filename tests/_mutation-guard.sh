#!/usr/bin/env bash
# Shared lifecycle guard for mutation runners.
#
# Caller contract:
#   ROOT=/absolute/repo
#   TARGETS=(/absolute/file ...)
#   mutation_guard_start "stable-name"
#
# This owns the pristine backup, durable inflight marker, and signal cleanup.
# Restore failure deliberately keeps both backup and marker: silence would make
# the next run diagnose a deliberately-mutated implementation as a product bug.

restore() {
  local f failed=0
  for f in "${TARGETS[@]}"; do
    cp -f "$BACKUP/$(basename "$f")" "$f" || failed=1
  done
  return "$failed"
}

_mutation_guard_finish() {
  [[ "${MUTATION_GUARD_FINISHED:-0}" -eq 0 ]] || return 0
  MUTATION_GUARD_FINISHED=1

  local restored=0
  restore || restored=1
  if [[ -n "${MUTATION_GUARD_ON_FINISH:-}" ]] \
      && declare -F "$MUTATION_GUARD_ON_FINISH" >/dev/null; then
    "$MUTATION_GUARD_ON_FINISH" || true
  fi

  if [[ "$restored" -eq 0 ]]; then
    rm -f "$INFLIGHT"
    rm -rf "$BACKUP"
    return 0
  fi

  echo "🔴 mutation guard:靶子还原失败;保留痕迹 $INFLIGHT 与备份 $BACKUP" >&2
  return 1
}

_mutation_guard_signal() {
  local sig="$1"
  _mutation_guard_finish || true
  trap - EXIT INT TERM HUP
  kill -s "$sig" "$$"
}

mutation_guard_start() {
  local name="${1:-}" f
  [[ -n "$name" ]] || { echo "mutation guard:缺稳定名称" >&2; exit 2; }
  [[ -n "${ROOT:-}" && "${#TARGETS[@]}" -gt 0 ]] \
    || { echo "mutation guard:调用前必须设置 ROOT 与 TARGETS" >&2; exit 2; }

  STATE_DIR="${MUTATION_STATE_DIR:-$ROOT/.mutation-state}"
  INFLIGHT="$STATE_DIR/mutation-$name.inflight"
  mkdir -p "$STATE_DIR" || exit 2
  if [[ -e "$INFLIGHT" ]]; then
    echo "🔴 上一轮红检**没跑完就被砍了**(痕迹:$INFLIGHT)⇒ 拒绝再跑。"
    echo "   靶子文件可能还留着变异;先核对痕迹中的备份与当前 git diff。"
    echo "   确认恢复后删除 $INFLIGHT 再跑。"
    echo "   痕迹内容:"; sed 's/^/     /' "$INFLIGHT"
    exit 3
  fi
  if [[ -n "${MUTATION_SELFCHECK:-}" ]]; then
    echo "自检:没有未收尾的红检痕迹,可以跑。"
    exit 0
  fi

  declare -gA BEFORE=()
  for f in "${TARGETS[@]}"; do
    [[ -f "$f" ]] || { echo "mutation guard:靶子不存在:$f" >&2; exit 2; }
    BEFORE["$f"]="$(sha256sum "$f" | cut -d' ' -f1)"
  done
  BACKUP="$(mktemp -d)" || exit 2
  for f in "${TARGETS[@]}"; do
    cp "$f" "$BACKUP/$(basename "$f")" \
      || { rm -rf "$BACKUP"; echo "mutation guard:备份失败:$f" >&2; exit 2; }
  done
  { echo "started=$(date -Is) pid=$$"
    echo "backup=$BACKUP"
    for f in "${TARGETS[@]}"; do echo "pristine ${BEFORE[$f]} $f"; done
  } > "$INFLIGHT" || { rm -rf "$BACKUP"; exit 2; }

  MUTATION_GUARD_FINISHED=0
  trap '_mutation_guard_finish' EXIT
  trap '_mutation_guard_signal INT' INT
  trap '_mutation_guard_signal TERM' TERM
  trap '_mutation_guard_signal HUP' HUP
}
