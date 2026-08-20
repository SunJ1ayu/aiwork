# Verify: ro-lock-teardown

- Date: 2026-08-20
- Verdict: PASS

## Mechanical checks

- [x] build / lint entrypoint passes
- [x] all local test suites pass
- [x] no credential contents entered the repository; login state was inspected by metadata only
- [x] final contaminated-environment run proves reviewer budget variables do not pollute default-value oracles

Machine receipts, copied byte-for-byte from `runlog`:

```text
runlog: oracle-red rc=1 commit=d20372b dirty=yes at=2026-08-19T15:11:30Z file=tracks/ro-lock-teardown/evidence/20260819T151130Z-01-oracle-red.txt
runlog: capabilities-red rc=1 commit=d20372b dirty=yes at=2026-08-19T15:11:42Z file=tracks/ro-lock-teardown/evidence/20260819T151142Z-01-capabilities-red.txt
runlog: implementation-green rc=1 commit=8b731a8 dirty=yes at=2026-08-19T15:37:57Z file=tracks/ro-lock-teardown/evidence/20260819T153757Z-01-implementation-green.txt
runlog: implementation-green-2 rc=0 commit=dc721fa dirty=yes at=2026-08-19T15:48:01Z file=tracks/ro-lock-teardown/evidence/20260819T154801Z-01-implementation-green-2.txt
runlog: panel-findings-red rc=1 commit=6ec2c61 dirty=yes at=2026-08-19T16:34:22Z file=tracks/ro-lock-teardown/evidence/20260819T163422Z-01-panel-findings-red.txt
runlog: panel-findings-green rc=0 commit=52a443c dirty=yes at=2026-08-20T00:55:52Z file=tracks/ro-lock-teardown/evidence/20260820T005552Z-01-panel-findings-green.txt
runlog: rereview-findings-green rc=0 commit=ed0e8f0 dirty=yes at=2026-08-20T02:01:08Z file=tracks/ro-lock-teardown/evidence/20260820T020108Z-01-rereview-findings-green.txt
runlog: final-contaminated-green rc=0 commit=559a4b6 dirty=yes at=2026-08-20T03:11:25Z file=tracks/ro-lock-teardown/evidence/20260820T031125Z-01-final-contaminated-green.txt
runlog: final-review-env-red rc=1 commit=113bf38 dirty=yes at=2026-08-20T04:41:38Z file=tracks/ro-lock-teardown/evidence/20260820T044138Z-01-final-review-env-red.txt
runlog: base-inside-source-red rc=1 commit=113bf38 dirty=yes at=2026-08-20T04:45:26Z file=tracks/ro-lock-teardown/evidence/20260820T044526Z-01-base-inside-source-red.txt
runlog: base-inside-source-green rc=0 commit=883b938 dirty=yes at=2026-08-20T04:46:35Z file=tracks/ro-lock-teardown/evidence/20260820T044635Z-01-base-inside-source-green.txt
runlog: final-three-leg-green rc=0 commit=9ef17bc dirty=yes at=2026-08-20T04:48:44Z file=tracks/ro-lock-teardown/evidence/20260820T044844Z-01-final-three-leg-green.txt
runlog: final-low-findings-red rc=1 commit=123a360 dirty=yes at=2026-08-20T05:20:14Z file=tracks/ro-lock-teardown/evidence/20260820T052014Z-01-final-low-findings-red.txt
runlog: final-closure-green rc=0 commit=8254dd5 dirty=yes at=2026-08-20T05:25:19Z file=tracks/ro-lock-teardown/evidence/20260820T052519Z-01-final-closure-green.txt
```

Red-run attribution:

- `oracle-red` / `capabilities-red`: helper and capability changes had not been implemented; the target
  assertions failed as designed. The same receipts also contain restricted-sandbox loopback failures,
  which are not counted as product findings.
- `implementation-green`: caught two real test-wiring mistakes (missing guard exit and a fixture without
  HEAD). The fixture/entry wiring was repaired without weakening the helper.
- `panel-findings-red`: first-panel regression fixtures made source index and ignore-channel drift red
  (`22/1`) before the production fix.
- `final-review-env-red`: with the owner's real `PANEL_KIMI_LEG=off` policy inherited, three fixtures
  that were intended to assert the default Kimi behavior went red (`423/3`). The product switch behaved
  correctly; the fixtures did not isolate the default they claimed to test.
- `base-inside-source-red`: the new path oracle proved the helper rejected an in-source workspace base
  only after `mkdir` had already created it (`23/1`), violating the no-source-write boundary.
- `base-inside-source-green`: preflight canonicalization now rejects that base before `mkdir`; the
  expanded workspace suite is `24/0`.
- `final-three-leg-green`: all 12 suites pass with the actual Kimi waiver plus contaminated XDG and
  reviewer-budget inputs; review-tooling is `426/0` and the expanded review-workspace suite is `24/0`.
- `final-low-findings-red`: two assertions derived from DeepSeek's final LOW findings fail (`425/2`):
  MiMo's child cwd is still the caller directory, and Kimi seed sync uses a fixed atomic temp name.
- `final-closure-green`: those two findings are repaired; all 12 suites pass under the same contaminated
  environment, with review-tooling `427/0` and review-workspace `24/0`.
- The earlier final receipt deliberately injects `ZHIPU_MAX_TURNS=80` and
  `DEEPSEEK_MAX_TURNS=25`; all 12 suites still pass, including review-tooling `426/0` and
  review-workspace `23/0`.

`dirty=yes` on these receipts includes the pre-existing untracked
`tasks/lock-teardown-adversarial.md`; this track did not overwrite, delete, or commit that user file.

## Review

- lane: **full** — this track changes write/permission and repository-integrity boundaries.
- delegated to: **main agent** — the work is primarily threat-model and oracle judgment; the main agent
  wrote and arbitrated the tests and fixes.
- main-agent first review: completed before panel dispatch in
  `/root/ro-lock-teardown-review-my-review.md` `[仓外不承重]`; it is not used as machine evidence.
- panel roster from the first re-review dispatch (verbatim):

```text
submimo=PASS subdeepseek=PASS(降级:回落聊天腿,只看得见 diff) subglm=PASS(降级:回落聊天腿,只看得见 diff) subkimi=FAIL(rc=1)
```

- final current-code panel roster from `123a360` (verbatim):

```text
submimo=PASS subdeepseek=PASS subglm=PASS subkimi=off
```

Independent agent reruns and arbitration:

- MiMo: `Conclusion: PASS` on the final panel; independently ran review-workspace `24/0` and
  review-tooling `426/0`, then found no unresolved code issue.
- DeepSeek agent: `Conclusion: PASS` on the final panel; independently checked staged/index fidelity,
  relative excludes, linked worktrees, unmerged-index fail-closed behavior, and all wrapper boundaries.
  Its two final LOW findings (MiMo child cwd and Kimi fixed temp name) were made red, repaired, and covered
  by `final-closure-green` (`427/0`, `24/0`).
- GLM agent: `Conclusion: PASS` on the final panel; independently ran both suites and the 12-suite entry,
  plus linked-worktree, unmerged-index, alternates, and concurrent-config probes. It reported no
  WARNING/BLOCK finding.
- Kimi: device authorization now succeeds in the actual isolated review HOME, and the model began
  reading the final repository. It then returned `403 You've reached your usage limit for this billing
  cycle` before producing a verdict. On 2026-08-20 the owner explicitly approved closing with
  MiMo/DeepSeek/GLM rather than waiting four days for quota refresh. The roster records Kimi as `off`,
  never as PASS.

Findings disposition:

- Fixed: staged/index fidelity, source `.git/info/exclude`, effective relative/absolute
  `core.excludesFile`, helper-failure zero-call coverage for all four wrappers, disposable-snapshot
  path self-containment, and atomic per-process-temp config replacement.
- Fixed: V8/V14/V21 default-value fixtures now clear inherited reviewer timeout/max-turn inputs.
- Fixed: default-Kimi fixtures clear an inherited `PANEL_KIMI_LEG`, OpenCode config parsing clears the
  reviewer's XDG/config overrides, and an in-source workspace base is rejected before any directory write.
- Fixed: MiMo review launches with its real cwd inside the disposable clone; Kimi seed config rewriting
  uses a per-process temporary name before atomic replace.
- No unresolved correctness or source-write finding remains from MiMo, DeepSeek, or GLM.

Arbitrated verdict: **PASS**. The final three completed independent reviews are PASS; every actionable
finding was repaired through a failing oracle and a post-fix 12-suite receipt. Kimi supplied no verdict
and is not counted as PASS; its absence is the owner's explicit quota waiver. The main agent accepts that
review-coverage deviation and finds no remaining correctness, source-write, or fail-open issue.

## Accepted deviations

- Full-lane policy normally uses four model legs. This close uses MiMo/DeepSeek/GLM plus main arbitration;
  Kimi is explicitly waived by the owner because its billing-cycle quota needs four days to refresh.
- The double scan detects drift across two complete reads but is not an atomic source freeze.
- Bash inside a disposable clone is not a host/network sandbox; same-uid/root adversaries can discover
  sibling temporary paths, and ignored dependency caches may be absent. These are documented non-goals.
- Concurrent `review` and `explore` runs sharing one MiMo/OpenCode config HOME use atomic replace but
  remain last-writer-wins. Either mode can inherit the other's Bash setting: `review` may lose Bash, while
  `explore` may gain Bash inside its disposable clone. Direct write tools remain denied in both modes, and
  Bash is already outside the documented host-sandbox guarantee. Per-invocation auth/config HOME isolation
  is deferred rather than expanded into this track.
- `_my-review-gate.sh` retains its pre-existing `/root/aiwork` convention. `panel-review` portability was
  fixed in scope; refactoring the separate gate is not required for the repository-isolation objective.
