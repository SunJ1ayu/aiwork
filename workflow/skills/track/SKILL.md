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
truth about that track. Full convention: `/root/aiwork/track/CONVENTION.md`.

CLI helper (assume `/root/aiwork/bin` is on PATH, else call by full path):

```
track new <name> [project-dir]      # scaffold tracks/<name>/ from templates
track archive <name> [project-dir]  # -> tracks/archive/<name>/
track list [project-dir]            # active + archived
```

## Routing on invocation

- `/track <description>` and no active track → **new track** (flow below).
- `/track` with no description → run `track list`, ask which to resume or start new.
- An active `tracks/<name>/` already exists → ask: continue it or start a new one.
- `/track archive [name]` → `track archive`; `/track list` → `track list`.

## Resume an interrupted track (reconstruct from disk, NOT conversation history)

A track has no state file — the artifacts on disk ARE the state, and they survive
across sessions. On resume (e.g. user comes back and types `/track`), do NOT trust
conversation history; reconstruct from the folder:

1. `track list` → find active tracks; pick the one named, or if one active track,
   confirm it; if several, ask which.
2. Read `tracks/<name>/`: which artifacts are filled, count remaining `[ ]` in
   tasks.md (`grep -c '\- \[ \]'`), check whether verify.md has a verdict.
3. Infer the resume point (first match wins):
   - design.md not yet filled with a real direction → still in **design**.
   - tasks.md has unchecked `[ ]` → in **build**; next = first unchecked task.
     Cross-check committed work since `base-ref` with `git log --oneline <base-ref>..HEAD`.
   - all tasks `[x]` but verify.md has no verdict → in **verify**.
   - verify.md verdict = PASS → offer `track archive <name>`.
4. Run `git status` for uncommitted work (lightweight dirty-worktree check); if the
   diff implies progress not reflected in the artifacts, surface it and ask before
   assuming it's done.
5. **State the inferred resume point and the next step, and confirm with the user**
   before continuing. Resume is inference, not a deterministic pointer — so verify
   it rather than silently barreling ahead.

## New-track flow (apply with judgment; skip steps that don't earn their keep)

1. **Name + scaffold.** Derive a kebab-case name from the description, confirm it,
   run `track new <name>` (default project = cwd). This drops the four artifact
   skeletons with date and git `base-ref` filled in.
2. **proposal.md** — draft goal / motivation / scope / non-goals. Keep it light;
   skip for trivial work.
3. **design.md (judgment branch).** Decide: is this a *genuine open architecture
   fork* (several defensible directions, risk = tunnel vision)?
   - **Yes** → commit your OWN direction first (anti-anchoring), then run
     `panel-explore` (brief under `/root/aiwork/tasks/`), fold the spread into
     design.md, converge with the user. Do not collapse the spread prematurely.
   - **No** → just write the chosen direction. Do not spend a panel.
   Always capture the **test strategy (oracle)** here — the main agent owns it.
4. **tasks.md** — break the work down. For bounded sub-tasks you may delegate to
   `submimo fix`: main agent writes the failing test (oracle) and commits it
   first, then hands the narrow file scope to submimo; oracle/test files are
   off-limits to it; verify with `git diff` they're untouched; cap ~2 retries
   then take it back. See main CLAUDE.md `submimo fix` rules.
5. **verify.md (two independent judgments).** Run mechanical checks
   (build/test/secrets), then classify two orthogonal axes:
   - `impact-risk`: self / standard / high, with external-review budgets
     self=0, standard=1, high=2. High rotates two healthy, different model
     families; failure/degradation/conflict/NEEDS_MORE_INFO adds a spare.
     Use explicit `panel-review --all` only for exceptional judging/sandbox/
     permission-control surfaces, not as the default meaning of high.
   - `design-uncertainty`: low / high. High uncertainty triggers premise attack,
     independent dual planning or `panel-explore`; high implementation impact
     alone does not.
   Main agent reviews first and commits findings BEFORE reading any panel output,
   then arbitrates a single verdict (PASS / BLOCK / NEEDS_MORE_INFO). A panel
   verdict never auto-advances anything — the main agent is sole arbiter.
6. **Archive.** On PASS, offer `track archive <name>`.

## What this is NOT

Not a state machine. No phase is forced, no transition is blocked, brainstorming
is not mandatory. If you catch yourself running ceremony on a one-line change,
stop and just do it. The artifacts exist to leave a trail, not to gate work.
