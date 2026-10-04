#!/usr/bin/env bash
# subcodex oracle —— GPT 只读评审腿(track sliced-panel-review 的整体腿)。codex 是桩,
# 只读挂载 ro-repo-exec 是真的。
#
# 桩只证明「我们递给 codex 的参数长这样、结果被这样收尾」;开关在真 codex 里是否生效,
# **这份判据证明不了**,要靠真跑(verify.md 里单列)。
#
# 2026-09-13 真跑已经证伪过一次:`--disable multi_agent/multi_agent_v2` 对 gpt-6-astra **无效**,
# 子 agent 能力写在 codex 的模型目录里(multi_agent_version=v2),腿身上照样有 spawn_agent;
# `web__run` 联网工具也在。实测有效的是:覆盖模型目录去掉该字段 + `-c web_search="disabled"`。
# 桩 codex 的 `debug prompt-input` 因此**按实测行为**模拟:目录里的该模型带 multi_agent_version
# ⇒ 渲染出 <multi_agent_role>。C5 钉的就是这两件和派发前的离线核验。
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
for f in subcodex aiwork-config _aiwork_config.py ro-repo-exec _review-workspace.sh _my-review-gate.sh _review_result.py _review-home-guard.sh; do
  [[ -e "$ROOT/bin/$f" ]] && cp "$ROOT/bin/$f" "$d/bin/"
done
check "C0: bin/subcodex 与本机设置读取入口都在" \
  $([[ -x "$ROOT/bin/subcodex" && -x "$ROOT/bin/aiwork-config" ]]; echo $?)
MODEL="$("$ROOT/bin/aiwork-config" model codex)"

cat > "$d/fake/codex" <<'EOF'
#!/usr/bin/env bash
cap="$CODEX_TEST_CAPTURE"
if [[ "${1:-}" == debug ]]; then
  case "${2:-}" in
    models)  # 真 codex 的目录形状:{"models":[{slug, multi_agent_version, ...}]}
      python3 - ${CODEX_TEST_CATALOG:-} <<'PY'
import json, sys
import os
ma = {} if os.environ.get("CODEX_TEST_NO_MA") == "1" else {"multi_agent_version": "v2", "multi_agent_reasoning_effort": "xhigh"}
print(json.dumps({"models": [dict({"slug": s, "tool_mode": "code_mode_only"}, **ma) for s in sys.argv[1:]]}))
PY
      exit 0 ;;
    prompt-input)
      printf '%s\n' "$@" > "$cap.preview.argv"
      { printf '%s\n' "$@"; echo '----'; } >> "$cap.preview.all"
      catalog=""; model=""
      for a in "$@"; do
        [[ "$a" == model_catalog_json=* ]] && catalog="$(sed -E 's/^model_catalog_json="?([^"]*)"?$/\1/' <<<"$a")"
        [[ "$a" == model=* ]] && model="$(sed -E 's/^model="?([^"]*)"?$/\1/' <<<"$a")"
      done
      leak="$(python3 - "$catalog" "$model" "${CODEX_TEST_MODE:-}" <<'PY'
import json, sys
catalog, model, mode = sys.argv[1:4]
import os
if mode == "role_leak":
    print("leak"); sys.exit()
if mode == "blind_detector":  # codex 改了渲染标记的名字:子 agent 其实还在,但 <multi_agent_role> 不再出现
    print("clean"); sys.exit()
try:
    entries = [m for m in json.load(open(catalog))["models"] if m.get("slug") == model]
except Exception:
    # 没给目录 = codex 用自带目录 = 与 `debug models` 输出的同一份
    entries = [{}] if os.environ.get("CODEX_TEST_NO_MA") == "1" else [{"multi_agent_version": "v2"}]
print("leak" if not entries or any("multi_agent_version" in m for m in entries) else "clean")
PY
)"
      if [[ "$leak" == leak ]]; then
        printf '[{"type":"message","role":"developer","content":[{"type":"input_text","text":"<multi_agent_role>You can use spawn_agent</multi_agent_role>"}]}]\n'
      else
        printf '[{"type":"message","role":"user","content":[{"type":"input_text","text":"probe"}]}]\n'
      fi
      exit 0 ;;
  esac
  exit 2
fi
printf '%s\n' "$@" > "$cap.argv"
for a in "$@"; do  # 派发那一刻把目录副本抄走(ws 跑完就清理了)
  [[ "$a" == model_catalog_json=* ]] && cp "$(sed -E 's/^model_catalog_json="?([^"]*)"?$/\1/' <<<"$a")" "$cap.catalog.json" 2>/dev/null
done
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
  CODEX_TEST_CATALOG="${CODEX_TEST_CATALOG-$MODEL gpt-fixture-next gpt-override}" \
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
argv_pair c1 -m "$MODEL"; check "C1: -m 取自 models.env 的 codex 行($MODEL)" $?
argv_pair c1 -c project_doc_max_bytes=0; check "C1: 带 -c project_doc_max_bytes=0(不吞仓里的 AGENTS.md)" $?
argv_has c1 --ignore-user-config; check "C1: --ignore-user-config(不加载业主的插件/MCP/配置)" $?
argv_has c1 --ephemeral; check "C1: --ephemeral(不往业主的会话历史里落评审会话)" $?
argv_pair c1 --disable multi_agent; check "C1: --disable multi_agent(只对不在模型目录里带子 agent 的模型有效,见 C5)" $?
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
cp -r "$d/bin" "$d/bin2"
test_model_set codex gpt-fixture-next
SC_BIN="$d/bin2" REVIEW_NO_MY_REVIEW=1 sc c2a review "$d/task.md" "$d/c2a.log" "$d/repo" >/dev/null 2>&1
argv_pair c2a -m gpt-fixture-next; check "C2: 只改 models.env 的 codex 一行 ⇒ 实际 -m 跟着变" $?
SUBCODEX_MODEL=gpt-override REVIEW_NO_MY_REVIEW=1 sc c2b review "$d/task.md" "$d/c2b.log" "$d/repo" >/dev/null 2>&1
argv_pair c2b -m gpt-override; check "C2: SUBCODEX_MODEL 单次覆盖" $?
test_model_set codex ""
SC_BIN="$d/bin2" REVIEW_NO_MY_REVIEW=1 sc c2c review "$d/task.md" "$d/c2c.log" "$d/repo" >/dev/null 2>"$d/c2c.err"; rc=$?
check "C2: codex 配置为空 ⇒ 拒绝且没调用 codex(理由点名 models.env)" \
  $([[ $rc -ne 0 && ! -e "$d/cap/c2c.argv" ]] && grep -q 'models.env' "$d/c2c.err"; echo $?)
test_model_set codex "$MODEL"
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

echo "[C5] 子 agent 与联网:真正生效的开关(2026-09-13 真跑实测)+ 派发前离线核验"
argv_pair c1 -c 'web_search="disabled"'
check "C5: 派发带 -c web_search=\"disabled\"(实测拿掉 web__run 的就是它)" $?
_cat_arg="$(awk 'prev=="-c" && /^model_catalog_json=/ {print; exit} {prev=$0}' "$d/cap/c1.argv" 2>/dev/null)"
python3 - "$d/cap/c1.catalog.json" "$MODEL" <<'PY'
import json, sys
try:
    entries = [m for m in json.load(open(sys.argv[1]))["models"] if m.get("slug") == sys.argv[2]]
except Exception:
    sys.exit(1)
sys.exit(0 if len(entries) == 1 and "multi_agent_version" not in entries[0] else 1)
PY
_cat_ok=$?
check "C5: 派发带 -c model_catalog_json=<目录副本>,副本里该模型没有 multi_agent_version" \
  $([[ -n "$_cat_arg" && "$_cat_ok" -eq 0 ]]; echo $?)
python3 - "$d/cap/c1.argv" "$d/cap/c1.preview.argv" <<'PY'
import sys
def cfg(path):
    try:
        args = open(path).read().splitlines()
    except OSError:
        return None
    out = []
    for i, a in enumerate(args):
        if a in ("-c", "--disable", "--enable") and i + 1 < len(args):
            v = args[i + 1]
            out.append((a, v.split("=", 1)[0] if v.startswith("model_catalog_json=") else v))
    return sorted(out)
exec_cfg, preview_cfg = cfg(sys.argv[1]), cfg(sys.argv[2])
sys.exit(0 if exec_cfg and preview_cfg is not None and set(exec_cfg) <= set(preview_cfg + [("-c", "approval_policy=never")]) else 1)
PY
check "C5: 派发前用同一组 -c/--disable 开关跑过 codex debug prompt-input(核验的就是要派发的配置)" $?
CODEX_TEST_MODE=role_leak REVIEW_NO_MY_REVIEW=1 sc c10 review "$d/task.md" "$d/c10.log" "$d/repo" >/dev/null 2>"$d/c10.err"; rc=$?
check "C5: 离线核验仍看到 <multi_agent_role> ⇒ 拒跑、没派发 codex exec、理由点名 sub-agent" \
  $([[ $rc -ne 0 && ! -e "$d/cap/c10.argv" && -e "$d/cap/c10.preview.argv" ]] && grep -qi 'sub-agent' "$d/c10.err"; echo $?)
CODEX_TEST_CATALOG="gpt-some-other" REVIEW_NO_MY_REVIEW=1 sc c11 review "$d/task.md" "$d/c11.log" "$d/repo" >/dev/null 2>"$d/c11.err"; rc=$?
check "C5: 模型不在 codex 模型目录里 ⇒ 拒跑、没派发 codex exec(不带着默认目录悄悄去跑)" \
  $([[ $rc -ne 0 && ! -e "$d/cap/c11.argv" ]] && grep -q 'catalog' "$d/c11.err"; echo $?)
# 2026-09-14 变异红检 C11 漏网后补:检测器自检加的 `next(...)` 在模型缺席时会自己崩 ⇒ 缺席照样拒跑,
# 「恰好一次」那道检查被盖住、删掉它上面那条断言仍绿。它唯一还看得见的后果是**重复出现**。
CODEX_TEST_CATALOG="$MODEL $MODEL gpt-some-other" REVIEW_NO_MY_REVIEW=1 sc c13 review "$d/task.md" "$d/c13.log" "$d/repo" >/dev/null 2>"$d/c13.err"; rc=$?
check "C5: 模型在 codex 模型目录里出现两次 ⇒ 拒跑、没派发 codex exec、理由点名 exactly once" \
  $([[ $rc -ne 0 && ! -e "$d/cap/c13.argv" ]] && grep -q 'exactly once' "$d/c13.err"; echo $?)
check "C5: 拒跑之后可丢弃副本同样清理干净" $([[ -z "$(ls -A "$d/ws" 2>/dev/null)" ]]; echo $?)
# C6:2026-09-14 panel-review 高风险评审(subdeepseek)发现 E 后补 —— 检测器自检。
# 只看「覆盖后的渲染里没有 <multi_agent_role>」,codex 一改标记名就恒过(注释却写着会拒跑)。
# 自检:模型目录声明了 multi_agent_version 时,**不覆盖目录**的基线渲染里必须看得见标记,看不见 = 检测器瞎了。
awk 'BEGIN{blk=""; found=0} /^----$/ {if (blk !~ /model_catalog_json=/ && blk ~ /(^|\n)prompt-input(\n|$)/) found=1; blk=""; next} {blk = blk $0 "\n"} END{exit found?0:1}' "$d/cap/c1.preview.all" 2>/dev/null
check "C6: 派发前另做一次不带目录覆盖的基线渲染(检测器自检)" $?
CODEX_TEST_MODE=blind_detector REVIEW_NO_MY_REVIEW=1 sc c12 review "$d/task.md" "$d/c12.log" "$d/repo" >/dev/null 2>"$d/c12.err"; rc=$?
check "C6: 目录声明有子 agent、基线渲染却看不到 <multi_agent_role>(检测器瞎了)⇒ 拒跑、没派发 codex exec、理由点名 blind" \
  $([[ $rc -ne 0 && ! -e "$d/cap/c12.argv" ]] && grep -qi 'blind' "$d/c12.err"; echo $?)
CODEX_TEST_NO_MA=1 REVIEW_NO_MY_REVIEW=1 sc c13 review "$d/task.md" "$d/c13.log" "$d/repo" >/dev/null 2>"$d/c13.err"; rc=$?
check "C6: 对照组:目录里本来就没有子 agent 字段的模型 ⇒ 自检不误拒、照常派发" \
  $([[ $rc -eq 0 && -e "$d/cap/c13.argv" ]]; echo $?)

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
