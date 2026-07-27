# aiwork

Multi-model review/execution tooling for the main agent (the frontier model
driving the session). The full workflow doctrine — when to use what, panel
protocol, safety rules — lives in `/root/CLAUDE.md` (symlinked as
`/root/AGENTS.md`); this README only maps the machinery.

## Layout

- `bin/` executors and panel tools (below)
- `tasks/` task/brief files sent to reviewers (main-agent-authored)
- `logs/` reviewer output, `.err` sidecars, my-review/arbitration records
- `templates/` starter task files (`review-task.md`, `fix-task.md`)
- `tests/` regression oracles for this tooling itself
- `track/` lightweight change-workflow convention + templates (`bin/track` CLI)
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

## Panel fan-out

- `bin/panel-review TASK [REPO] [LOG_PREFIX]` — convergent: all three
  reviewers in parallel on one diff/design; main agent arbitrates. Exits
  non-zero only if ALL THREE legs fail; failed legs keep a `.err` sidecar.
- `bin/panel-explore BRIEF [REPO] [LOG_PREFIX]` — divergent: three model
  families each propose ONE direction; no verdict by design.

Both stagger launches and the engine retries 429/5xx with bounded backoff.

## Tests (run before trusting any tooling change)

```bash
bash /root/aiwork/tests/test-review-tooling.sh   # 41-case oracle, V1..V7
python3 /root/aiwork/tests/test_submimo_retry.py # 429/5xx retry contract
```

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
