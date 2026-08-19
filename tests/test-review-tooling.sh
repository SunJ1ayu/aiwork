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

# 判卷面的不变量:**跑判据的进程不许有外网出口**(2026-08-10,track no-egress-judging)。
# 这一行把整个套件 exec 进一个没有出口的网络命名空间;做不到就拒跑。
. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78   # source 失败=裸跑,必须硬退

# **判据里绝不许调到真的 opencode 底座**(2026-08-18,track opencode-agent-base)。
# 起因:GLM 腿的底座换成 opencode CLI 之后,所有跑 subglm-agent 的老用例(V9/V21/V23…)
# 都会去调**真**的 opencode。断网闸(上面那行)保证了它出不去、不花钱,但症状不是
# 立刻失败,而是**每处干等 900 秒超时**,判据整体被拖死。
# 修法不是去补那几个调用点 —— 补完第 10 个还会漏。这里放一层**兜底桩**:
# 真 opencode 一旦被判据碰到就**立刻响亮失败**,把"谁没给桩"当场点名。
# 需要行为的用例照旧在自己的 $b 里放桩(PATH 里排在这层前面),不受影响。
_OC_FLOOR="$(mktemp -d)"
cat > "$_OC_FLOOR/opencode" <<'OCFLOOR'
#!/usr/bin/env bash
echo "判据里调到了**真的** opencode 底座:$* " >&2
echo "  这条用例跑了 opencode 底座的腿却没给它桩 —— 补一个桩,别让判据去碰真底座。" >&2
exit 97
OCFLOOR
chmod +x "$_OC_FLOOR/opencode"
export PATH="$_OC_FLOOR:$PATH"

# opencode 底座腿的共用夹具(2026-08-18)。GLM 腿换底座之后,"它被怎么约束的"
# 不在 claude 的命令行参数里了,而在**它生成的那份配置**里 —— 下面几组
# (V17/V21/V26/V28)都要读同一份东西,所以夹具只写一份。
# 桩把 argv 抄下来(opencode 的提示词走位置参数,不像 claude 走 stdin)。
oc_stub() {   # $1 = 要放桩的 bin 目录
  cat > "$1/opencode" <<'OCSTUB'
#!/usr/bin/env bash
[[ -n "${CAPTURE:-}" ]] && printf '%s\0' "$@" > "$CAPTURE"
# stdin 是什么 —— 这条是被真事故逼出来的,见 V28 ⑨
[[ -n "${CAPTURE_STDIN:-}" ]] && readlink /proc/self/fd/0 > "$CAPTURE_STDIN" 2>/dev/null
echo "stub reviewer"
echo "${STUB_OC_OUT:-Conclusion: PASS}"
OCSTUB
  chmod +x "$1/opencode"
}
# 读它生成的配置:occfg <配置路径> model|steps|baseURL|tools_off|bash_perm
occfg() {
  python3 - "$1" "$2" <<'OCCFG'
import json, sys
c = json.load(open(sys.argv[1])); q = sys.argv[2]
a = list(c["agent"].values())[0]; pv = list(c["provider"].values())[0]
if   q == "model":     print(a.get("model"))
elif q == "steps":     print(a.get("steps"))
elif q == "baseURL":   print(pv["options"]["baseURL"])
elif q == "tools_off": print(" ".join(sorted(k for k, v in a.get("tools", {}).items() if v is False)))
elif q == "bash_perm": print(json.dumps((a.get("permission") or {}).get("bash"), sort_keys=True))
OCCFG
}


# V23/V24 真跑 sub* 躯干,考的是**闸放不放行** —— 闸在启动的瞬间就判完了,
# 后面那段网络往返与本考卷无关。而 08-10 起判据进程没有外网出口,那一段**必然**失败,
# 只是失败得慢(node 自己还要重试几秒)。等它没有任何意义:
# 25s × 7 处 ⇒ 总跑 72s → 346s,超过每周 cron 的 300s 超时并触发 3 次重试。
# 调小只可能让考卷**误红**(闸没来得及说话),不可能让它误绿 —— 失败方向是安全的。
GATE_PROBE_TIMEOUT="${GATE_PROBE_TIMEOUT:-5}"

# 从判据自身位置推 bin/,**不写死绝对路径**:执行腿在 worktree 里改了代码,
# 写死路径会让判据仍去测主仓的文件 = 改了也永远红(2026-08-01 派活前发现)。
# 可用 REVIEW_BIN 覆盖。
BIN="${REVIEW_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"
# 2026-08-18 晚:**这里原本有一行 `export PANEL_GLM_LEG=agent`,已删。**
#
# 它的来历:08-04 GLM 腿因欠费默认 off,老用例问的是"这条腿的行为"不是"它默不默认开",
# 所以统一在这里把腿显式钉住,好让老用例不受默认档变动影响。听起来很合理。
#
# 它的实际效果:**任何问"默认是什么"的断言都在被污染的环境里问,于是永远问不到默认值。**
# 08-18 一天之内我被它咬了三次(V13 一次、V27 一次、V17 的 panel-explore 一次),
# 三次我都只是在那一处加 `env -u` —— **补的是症状**。第三次抓到时它已经在
# "panel-explore 默认值是错的"那整段时间里一直显示绿。
#
# 删它的依据不是嫌它碍事,是实测:拿掉之后**一条都不红**(334/0)——
# 说明它早就没有消费者了,留着只剩危害。四处真正关心底座腿的断言,
# 要么自己 `env -u` 问默认、要么在自己那一行显式写 `PANEL_GLM_LEG=agent`。
#
# 规矩(替代那行 export):**要哪一档,就在自己那条命令上写出来。**
# 环境里飘着的档位会把"问默认"变成"问那个飘着的值",而这种错的失败方向是不安全的:
# 断言写对了照样红,或者更糟——写错了照样绿。
# 2026-08-06:反锚定闸(review 模式要求主 agent 先落盘自己那一遍)新上线,而**下面的老用例
# 问的是各条腿自己的行为**(端点、模型、工具白名单、轮次上限……),不是这道闸。
# 统一在这里显式退出,和上面 GLM 那条同一个道理:断言一条不删、一条不弱。
# 只有 V23 那一组问闸本身。
# **不用全局 export**(四审两腿都点名这是脚枪:以后新写的用例会静默跳过闸)——
# 改成在下面的调用处逐个显式关掉,谁关的一眼看得见,新用例默认闸是开着的。

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
  # 2026-08-18:后端从智谱开放平台 bigmodel 换到 **OpenCode Go**(业主的 $10/月订阅)。
  # 改这条老断言不是放水:bigmodel 那把 key 已欠费,这条腿 08-04 起默认关着 ——
  # 断言的是"默认端点必须是**当前真正在付费的那一个**",规格换了,断言跟着换。
  [[ "$(envget "$d/c2.json" MIMO_CHAT_COMPLETIONS_URL)" == "https://opencode.ai/zen/go/v1/chat/completions" ]]
  check "zhipu: exact MIMO_CHAT_COMPLETIONS_URL default (OpenCode Go)" $?
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
v9_claude_shell_base() {
  echo "[V9] claude 壳底座(subdeepseek-agent):env 注入、只读工具、裁决 gate"
  local d b rc; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"
  # 2026-08-18 **这一组从 GLM 腿挪到 DeepSeek 腿**:GLM 的底座换成了 opencode CLI
  # (track opencode-agent-base),它已经不走 claude 壳,再拿它测 claude 壳就是
  # 拿错车验错路 —— 而且会去调真 opencode 干等 900 秒。
  # 这一组问的是**claude 壳这条底座本身**(env 注入、工具白名单、裁决 gate),
  # 它对 deepseek 仍然完全有效,断言一条不删、一条不弱。GLM 那条底座由 V28 问。
  # (本函数末尾那段 panel 选腿用例里的 subglm 桩保持不动:那里造的是桩,不碰真底座。)
  # 瘦 shim,躯干在 subagent(V21);bin/ 成套部署,两个都要 cp。
  cp "$BIN/subdeepseek-agent" "$BIN/subagent" "$b/"
  # stub claude: record argv + the env subdeepseek-agent must (and must not) inject,
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
    DEEPSEEK_API_KEY=dk-env DEEPSEEK_MODEL=ds-test-model \
    bash "$b/subdeepseek-agent" review "$d/t.md" "$d/a1.log" "$d" >/dev/null 2>&1; rc=$?
  check "agent review (env key) exits 0" $([[ $rc -eq 0 ]]; echo $?)
  # 2026-08-18 后端换成 OpenCode Go 之后,**认证 header 也换了**:
  # deepseek 的 Anthropic 面走 Authorization: Bearer(= ANTHROPIC_AUTH_TOKEN)。
  # 这和 GLM 那格(x-api-key)**故意相反** —— 差异只准活在供应商表里,
  # 两格各自被钉死,谁被顺手统一了这里就红。
  # 所以这里断言的是**表驱动的 header 风格**,不是"key 有没有传进去":
  # 传对了 key、传错了 header,腿一样是死的,而日志上看起来只是"模型没回话"。
  [[ "$(agentget "$d/a1.json" ANTHROPIC_AUTH_TOKEN)" == "dk-env" ]]
  check "agent: deepseek 走 Bearer(ANTHROPIC_AUTH_TOKEN)拿 DEEPSEEK_API_KEY" $?
  [[ -z "$(agentget "$d/a1.json" ANTHROPIC_API_KEY)" ]]
  check "agent: deepseek 那格 x-api-key 必须是空的(别被 GLM 的风格串味)" $?
  # **不带尾部 /v1** —— claude CLI 自己会补 /v1/messages。写成 .../go/v1 会打到
  # /zen/go/v1/v1/messages(实测 404),而 CLI 把这个 404 报成「模型不存在」。
  # 08-18 我在这个坑里查了半天模型名。(第三处写死同一个地址:改一个地方不够。)
  [[ "$(agentget "$d/a1.json" ANTHROPIC_BASE_URL)" == "https://api.deepseek.com/anthropic" ]]
  check "agent: default Anthropic-compatible base URL (DeepSeek)" $?
  [[ "$(agentget "$d/a1.json" ANTHROPIC_DEFAULT_SONNET_MODEL)" == "ds-test-model" ]]
  check "agent: sonnet slot mapped to DEEPSEEK_MODEL" $?
  # 父 harness 那把真 Anthropic key 绝不许活着进子进程(它现在和我们的 key 抢同一格,
  # 所以断言从"必须是空"改成"必须是我们的、绝不是父进程那把")。
  [[ "$(agentget "$d/a1.json" ANTHROPIC_API_KEY)" != "real-anthropic-key" ]]
  check "agent: 父进程的真 ANTHROPIC_API_KEY 被擦掉(没漏进腿里)" $?
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
  # 2026-08-18 晚收紧(track deepseek-leg-bash-hole):**allowlist 里不许再有任何 Bash**。
  # 实测:`Bash(git diff:*)` 放行了 `git diff --output=<仓内文件> HEAD`,文件真写出来了
  # ⇒ 评审腿能往被评审的仓里写 ⇒ **能写 tests/,也就是能动判据**。
  # (claude 这层守卫本身比前缀匹配聪明:它按路径拦住了 /dev/null 那类仓外访问,
  #  连 GNU diff / touch / rm 都拦;但它不管"写在工作目录内"的写。)
  # 顺带实测更正:pwd / ls / cat 这些**不在 allowlist 里的命令照样跑** ⇒
  # 这层是"拦危险的"不是"只放行列出的",把它当白名单理解是错的 —— 更没法靠黑名单补。
  if python3 -c "
import json,sys
a=json.load(open(sys.argv[1]))['argv']
i=a.index('--allowedTools'); rest=a[i+1:]
j=[k for k,x in enumerate(rest) if x.startswith('--')]
seg=rest[:j[0]] if j else rest
sys.exit(0 if any(t.startswith('Bash') for t in seg) else 1)" "$d/a1.json" 2>/dev/null; then
    ok  "agent: allowlist 里**要有** Bash —— 腿得能自己读 git(08-19 转向,见下)"
  else
    bad "agent: allowlist 里**要有** Bash —— 腿得能自己读 git(08-19 转向,见下)"
  fi
  # ⚠️ 这条 08-19 反转过一次,理由写在这儿免得有人再来回翻:
  # 08-18 我把 Bash 关了(理由:`git diff --output=` 能往仓里写 ⇒ 能改判据)。
  # 关掉的代价是腿看不了 git,于是主 agent 要算好 diff 喂进提示词 —— 那条链上长出
  # E2BIG(两条腿直接起不来)、SIGPIPE 静默暴毙、基线打错字静默变瞎,
  # **最坏形态是腿没跑起来而 panel 照常出结论**(比腿写个文件危险得多)。
  # 业主推翻了那个方向:评审腿**没有**"改判据让自己及格"的动机(那是执行腿的威胁模型),
  # 对面是误伤和提示注入,不是有动机的对手 ⇒ **检测代替预防**,写审计见 track
  # `repo-write-audit`(还没上线,窗口期是明账)。
  # 下面这条跟着反转:Bash **不许**再被塞进 disallowedTools。
  if python3 -c "
import json,sys
a=json.load(open(sys.argv[1]))['argv']
i=a.index('--disallowedTools'); rest=a[i+1:]
j=[k for k,x in enumerate(rest) if x.startswith('--')]
seg=rest[:j[0]] if j else rest
sys.exit(0 if 'Bash' in seg else 1)" "$d/a1.json" 2>/dev/null; then
    bad "agent: Bash 不许再列进 disallowedTools(腿要能读 git)"
  else
    ok  "agent: Bash 不许再列进 disallowedTools(腿要能读 git)"
  fi
  # **写口仍然全禁** —— 这几样评审腿本来就不需要,关掉是零成本的,和 Bash 完全不同。
  if python3 -c "
import json,sys
a=json.load(open(sys.argv[1]))['argv']
i=a.index('--disallowedTools'); rest=a[i+1:]
j=[k for k,x in enumerate(rest) if x.startswith('--')]
seg=rest[:j[0]] if j else rest
missing=[t for t in ('Write','Edit','NotebookEdit','Task','Agent') if t not in seg]
sys.exit(0 if not missing else 1)" "$d/a1.json" 2>/dev/null; then
    ok  "agent: 写口仍全禁(Write/Edit/NotebookEdit/Task/Agent)—— 零成本,不跟着 Bash 一起放"
  else
    bad "agent: 写口仍全禁(Write/Edit/NotebookEdit/Task/Agent)—— 零成本,不跟着 Bash 一起放"
  fi
  argvhas "$d/a1.json" "--model sonnet";    check "agent: --model sonnet (mapped slot)" $?
  argvhas "$d/a1.json" "--setting-sources project"; check "agent: user settings not loaded" $?
  argvhas "$d/a1.json" "--max-turns";       check "agent: turn cap present" $?

  # auth-file fallback
  printf '{"key":"dk-file"}' > "$d/auth.json"
  env -u DEEPSEEK_API_KEY PATH="$b:$PATH" CAPTURE="$d/a2.json" DEEPSEEK_AUTH_FILE="$d/auth.json" \
    bash "$b/subdeepseek-agent" review "$d/t.md" "$d/a2.log" "$d" >/dev/null 2>&1; rc=$?
  check "agent auth-file fallback exits 0" $([[ $rc -eq 0 ]]; echo $?)
  # 2026-08-18:env-key 那条路已经换成 x-api-key,**这条 auth-file 路当时被漏掉了**
  # —— 是判据自己在这儿红了一次才发现的。所以这里不止把变量名跟着改,还补上
  # "Bearer 那格必须是空的":只改名字的话,两条路各走各的 header 又会看不出来。
  [[ "$(agentget "$d/a2.json" ANTHROPIC_AUTH_TOKEN)" == "dk-file" ]]
  check "agent: key loaded from auth file" $?
  [[ -z "$(agentget "$d/a2.json" ANTHROPIC_API_KEY)" ]]
  check "agent: auth-file 这条路的 header 风格也必须对(两条路各走各的会看不出来)" $?

  # verdict gate: no Conclusion -> non-zero, log still written
  env PATH="$b:$PATH" CAPTURE="$d/a3.json" DEEPSEEK_API_KEY=dk \
    STUB_REVIEW_OUT="looks fine to me" \
    bash "$b/subdeepseek-agent" review "$d/t.md" "$d/a3.log" "$d" >/dev/null 2>&1; rc=$?
  check "agent: verdict-less output exits non-zero" $([[ $rc -ne 0 ]]; echo $?)
  [[ -f "$d/a3.log" ]]; check "agent: log still written on verdict miss" $?

  # verdict gate: Chinese 「结论：PASS」 (full-width colon) accepted — the drift
  # that bit subdeepseek twice (Track B + client-tools)
  env PATH="$b:$PATH" CAPTURE="$d/a3b.json" DEEPSEEK_API_KEY=dk \
    STUB_REVIEW_OUT=$'review body\n结论：PASS' \
    bash "$b/subdeepseek-agent" review "$d/t.md" "$d/a3b.log" "$d" >/dev/null 2>&1; rc=$?
  check "agent: Chinese 结论+full-width colon accepted" $([[ $rc -eq 0 ]]; echo $?)

  # fix refused; -h ok
  env PATH="$b:$PATH" CAPTURE="$d/a4.json" DEEPSEEK_API_KEY=dk \
    bash "$b/subdeepseek-agent" fix "$d/t.md" "$d/a4.log" "$d" >/dev/null 2>&1; rc=$?
  check "agent: fix refused" $([[ $rc -ne 0 ]]; echo $?)
  bash "$b/subdeepseek-agent" -h >/dev/null 2>&1; check "agent: -h exits 0" $?

  # panel-review leg selection: default=chat, PANEL_GLM_LEG=agent/chat, missing agent
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
  # **保留 env -u**:顶部那行 export 08-18 已经删掉了,但这条问的是"默认档是什么",
  # 摘干净环境再问是它自己该负的责任 —— 不依赖"外面正好没设"(那等于把正确性
  # 寄托在别处不变上)。
  env -u PANEL_GLM_LEG bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/P1" >/dev/null 2>&1
  # 2026-08-18 晚:**默认档翻回底座腿**。08-18 白天写成 chat 的理由是
  # 「底座腿在 OpenCode Go 上必 400」—— 那个事实随 track opencode-agent-base 消失了:
  # 底座从"借 Claude Code 当壳"换成 opencode CLI 自己,工具形状天然对得上。
  # **改这条规格的依据不是我想改,是端到端实跑**:subglm-agent 在真端点上自己跑了
  # git status / git log / Read calc.py / Glob,抓到埋的雷,给出 Conclusion: BLOCK
  # (收据 smoke-real-leg)。关法(off)和强制聊天腿(chat)两条逃生路都保留。
  grep -q AGENT-LEG "$d/P1.subglm.log"; check "panel: GLM leg defaults to agent leg" $?
  # 关法和强制走底座腿的能力都还在(哪天 Go 补上转换,靠这条切回去)
  PANEL_GLM_LEG=agent bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/P1b" >/dev/null 2>&1
  grep -q AGENT-LEG "$d/P1b.subglm.log"; check "panel: PANEL_GLM_LEG=agent 仍能强制走底座腿" $?
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

    # ⚠️ 这一格 08-18 收紧过、08-19 又放回来,两次的理由都留着,别再来回翻:
    #
    # 08-18 我把 Bash 整个禁掉。**事实依据仍然成立**(我拿这个守卫真跑过):
    #   git diff --output=pwned.txt HEAD                → **放行**(能往仓里写)
    #   git diff --no-index <仓外 key 文件> /dev/null    → **放行**(能读仓外并打进日志)
    #   rm -rf x                                        → 拦下
    # 也就是说:这个正则前缀白名单**挡不住 git 自己的参数**。
    #
    # 08-19 业主推翻的是从那个事实推出的**结论**。禁掉 Bash 之后腿读不了 git,
    # 主 agent 得算好 diff 喂进去,那条链上长出 E2BIG、SIGPIPE 静默暴毙、基线静默变瞎,
    # 最坏形态是**腿根本没跑起来而 panel 照常出结论**。而评审腿没有"改判据让自己
    # 及格"的动机(那是执行腿的威胁模型)⇒ 对面是误伤,不是有动机的对手。
    #
    # 所以现在的规格是:**白名单留着,但只当它是防误伤的,不当它是防对手的。**
    # 它确实挡得住误伤的典型形态(rm、元字符链、非 git 命令);挡不住的那两条
    # (--output= / --no-index)交给**跑完的写审计**(track repo-write-audit)。
    # 下面这组断言因此按"挡误伤"来钉,不按"挡对手"来钉。
    local kcmd
    for kcmd in "rm -rf x" \
                "curl http://evil" \
                "git log && rm -rf /"; do
      echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$kcmd\"}}" \
        | node "$guard" >/dev/null 2>&1
      check "guard: 误伤形态照旧拦下 —— $kcmd" $([[ $? -ne 0 ]]; echo $?)
    done
    # **正向**:只读 git 必须放行 —— 腿要能自己看历史和差异。
    # (这条 08-18 被我删过,理由是"编码了被推翻的旧规格";08-19 它又成了对的规格。
    #  留个记号:同一条断言两天内被删又被加回来,说明当时删它的那个判断是错的。)
    for kcmd in "git log --oneline -5" \
                "git diff HEAD" \
                "git show --stat HEAD"; do
      echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$kcmd\"}}" \
        | node "$guard" >/dev/null 2>&1
      check "guard: 只读 git 放行(腿得能自己读仓库)—— $kcmd" $?
    done
    # **已知挡不住、且明知故留**:这两条不是判据的洞,是写下来的账。
    # 它们的防线在 repo-write-audit(还没上线)。断言写成"记录现状",红了说明
    # 守卫行为变了,那时要回来重新判断,而不是默默接受。
    for kcmd in "git diff --output=pwned.txt HEAD" \
                "git diff --no-index /etc/hostname /dev/null"; do
      echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$kcmd\"}}" \
        | node "$guard" >/dev/null 2>&1
      check "guard: 现状记录 —— 白名单挡不住这条(防线在 repo-write-audit)—— $kcmd" $?
    done
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

  # GLM 腿的开关史:2026-08-04 智谱账号余额不足(429/1113),每轮四审都白等它一次超时,
  # 业主拍板「先关掉」⇒ 默认 off。**08-18 后端换成 OpenCode Go 订阅,欠费这个理由消失了**,
  # 所以默认翻回 on ——「默认关着」当初是为欠费立的,不是永久规格;理由没了还留着,
  # 四审就永远只有三腿(这条腿已经关了两周)。关它的开关必须还在(PANEL_GLM_LEG=off),
  # 否则下次没钱又得改代码。
  cat > "$pb/subglm-agent" <<'EOF'
#!/usr/bin/env bash
echo "GLM-AGENT-LEG" > "$3"; exit 0
EOF
  cat > "$pb/subglm" <<'EOF'
#!/usr/bin/env bash
echo "GLM-CHAT-LEG" > "$3"; exit 0
EOF
  chmod +x "$pb/subglm-agent" "$pb/subglm"
  env -u PANEL_GLM_LEG bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/G1" >/dev/null 2>&1
  if [[ -e "$d/G1.subglm.log" ]]; then ok "panel: GLM 腿默认开着(OpenCode Go 之后)"; else bad "panel: GLM 腿默认开着(OpenCode Go 之后)"; fi
  # 08-18 白天:默认改聊天腿,因为底座腿借 Claude Code 当壳、在 Go 上必 400。
  # 08-18 晚:**改回底座腿** —— 底座换成 opencode CLI 自己(track opencode-agent-base),
  # 400 那个前提没了。依据是端到端实跑:它自己 git status / Read / Glob 抓到埋的雷。
  # 「换成 opencode 自己的底座就改回 agent」这句话当时就写在旧注释里,现在兑现。
  grep -q "GLM-AGENT-LEG" "$d/G1.subglm.log" 2>/dev/null
  check "panel: GLM 默认走底座腿(opencode 底座,自己读仓库)" $?
  PANEL_GLM_LEG=off bash "$pb/panel-review" --no-my-review "$d/t.md" "$d" "$d/G2" >/dev/null 2>&1
  if [[ -e "$d/G2.subglm.log" ]]; then bad "panel: PANEL_GLM_LEG=off 还能把它关掉"; else ok "panel: PANEL_GLM_LEG=off 还能把它关掉"; fi
  rm -f "$pb/subglm-agent" "$pb/subglm"

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
  # 2026-08-18:**这一圈只剩 deepseek**。GLM 换成 opencode 底座之后,它的提示词走位置
  # 参数、约束住在生成的配置里,claude 那套 argv/stdin 断言对它整块问错了对象。
  # GLM 的同名五件事在下面 ①b 用 opencode 的形状重问 —— **一件都没少**。
  for leg in subdeepseek; do
    local keyenv=(DEEPSEEK_API_KEY=dk)
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

  # ---- ①b GLM 腿(opencode 底座)的同五件事,用它自己的形状问
  oc_stub "$b"
  local ge="$d/ochome17"
  argv_has() { python3 -c "
import sys
blob=open(sys.argv[1],'rb').read().decode('utf-8','replace')
sys.exit(0 if sys.argv[2] in blob else 1)" "$1" "$2"; }
  env PATH="$b:$PATH" CAPTURE="$d/glm.e1.argv" OPENCODE_REVIEW_HOME="$ge" ZHIPU_API_KEY=zk \
    STUB_OC_OUT="Direction: 单一看法" \
    bash "$b/subglm-agent" explore "$d/brief.md" "$d/glm.e1.log" "$d" >/dev/null 2>&1; rc=$?
  check "V17: subglm-agent(opencode 底座)接受 explore 且无裁决输出仍 rc=0" $([[ $rc -eq 0 ]]; echo $?)
  [[ -s "$d/glm.e1.log" ]]; check "V17: subglm-agent explore 写出了日志" $?
  if [[ -f "$d/glm.e1.argv" ]]; then
    argv_has "$d/glm.e1.argv" "Direction"
    check "V17: subglm-agent explore 提示词带发散格式(Direction)" $?
    # 否定断言的老坑:捕获文件不存在时它会假绿,所以先要求 brief 确实在里面
    if argv_has "$d/glm.e1.argv" "开放设计分叉" && ! argv_has "$d/glm.e1.argv" "Conclusion: PASS"; then
      ok  "V17: subglm-agent explore 提示词不再索要裁决行"
    else
      bad "V17: subglm-agent explore 提示词不再索要裁决行"
    fi
  else
    bad "V17: subglm-agent explore 提示词带发散格式(Direction)"
    bad "V17: subglm-agent explore 提示词不再索要裁决行"
    echo "    (opencode 桩没被调到 ⇒ 这两条在测空气)"
  fi
  # 换模式 ≠ 换权限:explore 下只读锁一个字都不许松
  local gcfg="$ge/.config/opencode/opencode.json"
  if [[ -f "$gcfg" ]]; then
    local goff; goff="$(occfg "$gcfg" tools_off)"
    [[ " $goff " == *" write "* && " $goff " == *" edit "* ]]
    check "V17: subglm-agent explore 仍无写工具(配置里 write/edit 关着)" $?
    # 08-19 反转(同 V28):bash 留着。换模式不许**收紧**成看不了 git,
    # 也不许放松写口 —— 两个方向都钉住。
    [[ " $goff " != *" bash "* ]]
    check "V17: subglm-agent explore 下 bash 也留着(换模式不许把腿弄瞎)" $?
  else
    bad "V17: subglm-agent explore 仍无写工具(配置里 write/edit 关着)"
    bad "V17: subglm-agent explore 下 bash 也留着(换模式不许把腿弄瞎)"
  fi
  # review 模式的裁决闸不许被放松(opencode 报错也 rc=0,这道闸是唯一的活口)
  env PATH="$b:$PATH" OPENCODE_REVIEW_HOME="$ge" ZHIPU_API_KEY=zk STUB_OC_OUT="看着还行" \
    bash "$b/subglm-agent" review "$d/brief.md" "$d/glm.r1.log" "$d" >/dev/null 2>&1; rc=$?
  check "V17: subglm-agent review 无裁决仍判失败(闸没被放松)" $([[ $rc -ne 0 ]]; echo $?)

  # ---- ⑤ 发散的系统提示词必须真的送达底座腿(单一真相源:panel-explore 导出它)
  env PATH="$b:$PATH" CAPTURE="$d/sysp.argv" OPENCODE_REVIEW_HOME="$ge" ZHIPU_API_KEY=zk \
    REVIEW_SYSTEM_PROMPT="ANGLE_NOT_CONSENSUS_MARKER" \
    bash "$b/subglm-agent" explore "$d/brief.md" "$d/sysp.log" "$d" >/dev/null 2>&1
  if [[ -f "$d/sysp.argv" ]]; then
    argv_has "$d/sysp.argv" "ANGLE_NOT_CONSENSUS_MARKER"
    check "V17: REVIEW_SYSTEM_PROMPT 送达底座腿(发散指令不丢)" $?
  else
    bad "V17: REVIEW_SYSTEM_PROMPT 送达底座腿(发散指令不丢)"
  fi

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
  # **保留 env -u**:顶部那行 export 08-18 已删;问默认档的断言自己摘环境,
  # 不依赖"外面正好没设"。
  # 不摘掉的话这条问的是那个 export、不是默认档 —— 实测它在 panel-explore 默认值
  # 是 chat 的那段时间里**一直是绿的**(2026-08-18 抓到,今天第三条同形状的瞎断言:
  # 问"默认是什么"却在被污染的环境里问)。
  env -u PANEL_GLM_LEG PANEL_STAGGER_MAX=0 bash "$pb/panel-explore" "$d/brief.md" "$d" "$d/E1" >/dev/null 2>&1
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
  # 2026-08-18:GLM 换成 opencode 底座之后,上限不在 claude 的 --max-turns 里了,
  # 而在 opencode 配置的 `steps` 字段(schema 里 maxSteps 已标废弃)。
  # **这条断言必须跟着搬家,不能跟着消失** —— 它当初就是为了"我合并躯干时把 GLM 的
  # 预算顺手翻倍"立的;换底座把上限弄丢,是同一种病的新形态。
  oc_stub "$ab"
  local zochome="$d/ochome21"
  env PATH="$ab:$PATH" OPENCODE_REVIEW_HOME="$zochome" ZHIPU_API_KEY=zk \
    bash "$ab/subglm-agent" review "$d/t.md" "$d/z.log" "$d/repo" >/dev/null 2>&1
  local zcfg="$zochome/.config/opencode/opencode.json"
  if [[ -f "$zcfg" ]]; then
    [[ "$(occfg "$zcfg" steps)" == "40" ]]
    check "V21: zhipu 默认轮次上限仍是历史值 40(换底座不许把上限弄丢)" $?
  else
    bad "V21: zhipu 默认轮次上限仍是历史值 40(换底座不许把上限弄丢)"
    echo "    (没生成 opencode 配置 ⇒ 这条是在测空气)"
  fi
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

  # 场景一:submimo 绿、subdeepseek 死(rc=5)、**GLM 显式关掉**、kimi 绿
  printf '#!/bin/bash\necho "STUB PASS" > "$3"\nexit 0\n' > "$pb/submimo"
  printf '#!/bin/bash\necho "STUB PASS" > "$3"\nexit 0\n' > "$pb/subkimi"
  printf '#!/bin/bash\necho "boom" >&2\nexit 5\n' > "$pb/subdeepseek"
  chmod +x "$pb/submimo" "$pb/subkimi" "$pb/subdeepseek"
  # 08-18:这里原本写 `env -u PANEL_GLM_LEG`,靠"默认就是 off"隐式让 GLM 关着 ——
  # 那天默认翻成 agent,这条判据就跟着红了。它要问的是**关着的腿怎么记账**
  # (08-05 那笔账),不是"默认开还是关"(那条归 V13 管)。把关法写明,
  # 别让一条判据挂在一个会漂的默认值上。
  PANEL_GLM_LEG=off bash "$pb/panel-review" --no-my-review "$d/t.md" "$repo" "$d/R1" >"$d/r1.out" 2>&1
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
# ---------------------------------------------------------------- V25
# 腿必须起在**自己的会话里**,否则调用者一断线,SIGTERM 打到整个进程组,
# 还没跑完的腿连同它的结论一起没。08-16 / 08-17 两次断线都栽在这儿,
# 而每次挨刀的都是 kimi —— **它不是最脆的,是尾巴最长的**(11~18 分钟)。
#
# 这条判据问的是"腿的 SID 和调用者的 SID 不一样",不是"脚本里有没有 setsid 这几个字":
# 后者是在规定代码长什么样,而且改个写法就瞎(今天刚在 design-studio 那边为同一种病
# 重写过一道闸)。
v25_legs_run_in_their_own_session() {
  echo "[V25] 腿起在自己的会话里(断线砍不到还在跑的那条)"
  local d b; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"
  cp "$BIN/panel-review" "$b/panel-review"
  printf '# t\n' > "$d/t.md"

  # 假腿:把自己的 SID 写进它那份日志(第 3 个参数)
  local leg
  for leg in submimo subdeepseek subglm; do
    cat > "$b/$leg" <<'EOF'
#!/usr/bin/env bash
ps -o sid= -p $$ | tr -d ' ' > "$3"
exit 0
EOF
    chmod +x "$b/$leg"
  done

  bash "$b/panel-review" --no-my-review "$d/t.md" "$d" "$d/S" >/dev/null 2>&1
  local mine; mine="$(ps -o sid= -p $$ | tr -d ' ')"
  for leg in submimo subdeepseek subglm; do
    local got; got="$(cat "$d/S.$leg.log" 2>/dev/null || echo MISSING)"
    if [[ "$got" == "MISSING" || -z "$got" ]]; then
      bad "V25: $leg 没写下自己的 SID(判据自己坏了,不是结论)"
    elif [[ "$got" == "$mine" ]]; then
      bad "V25: $leg 和调用者同一个会话($got)⇒ 断线会连它一起砍"
    else
      ok "V25: $leg 在自己的会话里(它 $got / 调用者 $mine)"
    fi
  done
  rm -rf "$d"
}

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
  for entry in "submimo|review" "subchat|deepseek review" "subagent|deepseek review" "subkimi|review"; do
    IFS='|' read -r tool args <<< "$entry"
    cp "$BIN/$tool" "$b/$tool"
    # ① 约定路径的自审文件不存在 ⇒ 拒跑,且错误信息点名"先写你自己的一遍"
    out="$(cd "$d" && env -u REVIEW_MY_REVIEW REVIEW_NO_MY_REVIEW=0 PANEL_DISPATCH=0 \
            timeout "$GATE_PROBE_TIMEOUT" bash "$b/$tool" $args "$d/t.md" "$d/out.log" "$d/repo" 2>&1)"; rc=$?
    check "V23: $tool 没有自审文件 ⇒ 拒跑" $([[ $rc -ne 0 ]]; echo $?)
    grep -q "自己的一遍" <<<"$out"; check "V23: $tool 说清是缺自审(不是别的报错)" $?

    # ② 自审文件在**仓内** ⇒ 拒跑(腿会照着我的答案抄)
    printf '我的一遍\n' > "$d/repo/mine.md"
    out="$(cd "$d" && REVIEW_NO_MY_REVIEW=0 REVIEW_MY_REVIEW="$d/repo/mine.md" timeout "$GATE_PROBE_TIMEOUT" bash "$b/$tool" $args \
            "$d/t.md" "$d/out.log" "$d/repo" 2>&1)"; rc=$?
    check "V23: $tool 自审文件在仓内 ⇒ 拒跑" $([[ $rc -ne 0 ]]; echo $?)

    # ③ 显式退出闸 ⇒ 不再被这道闸拦(会因为别的原因失败,但不许是这一句)
    out="$(cd "$d" && REVIEW_NO_MY_REVIEW=1 timeout "$GATE_PROBE_TIMEOUT" bash "$b/$tool" $args \
            "$d/t.md" "$d/out.log" "$d/repo" 2>&1)"
    if grep -q "自己的一遍" <<<"$out"; then
      bad "V23: $tool REVIEW_NO_MY_REVIEW=1 应当放行这道闸"
    else ok "V23: $tool REVIEW_NO_MY_REVIEW=1 应当放行这道闸"; fi

    # ④ panel-review 派发时不许被重复拦(它在自己那层已经查过)
    out="$(cd "$d" && REVIEW_NO_MY_REVIEW=0 timeout "$GATE_PROBE_TIMEOUT" bash "$b/$tool" $args \
            "$d/t.md" "$d/out.log" "$d/repo" --panel-dispatch 2>&1)"
    if grep -q "自己的一遍" <<<"$out"; then
      bad "V23: $tool 在 panel 派发下不许重复拦(否则四审整个派不出去)"
    else ok "V23: $tool 在 panel 派发下不许重复拦(否则四审整个派不出去)"; fi
    rm -f "$d/repo/mine.md"
  done
  # ⑤ realpath 不可用 ⇒ **拒跑**,不许静默放行。
  #    四审 subkimi 指出:panel-review 原来那层对 realpath 不带 `|| return 0`,
  #    我下沉成共享件时顺手加了个 fail-open —— **重构悄悄把检查改松了**,是真回归。
  local fb="$d/fakebin"; mkdir -p "$fb"
  printf '#!/bin/bash\nexit 1\n' > "$fb/realpath"; chmod +x "$fb/realpath"
  printf '我的一遍\n' > "$d/mine.md"
  cp "$BIN/_my-review-gate.sh" "$b/" 2>/dev/null
  out="$(cd "$d" && PATH="$fb:$PATH" REVIEW_NO_MY_REVIEW=0 REVIEW_MY_REVIEW="$d/mine.md" \
          timeout "$GATE_PROBE_TIMEOUT" bash "$b/submimo" review "$d/t.md" "$d/out.log" "$d/repo" 2>&1)"
  grep -qi "realpath" <<<"$out"
  check "V23: realpath 不可用 ⇒ 拒跑并说明(不许静默跳过仓内检查)" $?
  rm -rf "$d"
}


# ---------------------------------------------------------------- V24
v24_no_env_backdoor_and_coverage_report() {
  echo "[V24] 后门封死:环境变量不再能跳过反锚定闸;清单漏网要有人吭一声"
  local d b rc out; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b" "$d/repo"
  ( cd "$d/repo"; git init -q; git config user.email t@t; git config user.name t
    echo x > f; git add -A; git commit -qm init )
  cp "$BIN/_my-review-gate.sh" "$b/" 2>/dev/null
  printf '# 评审任务书\n' > "$d/t.md"

  for tool in submimo subkimi subchat subagent; do
    cp "$BIN/$tool" "$b/$tool"
    local args="review"; [[ "$tool" == subchat || "$tool" == subagent ]] && args="deepseek review"
    # ① **export 一个环境变量不再能过闸**(四审两腿都点名 PANEL_DISPATCH 是零成本后门:
    #    从 shell 里 export 一次,之后每条命令都自动带着,而且不留痕)
    out="$(cd "$d" && PANEL_DISPATCH=1 REVIEW_NO_MY_REVIEW=0 \
            timeout "$GATE_PROBE_TIMEOUT" bash "$b/$tool" $args "$d/t.md" "$d/out.log" "$d/repo" 2>&1)"
    grep -q "自己的一遍" <<<"$out"
    check "V24: $tool export PANEL_DISPATCH=1 **不再**能跳过闸" $?

    # ② 只有**显式写在命令行上**的 --panel-dispatch 才放行(不会从 shell 继承)
    out="$(cd "$d" && REVIEW_NO_MY_REVIEW=0 \
            timeout "$GATE_PROBE_TIMEOUT" bash "$b/$tool" $args "$d/t.md" "$d/out.log" "$d/repo" --panel-dispatch 2>&1)"
    if grep -q "自己的一遍" <<<"$out"; then
      bad "V24: $tool 命令行 --panel-dispatch 应当放行(否则四审派不出去)"
    else ok "V24: $tool 命令行 --panel-dispatch 应当放行(否则四审派不出去)"; fi
  done

  # ③ panel-review 派发时必须用命令行传,不许再靠 export
  grep -q -- "--panel-dispatch" "$BIN/panel-review"
  check "V24: panel-review 用命令行标记派发各腿" $?
  if grep -q "export PANEL_DISPATCH" "$BIN/panel-review"; then
    bad "V24: panel-review 不许再 export 环境变量后门"
  else ok "V24: panel-review 不许再 export 环境变量后门"; fi

  # ④ 清单漏网要看得见:总跑要报出"bin/ 里哪些工具不在规矩4 名单内"。
  #    不拦(硬堵会误报把运维脚本也拖进来),只让腐烂时有人吭一声。
  # 种一个**不在名单里**的工具:没有它这一幕问不出东西($b 里全是 sub*/_* 前缀,都被覆盖)
  printf '#!/bin/bash\nexit 0\n' > "$b/weird-new-tool"; chmod +x "$b/weird-new-tool"
  out="$(COVERAGE_BIN_DIR="$b" bash "$BIN/rust-check-review-tooling" --coverage-only 2>&1)"
  grep -q "weird-new-tool" <<<"$out"
  check "V24: 漏网报告点名那个不在名单里的工具" $?
  grep -qi "名单\|未覆盖\|漏网" <<<"$out"
  check "V24: 总跑报出规矩4 名单的漏网工具" $?

  # ⑤ **孤儿判据套件要红,不是只报**(2026-08-08 四审 F2 实证):
  #    新写的 tests/test-runlog.sh 没被加进 SUITES ⇒ 落盘那天是绿的,
  #    但从此没有任何入口再跑它,烂掉不会有人知道。本文件头部注释自己写着
  #    「新增判据套件 = 往那张表里加一行」—— 靠"记得加"就是没有闸。
  #    这里和 bin/ 名单不同:tests/test-* 没有"运维脚本"那种歧义,所以**硬红**。
  local td="$d/tests"; mkdir -p "$td"
  printf '#!/bin/bash\necho "=== total: 1 passed, 0 failed ==="\n' > "$td/test-orphan-suite.sh"
  out="$(COVERAGE_TESTS_DIR="$td" bash "$BIN/rust-check-review-tooling" --coverage-only 2>&1)"; rc=$?
  check "V24: 有判据套件不在 SUITES 里 ⇒ 总跑红(不是只报一句)" $([[ $rc -ne 0 ]]; echo $?)
  grep -q "test-orphan-suite" <<<"$out"; check "V24: 点名是哪个套件成了孤儿" $?
  # ⑥ 下划线的 shell 套件也要扫(名单那边 `tests/test_*` 是覆盖的,这边漏了就不一致)
  printf '#!/bin/bash\nexit 0\n' > "$td/test_underscore_suite.sh"
  out="$(COVERAGE_TESTS_DIR="$td" bash "$BIN/rust-check-review-tooling" --coverage-only 2>&1)"
  grep -q "test_underscore_suite" <<<"$out"; check "V24: tests/test_*.sh 也算判据套件,漏了要点名" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- V26
# GLM 腿换后端:智谱开放平台 bigmodel(欠费,08-04 起默认关着)→ **OpenCode Go**
# ($10/月订阅,业主 2026-08-18 买的)。壳一个字没换,换的是端点/key/模型。
#
# 这一节问的是 V8/V9 问不出来的三件事:
#   ① **认证 header 风格是表驱动的**。Go 的 Anthropic 面只认 x-api-key;
#      我们的壳一直注的是 ANTHROPIC_AUTH_TOKEN(=Bearer),实测 401 "Missing API key"。
#      传对 key、传错 header ⇒ 腿是死的,而日志上只看得见"模型没回话"。
#   ② **只换这条腿**。同一份躯干(subagent/subchat)服务着 deepseek,
#      "顺手统一"是本机记过账的老毛病(合并躯干那次我一度把 GLM 的轮次上限翻了倍)。
#   ③ **key 不许进仓**。新 key 落在 ~/.config/opencode-go/auth.json,
#      仓里任何被跟踪的文件都不许出现 API key 形状的字符串。
v26_glm_on_opencode_go() {
  echo "[V26] GLM 腿改挂 OpenCode Go:端点/认证风格/模型/key 落位,且不碰 deepseek"
  local d b rc; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"
  cp "$BIN/subglm-agent" "$BIN/subdeepseek-agent" "$BIN/subagent" \
     "$BIN/subchat" "$BIN/subglm" "$BIN/subdeepseek" "$b/"
  cat > "$b/claude" <<'PYEOF2'
#!/usr/bin/env python3
import sys, os, json
out = {"env": {k: os.environ.get(k) for k in
               ["ANTHROPIC_AUTH_TOKEN","ANTHROPIC_BASE_URL","ANTHROPIC_API_KEY",
                "ANTHROPIC_DEFAULT_SONNET_MODEL"]}}
open(os.environ["CAPTURE"], "w").write(json.dumps(out))
print(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "stub\nConclusion: PASS"}]}}))
PYEOF2
  chmod +x "$b/claude"
  cat > "$b/submimo-review" <<'PYEOF2'
import sys, os, json
keys = ["MIMO_API_KEY","MIMO_BASE_URL","MIMO_CHAT_COMPLETIONS_URL","MIMO_MODEL"]
open(os.environ["CAPTURE"], "w").write(json.dumps({"env": {k: os.environ.get(k) for k in keys}}))
PYEOF2
  printf '# review this\n' > "$d/t.md"
  get() { python3 -c "import json,sys;v=json.load(open(sys.argv[1]))['env'].get(sys.argv[2]);print('' if v is None else v)" "$1" "$2"; }

  # ── ① 默认模型:两条形态都必须是 glm-5.2(Go 上这把 key 能用的旗舰档)
  # 2026-08-18:底座腿改跑 opencode ⇒ "默认模型是什么"要去它生成的配置里问,
  # claude 那套 ANTHROPIC_DEFAULT_*_MODEL 对这条腿已经不再生效(供应商表里那几个
  # claude 专用值留着是为了将来切回,**不是活路径**,所以不许再拿它们当断言对象)。
  oc_stub "$b"
  local m1home="$d/ochome26"
  env PATH="$b:$PATH" OPENCODE_REVIEW_HOME="$m1home" ZHIPU_API_KEY=zk \
    bash "$b/subglm-agent" review "$d/t.md" "$d/m1.log" "$d" >/dev/null 2>&1
  local m1cfg="$m1home/.config/opencode/opencode.json"
  if [[ -f "$m1cfg" ]]; then
    [[ "$(occfg "$m1cfg" model)" == "go/glm-5.2" ]]
    check "V26: 底座腿默认模型 glm-5.2(在 opencode 配置里)" $?
  else
    bad "V26: 底座腿默认模型 glm-5.2(在 opencode 配置里)"; echo "    (没生成配置 ⇒ 测空气)"
  fi
  env PATH="$b:$PATH" CAPTURE="$d/m2.json" ZHIPU_API_KEY=zk \
    bash "$b/subglm" review "$d/t.md" "$d/m2.log" "$d" >/dev/null 2>&1
  [[ "$(get "$d/m2.json" MIMO_MODEL)" == "glm-5.2" ]]
  check "V26: 聊天腿默认模型 glm-5.2" $?

  # ── ② 默认 key 文件搬到 ~/.config/opencode-go/(旧的 zhipu/auth.json 是另一家的账)
  #    用假 HOME 跑:没 key 时它必须**点名新路径**并且**在调 claude 之前就死**。
  local fakehome="$d/home"; mkdir -p "$fakehome"
  rm -f "$d/h1.json"
  env -u ZHIPU_API_KEY -u ZHIPU_AUTH_FILE PATH="$b:$PATH" CAPTURE="$d/h1.json" HOME="$fakehome" \
    bash "$b/subglm-agent" review "$d/t.md" "$d/h1.log" "$d" >/dev/null 2>"$d/h1.err"; rc=$?
  check "V26: 底座腿没 key 时硬失败" $([[ $rc -ne 0 ]]; echo $?)
  grep -q "opencode-go/auth.json" "$d/h1.err"
  check "V26: 底座腿默认 key 文件 = ~/.config/opencode-go/auth.json" $?
  if [[ -e "$d/h1.json" ]]; then bad "V26: 没 key 时 claude 压根没被调起"; else ok "V26: 没 key 时 claude 压根没被调起"; fi
  env -u ZHIPU_API_KEY -u ZHIPU_AUTH_FILE PATH="$b:$PATH" CAPTURE="$d/h2.json" HOME="$fakehome" \
    bash "$b/subglm" review "$d/t.md" "$d/h2.log" "$d" >/dev/null 2>"$d/h2.err"; rc=$?
  check "V26: 聊天腿没 key 时硬失败" $([[ $rc -ne 0 ]]; echo $?)
  grep -q "opencode-go/auth.json" "$d/h2.err"
  check "V26: 聊天腿默认 key 文件 = ~/.config/opencode-go/auth.json" $?

  # ── ③ deepseek 腿一个字都没被顺手改(同一份躯干,差异只准活在供应商表里)
  env PATH="$b:$PATH" CAPTURE="$d/ds1.json" DEEPSEEK_API_KEY=dk \
    bash "$b/subdeepseek-agent" review "$d/t.md" "$d/ds1.log" "$d" >/dev/null 2>&1
  [[ "$(get "$d/ds1.json" ANTHROPIC_BASE_URL)" == "https://api.deepseek.com/anthropic" ]]
  check "V26: deepseek 底座腿端点没被顺手改" $?
  [[ "$(get "$d/ds1.json" ANTHROPIC_AUTH_TOKEN)" == "dk" ]]
  check "V26: deepseek 仍走 Bearer(AUTH_TOKEN),没被 GLM 的 header 风格串味" $?
  [[ -z "$(get "$d/ds1.json" ANTHROPIC_API_KEY)" ]]
  check "V26: deepseek 那格 x-api-key 保持空" $?
  env PATH="$b:$PATH" CAPTURE="$d/ds2.json" DEEPSEEK_API_KEY=dk \
    bash "$b/subdeepseek" review "$d/t.md" "$d/ds2.log" "$d" >/dev/null 2>&1
  [[ "$(get "$d/ds2.json" MIMO_BASE_URL)" == "https://api.deepseek.com" ]]
  check "V26: deepseek 聊天腿端点没被顺手改" $?

  # ── ④ 机上真 key 落位:文件在、只有属主读得了、是合法 JSON 且 key 非空
  local authf="$HOME/.config/opencode-go/auth.json"
  if [[ -f "$authf" ]]; then
    ok "V26: OpenCode Go key 文件就位($authf)"
    [[ "$(stat -c '%a' "$authf")" == "600" ]]
    check "V26: key 文件权限 600" $?
    python3 -c "import json,sys;k=json.load(open(sys.argv[1])).get('key','');sys.exit(0 if k.startswith('sk-') and len(k)>32 else 1)" "$authf"
    check "V26: key 文件里是一把像样的 key" $?
  else
    bad "V26: OpenCode Go key 文件就位($authf)"
    bad "V26: key 文件权限 600"
    bad "V26: key 文件里是一把像样的 key"
  fi

  # ── ④b base URL 不许以 /v1 结尾。claude CLI 自己会补 `/v1/messages`,
  #    写成 .../go/v1 会发到 /zen/go/v1/v1/messages(实测 404),而 CLI 把这个 404
  #    报成「模型 glm-5.2 不存在」—— 一个地址 bug 伪装成模型名 bug,08-18 真栽过。
  # 08-18 晚:底座换成 opencode 之后,**这两条问的东西整个变了**。
  # 旧规格(不带 /v1)是给 claude 壳的:claude CLI 自己会补 /v1/messages。
  # opencode 走的是 OpenAI 兼容面,要的是**完整的** .../zen/go/v1。
  # 所以不是放宽,是换了被问的对象;claude 壳那条规格由 deepseek 那格继续守着(V9)。
  if [[ -f "$m1cfg" ]]; then
    [[ "$(occfg "$m1cfg" baseURL)" == "https://opencode.ai/zen/go/v1" ]]
    check "V26: 底座腿 base URL = opencode.ai/zen/go/v1(OpenAI 兼容面要完整路径)" $?
  else
    bad "V26: 底座腿 base URL = opencode.ai/zen/go/v1(OpenAI 兼容面要完整路径)"
  fi

  # ── ④c 聊天腿必须带 User-Agent。urllib 的默认 UA 会被 Cloudflare 前置的端点
  #    403(error code 1010);同一个请求 curl 200 / urllib 403,只差这一行。
  #    这里用**本机 stub 服务**问,不出外网(判据不许有外网出口)。
  # **让内核挑端口**,别写死 8791:端口被占(并发跑 / 上次断线留下的遗孤)⇒ stub 起不来
  # ⇒ 这条判据误红。08-18 四审两处独立点到这个量具隐患。绑 0 之后把真端口回写出来。
  # stub 服务:绑好端口后自己写一个 ready 文件,**别用 /dev/tcp 探活** ——
  # handle_request() 只服务一次,探活那条连接会把它唯一的那次用掉,
  # 于是真请求撞上"连接被拒",而判据看到的现象是"stub 没收到请求"。
  # (08-18 第一版就是这么写的,红了一轮才看明白是量具自己的问题。)
  python3 - "$d/ua.json" "$d/ua.port" "$d/ua.ready" <<'PYUA' &
import http.server, json, sys, pathlib
out, portfile, ready = sys.argv[1], sys.argv[2], sys.argv[3]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('content-length', 0)); self.rfile.read(n)
        json.dump({"ua": self.headers.get("User-Agent")}, open(out, "w"))
        r = json.dumps({"choices":[{"message":{"content":"stub\nConclusion: PASS"}}]}).encode()
        self.send_response(200); self.send_header('content-type','application/json')
        self.send_header('content-length', str(len(r))); self.end_headers(); self.wfile.write(r)
    def log_message(self, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', 0), H)
pathlib.Path(portfile).write_text(str(srv.server_address[1]))
pathlib.Path(ready).write_text("ok")
srv.timeout = 60
srv.handle_request()
PYUA
  local stubpid=$!
  for _ in $(seq 1 40); do [[ -f "$d/ua.ready" ]] && break; sleep 0.25; done
  local port; port="$(cat "$d/ua.port" 2>/dev/null)"
  # **必须用真的那条腿**($BIN,不是 $b):$b/submimo-review 是本节自己造的桩,
  #  桩根本不发 HTTP —— 拿桩问"发出去的请求带没带 UA",问的是空气。
  ZHIPU_API_KEY=zk ZHIPU_INCLUDE="$d/t.md" \
    ZHIPU_CHAT_COMPLETIONS_URL="http://127.0.0.1:$port/v1/chat/completions" \
    bash "$BIN/subglm" review "$d/t.md" "$d/ua.log" "$d" >/dev/null 2>&1
  wait $stubpid 2>/dev/null
  if [[ -f "$d/ua.json" ]]; then
    local ua; ua="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('ua') or '')" "$d/ua.json")"
    [[ -n "$ua" && "$ua" != Python-urllib* ]]
    check "V26: 聊天腿带自己的 User-Agent(urllib 默认 UA 会被 Cloudflare 403)" $?
  else
    bad "V26: 聊天腿带自己的 User-Agent(urllib 默认 UA 会被 Cloudflare 403)"
    echo "    (stub 没收到请求 —— 判据自己没跑起来,不许当成绿)"
  fi

  # ── ⑤ key 绝不许进仓:被跟踪的文件里不许有 API key 形状的字符串。
  #    这里故意**不写出那把真 key**(判据自己会变成泄漏点),只查形状。
  #    不给任何文件开豁免 —— 判据自己是最可能被粘进真 key 的那个文件,而这条正则
  #    实测不会匹配到它自身(方括号不在字符集里)。豁免白给,却正好豁免掉高危文件。
  local repo="/root/aiwork" hits grc
  hits="$(git -C "$repo" grep -nIE 'sk-[A-Za-z0-9_-]{40,}' -- .)"; grc=$?
  # git grep: 0=有命中 1=无命中 其它=它自己坏了。坏了必须红,不许静默报绿
  #(本机记过账:闸在自己跑不起来的时候报绿,比不装这道闸更坏)。
  if [[ $grc -gt 1 ]]; then
    bad "V26: 仓里被跟踪的文件不含 API key 形状的字符串"; echo "    (git grep 自己失败 rc=$grc,判据不可用)"
  elif [[ -z "$hits" ]]; then ok "V26: 仓里被跟踪的文件不含 API key 形状的字符串"
  else bad "V26: 仓里被跟踪的文件不含 API key 形状的字符串"; echo "$hits" | head -5 | sed 's/^/    /'; fi

  rm -rf "$d"
}

# ---------------------------------------------------------------- V27
# 2026-08-18 四审逼出来的三件。前两件是**行为**,第三件是"帮助文本不许谎报"。
v27_knockon_of_the_backend_switch() {
  echo "[V27] 换后端的连带面:AUTH_ENV 守卫 / panel-explore 默认档 / -h 不许谎报"
  local d; d="$(mktemp -d)"; local b="$d/bin"; mkdir -p "$b"; local rc
  printf '# review this\n' > "$d/t.md"

  # ── ① AUTH_ENV 漏填必须**硬失败**,不许静默注一个空名变量。
  #    实测(GNU coreutils 9.4):`env '=secret' cmd` **rc=0、不报错**,子进程拿到一个
  #    名字为空的 `=secret`,而 ANTHROPIC_API_KEY 根本没设 ⇒ 腿活着、每次 401,
  #    日志上只看得见"模型没回话"。这正是本单要根治的病,表驱动自己却没守卫。
  #    (08-18 四审有两条腿都断言这里是 fail-closed —— **它们都错了**,我实测的。
  #     所以这条断言不是抄评审意见,是抄实测。)
  cp "$BIN/subglm-agent" "$BIN/subagent" "$b/"
  cat > "$b/claude" <<'EOF'
#!/usr/bin/env bash
touch "$CAPTURE"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"stub\nConclusion: PASS"}]}}'
EOF
  chmod +x "$b/claude"
  # 模拟"新增供应商时忘了填 AUTH_ENV"
  sed -i 's/^\( *\)AUTH_ENV="ANTHROPIC_API_KEY"/\1AUTH_ENV=""/' "$b/subagent"
  grep -q 'AUTH_ENV=""' "$b/subagent"
  check "V27: 前置——挖空 AUTH_ENV 这一刀真的切中了(不然下面三条是在测空气)" $?
  rm -f "$d/c1.flag"
  env PATH="$b:$PATH" CAPTURE="$d/c1.flag" ZHIPU_API_KEY=zk \
    bash "$b/subglm-agent" review "$d/t.md" "$d/c1.log" "$d" >/dev/null 2>"$d/c1.err"; rc=$?
  [[ $rc -ne 0 ]]
  check "V27: AUTH_ENV 漏填时硬失败(env 会静默放过,所以守卫必须在我们这边)" $?
  if [[ -e "$d/c1.flag" ]]; then
    bad "V27: AUTH_ENV 漏填时 claude 压根没被调起"
    echo "    (claude 被调起来了 ⇒ 我们把一条注定 401 的腿放出去了)"
  else ok "V27: AUTH_ENV 漏填时 claude 压根没被调起"; fi
  grep -qi "AUTH_ENV" "$d/c1.err"
  check "V27: 报错点名 AUTH_ENV(别让人对着 401 猜)" $?

  # ── ② panel-explore 的 GLM 默认档必须和 panel-review 一致 = 聊天腿。
  #    底座腿在 Go 上必 400(见 V26/design)⇒ 默认写 agent = 每轮先白撞一次再降级。
  #    08-18 四审两条腿(kimi / deepseek)独立命中这一处,我自审漏了。
  local pb="$d/pbin"; mkdir -p "$pb"
  cp "$BIN/panel-explore" "$pb/"
  local st
  for st in submimo subdeepseek subglm subdeepseek-agent subglm-agent; do
    printf '#!/usr/bin/env bash\necho "%s-RAN" > "$3"; exit 0\n' "$st" > "$pb/$st"
    chmod +x "$pb/$st"
  done
  printf 'brief\n' > "$d/brief.md"
  env -u PANEL_GLM_LEG bash "$pb/panel-explore" "$d/brief.md" "$d" "$d/E1" >/dev/null 2>&1
  grep -q "subglm-agent-RAN" "$d/E1.subglm.log" 2>/dev/null
  check "V27: panel-explore 的 GLM 默认档 = 底座腿(和 panel-review 一致)" $?
  PANEL_GLM_LEG=chat bash "$pb/panel-explore" "$d/brief.md" "$d" "$d/E2" >/dev/null 2>&1
  grep -q "subglm-RAN" "$d/E2.subglm.log" 2>/dev/null
  check "V27: panel-explore 仍能用 PANEL_GLM_LEG=chat 强制回落聊天腿" $?

  # ── ③ `-h` 不许谎报默认值。这类"只在 -h 时打印"的字符串没人会跑到,
  #    于是它们是仓里最容易变成化石的地方 —— 08-18 四审两条腿都翻出来了。
  local h
  h="$(bash "$BIN/subagent" -h 2>&1)"
  [[ "$h" != *glm-4.6v* ]];  check "V27: subagent -h 不许还写着 glm-4.6v" $?
  [[ "$h" == *glm-5.2* ]];   check "V27: subagent -h 要写现在的默认模型 glm-5.2" $?
  h="$(bash "$BIN/subchat" -h 2>&1)"
  [[ "$h" != *glm-4.6v* ]];  check "V27: subchat -h 不许还写着 glm-4.6v" $?
  # 08-18 收口时把这条**搬到问得出的地方**:原版禁的是字符串 "bigmodel",
  # 但它连"2026-08-18 从智谱 bigmodel 换来"这种**沿革句**一起禁了 —— 而沿革句正是
  # 本机要求留的账。真正的危险是**主机名以"当前默认端点"的身份出现**,禁词禁不到这件事。
  # 改后更强:连 deepseek 那一格的旧主机名一起禁,且下一条正面钉死默认端点是什么。
  # (改题面不是放水的通行证:改完重新红检过 —— 把旧 URL 塞回去,这条必须红。)
  [[ "$h" != *open.bigmodel.cn* ]]
  check "V27: subchat -h 里不许再出现 bigmodel 的主机名(沿革句里提名字可以)" $?
  [[ "$h" == *opencode.ai/zen/go/v1/chat/completions* ]]
  check "V27: subchat -h 正面写出当前默认端点全址" $?
  # (原本这里还有一条 `[[ "$h" == *opencode* ]]`。**红检当场证明它是瞎的**:
  #  把旧 bigmodel 端点塞回去之后它照样绿 —— 它匹配到的是 auth 路径里的
  #  `~/.config/opencode-go/auth.json`,而不是端点。它被上面那条"全址"断言严格覆盖,
  #  所以删掉而不是留着凑数:一条永远绿的断言比没有更坏,它会让人以为这里有防线。)

  rm -rf "$d"
}

# ---------------------------------------------------------------- V28
# 2026-08-18 track opencode-agent-base:GLM 腿的底座从「借 Claude Code 当壳」换成
# **opencode CLI 自己**,好让它重新能自己读仓库(Go 的 Anthropic 面不做工具格式转换,
# 借壳那条路带工具必 400)。这一组问的全是**机械事实**,不打网(判据不许有外网出口):
# 用 PATH 上的 stub opencode 截获 argv + 它生成的配置。
v28_glm_on_opencode_base() {
  echo "[V28] GLM 腿改用 opencode 底座:调谁、只读锁、配置隔离、裁决 gate"
  local d; d="$(mktemp -d)"; local b="$d/bin"; mkdir -p "$b"; local rc
  printf '# review this\n' > "$d/t.md"
  cp "$BIN/subglm-agent" "$BIN/subdeepseek-agent" "$BIN/subagent" "$b/"
  local ochome="$d/ochome"

  # stub:两个底座都放上,看它到底调哪个(自述不作数,查 argv)
  cat > "$b/opencode" <<'EOF'
#!/usr/bin/env bash
{ printf '%s\n' "ARGV: $*"; printf '%s\n' "HOME: $HOME"; } > "$CAPTURE"
echo "stub reviewer output"
echo "Conclusion: PASS"
EOF
  cat > "$b/claude" <<'EOF'
#!/usr/bin/env bash
echo "CLAUDE-WAS-CALLED" > "$CAPTURE_CLAUDE"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"stub\nConclusion: PASS"}]}}'
EOF
  chmod +x "$b/opencode" "$b/claude"

  rm -f "$d/oc.txt" "$d/claude.txt"
  env PATH="$b:$PATH" CAPTURE="$d/oc.txt" CAPTURE_CLAUDE="$d/claude.txt" \
    OPENCODE_REVIEW_HOME="$ochome" ZHIPU_API_KEY=zk \
    bash "$b/subglm-agent" review "$d/t.md" "$d/g1.log" "$d" >/dev/null 2>"$d/g1.err"; rc=$?

  # ── ① 调的是 opencode,不是 claude
  [[ -f "$d/oc.txt" ]]; check "V28: GLM 腿调起的是 opencode 底座" $?
  if [[ -f "$d/claude.txt" ]]; then
    bad "V28: GLM 腿不许再调 claude 壳"
    echo "    (claude 被调起来了 ⇒ 底座没换成,或者换了一半)"
  else ok "V28: GLM 腿不许再调 claude 壳"; fi

  # ── ② 模型走订阅那个 provider(默认 provider 是按量付费,实测 Insufficient balance)
  grep -q -- "go/glm-5.2" "$d/oc.txt" 2>/dev/null
  check "V28: 模型是 go/glm-5.2(订阅 provider,不是默认按量付费那个)" $?
  grep -q -- "--agent" "$d/oc.txt" 2>/dev/null
  check "V28: 显式指定 --agent(不许吃 opencode 的默认档)" $?
  # **不许用内置 plan 档**:实测它自称"禁掉所有编辑工具",而解析出来的配置是
  # write/edit/bash 全开 + 权限 * allow ⇒ 它的只读靠模型自觉,不是闸。
  grep -qE -- "--agent[= ]+plan" "$d/oc.txt" 2>/dev/null
  check "V28: 不许用内置 plan 档当只读保证(它是模型自觉,不是机械锁)" $([[ $? -ne 0 ]]; echo $?)

  # ── ③ 配置隔离:HOME 必须被换掉,否则污染 /root/.config/opencode(我的真配置)
  grep -q "^HOME: $ochome" "$d/oc.txt" 2>/dev/null
  check "V28: 跑 opencode 时 HOME 换成隔离目录(不许碰真实 HOME)" $?

  # ── ④ 只读锁**机械成立**:生成的配置里写工具必须是 false
  local cfg="$ochome/.config/opencode/opencode.json"
  if [[ ! -f "$cfg" ]]; then
    bad "V28: 生成了隔离配置文件"
    echo "    (没有配置 ⇒ 下面几条只读断言全是在测空气)"
  else
    ok "V28: 生成了隔离配置文件"
    local off; off="$(python3 - "$cfg" <<'PYCFG'
import json,sys
c=json.load(open(sys.argv[1]))
ag=list(c.get("agent",{}).values())
t=ag[0].get("tools",{}) if ag else {}
print(" ".join(sorted(k for k,v in t.items() if v is False)))
PYCFG
)"
    local w
    for w in write edit patch task webfetch websearch skill; do
      [[ " $off " == *" $w "* ]]
      check "V28: 只读锁——配置里 $w 关掉了" $?
    done
    # **bash 整个关掉。** 这条 08-18 晚上被四审推翻重写过一次,原委必须留着:
    # 原版是"bash 留着跑只读 git,但白名单 `*` deny + 只放行 git diff/log/status/show",
    # 我还在注释里写了"这是真闸"。**四审(subdeepseek BLOCK,kimi/glm 各自也点到)证明
    # 那个保证是假的,我亲手复现了两条**:
    #   写:`git diff --output=<path>`  —— git 自己的文档化选项,写出任意文件(实测成功)
    #   读:`git diff --no-index <仓外文件> /dev/null` —— 把任意可读文件全文打进 stdout,
    #       而 stdout 会进腿日志 ⇒ 一个恶意仓可以让这条腿把订阅 key 印出来(实测成功)
    # 而且这些 diff 选项在 `git log -p` / `git show` 上同样吃 ⇒ 逐个拉黑是打地鼠;
    # 还有 `--ext-diff` + 仓内配置这类口子。**结论:对 git 这么灵活的程序做命令行
    # 白名单本身就不成立**,不是模式写得不够细。所以不留 bash。
    # 代价认下来:这条腿看不了 git 历史/diff,但它的核心价值(自己读仓库)由
    # read/glob/grep 提供,一条没丢。
    # ⚠️ 08-19 反转:**bash 必须留着**。上面那段原委(白名单挡不住 git 自己的参数)
    # 事实仍然成立,但从它推出"所以关掉 bash"是错的一步 —— 关掉之后腿读不了 git,
    # 主 agent 得算好 diff 喂进去,那条链上长出 E2BIG(两条腿直接起不来)、
    # SIGPIPE 静默暴毙、基线静默变瞎。**最坏形态是腿没跑起来而 panel 照常出结论。**
    # 正确结论是:白名单不成立 ⇒ **别用白名单**,不是 ⇒ 别给 bash。
    # 评审腿没有改判据的动机;防误伤靠**跑完的写审计**(track repo-write-audit)。
    local off2; off2="$(occfg "$cfg" tools_off)"
    [[ " $off2 " != *" bash "* ]]
    check "V28: **bash 留着**(腿要能自己读 git;关掉的代价见上,已被推翻)" $?
    # 写口仍然全关 —— 零成本,不跟着 bash 一起放
    [[ " $off2 " == *" write "* && " $off2 " == *" edit "* && " $off2 " == *" task "* ]]
    check "V28: 写口仍全关(write/edit/task)—— 零成本,不跟着 bash 一起放" $?
  fi

  # ── ⑤ 裁决 gate 必须硬:**opencode 报错也 rc=0**(实测:余额不足那次错误打在
  #    stdout 上、退出码仍是 0)⇒ 判活只能靠裁决行,不能靠 rc。
  cat > "$b/opencode" <<'EOF'
#!/usr/bin/env bash
echo "Error: Insufficient balance. Manage your billing here: https://opencode.ai/..."
exit 0
EOF
  chmod +x "$b/opencode"
  env PATH="$b:$PATH" CAPTURE="$d/oc2.txt" OPENCODE_REVIEW_HOME="$ochome" ZHIPU_API_KEY=zk \
    bash "$b/subglm-agent" review "$d/t.md" "$d/g2.log" "$d" >/dev/null 2>"$d/g2.err"; rc=$?
  [[ $rc -ne 0 ]]
  check "V28: opencode 没给裁决行时必须硬失败(它报错也 rc=0,信不得)" $?

  # ── ⑥ 没 key 时硬失败,且底座压根没被调起
  rm -f "$d/oc3.txt"
  local fakehome="$d/home"; mkdir -p "$fakehome"
  env -u ZHIPU_API_KEY -u ZHIPU_AUTH_FILE PATH="$b:$PATH" CAPTURE="$d/oc3.txt" \
    OPENCODE_REVIEW_HOME="$ochome" HOME="$fakehome" \
    bash "$b/subglm-agent" review "$d/t.md" "$d/g3.log" "$d" >/dev/null 2>"$d/g3.err"; rc=$?
  [[ $rc -ne 0 ]]; check "V28: 没 key 时硬失败" $?
  if [[ -f "$d/oc3.txt" ]]; then bad "V28: 没 key 时 opencode 压根没被调起"
  else ok "V28: 没 key 时 opencode 压根没被调起"; fi

  # ── ⑦ deepseek 腿一个字没被串味:它仍走 claude 壳
  cat > "$b/opencode" <<'EOF'
#!/usr/bin/env bash
{ printf '%s\n' "ARGV: $*"; } > "$CAPTURE"; echo "Conclusion: PASS"
EOF
  chmod +x "$b/opencode"
  rm -f "$d/oc4.txt" "$d/claude4.txt"
  env PATH="$b:$PATH" CAPTURE="$d/oc4.txt" CAPTURE_CLAUDE="$d/claude4.txt" \
    DEEPSEEK_API_KEY=dk bash "$b/subdeepseek-agent" review "$d/t.md" "$d/ds.log" "$d" >/dev/null 2>&1
  [[ -f "$d/claude4.txt" ]]
  check "V28: deepseek 腿仍走 claude 壳(换底座不许串味到隔壁)" $?
  if [[ -f "$d/oc4.txt" ]]; then bad "V28: deepseek 腿不许被顺手改成 opencode 底座"
  else ok "V28: deepseek 腿不许被顺手改成 opencode 底座"; fi

  # ── ⑮ **提示词不许宣称一个它没有的工具**。bash 关掉之后,原提示词还写着
  #    「Read, Glob, Grep, and read-only git commands」、日志的"视野"行也还写着"只读 git"
  #    ⇒ 我们在给模型喂一份假的能力清单。08-18 真跑时这条腿当场把它顶回来了:
  #    "The task's premise that I have 'read-only git commands' is incorrect."
  #    它为此白花了几轮去发现自己没有 —— 假的能力清单比少写一句更贵。
  #    ⚠️ 写法:**先要求日志存在**。我第一版把这条插在了生成日志的那个用例之前,
  #    文件不存在 ⇒ grep 找不到 ⇒ 走 else 报绿(今天第五条假绿,同一个形状:
  #    "不含某串"的否定断言在输入缺席时会假绿)。
  if [[ ! -s "$d/g1.log" ]]; then
    bad "V28: opencode 底座的提示词/视野行不许再宣称有只读 git"
    echo "    (日志不存在 ⇒ 这条在测空气,不许当绿)"
  elif grep -qE "read-only git|只读 git" "$d/g1.log"; then
    bad "V28: opencode 底座的提示词/视野行不许再宣称有只读 git"
  else
    ok  "V28: opencode 底座的提示词/视野行不许再宣称有只读 git"
  fi

  # ── ⑫ 二进制存在性检查要查**这条腿真正要用的那个**。原来无条件查 claude:
  #    opencode 底座不依赖 claude ⇒ claude 没装而 opencode 装了,腿被误杀;
  #    反过来则放行到 `opencode run` 才报一个误导性的 rc=127。
  #    (四审两条腿独立点到:subdeepseek F2 / subglm MEDIUM。)
  local nb="$d/nobin"; mkdir -p "$nb"
  cp "$BIN/subglm-agent" "$BIN/subagent" "$nb/"
  oc_stub "$nb"        # 只有 opencode,**没有 claude**
  env PATH="$nb:/usr/bin:/bin" OPENCODE_REVIEW_HOME="$ochome" ZHIPU_API_KEY=zk \
    bash "$nb/subglm-agent" review "$d/t.md" "$d/g12.log" "$d" >/dev/null 2>"$d/g12.err"; rc=$?
  [[ $rc -eq 0 ]]
  check "V28: 机器上没装 claude 也不影响 opencode 底座的腿" $?

  # ── ⑬ 日志头印**完整**模型 id(带 provider 前缀),别印一个调用时并不存在的名字
  grep -q "^model: go/glm-5.2$" "$d/g12.log" 2>/dev/null
  check "V28: 日志头印完整模型 id go/glm-5.2(不是裸 glm-5.2)" $?

  # ── ⑭ key 不许经命令行传给写配置那步(进程存续期间 ps 看得见),
  #    且配置文件**创建即 600**,不许先 644 再 chmod(中断在中间会留下可读的 key 文件)。
  # 写法注意:**别用 `check "..." $([[ $? -ne 0 ]]; echo $?)`** —— 命令替换里的 $?
  # 不是上一条 grep 的退出码。08-18 我就是这么写的,结果这条在 key 明明还走 argv 时
  # 报绿(今天第四条假绿,前三条都是"问默认档却在被污染的环境里问")。
  # 两次写错的教训都留着:
  #  ① 别用 `check "..." $([[ $? -ne 0 ]]; echo $?)` —— 命令替换里的 $? 不是上一条的退出码;
  #  ② 别用单行 grep 找 argv —— `python3 - \` 的参数在**续行**上,单行永远匹配不到
  #     (这条断言因此连报两次假绿)。所以这里取 `python3 -` 到 heredoc 标记之间的
  #     **整段 argv 文本**再看有没有 key。
  python3 - "$BIN/subagent" <<'PYARGV'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"python3 -\s(.*?)<<'PYOC'", src, re.S)
sys.exit(2 if not m else (1 if "API_KEY" in m.group(1) else 0))
PYARGV
  rc=$?
  if   [[ $rc -eq 0 ]]; then ok  "V28: key 不经 argv 传给写配置那步(ps 看得见)"
  elif [[ $rc -eq 1 ]]; then bad "V28: key 不经 argv 传给写配置那步(ps 看得见)"
  else bad "V28: key 不经 argv 传给写配置那步(ps 看得见)"; echo "    (找不到那段 argv ⇒ 判据自己坏了,不许当绿)"; fi
  grep -q "umask 077" "$BIN/subagent"
  check "V28: 写配置前设 umask 077(创建即 600,没有 644 窗口)" $?

  # ── ⑨ **stdin 必须接到 /dev/null**。2026-08-18 真事故:opencode 在 stdin 是
  #    一个还开着的管道时会**一直等输入**——在 runlog(经 tee 管道)下这条腿挂死了
  #    12 分钟、一次模型调用都没发,而日志头已经写好了,看起来"正在跑"。
  #    直接跑不挂、经管道就挂 ⇒ 这种 bug 只在真派活时出现,判据必须钉死它。
  cat > "$b/opencode" <<'EOF'
#!/usr/bin/env bash
[[ -n "${CAPTURE_STDIN:-}" ]] && readlink /proc/self/fd/0 > "$CAPTURE_STDIN" 2>/dev/null
echo "Conclusion: PASS"
EOF
  chmod +x "$b/opencode"
  rm -f "$d/stdin.txt"
  # 故意把 stdin 接成一个**开着的管道**,模拟 runlog 那种现场
  ( sleep 30 ) | env PATH="$b:$PATH" CAPTURE_STDIN="$d/stdin.txt" \
      OPENCODE_REVIEW_HOME="$ochome" ZHIPU_API_KEY=zk \
      bash "$b/subglm-agent" review "$d/t.md" "$d/g9.log" "$d" >/dev/null 2>&1
  if [[ -f "$d/stdin.txt" ]]; then
    grep -q "^/dev/null$" "$d/stdin.txt"
    check "V28: 底座的 stdin 接到 /dev/null(否则管道下它会一直等输入)" $?
  else
    bad "V28: 底座的 stdin 接到 /dev/null(否则管道下它会一直等输入)"
    echo "    (桩没被调到 ⇒ 测空气)"
  fi

  # ── ⑩ 日志头印的 base URL 必须是**实际在用的那个**。供应商表里还留着 claude 底座
  #    的休眠值(.../zen/go,不带 /v1),日志头照抄它 = 取证材料自己撒谎:
  #    以后有人拿这份日志查"到底打的哪个端点"会被带偏。
  grep -q "opencode.ai/zen/go/v1" "$d/g9.log" 2>/dev/null
  check "V28: 日志头印实际在用的 base URL(不是 claude 那条路的休眠值)" $?

  # ── ⑪ 工具轨迹必须落进**腿自己的日志**,不能只落在收据里。
  #    opencode 把 "它读了哪些文件/跑了哪些命令" 打在 stderr 上;四审时我读的是
  #    腿的日志,而"它到底看没看"正是我最需要在那儿看到的东西
  #    (claude 那条腿的日志一直是有轨迹的,换底座不许把这个能力弄丢)。
  cat > "$b/opencode" <<'EOF'
#!/usr/bin/env bash
echo "TOOL-TRACE-Read calc.py" >&2
echo "Conclusion: PASS"
EOF
  chmod +x "$b/opencode"
  env PATH="$b:$PATH" OPENCODE_REVIEW_HOME="$ochome" ZHIPU_API_KEY=zk \
    bash "$b/subglm-agent" review "$d/t.md" "$d/g11.log" "$d" >/dev/null 2>&1
  grep -q "TOOL-TRACE-Read calc.py" "$d/g11.log" 2>/dev/null
  check "V28: 工具轨迹落进腿自己的日志(四审读的是它,不是收据)" $?

  # ── ⑧ key 不许进配置以外的地方,更不许进仓(仓那条 V26 ⑤ 已经在查,这里查日志)
  if grep -rq "zk" "$d/g1.log" 2>/dev/null; then
    bad "V28: key 不许出现在日志里"
  else ok "V28: key 不许出现在日志里"; fi

  rm -rf "$d"
}

# ---------------------------------------------------------------- V29~V32(已退场)
# 2026-08-19 拆除。这四段(底座腿的 diff 注入 / argv 预算 / 三腿覆盖 / 工件排除)
# 测的是一个**已经被推翻的机制**:为了给评审腿关掉 bash,由主 agent 把 diff 算好喂进
# 提示词。业主推翻了那个方向 —— 评审腿没有"改判据让自己及格"的动机(那是执行腿的
# 威胁模型),而关掉 bash 的代价是那条链上长出 E2BIG / SIGPIPE 静默暴毙 / 基线静默变瞎,
# 最坏形态是**两条腿根本没跑起来而 panel 照常出结论**。
#
# ⚠️ 这不是"删断言让自己及格":被删的断言测的是**不复存在的代码路径**
# (`bin/_prompt-budget.sh` 同轮删除),留着只会永远绿或永远红,两种都是噪音。
# 全文在 git 历史里:`git log --oneline -- tests/test-review-tooling.sh`,
# 拆除那一版是本行所在 commit 的父提交。
# 替代防线是新 track `repo-write-audit`(写审计,按进程树归因),**它还没上线** ——
# 窗口期是明账,写在 tracks/repo-write-audit/proposal.md 末尾。

# ---------------------------------------------------------------- V33
# 2026-08-19,收本轮四审 subkimi 的 F1(孤腿 BLOCK,成立)。
#
# 本单从头到尾在堵"评审腿能往被评审的仓里写 ⇒ 能改判据"。我以为是三条腿,
# **漏了 panel 的第一条**:`bin/submimo` 跑的是 `mimo run --agent plan`,
# 是 MiMoCode **agent 底座**,不是我一直以为的聊天腿 —— 这个错误分类我还亲手
# 写进了给评审腿的任务书,是腿去读代码把我推翻的。
#
# 取证(`mimo debug agent plan`,收据 20260819T025552Z):
#     description: "Plan mode. Disallows all edit tools."   ← 自述
#     tools:  bash=True  write=True  edit=True  task=True  webfetch=True  skill=True
#     permission: {"*": allow "*"},只有 edit 被 deny
# ⇒ **能跑任意命令、能写新文件**,比已修的三条腿的洞都大。而它一直在跑。
# 和 opencode 内置 plan 档一模一样的病(subagent 里早有取证):**自称禁编辑,
# 实际全开** —— 只读靠模型自觉,不是闸。
#
# ⚠️ 边界一(业主当场拦下的):`submimo` 有两个身份。`fix` 是**执行腿**,
# 写代码就是它的本职,`--agent build` 一个字都不许动。只锁 review / explore。
# 这条判据因此必须带**反面对照组**,否则"加一道防线顺手拆掉另一道"。
#
# ⚠️ 边界二(08-19 业主拍板转向后):**bash 必须留着。**
# 关 bash 那条路已经走过并被推翻:代价是腿不能自己读 git,于是要由主 agent 算好
# diff 喂进去,而那条链上长出了 E2BIG / SIGPIPE 静默暴毙 / 基线静默变瞎 一整串 bug,
# 最坏的形态是**两条腿根本没跑起来而 panel 照常出结论**。
# 评审腿没有"改判据让自己及格"的动机(那是执行腿的威胁模型),
# 对面是误伤不是有动机的对手 ⇒ 用**跑完检测工作树**兜底,不用砍能力。
# 下面因此有一条**反向断言:bash 不许被关掉** —— 它挡的是"以后又有人觉得关掉更安全"。
v33_submimo_review_leg_is_read_only() {
  echo "[V33] panel 第一条腿(submimo)写口关掉、bash 留着,fix 不受连累"
  local d b rc; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"
  local REAL_MIMO; REAL_MIMO="$(command -v mimo || true)"
  cp "$BIN/submimo" "$b/"
  printf '# t\n' > "$d/t.md"
  local repo="$d/repo"; mkdir -p "$repo"
  ( cd "$repo" && git init -q . && printf 'x\n' > a.txt && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm base ) >/dev/null 2>&1

  # stub mimo:只落 argv(查它到底用哪个档),不碰真底座
  cat > "$b/mimo" <<'EOF'
#!/usr/bin/env bash
python3 -c "
import os,sys,json
json.dump({'argv':sys.argv[1:]},open(os.environ['CAPTURE'],'w'))" "$@"
echo "stub review output"; echo "Conclusion: PASS"
EOF
  chmod +x "$b/mimo"
  local agent_of; agent_of() {
    python3 -c "
import json,sys
a=json.load(open(sys.argv[1]))['argv']
print(a[a.index('--agent')+1] if '--agent' in a else '')" "$1"
  }

  local mhome="$d/mimohome"

  # ── ⓪ 前置锚:内置 plan 档**确实**是全开的。
  #    没有这一条,下面所有断言都可能是在给一个本来就没问题的东西加锁(测空气)。
  #    用 mimo 自己的解析器取证 —— 查工件不查自述。
  if [[ -n "$REAL_MIMO" ]]; then
    local planopen
    planopen="$("$REAL_MIMO" debug agent plan 2>/dev/null | python3 -c "
import json,sys
try: t=json.load(sys.stdin).get('tools',{})
except Exception: print('ERR'); raise SystemExit
print('OPEN' if (t.get('write') and t.get('task')) else 'LOCKED')" 2>/dev/null)"
    [[ "$planopen" == "OPEN" ]]
    check "V33: 锚 —— 内置 plan 档实测 write+task 全开(自称 Disallows all edit tools)" $?
  else
    bad "V33: 锚 —— 内置 plan 档实测 write+task 全开"
    echo "    (机器上没有 mimo,这条取证跑不了)"
  fi

  # ── ① review 不许再用内置 plan 档
  rm -f "$d/c_review"
  env PATH="$b:$PATH" CAPTURE="$d/c_review" MIMO_REVIEW_HOME="$mhome" \
    bash "$b/submimo" review "$d/t.md" "$d/r.log" "$repo" >/dev/null 2>&1
  if [[ -f "$d/c_review" ]]; then
    local ag; ag="$(agent_of "$d/c_review")"
    [[ "$ag" != "plan" && -n "$ag" ]]
    check "V33: review 模式不许再用内置 plan 档(实际用的是 '$ag')" $?
  else
    bad "V33: review 模式不许再用内置 plan 档"
    echo "    (stub 没被调起 ⇒ 测空气)"
  fi

  # ── ② explore 同样(它的指令还写着"不许用任何工具",更不该有 shell)
  rm -f "$d/c_explore"
  env PATH="$b:$PATH" CAPTURE="$d/c_explore" MIMO_REVIEW_HOME="$mhome" \
    bash "$b/submimo" explore "$d/t.md" "$d/e.log" "$repo" >/dev/null 2>&1
  if [[ -f "$d/c_explore" ]]; then
    local ag2; ag2="$(agent_of "$d/c_explore")"
    [[ "$ag2" != "plan" && -n "$ag2" ]]
    check "V33: explore 模式不许再用内置 plan 档(实际用的是 '$ag2')" $?
  else
    bad "V33: explore 模式不许再用内置 plan 档"
  fi

  # ── ③ **反面对照(业主拦下的那条)**:fix 是执行腿,写代码是本职。
  #    只读锁不许连坐到它身上 —— 那等于把执行腿打死。
  rm -f "$d/c_fix"
  env PATH="$b:$PATH" CAPTURE="$d/c_fix" MIMO_REVIEW_HOME="$mhome" \
    bash "$b/submimo" fix "$d/t.md" "$d/f.log" "$repo" >/dev/null 2>&1
  if [[ -f "$d/c_fix" ]]; then
    local ag3; ag3="$(agent_of "$d/c_fix")"
    [[ "$ag3" == "build" ]]
    check "V33: 对照 —— fix 仍用 build 档(执行腿要写代码,不许被顺手锁死)" $?
  else
    bad "V33: 对照 —— fix 仍用 build 档(执行腿要写代码,不许被顺手锁死)"
  fi

  # ── ④ 锁必须是**机械的**:拿 mimo 自己的解析器去读我们生成的配置。
  #    只查"我们往 json 里写了什么"是不够的 —— plan 档骗过我的正是这个区别:
  #    配置说一套、解析出来是另一套。
  if [[ -f "$mhome/.config/mimocode/mimocode.json" ]]; then
    ok "V33: 只读 agent 的配置生成在隔离 HOME(没污染 /root/.config/mimocode)"
    if [[ -n "$REAL_MIMO" ]]; then
      # 写口必须关:write/edit/task/webfetch/skill。这几样评审腿本来就不需要,
      # 关掉是**零成本**的 —— 和关 bash 完全不同(那个的代价见文件头边界二)。
      # task 尤其要关:spawn 子代理 = 子代理有自己的工具面 = 现成的绕过通道。
      local wopen
      wopen="$(HOME="$mhome" "$REAL_MIMO" debug agent aiwork-review 2>/dev/null | python3 -c "
import json,sys
try: t=json.load(sys.stdin).get('tools',{})
except Exception: print('ERR'); raise SystemExit
bad=[k for k in ('write','edit','patch','task','webfetch','skill') if t.get(k)]
print(','.join(bad) if bad else 'NONE')" 2>/dev/null)"
      [[ "$wopen" == "NONE" ]]
      check "V33: 写口全关(残留: ${wopen:-?})—— write/edit/patch/task/webfetch/skill" $?

      # **反向断言**:bash 不许被关掉。
      # 这条挡的不是攻击者,是**未来的我** —— 08-18 我就是觉得"关掉更安全"才关的,
      # 结果两条腿静默不跑、一天半白干。腿要能自己 git diff/log/show 读仓库。
      local bashon
      bashon="$(HOME="$mhome" "$REAL_MIMO" debug agent aiwork-review 2>/dev/null | python3 -c "
import json,sys
t=json.load(sys.stdin).get('tools',{})
print('ON' if t.get('bash') else 'OFF')" 2>/dev/null)"
      [[ "$bashon" == "ON" ]]
      check "V33: **bash 保留**(关掉它就得自己喂 diff,那条路已被推翻)" $?

      local keep
      keep="$(HOME="$mhome" "$REAL_MIMO" debug agent aiwork-review 2>/dev/null | python3 -c "
import json,sys
t=json.load(sys.stdin).get('tools',{})
print('OK' if all(t.get(k) for k in ('read','glob','grep')) else 'MISSING')" 2>/dev/null)"
      [[ "$keep" == "OK" ]]
      check "V33: read/glob/grep 还在(否则这条腿等于废了)" $?
    else
      bad "V33: 写口全关 —— write/edit/patch/task/webfetch/skill"
      bad "V33: **bash 保留**(关掉它就得自己喂 diff,那条路已被推翻)"
      bad "V33: read/glob/grep 还在"
    fi
  else
    bad "V33: 只读 agent 的配置生成在隔离 HOME(没污染 /root/.config/mimocode)"
    bad "V33: 写口全关 —— write/edit/patch/task/webfetch/skill"
    bad "V33: **bash 保留**(关掉它就得自己喂 diff,那条路已被推翻)"
    bad "V33: read/glob/grep 还在"
  fi

  # ── ⑤ 配置每次重写(它就是锁本身,不许留隔夜残留)
  if [[ -f "$mhome/.config/mimocode/mimocode.json" ]]; then
    printf '{"agent":{"aiwork-review":{"tools":{"bash":true}}}}' > "$mhome/.config/mimocode/mimocode.json"
    rm -f "$d/c_rewrite"
    env PATH="$b:$PATH" CAPTURE="$d/c_rewrite" MIMO_REVIEW_HOME="$mhome" \
      bash "$b/submimo" review "$d/t.md" "$d/r2.log" "$repo" >/dev/null 2>&1
    grep -q '"bash": *true' "$mhome/.config/mimocode/mimocode.json"
    check "V33: 配置每次重写(被人改松了也会被覆盖回去)" $([[ $? -ne 0 ]]; echo $?)
  else
    bad "V33: 配置每次重写(被人改松了也会被覆盖回去)"
  fi

  rm -rf "$d"
}

echo "=== review-tooling regression oracle ==="
REVIEW_NO_MY_REVIEW=1 v1_untracked_content
REVIEW_NO_MY_REVIEW=1 v1_no_untracked_and_nonrepo
REVIEW_NO_MY_REVIEW=1 v2_glob_not_pre_expanded
REVIEW_NO_MY_REVIEW=1 v3_panel_sidecar
REVIEW_NO_MY_REVIEW=1 v4_output_validation
REVIEW_NO_MY_REVIEW=1 v5_diff_scope
REVIEW_NO_MY_REVIEW=1 v6_truncation
REVIEW_NO_MY_REVIEW=1 v7_blind_warning
REVIEW_NO_MY_REVIEW=1 v8_subchat_provider_table
REVIEW_NO_MY_REVIEW=1 v9_claude_shell_base
REVIEW_NO_MY_REVIEW=1 v10_git_stderr_isolation
REVIEW_NO_MY_REVIEW=1 v11_panel_gates
REVIEW_NO_MY_REVIEW=1 v12_gate_default_on
REVIEW_NO_MY_REVIEW=1 v13_subkimi_leg
REVIEW_NO_MY_REVIEW=1 v14_leg_fallback_and_include
REVIEW_NO_MY_REVIEW=1 v15_anchor_leak_warning
REVIEW_NO_MY_REVIEW=1 v16_timeout_and_blind_chat_leg
REVIEW_NO_MY_REVIEW=1 v17_explore_agent_legs
REVIEW_NO_MY_REVIEW=1 v18_engine_identity_single_source
REVIEW_NO_MY_REVIEW=1 v19_degradation_travels_with_conclusion
REVIEW_NO_MY_REVIEW=1 v19_chat_leg_declares_its_blindness
REVIEW_NO_MY_REVIEW=1 v20_max_turns_does_not_discard_work
REVIEW_NO_MY_REVIEW=1 v21_agent_leg_body_is_single_source
REVIEW_NO_MY_REVIEW=1 v22_head_moved_during_review
REVIEW_NO_MY_REVIEW=1 v22_anchor_leak_sees_committed_track
REVIEW_NO_MY_REVIEW=1 v22_roster_file
v23_my_review_gate_on_every_review_path
v24_no_env_backdoor_and_coverage_report
v25_legs_run_in_their_own_session
# 反锚定闸默认拦一切 review 派发 ⇒ 不带这个前缀,V26 里每一次派发都会被拦,
# 红的绿的全是空的(2026-08-18 第一版就是这样,红了 16 条没有一条是真问的)。
REVIEW_NO_MY_REVIEW=1 v26_glm_on_opencode_go
REVIEW_NO_MY_REVIEW=1 v27_knockon_of_the_backend_switch
REVIEW_NO_MY_REVIEW=1 v28_glm_on_opencode_base
REVIEW_NO_MY_REVIEW=1 v33_submimo_review_leg_is_read_only
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
