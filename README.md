# aiwork

Multi-model implementation and PR review tooling.

评审与修复规则见 [REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md)，项目已接受风险见项目 main 的
`.aiwork/accepted-risks.md`，正式评审与合并条件见项目关卡策略。
任务的操作步骤见 [workflow/CLAUDE.md](workflow/CLAUDE.md)；工具用法在 `workflow/skills/`。
`~/CLAUDE.md` 和 `~/.claude/skills/{panel,delegate}` 是由 `bin/sync-workflow-docs` 管理的部署副本。

GitHub `main` 是 aiwork 的源码准本。改动使用机器人分支和 PR；原始日志、配置、会话及本机资料
留在机器的数据目录。

## History

旧记录在 git 历史里。

## What lives elsewhere

- quicklook lives at `/root/quicklook`; its systemd unit and run-output path
  point there.
- The current wiki-ingest skill lives in the OpenClaw workspace at
  `/root/.openclaw/workspace/skills/wiki-ingest`; the older aiwork copy was
  removed.
- Local working files — task briefs, my-review files, reference notes, logs,
  tool homes — stay in the machine data directory outside this checkout. This repository is
  public: never commit private content.

## Layout

- `bin/` executors and panel tools (below)
- Machine data directory `tasks/` holds local task/brief files sent to reviewers (main-agent-authored)
- Machine data directory `logs/` holds reviewer output, `.err` sidecars and arbitration records
- `gate/` shared merge gate. A project connects by the steps in [gate/README.md](gate/README.md)
- `templates/` starter task files (`review-task.md`, `fix-task.md`) and the two gate workflow templates
- `tests/` regression oracles for this tooling itself
- `workflow/` canonical Claude instructions and workflow skills (deployed copies live outside Git)
- Machine data directory `worktrees/` holds per-job isolated checkouts created by `delegate-codex`
- `kimi-review-home/config.toml` and `hooks/guard.mjs` are versioned seeds; reviewer runtime homes use the data directory
- `out/`, `refs/`, `.mimocode/`, `etc/` and other local data live outside the checkout

## Core engine

- `bin/submimo-review` — provider-agnostic chat review engine. Assembles the
  prompt (task file + `git diff` vs HEAD/`PANEL_DIFF_BASE` + untracked-file
  content + `--include` files, all byte-capped), calls one OpenAI-compatible
  chat endpoint, validates the output (empty / verdict-less ⇒ non-zero exit),
  writes the log. Despite the name and the `MIMO_*` env namespace (historical),
  it serves ALL chat providers: subdeepseek and subglm drive it by overriding
  `MIMO_CHAT_COMPLETIONS_URL`/`MIMO_API_KEY`/`MIMO_MODEL`. panel-explore reuses
  it in explore mode (`--mode explore` / `REVIEW_MODE=explore`: no verdict
  demanded) with `REVIEW_SYSTEM_PROMPT` supplying the divergent prompt text.

## Executors (the "employees")

- `bin/submimo` — MiMo on the official agent CLI (`mimo run`); the only
  executor with `fix` mode. `review` uses the plan agent read-only.
- `bin/subdeepseek-agent` / `bin/subdeepseek` — DeepSeek review-only default agent
  leg plus chat fallback (formerly subsense). Extra chat context via `DEEPSEEK_INCLUDE`.
- `bin/subglm-agent` / `bin/subglm` — GLM review-only default OpenCode agent leg plus
  chat fallback. Extra chat context via `ZHIPU_INCLUDE`.
- `bin/subkimi` — Kimi membership-backed, review-only agent leg with no chat fallback.
- `bin/subgemini` — Gemini membership-backed, review-only Antigravity CLI leg with
  no chat fallback. `bin/subgemini-diag` extracts denied tools/commands from its
  local conversation database.
- `bin/subcursor <review|explore>` — Cursor CLI with read/search/list tools in an
  isolated workspace. Both modes read the `cursor` row in `~/.config/aiwork/models.env`;
  change that one model ID (or set `CURSOR_MODEL`) to switch models. Coverage
  follows the model family, not the Cursor transport. `PANEL_CURSOR_LEG=off`
  disables it in both dispatchers. Authenticate with `cursor-agent login`.
- `bin/subgrok` — Grok Build CLI, `review` and `explore`; both read their default
  model from the `grok` row in `~/.config/aiwork/models.env`. A model upgrade changes that one
  configuration line, not the adapter or panel; `GROK_MODEL` overrides one run.
  Uses an isolated runtime home and disposable snapshot with the source mounted
  read-only. Existing `~/.grok/auth.json` supplies session login; `XAI_API_KEY`
  explicitly selects API billing. Override with `GROK_MODEL`, `GROK_AUTH_FILE`,
  `GROK_TIMEOUT` (900 seconds), or `GROK_MAX_TURNS` (80). No chat fallback or fix
  mode. `PANEL_GROK_LEG=off` disables it in either panel. The report log is a
  header plus assistant text; `.stream.jsonl` and `.stream-summary.json` preserve tools,
  actual model, completion and reported usage. Timeout/turn-limit/error output
  remains partial evidence and never counts as completed review coverage.
- `bin/submimo-iso` — concurrency-safe submimo for two simultaneous
  driver agents (e.g. Claude + Codex).
- `bin/review-pr PR [--repo owner/name] --leg LEG` — review a PR head and publish. `--repo` defaults to this checkout's origin; pass it when that origin is not a GitHub `owner/name`.
  an aiwork-review COMMENT review. 需要联网、需要读取本机模型凭证；被 agent 派去跑时必须在沙箱外运行。
  Failed runs print the redacted last 40 stderr lines and retain diagnostics
  under the data path `logs/review-pr-failures/<run-id>/`, excluding the repository
  checkout and credential helper. Only the newest 20 failure archives are retained.
  The task contains the sole PR diff and repeats the conclusion requirement after it.
  Tasks exceeding `MIMO_MAX_FILE_BYTES` (default 120000 bytes) switch from chat to
  an available repository reader of the same family; the switch is disclosed in
  the terminal and published review. Without a reader, the run stops. Truncated
  chat context is refused before requesting a model response.
  Repository readers default to 2400 seconds for this command; their existing
  timeout environment variables override that default. Only a missing verdict
  or `finish_reason=length` triggers one retry, disclosed in the terminal and
  review. Each failed attempt is preserved, including when the retry succeeds;
  other failures do not restart the review leg. The chat engine retains its
  existing backoff retries for HTTP 429/5xx; other HTTP 4xx are not retried.

All executors: `<tool> review TASK LOG REPO`. Output is evidence for the main
agent to verify, never a verdict to adopt.

## Delegation entry + judging guards

- `bin/delegate-codex` — the ONE entry for handing implementation work to the
  codex (GPT) leg, and the mechanical half of receiving gate ①. It refuses to
  dispatch (codex never starts) unless: an attack-log exists outside the repo,
  a `--protect` judging list is given, and the attack-log carries the CURRENT
  `oracle-sha256:` of that judging surface (`--print-oracle-hash` emits the line).
  **Each job runs in its own git worktree by default** (`--no-isolate` opts out):
  data path `worktrees/<task>-<ts>` on branch `delegate/<same>`, created from the HEAD at
  dispatch. `--receive <receipt>` runs gate ① against that tree (plus a check for
  uncommitted judging changes in the MAIN tree, which the leg can still reach),
  records the machine-computed write set into the receipt, and PRINTS the
  integrate / symlink-check / `worktree remove` commands — it never merges or
  deletes anything itself.
  Isolation buys attribution, not confinement: `-s workspace-write` resolves its
  writable root upward to the main repo (a worktree's `.git` is a file), so case
  files (attack log, log, receipt) must stay outside `repo ∪ worktrees-root`.
- `bin/redcheck` — revert-the-implementation red check: puts the impl back to a
  baseline, rebuilds, reruns the oracle, and REQUIRES red (`--must-fail` pins
  where the red must land). Restores unconditionally and proves the tree is clean.
  The rule entry is [REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md).

## Panel fan-out

Use `bin/panel-candidates --mode review|explore` to inspect configured models,
capabilities and past health (remaining quota stays unknown). Add
`--discover-cursor` to list CLI model IDs. The arbiter chooses the members:

```bash
bin/panel-candidates --adapter subcursor --discover-cursor --mode review
bin/panel-review --members submimo,subcursor@composer-2.5 TASK REPO PREFIX
bin/panel-explore --members subcursor@cursor-grok-4.6-high,subcursor@composer-2.5 BRIEF REPO PREFIX
```

The Cursor pool can include GPT, Claude, GLM, Grok, Composer and other
explicit supported-family IDs returned by the CLI, not just the examples above.
Explicit lists freeze each model, support several models through one adapter,
and never rotate, add a spare or fall back. Formal PR review uses `review-pr`;
exploration reports are optional design material. Each run's plan preserves
members and models for `panel-roster` recovery. Legacy commands remain compatible.
Model defaults live in `~/.config/aiwork/models.env`; environment overrides are frozen per member.


- `bin/panel-review TASK [REPO] [LOG_PREFIX]` — optional second-opinion analysis.
  `--all` runs the entire current reviewer pool (enabled, available channels); tool status is diagnostic output.
  Details and explicit member selection are in the panel skill.
- `bin/panel-explore BRIEF [REPO] [LOG_PREFIX]` — divergent: MiMo, DeepSeek,
  GLM and Grok each propose ONE direction; no verdict by design.
- `bin/panel-slice run|verify|retry|abandon|decide|status` — sliced review, single layer:
  the main agent's manifest splits one change into 2..8 slices; each slice is one
  session of one healthy leg from a distinct model family, plus one independent
  overall leg (default `subcodex`, GPT) whose family no slice uses. N slices =
  exactly N+1 sessions; `verify` sends recorded findings to a different family,
  `retry` re-dispatches one item, both from a shared `extra_sessions` budget.
  Every work item is one `panel-review --scoped-review --pin-leg LEG` call, so
  isolation, task freezing, setsid survival, typed results and health all stay in
  panel-review. Scoped results carry `review_contract_version=2` for diagnostic sessions. Run dirs live outside the repo
  (default data path `logs/slice-<manifest>-<ts>/`); `status` is rebuilt from disk and
  `findings.jsonl` is append-only.
- `bin/subcodex <review|explore>` — GPT review leg on `codex exec`, model from
  the `codex` row in `~/.config/aiwork/models.env` (`SUBCODEX_MODEL` overrides one run). A
  role-only leg (`PANEL_ROLE_LEG_SPECS`), available to explicit calls and panel-slice. Source repo read-only via
  `ro-repo-exec`, disposable snapshot, `--ignore-user-config --ephemeral`, prompt via
  stdin. Sub-agent tools are removed with a per-run model catalog override (feature
  flags alone do not remove them for gpt-6-astra) and checked offline with
  `codex debug prompt-input` before dispatch; web search is disabled.

Both stagger launches and the engine retries 429/5xx with bounded backoff.

## Tests (run for tooling changes)

推送前启用仓内隐私钩子（在仓库根目录执行，每台机器设置一次）：

```bash
git config core.hooksPath .githooks
install -d -m 700 ~/.config/aiwork
touch ~/.config/aiwork/private-terms
chmod 600 ~/.config/aiwork/private-terms
# 自己编辑 private-terms，一行一个私人词；不要提交词表。
bin/privacy-check origin/main..HEAD
bin/privacy-check --all
bin/privacy-check --files kimi-review-home/config.toml kimi-review-home/hooks/guard.mjs
bin/privacy-check HEAD  # 当前分支可达的全部历史，含根提交
```

`aiwork-config path private-terms` 定位本机词表；词表缺失时检查失败，空表只检查密钥形状。
范围检查每个提交新增的行、新增文件路径、提交说明、作者和提交者的名字与邮箱；
`--all` 检查当前已跟踪和未忽略的工作树文件（包括路径）。钩子检查实际推送的提交，删除分支不检查。
新分支以本机已获取的远端 refs 排除已有历史；没有远端 refs 时检查全部历史。
命中只报 `文件:行号` 和类型，路径本身命中时隐藏路径；路径用 `:0`，提交元数据用 `commit/<SHA>/<字段>:行号`。
返回码 `0` 为干净，`1` 为命中，`2` 为检查失败。密钥形状只有 `bin/_secret-shapes` 一份定义，供日志脱敏和检查共用。
不许用 `--no-verify` 绕过；误报修改本机词表或在运行时拼接测试夹具。

```bash
bash bin/rust-check-review-tooling   # THE runner: every suite below, one summary line
bash bin/rust-check-review-tooling --coverage-only   # just the "who is not covered" report
```

The runner is list-driven (`SUITES`) and hard-reds when a `tests/test-*` file is
NOT in that list — a judging suite nobody runs rots silently. Individual suites
still run standalone (`bash tests/test-delegate-isolate.sh`); each one execs
itself into a network namespace first, because **a judging process must have no
egress** (2026-08-10: an oracle called a paid model and burned the quota).

The oracle is owned by the main agent; employees must never edit it.

## MiMo agent CLI setup

```bash
npm install -g @mimo-ai/cli
mimo                      # or: mimo providers login / list
```

## Engine environment

Secrets stay in the shell (or provider authfiles), never in this repo.

```bash
export MIMO_API_KEY='your-key'
export MIMO_BASE_URL='https://your-openai-compatible-endpoint'   # or:
export MIMO_CHAT_COMPLETIONS_URL='https://.../v1/chat/completions'
export MIMO_MODEL='mimo-2.5'
```

Dry run (writes the assembled prompt to the log without calling the API):

```bash
bin/submimo-review templates/review-task.md \
  ~/.local/share/aiwork/logs/dry-run.log --repo /path/to/repo --git-diff --dry-run
```

The chat engine cannot read files by itself: use `--git-diff` / `--include`
(or the wrapper INCLUDE env vars) to attach context. An empty diff with
nothing attached triggers a loud BLIND-review warning.

## 本机设置

仓库只保存工作流；本机设置统一放在 `~/.config/aiwork/`（目录权限 700）：

- `models.env`：Codex、Cursor、DeepSeek、Gemini、GLM、Grok、Kimi、MiMo 和 triage 的模型选择，每条腿一行。可参考 `templates/models.env.example`。
- `typesafe.env`：triage 使用的 `TYPESAFE_API_KEY`，保留文件权限 600。
- `apps/*.env`：GitHub App 各角色的 App ID、安装 ID、目标仓库和权限配置。
  `KEY` 推荐只写文件名（如 `KEY=aiwork-sync.pem`）；相对路径在所选 `apps/` 下查找，绝对路径照原样使用。
- `apps/*.pem`：GitHub App 私钥，文件权限 600。

换机器时把整个目录复制过去并保持权限。`bin/aiwork-config` 是统一读取入口；
`AIWORK_CONFIG_DIR` 可指定其他设置目录，测试只指向临时目录。
`AIWORK_APPS_DIR` 仍可单独覆盖 App 配置目录。
`models.env` 必须完整，包含每条腿的模型行；原有模型单次覆盖参数只是在完整设置的基础上换一次，不能代替文件或补缺行。
缺少 `models.env` 或所需腿的模型行时明确报错并停止，不调用模型。
本机数据由 `bin/aiwork-config data-path [相对路径]` 统一定位，默认 `~/.local/share/aiwork/`；
`AIWORK_DATA_DIR` 可覆盖该入口（例如离线测试使用临时目录）。供应商隔离运行时会改写
`XDG_*`，因此 aiwork 数据入口不随供应商的 XDG 设置变化。查询路径本身不创建目录。

`tasks/`、`logs/`（包括面板健康状态和失败日志）、`worktrees/`、`mimo-home/` 以及各评审腿的运行期 home
都使用该数据入口；已有的专用路径覆盖参数仍优先。源码、模板和共享组件相对实际工具位置查找，
`bin/` 应作为完整工具集部署；缺失共享组件时拒绝派发，不回落到其他机器的 checkout。

`kimi-review-home/config.toml` 和 `hooks/guard.mjs` 是版本控制中的种子；`subkimi` 在运行期 home 渲染模型和 guard 命令占位符。
运行期配置和 hooks 只从种子同步这两类文件；凭证、缓存、会话、日志、索引和遥测留在数据目录，
不会从种子目录整份复制。运行目录缺少凭证会明确拒绝运行。

`out/`、`refs/`、`.mimocode/`、`etc/` 的备份属于仓外本机数据。
归档发现旧位置仍有本轮注册的树时拒绝继续，
明确给出旧树和新根；`--keep-trees` 或既有专用路径覆盖仍可显式保留旧树。
普通缓存 `__pycache__`、`.pytest_cache`、`.mutation-state` 保持现状。
