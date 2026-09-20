# track — lightweight change workflow (Comet artifacts, no state machine)

This is the **lightweight** install: it borrows Comet's durable, traceable
artifact chain and **drops** the rigid phase machine and the OpenSpec/Superpowers
dependency. The main agent keeps full judgment over prose and ordering; narrow
typed/evidence/archive safety gates fail closed where ambiguity is unsafe.

## Unit

A **track** = one PR-sized feature/modification in an existing project. It lives
in `<project>/tracks/<name>/` with five artifacts:

Track names are unique across the active + archive lifetime. Reusing an archived name is
rejected: otherwise a late delegate receipt for the old run could be imported into a new track.

| File | What | When to write |
|---|---|---|
| `proposal.md` | what & why: goal, motivation, scope, non-goals | at the start of a non-trivial track |
| `design.md` | goal-to-design check, assumptions/evidence, approach, trade-offs, oracle | before implementation; panel skill **4c** chooses check depth |
| `tasks.md` | task checklist + `base-ref` | when breaking the work down |
| `decision.json` | typed machine facts: impact, uncertainty, premise evidence, execution plan, outcome | scaffolded as null; fill before a real dispatch and at final arbitration |
| `verify.md` | what was checked + arbitrated verdict | before calling it done; **panel-review hook** here |

On close: `track archive <name>` moves the folder to `tracks/archive/`. It **refuses**
if `verify.md` is missing, `decision.json.outcome.verdict` is null/invalid, or PASS lacks
valid execution coverage — archiving
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
track-record ledger --repo . --format json             # read-only derived view
```

Ledger 只扫描 `decision.json` 与 `observations/*.json`；不解析 verify prose、receipt、raw log 或
transcript。legacy 与采不到的 usage 明示 `unknown/null`，PASS 但缺 execution coverage 的 track
进入 missing 清单而不是成功成本聚合。它不写数据库、索引或缓存，所以 worktree 清理与日志
retention 不会和持久账本打架。

`execution_plan.adapter` v1 只接受 `main|submimo|delegate-codex|claude-worktree`，拼错不能退化成
任意 token。main 的归档覆盖要求成功 runlog；delegate 还要求 execution + 至少一次成功 receive。
submimo/claude 尚无统一 controller 用量接口，所以可完成归档，但 ledger 明示 coverage missing，
不进入 successful-cost 聚合。`observations/` 是严格白名单目录：只准直接的 100644 JSON 事件，
不准 transcript、子目录或 symlink。CLI 归档和手工 staged rename 都校验 staged decision、
staged observations 与 staged verify，working copy 不能替本次提交应试。

### 评审证据绑定实际交付内容(`decision.json.schema_version = 2`)

`schema_version: 2` 的 track 归档时,除了家族覆盖,还要求那轮评审**审的就是现在要交的东西**。
每条腿在自己的进程里算一份交付指纹(整仓内容,按下面的收口清单归一化),写进
`subject.delivery` 并进入 subject digest;归档闸重算一遍再比。对不上就 BLOCK,
提示里写着 `rerun panel-review after content changes`。

**评审之后还能改的,只有收口件**:本 track 的 `verify.md`、`tasks.md` 的勾选状态、
`decision.json` 的 `outcome`、严格命名的机器收据(`evidence/<UTC>-<NN>-<slug>.txt`
且内容确实是 runlog 收据)、`observations/*.json`,以及归档那一次的目录搬迁。
**别的都承重** —— 源码、设计、普通 evidence、track 里的 oracle、风险字段、任务正文,
以及文件模式与符号链接(收口件也不例外:`verify.md` 改成可执行或软链一样算改动)。
所以顺序是:**先把实现改完,再派评审**;评审后改了源码就得重派一轮,这不是 bug。

`schema_version: 1` 的旧 track 保持 `legacy-unbound`(历史不按今天的源码重判),
但 v2 不许退回 v1。已归档的 track 重新校验时,比的是**它当初归档那个提交的树**,
不是今天的工作区。没有迁移命令:模板已经是 v2,在飞的旧 track 要么继续 legacy,
要么手改那一个整数(和 `outcome.verdict` 一样是手写字段)。

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

## Preflight — archive checks before the final review (2026-09-16)

`track preflight <name> [project-dir]` runs the archive checks that can be judged **before** the
final review, without changing anything, and sorts every item into one of four classes:

| class | meaning | typical |
|---|---|---|
| `BLOCK` | fixable now, archive would refuse | temp-dir citation in design.md; pasted receipt line with no receipt (5a); working ≠ staged; dirty/unmerged worktree; typed decision invalid; PASS already written without execution evidence |
| `PENDING` | only judgeable after the final review / arbitration / closeout records | `outcome.verdict` null; review coverage not yet bound to current content; receipts not yet cited (5b/5c) |
| `OK` | passed | |
| `ERROR` | the check itself did not run (helper missing, checker crashed) — never downgraded | |

Exit code: `2` ERROR/usage > `1` BLOCK > `3` only PENDING > `0` all OK. All seven checks always run
(decision / views / verify / receipts / ephemeral / destination / worktrees); one BLOCK does not hide
the rest. Rule classification lives once, in `track-record validate --phase preflight`; unknown rules
are BLOCK. **Zero persistent side effects** (no move, no worktree removal, no staging, no
decision/observation write, `GIT_OPTIONAL_LOCKS=0`). **Not a credential**: it leaves no marker and
`track archive` re-runs everything. Not covered: 5d (receipts committed) — that belongs to the
archive commit. Why it exists: a BLOCK on a non-exempt file found only at archive time voids the
review binding and costs a whole round (design-studio, 2026-09-16). What to do with review reports
afterwards (disposition → fix list → re-review or finish, round budget, deferrals do not become new
tracks) is the panel skill's 4b — one authoritative copy.

## Commands

```
track new <name> [project-dir]      # scaffold tracks/<name>/ (default: cwd)
track archive <name> [project-dir]  # -> tracks/archive/<name>/
track list [project-dir]            # active + archived
track preflight <name> [project-dir]  # read-only pre-check; run before every review round
track-record validate --phase dispatch tracks/<name>
runlog -t <name> -- <cmd>           # 跑判据并把收据落进 tracks/<name>/evidence/
```

## What's deliberately NOT here

- No guard scripts forcing build→verify→archive order. **Narrow exceptions**:
  typed dispatch requires complete decisions; archiving requires a filled-in outcome
  (legacy tracks keep the old Markdown verdict check) and machine evidence that
  matches byte-for-byte (2026-08-08, see above). Both guard the *content of the
  last field*, not the *order of the phases*. The machine does not require every
  prose artifact; that is not a waiver of the agent's design-check protocol (panel 4c).
- No blocking user-decision points at every transition.
- No "brainstorming cannot be skipped" rule. Work classified as lightweight under
  panel 4c can skip planning calls and elaborate artifacts. A single proposed direction
  or a small diff does not by itself establish that classification.

## Where the panels attach (the only two stations)

- **design.md → design checks before implementation**, per **panel skill 4c** (the single
  detailed protocol). Novel required steps/default actions/failure paths, contract changes
  or costly reversal require an independent different-family challenge; critical unknowns
  need an experiment. Genuine direction forks may expand to `panel-explore`. Local,
  reversible changes under verified contracts stay lightweight. A self-assigned low or Jev
  score cannot waive triggered checks. Main agent records its direction before outside
  reports, keeps that record out of their input, and records factual resolutions afterwards.
  Existing `premise_attack.status=done` + evidence can represent a completed check even
  with low uncertainty; no new schema or low-evidence gate is introduced. Evidence existence
  does not prove a sound design, and unresolved critical assumptions still need resolution.
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
