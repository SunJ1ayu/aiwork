#!/usr/bin/env bash
# 留下的评审命令的离线判据。
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78
unset DEEPSEEK_INCLUDE
export CURSOR_MODEL=composer-2.5
_MIMO_FLOOR="$(mktemp -d)"
cat > "$_MIMO_FLOOR/mimo" <<'MIMOFLOOR'
#!/usr/bin/env bash
echo "判据里调到了真的 mimo 底座:$*" >&2
exit 97
MIMOFLOOR
chmod +x "$_MIMO_FLOOR/mimo"
export PATH="$_MIMO_FLOOR:$PATH"
# 写死路径会让判据仍去测主仓的文件 = 改了也永远红(2026-08-01 派活前发现)。
# 可用 TEST_REVIEW_BIN 覆盖。
BIN="${TEST_REVIEW_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"

# Fake credentials are generated at runtime, never stored as literal values.
FIXTURE_CHAT_KEY="$(printf '\170')"
FIXTURE_DS_KEY="$(printf '%s%s' d k)"
FIXTURE_DS_AUTH_KEY="$(printf '%s-%s' "$FIXTURE_DS_KEY" file)"
FIXTURE_DS_ENV_KEY="$(printf '%s-%s' "$FIXTURE_DS_KEY" env)"
FIXTURE_ANTHROPIC_KEY="$(printf '%s-%s-%s' real anthropic key)"

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ # check "desc" COND_RC   (0 => pass)
  if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi
}

# 判卷工具自己不许碰留下的评审命令所用的本机凭证和运行期 home。
OWNER_CRED_DIR="/root/.kimi-code/credentials"
OWNER_KIMI_HOME="$("$BIN/aiwork-config" data-path kimi-review-home)"
OWNER_MIMO_CFG="$("$BIN/aiwork-config" data-path mimo-review-home)/mimocode/mimocode.json"
_fp1() {   # 单个路径的指纹;**先判 -L**:符号链接要当链接看,不能被 -f/-d 吞掉
  local p="$1" n; n="$(basename "$p")"
  if   [[ -L "$p" ]]; then printf '%s=link->%s;' "$n" "$(readlink "$p" 2>/dev/null)"
  elif [[ -f "$p" ]]; then printf '%s=%s:%s:%s;' "$n" "$(stat -c %i "$p" 2>/dev/null)" \
                                  "$(stat -c %y "$p" 2>/dev/null)" \
                                  "$(sha256sum "$p" 2>/dev/null | cut -c1-12)"
  elif [[ -d "$p" ]]; then printf '%s=目录;' "$n"
  else                     printf '%s=absent;' "$n"; fi
}
_owner_env_fp() {
  local out="" f
  for f in "$OWNER_CRED_DIR"/*;      do [[ -e "$f" ]] && out+="cred/$(_fp1 "$f")"; done
  for f in "$OWNER_KIMI_HOME"/hooks/*; do [[ -e "$f" ]] && out+="hook/$(_fp1 "$f")"; done
  out+="link/$(_fp1 "$OWNER_KIMI_HOME/credentials")"
  out+="cfg/$(_fp1 "$OWNER_KIMI_HOME/config.toml")"
  out+="mimo/$(_fp1 "$OWNER_MIMO_CFG")"
  printf '%s' "$out"
}
OWNER_ENV_BEFORE="$(_owner_env_fp)"
fixture_git_repo() { # path
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" rev-parse --verify HEAD >/dev/null 2>&1 && return 0
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t
  git -C "$repo" config user.name t
  printf 'fixture\n' > "$repo/.fixture"
  git -C "$repo" add .fixture
  git -C "$repo" commit -qm fixture
}

v9_claude_shell_base() {
  echo "[V9] claude 壳底座(subdeepseek-agent):env 注入、只读工具、裁决 gate"
  local d b rc; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"
  mkdir -p "$d/repo"   # 被评审的仓 = 子目录;观测文件留在 $d 下 = 仓外
  fixture_git_repo "$d/repo"
  # 2026-08-18 **这一组从 GLM 腿挪到 DeepSeek 腿**:GLM 的底座换成了 opencode CLI
  # (track opencode-agent-base),它已经不走 claude 壳,再拿它测 claude 壳就是
  # 拿错车验错路 —— 而且会去调真 opencode 干等 900 秒。
  # 这一组问的是**claude 壳这条底座本身**(env 注入、工具白名单、裁决 gate),
  # 它对 deepseek 仍然完全有效,断言一条不删、一条不弱。GLM 那条底座由 V28 问。
  # 瘦 shim,躯干在 subagent(V21);bin/ 成套部署,两个都要 cp。
  cp "$BIN/subdeepseek-agent" "$BIN/_review-home-guard.sh" "$BIN/_review-workspace.sh" "$BIN/aiwork-config" "$BIN/_aiwork_config.py" "$BIN/_review_result.py" "$BIN/subagent" "$b/"
  cp "$BIN/ro-repo-exec" "$b/"   # 成套部署:wrapper 靠它把腿放进只读仓(V35/V36)
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
print(json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": text}))
PYEOF
  chmod +x "$b/claude"
  printf '# review this\n' > "$d/t.md"
  agentget() { python3 -c "import json,sys;o=json.load(open(sys.argv[1]));v=o['env'].get(sys.argv[2]);print('' if v is None else v)" "$1" "$2"; }
  argvhas() { python3 -c "import json,sys;a=json.load(open(sys.argv[1]))['argv'];sys.exit(0 if sys.argv[2] in ' '.join(a) else 1)" "$1" "$2"; }

  # env-key path: token, base url, model mapping, API_KEY scrubbed
  env PATH="$b:$PATH" CAPTURE="$d/a1.json" ANTHROPIC_API_KEY="$FIXTURE_ANTHROPIC_KEY" \
    DEEPSEEK_API_KEY="$FIXTURE_DS_ENV_KEY" DEEPSEEK_MODEL=ds-test-model \
    bash "$b/subdeepseek-agent" review "$d/t.md" "$d/a1.log" "$d/repo" >/dev/null 2>&1; rc=$?
  check "agent review (env key) exits 0" $([[ $rc -eq 0 ]]; echo $?)
  # 2026-08-18 后端换成 OpenCode Go 之后,**认证 header 也换了**:
  # deepseek 的 Anthropic 面走 Authorization: Bearer(= ANTHROPIC_AUTH_TOKEN)。
  # 这和 GLM 那格(x-api-key)**故意相反** —— 差异只准活在供应商表里,
  # 两格各自被钉死,谁被顺手统一了这里就红。
  # 所以这里断言的是**表驱动的 header 风格**,不是"key 有没有传进去":
  # 传对了 key、传错了 header,腿一样是死的,而日志上看起来只是"模型没回话"。
  [[ "$(agentget "$d/a1.json" ANTHROPIC_AUTH_TOKEN)" == "$FIXTURE_DS_ENV_KEY" ]]
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
  [[ "$(agentget "$d/a1.json" ANTHROPIC_DEFAULT_OPUS_MODEL)" == "ds-test-model" && "$(agentget "$d/a1.json" ANTHROPIC_DEFAULT_HAIKU_MODEL)" == "ds-test-model" ]]
  check "agent: all model slots honor DEEPSEEK_MODEL" $?
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
  # review 现在跑在**可写副本**里,原仓另由 ro-repo-exec 物理保护。Bash 的职责
  # 不再只是读 git:腿要能跑 tests/lint/build,这些命令产生的缓存也只落进副本。
  # 所以这里要求裸 Bash 能力；Write/Edit/Task 仍由下面的独立断言关闭。
  if python3 - "$d/a1.json" 2>/dev/null <<'PY_LOCAL_BASH'
import json,sys
a=json.load(open(sys.argv[1]))['argv']
i=a.index('--allowedTools'); rest=a[i+1:]
j=[k for k,x in enumerate(rest) if x.startswith('--')]
seg=rest[:j[0]] if j else rest
sys.exit(0 if 'Bash' in seg else 1)
PY_LOCAL_BASH
  then
    ok  "agent: 裸 Bash 可用(腿在副本里可跑 tests/lint/build)"
  else
    bad "agent: 裸 Bash 可用(腿在副本里可跑 tests/lint/build)"
  fi

  # **能力清单要说实话**(四审 subdeepseek 指出:V28⑮ 只钉了 opencode 腿,claude 壳这条漏了)。
  # 这条钉的不是方向,是"清单和实际能力必须一致" —— 两个方向都出过事:
  # 08-18 宣称了没有的工具(腿当场顶回来、白花几轮)、08-19 瞒着有的(腿不会去用)。
  python3 -c "
import json,sys
sys.exit(0 if 'tests' in json.load(open(sys.argv[1])).get('stdin','') and 'Bash' in json.load(open(sys.argv[1])).get('stdin','') else 1)" \
    "$d/a1.json" 2>/dev/null
  check "agent: 提示词如实写明可用 Bash 做本地诊断/测试" $?

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
  printf '{"key":"%s"}' "$FIXTURE_DS_AUTH_KEY" > "$d/auth.json"
  env -u DEEPSEEK_API_KEY PATH="$b:$PATH" CAPTURE="$d/a2.json" DEEPSEEK_AUTH_FILE="$d/auth.json" \
    bash "$b/subdeepseek-agent" review "$d/t.md" "$d/a2.log" "$d/repo" >/dev/null 2>&1; rc=$?
  check "agent auth-file fallback exits 0" $([[ $rc -eq 0 ]]; echo $?)
  # 2026-08-18:env-key 那条路已经换成 x-api-key,**这条 auth-file 路当时被漏掉了**
  # —— 是判据自己在这儿红了一次才发现的。所以这里不止把变量名跟着改,还补上
  # "Bearer 那格必须是空的":只改名字的话,两条路各走各的 header 又会看不出来。
  [[ "$(agentget "$d/a2.json" ANTHROPIC_AUTH_TOKEN)" == "$FIXTURE_DS_AUTH_KEY" ]]
  check "agent: key loaded from auth file" $?
  [[ -z "$(agentget "$d/a2.json" ANTHROPIC_API_KEY)" ]]
  check "agent: auth-file 这条路的 header 风格也必须对(两条路各走各的会看不出来)" $?

  # verdict gate: no Conclusion -> non-zero, log still written
  env PATH="$b:$PATH" CAPTURE="$d/a3.json" DEEPSEEK_API_KEY="$FIXTURE_DS_KEY" \
    STUB_REVIEW_OUT="looks fine to me" \
    bash "$b/subdeepseek-agent" review "$d/t.md" "$d/a3.log" "$d/repo" >/dev/null 2>&1; rc=$?
  check "agent: verdict-less output exits non-zero" $([[ $rc -ne 0 ]]; echo $?)
  [[ -f "$d/a3.log" ]]; check "agent: log still written on verdict miss" $?

  # verdict gate: Chinese 「结论：PASS」 (full-width colon) accepted — the drift
  # that drifted twice (Track B + client-tools)
  env PATH="$b:$PATH" CAPTURE="$d/a3b.json" DEEPSEEK_API_KEY="$FIXTURE_DS_KEY" \
    STUB_REVIEW_OUT=$'review body\n结论：PASS' \
    bash "$b/subdeepseek-agent" review "$d/t.md" "$d/a3b.log" "$d/repo" >/dev/null 2>&1; rc=$?
  check "agent: Chinese 结论+full-width colon accepted" $([[ $rc -eq 0 ]]; echo $?)

  # fix refused; -h ok
  env PATH="$b:$PATH" CAPTURE="$d/a4.json" DEEPSEEK_API_KEY="$FIXTURE_DS_KEY" \
    bash "$b/subdeepseek-agent" fix "$d/t.md" "$d/a4.log" "$d/repo" >/dev/null 2>&1; rc=$?
  check "agent: fix refused" $([[ $rc -ne 0 ]]; echo $?)
  bash "$b/subdeepseek-agent" -h >/dev/null 2>&1; check "agent: -h exits 0" $?

  rm -rf "$d"
}

v13_subkimi_leg() {
  echo "[V13] subkimi: guard default-deny, wrapper contract, panel 4th-leg selection"
  local d b rc; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"
  mkdir -p "$d/repo"   # 被评审的仓 = 子目录;观测文件留在 $d 下 = 仓外
  fixture_git_repo "$d/repo"

  # --- the SHIPPED guard, invoked directly: default-deny semantics
  local tool_root; tool_root="$(cd "$BIN/.." && pwd -P)"
  local guard="$tool_root/kimi-review-home/hooks/guard.mjs"

  # 2026-08-19:**守卫本体必须在版本控制里**。发现时它整个目录被 gitignore 挡着,
  # 从来没进过库 ⇒ 这道判卷防线被改了**不留痕**,闸③(亲读 diff)也照不到它。
  # 判据能测出它"行为对不对",测不出"它昨天是不是别的样子" —— 那要靠 git。
  # (凭证/oauth/sessions 仍然一律不入库,gitignore 里是精确放行两个 hooks 文件。)
  git -C "$tool_root" ls-files --error-unmatch \
      kimi-review-home/hooks/guard.mjs >/dev/null 2>&1
  check "guard: 守卫本体在版本控制里(判卷防线改了必须留痕)" $?
  ( cd "$BIN/.." && git ls-files --error-unmatch kimi-review-home/config.toml ) >/dev/null 2>&1
  check "种子 config.toml 在版本控制里(hook 挂不挂写在它里面)" $?
  if [[ -f "$guard" ]]; then
    echo '{"tool_name":"Write","tool_input":{}}' | node "$guard" >/dev/null 2>&1
    check "guard: Write denied (rc=2)" $([[ $? -eq 2 ]]; echo $?)
    echo '{"tool_name":"Read","tool_input":{}}' | node "$guard" >/dev/null 2>&1
    check "guard: Read allowed (rc=0)" $?

    # 腿现在在独立可写副本里执行，源仓由外层 ro-repo-exec 承重。Bash 不再
    # 假装是一张能兜住 git 参数面的安全白名单；测试、lint、build、解释器和
    # 它们的缓存都允许落在副本。工具级 Write/Edit/Agent 仍是独立禁口。
    local kcmd
    for kcmd in "bash tests/probe.sh" \
                "python3 -m pytest -q" \
                "git diff HEAD"; do
      echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$kcmd\"}}" \
        | node "$guard" >/dev/null 2>&1
      check "guard: 副本内本地 Bash 放行 —— $kcmd" $?
    done
    echo '{"tool_name":"SomeFutureTool","tool_input":{}}' | node "$guard" >/dev/null 2>&1
    check "guard: unknown tool denied (default-deny)" $([[ $? -eq 2 ]]; echo $?)
    echo 'garbage not json' | node "$guard" >/dev/null 2>&1
    check "guard: garbage stdin fails CLOSED (rc=2)" $([[ $? -eq 2 ]]; echo $?)
  else
    bad "shipped guard missing: $guard"
  fi

  # --- subkimi wrapper against a stub kimi + fixture review home
  cp "$BIN/subkimi" "$BIN/_review-home-guard.sh" "$BIN/_review-workspace.sh" "$BIN/aiwork-config" "$BIN/_aiwork_config.py" "$BIN/_review_result.py" "$b/"
  cp "$BIN/ro-repo-exec" "$b/"   # 成套部署:wrapper 靠它把腿放进只读仓(V35/V36)
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
text = os.environ.get("STUB_REVIEW_OUT", "stub review\nConclusion: PASS")
print(json.dumps({"role": "assistant", "content": text}))
PYEOF
  chmod +x "$b/kimi"
  printf '# review this\n' > "$d/t.md"
  kimiget() { python3 -c "import json,sys;o=json.load(open(sys.argv[1]));v=o['env'].get(sys.argv[2]);print('' if v is None else v)" "$1" "$2"; }

  env PATH="$b:$PATH" CAPTURE="$d/k1.json" KIMI_REVIEW_HOME="$rh" \
    bash "$b/subkimi" review "$d/t.md" "$d/k1.log" "$d/repo" >/dev/null 2>&1; rc=$?
  check "subkimi: review exits 0" $([[ $rc -eq 0 ]]; echo $?)
  [[ "$(kimiget "$d/k1.json" KIMI_CODE_HOME)" == "$rh" ]]
  check "subkimi: KIMI_CODE_HOME points at review home" $?
  python3 -c "
import json,sys
a=json.load(open(sys.argv[1]))['argv']
sys.exit(0 if any('tests' in str(x) and 'Bash' in str(x) for x in a) else 1)" "$d/k1.json" 2>/dev/null
  check "subkimi: 提示词如实写明 Bash 可跑本地诊断/测试" $?
  [[ "$(kimiget "$d/k1.json" KIMI_CODE_NO_AUTO_UPDATE)" == "1" ]]
  check "subkimi: auto-update disabled" $?
  grep -q 'Conclusion: PASS' "$d/k1.log"; check "subkimi: verdict recorded in log" $?

  # 改配置后观察 CLI 实际 argv；不用当前版本号作断言。
  local km
  for km in kimi-code/fixture-next kimi-code/fixture-later; do
    test_model_set kimi "$km"
    env -u KIMI_MODEL PATH="$b:$PATH" CAPTURE="$d/model.json" KIMI_REVIEW_HOME="$rh" \
      bash "$b/subkimi" review "$d/t.md" "$d/model.log" "$d/repo" >/dev/null 2>&1
    python3 - "$d/model.json" "$km" <<'PY'
import json,sys
a=json.load(open(sys.argv[1]))['argv']
assert a[a.index('-m')+1] == sys.argv[2]
PY
    check "subkimi: 只改模型文件就改变实际 CLI 调用 ($km)" $?
  done
  env KIMI_MODEL=kimi-code/fixture-override PATH="$b:$PATH" CAPTURE="$d/override.json" KIMI_REVIEW_HOME="$rh" \
    bash "$b/subkimi" review "$d/t.md" "$d/override.log" "$d/repo" >/dev/null 2>&1
  python3 - "$d/override.json" <<'PY'
import json,sys
a=json.load(open(sys.argv[1]))['argv']
assert a[a.index('-m')+1] == 'kimi-code/fixture-override'
PY
  check "subkimi: KIMI_MODEL 单次覆盖默认配置" $?
  for km in '' 'kimi-code/one kimi-code/two'; do
    test_model_set kimi "$km"
    env -u KIMI_MODEL PATH="$b:$PATH" CAPTURE="$d/invalid.json" KIMI_REVIEW_HOME="$rh" \
      bash "$b/subkimi" review "$d/t.md" "$d/invalid.log" "$d/repo" >/dev/null 2>&1; rc=$?
    [[ $rc -ne 0 && ! -e "$d/invalid.json" ]]
    check "subkimi: 空或非法模型配置不派发" $?
  done
  test_model_set kimi kimi-code/kimi-for-coding

  env PATH="$b:$PATH" CAPTURE="$d/k2.json" KIMI_REVIEW_HOME="$rh" STUB_REVIEW_OUT="no verdict here" \
    bash "$b/subkimi" review "$d/t.md" "$d/k2.log" "$d/repo" >/dev/null 2>&1; rc=$?
  check "subkimi: verdict-less output rejected" $([[ $rc -ne 0 ]]; echo $?)

  # Chinese-style verdict (结论 + full-width colon) must pass the gate — the
  # drift that drifted twice (Track B + client-tools).
  env PATH="$b:$PATH" CAPTURE="$d/k2b.json" KIMI_REVIEW_HOME="$rh" \
    STUB_REVIEW_OUT=$'review body\n结论：PASS' \
    bash "$b/subkimi" review "$d/t.md" "$d/k2b.log" "$d/repo" >/dev/null 2>&1; rc=$?
  check "subkimi: Chinese 结论+full-width colon accepted" $([[ $rc -eq 0 ]]; echo $?)

  env PATH="$b:$PATH" CAPTURE="$d/k3.json" KIMI_REVIEW_HOME="$rh" \
    bash "$b/subkimi" fix "$d/t.md" "$d/k3.log" "$d/repo" >/dev/null 2>&1; rc=$?
  check "subkimi: fix refused" $([[ $rc -ne 0 ]]; echo $?)

  # broken (fail-open) guard must refuse to dispatch BEFORE invoking kimi
  local rh2="$d/review-home2"; mkdir -p "$rh2/hooks" "$rh2/credentials"
  printf 'default_model = "x"\n' > "$rh2/config.toml"
  printf 'process.exit(0)\n' > "$rh2/hooks/guard.mjs"
  echo '{}' > "$rh2/credentials/kimi-code.json"
  rm -f "$d/k4.json"
  env PATH="$b:$PATH" CAPTURE="$d/k4.json" KIMI_REVIEW_HOME="$rh2" \
    bash "$b/subkimi" review "$d/t.md" "$d/k4.log" "$d/repo" >/dev/null 2>&1; rc=$?
  check "subkimi: fail-open guard refused (preflight)" $([[ $rc -ne 0 ]]; echo $?)
  if [[ -e "$d/k4.json" ]]; then bad "subkimi: kimi never invoked on bad guard"; else ok "subkimi: kimi never invoked on bad guard"; fi

  bash "$b/subkimi" -h >/dev/null 2>&1; check "subkimi: -h exits 0" $?
  grep -Fq 'p + ".tmp." + str(os.getpid())' "$BIN/subkimi"
  check "subkimi: seed config rewrite uses a per-process atomic temp" $?
  rm -rf "$d"
}

v20_max_turns_does_not_discard_work() {
  echo "[V20] 底座腿撞上 max-turns 不许把工作全丢掉"
  local d fake; d="$(mktemp -d)"; fake="$d/fakebin"; mkdir -p "$fake"
  mkdir -p "$d/repo"   # 被评审的仓 = 子目录;观测文件留在 $d 下 = 仓外
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
  fixture_git_repo "$d/repo"
  printf '{"key":"%s"}\n' "$FIXTURE_CHAT_KEY" > "$d/auth.json"
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

v21_agent_leg_body_is_single_source() {
  echo "[V21] DeepSeek 评审命令的躯干只有一份"
  [[ -f "$BIN/subagent" ]]; check "V21: 共享躯干 subagent 存在" $?
  grep -q "subagent" "$BIN/subdeepseek-agent" 2>/dev/null; check "V21: subdeepseek-agent 走共享躯干" $?
  [[ "$(grep -cvE '^\s*(#.*)?$' "$BIN/subdeepseek-agent" 2>/dev/null)" -le 6 ]]
  check "V21: subdeepseek-agent 是瘦 shim(有效行 ≤ 6)" $?
  grep -q "deepseek" "$BIN/subagent" 2>/dev/null; check "V21: 供应商表含 deepseek" $?

  local d; d="$(mktemp -d)"; local ab="$d/bin"; mkdir -p "$ab" "$d/repo"
  fixture_git_repo "$d/repo"
  cp "$BIN/subdeepseek-agent" "$BIN/_review-home-guard.sh" "$BIN/_review-workspace.sh" "$BIN/aiwork-config" "$BIN/_aiwork_config.py" "$BIN/_review_result.py" "$BIN/subagent" "$ab/"
  cp "$BIN/ro-repo-exec" "$ab/"
  cat > "$ab/claude" <<'CAPEOF'
#!/usr/bin/env python3
import sys, os, json
open(os.environ["CAPTURE"], "w").write(json.dumps({"argv": sys.argv[1:]}))
print(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "Conclusion: PASS"}]}}))
print(json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": "Conclusion: PASS"}))
CAPEOF
  chmod +x "$ab/claude"
  printf '# t\n' > "$d/t.md"
  capturing_turns() { python3 -c "import json,sys;a=json.load(open(sys.argv[1]))['argv'];print(a[a.index('--max-turns')+1])" "$1"; }
  env -u DEEPSEEK_MAX_TURNS PATH="$ab:$PATH" CAPTURE="$d/s.json" DEEPSEEK_API_KEY="$FIXTURE_DS_KEY" \
    bash "$ab/subdeepseek-agent" review "$d/t.md" "$d/s.log" "$d/repo" >/dev/null 2>&1
  [[ "$(capturing_turns "$d/s.json")" -ge 200 ]]
  check "V21: deepseek 默认轮次上限 ≥200" $?
  rm -rf "$d"
}

v24_coverage_report() {
  echo "[V24] 孤儿套件要红"
  local d rc out; d="$(mktemp -d)"
  out="$(bash "$BIN/rust-check-review-tooling" --coverage-only 2>&1)"; rc=$?
  check "V24: 没有孤儿套件时 coverage-only 不因为手列名单变红" $([[ $rc -eq 0 ]]; echo $?)
  if grep -Eq "规矩4|_tooling-paths|未覆盖" <<<"$out"; then
    bad "V24: 总跑不再报手列名单漏网"
  else ok "V24: 总跑不再报手列名单漏网"; fi

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

v33_submimo_review_leg_is_read_only() {
  echo "[V33] submimo 写口关掉、bash 留着,fix 不受连累"
  local d b rc; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"
  mkdir -p "$d/repo"   # 被评审的仓 = 子目录;观测文件留在 $d 下 = 仓外
  cp "$BIN/submimo" "$BIN/_review-home-guard.sh" "$BIN/_review-workspace.sh" "$BIN/aiwork-config" "$BIN/_aiwork_config.py" "$BIN/_review_result.py" "$b/"
  cp "$BIN/ro-repo-exec" "$b/"   # 成套部署:wrapper 靠它把腿放进只读仓(V35/V36)
  printf '# t\n' > "$d/t.md"
  local repo="$d/repo"; mkdir -p "$repo"
  ( cd "$repo" && git init -q . && printf 'x\n' > a.txt && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm base ) >/dev/null 2>&1

  # stub mimo:只落 argv(查它到底用哪个档),不碰真底座
  # stub 要落**自己的环境**,不只是 argv —— `env HOME=x cmd` 的赋值进的是子进程环境,
  # **永远不进 cmd 的 argv**。第一版我查 argv 里有没有 `HOME=`,于是那条断言
  # 即使实现真换了 HOME 也照样绿(结构上永远绿,是评审抓到的)。
  cat > "$b/mimo" <<'EOF'
#!/usr/bin/env bash
python3 -c "
import os,sys,json
json.dump({'argv':sys.argv[1:],
           'HOME':os.environ.get('HOME'),
           'XDG_CONFIG_HOME':os.environ.get('XDG_CONFIG_HOME')},
          open(os.environ['CAPTURE'],'w'))" "$@"
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

  # 内置 plan 档是否名不副实,问的是这台机器装的 mimo,不在仓库判据里。
  # 下面只钉仓库自己写出的档:不用 plan、写口关掉、bash 留着。

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
  # `--no-oracle` 是必须的:submimo fix 在既没 --oracle 也没 --no-oracle 时**拒绝运行**
  # (它自己的闸,防的是"忘了给判据就裸跑一发")。第一版我没给,腿压根没起来,
  # 于是这条对照断言红了 —— 红得对,但红的原因不是我要测的那个。
  env PATH="$b:$PATH" CAPTURE="$d/c_fix" MIMO_REVIEW_HOME="$mhome" \
    bash "$b/submimo" fix "$d/t.md" "$d/f.log" "$repo" --no-oracle >/dev/null 2>&1
  if [[ -f "$d/c_fix" ]]; then
    local ag3; ag3="$(agent_of "$d/c_fix")"
    [[ "$ag3" == "build" ]]
    check "V33: 对照 —— fix 仍用 build 档(执行腿要写代码,不许被顺手锁死)" $?
  else
    bad "V33: 对照 —— fix 仍用 build 档(执行腿要写代码,不许被顺手锁死)"
  fi

  # 上面 explore 会按旧语义把 Bash 收回只读 git；O4 问的是 review 能力。
  # 再跑一次 review，让下面检查 review 最终写下的配置。
  env PATH="$b:$PATH" CAPTURE="$d/c_review_config" MIMO_REVIEW_HOME="$mhome" \
    bash "$b/submimo" review "$d/t.md" "$d/r-config.log" "$repo" >/dev/null 2>&1

  # ── ④ 锁写在仓库生成的配置里。mimo 装好的那一版是否照这份 JSON 解析,
  #    是本机体检;这里只读我们写下的文件,缺文件就红,不许跳过。
  local mcfg="$mhome/mimocode/mimocode.json"
  if [[ -f "$mcfg" ]]; then
    ok "V33: 只读 agent 的配置生成在隔离目录(XDG_CONFIG_HOME,没污染调用者的 mimocode)"
    local v33json
    v33json="$(python3 - "$mcfg" <<'PYV33'
import json, sys
c = json.load(open(sys.argv[1]))
ag = c.get("agent", {}).get("aiwork-review", {})
tools = ag.get("tools") or {}
perm = ag.get("permission") or {}
closed = [k for k in ("write", "edit", "patch", "task", "webfetch", "skill") if tools.get(k) is not False]
print("CLOSED" if not closed else "OPEN:" + ",".join(closed))
print("BASH_ON" if tools.get("bash") is True else "BASH_OFF")
print("ALLOW" if perm.get("bash") == "allow" else "NOT_ALLOW")
print("KEEP" if all(tools.get(k) is True for k in ("read", "glob", "grep")) else "MISSING")
PYV33
)"
    grep -qx "CLOSED" <<< "$v33json"
    check "V33: 配置里写口全关 —— write/edit/patch/task/webfetch/skill" $?
    grep -qx "BASH_ON" <<< "$v33json"
    check "V33: 配置里 bash 留着(关掉它就得自己喂 diff,那条路已被推翻)" $?
    grep -qx "ALLOW" <<< "$v33json"
    check "V33: 配置里 Bash permission 是整项 allow" $?
    grep -qx "KEEP" <<< "$v33json"
    check "V33: 配置里 read/glob/grep 还在" $?
  else
    bad "V33: 只读 agent 的配置生成在隔离目录(XDG_CONFIG_HOME,没污染调用者的 mimocode)"
    bad "V33: 配置里写口全关 —— write/edit/patch/task/webfetch/skill"
    bad "V33: 配置里 bash 留着(关掉它就得自己喂 diff,那条路已被推翻)"
    bad "V33: 配置里 Bash permission 是整项 allow"
    bad "V33: 配置里 read/glob/grep 还在"
  fi

  # ── ④b 隔离必须用 XDG_CONFIG_HOME,**不许用 HOME**。
  #    实测:mimo 的 data 路径(含 auth.json 凭证)只跟 HOME 走 —— 换 HOME 会把凭证
  #    一起换掉,腿当场没法认证,而失败形态是"模型没回话",查起来像模型问题。
  #    这条钉的是"隔离别把腿弄死"。
  if [[ -f "$d/c_review" ]]; then
    # 查腿进程**实际拿到的** HOME —— 必须还是调用者的 HOME。
    HOME_NOW="$HOME" python3 -c "
import json,os,sys
o=json.load(open(sys.argv[1]))
sys.exit(0 if o.get('HOME')==os.environ['HOME_NOW'] else 1)" "$d/c_review" 2>/dev/null
    check "V33: 隔离不许换 HOME(换了会把 mimo 的凭证一起带走 ⇒ 腿只会'没回话')" $?
    # 正面:配置隔离必须真的发生(否则上一条用"什么都不隔离"也能绿)
    # 断言腿拿到的 XDG_CONFIG_HOME 就是我们指定的隔离目录。
    # (第一版这里漏了 `import os` ⇒ 红在 NameError 上 —— "红在 TypeError 上
    #  等于没红检过",本仓记过的形状,我又犯一次。)
    WANT="$mhome" python3 -c "
import json,os,sys
o=json.load(open(sys.argv[1]))
sys.exit(0 if o.get('XDG_CONFIG_HOME')==os.environ['WANT'] else 1)" "$d/c_review" 2>/dev/null
    check "V33: 配置确实被隔离到我们指定的 XDG_CONFIG_HOME(不是什么都没做)" $?
  else
    bad "V33: 隔离不许换 HOME(换了会把 mimo 的凭证一起带走 ⇒ 腿只会'没回话')"
    bad "V33: 配置确实被隔离到 XDG_CONFIG_HOME(不是什么都没做)"
  fi

  # ── ⑤ 配置每次重写(它就是锁本身,不许留隔夜残留)
  if [[ -f "$mhome/mimocode/mimocode.json" ]]; then
    # 用一个**实现绝不会写**的标记键来验"被重写了"。
    # 第一版我拿 `"bash": true` 当标记 —— 而转向后实现本来就写 bash:true,
    # 这条断言于是永远红。标记必须选实现不可能产出的东西。
    printf '{"__stale_marker__":true,"agent":{"aiwork-review":{"tools":{"bash":true}}}}' > "$mhome/mimocode/mimocode.json"
    rm -f "$d/c_rewrite"
    env PATH="$b:$PATH" CAPTURE="$d/c_rewrite" MIMO_REVIEW_HOME="$mhome" \
      bash "$b/submimo" review "$d/t.md" "$d/r2.log" "$repo" >/dev/null 2>&1
    grep -q '__stale_marker__' "$mhome/mimocode/mimocode.json"
    check "V33: 配置每次重写(被人改过也会被覆盖回去)" $([[ $? -ne 0 ]]; echo $?)
  else
    bad "V33: 配置每次重写(被人改松了也会被覆盖回去)"
  fi

  # ── ⑥ 配置必须**原子落盘**(2026-08-19,第三轮四审 subkimi 挂掉前留下的发现)。
  #    洞:`json.dump(cfg, open(cfgpath,"w"))` 是 truncate 之后逐步写。两个 agent
  #    并发跑 review 时共享同一份配置(`MIMO_REVIEW_HOME` 没设时都落在
  #    `$HOME/.cache/aiwork/mimo-review-home`)⇒ 另一边可能读到半截 JSON。
  #    **失败形态我没验过**:mimo 解析不了这份配置会不会回退到内置 `plan` 档
  #    (写口全开、本单整单就是在推翻它)—— 不去猜它,把窗口关掉即可。
  #
  #    下面三条里,前两条是**看得见的**(权限、无残留),第三条是**字面断言**:
  #    原子性没法从结果观察(窗口只在写的那一瞬间),只能查写法。
  #    配置内容由上面读落盘 JSON 的检查钉住。这一条查的是写入机制,机制不在产物里。
  #    它挡的是"未来改回直写",证明不了原子性本身。
  if [[ -f "$mhome/mimocode/mimocode.json" ]]; then
    [[ "$(stat -c '%a' "$mhome/mimocode/mimocode.json")" == "600" ]]
    check "V33: 配置文件权限 600(凭证级别的东西,别人读不到)" $?
    [[ -z "$(find "$mhome/mimocode" -name '*.tmp*' -o -name '.*tmp*' 2>/dev/null)" ]]
    check "V33: 原子写不许留下 tmp 残留(留了说明 replace 那步没走到)" $?
  else
    bad "V33: 配置文件权限 600(凭证级别的东西,别人读不到)"
    bad "V33: 原子写不许留下 tmp 残留(留了说明 replace 那步没走到)"
  fi
  # 字面断言:必须 tmp + os.replace,不许把 open(...,"w") 直接喂给 json.dump。
  python3 - "$BIN/submimo" <<'PYATOM'
import re, sys
src = open(sys.argv[1]).read()
direct = re.search(r'json\.dump\([^)]*open\(', src)
atomic = 'os.replace(' in src
per_process = 'os.getpid()' in src
sys.exit(0 if (atomic and per_process and not direct) else 1)
PYATOM
  check "V33: 配置走每进程唯一 tmp + os.replace 原子落盘" $?

  rm -rf "$d"
}

# ---------------------------------------------------------------- V35
# 评审腿在**只读的仓**里跑(track repo-write-audit,2026-08-19)。
#
# 为什么是"只读挂载"而不是"事后审计":08-18 我发现腿能写被评审的仓
# (`git diff --output=<path>` 挡不住),第一反应是把 bash 整个关掉 —— 四审推翻了,
# 关掉的代价是腿静默起不来。第二版方案是 strace 写审计(检测),而**真探针**证明
# 更简单的一条路成立:把仓 ro bind 进腿自己的 mount namespace,
# **腿的读能力一条不少**(status/diff/log/show/rev-parse/blame 全 rc=0,
# 与可写状态逐条对照无差异),而写口物理消失。收据在
# 只读挂载探针记录在 git 历史里。
#
# ⚠️ 这道防线**最危险的失败形态是安静的**:挂载没生效时腿照跑、结论照出、
# 一切看起来完全正常。所以下面每一条正面断言前都先钉**前置锚**(证明确实进了

v35_legs_run_in_readonly_repo() {
  echo "[V35] 评审腿在只读的仓里跑(写口物理消失,读能力一条不少)"
  local d; d="$(mktemp -d)"
  mkdir -p "$d/repo"   # 被评审的仓 = 子目录;观测文件留在 $d 下 = 仓外
  local repo="$d/repo"; mkdir -p "$repo/logs" "$repo/bin" "$repo/tests"
  ( cd "$repo" && git init -q . && printf 'x\n' > a.txt && printf 'y\n' > tests/oracle.sh \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm base ) >/dev/null 2>&1
  # 制造脏工作树:腿要评的正是未提交的改动(真跑时 panel 全是 dirty=yes)
  printf 'dirty\n' >> "$repo/a.txt"

  # **依赖缺失一律拒跑,不静默跳过**(先例:V23 的 realpath)。
  # 而且这里有一个更阴的坑,第一版就踩了:`ro-repo-exec` 不存在时,
  # "写仓失败"这类断言会**全部假绿** —— 命令根本没跑,当然写不进去。
  # 11 条里有 6 条这样绿了(2026-08-19 红检当场照出来,我自己看 PASS 数发现的)。
  # ⇒ 前置不满足就把**每一条**都判红,一条都不许留在"看起来绿"的状态。
  if ! command -v unshare >/dev/null 2>&1 || [[ ! -x "$BIN/ro-repo-exec" ]]; then
    local why="机器上没有 unshare"
    [[ -x "$BIN/ro-repo-exec" ]] || why="$BIN/ro-repo-exec 不存在或不可执行"
    local t
    for t in "锚 —— ro-repo-exec 确实把命令送进了只读仓" \
             "腿写不了仓内新文件" "\`git diff --output=\` 写不进去" \
             "腿改不了 tests/" "只读下六条读命令全通" "对照组 —— 可写状态下失败数相同" \
             "--rw 开的口子真能写" "开了 logs/ 之后仓的其余部分仍然只读" \
             "unshare 挂不上 ⇒ 非零退出" "挂不上时命令根本没跑" "拒跑时说清是什么挂了"; do
      bad "V35: $t(前置不满足:$why)"
    done
    rm -rf "$d"; return
  fi

  # ── 前置锚:确认 ro-repo-exec 真的把我们送进了只读 namespace。
  #    这条不成立的话,下面"写失败"全是假绿(在可写树上写失败才是怪事)。
  local anchor
  anchor="$("$BIN/ro-repo-exec" "$repo" -- bash -c 'touch "$1/anchor" 2>&1 || echo BLOCKED' _ "$repo" 2>/dev/null)"
  [[ "$anchor" == *BLOCKED* ]]
  check "V35: 锚 —— ro-repo-exec 确实把命令送进了只读仓(不然下面全是测空气)" $?

  # ── ① 写口:两条都必须失败,其中第二条正是 08-18 判定"白名单不成立"的那个绕过
  # ⚠️ 每条写口断言都要**先证明命令真的跑过了**(往仓外落一个标记,仓外是可写的)。
  # 只断言"写失败"的话,工具不存在/exec 失败也能让它绿 —— 那是**没跑**冒充**被挡住**。
  rm -f "$d/ran1"
  "$BIN/ro-repo-exec" "$repo" -- bash -c 'echo ran > "$2"; touch "$1/PWNED"' _ "$repo" "$d/ran1" >/dev/null 2>&1
  [[ -s "$d/ran1" && ! -e "$repo/PWNED" ]]
  check "V35: 腿写不了仓内新文件(且命令确实跑过、仓里真的没多出东西)" $?

  rm -f "$d/ran3"
  "$BIN/ro-repo-exec" "$repo" -- bash -c 'echo ran > "$2"; git -C "$1" diff --output="$1/PWNED2" HEAD' \
    _ "$repo" "$d/ran3" >/dev/null 2>&1
  [[ -s "$d/ran3" && ! -e "$repo/PWNED2" ]]
  check "V35: \`git diff --output=\` 写不进去(08-18 那条已知绕过被物理挡死)" $?

  rm -f "$d/ran2"
  "$BIN/ro-repo-exec" "$repo" -- bash -c 'echo ran > "$2"; echo x >> "$1/tests/oracle.sh"' _ "$repo" "$d/ran2" >/dev/null 2>&1
  [[ -s "$d/ran2" ]] && ! grep -q '^x$' "$repo/tests/oracle.sh"
  check "V35: 腿改不了 tests/(命令跑过了,但判据一个字没变 —— 这条是整单的理由)" $?

  # ── ② 读能力一条都不许少 + **对照组**(同样命令在没挂载时也全 0 ⇒ 差异只来自只读)
  local ro_fail=0 rw_fail=0 c
  for c in "git -C $repo status --short" "git -C $repo diff --stat" \
           "git -C $repo log --oneline -1" "git -C $repo show --stat HEAD" \
           "git -C $repo rev-parse HEAD" "git -C $repo blame -L1,1 a.txt"; do
    "$BIN/ro-repo-exec" "$repo" -- bash -c "$c" >/dev/null 2>&1 || ro_fail=$((ro_fail+1))
    bash -c "$c" >/dev/null 2>&1 || rw_fail=$((rw_fail+1))
  done
  [[ $ro_fail -eq 0 ]]
  check "V35: 只读下六条读命令全通(读能力没被削)" $?
  [[ $ro_fail -eq $rw_fail ]]
  check "V35: 对照组 —— 可写状态下失败数相同(差异只许来自只读:ro=$ro_fail rw=$rw_fail)" $?

  # ── ③ 写口白名单:--rw 指定的目录必须真能写(腿日志就在仓内 logs/,
  #    写不了 = 这道防线把腿弄死了,而"腿静默起不来"正是 08-18 那次的病)
  "$BIN/ro-repo-exec" --rw "$repo/logs" "$repo" -- bash -c 'echo hi > "$1/logs/leg.log"' _ "$repo" >/dev/null 2>&1
  [[ $? -eq 0 && -s "$repo/logs/leg.log" ]]
  check "V35: --rw 开的口子真能写(腿日志在仓内 logs/)" $?
  "$BIN/ro-repo-exec" --rw "$repo/logs" "$repo" -- bash -c 'touch "$1/STILL_RO"' _ "$repo" >/dev/null 2>&1
  [[ $? -ne 0 && ! -e "$repo/STILL_RO" ]]
  check "V35: 开了 logs/ 之后仓的其余部分**仍然只读**(不是整仓开闸)" $?

  # ── ③b 参数写错必须**拒跑**(2026-08-19 真探针撞出来的:我把 `--rw` 写到了仓根
  #    后面,工具没吭声,反而把 `--rw` 当成命令 exec 了 —— "把误用当命令跑"
  #    同样是静默降级,而且它伪装成"跑起来了")。
  local badout badrc
  badout="$("$BIN/ro-repo-exec" "$repo" --rw "$repo/logs" -- bash -c 'echo hi' 2>&1)"; badrc=$?
  [[ $badrc -ne 0 ]]
  check "V36/V35: 选项写在仓根后面 ⇒ 拒跑(不许把 --rw 当命令执行)" $?
  # 必须是 **ro-repo-exec 自己**说的话。第一版只 grep `--`,而它把 `--rw` 当命令
  # exec 时 bash 报的 `exec: --: invalid option` 里正好有 `--` ⇒ 那条断言把
  # "执行失败"读成了"主动拒绝"。**报错来自谁**,和报没报一样重要。
  grep -q 'ro-repo-exec:' <<<"$badout"
  check "V36/V35: 拒跑是 ro-repo-exec 自己说的(不是 bash exec 失败的副产品)" $?
  ! grep -qi 'invalid option' <<<"$badout"
  check "V36/V35: 不许把 --rw 当命令 exec(静默降级伪装成"跑起来了")" $?

  # ── ③c `--rw` 指到**仓根**就等于整仓开闸 ⇒ **拒跑**。
  #    这是我自审时发现的洞,不是腿指出来的:真跑时日志在 `<仓>/logs/`(没问题),
  #    但谁把 LOG_PREFIX 设成仓根,防线就**静默消失**,而外面一切看起来正常 ——
  #    "一切正常正是它失败的样子",这一单的头号风险形态。
  #    ⚠️ **2026-08-19 第二轮:合约从"警告"改成"拒跑"**(另一条评审路径)。
  #    原来选警告的理由是"判据里几十条老夹具的日志落在仓根,拒绝会误伤一大片";
  #    第二轮把三条 wrapper 的写口全删了(V37 写口为零)⇒ 生产调用方归零,理由过期。
  #    这一条留在这里只做**冒烟**(还认得出这个形状、话还说得清楚);
  #    拒跑合约本身由 V40③ 端到端盯(含"命令根本没跑"),红检也在那边。
  #    留着而不是删掉,是因为删了之后"仓根"这个词在 V35 这一节就再没人提 ——
  #    而这一节正是别人读只读锁合约时第一个打开的地方。
  local rootrw rootrw_rc
  rootrw="$("$BIN/ro-repo-exec" --rw "$repo" "$repo" -- bash -c 'echo hi' 2>&1 >/dev/null)"; rootrw_rc=$?
  [[ $rootrw_rc -ne 0 ]] && grep -qiE '仓根|整仓|whole repo' <<<"$rootrw"
  check "V35: --rw 指到仓根 ⇒ 拒跑并说清楚(等于整仓开闸,不许悄悄发生)" $?

  # ── ④ fail-closed:挂不上就**拒跑**,绝不许静默降级成"可写地跑"。
  #    08-18 刚栽过:两条评审腿把 fail-closed 判反,`env '=key'` rc=0 静默放过
  #    ⇒ 腿活着但永远 401。安静的失败比响亮的失败贵得多。
  local fb="$d/fakebin"; mkdir -p "$fb"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$fb/unshare"; chmod +x "$fb/unshare"
  local out rc
  out="$(PATH="$fb:$PATH" "$BIN/ro-repo-exec" "$repo" -- bash -c 'touch "$1/LEAKED"' _ "$repo" 2>&1)"; rc=$?
  [[ $rc -ne 0 ]]
  check "V35: unshare 挂不上 ⇒ **非零退出**(不许静默降级)" $?
  [[ ! -e "$repo/LEAKED" ]]
  check "V35: 挂不上时命令**根本没跑**(降级跑=白读了只读两个字)" $?
  grep -qiE 'unshare|namespace|只读|拒绝' <<<"$out"
  check "V35: 拒跑时说清是什么挂了(不说清 = 下次没人查得动)" $?

  rm -rf "$d"
}

# ---------------------------------------------------------------- V36
# 工具做好了**没接上**就是白做 —— 本仓记过这笔账("给防线加构件却没把构件放进防线")。
# V35 测 `ro-repo-exec` 自身；V36 端到端测留下的 review 路径都把模型放进独立
# **可写副本**，同时仍把 SOURCE_REPO 挂成只读。两边必须在同一次假模型调用里
# 各写一次，避免“模型没启动”或“只测了一边”的假绿。
v36_wrappers_actually_use_readonly_repo() {
  echo "[V36] review 路径在可写副本运行，原仓保持物理只读"
  local d b; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"
  mkdir -p "$d/repo"   # 被评审的仓 = 子目录;观测文件留在 $d 下 = 仓外
  local repo="$d/repo"; mkdir -p "$repo/logs"
  ( cd "$repo" && git init -q . && printf 'x\n' > a.txt && printf '/logs/\n' > .gitignore && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm base ) >/dev/null 2>&1
  printf '# t\n' > "$d/t.md"

  if ! command -v unshare >/dev/null 2>&1 || [[ ! -x "$BIN/ro-repo-exec" ]]; then
    local t
    for t in "subdeepseek-agent 副本可写/原仓只读" \
             "submimo review 副本可写/原仓只读" \
             "subkimi 副本可写/原仓只读" "submimo fix 仍然直接写原仓" \
             "腿在只读下仍然正常出结论(防线没把腿弄死)"; do
      bad "V36: $t(前置不满足:缺 unshare 或 ro-repo-exec)"
    done
    rm -rf "$d"; return
  fi

  cp "$BIN/subdeepseek-agent" "$BIN/_review-home-guard.sh" "$BIN/_review-workspace.sh" "$BIN/aiwork-config" "$BIN/_aiwork_config.py" "$BIN/_review_result.py" "$BIN/subagent" "$BIN/submimo" "$BIN/subkimi" "$b/"
  cp "$BIN/ro-repo-exec" "$b/"   # 成套部署:wrapper 靠它把腿放进只读仓(V35/V36)
  cp "$BIN/_review-workspace.sh" "$b/" 2>/dev/null || true

  # 假模型从 cwd/--dir 找到真正派给它的 repo:往那里写必须成功；再往显式传入的
  # SOURCE_REPO 写必须失败。结果落仓外，副本退出即删也仍有可核对的记录。
  _mk_pwn_stub() {  # $1 = stub 路径
    cat > "$1" <<'PWN'
#!/usr/bin/env bash
target="$PWD"; prev=""
for arg in "$@"; do
  [[ "$prev" == "--dir" ]] && target="$arg"
  prev="$arg"
done
work=BLOCKED; source=BLOCKED
touch "$target/PWNED_IN_WORKSPACE" 2>/dev/null && work=WROTE
touch "$PWN_REPO/PWNED_IN_SOURCE" 2>/dev/null && source=WROTE
printf 'repo=%s\ncwd=%s\nwork=%s\nsource=%s\n' "$target" "$PWD" "$work" "$source" > "$PWN_OUT"
printf 'model=%s\n' "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}" >> "$PWN_OUT"
printf 'mimocfg=%s\n' "${MIMOCODE_CONFIG_CONTENT:-}" >> "$PWN_OUT"
# 每条腿只认自己命令行的最后一条消息。claude 是 result 事件，kimi 是 role=assistant，
# mimo review 是 --format json 的最后一条 assistant 文本。
case "$(basename "$0")" in
  claude)
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"stub\nConclusion: PASS"}]}}'
    echo '{"type":"result","subtype":"success","is_error":false,"result":"stub\nConclusion: PASS"}'
    ;;
  kimi)
    echo '{"role":"assistant","content":"stub\nConclusion: PASS"}'
    ;;
  *)
    if [[ " $* " == *" json "* ]]; then
      echo '{"type":"message.updated","properties":{"info":{"id":"m1","role":"assistant"}}}'
      echo '{"type":"message.part.updated","properties":{"part":{"id":"p1","messageID":"m1","type":"text","text":"stub\nConclusion: PASS"}}}'
    else
      echo "Conclusion: PASS"
    fi
    ;;
esac
PWN
    chmod +x "$1"
  }
  _mk_pwn_stub "$b/claude"; _mk_pwn_stub "$b/mimo"; _mk_pwn_stub "$b/kimi"

  test_model_set deepseek deepseek-fixture-next
  [[ "$(bash "$b/subdeepseek-agent" --help 2>&1)" == *"DeepSeek default model: deepseek-fixture-next"* ]]
  check "V36: agent help follows the shared default" $?
  local rc
  # ── ① claude 壳(subdeepseek-agent)
  rm -f "$d/o1" "$repo/PWNED_IN_SOURCE" "$repo/PWNED_IN_WORKSPACE"
  env PATH="$b:$PATH" PWN_REPO="$repo" PWN_OUT="$d/o1" CAPTURE="$d/c1.json" \
    DEEPSEEK_API_KEY="$FIXTURE_DS_KEY" DEEPSEEK_MODEL= AIWORK_REVIEW_FACTS_PATH="$d/deepseek.facts.json" \
    AIWORK_REVIEW_RESULT_BIN="$BIN/_review_result.py" \
    bash "$b/subdeepseek-agent" review "$d/t.md" "$repo/logs/l1.log" "$repo" >/dev/null 2>&1; rc=$?
  grep -q '^work=WROTE$' "$d/o1" 2>/dev/null \
    && grep -q '^source=BLOCKED$' "$d/o1" 2>/dev/null \
    && [[ "$(sed -n 's/^repo=//p' "$d/o1")" != "$repo" ]] \
    && [[ ! -e "$repo/PWNED_IN_SOURCE" ]]; local r1=$?
  # ⚠️ rc 先存变量再取文案:`check "…$(cat …)" $?` 里那个命令替换会**在 $? 求值之前**
  # 跑掉,把退出码覆盖成 cat 的 0 ⇒ 断言永远绿。2026-08-19 第一版就是这样,
  # 五条假绿(其中一条文案自己写着 WROTE 却 PASS)。本仓"管道吃 rc"记过四次,
  # 这是同一族的第五次,换了个壳:**命令替换吃 rc**。
  local seen1; seen1="$(cat "$d/o1" 2>/dev/null || echo 没跑)"
  check "V36: subdeepseek-agent 副本可写、原仓只读(假模型双向试写:$seen1)" $r1
  [[ $rc -eq 0 ]]
  check "V36: 腿在只读下仍然正常出结论(防线没把腿弄死 —— 08-18 就是死在这)" $?
  python3 - "$d/deepseek.facts.json" "$d/o1" <<'PY'
import json,sys
p=json.load(open(sys.argv[1]))
assert p['model']['requested'] == p['model']['invoked'] == 'deepseek-fixture-next'
assert 'model=deepseek-fixture-next' in open(sys.argv[2]).read().splitlines()
assert p['source'] and p['view']['mode'] == 'full_snapshot'
PY
  check "V36: subdeepseek-agent 交出实际模型与完整 snapshot facts" $?

  # ── ② submimo review
  rm -f "$d/o2" "$repo/PWNED_IN_SOURCE" "$repo/PWNED_IN_WORKSPACE"
  # ⚠️ MIMO_REVIEW_HOME 必须指进夹具:①b/③ 都设了,唯独这条没设 ⇒ submimo 会去写
  #    **业主真实的** ~/.cache/aiwork/mimo-review-home(判据每跑一次重写一次它的配置)。
  #    同族第三处,2026-08-25 panel 抓到、V45 当场红过。
  env PATH="$b:$PATH" PWN_REPO="$repo" PWN_OUT="$d/o2" \
    MIMO_REVIEW_HOME="$d/mimo-home-v36" AIWORK_REVIEW_FACTS_PATH="$d/mimo.facts.json" \
    AIWORK_REVIEW_RESULT_BIN="$BIN/_review_result.py" \
    bash "$b/submimo" review "$d/t.md" "$repo/logs/l2.log" "$repo" >/dev/null 2>&1
  grep -q '^work=WROTE$' "$d/o2" 2>/dev/null \
    && grep -q '^source=BLOCKED$' "$d/o2" 2>/dev/null \
    && [[ "$(sed -n 's/^cwd=//p' "$d/o2")" == "$(sed -n 's/^repo=//p' "$d/o2")" ]] \
    && [[ "$(sed -n 's/^repo=//p' "$d/o2")" != "$repo" ]] \
    && [[ ! -e "$repo/PWNED_IN_SOURCE" ]]; local r2=$?
  local seen2; seen2="$(cat "$d/o2" 2>/dev/null || echo 没跑)"
  check "V36: submimo review 副本可写、原仓只读(双向试写:$seen2)" $r2
  python3 - "$d/mimo.facts.json" "$("$BIN/aiwork-config" model mimo)" <<'PY'
import json,sys
p=json.load(open(sys.argv[1]))
want=sys.argv[2]
assert want.startswith('xiaomi/mimo-'), want
assert p['model']['requested'] == p['model']['invoked'] == want
assert p['source']['git_object_format'] in ('sha1','sha256')
assert p['view'] == {'delivery_state':'complete','mode':'full_snapshot'}
PY
  check "V36: submimo 把 models.env 的 mimo 行模型与完整 snapshot 事实交给唯一 terminal producer" $?
  # MiMo CLI 自带模型表会落后于新模型(09-22:mimo-v2.6-pro 发布当天 CLI 报 Model not found)。
  # submimo 必须在运行时把 models.env 的 mimo 行模型登记给 CLI,且登记**只含 provider 段**
  # —— 带 agent/permission 段就可能盖掉评审档那把锁。
  python3 - "$d/o2" "$("$BIN/aiwork-config" model mimo)" <<'PY'
import json,sys
cfg=[l[len('mimocfg='):] for l in open(sys.argv[1]).read().splitlines() if l.startswith('mimocfg=')]
assert len(cfg)==1 and cfg[0], cfg
c=json.loads(cfg[0])
provider,mid=sys.argv[2].split('/',1)
assert set(c)=={'provider'}, sorted(c)
m=c['provider'][provider]['models'][mid]
assert m['tool_call'] is True and m['limit']['context']>0 and m['limit']['output']>0, m
PY
  check "V36: submimo 把 models.env 的 mimo 行模型登记给 MiMo CLI(只含 provider 段)" $?

  # ── ③ subkimi
  # subkimi 要一份 review home 才肯派发(config.toml + 守卫 + 凭证),照 V13 的建法。
  # 第一版没建 ⇒ 它在调 kimi **之前**就退了,断言红在"没跑"上 —— 那不是防线的功劳,
  # 是夹具的洞。**红也要红在该红的地方**,本仓为这条记过账。
  local rh="$d/review-home"; mkdir -p "$rh/hooks" "$rh/credentials"
  printf 'default_model = "x"\n' > "$rh/config.toml"
  printf 'process.exit(2)\n' > "$rh/hooks/guard.mjs"
  echo '{}' > "$rh/credentials/kimi-code.json"
  rm -f "$d/o3" "$repo/PWNED_IN_SOURCE" "$repo/PWNED_IN_WORKSPACE"
  env PATH="$b:$PATH" PWN_REPO="$repo" PWN_OUT="$d/o3" KIMI_REVIEW_HOME="$rh" \
    AIWORK_REVIEW_FACTS_PATH="$d/kimi.facts.json" AIWORK_REVIEW_RESULT_BIN="$BIN/_review_result.py" \
    bash "$b/subkimi" review "$d/t.md" "$repo/logs/l3.log" "$repo" >/dev/null 2>&1
  grep -q '^work=WROTE$' "$d/o3" 2>/dev/null \
    && grep -q '^source=BLOCKED$' "$d/o3" 2>/dev/null \
    && [[ "$(sed -n 's/^repo=//p' "$d/o3")" != "$repo" ]] \
    && [[ ! -e "$repo/PWNED_IN_SOURCE" ]]; local r3=$?
  local seen3; seen3="$(cat "$d/o3" 2>/dev/null || echo 没跑)"
  check "V36: subkimi 副本可写、原仓只读(双向试写:$seen3)" $r3
  python3 - "$d/kimi.facts.json" "$("$BIN/aiwork-config" model kimi)" <<'PY'
import json,sys
p=json.load(open(sys.argv[1]))
assert p['model']['requested'] == p['model']['invoked'] == sys.argv[2]
assert p['source'] and p['view'] == {'delivery_state':'complete','mode':'full_snapshot'}
assert p['process_state'] == 'exited' and p['verdict'] == 'PASS'
PY
  check "V36: subkimi 交出实际模型、完整 snapshot 与裁决 facts" $?

  # ── ④ **对照组:fix 一个字都不许被连累**。submimo fix 是执行腿,写代码是它的本职;
  #    "加一道防线顺手拆掉另一道"是本仓记过的账(V33 里有同款对照)。
  rm -f "$d/o4" "$repo/PWNED_IN_SOURCE" "$repo/PWNED_IN_WORKSPACE"
  env PATH="$b:$PATH" PWN_REPO="$repo" PWN_OUT="$d/o4" \
    MIMO_REVIEW_HOME="$d/mimo-home-v36d" \
    bash "$b/submimo" fix --no-oracle "$d/t.md" "$repo/logs/l4.log" "$repo" >/dev/null 2>&1
  grep -q '^work=WROTE$' "$d/o4" 2>/dev/null \
    && grep -q '^source=WROTE$' "$d/o4" 2>/dev/null \
    && [[ "$(sed -n 's/^repo=//p' "$d/o4")" == "$repo" ]]; local r4=$?
  local seen4; seen4="$(cat "$d/o4" 2>/dev/null || echo 没跑)"
  check "V36: submimo fix 仍直接写原仓:$seen4" $r4
  rm -f "$repo/PWNED_IN_SOURCE" "$repo/PWNED_IN_WORKSPACE"

  rm -rf "$d"
}

# ---------------------------------------------------------------- V37
# **写口本身不该存在。**(track repo-write-audit,2026-08-19 第二轮,四审逼出来的)
#
# 第一版给每条 wrapper 开了一个写口:`--rw "$(dirname "$LOG_FILE")"`,理由写在
# design 2c 第 1 条:「腿日志就在仓内 logs/,写不了 = 防线把腿弄死了」。
# **那个前提是错的。** 三条 wrapper 的腿日志都是父 shell 重定向写的
# (`>> "$LOG_FILE"` / `| tee -a`),fd 在**父 namespace** 就打开了,
# 挂载管不着已经打开的 fd。探针证明:不开任何写口,日志照样写得出;
# 而腿自己在 namespace 里新开仓内文件仍然 `Read-only file system`。
#
# 这个多余的写口不是白拿的,它带来了两条真问题(都是四审抓的,我复现过):
#  ① `dirname` 相对**调用方 cwd** 解析 ⇒ 从仓根用裸文件名调用(`… out.log <仓>`)
#     时 `--rw` 解析成**仓根** = 整仓开闸,而只有两行 stderr 警告。
#     腿照跑、结论照出 —— 正是本单立项要防的那种**安静失效**。
#  ② `RO_EXEC` 在 wrapper 自己 `mkdir -p` 日志目录**之前**构建 ⇒ 日志目录还不存在时
#     解析成 `/nonexistent`,ro-repo-exec 拒跑。这是本单引入的**行为回归**
#     (以前 wrapper 会把日志目录建出来)。`subagent` 的顺序是对的、另两条不是 ——
#     又一次"两份拷贝、只更新一份"。
#
# ⇒ 修法是**把写口去掉**,不是把它修好:写口为零 ⇒ 上面两条一起消失,防线还更严。
v37_wrappers_open_no_write_hole() {
  echo "[V37] wrapper 不给腿开任何写口(腿日志靠父进程的 fd,不靠写口)"
  local d b; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"
  mkdir -p "$d/repo"   # 被评审的仓 = 子目录;观测文件留在 $d 下 = 仓外
  local repo="$d/repo"; mkdir -p "$repo/logs"
  ( cd "$repo" && git init -q . && printf 'x\n' > a.txt && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm base ) >/dev/null 2>&1
  printf '# t\n' > "$d/t.md"

  if ! command -v unshare >/dev/null 2>&1 || [[ ! -x "$BIN/ro-repo-exec" ]]; then
    local t
    for t in "腿日志不靠写口也写得出" "wrapper 一个 --rw 都不传" \
             "相对日志路径 + cwd=仓根 ⇒ 防线仍然生效" \
             "日志目录不存在 ⇒ wrapper 自己建好并跑起来"; do
      bad "V37: $t(前置不满足:缺 unshare 或 ro-repo-exec)"
    done
    rm -rf "$d"; return
  fi

  cp "$BIN/subdeepseek-agent" "$BIN/_review-home-guard.sh" "$BIN/_review-workspace.sh" "$BIN/aiwork-config" "$BIN/_aiwork_config.py" "$BIN/_review_result.py" "$BIN/subagent" "$BIN/submimo" "$BIN/subkimi" "$b/"
  cp "$BIN/ro-repo-exec" "$b/"
  _mk_pwn_stub2() {
    cat > "$1" <<'PWN2'
#!/usr/bin/env bash
if touch "$PWN_REPO/PWNED_BY_LEG" 2>/dev/null; then echo WROTE > "$PWN_OUT"; else echo BLOCKED > "$PWN_OUT"; fi
case "$(basename "$0")" in
  claude)
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"stub\nConclusion: PASS"}]}}'
    echo '{"type":"result","subtype":"success","is_error":false,"result":"stub\nConclusion: PASS"}'
    ;;
  kimi)
    echo '{"role":"assistant","content":"stub\nConclusion: PASS"}'
    ;;
  *)
    if [[ " $* " == *" json "* ]]; then
      echo '{"type":"message.updated","properties":{"info":{"id":"m1","role":"assistant"}}}'
      echo '{"type":"message.part.updated","properties":{"part":{"id":"p1","messageID":"m1","type":"text","text":"stub\nConclusion: PASS"}}}'
    else
      echo "Conclusion: PASS"
    fi
    ;;
esac
PWN2
    chmod +x "$1"
  }
  _mk_pwn_stub2 "$b/claude"; _mk_pwn_stub2 "$b/mimo"; _mk_pwn_stub2 "$b/kimi"

  # ── ① 腿日志确实写得出来(这条立住了,写口才可以去掉)
  rm -f "$repo/logs/l.log" "$d/o"
  env PATH="$b:$PATH" PWN_REPO="$repo" PWN_OUT="$d/o" CAPTURE="$d/c.json" \
    DEEPSEEK_API_KEY="$FIXTURE_DS_KEY" \
    bash "$b/subdeepseek-agent" review "$d/t.md" "$repo/logs/l.log" "$repo" >/dev/null 2>&1
  [[ -s "$repo/logs/l.log" ]]
  check "V37: 腿日志不靠写口也写得出(fd 在父 namespace 打开)" $?

  # ── ② 结构:wrapper 一个 --rw 都不许传给 ro-repo-exec。
  #    用一个记账版 ro-repo-exec 顶替真的,把它收到的 argv 抄下来。
  cat > "$b/ro-repo-exec" <<RECORD
#!/usr/bin/env bash
printf '%s\\n' "\$@" > "\${RO_ARGV_OUT:-/dev/null}"
# 照常放行,后面还要跑真腿。**指到 \$BIN 那份**,不写死路径 ——
# 写死的话变异测试(TEST_REVIEW_BIN 指到变异 bin)会从这里溜回未变异的实现。
exec "$BIN/ro-repo-exec" "\$@"
RECORD
  chmod +x "$b/ro-repo-exec"
  rm -f "$d/argv.txt"
  env PATH="$b:$PATH" PWN_REPO="$repo" PWN_OUT="$d/o" CAPTURE="$d/c.json" \
    RO_ARGV_OUT="$d/argv.txt" DEEPSEEK_API_KEY="$FIXTURE_DS_KEY" \
    bash "$b/subdeepseek-agent" review "$d/t.md" "$repo/logs/l2.log" "$repo" >/dev/null 2>&1
  ! grep -q -- '^--rw$' "$d/argv.txt" 2>/dev/null
  check "V37: wrapper 一个 --rw 都不传(写口为零 —— 多余的写口正是那两条 bug 的来源)" $?
  cp "$BIN/ro-repo-exec" "$b/"   # 换回真的

  # ── ③ 相对日志路径 + cwd=仓根:第一版在这里整仓开闸,而且**一声不响**
  rm -f "$d/o3" "$repo/PWNED_BY_LEG"
  ( cd "$repo" && env PATH="$b:$PATH" PWN_REPO="$repo" PWN_OUT="$d/o3" \
      MIMO_REVIEW_HOME="$d/mimo-home-v37a" \
      bash "$b/submimo" review "$d/t.md" "relative.log" "$repo" ) >/dev/null 2>&1
  [[ "$(cat "$d/o3" 2>/dev/null)" == "BLOCKED" && ! -e "$repo/PWNED_BY_LEG" ]]
  check "V37: 相对日志路径 + cwd=仓根 ⇒ 防线**仍然生效**(第一版这里整仓开闸,还不报错)" $?

  # ── ④ 日志目录还不存在:wrapper 应当自己建好并跑起来,不是拒跑(回归)
  rm -rf "$repo/fresh" ; rm -f "$d/o4" "$repo/PWNED_BY_LEG"
  env PATH="$b:$PATH" PWN_REPO="$repo" PWN_OUT="$d/o4" \
    MIMO_REVIEW_HOME="$d/mimo-home-v37b" \
    bash "$b/submimo" review "$d/t.md" "$repo/fresh/leg.log" "$repo" >/dev/null 2>&1
  [[ -e "$repo/fresh/leg.log" && "$(cat "$d/o4" 2>/dev/null)" == "BLOCKED" ]]
  check "V37: 日志目录不存在 ⇒ wrapper 建好它并正常跑(别把防线做成回归)" $?

  rm -rf "$d"
}

# ---------------------------------------------------------------- V38
# **腿的运行期状态目录不许住在被评审的仓里。**(2026-08-19 第二轮)
#
# 这条是真跑出来的,判据里的 stub 撞不出:V36 的夹具把 review home
# 建在仓外的临时目录(`KIMI_REVIEW_HOME="$rh"`),而真跑时 subkimi 的默认 home 是
# `/root/aiwork/kimi-review-home` —— **仓内**。只读一上,kimi 的 logger 当场:
#     [logger] write failed: EROFS
#     error: failed to run prompt: storage write failed: unrecognized I/O error
# 腿起不来。而「防线不许把腿弄死」正是这一单 design 写死的硬要求(08-18 就死在这),
# V36 那条"腿在只读下仍然正常出结论"却照样绿 —— **夹具覆盖了出问题的那个默认值**,
# 夹具盖住默认值时,这条会结构上永远绿。
#
# 两条断言,第二条才是要害:错误信息里那句 "unrecognized I/O error" 谁看了都
# 想不到是只读挂载,而 roster 记的 `FAIL(rc=1)` 和"额度耗尽"长得一模一样。
# ⇒ 落在仓内就**拒跑并说清楚**,别让底座自己去撞一个没人看得懂的错。
v38_leg_runtime_home_outside_repo() {
  echo "[V38] 腿的运行期状态目录不许在被评审的仓里"
  local d; d="$(mktemp -d)"
  mkdir -p "$d/repo"   # 被评审的仓 = 子目录;观测文件留在 $d 下 = 仓外
  local repo="$d/repo"; mkdir -p "$repo/logs"
  ( cd "$repo" && git init -q . && printf 'x\n' > a.txt && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm base ) >/dev/null 2>&1
  printf '# t\n' > "$d/t.md"

  # ── ① 默认 home 必须在仓外。**查工件不查自述**:让 wrapper 自己把它解析出来打印,
  #    而不是我在这儿 grep 一个字符串。
  # ⚠️ 必须隔离 HOME:不设 KIMI_REVIEW_HOME 是**故意的**(要问出默认值),但那会让
  #    subkimi 的种子同步(bin/subkimi:100-110)去写**业主真实的**运行期 home ——
  #    判据每跑一次就把他的 config/hooks 重置一次。假 HOME 一样问得出"默认 home
  #    在不在仓外",而那正是本条要查的东西。2026-08-25 panel 抓到,V45 红过。
  local home_default fh38="$d/fh38"; mkdir -p "$fh38"
  home_default="$(env -u AIWORK_DATA_DIR HOME="$fh38" REVIEW_PRINT_HOME=1 bash "$BIN/subkimi" review "$d/t.md" "$repo/logs/x.log" "$repo" 2>/dev/null | tail -1)"
  [[ -n "$home_default" ]] && case "$home_default" in "$repo"/*|"$repo") false ;; *) true ;; esac
  check "V38: subkimi 的默认运行期 home 在**被评审的仓外面**(解析出来的是:${home_default:-没打印})" $?
  # ⚠️ **"问一句默认值"不许有副作用**。假 HOME 让运行期 home 不存在 ⇒ subkimi 的
  #    首次同步(bin/subkimi:102-104)会把**整份活种子**(101MB,含那条指向业主真凭证
  #    的符号链接)抄进夹具 —— 我 2026-08-25 修写穿 bug 时亲手引入的:V40① 那边刚
  #    改成不产生通道,这里又把通道造了一遍。三条腿里两条独立指出,探针实测 100MB。
  #    这两条断言盯的就是它,别只盯体积:**链接本身才是那个通道**。
  local fh38_sz; fh38_sz="$(du -sm "$fh38" 2>/dev/null | cut -f1)"
  [[ ! -e "$fh38/.local/share/aiwork/kimi-review-home/credentials" ]]
  check "V38: 问一句默认 home **不许**把种子里的 credentials 链接抄进夹具(通道)" $?
  [[ "${fh38_sz:-999}" -lt 5 ]]
  check "V38: 问一句默认 home **不许**整份抄种子(夹具实测 ${fh38_sz:-?}MB,要 <5MB)" $?

  # ── ② home 落在仓内 ⇒ 响亮拒跑,而且说得出原因(不许让底座去撞 EROFS)
  #
  # ⚠️ 这个 home 必须建**完整**(config + 守卫 + 凭证,照 V13/V36 的建法)。
  # 不建全的话 subkimi 会因为 "review home config missing" 提前退出、rc 照样非零 ——
  # 断言就**绿在不该绿的地方**了(第一版正是如此:home 目录压根不存在,
  # 我却把它读成"防线拒跑了")。这是 V36 ③ 那条注释("红要红在该红的地方")的镜像,
  # 同一个文件里几十行外就写着,我还是踩了。
  _mk_kimi_home() {   # $1 = home 路径
    mkdir -p "$1/hooks" "$1/credentials"
    printf 'default_model = "x"\n' > "$1/config.toml"
    printf 'process.exit(2)\n' > "$1/hooks/guard.mjs"
    echo '{}' > "$1/credentials/kimi-code.json"
  }
  # ⚠️ **"非零退出"问不出任何东西**:这个 stub 环境里 subkimi 因为守卫 / 凭证 /
  # 底座缺失,本来就会非零退出 —— 第一版那条 `[[ $rc -ne 0 ]]` 是**结构上永远绿**的
  # (它 PASS 的原因跟 home 在哪毫无关系)。这正是我在任务书里请四审去查的那类假闸,
  # 我自己又写了一条。⇒ 改成问**拒跑发生在什么时候**:必须在调起底座**之前**。
  # 用一个会留痕的假 kimi 来问,和 V35 ④「挂不上时命令根本没跑」同款。
  #
  local fb="$d/fakebin"; mkdir -p "$fb"
  printf '#!/usr/bin/env bash\necho ran > "$KIMI_RAN_MARK"\necho "Conclusion: PASS"\n' > "$fb/kimi"
  chmod +x "$fb/kimi"

  local out
  _mk_kimi_home "$repo/kimi-home"
  rm -f "$d/kimi-ran"
  out="$(PATH="$fb:$PATH" KIMI_RAN_MARK="$d/kimi-ran" KIMI_REVIEW_HOME="$repo/kimi-home" \
         bash "$BIN/subkimi" review "$d/t.md" "$repo/logs/y.log" "$repo" 2>&1)"
  [[ ! -e "$d/kimi-ran" ]]
  check "V38: home 在被评审的仓内 ⇒ **底座根本没被调起**(拒在前面,不是让它去撞 EROFS)" $?
  grep -qE '仓内|被评审的仓|只读|read-only' <<<"$out"
  check "V38: 拒跑时说清了是 home 在仓内(底座那句 unrecognized I/O error 没人看得懂)" $?

  # ── ②b **对照组**:一模一样的 home 建在仓外 ⇒ 底座**必须**被调起。
  #    没有它,上面两条会被"subkimi 恰好因为别的原因退了"骗过去照样绿。
  local out2
  _mk_kimi_home "$d/outside-home"
  rm -f "$d/kimi-ran"
  out2="$(PATH="$fb:$PATH" KIMI_RAN_MARK="$d/kimi-ran" KIMI_REVIEW_HOME="$d/outside-home" \
          bash "$BIN/subkimi" review "$d/t.md" "$repo/logs/z.log" "$repo" 2>&1)"
  [[ -e "$d/kimi-ran" ]]
  check "V38: 对照组 —— home 在仓外时底座照常被调起(拒的是位置,不是别的)" $?
  ! grep -qE '仓内|被评审的仓' <<<"$out2"
  check "V38: 对照组 —— 仓外的 home 不许报「在仓内」" $?

  rm -rf "$d"
}

# ---------------------------------------------------------------- V39
# 只读挂载的两个**结构性盲区**(2026-08-19 四审抓的,我都复现过)。
#
# ① **linked worktree 的 git 元数据在挂载外面**。
#    worktree 里的 `.git` 只是个指针文件,真正的 refs/index/objects 住在主仓的
#    `.git/worktrees/<name>` 里 —— 只 bind 仓根**盖不到它**。实测:腿在只读的
#    worktree 里照样 `git commit --allow-empty` 和 `git tag` 成功,**主仓的 git
#    状态被改了**。被推翻的 strace 方案当初明确计划保护 `--git-common-dir`,
#    只读方案漏了(`proposal.md`)。aiwork 自己就有 worktree 基础设施 ⇒ 不是理论。
#
# ② **挂载"成功"了但没生效,没有任何东西会发现**(submimo 的结构盲区那条)。
#    现在只看 mount 的退出码:每条都 rc=0 就落标记、然后 exec。可 rc=0 不等于
#    仓真的只读了 —— 而这正是**最贵的失败形态**:腿照跑、结论照出、一切看起来正常。
#    本仓已有的做法是「每次都实测一次」(`tests/_no-egress.sh` 就是在 namespace 里
#    真的 connect 一次,而不是相信 unshare 有效)。这里照搬:挂完**真写一次**,
#    写得进去就拒跑。
v39_readonly_blind_spots() {
  echo "[V39] 只读挂载的两个盲区:worktree 的 git 目录 / 挂载没生效"
  local d; d="$(mktemp -d)"
  local repo="$d/repo"; mkdir -p "$repo"
  ( cd "$repo" && git init -q . && printf 'x\n' > a.txt && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm base ) >/dev/null 2>&1

  if ! command -v unshare >/dev/null 2>&1 || [[ ! -x "$BIN/ro-repo-exec" ]]; then
    local t
    for t in "worktree:工作树写不了" "worktree:git commit 写不进主仓" \
             "worktree:git tag 写不进主仓" "对照组:worktree 的读能力没被削" \
             "挂载没生效 ⇒ 拒跑" "挂载没生效时命令根本没跑" \
             "对照组:挂载真生效时照常跑"; do
      bad "V39: $t(前置不满足:缺 unshare 或 ro-repo-exec)"
    done
    rm -rf "$d"; return
  fi

  # ── ① linked worktree
  local wt="$d/wt"
  ( cd "$repo" && git worktree add -q "$wt" -b probe-wt ) >/dev/null 2>&1
  if [[ -d "$wt" ]]; then
    "$BIN/ro-repo-exec" "$wt" -- bash -c 'touch "$1/PWNED"' _ "$wt" >/dev/null 2>&1
    [[ ! -e "$wt/PWNED" ]]
    check "V39: worktree —— 工作树本身写不了" $?

    local before after
    before="$(git -C "$repo" rev-parse probe-wt 2>/dev/null)"
    "$BIN/ro-repo-exec" "$wt" -- bash -c \
      'cd "$1" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "腿写的"' \
      _ "$wt" >/dev/null 2>&1
    after="$(git -C "$repo" rev-parse probe-wt 2>/dev/null)"
    [[ "$before" == "$after" ]]
    check "V39: worktree —— git commit 改不动主仓的 git 状态(真 git 目录在仓外)" $?

    "$BIN/ro-repo-exec" "$wt" -- bash -c 'cd "$1" && git tag PWNED_TAG' _ "$wt" >/dev/null 2>&1
    ! git -C "$repo" tag | grep -qx PWNED_TAG
    check "V39: worktree —— git tag 也写不进去" $?

    # 对照组:读能力一条不能少(不然"挡住了"可能只是把 git 整个弄坏了)
    local ro_fail=0 c
    for c in "git -C $wt status --short" "git -C $wt log --oneline -1" "git -C $wt diff --stat"; do
      "$BIN/ro-repo-exec" "$wt" -- bash -c "$c" >/dev/null 2>&1 || ro_fail=$((ro_fail+1))
    done
    [[ $ro_fail -eq 0 ]]
    check "V39: worktree —— 对照组:三条读命令仍全通(挡的是写,不是把 git 弄坏)" $?
  else
    bad "V39: worktree —— 夹具没建出 worktree(前置不满足)"
  fi

  # ── ② 挂载"成功"但没生效:注入一个 rc=0 却什么都不做的假 mount
  local fb="$d/fakemount"; mkdir -p "$fb"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fb/mount"; chmod +x "$fb/mount"
  local out
  rm -f "$repo/LEAKED2"
  out="$(PATH="$fb:$PATH" "$BIN/ro-repo-exec" "$repo" -- bash -c 'touch "$1/LEAKED2"' _ "$repo" 2>&1)"
  [[ ! -e "$repo/LEAKED2" ]]
  check "V39: 挂载没生效(假 mount 全 rc=0)⇒ 命令**根本没跑**,仓没被写" $?
  grep -qiE '没有真的只读|自检|仍然可写|not read-only' <<<"$out"
  check "V39: 挂载没生效时说得出是自检发现的(不是含糊的 78)" $?

  # 对照组:真挂载时不许被这条自检误杀
  "$BIN/ro-repo-exec" "$repo" -- bash -c 'echo ok' >/dev/null 2>&1
  check "V39: 对照组 —— 挂载真生效时照常跑(自检不许误杀)" $?

  ( cd "$repo" && git worktree remove --force "$wt" ) >/dev/null 2>&1
  rm -rf "$d"
}


v41_oracle_never_executes_its_own_comments() {
  echo "[V41] 判据自己不许把注释交给 shell 执行(08-19 实证)"
  # 2026-08-19:V40③c 那条断言写成 `python3 -c "…"`,**双引号**里的中文注释带反引号,
  # 被 shell 当成命令替换真跑了一遍 —— 其中一句注释正好是
  # "`git diff --output=` 能写文件所以危险",于是判据自己把它执行了(空文件名被 git
  # 拒了才没写成)。判定逻辑当时没坏,所以三组对照全对、收据照印 PASS ——
  # **这种病不会让判据变红,它让判据在你背后跑命令**,只能靠机械扫描抓。
  local d; d="$(mktemp -d)"
  local lint="$d/lint.py"
  cat > "$lint" <<'LINT_PY'
# shell 引号状态机:找出「会被 shell 当成命令替换执行」的反引号。
# 安全:单引号内 / shell 注释内 / <<'X' 这种加引号的 heredoc 内 / 反斜杠转义过的
# 危险:双引号内(python3 -c "…" 的块正是这种)/ 裸露的 / 没加引号的 heredoc 内
#
# 🔴 `$( … )` 是一个**新的引号上下文**(2026-08-26,嵌套命令替换)。
# 第一版把它当成"还在双引号里"继续扫,于是下面这种再普通不过的写法:
#     x="$(sed -n '/^PROMPT="/,/^Conclusion: …/p' "$F")"
# 里,单引号**内**的那个 " 会被当成外层双引号的收尾 —— 引号奇偶当场反相,
# 其后一百多行被判成"在单引号里"**从此不被扫**(盲区),同一处还会把后面
# 一行安全的 grep -q '<反引号>' 报成暴露点(误报)。两种坏,一个根因。
# 修法:进 $( 压栈、遇到配对的 ) 弹栈,里面从**干净的 N 状态**重新开始。
# 判据 V41⑦(不许误报)/ V41⑧(不许留盲区)分别钉这两面。
#
# 跨行双引号块里的 $( ):只报**这段双引号自己的文本里换过行之后**才出现的那些。
# 认了嵌套之后,"跨行就一律报"会把每一个正常的多行 x="$(cmd \ … )" 都报成
# 暴露点(对照组 V41⑨ 守着)。真正要抓的形状是"嵌在另一门语言的代码块里":
# 08-19 那次是 python3 -c "…\n# 注释里的 $(touch X)…" —— 替换出现在**后续行**上。
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
n = len(src); i = 0; st = 'N'; hd = None; hits = []; dstart = 0
stack = []   # $( … ) 上下文栈:(外层 st, 外层 dstart, 本层已进的普通括号深度)
def ln(off): return src.count('\n', 0, off) + 1
while i < n:
    c = src[i]
    if hd is not None:
        j = src.find('\n', i); j = n if j < 0 else j
        # bash 的规则:<< 要求结束标记**整行完全相等**,只有 <<- 才容前导 tab(且只有 tab)。
        # 用 strip() 匹配会把缩进的 EOF 误当结束 ⇒ 提前出块、后面整段状态错位 ⇒ **漏报**。
        _l = src[i:j]
        if (_l.lstrip('\t') if hd[2] else _l) == hd[0]:
            hd = None; i = j + 1; continue
        if not hd[1]:
            # 没加引号的 heredoc 里,反斜杠仍然转义 ` $ \ —— 必须逐字符走,
            # 粗暴地 '`' in line 会把 \` 这种**已经转义好**的报成危险(08-19 实测误报 4 处)
            k = i
            while k < j:
                if src[k] == '\\': k += 2; continue
                if src[k] == '`':
                    hits.append(ln(k)); break
                k += 1
        i = j + 1
    elif st == 'S':
        st = 'N' if c == "'" else 'S'; i += 1
    elif st == 'D':
        # `…` 一律报:现代 shell 里没人拿它做有意的命令替换($( ) 早就取代了),实测 0 误报。
        if c == '\\': i += 2
        elif c == '"': st = 'N'; i += 1
        elif c == '`': hits.append(ln(i)); i += 1
        elif src.startswith('$(', i):
            if src.count('\n', dstart, i) > 0: hits.append(ln(i))
            stack.append((st, dstart, 0)); st = 'N'; i += 2
        else: i += 1
    else:
        if c == '\\': i += 2
        elif c == '#' and (i == 0 or src[i-1] in ' \t\n'):
            j = src.find('\n', i); i = n if j < 0 else j
        elif c == "'": st = 'S'; i += 1
        elif c == '"': st = 'D'; dstart = i; i += 1
        elif src.startswith('<<', i):
            m = re.match(r"<<(-?)\s*('([^']+)'|\"([^\"]+)\"|([A-Za-z_]\w*))", src[i:i+64])
            if m:
                tok = m.group(3) or m.group(4) or m.group(5)
                quoted = bool(m.group(3) or m.group(4))
                dash = bool(m.group(1))
                j = src.find('\n', i); i = (n if j < 0 else j) + 1
                hd = (tok, quoted, dash); continue
            i += 2
        elif src.startswith('$(', i):
            stack.append((st, dstart, 0)); st = 'N'; i += 2
        elif c == '(' and stack:
            _st, _ds, depth = stack[-1]; stack[-1] = (_st, _ds, depth + 1); i += 1
        elif c == ')' and stack:
            _st, _ds, depth = stack[-1]
            if depth > 0: stack[-1] = (_st, _ds, depth - 1)
            else: stack.pop(); st, dstart = _st, _ds
            i += 1
        elif c == '`': hits.append(ln(i)); i += 1
        else: i += 1
lines = src.split('\n')
for l in sorted(set(hits)):
    print(f"{l}: {lines[l-1].strip()[:100]}")
sys.exit(1 if hits else 0)
LINT_PY

  # ① 真身:判据文件自己必须是零处
  local self out rc
  self="${BASH_SOURCE[0]}"
  if [[ ! -f "$self" ]]; then
    bad "V41①: 找不到判据自己($self)—— 不许静默跳过"
  else
    out="$(python3 "$lint" "$self" 2>&1)"; rc=$?
    [[ $rc -eq 0 ]]
    check "V41①: 判据自己没把注释暴露给 shell(python3 的块要用加引号 heredoc 喂)" $?
    [[ $rc -eq 0 ]] || echo "    暴露点:$out"
  fi

  # ② 检查器得咬得动 —— 埋一个和 08-19 那处同形的
  cat > "$d/bad.sh" <<'BAD_FIXTURE'
check_it() {
  python3 -c "
import sys
# 这句注释里的 `date` 会被 shell 当命令替换真跑掉
sys.exit(0)"
}
BAD_FIXTURE
  python3 "$lint" "$d/bad.sh" >/dev/null 2>&1
  [[ $? -eq 1 ]]
  check "V41②: 检查器咬得动(埋进去的裸反引号必须被报出来,否则它是个瞎子)" $?

  # ③ 不许误报 —— 误报会逼出「绕开它」的习惯,和假绿一样坏
  cat > "$d/good.sh" <<'GOOD_FIXTURE'
x="$(date)"
y="literal \` backtick"
# shell 注释里的 `backtick` 无害
python3 - <<'INNER_PY'
# 加引号 heredoc 里的 `backtick` 也无害
print(1)
INNER_PY
cat <<UNQ_OK
没加引号的 heredoc 里,**转义过的** \` 是字面量,不许报(08-19 误报 4 处的形状)
UNQ_OK
GOOD_FIXTURE
  python3 "$lint" "$d/good.sh" >/dev/null 2>&1
  [[ $? -eq 0 ]]
  check "V41③: 不许误报(\$(cmd)、转义反引号、shell 注释、加引号 heredoc 都安全)" $?

  # ④ 没加引号的 heredoc 里,反引号同样真执行
  cat > "$d/unquoted.sh" <<'UNQ_FIXTURE'
cat <<EOF
里面的 `date` 会真的执行
EOF
UNQ_FIXTURE
  python3 "$lint" "$d/unquoted.sh" >/dev/null 2>&1
  [[ $? -eq 1 ]]
  check "V41④: 没加引号的 heredoc 里的反引号也会执行,同样要报" $?

  # ⑤ $( ) 和反引号同罪 —— V41 第一版只查反引号,是**半瞎的闸**。
  # 08-19 自审实测:python3 -c "…" 的注释里写 $(touch X),X **真被创建出来**了
  # (比反引号那次更狠 —— 那次是 `git diff --output=` 被 git 拒了才没落地)。
  cat > "$d/dollar.sh" <<'DOLLAR_FIXTURE'
python3 -c "
import sys
# 这句注释里的 $(id) 会被 shell 真执行
sys.exit(0)"
DOLLAR_FIXTURE
  python3 "$lint" "$d/dollar.sh" >/dev/null 2>&1
  [[ $? -eq 1 ]]
  check "V41⑤: 跨行双引号块里的 \$( ) 也要报(和反引号同罪,第一版漏了这一整类)" $?

  # ⑥ heredoc 结束标记必须整行相等(<<- 才容 tab)。用 strip() 匹配会提前出块,
  # 后面整段状态错位 —— 这类坏法造的是**漏报**,比误报更难发现。
  cat > "$d/hd.sh" <<'HD_FIXTURE'
cat <<'EOF'
  EOF
`safe_inside_quoted_heredoc`
EOF
HD_FIXTURE
  python3 "$lint" "$d/hd.sh" >/dev/null 2>&1
  [[ $? -eq 0 ]]
  check "V41⑥: 缩进的 EOF 不算结束标记 —— 不许提前出 heredoc(错位=漏报)" $?

  # ⑦/⑧ 🔴 `$( … )` 是一个**新的引号上下文**,状态机进得去也得出得来。
  # 2026-08-26 实事故:本文件 4957 行那句
  #     prompt_txt="$(sed -n '/^PROMPT="/,/^Conclusion: …/p' "$SOME_FILE")"
  # 里,单引号**内**的那个 `"` 被状态机当成外层双引号的收尾 ⇒ 引号奇偶当场反相,
  # 其后 108 行整段被判成"在单引号里" —— 一箭双雕的两种坏:
  #   · 误报:一行安全的 `grep -q '<反引号>'` 被报成暴露点(实测 bash 不执行它);
  #   · 盲区:我往那段里插一句真危险的 python3 -c "… # <反引号>touch X<反引号> …",
  #     闸**一声不吭**。误报还看得见,盲区看不见 —— 这才是这道闸最贵的坏法。
  # 所以两条一起钉:同一个形状,一条问"不许报",一条问"必须报得出、且报对行"。
  cat > "$d/subctx_ok.sh" <<'SUBCTX_OK'
val="$(sed -n '/^PROMPT="/,/^Conclusion: PASS/p' "$SOME_FILE")"
if grep -q '`' <<<"$val"; then echo found; fi
SUBCTX_OK
  python3 "$lint" "$d/subctx_ok.sh" >/dev/null 2>&1
  [[ $? -eq 0 ]]
  check "V41⑦: \$( ) 里的引号不许把后面整段带偏(单引号里的双引号 ⇒ 误报)" $?

  cat > "$d/subctx_blind.sh" <<'SUBCTX_BLIND'
val="$(sed -n '/^PROMPT="/,/^Conclusion: PASS/p' "$SOME_FILE")"
python3 -c "
import sys
# V41_BLINDSPOT_MARKER 这句注释里的 `date` 会被 shell 真跑掉
sys.exit(0)"
SUBCTX_BLIND
  out="$(python3 "$lint" "$d/subctx_blind.sh" 2>&1)"; rc=$?
  # 只问 rc=1 不够:上面那种误报也会给 rc=1 —— 那样这条断言会**为了错误的理由变绿**。
  # 必须问"报出来的是不是那一行"。
  [[ $rc -eq 1 ]] && grep -q "V41_BLINDSPOT_MARKER" <<<"$out"
  check "V41⑧: 同一形状之后的真危险行必须报得出来(盲区=漏报,比误报更贵)" $?
  [[ $rc -eq 1 ]] || echo "    (盲区实况:$out)"

  # ⑨ 对照组 🔴 修 ⑦⑧ 时最容易顺手造出来的新病:把"跨行双引号块里的 $( ) 一律报"
  # 当成规则。状态机认了 $( … ) 之后,这条规则会把**每一个**跨行命令替换都报成暴露点
  # (本文件里就有 3 处正常写法)—— 误报会逼出"绕开这道闸"的习惯,和假绿一样坏。
  # 收紧后的契约:只报**这段双引号自己的文本里换过行之后**才出现的替换
  # ——那才是"嵌在另一门语言的代码块里"的形状(08-19 那次就是)。
  # 这条在修改前后都必须是绿的(实测:旧量具 rc=0、新量具 rc=0),它是对照组不是新断言。
  cat > "$d/multiline_ok.sh" <<'ML_FIXTURE'
changed="$(comm -3 <(printf '%s' "$A" | sort) \
                   <(printf '%s' "$B" | sort) | head -5)"
out="$(cd "$d" && env -u FOO BAR=1 \
  bash ./thing.sh 2>&1)"
ML_FIXTURE
  python3 "$lint" "$d/multiline_ok.sh" >/dev/null 2>&1
  [[ $? -eq 0 ]]
  check "V41⑨: 合法的跨行 \$( … ) 惯用法不许被报(对照组:收紧不是放宽)" $?

  rm -rf "$d"
}

v42_git_common_dir_no_silent_gap() {
  echo "[V42] 老 git 不认 --path-format ⇒ worktree 共同目录不许静默漏挂(共同目录静默漏挂)"
  # `--path-format=absolute --git-common-dir` 要 git ≥2.31(2021-03)。老 git 不认这个参数
  # ⇒ 报错进 /dev/null、`|| true` 吞掉 rc ⇒ 共同目录拿到空 ⇒ **不挂只读**。
  # 后果:腿照样往 /main/.git 写(git tag / 直接写 objects),而仓根探针一路绿灯。
  # 这是全工具唯一一处**失败被吞而不是 fail-closed** 的地方,而 fail-closed 正是本单的规格。
  local d b; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b"

  if ! command -v unshare >/dev/null 2>&1 || [[ ! -x "$BIN/ro-repo-exec" ]]; then
    bad "V42①: 老 git 下 worktree 共同目录仍然只读(缺 unshare/ro-repo-exec ⇒ 不许静默跳过)"
    bad "V42②: 共同目录拿不到时拒跑(缺件同上)"
    rm -rf "$d"; return
  fi

  ( cd "$d" && git init -q main && cd main && printf 'x\n' > a.txt && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm base \
    && git worktree add -q "$d/linked" -b probe ) >/dev/null 2>&1
  local common="$d/main/.git"
  if [[ ! -d "$common" ]]; then
    bad "V42: 夹具没搭起来(没有 worktree 共同目录)—— 不许静默跳过"
    rm -rf "$d"; return
  fi

  local realgit; realgit="$(command -v git)"

  # ① 老 git 的替身:**只**对 --path-format 装不认识,其余原样转给真 git
  cat > "$b/git" <<GITSTUB
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in --path-format=*) echo "error: unknown option \$a" >&2; exit 129 ;; esac
done
exec "$realgit" "\$@"
GITSTUB
  chmod +x "$b/git"
  rm -f "$common/PWNED_V42"
  PATH="$b:$PATH" bash "$BIN/ro-repo-exec" "$d/linked" -- \
    bash -c ": > '$common/PWNED_V42'" >/dev/null 2>&1
  [[ ! -e "$common/PWNED_V42" ]]
  check "V42①: 老 git(不认 --path-format)下,worktree 的共同目录仍然写不进去" $?
  rm -f "$common/PWNED_V42"

  # ② 连兜底也拿不到共同目录 ⇒ 必须**拒跑**。静默少挂一块 = 防线在你不知道的时候变薄。
  local b2="$d/bin2"; mkdir -p "$b2"
  cat > "$b2/git" <<GITSTUB2
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in --git-common-dir) echo "error: unknown option \$a" >&2; exit 129 ;; esac
done
exec "$realgit" "\$@"
GITSTUB2
  chmod +x "$b2/git"
  PATH="$b2:$PATH" bash "$BIN/ro-repo-exec" "$d/linked" -- true >/dev/null 2>&1
  [[ $? -ne 0 ]]
  check "V42②: 共同目录拿不到时**拒跑**(不许静默少挂 —— 这单唯一的 fail-open)" $?

  rm -rf "$d"
}

# ---------------------------------------------------------------- V43
# 用户 2026-08-20 拍板:常态不再固定四审。默认从健康池轮换两条不同家族的腿，
# 失败/冲突才加第三条；四审保留显式入口。额度不足是腿的健康状态，不是实现 BLOCK。

v45_oracle_never_touches_owner_credentials() {
  echo "V45: 判卷工具自己不许碰业主的真实评审环境"
  local after changed
  after="$(_owner_env_fp)"
  if [[ "$after" == "$OWNER_ENV_BEFORE" ]]; then
    # 🔴 PASS 时**不打印指纹**:收据是要 commit 进仓的,而指纹里有业主凭证文件的
    #    大小/时间/短哈希 —— 绿的时候没人需要它,红的时候才需要,那时也只打变了的那几项。
    ok "V45: 整套判据跑完后业主的凭证目录 / kimi home / mimo home 原封不动"
  else
    changed="$(comm -3 <(printf '%s' "$OWNER_ENV_BEFORE" | tr ';' '\n' | sort) \
                       <(printf '%s' "$after"            | tr ';' '\n' | sort) \
               | tr -d '\t' | paste -sd' ' -)"
    bad "V45: 判据动了业主的真实环境 —— 变的是:$changed"
    echo "     ⚠️ 你若在这 ~3 分钟里跑过 kimi login / 并发跑了一轮评审,那是误报;"
    echo "        否则就是判据在写它不该写的地方 —— **先查判据,别先调钝这道闸**。"
    echo "     去哪找:判据里跑 subkimi / submimo / subdeepseek-agent 而**没把对应的"
    echo "        *_REVIEW_HOME 指进夹具**的调用点。2026-08-25 一共揪出 5 处,一处一处补。"
  fi
}

# 发布正文是各家命令行结构里的最后一条消息，不是渲染后的过程。
v46_final_report_is_the_last_message() {
  echo "[V46] 评审腿把最后一条消息原样写入报告文件"
  local d b rc; d="$(mktemp -d)"; b="$d/bin"; mkdir -p "$b" "$d/repo"
  fixture_git_repo "$d/repo"
  printf '# t\n' > "$d/t.md"
  cp "$BIN/subdeepseek-agent" "$BIN/subagent" "$BIN/subkimi" "$BIN/submimo" \
    "$BIN/_review-home-guard.sh" "$BIN/_review-workspace.sh" "$BIN/aiwork-config" \
    "$BIN/_aiwork_config.py" "$BIN/_review_result.py" "$BIN/ro-repo-exec" "$b/"
  printf '%s' $'Findings at gate/decide.mjs:22.\n\nThe pending ternary is not a verdict line.\n\nConclusion: PASS' > "$d/last.txt"
  local rh="$d/review-home"; mkdir -p "$rh/hooks" "$rh/credentials"
  printf 'default_model = "x"\n' > "$rh/config.toml"
  printf 'process.exit(2)\n' > "$rh/hooks/guard.mjs"
  echo '{}' > "$rh/credentials/kimi-code.json"

  cat > "$b/claude" <<'PY'
#!/usr/bin/env python3
import json, os, sys
sys.stdin.read()
noise = ("## 过程\n\n```python\n# 注释\nconclusion: pending ? null : value\n```\n\n"
         "  → Bash sed -n '1,40p' gate/decide.mjs\necho hi\n\nkimi> \n\nConclusion: BLOCK")
last = open(os.environ["FINAL_LAST"], encoding="utf-8").read()
print(json.dumps({"type":"assistant","message":{"content":[
    {"type":"text","text":noise},
    {"type":"tool_use","name":"Bash","input":{"command":"sed -n '1,40p' gate/decide.mjs\n# 注释\necho hi"}}]}}))
print(json.dumps({"type":"result","subtype":"success","is_error":False,"result":last}))
PY
  cat > "$b/kimi" <<'PY'
#!/usr/bin/env python3
import json, os
noise = ("## 过程\n\n```python\n# 注释\nconclusion: pending ? null : value\n```\n\n"
         "kimi> \n  → Bash sed -n '1,40p' gate/decide.mjs\n# 注释\necho hi\n\nConclusion: BLOCK")
last = open(os.environ["FINAL_LAST"], encoding="utf-8").read()
print(json.dumps({"role":"assistant","content":noise,"tool_calls":[
    {"id":"1","type":"function","function":{"name":"bash","arguments":"sed -n '1,40p' gate/decide.mjs\n# 注释\necho hi"}}]}, ensure_ascii=False))
print(json.dumps({"role":"tool","tool_call_id":"1","content":"## 过程\nkimi> \nconclusion: pending ? null : value"}, ensure_ascii=False))
print(json.dumps({"role":"assistant","content":last}, ensure_ascii=False))
print(json.dumps({"role":"meta","type":"session.resume_hint","content":"To resume this session: kimi -r x"}, ensure_ascii=False))
PY
  cat > "$b/mimo" <<'PY'
#!/usr/bin/env python3
import json, os, sys
if "--format" not in sys.argv or sys.argv[sys.argv.index("--format")+1] != "json":
    raise SystemExit("review must request --format json")
noise = ("## 过程\n\n```python\n# 注释\nconclusion: pending ? null : value\n```\n\n"
         "mimo> \n  → Bash sed -n '1,40p' gate/decide.mjs\n# 注释\necho hi")
last = open(os.environ["FINAL_LAST"], encoding="utf-8").read()
def emit(obj):
    print(json.dumps(obj, ensure_ascii=False))
emit({"type":"message.updated","properties":{"info":{"id":"m1","role":"assistant"}}})
emit({"type":"message.part.updated","properties":{"part":{
    "id":"p1","messageID":"m1","type":"text","text":noise}}})
emit({"type":"message.part.updated","properties":{"part":{
    "id":"p2","messageID":"m1","type":"tool","tool":"bash"}}})
emit({"type":"message.updated","properties":{"info":{"id":"m2","role":"assistant"}}})
emit({"type":"message.part.updated","properties":{"part":{
    "id":"p3","messageID":"m2","type":"text","text":"synthetic note","synthetic":True}}})
emit({"type":"message.part.updated","properties":{"part":{
    "id":"p4","messageID":"m2","type":"text","text":last}}})
emit({"type":"session.idle","properties":{}})
print("Conclusion: BLOCK")
PY
  chmod +x "$b/claude" "$b/kimi" "$b/mimo"

  _published() {  # $1 report $2 log
    python3 - "$BIN/review-pr" "$1" "$d/last.txt" "$2" <<'PY'
import importlib.machinery, importlib.util, pathlib, sys
loader = importlib.machinery.SourceFileLoader("review_pr", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
report, want, log = sys.argv[2:]
got = mod.review_report(pathlib.Path(report))
text = pathlib.Path(want).read_text(encoding="utf-8")
body_log = pathlib.Path(log).read_text(encoding="utf-8")
ok = (got == text and "## 过程" not in got and "pending ? null" not in got
      and "## 过程" in body_log and "pending ? null" in body_log and "# 注释" in body_log)
raise SystemExit(0 if ok else 1)
PY
  }

  env PATH="$b:$PATH" FINAL_LAST="$d/last.txt" DEEPSEEK_API_KEY="$FIXTURE_DS_KEY" \
    AIWORK_REVIEW_FACTS_PATH="$d/ds.facts.json" AIWORK_REVIEW_RESULT_BIN="$b/_review_result.py" \
    AIWORK_REVIEW_REPORT_PATH="$d/ds-report.md" \
    bash "$b/subdeepseek-agent" review "$d/t.md" "$d/ds.log" "$d/repo" >/dev/null 2>"$d/ds.err"; rc=$?
  check "V46: subdeepseek-agent 退出 0" $([[ $rc -eq 0 ]]; echo $?)
  cmp -s "$d/ds-report.md" "$d/last.txt"; check "V46: subdeepseek-agent 报告与最后一条消息一字不差" $?
  check "V46: subdeepseek-agent 发布正文只有报告，过程留在日志" \
    $(_published "$d/ds-report.md" "$d/ds.log"; echo $?)
  check "V46: subdeepseek-agent 裁决来自报告而不是过程里的 BLOCK" \
    $(python3 -c 'import json,sys; f=json.load(open(sys.argv[1])); sys.exit(0 if f["verdict"]=="PASS" else 1)' "$d/ds.facts.json"; echo $?)

  env PATH="$b:$PATH" FINAL_LAST="$d/last.txt" KIMI_REVIEW_HOME="$rh" \
    AIWORK_REVIEW_FACTS_PATH="$d/kimi.facts.json" AIWORK_REVIEW_RESULT_BIN="$b/_review_result.py" \
    AIWORK_REVIEW_REPORT_PATH="$d/kimi-report.md" \
    bash "$b/subkimi" review "$d/t.md" "$d/kimi.log" "$d/repo" >/dev/null 2>"$d/kimi.err"; rc=$?
  check "V46: subkimi 退出 0" $([[ $rc -eq 0 ]]; echo $?)
  cmp -s "$d/kimi-report.md" "$d/last.txt"; check "V46: subkimi 报告与最后一条消息一字不差" $?
  check "V46: subkimi 发布正文只有报告，过程留在日志" \
    $(_published "$d/kimi-report.md" "$d/kimi.log"; echo $?)
  check "V46: subkimi 裁决来自报告而不是过程里的 BLOCK" \
    $(python3 -c 'import json,sys; f=json.load(open(sys.argv[1])); sys.exit(0 if f["verdict"]=="PASS" else 1)' "$d/kimi.facts.json"; echo $?)

  env PATH="$b:$PATH" FINAL_LAST="$d/last.txt" MIMO_REVIEW_HOME="$d/mimo-home" \
    AIWORK_REVIEW_FACTS_PATH="$d/mimo.facts.json" AIWORK_REVIEW_RESULT_BIN="$b/_review_result.py" \
    AIWORK_REVIEW_REPORT_PATH="$d/mimo-report.md" \
    bash "$b/submimo" review "$d/t.md" "$d/mimo.log" "$d/repo" >/dev/null 2>"$d/mimo.err"; rc=$?
  check "V46: submimo 退出 0" $([[ $rc -eq 0 ]]; echo $?)
  cmp -s "$d/mimo-report.md" "$d/last.txt"; check "V46: submimo 报告与最后一条消息一字不差" $?
  check "V46: submimo 发布正文只有报告，过程留在日志" \
    $(_published "$d/mimo-report.md" "$d/mimo.log"; echo $?)
  check "V46: submimo 裁决来自报告而不是过程里的 BLOCK" \
    $(python3 -c 'import json,sys; f=json.load(open(sys.argv[1])); sys.exit(0 if f["verdict"]=="PASS" else 1)' "$d/mimo.facts.json"; echo $?)

  rm -rf "$d"
}

v9_claude_shell_base
v13_subkimi_leg
v20_max_turns_does_not_discard_work
v21_agent_leg_body_is_single_source
v24_coverage_report
v33_submimo_review_leg_is_read_only
v35_legs_run_in_readonly_repo
v36_wrappers_actually_use_readonly_repo
v37_wrappers_open_no_write_hole
v38_leg_runtime_home_outside_repo
v39_readonly_blind_spots
v41_oracle_never_executes_its_own_comments
v42_git_common_dir_no_silent_gap
v45_oracle_never_touches_owner_credentials
v46_final_report_is_the_last_message
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
