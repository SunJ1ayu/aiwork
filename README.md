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
- `bin/subdeepseek` — DeepSeek official, review-only chat wrapper (formerly subsense) over the engine.
  Extra context via `DEEPSEEK_INCLUDE`.
- `bin/subglm` — Zhipu GLM, review-only chat wrapper over the engine.
  Extra context via `ZHIPU_INCLUDE`.
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

- `bin/panel-review --track NAME --risk self|standard|high TASK [REPO] [LOG_PREFIX]` —
  convergent review. Default high rotates two healthy model families; standard
  uses one and self uses none. Failure/degradation/conflict can add one spare;
  `--all` explicitly requests every available reviewer. Use `--no-track`
  explicitly when the review belongs to no typed active track. Main agent arbitrates.
  It exits non-zero only if every actually dispatched leg fails; failed legs
  keep a `.err` sidecar.
- `bin/panel-explore BRIEF [REPO] [LOG_PREFIX]` — divergent: three model
  families each propose ONE direction; no verdict by design.

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
