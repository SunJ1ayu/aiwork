# aiwork

Multi-model review/execution tooling for the main agent (the frontier model
driving the session). The full workflow doctrine — when to use what, panel
protocol, safety rules — is versioned under `workflow/`; `/root/CLAUDE.md` and
`/root/.claude/skills/{track,panel,delegate}` are deployment copies checked by
`bin/sync-workflow-docs --check`. `/root/AGENTS.md` is
deliberately absent so Codex does not automatically load these Claude-specific
instructions; this README only maps the machinery.

## Layout

- `bin/` executors and panel tools (below)
- `tasks/` task/brief files sent to reviewers (main-agent-authored)
- `logs/` reviewer output, `.err` sidecars, my-review/arbitration records
- `templates/` starter task files (`review-task.md`, `fix-task.md`)
- `tests/` regression oracles for this tooling itself
- `track/` lightweight change-workflow convention + templates (`bin/track` CLI)
- `tracks/` the change artifacts themselves (proposal/design/tasks/verify + evidence)
- `workflow/` canonical Claude instructions and workflow skills (deployed copies live outside Git)
- `worktrees/` per-job isolated checkouts created by `delegate-codex` (gitignored)
- `reports/`, `review/`, `mimo-home/`, `quicklook/` project-specific areas

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
  isolated workspace. Both modes read [`bin/cursor-model`](bin/cursor-model);
  change that one model ID (or set `CURSOR_MODEL`) to switch models. Coverage
  follows the model family, not the Cursor transport. `PANEL_CURSOR_LEG=off`
  disables it in both dispatchers. Authenticate with `cursor-agent login`.
- `bin/subgrok` — Grok Build CLI, `review` and `explore`; both read their default
  model from [`bin/grok-model`](bin/grok-model). A model upgrade changes that one
  configuration line, not the adapter or panel; `GROK_MODEL` overrides one run.
  Uses an isolated runtime home and disposable snapshot with the source mounted
  read-only. Existing `~/.grok/auth.json` supplies session login; `XAI_API_KEY`
  explicitly selects API billing. Override with `GROK_MODEL`, `GROK_AUTH_FILE`,
  `GROK_TIMEOUT` (900 seconds), or `GROK_MAX_TURNS` (80). No chat fallback or fix
  mode. `PANEL_GROK_LEG=off` disables it in either panel. The report log contains
  assistant text only; `.stream.jsonl` and `.stream-summary.json` preserve tools,
  actual model, completion and reported usage. Timeout/turn-limit/error output
  remains partial evidence and never counts as completed review coverage.
- `bin/submimo-iso` — concurrency-safe submimo for two simultaneous
  driver agents (e.g. Claude + Codex).

All executors: `<tool> review TASK LOG REPO`. Output is evidence for the main
agent to verify, never a verdict to adopt.

## Delegation entry + judging guards

- `bin/delegate-codex` — the ONE entry for handing implementation work to the
  codex (GPT) leg, and the mechanical half of receiving gate ①. It refuses to
  dispatch (codex never starts) unless: an attack-log exists outside the repo,
  a `--protect` judging list is given, and the attack-log carries the CURRENT
  `oracle-sha256:` of that judging surface (`--print-oracle-hash` emits the line).
  **Each job runs in its own git worktree by default** (`--no-isolate` opts out):
  `worktrees/<task>-<ts>` on branch `delegate/<same>`, created from the HEAD at
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
Model defaults live in `bin/*-model`; environment overrides are frozen per member.


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
  (default `logs/slice-<manifest>-<ts>/`); `status` is rebuilt from disk and
  `findings.jsonl` is append-only.
- `bin/subcodex <review|explore>` — GPT review leg on `codex exec`, model from
  [`bin/codex-model`](bin/codex-model) (`SUBCODEX_MODEL` overrides one run). A
  role-only leg (`PANEL_ROLE_LEG_SPECS`): never rotated into normal panel-review,
  because GPT is also the default implementation leg. Source repo read-only via
  `ro-repo-exec`, disposable snapshot, `--ignore-user-config --ephemeral`, prompt via
  stdin. Sub-agent tools are removed with a per-run model catalog override (feature
  flags alone do not remove them for gpt-6-astra) and checked offline with
  `codex debug prompt-input` before dispatch; web search is disabled.

Both stagger launches and the engine retries 429/5xx with bounded backoff.

## Tests (run before trusting any tooling change)

```bash
bash /root/aiwork/bin/rust-check-review-tooling   # THE runner: every suite below, one summary line
bash /root/aiwork/bin/rust-check-review-tooling --coverage-only   # just the "who is not covered" report
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
/root/aiwork/bin/submimo-review /root/aiwork/templates/review-task.md \
  /root/aiwork/logs/dry-run.log --repo /path/to/repo --git-diff --dry-run
```

The chat engine cannot read files by itself: use `--git-diff` / `--include`
(or the wrapper INCLUDE env vars) to attach context. An empty diff with
nothing attached triggers a loud BLIND-review warning.
