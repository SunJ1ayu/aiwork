# track — lightweight change workflow (Comet artifacts, no state machine)

This is the **lightweight** install: it borrows Comet's durable, traceable
artifact chain and **drops** the rigid phase machine, HARD-STOP guards, blocking
decision points, and the OpenSpec/Superpowers dependency. The main agent (Opus)
keeps full judgment; nothing forces a phase order.

## Unit

A **track** = one PR-sized feature/modification in an existing project. It lives
in `<project>/tracks/<name>/` with four artifacts:

| File | What | When to write |
|---|---|---|
| `proposal.md` | what & why: goal, motivation, scope, non-goals | at the start of a non-trivial track |
| `design.md` | how: approach, trade-offs, alternatives, test strategy (oracle) | when there's a real design choice; **panel-explore hook** here |
| `tasks.md` | task checklist + `base-ref` | when breaking the work down |
| `verify.md` | what was checked + arbitrated verdict | before calling it done; **panel-review hook** here |

On close: `track archive <name>` moves the folder to `tracks/archive/`.

## Commands

```
track new <name> [project-dir]      # scaffold tracks/<name>/ (default: cwd)
track archive <name> [project-dir]  # -> tracks/archive/<name>/
track list [project-dir]            # active + archived
```

## What's deliberately NOT here

- No guard scripts forcing build→verify→archive order.
- No blocking user-decision points at every transition.
- No "brainstorming cannot be skipped" rule. Small/obvious → just do it, skip the
  artifacts entirely (consistent with the main workflow's "don't spend a panel"
  rule). Write artifacts only when they earn their keep.

## Where the panels attach (the only two stations)

- **design.md → panel-explore**, *conditionally*: only a genuine open architecture
  fork (several defensible directions, risk = tunnel vision). Main agent commits
  its own direction first, then folds the spread in. Otherwise just write it.
- **verify.md → panel-review**, by lane: `full` (main + 全部评审腿:MiMo/DeepSeek/GLM/Kimi,
  现 4 条) for high-risk tracks — 新写口/权限/auth/钱/数据一致性/migration/cross-module 一律 full,
  针孔再薄也不打折; `fast` (main + submimo) 只给纯展示/纯逻辑改动; `self` (main only) for small.
  Build/test pass stays mechanical.
  Main agent is sole arbiter — a panel verdict never auto-advances anything.

## Build delegation

When delegating to `submimo fix`: main agent writes the failing test (oracle) and
commits it first, then hands the narrow file scope to submimo; oracle/test files
are off-limits to it; cap ~2 retries, then take it back. See main CLAUDE.md.

## When to reconsider the full Comet install

Flip to full Comet only if you find yourself actually skipping verification,
leaving no design trail, or unable to reconstruct why a past decision was made —
i.e. you want the rigidity to *force* discipline. As long as the panel workflow
already enforces judgment quality, the lightweight install is the better fit.
