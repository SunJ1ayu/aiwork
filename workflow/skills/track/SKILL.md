---
name: track
description: Lightweight, traceable change workflow for a PR-sized unit of work in an existing project — proposal→design→tasks→verify→archive artifacts plus narrow mechanical guards. Use when the user says /track, "起一个 track", "建个 track / change", "新建/归档 track", or wants a durable artifact trail for a feature/modification (not for scaffolding a brand-new project). The artifact depth remains judgment-based; safety and evidence guards are real.
---

# track — lightweight change workflow

A **track** = one PR-sized feature/modification in an existing repo, with a
durable artifact trail under `<project>/tracks/<name>/`. This skill is a guide
the main agent (sole arbiter) follows **with judgment**. Artifact depth is not a
rigid state machine, but `track-guard`, commit trailers, evidence checks and safe
archive behavior are mechanical gates, not optional prose. Small/obvious work
may skip creating a track entirely; once a track exists, its guards tell the
truth about that track. Full convention: `aiwork/track/CONVENTION.md`.

CLI helper (assume `/root/aiwork/bin` is on PATH, else call by full path):

```
track new <name> [project-dir]      # scaffold tracks/<name>/ from templates
track archive <name> [project-dir]  # -> tracks/archive/<name>/
track list [project-dir]            # active + archived
track preflight <name> [project-dir] # read-only archive pre-check; run before EVERY review round
track-record ledger --repo <project-dir> --format json|markdown
```

## Routing on invocation

- `/track <description>` and no active track → **new track** (flow below).
- `/track` with no description → run `track list`, ask which to resume or start new.
- An active `tracks/<name>/` already exists → ask: continue it or start a new one.
- `/track archive [name]` → `track archive`; `/track list` → `track list`.

## Resume an interrupted track (reconstruct from disk, NOT conversation history)

A track has no phase pointer — the artifacts on disk ARE the state, and they survive
across sessions. On resume (e.g. user comes back and types `/track`), do NOT trust
conversation history; reconstruct from the folder:

1. `track list` → find active tracks; pick the one named, or if one active track,
   confirm it; if several, ask which.
2. Read `tracks/<name>/`: which artifacts are filled, validate `decision.json` shape,
   count remaining `[ ]` in tasks.md (`grep -c '\- \[ \]'`), and inspect
   `decision.json.outcome.verdict` (legacy tracks still use the Markdown verdict).
3. Infer the resume point (first match wins):
   - design.md not yet filled with a real direction → still in **design**.
   - tasks.md has unchecked `[ ]` → in **build**; next = first unchecked task.
     Cross-check committed work since `base-ref` with `git log --oneline <base-ref>..HEAD`.
   - all tasks `[x]` but typed outcome is null → in **verify**.
   - typed outcome = PASS → offer `track archive <name>`.
4. Run `git status` for uncommitted work (lightweight dirty-worktree check); if the
   diff implies progress not reflected in the artifacts, surface it and ask before
   assuming it's done.
5. **State the inferred resume point and the next step, and confirm with the user**
   before continuing. Resume is inference, not a deterministic pointer — so verify
   it rather than silently barreling ahead.

## New-track flow (apply with judgment; skip steps that don't earn their keep)

1. **Name + scaffold.** Derive a kebab-case name from the description, confirm it,
   run `track new <name>` (default project = cwd). This drops four Markdown artifacts
   plus `decision.json`, with date and git `base-ref` filled in.
2. **proposal.md** — draft goal / motivation / scope / non-goals. Keep it light;
   skip for trivial work. If the track will be reviewed, write the **acceptance boundary and
   round budget** here at kickoff (default 2 substantive rounds) — see panel skill 4b.
3. **design.md — check the plan before building it.** Apply panel skill **4c**,
   the single detailed protocol: start with the user's actual goal, observed behavior,
   proposed behavior change, and assumptions. Novel required steps/default actions/failure
   paths, contract changes or costly reversal require an independent different-family
   challenge even if there is only one proposed design. Resolve critical unknowns with
   the smallest useful experiment. Local reversible changes under a verified contract
   stay lightweight; genuine direction forks may use `panel-explore`.
   Save your OWN direction before reading outside reports; keep it out of their input.
   Record findings, fact checks and unresolved assumptions in design/evidence. Then write
   the implementation **test strategy (oracle)** — the main agent owns it. An oracle attack
   about bad implementations is not a substitute for challenging the goal-to-design translation.
4. **tasks.md** — break the work down. For bounded sub-tasks you may delegate to
   `submimo fix`: main agent writes the failing test (oracle) and commits it
   first, then hands the narrow file scope to submimo; oracle/test files are
   off-limits to it; verify with `git diff` they're untouched; cap ~2 retries
   then take it back. See main CLAUDE.md `submimo fix` rules.
5. **decision + verify (two independent judgments).** Before a real controller dispatch,
   classify the two orthogonal axes in `decision.json` and run
   `track-record validate --phase dispatch tracks/<name>`:
   - `impact-risk`: self / standard / high, with external-review budgets
     self=0, standard=1, high=2. Use `panel-candidates` then explicit `--members`; high requires at least two
     different families. Explicit selections never add a spare or silently fall back;
     legacy rotation remains available when no members are specified.
     Use explicit `panel-review --all` only for exceptional judging/sandbox/
     permission-control surfaces, not as the default meaning of high.
   - `design-uncertainty`: low / high, judged after step 3, not permission to skip it.
     High requires completed premise checks and durable evidence; low also permits
     `premise_attack.status=done` when a check was performed. Lightweight work can retain
     `not_required`. High implementation impact alone does not require full-pool planning.
   Record the planned Adapter/model there too (v1 Adapter enum:
   `main|submimo|delegate-codex|claude-worktree`); keep reasons and review findings in Markdown.
   **Before every review round run `track preflight <name>`** and fix its BLOCK items first
   (a fix on a non-exempt file after the review voids the binding and costs a round).
   Main agent reviews first and commits findings BEFORE reading any panel output. After the
   reports: verify → disposition each finding (must-fix / defer / reject / unverified) in
   verify.md → one fix list → re-review within the budget or finish. **Deferred findings stay
   in verify.md; they do not become a new track by default.** The full protocol lives in
   panel skill 4b/4c — not copied here. Then
   arbitrate one outcome into `decision.json` (PASS / BLOCK / NEEDS_MORE_INFO or
   ARCHIVED-SUPERSEDED). A panel verdict never auto-advances anything — the main agent
   is sole arbiter. Never copy these enums into verify.md as a second machine source.
6. **Archive.** On PASS, offer `track archive <name>`. Archive mechanically requires
   0 / 1 / 2 coverage-eligible distinct external model families for self / standard /
   high, all from one successful panel run and one subject digest, with no eligible
   PASS/BLOCK conflict. Legacy v1, UNKNOWN/NMI, timeout, degraded/incomplete evidence,
   cross-run aggregation, and an unbound panel cannot satisfy the budget.

## Cost-quality ledger

`track-record ledger` 是纯派生、零写入视图，只扫描 active/archive track 的 `decision.json` 与
`observations/*.json`。它不读 `verify.md` 自由文本、runlog receipt、review transcript 或 raw log；
因此删日志、归档 track、按原机械闸 sweep worktree 都不会让账本失忆。重复输入的 JSON 输出字节
稳定，适合留给后续 trial 比较。

账本把最终 `PASS`、controller/leg dispatch 次数、失败/降级、实际模型、耗时和可得 usage 放在
同一行，但不把 dispatch_count 解释成“返工轮数”。只有 PASS 且 execution/review coverage 完整的 track
进入 successful-cost 聚合；缺 event 的 PASS 单独列 missing。订阅拿不到 token/API 现金成本、
或历史 track 根本没有 typed facts 时都保留 `null/unknown`，绝不能补成 0，也不从旧 prose 猜。
planned/actual model 或 Adapter **可比较时**由 mismatch 明示，不相互覆盖；main 的 runlog 是验证
controller，不冒充实际执行 Adapter，所以该维度拿不到时保持 null。agent→chat 回落是第二次真实
dispatch，ledger 会在 degraded leg 之外另计一次 fallback dispatch。`observations/` 只准紧凑 JSON，
不能夹带 transcript/子目录/symlink；单文件最多 64 KiB，panel 腿数由运行时花名册决定、
不另抄固定上限。writer 写前与
reader/guard 共用同一 schema，未知敏感字段的 BLOCK trace 只报字段名、不回显内容。active 和
archive 的机器源每次 staged 改动都持续校验；archive 对 working/staged 两种路径都 fail closed。

## What this is NOT

Not a state machine. Prose depth and phase order remain judgment-based; the narrow
shape/dispatch/archive fact and safety gates are mechanical. Brainstorming is not mandatory.
If you catch yourself running ceremony on a one-line change,
stop and just do it. The artifacts exist to leave a trail, not to gate work.
