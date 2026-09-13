#!/usr/bin/env bash
# subcodex oracle —— GPT 只读评审腿(track sliced-panel-review 的整体腿)。codex 是桩,
# 只读挂载 ro-repo-exec 是真的。
#
# 桩只证明「我们递给 codex 的参数长这样、结果被这样收尾」;`--disable multi_agent` 在真 codex
# 里是否真的关掉子 agent、`--ignore-user-config` 是否真的挡住插件/MCP,**这份判据证明不了**,
# 要靠真跑读 --json 事件流(verify.md 里单列)。
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

if [[ "${SUBCODEX_ENV_SCRUBBED:-}" != "1" ]]; then
  exec env -u SUBCODEX_MODEL -u SUBCODEX_TIMEOUT -u SUBCODEX_EFFORT -u CODEX_BIN \
    -u REVIEW_MY_REVIEW -u REVIEW_NO_MY_REVIEW -u AIWORK_REVIEW_FACTS_PATH -u AIWORK_REVIEW_RESULT_BIN \
    -u AIWORK_REVIEW_TRACK -u REVIEW_WORKSPACE_BASE -u GATE_PANEL_DISPATCH \
    SUBCODEX_ENV_SCRUBBED=1 bash "$0" "$@"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

echo "=== subcodex oracle ==="
d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
mkdir -p "$d/bin" "$d/fake" "$d/ws" "$d/cap"
for f in subcodex codex-model ro-repo-exec _review-workspace.sh _my-review-gate.sh _review_result.py _review-home-guard.sh; do
  [[ -e "$ROOT/bin/$f" ]] && cp "$ROOT/bin/$f" "$d/bin/"
done
check "C0: bin/subcodex 与单源模型文件 bin/codex-model 都在" \
  $([[ -x "$ROOT/bin/subcodex" && -s "$ROOT/bin/codex-model" ]]; echo $?)
MODEL="$(cat "$ROOT/bin/codex-model" 2>/dev/null)"

cat > "$d/fake/codex" <<'EOF'
#!/usr/bin/env bash
cap="$CODEX_TEST_CAPTURE"
printf '%s\n' "$@" > "$cap.argv"
pwd -P > "$cap.pwd"
cat > "$cap.stdin"
{ if touch "$CODEX_TEST_SOURCE/PWNED" 2>/dev/null; then echo src-writable; else echo src-readonly; fi
  if touch ./clone-write-probe 2>/dev/null; then echo clone-writable; else echo clone-readonly; fi
} > "$cap.writes"
out=""; model=""; prev=""
for a in "$@"; do
  [[ "$prev" == "-o" || "$prev" == "--output-last-message" ]] && out="$a"
  [[ "$prev" == "-m" || "$prev" == "--model" ]] && model="$a"
  prev="$a"
done
case "${CODEX_TEST_MODE:-pass}" in
  pass)
    printf '{"type":"thread.started","model":"%s"}\n' "${CODEX_TEST_REPORTED:-$model}"
    printf 'Findings: none.\nConclusion: PASS\n' > "$out" ;;
  explore)
    printf '{"type":"thread.started","model":"%s"}\n' "$model"
    printf 'Direction: keep it simple\n' > "$out" ;;
  noverdict)
    printf 'I looked around.\n' > "$out" ;;
  quota)
    printf '{"type":"error","message":"You have hit your usage limit.","codex_error_info":"usage_limit_exceeded"}\n'
    exit 1 ;;
  sleep)
    sleep 30 ;;
esac
exit 0
EOF
chmod +x "$d/fake/codex"

( cd "$d" && mkdir repo && cd repo && git init -q -b main && git config user.email t@t \
  && git config user.name t && printf 'x\n' > app.txt && git add -A && git commit -qm init )
printf '# task\nTASK_SENTINEL_c0d3\n' > "$d/task.md"

sc() {  # sc <capture-name> <subcodex args...>  (env 由调用者前缀)
  local name="$1"; shift
  rm -f "$d/cap/$name".*
  CODEX_TEST_CAPTURE="$d/cap/$name" CODEX_TEST_SOURCE="$d/repo" PATH="$d/fake:$PATH" \
    REVIEW_WORKSPACE_BASE="$d/ws" AIWORK_REVIEW_RESULT_BIN="$d/bin/_review_result.py" \
    AIWORK_REVIEW_FACTS_PATH="$d/cap/$name.facts.json" \
    bash "${SC_BIN:-$d/bin}/subcodex" "$@"
}
argv_has() { grep -qxF -- "$2" "$d/cap/$1.argv" 2>/dev/null; }
argv_pair() {  # argv_pair <cap> <flag> <value>
  awk -v f="$2" -v v="$3" 'prev==f && $0==v {found=1} {prev=$0} END{exit found?0:1}' "$d/cap/$1.argv" 2>/dev/null
}
facts() {  # facts <cap> <python expr over f>
  python3 - "$d/cap/$1.facts.json" "$2" <<'PY'
import json, sys
try:
    f = json.load(open(sys.argv[1])); sys.exit(0 if eval(sys.argv[2], {"f": f}) else 1)
except Exception as exc:
    print(f"    (facts: {type(exc).__name__}: {exc})", file=sys.stderr); sys.exit(1)
PY
}

echo "[C1] review:参数面、只读源仓、可写副本、裁决与 facts"
REVIEW_NO_MY_REVIEW=1 sc c1 review "$d/task.md" "$d/c1.log" "$d/repo" >/dev/null 2>"$d/c1.err"; rc=$?
check "C1: 正常 review rc=0" $([[ $rc -eq 0 ]]; echo $?)
[[ $rc -eq 0 ]] || sed 's/^/    | /' "$d/c1.err" | tail -5
argv_has c1 exec; check "C1: 走 codex exec" $?
argv_pair c1 -m "$MODEL"; check "C1: -m 取自 bin/codex-model($MODEL)" $?
argv_pair c1 -c project_doc_max_bytes=0; check "C1: 带 -c project_doc_max_bytes=0(不吞仓里的 AGENTS.md)" $?
argv_has c1 --ignore-user-config; check "C1: --ignore-user-config(不加载业主的插件/MCP/配置)" $?
argv_has c1 --ephemeral; check "C1: --ephemeral(不往业主的会话历史里落评审会话)" $?
argv_pair c1 --disable multi_agent; check "C1: --disable multi_agent(腿内不许再派子 agent)" $?
argv_pair c1 --disable multi_agent_v2; check "C1: --disable multi_agent_v2" $?
argv_has c1 --json; check "C1: --json 事件流留证" $?
grep -q 'TASK_SENTINEL_c0d3' "$d/cap/c1.stdin" 2>/dev/null
check "C1: 任务书经 stdin 递给 codex(不走 argv,躲开 128KiB 单参数上限)" $?
_pwd="$(cat "$d/cap/c1.pwd" 2>/dev/null)"
check "C1: codex 的工作目录是 ws 下的可丢弃副本,不是源仓" \
  $([[ -n "$_pwd" && "$_pwd" != "$d/repo" && "$_pwd" == "$(cd "$d/ws" && pwd -P)"/* ]]; echo $?)
check "C1: 源仓物理只读(桩试写被拒)、副本可写" \
  $([[ "$(cat "$d/cap/c1.writes" 2>/dev/null)" == $'src-readonly\nclone-writable' && ! -e "$d/repo/PWNED" ]]; echo $?)
grep -q '^Conclusion: PASS' "$d/c1.log" 2>/dev/null; check "C1: 报告落进 LOG_FILE" $?
[[ -s "$d/c1.stream.jsonl" ]]; check "C1: 事件流另存 <log 去掉 .log>.stream.jsonl" $?
facts c1 "f['model']['requested'] == f['model']['invoked'] == '$MODEL' and f['model']['reported'] == '$MODEL' and f['view'] == {'delivery_state':'complete','mode':'full_snapshot'} and f['process_state'] == 'exited' and f['verdict'] == 'PASS'"
check "C1: facts:请求/调用/上报模型一致、完整快照视野、exited、PASS" $?
check "C1: 跑完可丢弃副本已清理" $([[ -z "$(ls -A "$d/ws" 2>/dev/null)" ]]; echo $?)

echo "[C2] 模型单源 + 单次覆盖 + 非法值不派发"
cp -r "$d/bin" "$d/bin2"; printf 'gpt-fixture-next\n' > "$d/bin2/codex-model"
SC_BIN="$d/bin2" REVIEW_NO_MY_REVIEW=1 sc c2a review "$d/task.md" "$d/c2a.log" "$d/repo" >/dev/null 2>&1
argv_pair c2a -m gpt-fixture-next; check "C2: 只改 codex-model 一行 ⇒ 实际 -m 跟着变" $?
SUBCODEX_MODEL=gpt-override REVIEW_NO_MY_REVIEW=1 sc c2b review "$d/task.md" "$d/c2b.log" "$d/repo" >/dev/null 2>&1
argv_pair c2b -m gpt-override; check "C2: SUBCODEX_MODEL 单次覆盖" $?
printf '\n' > "$d/bin2/codex-model"
SC_BIN="$d/bin2" REVIEW_NO_MY_REVIEW=1 sc c2c review "$d/task.md" "$d/c2c.log" "$d/repo" >/dev/null 2>"$d/c2c.err"; rc=$?
check "C2: 模型文件为空 ⇒ 拒绝且没调用 codex(理由点名 codex-model)" \
  $([[ $rc -ne 0 && ! -e "$d/cap/c2c.argv" ]] && grep -q 'codex-model' "$d/c2c.err"; echo $?)
SUBCODEX_MODEL=kimi-code/k3 REVIEW_NO_MY_REVIEW=1 sc c2d review "$d/task.md" "$d/c2d.log" "$d/repo" >/dev/null 2>"$d/c2d.err"; rc=$?
check "C2: 非 gpt- 家族的模型名 ⇒ 拒绝且没调用 codex(理由点名 gpt-)" \
  $([[ $rc -ne 0 && ! -e "$d/cap/c2d.argv" ]] && grep -q 'gpt-' "$d/c2d.err"; echo $?)

echo "[C3] 无裁决 / 额度耗尽 / 超时:都不许冒充完成的评审"
CODEX_TEST_MODE=noverdict REVIEW_NO_MY_REVIEW=1 sc c3 review "$d/task.md" "$d/c3.log" "$d/repo" >/dev/null 2>&1; rc=$?
check "C3: 没有裁决行 ⇒ rc≠0,但报告原样留着" $([[ $rc -ne 0 ]] && grep -q 'I looked around' "$d/c3.log"; echo $?)
facts c3 "f['verdict'] == 'UNKNOWN' and f['failure_kind'] == 'no_verdict'"
check "C3: facts 记 UNKNOWN / no_verdict" $?
CODEX_TEST_MODE=quota REVIEW_NO_MY_REVIEW=1 sc c4 review "$d/task.md" "$d/c4.log" "$d/repo" >/dev/null 2>&1; rc=$?
check "C3: 额度耗尽 ⇒ rc≠0,事件流原样留着" $([[ $rc -ne 0 ]] && grep -q 'usage_limit_exceeded' "$d/c4.stream.jsonl"; echo $?)
facts c4 "f['failure_kind'] == 'quota'"
check "C3: 额度耗尽被分型为 quota(健康池据此冷却,而不是记成 runtime)" $?
_t0=$(date +%s)
CODEX_TEST_MODE=sleep SUBCODEX_TIMEOUT=1 REVIEW_NO_MY_REVIEW=1 sc c5 review "$d/task.md" "$d/c5.log" "$d/repo" >/dev/null 2>&1; rc=$?
check "C3: 超时 ⇒ rc=124 且没有干等 30 秒" $([[ $rc -eq 124 && $(( $(date +%s) - _t0 )) -lt 20 ]]; echo $?)
facts c5 "f['process_state'] == 'timed_out'"
check "C3: facts 记 timed_out" $?

echo "[C4] 模式与反锚定闸"
REVIEW_NO_MY_REVIEW=1 sc c6 fix "$d/task.md" "$d/c6.log" "$d/repo" >/dev/null 2>"$d/c6.err"; rc=$?
check "C4: fix 模式拒绝(评审腿只读)且没调用 codex" \
  $([[ $rc -eq 2 && ! -e "$d/cap/c6.argv" ]] && grep -qi 'usage' "$d/c6.err"; echo $?)
CODEX_TEST_MODE=explore REVIEW_NO_MY_REVIEW=1 sc c7 explore "$d/task.md" "$d/c7.log" "$d/repo" >/dev/null 2>&1; rc=$?
check "C4: explore 不要求裁决行" $([[ $rc -eq 0 ]] && grep -q 'Direction' "$d/c7.log"; echo $?)
sc c8 review "$d/task.md" "$d/c8.log" "$d/repo" >/dev/null 2>"$d/c8.err"; rc=$?
check "C4: 没写自审又没显式跳过 ⇒ review 拒绝且没调用 codex(共享反锚定闸在说话)" \
  $([[ $rc -ne 0 && ! -e "$d/cap/c8.argv" ]] && grep -q 'my-review' "$d/c8.err"; echo $?)
CODEX_TEST_REPORTED=gpt-something-else REVIEW_NO_MY_REVIEW=1 sc c9 review "$d/task.md" "$d/c9.log" "$d/repo" >/dev/null 2>&1
facts c9 "f['model']['reported'] == 'gpt-something-else' and f['model']['invoked'] == '$MODEL'"
check "C4: 事件流报告的模型与请求不符时如实记下(不许用请求值盖掉)" $?

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
