# Verify: phase-c-review-pr

## Oracle and local checks

The oracle was committed before implementation and failed because `bin/review-pr` did not exist.

runlog: oracle-red rc=1 commit=d0ffb4f dirty=yes at=2026-09-29T10:57:07Z file=tracks/phase-c-review-pr/evidence/20260929T105707Z-01-oracle-red.txt

After implementation, its four checks pass. The shared ReviewLegResult tests pass 20/20 and the subcodex adapter oracle passes 41/41 in an isolated network namespace. `bin/gh-app-token` is byte-identical to the installed adapter; shell syntax and `git diff --check` pass.

runlog: review-pr-green rc=0 commit=87bc034 dirty=yes at=2026-09-29T11:30:10Z file=tracks/phase-c-review-pr/evidence/20260929T113010Z-01-review-pr-green.txt

## Phase C acceptance on OpenDesign PR #10

1. `subcodex --dry-run`: pass. Exactly one JSON block, all required fields, head `58d9bea2000578af8ac431cc887b2511bd92885e`, family `openai`, model `gpt-6-sol`, completeness `complete`, eight changed files. Its independent verdict was BLOCK.
2. `subdeepseek --dry-run`: model ran, but the second HEAD read differed from the reviewed head. The command exited nonzero without printing a body; family output is therefore unverified.
3. Anthropic/unlisted leg refusal: pass; `subclaude` was rejected before network/model use.
4. JSON fence sanitization: pass in oracle; a model JSON fence becomes text, leaving exactly one machine JSON block.
5. Changed HEAD: pass in a real race during the DeepSeek dry-run; command exited nonzero and did not post.
6. Live COMMENT review and shadow check: not run because the head changed. Also, the PR introduces the gate workflows for the first time; the base branch lacks them, so a shadow rerun on this PR cannot be expected before bootstrap deployment. The proposed policy's gate App ID is null.
7. Failed model/no review: not run against GitHub after the stale-head stop; local failure check passes.

No review was posted. No PR was approved or merged. Acceptance remains incomplete and this track stays active. The owner requested stopping on unexpected results; no further GitHub operations were made after the stale-head result.
