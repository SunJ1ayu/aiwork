#!/usr/bin/env bash
# Regression oracle for the review-tooling fixes V1..V7.
# Owned by the main agent (the frontier model driving the session).
# Must NOT be edited by submimo/subdeepseek/subglm.
#
#   V1  submimo-review: untracked/new files have their CONTENT inlined under
#       --git-diff (they are absent from `git diff`, so reviewing new files
#       must not be a silent blind spot).
#   V2  subdeepseek: DEEPSEEK_INCLUDE patterns reach the engine LITERALLY; the
#       shell must not pre-expand globs against subdeepseek's own CWD (needs set -f).
#   V3  panel-review: a reviewer's early stderr failure is captured to a .err
#       sidecar (not swallowed, not racing the reviewer's own .log); empty
#       sidecars are removed on success; exit code is 1 only if ALL THREE fail.
#   V4  submimo-review: empty / null / verdict-less model output exits non-zero
#       (log still written, reason on stderr); explore mode (--mode explore /
#       REVIEW_MODE=explore, flag wins) is exempt from the verdict check; a
#       custom REVIEW_SYSTEM_PROMPT alone is NOT; dry-run stays exempt from all.
#   V5  submimo-review: staged and committed work is visible in the diff
#       (HEAD default, empty-tree fallback in fresh repos, PANEL_DIFF_BASE for
#       branch review; invalid base is a hard error).
#   V6  submimo-review: git diff and pooled untracked content are byte-capped
#       with explicit [TRUNCATED] markers.
#   V7  submimo-review: empty diff + nothing attached emits a BLIND warning on
#       stderr and in the log header, but stays rc=0.
#   V17 panel-explore 的 GLM / DeepSeek 两腿必须走**底座**(自己读仓库),不是聊天壳。
#       2026-08-01 实证:panel-explore 建于 6-26,底座腿是 7-05/7-14 才有的,它一直
#       硬写着 `subdeepseek review` / `subglm review` 两个聊天壳。聊天腿看代码的**唯一
#       通道是 git diff**,而发散任务按定义没有 diff(工作树干净)⇒ **那两腿结构性
#       蒙眼**,brief 里写「请自己读代码」对它们是空话。同一个病 panel-review 治过了
#       (代码里就有那条注释),发散这边漏改。
#       光把调用换成底座腿会**立刻坏两处**,所以判据把这两处一起钉死:
#         ① 底座腿的提示词写死"评审员"且强制 `Conclusion: PASS|BLOCK|NEEDS_MORE_INFO`
#            出卷闸 —— 发散没有裁决 ⇒ 闸判失败 ⇒ 自动回落聊天腿 ⇒ 绕回蒙眼;
#         ② 底座腿不读发散用的系统提示词(那是聊天引擎才认的)⇒ 就算跑通也写成评审。
#       模式沿用仓里已有的约定(submimo-review 的 --mode explore / REVIEW_MODE),
#       不另立第二套写法;panel-explore 早就在用 `submimo explore` 当第一位置参数。
#   V18 引擎的身份只有一个来源。2026-08-03 实证:`REVIEW_LABEL` 只喂了日志头,
#       而 `submimo-review` 的每一条 stderr 都硬写着自己的名字 ⇒ **subglm 腿把智谱的
#       429/1113 印成 `submimo-review: ... from Mimo endpoint`**,我第一遍差点把死因
#       记到 MiMo 头上。同一件事写在两个地方、只更新其中一个 —— 本仓反复记账的那条债。
#       附带:端点报错不许硬写厂商名,要打印**真实端点 URL**(它不可能撒谎)。
#   V19 降级的事实必须写进**结论所在的那份日志**。底座腿死了自动回落聊天腿是对的,
#       但那行 `NOTE: ... fallback` 只印在 panel-review 的实时 stdout 上;事后(或断线
#       重连后)读日志的人,看到的是一份和健康腿长得一模一样的结论。2026-08-03 我就是
#       这样差点按「四审三腿 PASS」给权重,实际是两腿睁眼、一腿只看得见 diff、一腿没来。
#       ⇒ ① 回落时把降级横幅写进 <log> 本身;② 聊天腿日志头必须自报**视野边界**
#       (只有 diff + INCLUDE,看不到仓库其余部分)。结论可以旅行,资格必须跟着走。
#   V20 撞上 max-turns 不许把工作全丢掉。`claude -p` 默认只印最后一条消息 ⇒ 撞上限
#       时**80 轮的探索产出为零**,然后静默换上蒙眼的聊天腿。deepseek 腿 07-21 撞 40、
#       08-03 撞 80,两次的修法都是把上限翻倍 —— 那是在修数字不是修因。
#       真正的因:**一个会把"慢"变成"什么都没有"的护栏**。⇒ 底座腿走 stream-json,
#       模型说过的话与工具动作实时落盘,撞上限也留得下;并记一行「用了 N/上限 M 轮」,
#       下次调上限**凭测量不凭翻倍**。
#   V21 底座腿的躯干只有一份。`subdeepseek-agent` 与 `subglm-agent` 是 95% 相同的两份
#       拷贝(342 行里只有 80 行不同,且多半是注释)⇒ V18/V19/V20 每条修法都得改两遍,
#       而历史证明**总有一份会落下**(聊天腿早就用 subchat + 供应商表治过这个病,
#       底座腿这边一直没治)。⇒ 共享躯干 `subagent` + 供应商表 + 瘦 shim,照 subchat 的先例。
#   V22 派发窗口里的三个盲区(2026-08-05 `opendesign-turn-id` 一单里各栽一次):
#       a) **评审期间 HEAD 动了没人说**。22:40 我趁 Kimi 还在跑提交了 `80d2d23`,
#          它日志 1027–1094 行整段在追查"仓库正在被人改",并把 BLOCK 押在这个幻影上,
#          25 分钟全废。⇒ 派发前后各记一次 HEAD,不同就报,且横幅要**写进每份腿日志**
#          (结论会被单独读到,那时终端上那行早没了 —— 和 V19 同一个道理)。
#       b) **反锚定检查有两臂,本机默认形状下两臂都照不到**。`PANEL_DIFF_BASE` 的推导
#          要求 `main != HEAD`,而我一直在 main 上干活;verify.md 又是**已提交**的
#          ⇒ status 那臂也空。实测泄漏:DeepSeek 日志第 28 行读了 verify.md、
#          第 101 行原文引用我的「规格自查第 2 条」。⇒ 补一条不依赖 diff 基线的:
#          按任务名去 `git ls-files` 找同名 track 的 verify.md(不相干的 track 不报,
#          否则警告变噪音、下次就没人看了)。
#       c) **各腿状态只活在终端里**。08-05 我在 verify.md 写下"三条腿一致 PASS",
#          而 Kimi 根本没出结论(同一页第 90 行自己还写着它没出报告)—— 同页自相矛盾,
#          `df527f2` 才更正。⇒ 收尾把花名册落盘成 `<prefix>.roster`,粘进 verify.md;
#          关着的腿记 `off`(不许记成 PASS),回落腿带降级标记。
#
# Run:  bash /root/aiwork/tests/test-review-tooling.sh
set -uo pipefail

# 从判据自身位置推 bin/,**不写死绝对路径**:执行腿在 worktree 里改了代码,
# 写死路径会让判据仍去测主仓的文件 = 改了也永远红(2026-08-01 派活前发现)。
# 可用 REVIEW_BIN 覆盖。
BIN="${REVIEW_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"
# 2026-08-04:GLM 腿默认改成 off(智谱欠费,见 bin/panel-review 里的理由)。
# 下面的老用例问的是**这条腿的行为**(回落、失败留证、rc 语义……),不是"它默不默认开",
# 所以统一在这里把腿显式打开 —— 断言一条不删、一条不弱。
# 只有"默认关不关"那两条用 `env -u PANEL_GLM_LEG` 在干净环境里问。
export PANEL_GLM_LEG=agent

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ # check "desc" COND_RC   (0 => pass)
  if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi
}

# ---------------------------------------------------------------- V1
v1_untracked_content() {
  echo "[V1] submimo-review inlines untracked file content under --git-diff"
  local d; d="$(mktemp -d)"
  local repo="$d/repo"; mkdir -p "$repo"   # task/out live outside repo so they aren't untracked
  ( cd "$repo"
    git init -q; git config user.email t@t; git config user.name t
    echo old > tracked.txt; git add tracked.txt; git commit -qm init
    echo CHANGED >> tracked.txt
    printf 'SECRET_NEW_FILE_CONTENT_LINE\n' > brandnew.py
    echo '*.log' > .gitignore
    printf 'should_not_leak\n' > ignore_me.log )
  printf '# review\ncheck new file\n' > "$d/t.md"
  MIMO_API_KEY=x MIMO_BASE_URL=http://x python3 "$BIN/submimo-review" \
    "$d/t.md" "$d/out.log" --repo "$repo" --git-diff --dry-run >/dev/null 2>&1

  grep -q SECRET_NEW_FILE_CONTENT_LINE "$d/out.log"; check "untracked content present" $?
  grep -q "Untracked / New Files" "$d/out.log";       check "untracked section header present" $?
  grep -q CHANGED "$d/out.log";                        check "tracked diff still present" $?
  if grep -q ignore_me "$d/out.log"; then bad "gitignored file excluded"; else ok "gitignored file excluded"; fi
  rm -rf "$d"
}

v1_no_untracked_and_nonrepo() {
  echo "[V1] submimo-review: clean repo has no header; non-repo does not crash"
  local d; d="$(mktemp -d)"
  local repo="$d/repo"; mkdir -p "$repo"
  ( cd "$repo"; git init -q; git config user.email t@t; git config user.name t
    echo a > f; git add f; git commit -qm init )
  printf '# t\n' > "$d/t.md"
  MIMO_API_KEY=x MIMO_BASE_URL=http://x python3 "$BIN/submimo-review" \
    "$d/t.md" "$d/out.log" --repo "$repo" --git-diff --dry-run >/dev/null 2>&1
  if grep -q "Untracked / New Files" "$d/out.log"; then bad "no header when no untracked"; else ok "no header when no untracked"; fi

  local nd; nd="$(mktemp -d)"   # not a git repo
  printf '# t\n' > "$nd/t.md"
  MIMO_API_KEY=x MIMO_BASE_URL=http://x python3 "$BIN/submimo-review" \
    "$nd/t.md" "$nd/out.log" --repo "$nd" --git-diff --dry-run >/dev/null 2>&1
  check "non-repo dry-run exits 0 (no crash)" $?
  rm -rf "$d" "$nd"
}

# ---------------------------------------------------------------- V2
v2_glob_not_pre_expanded() {
  echo "[V2] subdeepseek passes DEEPSEEK_INCLUDE patterns literally (no shell glob)"
  local d stub_bin; d="$(mktemp -d)"; stub_bin="$d/bin"
  mkdir -p "$stub_bin"
  # subdeepseek is a thin shim onto subchat; bin/ deploys as a set, so copy both.
  cp "$BIN/subdeepseek" "$stub_bin/subdeepseek"
  cp "$BIN/subchat" "$stub_bin/subchat"
  # stub engine: subdeepseek does `exec python3 "$ENGINE" ...`; record argv.
  cat > "$stub_bin/submimo-review" <<PYEOF
import sys
open("$d/argv.txt","w").write("\0".join(sys.argv[1:]))
PYEOF
  # decoy files in subdeepseek's CWD that *.py would expand to if globbing leaks.
  ( cd "$d"; touch decoy_a.py decoy_b.py
    printf '# t\n' > t.md
    DEEPSEEK_API_KEY=dummy DEEPSEEK_INCLUDE="*.py" \
      bash "$stub_bin/subdeepseek" review "$d/t.md" "$d/out.log" "$d" >/dev/null 2>&1 )

  if [[ -f "$d/argv.txt" ]]; then
    # literal pattern present, decoy-expanded names absent
    grep -qz -- '*.py' "$d/argv.txt"; check "literal '*.py' reached engine" $?
    if grep -qz decoy_a.py "$d/argv.txt"; then bad "no CWD-expanded decoy leaked"; else ok "no CWD-expanded decoy leaked"; fi
  else
    bad "stub engine was invoked (argv captured)"
  fi
  rm -rf "$d"
}

# ---------------------------------------------------------------- V3
make_fake_reviewer() { # path RC  -> writes a stub that mimics a reviewer
  local p="$1" rc="$2"
  cat > "$p" <<EOF
#!/usr/bin/env bash
# args: review TASK LOG REPO
echo "stub result" > "\$3"            # mimic writing its own .log
if [[ $rc -ne 0 ]]; then echo "STUB_STARTUP_FAILURE rc=$rc" >&2; fi
exit $rc
EOF
  chmod +x "$p"
}

v3_panel_sidecar() {
  echo "[V3] panel-review captures stderr to .err sidecar, prunes empties, exits right"
  local d b; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"
  cp "$BIN/panel-review" "$b/panel-review"
  printf '# t\n' > "$d/t.md"

  # scenario A: all three fail -> each .err non-empty with reason, exit 1
  make_fake_reviewer "$b/submimo"  3
  make_fake_reviewer "$b/subdeepseek" 4
  make_fake_reviewer "$b/subglm"   6
  bash "$b/panel-review" --no-my-review "$d/t.md" "$d" "$d/A" >/dev/null 2>&1; local rcA=$?
  check "all-fail exits 1" $([[ $rcA -eq 1 ]]; echo $?)
  grep -q STUB_STARTUP_FAILURE "$d/A.submimo.log.err"  2>/dev/null; check "submimo failure reason captured in .err" $?
  grep -q STUB_STARTUP_FAILURE "$d/A.subdeepseek.log.err" 2>/dev/null; check "subdeepseek failure reason captured in .err" $?
  grep -q STUB_STARTUP_FAILURE "$d/A.subglm.log.err"   2>/dev/null; check "subglm failure reason captured in .err" $?

  # scenario B: all succeed -> empty .err pruned, exit 0
  make_fake_reviewer "$b/submimo"  0
  make_fake_reviewer "$b/subdeepseek" 0
  make_fake_reviewer "$b/subglm"   0
  bash "$b/panel-review" --no-my-review "$d/t.md" "$d" "$d/B" >/dev/null 2>&1; local rcB=$?
  check "all-ok exits 0" $([[ $rcB -eq 0 ]]; echo $?)
  if [[ -e "$d/B.submimo.log.err" || -e "$d/B.subdeepseek.log.err" || -e "$d/B.subglm.log.err" ]]; then bad "empty .err sidecars pruned on success"; else ok "empty .err sidecars pruned on success"; fi

  # scenario C: one fails -> exit 0 (panel only fails if ALL fail), failing .err kept, others pruned
  make_fake_reviewer "$b/submimo"  0
  make_fake_reviewer "$b/subdeepseek" 5
  make_fake_reviewer "$b/subglm"   0
  bash "$b/panel-review" --no-my-review "$d/t.md" "$d" "$d/C" >/dev/null 2>&1; local rcC=$?
  check "one-fail exits 0" $([[ $rcC -eq 0 ]]; echo $?)
  grep -q STUB_STARTUP_FAILURE "$d/C.subdeepseek.log.err" 2>/dev/null; check "failing reviewer's .err kept" $?
  if [[ -e "$d/C.submimo.log.err" || -e "$d/C.subglm.log.err" ]]; then bad "passing reviewers' empty .err pruned"; else ok "passing reviewers' empty .err pruned"; fi
  rm -rf "$d"
}

# ---------------------------------------------------------------- V4
# Stub OpenAI-compatible API: serves one fixed JSON body on every POST.
# Binds port 0 and reports the real port via a file (avoids collisions).
# Sets STUB_URL/STUB_PID globals; must NOT be called in a command substitution
# (a $() would wait for EOF on the pipe the background server keeps open, and
# would also lose STUB_PID to the subshell -> unkillable stub + suite deadlock).
start_stub_api() { # dir response_json -> sets STUB_URL, STUB_PID
  local dir="$1" body="$2"
  rm -f "$dir/port"
  python3 - "$dir/port" "$body" <<'PY' >/dev/null 2>&1 &
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
portfile, body = sys.argv[1], sys.argv[2].encode()
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
srv = HTTPServer(('127.0.0.1', 0), H)
open(portfile, 'w').write(str(srv.server_address[1]))
srv.serve_forever()
PY
  STUB_PID=$!
  for _ in $(seq 50); do [[ -s "$dir/port" ]] && break; sleep 0.1; done
  STUB_URL="http://127.0.0.1:$(cat "$dir/port")/chat/completions"
}

run_engine_against() { # url task log [VAR=VAL...] [engine-args...] -> engine rc
  local url="$1" task="$2" log="$3"; shift 3
  local envs=()
  while [[ "${1:-}" == *=* ]]; do envs+=("$1"); shift; done
  env "${envs[@]}" MIMO_API_KEY=x MIMO_CHAT_COMPLETIONS_URL="$url" \
    python3 "$BIN/submimo-review" "$task" "$log" --git-diff "$@" 2>"${log}.stderr"
}

v4_output_validation() {
  echo "[V4] submimo-review rejects empty/null/verdict-less output; explore exempt"
  local d url rc; d="$(mktemp -d)"
  printf '# t\n' > "$d/t.md"

  start_stub_api "$d" '{"choices":[{"message":{"content":""}}]}'
  run_engine_against "$STUB_URL" "$d/t.md" "$d/empty.log" --repo "$d" >/dev/null; rc=$?
  check "empty content exits non-zero" $([[ $rc -ne 0 ]]; echo $?)
  [[ -f "$d/empty.log" ]]; check "log still written on empty content" $?
  grep -q "model returned empty output" "$d/empty.log.stderr"; check "reason on stderr (sidecar)" $?
  kill "$STUB_PID" 2>/dev/null; rm -f "$d/port"

  start_stub_api "$d" '{"choices":[{"message":{"content":null}}]}'
  run_engine_against "$STUB_URL" "$d/t.md" "$d/null.log" --repo "$d" >/dev/null; rc=$?
  check "null content exits non-zero" $([[ $rc -ne 0 ]]; echo $?)
  if grep -q "Traceback" "$d/null.log.stderr"; then bad "null content: no traceback"; else ok "null content: no traceback"; fi
  [[ -f "$d/null.log" ]]; check "log still written on null content" $?
  kill "$STUB_PID" 2>/dev/null; rm -f "$d/port"

  # GLM-family reasoning models: content null but the review lives in
  # reasoning_content -> that leg must be recovered, not reported empty
  start_stub_api "$d" '{"choices":[{"message":{"content":null,"reasoning_content":"Conclusion: PASS (reasoning fallback)"}}]}'
  run_engine_against "$STUB_URL" "$d/t.md" "$d/reasoning.log" --repo "$d" >/dev/null; rc=$?
  check "reasoning_content fallback exits 0" $([[ $rc -eq 0 ]]; echo $?)
  grep -q "reasoning fallback" "$d/reasoning.log"; check "reasoning_content text lands in log" $?
  kill "$STUB_PID" 2>/dev/null; rm -f "$d/port"

  start_stub_api "$d" '{"choices":[{"message":{"content":"looks fine to me"}}]}'
  run_engine_against "$STUB_URL" "$d/t.md" "$d/noverdict.log" --repo "$d" >/dev/null; rc=$?
  check "verdict-less review output exits non-zero" $([[ $rc -ne 0 ]]; echo $?)
  run_engine_against "$STUB_URL" "$d/t.md" "$d/explore.log" \
    REVIEW_MODE=explore REVIEW_SYSTEM_PROMPT="divergent design" --repo "$d" >/dev/null; rc=$?
  check "explore mode exempt from verdict check" $([[ $rc -eq 0 ]]; echo $?)
  # the old trap: a CUSTOM review prompt must NOT silently disable the verdict
  # check - only an explicit explore mode may
  run_engine_against "$STUB_URL" "$d/t.md" "$d/customprompt.log" \
    REVIEW_SYSTEM_PROMPT="my stricter review prompt" --repo "$d" >/dev/null; rc=$?
  check "custom review prompt still verdict-checked" $([[ $rc -ne 0 ]]; echo $?)
  # --mode flag wins over REVIEW_MODE env
  run_engine_against "$STUB_URL" "$d/t.md" "$d/modeflag.log" \
    REVIEW_MODE=review REVIEW_SYSTEM_PROMPT="divergent design" --repo "$d" --mode explore >/dev/null; rc=$?
  check "--mode flag overrides REVIEW_MODE env" $([[ $rc -eq 0 ]]; echo $?)
  kill "$STUB_PID" 2>/dev/null; rm -f "$d/port"

  start_stub_api "$d" '{"choices":[{"message":{"content":"Conclusion: PASS"}}]}'
  run_engine_against "$STUB_URL" "$d/t.md" "$d/pass.log" --repo "$d" >/dev/null; rc=$?
  check "verdict output exits 0" $([[ $rc -eq 0 ]]; echo $?)
  kill "$STUB_PID" 2>/dev/null

  # dry-run produces result="" by design and must stay exempt
  MIMO_API_KEY=x MIMO_BASE_URL=http://x python3 "$BIN/submimo-review" \
    "$d/t.md" "$d/dry.log" --repo "$d" --git-diff --dry-run >/dev/null 2>&1
  check "dry-run still exits 0" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- V5
dry_prompt() { # task log repo extra-args/env... (env VAR=VAL pairs first)
  local envs=()
  while [[ "${1:-}" == *=* ]]; do envs+=("$1"); shift; done
  env "${envs[@]}" MIMO_API_KEY=x MIMO_BASE_URL=http://x \
    python3 "$BIN/submimo-review" "$@" --git-diff --dry-run
}

v5_diff_scope() {
  echo "[V5] staged/committed work visible; empty-tree fallback; PANEL_DIFF_BASE"
  local d repo; d="$(mktemp -d)"; repo="$d/repo"; mkdir -p "$repo"
  printf '# t\n' > "$d/t.md"

  # -b main: deterministic base branch name so the PANEL_DIFF_BASE case below
  # does not depend on the machine's init.defaultBranch
  ( cd "$repo"; git init -q -b main; git config user.email t@t; git config user.name t
    echo base > f.txt; git add f.txt; git commit -qm init
    echo STAGED_ONLY_CHANGE >> f.txt; git add f.txt )
  dry_prompt "$d/t.md" "$d/staged.log" --repo "$repo" >/dev/null 2>&1
  grep -q STAGED_ONLY_CHANGE "$d/staged.log"; check "staged-only change visible in diff" $?

  local fresh="$d/fresh"; mkdir -p "$fresh"
  ( cd "$fresh"; git init -q; git config user.email t@t; git config user.name t
    echo FRESH_STAGED_CONTENT > new.txt; git add new.txt )
  dry_prompt "$d/t.md" "$d/fresh.log" --repo "$fresh" >/dev/null 2>&1; local rc=$?
  check "fresh repo (no HEAD) exits 0" $([[ $rc -eq 0 ]]; echo $?)
  grep -q FRESH_STAGED_CONTENT "$d/fresh.log"; check "fresh repo staged content visible" $?

  ( cd "$repo"; git checkout -q -b feature
    echo COMMITTED_BRANCH_CHANGE >> f.txt; git commit -qam branchwork )
  PANEL_DIFF_BASE=main dry_prompt "$d/t.md" "$d/branch.log" --repo "$repo" >/dev/null 2>&1
  grep -q COMMITTED_BRANCH_CHANGE "$d/branch.log"; check "PANEL_DIFF_BASE shows committed branch work" $?

  PANEL_DIFF_BASE=no-such-ref dry_prompt "$d/t.md" "$d/bad.log" --repo "$repo" >/dev/null 2>&1; rc=$?
  check "invalid PANEL_DIFF_BASE is a hard error" $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"
}

# ---------------------------------------------------------------- V6
v6_truncation() {
  echo "[V6] diff and pooled untracked content are byte-capped with markers"
  local d repo; d="$(mktemp -d)"; repo="$d/repo"; mkdir -p "$repo"
  printf '# t\n' > "$d/t.md"
  ( cd "$repo"; git init -q; git config user.email t@t; git config user.name t
    echo base > big.txt; git add big.txt; git commit -qm init
    python3 -c "print('X'*5000)" >> big.txt )
  MIMO_MAX_DIFF_BYTES=1000 dry_prompt "$d/t.md" "$d/diff.log" --repo "$repo" >/dev/null 2>&1
  grep -q "TRUNCATED: git diff exceeded 1000 bytes" "$d/diff.log"; check "oversized diff truncated with marker" $?

  ( cd "$repo"; git checkout -q big.txt
    for i in 1 2 3 4 5 6; do python3 -c "print('U'*400)" > "untracked_$i.txt"; done )
  MIMO_MAX_UNTRACKED_TOTAL_BYTES=1000 dry_prompt "$d/t.md" "$d/untr.log" --repo "$repo" >/dev/null 2>&1
  grep -q "untracked files exceeded 1000 bytes total" "$d/untr.log"; check "untracked pool capped with marker" $?
  grep -q "listed by name only" "$d/untr.log"; check "omitted untracked files listed by name" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- V7
v7_blind_warning() {
  echo "[V7] empty diff + nothing attached warns BLIND on stderr and in log, rc=0"
  local d repo; d="$(mktemp -d)"; repo="$d/repo"; mkdir -p "$repo"
  printf '# t\n' > "$d/t.md"
  ( cd "$repo"; git init -q; git config user.email t@t; git config user.name t
    echo a > f; git add f; git commit -qm init )
  dry_prompt "$d/t.md" "$d/out.log" --repo "$repo" >/dev/null 2>"$d/stderr.txt"; local rc=$?
  check "empty-diff run still exits 0" $([[ $rc -eq 0 ]]; echo $?)
  grep -q "BLIND" "$d/stderr.txt"; check "BLIND warning on stderr" $?
  grep -q "warning:.*BLIND" "$d/out.log"; check "BLIND warning in log header" $?

  # attaching an include silences the warning
  echo content > "$repo/x.py"; ( cd "$repo"; git add x.py; git commit -qm x )
  MIMO_API_KEY=x MIMO_BASE_URL=http://x python3 "$BIN/submimo-review" \
    "$d/t.md" "$d/inc.log" --repo "$repo" --git-diff --include x.py --dry-run >/dev/null 2>"$d/stderr2.txt"
  if grep -q "BLIND" "$d/stderr2.txt"; then bad "no warning when include attached"; else ok "no warning when include attached"; fi
  rm -rf "$d"
}

# ---------------------------------------------------------------- V8
v8_subchat_provider_table() {
  echo "[V8] subchat: provider table drives engine env; shims + auth fallback intact"
  local d b rc; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"
  cp "$BIN/subchat" "$b/subchat"
  cp "$BIN/subdeepseek" "$b/subdeepseek"
  cp "$BIN/subglm"   "$b/subglm"
  # stub engine: record argv + the MIMO_*/REVIEW_LABEL env subchat must inject.
  cat > "$b/submimo-review" <<'PYEOF'
import sys, os, json
keys = ["MIMO_API_KEY","MIMO_BASE_URL","MIMO_CHAT_COMPLETIONS_URL",
        "MIMO_MODEL","MIMO_TIMEOUT","REVIEW_LABEL"]
out = {"argv": sys.argv[1:], "env": {k: os.environ.get(k) for k in keys}}
open(os.environ["CAPTURE"], "w").write(json.dumps(out))
PYEOF
  printf '# t\n' > "$d/t.md"
  envget() { # capture.json KEY -> value ('' if unset)
    python3 -c "import json,sys;v=json.load(open(sys.argv[1]))['env'].get(sys.argv[2]);print('' if v is None else v)" "$1" "$2"
  }

  # unknown provider is a hard error naming the supported ones
  env CAPTURE="$d/c0.json" bash "$b/subchat" nope review "$d/t.md" "$d/o0.log" "$d" \
    >/dev/null 2>"$d/e0.txt"; rc=$?
  check "unknown provider exits non-zero" $([[ $rc -ne 0 ]]; echo $?)
  grep -q "deepseek" "$d/e0.txt"; check "unknown-provider error lists supported providers" $?

  # deepseek leg: base-URL style endpoint, default model, label; a stray
  # engine endpoint var inherited from the caller must NOT leak through; an
  # EMPTY (set-but-null) model var must still fall back to the default
  env CAPTURE="$d/c1.json" DEEPSEEK_MODEL= \
    MIMO_CHAT_COMPLETIONS_URL=http://stray.example/chat DEEPSEEK_API_KEY=sk-dummy \
    bash "$b/subchat" deepseek review "$d/t.md" "$d/o1.log" "$d" >/dev/null 2>&1; rc=$?
  check "subchat deepseek review exits 0" $([[ $rc -eq 0 ]]; echo $?)
  [[ "$(envget "$d/c1.json" MIMO_BASE_URL)" == "https://api.deepseek.com" ]]
  check "deepseek: MIMO_BASE_URL default" $?
  [[ "$(envget "$d/c1.json" MIMO_MODEL)" == "deepseek-v4-flash" ]]
  check "deepseek: default model (even when env var set-but-empty)" $?
  [[ "$(envget "$d/c1.json" MIMO_TIMEOUT)" == "900" ]]
  check "deepseek: default timeout 900" $?
  [[ "$(envget "$d/c1.json" REVIEW_LABEL)" == "subdeepseek-review" ]]
  check "deepseek: REVIEW_LABEL preserved" $?
  [[ "$(envget "$d/c1.json" MIMO_API_KEY)" == "sk-dummy" ]]
  check "deepseek: env key wins" $?
  [[ -z "$(envget "$d/c1.json" MIMO_CHAT_COMPLETIONS_URL)" ]]
  check "deepseek: stray MIMO_CHAT_COMPLETIONS_URL scrubbed" $?

  # zhipu leg: exact chat-URL style endpoint, label; model override; stray
  # MIMO_BASE_URL from the caller must be scrubbed likewise
  env CAPTURE="$d/c2.json" MIMO_BASE_URL=http://stray.example/v1 \
    ZHIPU_API_KEY=zk-dummy ZHIPU_MODEL=glm-custom ZHIPU_TIMEOUT=123 \
    bash "$b/subchat" zhipu review "$d/t.md" "$d/o2.log" "$d" >/dev/null 2>&1; rc=$?
  check "subchat zhipu review exits 0" $([[ $rc -eq 0 ]]; echo $?)
  [[ "$(envget "$d/c2.json" MIMO_CHAT_COMPLETIONS_URL)" == "https://open.bigmodel.cn/api/paas/v4/chat/completions" ]]
  check "zhipu: exact MIMO_CHAT_COMPLETIONS_URL default" $?
  [[ "$(envget "$d/c2.json" MIMO_MODEL)" == "glm-custom" ]]
  check "zhipu: ZHIPU_MODEL override honored" $?
  [[ "$(envget "$d/c2.json" REVIEW_LABEL)" == "subglm-review" ]]
  check "zhipu: REVIEW_LABEL preserved" $?
  [[ -z "$(envget "$d/c2.json" MIMO_BASE_URL)" ]]
  check "zhipu: stray MIMO_BASE_URL scrubbed" $?
  [[ "$(envget "$d/c2.json" MIMO_TIMEOUT)" == "123" ]]
  check "zhipu: ZHIPU_TIMEOUT override honored" $?

  # auth-file fallback: no *_API_KEY in env -> key read from JSON auth file
  printf '{"key":"file-key-zhipu"}' > "$d/zauth.json"
  env -u ZHIPU_API_KEY CAPTURE="$d/c3.json" ZHIPU_AUTH_FILE="$d/zauth.json" \
    bash "$b/subchat" zhipu review "$d/t.md" "$d/o3.log" "$d" >/dev/null 2>&1; rc=$?
  check "zhipu auth-file fallback exits 0" $([[ $rc -eq 0 ]]; echo $?)
  [[ "$(envget "$d/c3.json" MIMO_API_KEY)" == "file-key-zhipu" ]]
  check "zhipu: key loaded from auth file" $?
  printf '{"key":"file-key-ds"}' > "$d/sauth.json"
  env -u DEEPSEEK_API_KEY CAPTURE="$d/c4.json" DEEPSEEK_AUTH_FILE="$d/sauth.json" \
    bash "$b/subchat" deepseek review "$d/t.md" "$d/o4.log" "$d" >/dev/null 2>&1; rc=$?
  check "deepseek auth-file fallback exits 0" $([[ $rc -eq 0 ]]; echo $?)
  [[ "$(envget "$d/c4.json" MIMO_API_KEY)" == "file-key-ds" ]]
  check "deepseek: key loaded from auth file" $?
  # missing key everywhere is a hard error
  env -u DEEPSEEK_API_KEY CAPTURE="$d/c5.json" DEEPSEEK_AUTH_FILE="$d/nope.json" \
    bash "$b/subchat" deepseek review "$d/t.md" "$d/o5.log" "$d" >/dev/null 2>&1; rc=$?
  check "missing key + missing auth file is a hard error" $([[ $rc -ne 0 ]]; echo $?)
  # malformed auth JSON is a hard error, not a silent empty key
  printf '{"key":' > "$d/bad.json"
  env -u ZHIPU_API_KEY CAPTURE="$d/c5b.json" ZHIPU_AUTH_FILE="$d/bad.json" \
    bash "$b/subchat" zhipu review "$d/t.md" "$d/o5b.log" "$d" >/dev/null 2>&1; rc=$?
  check "malformed auth JSON is a hard error" $([[ $rc -ne 0 ]]; echo $?)

  # -h through a shim lands in subchat's $2 and must still print usage, rc=0
  bash "$b/subdeepseek" -h >"$d/h.out" 2>"$d/h.err"; rc=$?
  check "subdeepseek -h exits 0" $([[ $rc -eq 0 ]]; echo $?)
  grep -q "Usage" "$d/h.out" "$d/h.err" 2>/dev/null; check "subdeepseek -h prints usage" $?

  # fix stays refused, on subchat and through a shim
  env CAPTURE="$d/c6.json" ZHIPU_API_KEY=zk \
    bash "$b/subchat" zhipu fix "$d/t.md" "$d/o6.log" "$d" >/dev/null 2>&1; rc=$?
  check "subchat zhipu fix refused" $([[ $rc -ne 0 ]]; echo $?)
  env CAPTURE="$d/c7.json" DEEPSEEK_API_KEY=sk \
    bash "$b/subdeepseek" fix "$d/t.md" "$d/o7.log" "$d" >/dev/null 2>&1; rc=$?
  check "subdeepseek shim fix refused" $([[ $rc -ne 0 ]]; echo $?)

  # subglm shim end-to-end: literal include glob survives the shim->subchat chain
  ( cd "$d"; touch decoy_c.py
    env CAPTURE="$d/c8.json" ZHIPU_API_KEY=zk ZHIPU_INCLUDE="*.py" \
      bash "$b/subglm" review "$d/t.md" "$d/o8.log" "$d" >/dev/null 2>&1 )
  if [[ -f "$d/c8.json" ]]; then
    python3 -c "import json,sys;a=json.load(open(sys.argv[1]))['argv'];sys.exit(0 if '*.py' in a else 1)" "$d/c8.json"
    check "subglm shim: literal '*.py' reached engine" $?
    python3 -c "import json,sys;a=json.load(open(sys.argv[1]))['argv'];sys.exit(1 if 'decoy_c.py' in a else 0)" "$d/c8.json"
    check "subglm shim: no CWD-expanded decoy leaked" $?
  else
    bad "subglm shim invoked stub engine"
    bad "subglm shim invoked stub engine (decoy)"
  fi
  rm -rf "$d"
}

# ---------------------------------------------------------------- V9
v9_subglm_agent() {
  echo "[V9] subglm-agent: claude-shell env injection, read-only tools, verdict gate"
  local d b rc; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"
  # subglm-agent 是瘦 shim,躯干在 subagent(V21);bin/ 成套部署,两个都要 cp。
  cp "$BIN/subglm-agent" "$BIN/subagent" "$b/"
  # stub claude: record argv + the env subglm-agent must (and must not) inject,
  # then emit STUB_REVIEW_OUT as the review text.
  cat > "$b/claude" <<'PYEOF'
#!/usr/bin/env python3
import sys, os, json
out = {"argv": sys.argv[1:],
       "stdin": sys.stdin.read() if not sys.stdin.isatty() else "",
       "env": {k: os.environ.get(k) for k in
               ["ANTHROPIC_AUTH_TOKEN","ANTHROPIC_BASE_URL",
                "ANTHROPIC_DEFAULT_SONNET_MODEL","ANTHROPIC_DEFAULT_OPUS_MODEL",
                "ANTHROPIC_DEFAULT_HAIKU_MODEL","ANTHROPIC_API_KEY"]},
       "cwd": os.getcwd()}
open(os.environ["CAPTURE"], "w").write(json.dumps(out))
# 真 claude 在 --output-format stream-json 下吐的是 JSONL;stub 照同一个契约说话。
text = os.environ.get("STUB_REVIEW_OUT", "stub review\nConclusion: PASS")
print(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}}))
PYEOF
  chmod +x "$b/claude"
  printf '# review this\n' > "$d/t.md"
  agentget() { python3 -c "import json,sys;o=json.load(open(sys.argv[1]));v=o['env'].get(sys.argv[2]);print('' if v is None else v)" "$1" "$2"; }
  argvhas() { python3 -c "import json,sys;a=json.load(open(sys.argv[1]))['argv'];sys.exit(0 if sys.argv[2] in ' '.join(a) else 1)" "$1" "$2"; }

  # env-key path: token, base url, model mapping, API_KEY scrubbed
  env PATH="$b:$PATH" CAPTURE="$d/a1.json" ANTHROPIC_API_KEY=real-anthropic-key \
    ZHIPU_API_KEY=zk-env ZHIPU_MODEL=glm-4.6 \
    bash "$b/subglm-agent" review "$d/t.md" "$d/a1.log" "$d" >/dev/null 2>&1; rc=$?
  check "agent review (env key) exits 0" $([[ $rc -eq 0 ]]; echo $?)
  [[ "$(agentget "$d/a1.json" ANTHROPIC_AUTH_TOKEN)" == "zk-env" ]]
  check "agent: AUTH_TOKEN from ZHIPU_API_KEY" $?
  [[ "$(agentget "$d/a1.json" ANTHROPIC_BASE_URL)" == "https://open.bigmodel.cn/api/anthropic" ]]
  check "agent: default Anthropic-compatible base URL" $?
  [[ "$(agentget "$d/a1.json" ANTHROPIC_DEFAULT_SONNET_MODEL)" == "glm-4.6" ]]
  check "agent: sonnet slot mapped to ZHIPU_MODEL" $?
  [[ -z "$(agentget "$d/a1.json" ANTHROPIC_API_KEY)" ]]
  check "agent: stray ANTHROPIC_API_KEY scrubbed" $?
  grep -q "Conclusion: PASS" "$d/a1.log"; check "agent: review text lands in log" $?
  # the task content must reach claude via STDIN (a trailing positional prompt
  # would be swallowed by the variadic --disallowedTools list)
  python3 -c "import json,sys;o=json.load(open(sys.argv[1]));sys.exit(0 if 'review this' in o.get('stdin','') else 1)" "$d/a1.json"
  check "agent: task content reaches claude via stdin" $?
  python3 -c "import json,sys;o=json.load(open(sys.argv[1]));sys.exit(1 if any('review this' in x for x in o['argv']) else 0)" "$d/a1.json"
  check "agent: prompt not passed as positional argv" $?

  # read-only tool posture on argv
  argvhas "$d/a1.json" "--allowedTools";    check "agent: --allowedTools present" $?
  argvhas "$d/a1.json" "Read";              check "agent: Read allowed" $?
  if python3 -c "import json,sys;a=json.load(open(sys.argv[1]))['argv'];i=a.index('--allowedTools');rest=a[i+1:];j=[k for k,x in enumerate(rest) if x.startswith('--')];seg=rest[:j[0]] if j else rest;sys.exit(1 if any(t in seg for t in ('Write','Edit','NotebookEdit')) else 0)" "$d/a1.json"; then
    ok "agent: no write-capable tool in allowlist"
  else
    bad "agent: no write-capable tool in allowlist"
  fi
  argvhas "$d/a1.json" "--disallowedTools"; check "agent: --disallowedTools present" $?
  argvhas "$d/a1.json" "Write";             check "agent: Write explicitly disallowed" $?
  argvhas "$d/a1.json" "Agent";             check "agent: subagent tool (Agent) disallowed" $?
  argvhas "$d/a1.json" "Bash(git diff:*)";  check "agent: Bash limited to git read-only patterns" $?
  argvhas "$d/a1.json" "--model sonnet";    check "agent: --model sonnet (mapped slot)" $?
  argvhas "$d/a1.json" "--setting-sources project"; check "agent: user settings not loaded" $?
  argvhas "$d/a1.json" "--max-turns";       check "agent: turn cap present" $?

  # auth-file fallback
  printf '{"key":"zk-file"}' > "$d/auth.json"
  env -u ZHIPU_API_KEY PATH="$b:$PATH" CAPTURE="$d/a2.json" ZHIPU_AUTH_FILE="$d/auth.json" \
    bash "$b/subglm-agent" review "$d/t.md" "$d/a2.log" "$d" >/dev/null 2>&1; rc=$?
  check "agent auth-file fallback exits 0" $([[ $rc -eq 0 ]]; echo $?)
  [[ "$(agentget "$d/a2.json" ANTHROPIC_AUTH_TOKEN)" == "zk-file" ]]
  check "agent: key loaded from auth file" $?

  # verdict gate: no Conclusion -> non-zero, log still written
  env PATH="$b:$PATH" CAPTURE="$d/a3.json" ZHIPU_API_KEY=zk \
    STUB_REVIEW_OUT="looks fine to me" \
    bash "$b/subglm-agent" review "$d/t.md" "$d/a3.log" "$d" >/dev/null 2>&1; rc=$?
  check "agent: verdict-less output exits non-zero" $([[ $rc -ne 0 ]]; echo $?)
  [[ -f "$d/a3.log" ]]; check "agent: log still written on verdict miss" $?

  # verdict gate: Chinese 「结论：PASS」 (full-width colon) accepted — the drift
  # that bit subdeepseek twice (Track B + client-tools)
  env PATH="$b:$PATH" CAPTURE="$d/a3b.json" ZHIPU_API_KEY=zk \
    STUB_REVIEW_OUT=$'review body\n结论：PASS' \
    bash "$b/subglm-agent" review "$d/t.md" "$d/a3b.log" "$d" >/dev/null 2>&1; rc=$?
  check "agent: Chinese 结论+full-width colon accepted" $([[ $rc -eq 0 ]]; echo $?)

  # fix refused; -h ok
  env PATH="$b:$PATH" CAPTURE="$d/a4.json" ZHIPU_API_KEY=zk \
    bash "$b/subglm-agent" fix "$d/t.md" "$d/a4.log" "$d" >/dev/null 2>&1; rc=$?
  check "agent: fix refused" $([[ $rc -ne 0 ]]; echo $?)
  bash "$b/subglm-agent" -h >/dev/null 2>&1; check "agent: -h exits 0" $?

  # panel-review leg selection: default=agent, PANEL_GLM_LEG=chat, missing agent
  local pb="$d/panelbin"; mkdir -p "$pb"
  cp "$BIN/panel-review" "$pb/panel-review"
  for stubname in submimo subdeepseek; do
    cat > "$pb/$stubname" <<'EOF'
#!/usr/bin/env bash
echo "other leg" > "$3"; exit 0
EOF
    chmod +x "$pb/$stubname"
  done
  cat > "$pb/subglm" <<'EOF'
#!/usr/bin/env bash
echo "CHAT-LEG" > "$3"; exit 0
EOF
  cat > "$pb/subglm-agent" <<'EOF'
#!/usr/bin/env bash
echo "AGENT-LEG" > "$3"; exit 0
EOF
  chmod +x "$pb/subglm" "$pb/subglm-agent"
  bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/P1" >/dev/null 2>&1
  grep -q AGENT-LEG "$d/P1.subglm.log"; check "panel: GLM leg defaults to agent" $?
  PANEL_GLM_LEG=chat bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/P2" >/dev/null 2>&1
  grep -q CHAT-LEG "$d/P2.subglm.log"; check "panel: PANEL_GLM_LEG=chat forces chat leg" $?
  rm -f "$pb/subglm-agent"
  bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/P3" >/dev/null 2>&1
  grep -q CHAT-LEG "$d/P3.subglm.log"; check "panel: missing agent falls back to chat leg" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- V10
v10_git_stderr_isolation() {
  echo "[V10] git stderr never pollutes values or prompt (F4/F5, 07-04 存量债)"
  local d; d="$(mktemp -d)"

  # F4: non-git dir -> fatal text must NOT appear as diff content, BLIND must fire
  local nr="$d/notrepo"; mkdir -p "$nr"; printf '# t\n' > "$d/t.md"
  dry_prompt "$d/t.md" "$d/f4.log" --repo "$nr" >/dev/null 2>"$d/f4.err"
  if grep -q "fatal: not a git repository" "$d/f4.log"; then
    bad "F4: no fatal text in prompt for non-git dir"
  else ok "F4: no fatal text in prompt for non-git dir"; fi
  grep -q "BLIND" "$d/f4.err"; check "F4: BLIND warning fires in non-git dir" $?

  # F5: git stderr noise must not pollute the merge-base value
  local repo="$d/repo" gb; gb="$(command -v git)"; mkdir -p "$d/shim"
  printf '#!/bin/bash\necho "warning: shim noise" >&2\nexec %s "$@"\n' "$gb" > "$d/shim/git"
  chmod +x "$d/shim/git"
  ( cd "$repo" 2>/dev/null || mkdir -p "$repo" && cd "$repo"
    git init -q -b main; git config user.email t@t; git config user.name t
    echo base > f.txt; git add f.txt; git commit -qm init
    git checkout -qb feat; echo featline >> f.txt; git add f.txt; git commit -qm feat )
  PATH="$d/shim:$PATH" PANEL_DIFF_BASE=main \
    dry_prompt "$d/t.md" "$d/f5.log" --repo "$repo" >/dev/null 2>"$d/f5.err"
  grep -q "featline" "$d/f5.log"; check "F5: branch diff vs merge-base survives stderr noise" $?
  if grep -qE "shim noise|ambiguous argument|fatal:" "$d/f5.log"; then
    bad "F5: no stderr noise leaked into prompt"
  else ok "F5: no stderr noise leaked into prompt"; fi
  rm -rf "$d"
}

# ---------------------------------------------------------------- V11
v11_panel_gates() {
  echo "[V11] panel-review: PANEL_ORACLE_CMD 记录位 + --require-my-review 闸门"
  local d pb; d="$(mktemp -d)"; pb="$d/bin"; mkdir -p "$pb" "$d/repo"
  cp "$BIN/panel-review" "$pb/panel-review"
  for leg in submimo subdeepseek subglm; do
    printf '#!/bin/bash\necho "STUB PASS" > "$3"\nexit 0\n' > "$pb/$leg"
    chmod +x "$pb/$leg"
  done
  printf '# t\n' > "$d/t.md"
  ( cd "$d/repo"; git init -q )

  # oracle red: recorded + loud warning, but NOT blocking (rc stays 0)
  PANEL_ORACLE_CMD="exit 3" bash "$pb/panel-review" --no-my-review "$d/t.md" "$d/repo" "$d/O1" >"$d/o1.out" 2>&1
  check "oracle red: panel still exits 0" $?
  grep -q "ORACLE:.*rc=3" "$d/o1.out"; check "oracle red: rc recorded on stdout" $?
  grep -qi "oracle is RED" "$d/o1.out"; check "oracle red: loud warning printed" $?
  [[ -f "$d/O1.oracle.log" ]]; check "oracle red: output captured to sidecar log" $?

  # oracle green: recorded, no red warning
  PANEL_ORACLE_CMD="true" bash "$pb/panel-review" --no-my-review "$d/t.md" "$d/repo" "$d/O2" >"$d/o2.out" 2>&1
  grep -q "ORACLE:.*rc=0" "$d/o2.out"; check "oracle green: rc=0 recorded" $?
  if grep -qi "oracle is RED" "$d/o2.out"; then bad "oracle green: no red warning"
  else ok "oracle green: no red warning"; fi

  # --require-my-review: missing file refuses to dispatch
  bash "$pb/panel-review" --require-my-review "$d/nope.md" "$d/t.md" "$d/repo" "$d/M1" \
    >"$d/m1.out" 2>&1
  [[ $? -ne 0 ]]; check "my-review missing: non-zero exit" $?
  [[ ! -f "$d/M1.submimo.log" ]]; check "my-review missing: no dispatch happened" $?

  # --require-my-review: file inside the repo under review is rejected
  echo r > "$d/repo/selfrev.md"
  bash "$pb/panel-review" --require-my-review "$d/repo/selfrev.md" "$d/t.md" "$d/repo" "$d/M2" \
    >"$d/m2.out" 2>&1
  [[ $? -ne 0 ]]; check "my-review inside repo: rejected" $?
  grep -qi "inside" "$d/m2.out"; check "my-review inside repo: reason names the leak" $?

  # --require-my-review: valid outside file passes through
  echo r > "$d/myrev.md"
  bash "$pb/panel-review" --require-my-review "$d/myrev.md" "$d/t.md" "$d/repo" "$d/M3" \
    >"$d/m3.out" 2>&1
  check "my-review valid: panel runs" $?
  [[ -f "$d/M3.submimo.log" ]]; check "my-review valid: dispatch happened" $?

  # --require-my-review: a symlink PHYSICALLY in the repo but pointing outside
  # must still be rejected (collect_untracked follows it and leaks). realpath
  # alone resolves the link and misses this; needs a lexical check too.
  echo outside > "$d/outside-rev.md"
  ln -s "$d/outside-rev.md" "$d/repo/linkrev.md"
  bash "$pb/panel-review" --require-my-review "$d/repo/linkrev.md" "$d/t.md" "$d/repo" "$d/M4" \
    >"$d/m4.out" 2>&1
  [[ $? -ne 0 ]]; check "my-review repo-internal symlink: rejected" $?
  [[ ! -f "$d/M4.submimo.log" ]]; check "my-review symlink: no dispatch (no leak)" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- V12
v12_gate_default_on() {
  echo "[V12] panel-review my-review gate is DEFAULT-ON (opt-out), auto-arms on convention path"
  local d pb; d="$(mktemp -d)"; pb="$d/bin"; mkdir -p "$pb" "$d/repo"
  cp "$BIN/panel-review" "$pb/panel-review"
  for leg in submimo subdeepseek subglm; do
    printf '#!/bin/bash\necho "STUB PASS" > "$3"\nexit 0\n' > "$pb/$leg"; chmod +x "$pb/$leg"
  done
  ( cd "$d/repo"; git init -q )
  # task file basename drives the convention path the tool looks for
  local t="$d/mytask.md"; printf '# t\n' > "$t"
  local conv="/root/aiwork/tasks/mytask-my-review.md"

  # no flag + no convention file present -> REFUSE (forgetting = tool stops you)
  rm -f "$conv"
  bash "$pb/panel-review" "$t" "$d/repo" "$d/D1" >"$d/d1.out" 2>&1
  [[ $? -ne 0 ]]; check "default-on: refuses when no my-review exists" $?
  [[ ! -f "$d/D1.submimo.log" ]]; check "default-on: no dispatch on refuse" $?
  grep -qi "my-review" "$d/d1.out"; check "default-on: message points at my-review" $?

  # explicit opt-out -> runs
  bash "$pb/panel-review" --no-my-review "$t" "$d/repo" "$d/D2" >/dev/null 2>&1
  check "opt-out --no-my-review: runs" $?
  [[ -f "$d/D2.submimo.log" ]]; check "opt-out: dispatch happened" $?

  # convention file present -> auto-arms with NO flag, runs
  echo "my review" > "$conv"
  bash "$pb/panel-review" "$t" "$d/repo" "$d/D3" >/dev/null 2>&1
  check "auto-arm: convention my-review present -> runs with no flag" $?
  [[ -f "$d/D3.submimo.log" ]]; check "auto-arm: dispatch happened" $?
  rm -f "$conv"
  rm -rf "$d"
}

# ---------------------------------------------------------------- V13
v13_subkimi_leg() {
  echo "[V13] subkimi: guard default-deny, wrapper contract, panel 4th-leg selection"
  local d b rc; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"

  # --- the SHIPPED guard, invoked directly: default-deny semantics
  local guard="/root/aiwork/kimi-review-home/hooks/guard.mjs"
  if [[ -f "$guard" ]]; then
    echo '{"tool_name":"Write","tool_input":{}}' | node "$guard" >/dev/null 2>&1
    check "guard: Write denied (rc=2)" $([[ $? -eq 2 ]]; echo $?)
    echo '{"tool_name":"Read","tool_input":{}}' | node "$guard" >/dev/null 2>&1
    check "guard: Read allowed (rc=0)" $?
    echo '{"tool_name":"Bash","tool_input":{"command":"git log --oneline -3"}}' | node "$guard" >/dev/null 2>&1
    check "guard: read-only git allowed" $?
    echo '{"tool_name":"Bash","tool_input":{"command":"git log && rm -rf /"}}' | node "$guard" >/dev/null 2>&1
    check "guard: metachar chain denied" $([[ $? -eq 2 ]]; echo $?)
    echo '{"tool_name":"Bash","tool_input":{"command":"curl http://evil"}}' | node "$guard" >/dev/null 2>&1
    check "guard: non-git bash denied" $([[ $? -eq 2 ]]; echo $?)
    echo '{"tool_name":"SomeFutureTool","tool_input":{}}' | node "$guard" >/dev/null 2>&1
    check "guard: unknown tool denied (default-deny)" $([[ $? -eq 2 ]]; echo $?)
    echo 'garbage not json' | node "$guard" >/dev/null 2>&1
    check "guard: garbage stdin fails CLOSED (rc=2)" $([[ $? -eq 2 ]]; echo $?)
  else
    bad "shipped guard missing: $guard"
  fi

  # --- subkimi wrapper against a stub kimi + fixture review home
  cp "$BIN/subkimi" "$b/subkimi"
  local rh="$d/review-home"; mkdir -p "$rh/hooks" "$rh/credentials"
  printf 'default_model = "x"\n' > "$rh/config.toml"
  cp "$guard" "$rh/hooks/guard.mjs" 2>/dev/null || printf 'process.exit(2)\n' > "$rh/hooks/guard.mjs"
  echo '{}' > "$rh/credentials/kimi-code.json"
  cat > "$b/kimi" <<'PYEOF'
#!/usr/bin/env python3
import sys, os, json
out = {"argv": sys.argv[1:],
       "env": {k: os.environ.get(k) for k in
               ["KIMI_CODE_HOME", "KIMI_CODE_NO_AUTO_UPDATE"]},
       "cwd": os.getcwd()}
open(os.environ["CAPTURE"], "w").write(json.dumps(out))
print(os.environ.get("STUB_REVIEW_OUT", "stub review\nConclusion: PASS"))
PYEOF
  chmod +x "$b/kimi"
  printf '# review this\n' > "$d/t.md"
  kimiget() { python3 -c "import json,sys;o=json.load(open(sys.argv[1]));v=o['env'].get(sys.argv[2]);print('' if v is None else v)" "$1" "$2"; }

  env PATH="$b:$PATH" CAPTURE="$d/k1.json" KIMI_REVIEW_HOME="$rh" \
    bash "$b/subkimi" review "$d/t.md" "$d/k1.log" "$d" >/dev/null 2>&1; rc=$?
  check "subkimi: review exits 0" $([[ $rc -eq 0 ]]; echo $?)
  [[ "$(kimiget "$d/k1.json" KIMI_CODE_HOME)" == "$rh" ]]
  check "subkimi: KIMI_CODE_HOME points at review home" $?
  [[ "$(kimiget "$d/k1.json" KIMI_CODE_NO_AUTO_UPDATE)" == "1" ]]
  check "subkimi: auto-update disabled" $?
  grep -q 'Conclusion: PASS' "$d/k1.log"; check "subkimi: verdict recorded in log" $?

  env PATH="$b:$PATH" CAPTURE="$d/k2.json" KIMI_REVIEW_HOME="$rh" STUB_REVIEW_OUT="no verdict here" \
    bash "$b/subkimi" review "$d/t.md" "$d/k2.log" "$d" >/dev/null 2>&1; rc=$?
  check "subkimi: verdict-less output rejected" $([[ $rc -ne 0 ]]; echo $?)

  # Chinese-style verdict (结论 + full-width colon) must pass the gate — the
  # drift that bit subdeepseek twice (Track B + client-tools).
  env PATH="$b:$PATH" CAPTURE="$d/k2b.json" KIMI_REVIEW_HOME="$rh" \
    STUB_REVIEW_OUT=$'review body\n结论：PASS' \
    bash "$b/subkimi" review "$d/t.md" "$d/k2b.log" "$d" >/dev/null 2>&1; rc=$?
  check "subkimi: Chinese 结论+full-width colon accepted" $([[ $rc -eq 0 ]]; echo $?)

  env PATH="$b:$PATH" CAPTURE="$d/k3.json" KIMI_REVIEW_HOME="$rh" \
    bash "$b/subkimi" fix "$d/t.md" "$d/k3.log" "$d" >/dev/null 2>&1; rc=$?
  check "subkimi: fix refused" $([[ $rc -ne 0 ]]; echo $?)

  # broken (fail-open) guard must refuse to dispatch BEFORE invoking kimi
  local rh2="$d/review-home2"; mkdir -p "$rh2/hooks" "$rh2/credentials"
  printf 'default_model = "x"\n' > "$rh2/config.toml"
  printf 'process.exit(0)\n' > "$rh2/hooks/guard.mjs"
  echo '{}' > "$rh2/credentials/kimi-code.json"
  rm -f "$d/k4.json"
  env PATH="$b:$PATH" CAPTURE="$d/k4.json" KIMI_REVIEW_HOME="$rh2" \
    bash "$b/subkimi" review "$d/t.md" "$d/k4.log" "$d" >/dev/null 2>&1; rc=$?
  check "subkimi: fail-open guard refused (preflight)" $([[ $rc -ne 0 ]]; echo $?)
  if [[ -e "$d/k4.json" ]]; then bad "subkimi: kimi never invoked on bad guard"; else ok "subkimi: kimi never invoked on bad guard"; fi

  bash "$b/subkimi" -h >/dev/null 2>&1; check "subkimi: -h exits 0" $?

  # --- panel-review 4th-leg selection
  local pb="$d/panelbin"; mkdir -p "$pb"
  cp "$BIN/panel-review" "$pb/panel-review"
  for stubname in submimo subdeepseek subglm; do
    cat > "$pb/$stubname" <<'EOF'
#!/usr/bin/env bash
echo "other leg" > "$3"; exit 0
EOF
    chmod +x "$pb/$stubname"
  done
  cat > "$pb/subkimi" <<'EOF'
#!/usr/bin/env bash
echo "KIMI-LEG" > "$3"; exit 0
EOF
  chmod +x "$pb/subkimi"
  bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/K1" >/dev/null 2>&1
  grep -q KIMI-LEG "$d/K1.subkimi.log" 2>/dev/null; check "panel: subkimi auto-enabled when installed" $?
  PANEL_KIMI_LEG=off bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/K2" >/dev/null 2>&1
  if [[ -e "$d/K2.subkimi.log" ]]; then bad "panel: PANEL_KIMI_LEG=off skips kimi"; else ok "panel: PANEL_KIMI_LEG=off skips kimi"; fi

  # 2026-08-04:智谱账号余额不足(429/1113),每轮四审都白等它超时一次。
  # 用户拍板「先关掉,等我重置了再开」⇒ GLM 腿要能像 kimi 一样被关,而且
  # **默认就是关的**(不是靠每次记得加环境变量 —— 那正是自述型开关的老毛病)。
  # 充值后打开的方式:PANEL_GLM_LEG=agent(或把脚本里的默认值改回 agent)。
  env -u PANEL_GLM_LEG bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/G1" >/dev/null 2>&1
  if [[ -e "$d/G1.subglm.log" ]]; then bad "panel: GLM 腿默认关闭(欠费期间不白等)"; else ok "panel: GLM 腿默认关闭(欠费期间不白等)"; fi
  PANEL_GLM_LEG=agent bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/G2" >/dev/null 2>&1
  if [[ -e "$d/G2.subglm.log" ]]; then ok "panel: PANEL_GLM_LEG=agent 能把它开回来"; else bad "panel: PANEL_GLM_LEG=agent 能把它开回来"; fi

  # exit semantics: 3 classic legs fail + kimi passes -> evidence exists -> rc=0
  for stubname in submimo subdeepseek subglm; do
    cat > "$pb/$stubname" <<'EOF'
#!/usr/bin/env bash
echo "stub result" > "$3"; echo fail >&2; exit 7
EOF
    chmod +x "$pb/$stubname"
  done
  bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/K3" >/dev/null 2>&1; rc=$?
  check "panel: 3 legs fail + kimi passes -> rc=0" $([[ $rc -eq 0 ]]; echo $?)
  # all 4 fail -> rc=1
  cat > "$pb/subkimi" <<'EOF'
#!/usr/bin/env bash
echo "stub result" > "$3"; echo fail >&2; exit 7
EOF
  chmod +x "$pb/subkimi"
  bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/K4" >/dev/null 2>&1; rc=$?
  check "panel: all 4 legs fail -> rc=1" $([[ $rc -ne 0 ]]; echo $?)
  # kimi absent -> classic 3-leg panel still works
  rm -f "$pb/subkimi"
  for stubname in submimo subdeepseek subglm; do
    cat > "$pb/$stubname" <<'EOF'
#!/usr/bin/env bash
echo "other leg" > "$3"; exit 0
EOF
    chmod +x "$pb/$stubname"
  done
  bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/K5" >/dev/null 2>&1; rc=$?
  check "panel: no subkimi installed -> classic 3-leg rc=0" $([[ $rc -eq 0 ]]; echo $?)
  if [[ -e "$d/K5.subkimi.log" ]]; then bad "panel: no kimi log when absent"; else ok "panel: no kimi log when absent"; fi
  rm -rf "$d"
}

# ---------------------------------------------------------------- V14
v14_leg_fallback_and_include() {
  echo "[V14] panel-review: agent 腿失败自动回落 chat 腿 + PANEL_INCLUDE 喂 oracle + DS 轮次上限"
  local d pb rc; d="$(mktemp -d)"; pb="$d/bin"; mkdir -p "$pb" "$d/repo"
  cp "$BIN/panel-review" "$pb/panel-review"
  printf '# review\n' > "$d/t.md"
  # 中立的两条腿(不参与本组断言)
  for leg in submimo subkimi; do
    printf '#!/bin/bash\necho "STUB PASS" > "$3"\nexit 0\n' > "$pb/$leg"; chmod +x "$pb/$leg"
  done

  # --- ① agent 腿失败 → 自动回落 chat 腿(GLM:CodingPlan 未订阅那种 400 即死)
  cat > "$pb/subglm-agent" <<'EOF'
#!/usr/bin/env bash
echo "API Error: 400 does not have a valid CodingPlan subscription" >&2
echo "AGENT-JUNK" > "$3"
exit 1
EOF
  printf '#!/bin/bash\necho "CHAT-LEG-GLM" > "$3"\nexit 0\n' > "$pb/subglm"
  # --- ② 同样适用于 DeepSeek(max turns 那种)
  cat > "$pb/subdeepseek-agent" <<'EOF'
#!/usr/bin/env bash
echo "Error: Reached max turns (40)" >&2
echo "AGENT-JUNK" > "$3"
exit 1
EOF
  printf '#!/bin/bash\necho "CHAT-LEG-DS" > "$3"\nexit 0\n' > "$pb/subdeepseek"
  chmod +x "$pb/subglm" "$pb/subglm-agent" "$pb/subdeepseek" "$pb/subdeepseek-agent"

  bash "$pb/panel-review" --no-my-review "$d/t.md" "$d/repo" "$d/F1" >"$d/f1.out" 2>&1; rc=$?
  check "V14: 两条 agent 腿都失败仍 rc=0(chat 腿顶上)" $([[ $rc -eq 0 ]]; echo $?)
  grep -q "CHAT-LEG-GLM" "$d/F1.subglm.log"; check "V14: GLM agent 腿失败 → 日志是 chat 腿的卷" $?
  grep -q "CHAT-LEG-DS" "$d/F1.subdeepseek.log"; check "V14: DeepSeek agent 腿失败 → chat 腿顶上" $?
  grep -qi "fallback\|回落" "$d/f1.out"; check "V14: 控制台明说发生了回落(不许静默)" $?
  # 失败的 agent 产出必须留证,不许被 chat 腿覆盖抹掉
  [[ -s "$d/F1.subglm.agent.log" || -s "$d/F1.subglm.agent.log.err" ]]
  check "V14: 失败的 agent 腿产出另存留证" $?
  grep -q "CodingPlan" "$d/F1.subglm.agent.log.err" 2>/dev/null
  check "V14: agent 腿的失败原因可追(stderr 留在 .agent.log.err)" $?

  # --- ③ agent 与 chat 都失败 → 该腿算失败(err 侧车留着)
  printf '#!/bin/bash\necho "chat also broke" >&2\nexit 1\n' > "$pb/subglm"; chmod +x "$pb/subglm"
  bash "$pb/panel-review" --no-my-review "$d/t.md" "$d/repo" "$d/F2" >/dev/null 2>&1
  [[ -s "$d/F2.subglm.log.err" ]]; check "V14: 双失败仍留 .err 侧车" $?
  printf '#!/bin/bash\necho "CHAT-LEG-GLM" > "$3"\nexit 0\n' > "$pb/subglm"; chmod +x "$pb/subglm"

  # --- ④ PANEL_INCLUDE 转发给 chat 腿(chat 腿只吃增量 diff,看不到基线里的 oracle)
  cat > "$pb/subglm" <<'EOF'
#!/usr/bin/env bash
echo "ZHIPU_INCLUDE=[${ZHIPU_INCLUDE:-}]" > "$3"; exit 0
EOF
  cat > "$pb/subdeepseek" <<'EOF'
#!/usr/bin/env bash
echo "DEEPSEEK_INCLUDE=[${DEEPSEEK_INCLUDE:-}]" > "$3"; exit 0
EOF
  chmod +x "$pb/subglm" "$pb/subdeepseek"
  PANEL_GLM_LEG=chat PANEL_DEEPSEEK_LEG=chat     PANEL_INCLUDE="tests/test_a.py tests/e2e/b.mjs"     bash "$pb/panel-review" --no-my-review "$d/t.md" "$d/repo" "$d/F3" >"$d/f3.out" 2>&1
  grep -q "ZHIPU_INCLUDE=\[tests/test_a.py tests/e2e/b.mjs\]" "$d/F3.subglm.log"
  check "V14: PANEL_INCLUDE 原样转成 ZHIPU_INCLUDE" $?
  grep -q "DEEPSEEK_INCLUDE=\[tests/test_a.py tests/e2e/b.mjs\]" "$d/F3.subdeepseek.log"
  check "V14: PANEL_INCLUDE 原样转成 DEEPSEEK_INCLUDE" $?

  # 没给 PANEL_INCLUDE 而确实有 chat 腿在跑 → 必须提醒(它看不到基线里的 oracle)
  PANEL_GLM_LEG=chat PANEL_DEEPSEEK_LEG=chat     bash "$pb/panel-review" --no-my-review "$d/t.md" "$d/repo" "$d/F4" >"$d/f4.out" 2>&1
  grep -qi "PANEL_INCLUDE" "$d/f4.out"; check "V14: 有 chat 腿却没喂 oracle 时出提醒" $?
  # 全 agent 腿时不该乱提醒
  cat > "$pb/subglm-agent" <<'EOF'
#!/usr/bin/env bash
echo "AGENT-OK" > "$3"; exit 0
EOF
  cat > "$pb/subdeepseek-agent" <<'EOF'
#!/usr/bin/env bash
echo "AGENT-OK" > "$3"; exit 0
EOF
  chmod +x "$pb/subglm-agent" "$pb/subdeepseek-agent"
  bash "$pb/panel-review" --no-my-review "$d/t.md" "$d/repo" "$d/F5" >"$d/f5.out" 2>&1
  if grep -qi "PANEL_INCLUDE" "$d/f5.out"; then
    bad "V14: 全 agent 腿时不该提 PANEL_INCLUDE"
  else ok "V14: 全 agent 腿时不该提 PANEL_INCLUDE"; fi

  # --- ⑤ subdeepseek-agent 的轮次上限:默认放宽到 80,env 仍可覆盖
  local ab="$d/agentbin"; mkdir -p "$ab"
  # 瘦 shim + 共享躯干(V21):bin/ 成套部署,subagent 也要 cp,否则被测脚本起不来。
  cp "$BIN/subdeepseek-agent" "$BIN/subagent" "$ab/"
  cat > "$ab/claude" <<'PYEOF'
#!/usr/bin/env python3
import sys, os, json
open(os.environ["CAPTURE"], "w").write(json.dumps({"argv": sys.argv[1:]}))
# 底座腿走 --output-format stream-json(V20),stub 照同一契约说话
print(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "stub review\nConclusion: PASS"}]}}))
PYEOF
  chmod +x "$ab/claude"
  turns() { python3 -c "import json,sys;a=json.load(open(sys.argv[1]))['argv'];print(a[a.index('--max-turns')+1])" "$1"; }
  env PATH="$ab:$PATH" CAPTURE="$d/ds1.json" DEEPSEEK_API_KEY=dk     bash "$ab/subdeepseek-agent" review "$d/t.md" "$d/ds1.log" "$d/repo" >/dev/null 2>&1
  [[ "$(turns "$d/ds1.json")" -ge 80 ]]
  check "V14: subdeepseek-agent 默认轮次上限 ≥80(40 撞墙实事故)" $?
  env PATH="$ab:$PATH" CAPTURE="$d/ds2.json" DEEPSEEK_API_KEY=dk DEEPSEEK_MAX_TURNS=25     bash "$ab/subdeepseek-agent" review "$d/t.md" "$d/ds2.log" "$d/repo" >/dev/null 2>&1
  [[ "$(turns "$d/ds2.json")" == "25" ]]
  check "V14: DEEPSEEK_MAX_TURNS 仍可覆盖" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- V15
v15_anchor_leak_warning() {
  echo "[V15] panel-review: 主审自己的评审落进被评 diff 时报警(反锚定,07-21 实事故)"
  local d pb; d="$(mktemp -d)"; pb="$d/bin"; mkdir -p "$pb"
  cp "$BIN/panel-review" "$pb/panel-review"
  for leg in submimo subdeepseek subglm subkimi; do
    printf '#!/bin/bash\necho "STUB PASS" > "$3"\nexit 0\n' > "$pb/$leg"; chmod +x "$pb/$leg"
  done
  printf '# review\n' > "$d/t.md"
  local repo="$d/repo"; mkdir -p "$repo/tracks/x"
  ( cd "$repo"; git init -q; git config user.email t@t; git config user.name t
    echo base > f.txt; git add -A; git commit -qm init )

  # 干净仓:不该报警
  bash "$pb/panel-review" --no-my-review "$d/t.md" "$repo" "$d/A1" >"$d/a1.out" 2>&1
  if grep -qi "anchor\|锚定" "$d/a1.out"; then bad "V15: 干净仓不该报锚定"; else ok "V15: 干净仓不该报锚定"; fi

  # 未提交的 verify.md(带主审 findings)在仓里 → 会被 collect_untracked 喂给评审腿
  printf '# Verify\n- findings: M1 主审抓到的真问题\n' > "$repo/tracks/x/verify.md"
  bash "$pb/panel-review" --no-my-review "$d/t.md" "$repo" "$d/A2" >"$d/a2.out" 2>&1
  grep -qi "anchor\|锚定" "$d/a2.out"; check "V15: 仓里有 verify.md 时报锚定风险" $?

  # 已提交进被评 diff 的 verify.md(= 07-21 的真实踩法)
  ( cd "$repo"; git add -A; git commit -qm "verify" )
  PANEL_DIFF_BASE=HEAD~1 bash "$pb/panel-review" --no-my-review "$d/t.md" "$repo" "$d/A3" >"$d/a3.out" 2>&1
  grep -qi "anchor\|锚定" "$d/a3.out"; check "V15: verify.md 已提交进 diff 时同样报警" $?

  # 报警不阻断:腿照跑,rc 照常
  [[ -s "$d/A3.subglm.log" ]]; check "V15: 报警只是提醒,不阻断派发" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- V16
v16_timeout_and_blind_chat_leg() {
  echo "[V16] subkimi 超时可用性 + chat 腿「先 commit 再派发 = 空 diff 盲评」(07-27 实事故)"
  local d pb rc; d="$(mktemp -d)"; pb="$d/bin"; mkdir -p "$pb"

  # --- ① subkimi:超时后仍要留下裁决 → prompt 必须要求「一有结论就先写出来」
  # 07-27 取证:kimi 900s 被砍时,最值钱的发现已经在正文里,唯独裁决行没写成
  # (prompt 原文要求 "MUST end your review with a final line")。工具调用只有个位数,
  # 时间全花在长推理上 —— 所以解法不是缩小它的自读面,而是让裁决先落地。
  cp "$BIN/subkimi" "$pb/subkimi"
  local rh="$d/review-home"; mkdir -p "$rh/hooks" "$rh/credentials"
  printf 'default_model = "x"\n' > "$rh/config.toml"
  printf 'process.exit(2)\n' > "$rh/hooks/guard.mjs"
  echo '{}' > "$rh/credentials/kimi-code.json"
  # stub timeout:记下它拿到的秒数,再原样执行后面的命令
  cat > "$pb/timeout" <<'EOF'
#!/usr/bin/env bash
echo "$1" > "$CAPTURE_TIMEOUT"; shift; exec "$@"
EOF
  chmod +x "$pb/timeout"
  cat > "$pb/kimi" <<'EOF'
#!/usr/bin/env bash
# 把收到的 prompt 原样落盘,供断言检查
while [[ $# -gt 0 ]]; do [[ "$1" == "-p" ]] && { echo "$2" > "$CAPTURE_PROMPT"; }; shift; done
echo "stub review"; echo "Conclusion: PASS"
EOF
  chmod +x "$pb/kimi"
  printf '# review this\n' > "$d/t.md"
  env PATH="$pb:$PATH" KIMI_REVIEW_HOME="$rh" \
      CAPTURE_TIMEOUT="$d/to.txt" CAPTURE_PROMPT="$d/prompt.txt" \
      bash "$pb/subkimi" review "$d/t.md" "$d/k.log" "$d" >/dev/null 2>&1

  [[ "$(cat "$d/to.txt" 2>/dev/null)" -ge 1500 ]]
  check "V16: subkimi 默认超时 ≥1500s(900 实测不够,证据在 07-27 日志)" $?
  # 两个方向都认(「verdict … as soon as」与「as soon as … verdict」都是同一个意思)
  grep -qiE '(conclusion|verdict|裁决).*(as soon as|immediately|一有|尽早|先写)|(as soon as|immediately|一有|尽早|先写).*(conclusion|verdict|裁决)' "$d/prompt.txt"
  check "V16: prompt 要求一有结论就先写出裁决行(超时也能留下裁决)" $?
  grep -q 'Conclusion: PASS | BLOCK | NEEDS_MORE_INFO' "$d/prompt.txt"
  check "V16: 裁决行格式仍逐字给出" $?

  # 超时本身必须不再作废整份评审:裁决行已经写出来了就算数(否则「先写裁决」白做)
  # ⚠️ 必须先撤掉上面那个 stub timeout(它忽略秒数直接 exec),否则这两条根本没真超时
  #    —— 首版判据就栽在这:两条假绿,还各白等 30 秒。
  rm -f "$pb/timeout"
  cat > "$pb/kimi" <<'EOF'
#!/usr/bin/env bash
echo "findings: 一条真发现"; echo "Conclusion: BLOCK"; sleep 30
EOF
  chmod +x "$pb/kimi"
  env PATH="$pb:$PATH" KIMI_REVIEW_HOME="$rh" KIMI_TIMEOUT=2 \
      bash "$pb/subkimi" review "$d/t.md" "$d/kt.log" "$d" >/dev/null 2>"$d/kt.err"; rc=$?
  check "V16: 超时但裁决已写出 → rc=0(评审算数)" $([[ $rc -eq 0 ]]; echo $?)
  grep -qiE 'timed out|超时' "$d/kt.err" "$d/kt.log"
  check "V16: 超时仍要留痕(不静默当成正常完卷)" $?
  # 超时且没有裁决 → 仍然是失败(原语义不变)
  cat > "$pb/kimi" <<'EOF'
#!/usr/bin/env bash
echo "还在想"; sleep 30
EOF
  chmod +x "$pb/kimi"
  env PATH="$pb:$PATH" KIMI_REVIEW_HOME="$rh" KIMI_TIMEOUT=2 \
      bash "$pb/subkimi" review "$d/t.md" "$d/kt2.log" "$d" >/dev/null 2>&1; rc=$?
  check "V16: 超时且无裁决 → 仍判失败" $([[ $rc -ne 0 ]]; echo $?)

  # --- ② chat 腿的空 diff 盲评:先 commit 再派发是本机的**标准流程**,
  # 而 chat 腿默认只看工作区未提交改动 → 它拿到的实现代码是空的。
  # 07-27 实事故:subglm agent 腿挂了回落 chat 腿,报告里自己写着
  # "bin/ds_web.py 的具体实现内容不可得",findings 全是把任务书复述回来。
  local repo="$d/repo"; mkdir -p "$repo"
  ( cd "$repo"; git init -qb main; git config user.email t@t; git config user.name t
    echo base > impl.py; git add -A; git commit -qm init
    git checkout -qb feature; echo "真正要审的实现" >> impl.py
    git add -A; git commit -qm work )
  cp "$BIN/panel-review" "$pb/panel-review"
  for leg in submimo subdeepseek subglm subkimi; do
    printf '#!/bin/bash\necho "DIFF_BASE=${PANEL_DIFF_BASE:-unset}" > "$3"\nexit 0\n' \
      > "$pb/$leg"; chmod +x "$pb/$leg"
  done
  ( cd "$repo" && bash "$pb/panel-review" --no-my-review "$d/t.md" "$repo" "$d/B1" \
      >"$d/b1.out" 2>&1 )
  grep -q 'DIFF_BASE=main' "$d/B1.subglm.log" 2>/dev/null
  check "V16: 工作区干净时 panel 自动把 diff 基线设成默认分支(否则 chat 腿空手评审)" $?

  # 显式给了就不覆盖
  ( cd "$repo" && PANEL_DIFF_BASE=HEAD~1 bash "$pb/panel-review" --no-my-review \
      "$d/t.md" "$repo" "$d/B2" >/dev/null 2>&1 )
  grep -q 'DIFF_BASE=HEAD~1' "$d/B2.subglm.log" 2>/dev/null
  check "V16: 显式 PANEL_DIFF_BASE 不被默认值覆盖" $?

  rm -rf "$d"
}

# ---------------------------------------------------------------- V17
# 两条底座腿(subglm-agent / subdeepseek-agent)的 explore 模式 + panel-explore 选腿。
# 全程用假 claude / 假腿脚本,不打任何真端点、不烧额度。
v17_explore_agent_legs() {
  echo "[V17] panel-explore 走底座腿:explore 模式 + 无裁决闸 + 只读姿态不松"
  local d b rc; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"
  # 瘦 shim + 共享躯干(V21):bin/ 成套部署,subagent 也要 cp,否则被测脚本起不来。
  cp "$BIN/subglm-agent" "$BIN/subdeepseek-agent" "$BIN/subagent" "$b/"
  # 假 claude:把 argv/stdin/env 落盘,输出由 STUB_REVIEW_OUT 控制。
  # 默认输出**不带任何裁决行** —— 发散的正常形态就是没有 Conclusion。
  cat > "$b/claude" <<'PYEOF'
#!/usr/bin/env python3
import sys, os, json
out = {"argv": sys.argv[1:],
       "stdin": sys.stdin.read() if not sys.stdin.isatty() else "",
       "cwd": os.getcwd()}
cap = os.environ.get("CAPTURE")
if cap:
    open(cap, "w").write(json.dumps(out))
text = os.environ.get("STUB_REVIEW_OUT", "Direction: 单一看法\nCore bet: 略")
print(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}}))
PYEOF
  chmod +x "$b/claude"
  printf '# BRIEF\n开放设计分叉,请给一个方向。\n' > "$d/brief.md"
  stdin_has() { python3 -c "import json,sys;o=json.load(open(sys.argv[1]));sys.exit(0 if sys.argv[2] in o.get('stdin','') else 1)" "$1" "$2"; }

  # ---- ① explore 模式必须被接受,且不套裁决闸(输出里没有 Conclusion 也得 rc=0)
  for leg in subglm subdeepseek; do
    local keyenv=(ZHIPU_API_KEY=zk); [[ "$leg" == subdeepseek ]] && keyenv=(DEEPSEEK_API_KEY=dk)
    env PATH="$b:$PATH" CAPTURE="$d/$leg.e1.json" "${keyenv[@]}" \
      bash "$b/$leg-agent" explore "$d/brief.md" "$d/$leg.e1.log" "$d" >/dev/null 2>&1; rc=$?
    check "V17: $leg-agent 接受 explore 模式且无裁决输出仍 rc=0" $([[ $rc -eq 0 ]]; echo $?)
    [[ -s "$d/$leg.e1.log" ]]; check "V17: $leg-agent explore 写出了日志" $?
    # ② 发散提示词到位:要"一个方向",且**不能**再要求裁决行
    stdin_has "$d/$leg.e1.json" "Direction"
    check "V17: $leg-agent explore 提示词带发散格式(Direction)" $?
    # ⚠️ 锚:这条是"不含某串"的否定断言,**捕获文件不存在时它会假绿**
    # (功能还没做 = 文件没生成 = 也"不含" ⇒ 永远绿 = 等于没判)。
    # 先要求捕获存在且确实带着 brief,再问它含不含裁决行。
    if [[ -f "$d/$leg.e1.json" ]] && stdin_has "$d/$leg.e1.json" "开放设计分叉" \
       && ! stdin_has "$d/$leg.e1.json" "Conclusion: PASS"; then
      ok  "V17: $leg-agent explore 提示词不再索要裁决行"
    else
      bad "V17: $leg-agent explore 提示词不再索要裁决行"
    fi
    # ③ 护栏:只读姿态一个字都不许松(换模式 ≠ 换权限)
    python3 -c "import json,sys;a=json.load(open(sys.argv[1]))['argv'];i=a.index('--allowedTools');rest=a[i+1:];j=[k for k,x in enumerate(rest) if x.startswith('--')];seg=rest[:j[0]] if j else rest;sys.exit(1 if any(t in seg for t in ('Write','Edit','NotebookEdit')) else 0)" "$d/$leg.e1.json"
    check "V17: $leg-agent explore 仍无写工具" $?
    python3 -c "import json,sys;a=' '.join(json.load(open(sys.argv[1]))['argv']);sys.exit(0 if '--disallowedTools' in a and 'Write' in a else 1)" "$d/$leg.e1.json"
    check "V17: $leg-agent explore 仍显式禁写" $?
    # ④ 护栏:review 模式的裁决闸**不许被这次改动放松**
    env PATH="$b:$PATH" CAPTURE="$d/$leg.r1.json" "${keyenv[@]}" \
      STUB_REVIEW_OUT="看着还行" \
      bash "$b/$leg-agent" review "$d/brief.md" "$d/$leg.r1.log" "$d" >/dev/null 2>&1; rc=$?
    check "V17: $leg-agent review 无裁决仍判失败(闸没被放松)" $([[ $rc -ne 0 ]]; echo $?)
  done

  # ---- ⑤ 发散的系统提示词必须真的送达底座腿(单一真相源:panel-explore 导出它)
  env PATH="$b:$PATH" CAPTURE="$d/sysp.json" ZHIPU_API_KEY=zk \
    REVIEW_SYSTEM_PROMPT="ANGLE_NOT_CONSENSUS_MARKER" \
    bash "$b/subglm-agent" explore "$d/brief.md" "$d/sysp.log" "$d" >/dev/null 2>&1
  stdin_has "$d/sysp.json" "ANGLE_NOT_CONSENSUS_MARKER"
  check "V17: REVIEW_SYSTEM_PROMPT 送达底座腿(发散指令不丢)" $?

  # ---- ⑥ panel-explore 选腿:默认底座 / 可强制回落 / 缺底座自动回落 / 模式必须是 explore
  local pb="$d/panelbin"; mkdir -p "$pb"
  cp "$BIN/panel-explore" "$pb/panel-explore"
  cat > "$pb/submimo" <<'EOF'
#!/usr/bin/env bash
echo "mimo leg mode=$1" > "$3"; exit 0
EOF
  chmod +x "$pb/submimo"
  for leg in subglm subdeepseek; do
    cat > "$pb/$leg" <<'EOF'
#!/usr/bin/env bash
echo "CHAT-LEG mode=$1" > "$3"; exit 0
EOF
    cat > "$pb/$leg-agent" <<'EOF'
#!/usr/bin/env bash
echo "AGENT-LEG mode=$1" > "$3"; exit 0
EOF
    chmod +x "$pb/$leg" "$pb/$leg-agent"
  done
  PANEL_STAGGER_MAX=0 bash "$pb/panel-explore" "$d/brief.md" "$d" "$d/E1" >/dev/null 2>&1
  for leg in subglm subdeepseek; do
    grep -q AGENT-LEG "$d/E1.$leg.log" 2>/dev/null
    check "V17: panel-explore 的 $leg 默认走底座腿" $?
    grep -q "mode=explore" "$d/E1.$leg.log" 2>/dev/null
    check "V17: panel-explore 派给 $leg 底座腿的模式是 explore(不是 review)" $?
  done
  PANEL_STAGGER_MAX=0 PANEL_GLM_LEG=chat PANEL_DEEPSEEK_LEG=chat \
    bash "$pb/panel-explore" "$d/brief.md" "$d" "$d/E2" >/dev/null 2>&1
  grep -q CHAT-LEG "$d/E2.subglm.log" 2>/dev/null
  check "V17: PANEL_GLM_LEG=chat 仍能强制回落聊天腿" $?
  grep -q CHAT-LEG "$d/E2.subdeepseek.log" 2>/dev/null
  check "V17: PANEL_DEEPSEEK_LEG=chat 仍能强制回落聊天腿" $?

  # ⑦ 底座腿挂了 -> 自动回落聊天腿,且失败证据留档(照 panel-review V14 的约定)
  cat > "$pb/subglm-agent" <<'EOF'
#!/usr/bin/env bash
echo "agent boom" >&2; exit 3
EOF
  chmod +x "$pb/subglm-agent"
  PANEL_STAGGER_MAX=0 bash "$pb/panel-explore" "$d/brief.md" "$d" "$d/E3" >/dev/null 2>&1
  grep -q CHAT-LEG "$d/E3.subglm.log" 2>/dev/null
  check "V17: 底座腿失败自动回落聊天腿" $?
  [[ -s "$d/E3.subglm.log.agent.log" || -s "$d/E3.subglm.log.agent.log.err" ]]
  check "V17: 底座腿失败的证据留档(.agent.log/.err)" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- V18
v18_engine_identity_single_source() {
  echo "[V18] submimo-review: 身份只有一个来源(不许用别人的名字报自己的错)"
  local d; d="$(mktemp -d)"
  printf '# t\n' > "$d/t.md"
  # 走"无裁决 ⇒ fail()"这条必然报错的路径,看它自报家门用的是哪个名字。
  # 起一个只回 429 的本地端点,顺便验端点报错不写死厂商名。
  cat > "$d/stub_429.py" <<'PY'
import http.server, socketserver, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = '{"error":{"code":"1113","message":"quota"}}'.encode()
        self.send_response(429); self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
srv = socketserver.TCPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(srv.server_address[1]))
srv.serve_forever()
PY
  python3 "$d/stub_429.py" "$d/port.txt" &
  local srv_pid=$!
  for _ in $(seq 1 50); do [[ -s "$d/port.txt" ]] && break; sleep 0.1; done
  local port; port="$(cat "$d/port.txt")"

  REVIEW_LABEL="subglm-review" MIMO_API_KEY=x MIMO_RETRIES=1 \
    MIMO_CHAT_COMPLETIONS_URL="http://127.0.0.1:$port/v1/chat/completions" \
    python3 "$BIN/submimo-review" "$d/t.md" "$d/out.log" >/dev/null 2>"$d/err.txt"
  kill "$srv_pid" 2>/dev/null; wait "$srv_pid" 2>/dev/null

  [[ -s "$d/err.txt" ]];                    check "V18: 锚 —— stderr 非空(stub 端点真的被打到了)" $?
  grep -q "subglm-review" "$d/err.txt";      check "V18: stderr 自报的是本腿的名字" $?
  if grep -q "submimo-review" "$d/err.txt"; then
    bad "V18: stderr 不许出现别的腿的名字"
  else ok "V18: stderr 不许出现别的腿的名字"; fi
  if grep -qi "Mimo endpoint" "$d/err.txt"; then
    bad "V18: 端点报错不许硬写厂商名"
  else ok "V18: 端点报错不许硬写厂商名"; fi
  grep -q "127.0.0.1:$port" "$d/err.txt";    check "V18: 端点报错打印真实端点 URL" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- V19
v19_degradation_travels_with_conclusion() {
  echo "[V19] 降级的事实必须写进结论所在的那份日志"
  local d pb; d="$(mktemp -d)"; pb="$d/bin"; mkdir -p "$pb"
  cp "$BIN/panel-review" "$pb/panel-review"
  # 三腿:mimo 正常;deepseek 底座腿必死 + 聊天腿成功(这就是要验的回落路径);glm 关掉
  for n in submimo subglm subkimi; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "Conclusion: PASS" > "$3"\n' > "$pb/$n"
    chmod +x "$pb/$n"
  done
  printf '#!/usr/bin/env bash\necho "boom" >&2\nexit 7\n' > "$pb/subdeepseek-agent"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "CHAT-LEG" "Conclusion: PASS" > "$3"\n' > "$pb/subdeepseek"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "Conclusion: PASS" > "$3"\n' > "$pb/subglm-agent"
  chmod +x "$pb/subdeepseek-agent" "$pb/subdeepseek" "$pb/subglm-agent"
  printf '# t\n' > "$d/t.md"
  PANEL_STAGGER_MAX=0 PANEL_KIMI_LEG=off bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/R" >/dev/null 2>&1

  local log="$d/R.subdeepseek.log"
  [[ -s "$log" ]];                              check "V19: 回落后的结论日志存在" $?
  grep -q "CHAT-LEG" "$log" 2>/dev/null;        check "V19: 结论确实来自聊天腿" $?
  grep -qi "DEGRADED\|降级" "$log" 2>/dev/null; check "V19: 结论日志里带降级横幅" $?
  grep -q "rc=7" "$log" 2>/dev/null;            check "V19: 横幅写明底座腿的死因 rc" $?
  # 健康腿不许被误标
  if grep -qi "DEGRADED\|降级" "$d/R.submimo.log" 2>/dev/null; then
    bad "V19: 健康腿不许带降级横幅"
  else ok "V19: 健康腿不许带降级横幅"; fi
  rm -rf "$d"
}

v19_chat_leg_declares_its_blindness() {
  echo "[V19] 聊天腿日志头自报视野边界"
  local d; d="$(mktemp -d)"; local repo="$d/repo"; mkdir -p "$repo"
  ( cd "$repo"; git init -q; git config user.email t@t; git config user.name t
    echo a > f; git add f; git commit -qm init; echo b >> f )
  printf '# t\n' > "$d/t.md"
  REVIEW_LABEL="subglm-review" MIMO_API_KEY=x MIMO_BASE_URL=http://x \
    python3 "$BIN/submimo-review" "$d/t.md" "$d/out.log" --repo "$repo" --git-diff --dry-run >/dev/null 2>&1
  grep -qi "视野\|scope:" "$d/out.log"; check "V19: 日志头有视野字段" $?
  grep -qi "看不到\|cannot read\|only" "$d/out.log"; check "V19: 视野字段说明看不到仓库其余部分" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- V20
v20_max_turns_does_not_discard_work() {
  echo "[V20] 底座腿撞上 max-turns 不许把工作全丢掉"
  local d fake; d="$(mktemp -d)"; fake="$d/fakebin"; mkdir -p "$fake"
  # 假 claude:吐几条 stream-json(含模型说的话与工具动作)后按 max-turns 那样 rc=1
  cat > "$fake/claude" <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
cat <<'J'
{"type":"assistant","message":{"content":[{"type":"text","text":"FINDING-ALPHA 我在 bin/x.py:12 看到一个洞"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"bin/x.py"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"FINDING-BETA 第二条"}]}}
J
echo "Error: Reached max turns (80)" >&2
exit 1
FAKE
  chmod +x "$fake/claude"
  printf '# t\n' > "$d/t.md"
  mkdir -p "$d/repo"; ( cd "$d/repo"; git init -q )
  printf '{"key":"x"}\n' > "$d/auth.json"
  PATH="$fake:$PATH" DEEPSEEK_AUTH_FILE="$d/auth.json" \
    "$BIN/subdeepseek-agent" review "$d/t.md" "$d/a.log" "$d/repo" >/dev/null 2>"$d/a.err"

  if grep -q '^{"type":' "$d/a.log" 2>/dev/null; then
    bad "V20: 锚 —— 日志是渲染过的,不是把 stream-json 原文倒进去"
  else ok "V20: 锚 —— 日志是渲染过的,不是把 stream-json 原文倒进去"; fi
  grep -q "FINDING-ALPHA" "$d/a.log" 2>/dev/null; check "V20: 撞上限也留下模型说过的话" $?
  grep -q "FINDING-BETA"  "$d/a.log" 2>/dev/null; check "V20: 留下的是全部而不是最后一条" $?
  grep -qi "max.turns\|轮次上限" "$d/a.log" 2>/dev/null; check "V20: 日志里写明是被上限打断的" $?
  grep -qE "turns[: ]+[0-9]+" "$d/a.log" 2>/dev/null; check "V20: 记下实际用了多少轮" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- V21
v21_agent_leg_body_is_single_source() {
  echo "[V21] 底座腿的躯干只有一份(照 subchat 的先例)"
  [[ -f "$BIN/subagent" ]]; check "V21: 共享躯干 subagent 存在" $?
  local n
  for n in subdeepseek-agent subglm-agent; do
    grep -q "subagent" "$BIN/$n" 2>/dev/null; check "V21: $n 走共享躯干" $?
    [[ "$(grep -cvE '^\s*(#.*)?$' "$BIN/$n" 2>/dev/null)" -le 6 ]]
    check "V21: $n 是瘦 shim(有效行 ≤ 6)" $?
  done
  # 供应商差异只准活在躯干的供应商表里
  grep -q "deepseek" "$BIN/subagent" 2>/dev/null; check "V21: 供应商表含 deepseek" $?
  grep -q "zhipu\|glm" "$BIN/subagent" 2>/dev/null; check "V21: 供应商表含 zhipu/glm" $?

  # 合并躯干时**每条腿的默认预算不许被顺手统一掉**。2026-08-03 实证:我把两条腿
  # 合进 subagent 时,zhipu 的默认轮次上限被从历史的 40 悄悄抬到 80(翻倍的是**钱**),
  # 而合并说明里一个字没提 —— 这是"超出规格的好意",不是修复。讽刺的是抓到它的正是
  # 这次刚修好的那条 deepseek 腿的首跑。⇒ 每条腿的默认值单独钉死,改要显式改判据。
  local d; d="$(mktemp -d)"; local ab="$d/bin"; mkdir -p "$ab" "$d/repo"
  cp "$BIN/subdeepseek-agent" "$BIN/subglm-agent" "$BIN/subagent" "$ab/"
  cat > "$ab/claude" <<'CAPEOF'
#!/usr/bin/env python3
import sys, os, json
open(os.environ["CAPTURE"], "w").write(json.dumps({"argv": sys.argv[1:]}))
print(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "Conclusion: PASS"}]}}))
CAPEOF
  chmod +x "$ab/claude"
  printf '# t\n' > "$d/t.md"
  capturing_turns() { python3 -c "import json,sys;a=json.load(open(sys.argv[1]))['argv'];print(a[a.index('--max-turns')+1])" "$1"; }
  env PATH="$ab:$PATH" CAPTURE="$d/z.json" ZHIPU_API_KEY=zk \
    bash "$ab/subglm-agent" review "$d/t.md" "$d/z.log" "$d/repo" >/dev/null 2>&1
  [[ "$(capturing_turns "$d/z.json")" -eq 40 ]]
  check "V21: zhipu 默认轮次上限仍是历史值 40(合并躯干不许顺手改别人的预算)" $?
  env PATH="$ab:$PATH" CAPTURE="$d/s.json" DEEPSEEK_API_KEY=dk \
    bash "$ab/subdeepseek-agent" review "$d/t.md" "$d/s.log" "$d/repo" >/dev/null 2>&1
  # deepseek 的上限是**凭测量**定的:08-03 实测一个只看单文件的琐碎任务就用掉 56 轮
  # (log: scratchpad/smoke.log),而它 07-21 撞过 40、08-03 撞过 80。翻倍法到此为止。
  [[ "$(capturing_turns "$d/s.json")" -ge 200 ]]
  check "V21: deepseek 默认轮次上限 ≥200(56 轮/单文件的实测外推)" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- V22
# 派发窗口内的三个盲区(2026-08-05 同一单里各栽一次,见 V22 顶部注释)。
v22_head_moved_during_review() {
  echo "[V22a] panel-review: 评审期间 HEAD 动了要报,且要写进每份腿日志"
  local d pb repo; d="$(mktemp -d)"; pb="$d/bin"; repo="$d/repo"; mkdir -p "$pb" "$repo"
  cp "$BIN/panel-review" "$pb/panel-review"
  printf '# review\n' > "$d/t.md"
  ( cd "$repo"; git init -q; git config user.email t@t; git config user.name t
    echo base > f.txt; git add -A; git commit -qm init )

  # 老实的三条腿:HEAD 不动
  for leg in submimo subdeepseek subglm subkimi; do
    printf '#!/bin/bash\necho "STUB PASS" > "$3"\nexit 0\n' > "$pb/$leg"; chmod +x "$pb/$leg"
  done
  bash "$pb/panel-review" --no-my-review "$d/t.md" "$repo" "$d/H1" >"$d/h1.out" 2>&1
  if grep -qi "HEAD 从\|HEAD moved" "$d/h1.out"; then bad "V22a: HEAD 没动时不许报"; else ok "V22a: HEAD 没动时不许报"; fi
  if grep -qi "HEAD 从" "$d/H1.submimo.log"; then bad "V22a: HEAD 没动时日志不许被加尾巴"; else ok "V22a: HEAD 没动时日志不许被加尾巴"; fi

  # 一条腿还在跑时,仓库被人提交了(08-05 实况:我在 Kimi 跑着时 commit 了 80d2d23)
  cat > "$pb/submimo" <<'EOF'
#!/usr/bin/env bash
git -C "$4" commit -q --allow-empty -m "主审在评审期间提交"
echo "STUB PASS" > "$3"
exit 0
EOF
  chmod +x "$pb/submimo"
  bash "$pb/panel-review" --no-my-review "$d/t.md" "$repo" "$d/H2" >"$d/h2.out" 2>&1
  grep -qi "HEAD 从" "$d/h2.out"; check "V22a: HEAD 漂移在 stdout 报出来" $?
  # 报告会被单独读到(归档/断线重连),所以横幅必须跟着结论走 —— 每一份腿日志都要有
  local missed=0 f
  for f in "$d/H2.submimo.log" "$d/H2.subdeepseek.log" "$d/H2.subglm.log" "$d/H2.subkimi.log"; do
    [[ -s "$f" ]] || continue
    grep -qi "HEAD 从" "$f" || { missed=1; echo "     (缺横幅: $f)"; }
  done
  check "V22a: 每份腿日志尾部都带 HEAD 漂移横幅" $([[ $missed -eq 0 ]]; echo $?)
  # 原结论不许被横幅顶掉
  grep -q "STUB PASS" "$d/H2.subdeepseek.log"; check "V22a: 加横幅不吞掉腿的原文" $?
  rm -rf "$d"
}

v22_anchor_leak_sees_committed_track() {
  echo "[V22b] panel-review: 已提交的同名 track verify.md 也算锚定泄漏(不依赖 diff 基线)"
  local d pb repo; d="$(mktemp -d)"; pb="$d/bin"; repo="$d/repo"; mkdir -p "$pb"
  cp "$BIN/panel-review" "$pb/panel-review"
  for leg in submimo subdeepseek subglm subkimi; do
    printf '#!/bin/bash\necho "STUB PASS" > "$3"\nexit 0\n' > "$pb/$leg"; chmod +x "$pb/$leg"
  done
  # 本机默认形状:在 main 上干活(main == HEAD ⇒ PANEL_DIFF_BASE 那一臂结构上不存在)、
  # 工作区干净(verify.md 已提交 ⇒ status 那一臂也照不到)。08-05 实测泄漏就长这样。
  mkdir -p "$repo/tracks/turnid" "$repo/tracks/unrelated"
  ( cd "$repo"; git init -q -b main; git config user.email t@t; git config user.name t
    echo base > f.txt
    printf '# Verify\n规格自查第 2 条:……\n' > tracks/turnid/verify.md
    printf '# Verify\n别的 track\n' > tracks/unrelated/verify.md
    git add -A; git commit -qm init )
  printf '# review\n' > "$d/turnid-review.md"

  bash "$pb/panel-review" --no-my-review "$d/turnid-review.md" "$repo" "$d/L1" >"$d/l1.out" 2>&1
  grep -q "tracks/turnid/verify.md" "$d/l1.out"
  check "V22b: 同名 track 的已提交 verify.md 被点名" $?
  grep -qi "anchor\|锚定" "$d/l1.out"; check "V22b: 点名时给的是锚定泄漏警告" $?
  if grep -q "tracks/unrelated/verify.md" "$d/l1.out"; then
    bad "V22b: 不相干 track 的 verify.md 不许跟着报(误报会把警告变噪音)"
  else
    ok "V22b: 不相干 track 的 verify.md 不许跟着报(误报会把警告变噪音)"
  fi
  # 警告只是提醒,不阻断
  [[ -s "$d/L1.submimo.log" ]]; check "V22b: 报警不阻断派发" $?
  rm -rf "$d"
}

v22_roster_file() {
  echo "[V22c] panel-review: 收尾把各腿状态落盘成 <prefix>.roster(verify.md 直接粘)"
  local d pb repo; d="$(mktemp -d)"; pb="$d/bin"; repo="$d/repo"; mkdir -p "$pb" "$repo"
  cp "$BIN/panel-review" "$pb/panel-review"
  printf '# review\n' > "$d/t.md"
  ( cd "$repo"; git init -q; git config user.email t@t; git config user.name t
    echo base > f.txt; git add -A; git commit -qm init )

  # 场景一:submimo 绿、subdeepseek 死(rc=5)、GLM 关着(默认)、kimi 绿
  printf '#!/bin/bash\necho "STUB PASS" > "$3"\nexit 0\n' > "$pb/submimo"
  printf '#!/bin/bash\necho "STUB PASS" > "$3"\nexit 0\n' > "$pb/subkimi"
  printf '#!/bin/bash\necho "boom" >&2\nexit 5\n' > "$pb/subdeepseek"
  chmod +x "$pb/submimo" "$pb/subkimi" "$pb/subdeepseek"
  env -u PANEL_GLM_LEG bash "$pb/panel-review" --no-my-review "$d/t.md" "$repo" "$d/R1" >"$d/r1.out" 2>&1
  [[ -s "$d/R1.roster" ]]; check "V22c: 收尾写出 <prefix>.roster" $?
  grep -q "submimo=PASS" "$d/R1.roster";      check "V22c: 绿腿记 PASS" $?
  grep -q "subdeepseek=FAIL(rc=5)" "$d/R1.roster"; check "V22c: 死腿记 FAIL 且带 rc" $?
  # 08-05 那次的病根:关着/没出结论的腿被我在 verify.md 里写成了"一致 PASS"
  grep -q "subglm=off" "$d/R1.roster";        check "V22c: 关着的腿记 off,不许记成 PASS" $?
  if grep -q "subglm=PASS" "$d/R1.roster"; then bad "V22c: 关着的腿绝不能出现 PASS"; else ok "V22c: 关着的腿绝不能出现 PASS"; fi
  grep -q "subkimi=PASS" "$d/R1.roster";      check "V22c: 第四腿也在花名册里" $?
  grep -q "R1.roster" "$d/r1.out";            check "V22c: stdout 指出 roster 路径(不然没人知道它在)" $?

  # 场景二:底座腿死了回落聊天腿 ⇒ 花名册必须带降级标记(结论可以旅行,资格要跟着走)
  cat > "$pb/subdeepseek-agent" <<'EOF'
#!/usr/bin/env bash
echo "Error: Reached max turns" >&2
echo "AGENT-JUNK" > "$3"
exit 1
EOF
  printf '#!/bin/bash\necho "CHAT-LEG" > "$3"\nexit 0\n' > "$pb/subdeepseek"
  chmod +x "$pb/subdeepseek" "$pb/subdeepseek-agent"
  env -u PANEL_GLM_LEG bash "$pb/panel-review" --no-my-review "$d/t.md" "$repo" "$d/R2" >/dev/null 2>&1
  grep -qE "subdeepseek=PASS\(.*(降级|DEGRADED).*\)" "$d/R2.roster"
  check "V22c: 回落腿在花名册里带降级标记" $?
  rm -rf "$d"
}


# ---------------------------------------------------------------- V23
v23_my_review_gate_on_every_review_path() {
  echo "[V23] 反锚定闸要盖住**每一条评审路径**,不只是 panel-review"
  local d b rc; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b" "$d/repo"
  ( cd "$d/repo"; git init -q; git config user.email t@t; git config user.name t
    echo x > f; git add -A; git commit -qm init )
  cp "$BIN/_my-review-gate.sh" "$b/" 2>/dev/null
  printf '# 评审任务书\n' > "$d/t.md"

  # 三条躯干各造一个"被调用就留痕"的假模型端点:闸该在**调用之前**拦下。
  # 直接用真脚本 + 假 CLI:mimo/claude 都不在这条路径上时脚本会自己报错,
  # 所以这里只断言 rc 和 stderr 里的那句话(拦在闸上,而不是拦在缺 CLI 上)。
  for entry in "submimo|review" "subchat|deepseek review" "subagent|deepseek review"; do
    IFS='|' read -r tool args <<< "$entry"
    cp "$BIN/$tool" "$b/$tool"
    # ① 约定路径的自审文件不存在 ⇒ 拒跑,且错误信息点名"先写你自己的一遍"
    out="$(cd "$d" && env -u REVIEW_MY_REVIEW REVIEW_NO_MY_REVIEW=0 PANEL_DISPATCH=0 \
            bash "$b/$tool" $args "$d/t.md" "$d/out.log" "$d/repo" 2>&1)"; rc=$?
    check "V23: $tool 没有自审文件 ⇒ 拒跑" $([[ $rc -ne 0 ]]; echo $?)
    grep -q "自己的一遍" <<<"$out"; check "V23: $tool 说清是缺自审(不是别的报错)" $?

    # ② 自审文件在**仓内** ⇒ 拒跑(腿会照着我的答案抄)
    printf '我的一遍\n' > "$d/repo/mine.md"
    out="$(cd "$d" && REVIEW_MY_REVIEW="$d/repo/mine.md" bash "$b/$tool" $args \
            "$d/t.md" "$d/out.log" "$d/repo" 2>&1)"; rc=$?
    check "V23: $tool 自审文件在仓内 ⇒ 拒跑" $([[ $rc -ne 0 ]]; echo $?)

    # ③ 显式退出闸 ⇒ 不再被这道闸拦(会因为别的原因失败,但不许是这一句)
    out="$(cd "$d" && REVIEW_NO_MY_REVIEW=1 bash "$b/$tool" $args \
            "$d/t.md" "$d/out.log" "$d/repo" 2>&1)"
    if grep -q "自己的一遍" <<<"$out"; then
      bad "V23: $tool REVIEW_NO_MY_REVIEW=1 应当放行这道闸"
    else ok "V23: $tool REVIEW_NO_MY_REVIEW=1 应当放行这道闸"; fi

    # ④ panel-review 派发时不许被重复拦(它在自己那层已经查过)
    out="$(cd "$d" && PANEL_DISPATCH=1 bash "$b/$tool" $args \
            "$d/t.md" "$d/out.log" "$d/repo" 2>&1)"
    if grep -q "自己的一遍" <<<"$out"; then
      bad "V23: $tool 在 panel 派发下不许重复拦(否则四审整个派不出去)"
    else ok "V23: $tool 在 panel 派发下不许重复拦(否则四审整个派不出去)"; fi
    rm -f "$d/repo/mine.md"
  done
  rm -rf "$d"
}

echo "=== review-tooling regression oracle ==="
v1_untracked_content
v1_no_untracked_and_nonrepo
v2_glob_not_pre_expanded
v3_panel_sidecar
v4_output_validation
v5_diff_scope
v6_truncation
v7_blind_warning
v8_subchat_provider_table
v9_subglm_agent
v10_git_stderr_isolation
v11_panel_gates
v12_gate_default_on
v13_subkimi_leg
v14_leg_fallback_and_include
v15_anchor_leak_warning
v16_timeout_and_blind_chat_leg
v17_explore_agent_legs
v18_engine_identity_single_source
v19_degradation_travels_with_conclusion
v19_chat_leg_declares_its_blindness
v20_max_turns_does_not_discard_work
v21_agent_leg_body_is_single_source
v22_head_moved_during_review
v22_anchor_leak_sees_committed_track
v22_roster_file
v23_my_review_gate_on_every_review_path
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
