# Verify: ro-lock-teardown

- Date: 2026-08-20
- Verdict: NEEDS_MORE_INFO

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
- All later receipts are green. The final receipt deliberately injects `ZHIPU_MAX_TURNS=80` and
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

Independent agent reruns and arbitration:

- MiMo: `Conclusion: PASS`; no code finding in its completed review.
- DeepSeek agent: `Conclusion: PASS`; found a Medium relative `core.excludesFile` resolution bug and
  a Low inherited-timeout oracle leak. Both were independently reproduced and fixed. It also confirmed
  unmerged-index fail-closed behavior and both full local suites.
- GLM agent: `Conclusion: PASS` on `aa9bc49`; independently confirmed relative excludes handling,
  linked worktrees, unmerged index rejection, `426/0`, and `23/0`. Its Low inherited-max-turn oracle
  leak and stale “mixed reset” task text were fixed in `559a4b6` and revalidated under polluted env.
- Kimi: device authorization now succeeds in the actual isolated review HOME, and the model began
  reading the final repository. It then returned `403 You've reached your usage limit for this billing
  cycle` before producing a verdict. Repeating the call cannot add review evidence until quota refreshes.

Findings disposition:

- Fixed: staged/index fidelity, source `.git/info/exclude`, effective relative/absolute
  `core.excludesFile`, helper-failure zero-call coverage for all four wrappers, disposable-snapshot
  path self-containment, and atomic per-process-temp config replacement.
- Fixed: V8/V14/V21 default-value fixtures now clear inherited reviewer timeout/max-turn inputs.
- No unresolved correctness or source-write finding remains from MiMo, DeepSeek, or GLM.

Arbitrated verdict: **NEEDS_MORE_INFO**. The implementation and mechanical evidence are green, and the
three completed independent reviews are PASS after their findings were repaired. However, the selected
full lane requires all four review legs. Kimi produced no verdict because the account quota is exhausted,
so this track remains active and must not be archived as PASS. Once quota refreshes, rerun the full panel
from the then-current HEAD, arbitrate any Kimi finding, and replace this verdict with the actual result.

## Accepted deviations

- The double scan detects drift across two complete reads but is not an atomic source freeze.
- Bash inside a disposable clone is not a host/network sandbox; same-uid/root adversaries can discover
  sibling temporary paths, and ignored dependency caches may be absent. These are documented non-goals.
- Concurrent `review` and `explore` runs sharing one MiMo/OpenCode config HOME use atomic replace but
  remain last-writer-wins. The only observed direction is loss of Bash capability (safe failure / reduced
  availability), because both modes deny direct write tools. Per-invocation auth/config HOME isolation is
  deferred rather than expanded into this track.
- `_my-review-gate.sh` retains its pre-existing `/root/aiwork` convention. `panel-review` portability was
  fixed in scope; refactoring the separate gate is not required for the repository-isolation objective.
