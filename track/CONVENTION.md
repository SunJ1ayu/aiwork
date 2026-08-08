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

On close: `track archive <name>` moves the folder to `tracks/archive/`. It **refuses**
if `verify.md` is missing or its `Verdict:` line is still the template placeholder —
archiving means "this is done", and done without an arbitrated verdict means the
judgment was never made. Superseded work still archives: write the real outcome
(e.g. `ARCHIVED-SUPERSEDED`), just don't stamp a `PASS` on it.

## Machine evidence (2026-08-08)

判据结果**由机器写,不由我转述**。用 `runlog` 代跑,它把输出连同
「哪个 commit / 工作树脏不脏 / 退出码几」落进 `tracks/<name>/evidence/`,
并打印一行**收据行**粘进 verify.md:

```
runlog -t <track> [-n <slug>] -- <判据命令>     # 退出码原样透传
```

`track-guard` 规矩5 / `track archive` 会查:粘的收据行必须与收据文件**逐字节相同**(5a);
归档时**最后一份**收据必须被引用(5b);一份收据都没有要写
`- 无机器证据:<理由>`(5c);收据必须进 git(5d)。

出处:08-05 我写「python 866/0」,听起来完美 —— 实际上回归用的解释器缺依赖,
一整块闸被整块 SKIP,汇总照印 OK。**汇总会撒谎,细节不会。**
⚠️ 强度只到「堵顺手四舍五入」,**堵不住蓄意伪造**(手改收据文件即可)。别高估它。

## Commands

```
track new <name> [project-dir]      # scaffold tracks/<name>/ (default: cwd)
track archive <name> [project-dir]  # -> tracks/archive/<name>/
track list [project-dir]            # active + archived
runlog -t <name> -- <cmd>           # 跑判据并把收据落进 tracks/<name>/evidence/
```

## What's deliberately NOT here

- No guard scripts forcing build→verify→archive order. **Two exceptions**:
  archiving requires a filled-in verdict (2026-08-04) and machine evidence that
  matches byte-for-byte (2026-08-08, see above). Both guard the *content of the
  last field*, not the *order of the phases* — you can still skip
  proposal/design/tasks entirely.
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
