#!/bin/bash
# 自攻 track preflight 的判据:几种"看着差不多、其实错"的实现,每一种判据都必须红。跑完无论如何恢复。
set -u
cd "$(git rev-parse --show-toplevel)"
files=(bin/track bin/track-record)
git diff --quiet -- "${files[@]}" || { echo "拒跑:${files[*]} 有未提交改动"; exit 2; }
trap 'git checkout -- "${files[@]}"' EXIT
bad=0
mutate() {  # $1=名字 $2=文件 $3=python 替换表达式(对 s 操作)$4=判据过滤(unittest 名字,空=全跑)
  git checkout -- "${files[@]}"
  python3 - "$2" "$3" <<'PY'
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read(); t = eval(expr)
assert t != s, "变异没改到任何东西(锚点失效)"
open(p, "w", encoding="utf-8").write(t)
PY
  [ $? -eq 0 ] || { echo "🔴 [$1] 变异没打上"; bad=1; return; }
  # shellcheck disable=SC2086
  if python3 tests/test_track_preflight.py $4 >/dev/null 2>&1; then
    echo "🔴 [$1] 判据仍然绿 ⇒ 问不住"; bad=1
  else
    echo "✅ [$1] 判据红"
  fi
}
mutate "预检里 worktree 判完不返回、照走删除" bin/track \
  's.replace("    echo \"  预检:标 OK 的树归档时会被收掉(预检不删)。\"\n    return 0\n", "    echo \"  预检:标 OK 的树归档时会被收掉(预检不删)。\"\n")' \
  "PreflightTest.test_p8b_clean_merged_tree_is_ok_and_still_there"
mutate "检查崩溃降格成 PENDING" bin/track \
  's.replace("pf_report ERROR decision", "pf_report PENDING decision")' \
  "PreflightTest.test_p7_checker_crash_is_error_not_pending"
mutate "decision 一挡就短路退出" bin/track \
  's.replace("pf_report BLOCK decision \"typed 事实不合法,归档一定拒\" \"$rec_out\"", "pf_report BLOCK decision \"typed 事实不合法,归档一定拒\" \"$rec_out\"; exit 1")' \
  "PreflightTest.test_p3_decision_block_and_other_block_both_reported"
mutate "已写 PASS 缺执行收据也算 PENDING" bin/track-record \
  's.replace("if not assumed or (exc.rule, exc.path) not in PREFLIGHT_PENDING:", "if (exc.rule, exc.path) not in PREFLIGHT_PENDING:")' \
  "PreflightTest.test_p10_decided_pass_without_execution_is_block_not_pending"
mutate "5a 对不上也只算 PENDING" bin/track \
  's.replace("pf_report BLOCK receipts \"verify.md 里粘的收据行", "pf_report PENDING receipts \"verify.md 里粘的收据行")' \
  "PreflightTest.test_p4b_pasted_receipt_without_evidence_blocks"
mutate "不假设 PASS、覆盖检查直接跳过" bin/track-record \
  's.replace("probe[\"outcome\"][\"verdict\"] = \"PASS\"", "pass")' \
  "PreflightTest.test_p11_bound_review_leaves_only_outcome_then_drift_is_pending_review"
mutate "预检输出冒充归档凭据" bin/track-record \
  's.replace("print(f\"track-record: status=legacy phase=preflight", "print(\"track-record: status=valid phase=archive\"); print(f\"track-record: status=legacy phase=preflight").replace("preflight_pending(\n            DecisionError(\"field.decided\"", "print(\"track-record: status=valid phase=archive\")\n        preflight_pending(\n            DecisionError(\"field.decided\"")' \
  "PreflightTest.test_p1_before_final_review_is_pending_not_blocked PreflightTest.test_p14_new_phase_does_not_leak_into_old_phases"
mutate "未知规则也放成 PENDING" bin/track-record \
  's.replace("if not assumed or (exc.rule, exc.path) not in PREFLIGHT_PENDING:", "if not assumed:")' \
  ""
mutate "不关 git 的顺手刷新 index" bin/track \
  's.replace("    export GIT_OPTIONAL_LOCKS=0\n", "")' \
  ""
git checkout -- "${files[@]}"; trap - EXIT
git diff --quiet -- "${files[@]}" && echo "== 已恢复(${files[*]} 与 HEAD 一致,git 说的)"
exit $bad
