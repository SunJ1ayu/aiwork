# track — lightweight change workflow (Comet artifacts, no state machine)

This is the **lightweight** install: it borrows Comet's durable, traceable
artifact chain and **drops** the rigid phase machine and the OpenSpec/Superpowers
dependency. The main agent keeps full judgment over prose and ordering; narrow
typed/evidence/archive safety gates fail closed where ambiguity is unsafe.

## Unit

A **track** = one PR-sized feature/modification in an existing project. It lives
in `<project>/tracks/<name>/` with five artifacts:

| File | What | When to write |
|---|---|---|
| `proposal.md` | what & why: goal, motivation, scope, non-goals | at the start of a non-trivial track |
| `design.md` | how: approach, trade-offs, alternatives, test strategy (oracle) | when there's a real design choice; **panel-explore hook** here |
| `tasks.md` | task checklist + `base-ref` | when breaking the work down |
| `decision.json` | typed machine facts: impact, uncertainty, premise evidence, execution plan, outcome | scaffolded as null; fill before a real dispatch and at final arbitration |
| `verify.md` | what was checked + arbitrated verdict | before calling it done; **panel-review hook** here |

On close: `track archive <name>` moves the folder to `tracks/archive/`. It **refuses**
if `verify.md` is missing or `decision.json.outcome.verdict` is null/invalid — archiving
means "this is done", and done without an arbitrated outcome means the judgment was
never made. Superseded work still archives with `ARCHIVED-SUPERSEDED`; do not stamp a
fake `PASS`. Tracks created before `decision.json` remain on the legacy Markdown verdict
path; they are not backfilled or guessed.

## Typed machine facts (2026-08-21)

`decision.json` is the only machine source for current decisions. Markdown keeps reasons,
findings and trade-offs; it does not copy `Verdict:`, `lane:` or `派给:` fields. Missing and
unknown are JSON `null`, never silently `false`, `[]`, self risk or zero cost.

The validator has three narrow modes, not a workflow state machine:

```
track-record validate --phase shape tracks/<name>     # schema/types; null is legal
track-record validate --phase dispatch tracks/<name>  # decisions + hand-written cross rules
track-record validate --phase archive tracks/<name>   # dispatch rules + final outcome
```

Known high-impact factors (new write surfaces, permissions, auth, money, data consistency,
migrations and control boundaries) mechanically require `impact.level=high`. High design
uncertainty requires `premise_attack.status=done` and a durable in-track evidence file.
Every block prints rule/path/actual/expected. The commit hook checks the staged snapshot,
so a later working-copy edit cannot answer for the commit being made. Rules are hand-written
and tested; an LLM does not compile this control plane from prose.

## Machine evidence (2026-08-08)

判据结果**由机器写,不由我转述**。用 `runlog` 代跑,它把输出连同
「哪个 commit / 工作树脏不脏 / 退出码几」落进 `tracks/<name>/evidence/`,
并打印一行**收据行**粘进 verify.md:

```
runlog -t <track> [-n <slug>] -- <判据命令>     # 退出码原样透传
```

`track-guard` 规矩5 / `track archive` 会查:**每次提交**——粘的收据行必须与收据文件
**逐字节相同**(5a,行首行尾的 markdown 装饰会先剥掉);**归档那一次**——最后一份收据
必须被引用、**跑红的那几遍一份都不许藏**(5b),一份收据都没有要写
`- 无机器证据:<理由>`(5c),收据必须进 git(5d)。
「归档那一次」= 这次提交把 verify.md **搬进/新建进** `tracks/archive/`(git 状态 A 或 R);
改一份早已归档的工件不算,那样会误伤历史文件。

出处:08-05 我写「python 866/0」,听起来完美 —— 实际上回归用的解释器缺依赖,
一整块闸被整块 SKIP,汇总照印 OK。**汇总会撒谎,细节不会。**
⚠️ 强度只到「堵顺手四舍五入」,**堵不住蓄意伪造**(手改收据文件即可)。别高估它。

## Evidence lifetime — the `[仓外不承重]` marker (2026-08-13)

Artifacts live as long as the repo. Session scratch dirs (`/tmp/claude-0/<session>/scratchpad`,
`$TMPDIR`) die with the session. A prose citation stitches the two together with a
plain path string that **carries no lifetime guarantee and does not error when it breaks** —
the sentence still reads fine, so a checkable artifact silently degrades into a self-report.
Measured 2026-08-13: 22 of 348 track md files carried such a reference; ~9 were load-bearing
(e.g. "自审全文在 scratchpad 的 my-review" — a file whose whole purpose was proving
the self-review predated the panel).

`track archive` therefore scans every `*.md` under the track being archived and refuses to
archive any line mentioning `/tmp/` (literal), `scratchpad` (case-insensitive) or `TMPDIR`
(word). Two ways forward, and **only these two**:

1. **Move the evidence into the repo** (`evidence/…`) and rewrite the citation to the in-repo
   path. The correct fix removes the trigger by itself. If the moved file is byte-identical to
   something already in git, cite the commit instead (`git show <commit>:<path>`) rather than
   storing a second copy.
2. **Mark the line `[仓外不承重]`** — per line, never a blanket "I checked" note.

**Semantics of the marker — read this before using it.** It means *"I judged this line to be
non-load-bearing"*. It is a claim by the author, not a fact the gate verified: pasting it onto
every line will pass the gate. That is the same acknowledged range limit as 规矩5a
(which cannot stop a hand-edited receipt either). The only backstop is that the marker lands
in the git diff, where 闸③ (亲读 diff) can see it. **Marking a load-bearing citation is a
judgment error, and it is attributable.**

Why archive-time only, never pre-commit: citing scratchpad *while the work is live* is normal —
the file still exists. The claim only has to hold when you declare the work done. Checking it at
commit time would be noise on active work, and a noisy guard stops being believed.

Known range limits (do not pretend otherwise): `$(mktemp -d)`, URL-encoded paths, and paths that
reach a temp dir through a stable symlink are **not** caught — the gate never resolves paths.
Bare `/tmp` with no trailing slash is not caught either. Fenced code blocks *are* scanned, so a
pasted terminal transcript containing a temp path needs a marker (which edits the transcript) —
accepted for now, revisit with a block-level exemption if it actually bites.

## Commands

```
track new <name> [project-dir]      # scaffold tracks/<name>/ (default: cwd)
track archive <name> [project-dir]  # -> tracks/archive/<name>/
track list [project-dir]            # active + archived
track-record validate --phase dispatch tracks/<name>
runlog -t <name> -- <cmd>           # 跑判据并把收据落进 tracks/<name>/evidence/
```

## What's deliberately NOT here

- No guard scripts forcing build→verify→archive order. **Narrow exceptions**:
  typed dispatch requires complete decisions; archiving requires a filled-in outcome
  (legacy tracks keep the old Markdown verdict check) and machine evidence that
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
- **verify.md → panel-review**, with the budget from `decision.json.impact.level`:
  `self=0`, `standard=1`, `high=2` external review legs. High rotates healthy,
  cross-family legs; failure/degradation/conflict may add one spare. `--all` is explicit
  for exceptional judging/sandbox/permission control surfaces. Build/test pass stays mechanical.
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
