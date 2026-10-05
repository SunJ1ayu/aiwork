# aiwork

Multi-model review/execution tooling for the main agent (the frontier model
driving the session). The full workflow doctrine — when to use what, panel
protocol, safety rules — is versioned under `workflow/`; `~/CLAUDE.md` and
`~/.claude/skills/{track,panel,delegate}` are deployment copies checked by
`bin/sync-workflow-docs --check`. `~/AGENTS.md` is
deliberately absent so Codex does not automatically load these Claude-specific
instructions; this README only maps the machinery.

The `main` branch of this GitHub repository is the authoritative source for
aiwork. The local `/root/aiwork` is a clone of it; changes land through branches
and PRs. This repository keeps workflow tooling and its change records.
Credentials, project task briefs, reviewer logs, runtime homes, reference
copies, build output and worktrees stay on the machine as listed in `.gitignore`.
Track evidence and observations are versioned alongside their change records.

## History and project separation

This repository holds only the workflow: tools, tests, track records and
their evidence. Its history was filtered on 2026-10-04, before the repository
was made public: every commit keeps only workflow paths, so task briefs,
reference notes, configuration backups, logs and project material are gone
from all of history, and one private project name in three track records was
replaced with "另一个项目".

Commit IDs therefore differ from the ones quoted in records written before the
filter (track evidence, verify.md, review links). Those refer to the
unfiltered history, kept read-only in the private repository
`SunJ1ayu/aiwork-archive` together with the pull requests opened before the
switch. Nothing new goes into the archive.

The first-parent history of `main` is the original local history of
`/root/aiwork` (639 commits after filtering, up to `a617d69`), joined in by
merge `d2c5cb4`. Tracks archived before the switch therefore keep their
evidence and observations from their original archive commits. The
second-parent line is the curated snapshot (`2363e54`) that briefly stood in
for this repository, plus the changes made on it.

Things that are not aiwork live with their own owners:

- quicklook lives at `/root/quicklook`; its systemd unit and run-output path
  point there.
- The current wiki-ingest skill lives in the OpenClaw workspace at
  `/root/.openclaw/workspace/skills/wiki-ingest`; the older aiwork copy was
  removed.
- The `opendesign-file-organizer` and `opendesign-ref-images` track records
  belong to OpenDesign (moved by `SunJ1ayu/OpenDesign` PR #20).
- Local working files — task briefs, my-review files, reference notes, logs,
  tool homes — stay on the machine, ignored by Git. This repository is
  public: never commit private content.

## Layout

- `bin/` executors and panel tools (below)
- Data directory `tasks/` holds local task/brief files sent to reviewers (main-agent-authored)
- Data directory `logs/` holds reviewer output, `.err` sidecars and arbitration records
- `templates/` starter task files (`review-task.md`, `fix-task.md`)
- `tests/` regression oracles for this tooling itself
- `track/` lightweight change-workflow convention + templates (`bin/track` CLI)
- `tracks/` workflow change records with their `evidence/` and `observations/`
- `workflow/` canonical Claude instructions and workflow skills (deployed copies live outside Git)
- Data directory `worktrees/` holds per-job isolated checkouts created by `delegate-codex`
- `kimi-review-home/config.toml` and `hooks/` are local seeds; reviewer runtime homes use the data directory
- Existing `out/`, `refs/`, `.mimocode/`, `etc/` and other ignored local data await migration after merge

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
- `bin/review-pr PR --repo owner/name --leg LEG` — review a PR head and publish
  an aiwork-review COMMENT review. 需要联网、需要读取本机模型凭证；被 agent 派去跑时必须在沙箱外运行。
  Failed runs print the redacted last 40 stderr lines and retain their complete
  temporary directory under the data path `logs/review-pr-failures/<run-id>/`; successful runs
  discard it. Truncated chat context is published with `completeness=partial`.

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
- `bin/track-record` — validates the typed `decision.json`, atomically writes
  compact controller observations, and derives the read-only ledger. Controller
  events live in the main checkout's track (never an execution worktree), contain
  no prompt/transcript, and therefore survive safe worktree cleanup. Unknown usage
  stays `null`; observation-write failure is loud without changing controller rc.
  The `observations/` directory accepts only direct regular JSON events (64 KiB
  per event; panel-leg capacity is bounded by that byte limit, not a duplicate count).
  Writers and readers share the same strict
  schema, and staged machine facts remain guarded both before and after archive.
  Both CLI archive and staged manual archive validate execution plus the declared
  self/standard/high review floor: 0/1/2 coverage-eligible distinct model families
  from one successful panel run and one subject digest, with no eligible PASS/BLOCK
  conflict. Legacy v1, incomplete/degraded results, and cross-run evidence never fill
  that floor.
- `bin/redcheck` — revert-the-implementation red check: puts the impl back to a
  baseline, rebuilds, reruns the oracle, and REQUIRES red (`--must-fail` pins
  where the red must land). Restores unconditionally and proves the tree is clean.
- `bin/runlog` — makes the MACHINE write down what it ran: receipt files under
  `tracks/<track>/evidence/` plus one line to paste into verify.md. `--final`
  binds the same run (no extra execution) to full HEAD + before/after source-view
  hashes; every mode refuses secret-shaped argv/output before it can become a receipt
  or be replayed to the terminal.
- `bin/track-guard` — pre-commit guard for the track conventions.
- `bin/track archive` also SWEEPS the worktrees of the track being archived, but only
  those that are provably redundant: working tree clean AND their HEAD already an
  ancestor of the owning repo's default branch. Anything else BLOCKS the archive and is
  named (`--keep-trees` opts out). Trees belonging to another track, another repo, or to
  nobody are only listed, never touched — deleting the last copy of work is not
  symmetric with leaving a few MB on disk.

## Panel fan-out

Use `bin/panel-candidates --mode review|explore` to inspect configured models,
capabilities and past health (remaining quota stays unknown). Add
`--discover-cursor` to list CLI model IDs. The arbiter chooses the members:

```bash
bin/panel-candidates --adapter subcursor --discover-cursor --mode review
bin/panel-review --members submimo,subcursor@composer-2.5 --track NAME --risk high TASK REPO PREFIX
bin/panel-explore --members subcursor@cursor-grok-4.6-high,subcursor@composer-2.5 BRIEF REPO PREFIX
```

The Cursor pool can include GPT, Claude, GLM, Grok, Composer and other
explicit supported-family IDs returned by the CLI, not just the examples above.
Explicit lists freeze each model, support several models through one adapter,
and never rotate, add a spare or fall back. Review family minima still apply;
exploration results never count as review coverage. Each run's plan preserves
members and models for `panel-roster` recovery. Legacy commands remain compatible.
Model defaults live in `~/.config/aiwork/models.env`; environment overrides are frozen per member.


- `bin/panel-review --track NAME --risk self|standard|high TASK [REPO] [LOG_PREFIX]` —
  convergent review. Default high rotates two healthy model families; standard
  uses one and self uses none. Failure/degradation/conflict can add one spare;
  `--all` explicitly requests the entire current reviewer pool (all enabled legs
  whose configured executables are available). Pool membership comes from the
  single roster table, so adding or removing a leg does not change this contract. Use `--no-track`
  explicitly when the review belongs to no typed active track. Main agent arbitrates.
  It exits non-zero only if every actually dispatched leg fails; failed legs
  keep a `.err` sidecar.
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
  panel-review. Scoped results carry `review_contract_version=2` and never count as
  archive coverage; panel-slice never binds a track. Run dirs live outside the repo
  (default data path `logs/slice-<manifest>-<ts>/`); `status` is rebuilt from disk and
  `findings.jsonl` is append-only.
- `bin/subcodex <review|explore>` — GPT review leg on `codex exec`, model from
  the `codex` row in `~/.config/aiwork/models.env` (`SUBCODEX_MODEL` overrides one run). A
  role-only leg (`PANEL_ROLE_LEG_SPECS`): never rotated into normal panel-review,
  because GPT is also the default implementation leg. Source repo read-only via
  `ro-repo-exec`, disposable snapshot, `--ignore-user-config --ephemeral`, prompt via
  stdin. Sub-agent tools are removed with a per-run model catalog override (feature
  flags alone do not remove them for gpt-6-astra) and checked offline with
  `codex debug prompt-input` before dispatch; web search is disabled.

Both stagger launches and the engine retries 429/5xx with bounded backoff.

## Tests (run before trusting any tooling change)

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

`kimi-review-home/config.toml` 和 `hooks/` 是种子，留在仓内原处且继续忽略；后续单独做隐私检查后入 Git。
运行期配置和 hooks 只从种子同步这两类文件；凭证、缓存、会话、日志、索引和遥测留在数据目录，
不会从旧种子目录整份复制。未搬迁或认证前，新运行目录缺少凭证会明确拒绝运行。

`out/`、`refs/`、`.mimocode/`、`etc/` 的备份属于本机数据，当前 B 范围内的代码没有读取这些备份。
本 PR 不搬动已有本机数据；合并后由云端 Claude 提供搬迁命令。
正式切换新默认值前须完成搬迁（包括各评审 cache home、面板健康状态、任务与日志）；
worktree 的 Git 注册路径也须修复。归档发现旧位置仍有本轮注册的树时拒绝继续，
明确给出旧树和新根；`--keep-trees` 或既有专用路径覆盖仍可显式保留旧树。
`tmp-sweeper`、`disk-watch`、`openclaw-up`、`check-gateway-version`、MiMo 密钥位置清单及 cron 留给 PR C。
普通缓存 `__pycache__`、`.pytest_cache`、`.mutation-state` 保持现状。
