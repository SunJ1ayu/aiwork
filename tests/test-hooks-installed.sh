#!/usr/bin/env bash
# 判据:守卫**装没装**本身也要有人查(2026-08-06)。
#
# 出处:当天自查发现 `/root/aiwork` 这个仓**一个 pre-commit hook 都没有** ——
# 而 `bin/track-guard`、`bin/panel-review`、判据文件全住在这个仓里。
# 也就是说:规矩写得再对,在工具自己的家门口从来没生效过。
# 这是"守卫守错门"的第三例,而且比前两例更难看:**门根本没装锁**。
#
# hook 不进版本控制(`.git/hooks/` 是本地的),所以它没有任何 diff 能证明自己还在 ——
# 唯一能发现它掉了的办法就是**定期问一句**。这份判据挂在 `rust-check-review-tooling`
# 总跑上,就是那一问。
set -uo pipefail

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== hooks installed oracle ==="
for repo in /root/aiwork /root/.openclaw/workspace/projects/design-studio; do
  [[ -d "$repo/.git" ]] || continue
  hook="$repo/.git/hooks/pre-commit"
  name="$(basename "$repo")"
  if [[ -x "$hook" ]]; then ok "$name: 装了可执行的 pre-commit"; else bad "$name: **没装** pre-commit($hook)"; fi
  if [[ -f "$hook" ]] && grep -q "track-guard" "$hook"; then
    ok "$name: hook 确实调 track-guard"
  else
    bad "$name: hook 没调 track-guard(装了个别的东西 = 这条防线仍然是空的)"
  fi
done
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
