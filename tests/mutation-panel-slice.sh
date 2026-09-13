#!/usr/bin/env bash
# 红检:把切片评审的实现**故意改坏**,看 test-panel-slice.sh / test-subcodex.sh 咬不咬得住。
#
# 判据全绿只说明"现在没红",不说明"改坏了会红"。这一单首轮实现就 82/0、31/0 全绿 ——
# 恰恰是最该怀疑的时候(本机记过账:永远绿的瞎断言、锚点过期、靶子名过期)。
# 每个变异点名**它该打红哪一条**;打不红 = 那条断言是摆设。锚点没命中也算漏网。
# 变异用 heredoc 喂 python(不走 python3 -c "...",嵌套引号会把反引号交给 shell 真执行)。
#
# ⚠️ 原地改 bin/ 下的文件:跑这个的时候**别的东西都不许读这些文件**(总闸、真跑的评审)。
set -uo pipefail
export ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLICE_ORACLE="$ROOT/tests/test-panel-slice.sh"
CODEX_ORACLE="$ROOT/tests/test-subcodex.sh"
TARGETS=("$ROOT/bin/panel-review" "$ROOT/bin/_panel-roster-lib.sh" "$ROOT/bin/_panel_slice.py"
         "$ROOT/bin/panel-slice" "$ROOT/bin/subcodex" "$ROOT/bin/_review_result.py")

. "$ROOT/tests/_mutation-guard.sh" || exit 2
mutation_guard_start "panel-slice"

BIT=0; MISS=0
echo "== 基线 =="
SLICE_BASE="$(bash "$SLICE_ORACLE" 2>&1)"
CODEX_BASE="$(bash "$CODEX_ORACLE" 2>&1)"
if grep -q "FAIL:" <<<"$SLICE_BASE$CODEX_BASE"; then
  echo "🔴 基线就不是全绿 —— 先把判据弄绿再红检"; grep "FAIL:" <<<"$SLICE_BASE$CODEX_BASE"; exit 2
fi
echo "  基线全绿:$(grep -c 'PASS:' <<<"$SLICE_BASE") + $(grep -c 'PASS:' <<<"$CODEX_BASE") 条"

mutate() {  # mutate <编号> <slice|codex> <该打红的断言关键字>   (python 从 stdin 喂)
  local id="$1" which="$2" target="$3" py out base oracle
  py="$(cat)"
  if [[ "$which" == codex ]]; then base="$CODEX_BASE"; oracle="$CODEX_ORACLE"; else base="$SLICE_BASE"; oracle="$SLICE_ORACLE"; fi
  # 一律 grep -F:断言名里有 `**`、括号、问号,当正则会静默匹配不上(2026-08-23 撞过)。
  if ! grep "PASS:" <<<"$base" | grep -qF -- "$target"; then
    echo "  [漏网] $id 的靶子「$target」在基线里不是一条断言 —— 靶子名过期"; MISS=$((MISS+1)); return
  fi
  restore
  if ! printf '%s' "$py" | python3 - ; then
    echo "  [漏网] $id 的锚点没命中 —— 锚点过期本身就是问题"; MISS=$((MISS+1)); restore; return
  fi
  out="$(bash "$oracle" 2>&1)"
  if grep "FAIL:" <<<"$out" | grep -qF -- "$target"; then
    echo "  [OK]   $id -> 「$target」如期红了"; BIT=$((BIT+1))
  else
    echo "  [漏网] $id -> 改坏了,而「$target」还是绿的 ⇒ 那条断言是摆设"; MISS=$((MISS+1))
  fi
  restore
}

# 共用的一段 python:在 <文件> 里把 <old> 恰好替换一次(没命中或命中多次 ⇒ 非零 = 锚点过期)
PYSUB='
import os, pathlib, sys
p = pathlib.Path(os.environ["ROOT"], os.environ["MUT_FILE"]); s = p.read_text()
old, new = os.environ["MUT_OLD"], os.environ["MUT_NEW"]
if s.count(old) != 1: sys.exit(1)
p.write_text(s.replace(old, new))
'
sub() {  # sub <编号> <slice|codex> <靶子> <文件> <old> <new>
  local id="$1" which="$2" target="$3"
  export MUT_FILE="$4" MUT_OLD="$5" MUT_NEW="$6"
  mutate "$id" "$which" "$target" <<<"$PYSUB"
}

echo "== 红检开始(切片评审)=="
sub M1 slice "S1: 每份腿结果契约版本=2" bin/panel-review \
  '  REVIEW_CONTRACT_VERSION=2' '  REVIEW_CONTRACT_VERSION=1'
sub M2 slice "S1: 各项家族两两不同" bin/_panel_slice.py \
  'pick = next((name for name in candidates if legs[name]["family"] not in used), None)' \
  'pick = next((name for name in candidates), None)'
sub M3 slice "S5: 3 个复核 > extra 余量 2 ⇒ 整批拒绝" bin/_panel_slice.py \
  '        if len(raw_checks) > remaining:' '        if False:'
sub M4 slice "S4: s1 第 2 次 PASS 之后,第 1 次的 BLOCK 仍在「未登记」里" bin/_panel_slice.py \
  'and a["verdict"] in UNACKNOWLEDGED_VERDICTS' 'and a is attempts[-1] and a["verdict"] in UNACKNOWLEDGED_VERDICTS'
sub M5 slice "S9: scoped 模式 agent 腿失败 ⇒ 不调聊天腿" bin/panel-review \
  '  [[ "$SCOPED_REVIEW" -eq 0 ]] || LEG_CHAT[$_leg]=""' '  :'
sub M6 slice "S1: 每条腿启动那一刻 plan.json 与自己的 reserved.json 都已落盘" bin/panel-slice \
  '  python3 "$HELPER" reserve --run-dir' '  : python3 "$HELPER" reserve --run-dir'
sub M7 slice "S9: 普通 --all 派满整个池,但角色腿一次都没被派" bin/_panel-roster-lib.sh \
  'for _panel_spec in "${PANEL_LEG_SPECS[@]}"; do' 'for _panel_spec in "${PANEL_LEG_SPECS[@]}" "${PANEL_ROLE_LEG_SPECS[@]}"; do'
sub M8 slice "S9: scoped 评审不推动普通轮换游标" bin/panel-review \
  'if [[ "$FORCE_ALL" -ne 1 && "$SCOPED_REVIEW" -eq 0 ]]; then' 'if [[ "$FORCE_ALL" -ne 1 ]]; then'
sub M9 slice "S7: 砍掉之后立刻看:有 unknown、没有一条被说成 failed" bin/_panel_slice.py \
  '"category": reserved["category"], "verdict": None, "state": "unknown",' \
  '"category": reserved["category"], "verdict": None, "state": "failed",'
sub M10 slice "S6: 新增未跟踪文件也算源码变了" bin/_panel_slice.py \
  '    for rel in untracked:' '    for rel in []:'
sub M11 slice "S5: 复核钉回出处同一家族 ⇒ 拒绝" bin/_panel_slice.py \
  '                    excluded |= item_families(run_dir, src, items)
            if raw.get("leg") is not None:' \
  '                    pass
            if raw.get("leg") is not None:'
sub M12 slice "S5: decide 不给理由 ⇒ 拒绝" bin/_panel_slice.py \
  '    if not args.reason or not args.reason.strip():' '    if False:'
sub M13 slice "S5: 同 id 不同内容的 finding ⇒ 拒绝" bin/_panel_slice.py \
  '                if old != new:' '                if False:'
sub M14 slice "S9: --scoped-review 与 --track 同时给 ⇒ 拒绝且零调用" bin/panel-review \
  '  if [[ -n "$TRACK_NAME" ]]; then
    echo "panel-review: --scoped-review cannot bind --track' \
  '  if false; then
    echo "panel-review: --scoped-review cannot bind --track'
sub M15 slice "S9: 非 scoped 模式不许 --pin-leg" bin/panel-review \
  'if [[ -n "$PIN_LEG" && "$SCOPED_REVIEW" -eq 0 ]]; then' 'if false; then'
sub M16 slice "S2: 默认整体腿 subcodex 被关掉 ⇒ 拒绝且零调用" bin/_panel_slice.py \
  '        if not healthy(legs, health, overall_leg):
            raise Refused("overall-leg"' \
  '        if False:
            raise Refused("overall-leg"'
sub M17 slice "S4: s2 失败 ⇒ incomplete" bin/_panel_slice.py \
  '        covered = any(a["state"] == COVERED_STATE for a in attempts)' \
  '        covered = bool(attempts)'
sub M18 slice "S1: 每份腿结果契约版本=2,旧覆盖谓词判否" bin/_review_result.py \
  'SUPPORTED_REVIEW_CONTRACTS = frozenset({REVIEW_CONTRACT_VERSION})' \
  'SUPPORTED_REVIEW_CONTRACTS = frozenset({REVIEW_CONTRACT_VERSION, SCOPED_REVIEW_CONTRACT_VERSION})'
sub M19 slice "S7: 还是 unknown 的项不许 retry" bin/_panel_slice.py \
  '        if latest["state"] == "unknown":' '        if False:'
sub M20 slice "S3: 自审文件在被评审仓内 ⇒ 拒绝且零调用" bin/_panel_slice.py \
  '        if inside(candidate, repo_real):' '        if False:'

echo "== 红检开始(GPT 整体腿 subcodex)=="
sub C1 codex "C1: --disable multi_agent(" bin/subcodex \
  '  --disable multi_agent --disable multi_agent_v2' '  --disable multi_agent_v2'
sub C2 codex "C1: 带 -c project_doc_max_bytes=0" bin/subcodex \
  '  -c project_doc_max_bytes=0 -c "model_reasoning_effort=$EFFORT"' '  -c "model_reasoning_effort=$EFFORT"'
sub C3 codex "C2: 非 gpt- 家族的模型名 ⇒ 拒绝且没调用 codex" bin/subcodex \
  '  [[ "$MODEL" =~ ^gpt-[A-Za-z0-9._-]+$ ]] || die "SUBCODEX_MODEL' '  true || die "SUBCODEX_MODEL'
sub C4 codex "C3: 额度耗尽被分型为 quota" bin/subcodex \
  "if grep -qE 'usage_limit_exceeded|hit your usage limit'" "if false && grep -qE 'usage_limit_exceeded|hit your usage limit'"
sub C5 codex "C4: 事件流报告的模型与请求不符时如实记下" bin/subcodex \
  '"$([[ "$MODE" == review ]] && echo "$VERDICT")" "" "$REPORTED" || exit 78' \
  '"$([[ "$MODE" == review ]] && echo "$VERDICT")" "" "$MODEL" || exit 78'
sub C6 codex "C1: 源仓物理只读(桩试写被拒)、副本可写" bin/subcodex \
  '  "$BIN_DIR/ro-repo-exec" "$SOURCE_REPO" -- timeout' '  timeout'
sub C7 codex "C4: 没写自审又没显式跳过 ⇒ review 拒绝且没调用 codex" bin/subcodex \
  'my_review_gate "$MODE" "$TASK_FILE" "$SOURCE_REPO" subcodex || exit 1' ':'
# C8~C11:2026-09-13 真跑证伪 `--disable multi_agent` 之后补的四件(子 agent 目录覆盖、离线核验、联网)
sub C8 codex 'C5: 派发带 -c web_search="disabled"' bin/subcodex \
  "  -c 'web_search=\"disabled\"'
" ''
sub C9 codex "C5: 派发带 -c model_catalog_json=<目录副本>" bin/subcodex \
  'CODEX_CFG+=(-c "model_catalog_json=\"$CATALOG\"")' ':'
sub C10 codex "C5: 离线核验仍看到 <multi_agent_role> ⇒ 拒跑" bin/subcodex \
  "|| [[ ! -s \"\$PREVIEW\" ]] || grep -q 'multi_agent_role' \"\$PREVIEW\"; then" \
  "|| [[ ! -s \"\$PREVIEW\" ]]; then"
sub C11 codex "C5: 模型不在 codex 模型目录里 ⇒ 拒跑" bin/subcodex \
  'sum(1 for m in entries if isinstance(m, dict) and m.get("slug") == model) != 1' 'False'

printf -- '---- 合计 咬住=%s 漏网=%s ----\n' "$BIT" "$MISS"
for f in "${TARGETS[@]}"; do
  cmp -s "$f" "$BACKUP/$(basename "$f")" || { echo "🔴 $f 没还原"; MISS=$((MISS+1)); }
done
[[ "$MISS" -eq 0 ]]
