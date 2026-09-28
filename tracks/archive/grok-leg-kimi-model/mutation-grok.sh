#!/usr/bin/env bash
# 手工变异:GPT 写的 test_subgrok.py 是否咬得住 subgrok / _grok-stream.py 里的每道守卫。
# 判据是执行腿自己写的(没有「判据先行」的红收据)⇒ 用变异当补偿控制。
# 每个变异:改一行实现 → 确认真改上了 → 跑判据 → 要求红且红在指名的测试上 → 恢复。
# 退出码:0 全部咬住;1 有变异漏网或红错地方;2 前置不满足/变异没改上(量具坏了,不算结论)。
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2
IMPL=(bin/subgrok bin/_grok-stream.py)
[[ -z "$(git status --porcelain -- "${IMPL[@]}")" ]] || { echo "实现文件有未提交改动,拒跑"; exit 2; }
trap 'git checkout -q -- "${IMPL[@]}"' EXIT

escaped=0
mutant() {  # mutant <名字> <文件> <原文> <替换> <必须红的测试名>
  local name="$1" file="$2" old="$3" new="$4" want="$5" out rc
  python3 - "$file" "$old" "$new" <<'PY' || { echo "$name: 原文不唯一或找不到 ⇒ 量具坏了"; exit 2; }
import sys
p, old, new = sys.argv[1:]
s = open(p).read()
if s.count(old) != 1:
    sys.exit(1)
open(p, 'w').write(s.replace(old, new))
PY
  git diff --quiet -- "$file" && { echo "$name: 变异没改上 ⇒ 量具坏了"; exit 2; }
  out="$(python3 tests/test_subgrok.py 2>&1)"; rc=$?
  git checkout -q -- "$file"
  if [[ $rc -eq 0 ]]; then
    echo "❌ $name: 漏网(判据仍绿)"; escaped=1
  elif grep -qE "^(FAIL|ERROR): $want" <<< "$out"; then
    echo "✅ $name: 咬住($want)"
  else
    echo "❌ $name: 红了但没红在 $want 上"; grep -E '^(FAIL|ERROR): ' <<< "$out"; escaped=1
  fi
}

mutant M1-模型身份不校验 bin/_grok-stream.py \
  'identity_ok = models == {expected}' 'identity_ok = True' \
  test_empty_or_failed_or_wrong_model_never_succeeds
mutant M2-子代理文本当报告 bin/_grok-stream.py \
  'if event.get("parent_tool_use_id") is not None:' 'if False:' \
  test_decoder_rejects_tool_and_child_verdicts
mutant M3-不要求end_turn bin/_grok-stream.py \
  'and terminal.get("stop_reason") == "end_turn")' ')' \
  test_empty_or_failed_or_wrong_model_never_succeeds
mutant M4-超时不映射成timed_out bin/subgrok \
  'if [[ "$RC" == 124 || "$RC" == 137 ]]; then' 'if false; then' \
  test_timeout_preserves_report_without_coverage
mutant M5-不关联网搜索 bin/subgrok \
  ' --disable-web-search' '' \
  test_review_reads_dirty_snapshot_protects_source_and_cleans_home
mutant M6-不清理临时home bin/subgrok \
  'trap cleanup EXIT' 'trap - EXIT' \
  test_review_reads_dirty_snapshot_protects_source_and_cleans_home
mutant M7-不要求is_error为False bin/_grok-stream.py \
  'and terminal.get("is_error") is False' 'and True' \
  test_empty_or_failed_or_wrong_model_never_succeeds

mutant M8-只清测试点名的三个变量 bin/subgrok \
  '[[ "$_name" == GROK_* ]] && GROK_ENV_UNSET+=(-u "$_name")' \
  'case "$_name" in GROK_FOLDER_TRUST|GROK_CODE_XAI_API_KEY|GROK_WEB_FETCH) GROK_ENV_UNSET+=(-u "$_name") ;; esac' \
  test_caller_grok_env_and_repo_instruction_scans_do_not_reach_cli
mutant M9-不关规则文件扫描 bin/subgrok \
  '    GROK_CLAUDE_RULES_ENABLED=0 GROK_CURSOR_RULES_ENABLED=0 \' \
  '    \' \
  test_caller_grok_env_and_repo_instruction_scans_do_not_reach_cli

[[ -z "$(git status --porcelain -- "${IMPL[@]}")" ]] || { echo "恢复失败"; exit 2; }
exit "$escaped"
