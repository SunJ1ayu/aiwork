# Design: phase-c-review-pr

- Use the existing `ADAPTER_IDENTITIES` map and ReviewLegResult emission/validation. The publisher does not interpret model verdict text.
- Acquire one short lived review App token in memory. Pass it only to GitHub API and Git fetch; never to the model process, command arguments, files, or output.
- Fetch the PR's head and base commits into a disposable Git repository. Verify checked out HEAD, compute merge base, and include complete diff and changed file list in the task. Stop if no changed files or the view is incomplete.
- `subcodex` receives the full snapshot. `subdeepseek` receives the merge base diff through the existing chat adapter. Treat its reported view accurately.
- Reject a failed leg, missing verdict, unknown model identity, or changed PR head before posting. Always post with event COMMENT. Add `aiwork:recheck` after successful posting so the shadow gate recalculates.
- Acceptance oracle is `tests/test_review_pr.py`, followed by two real dry runs, refusal probes, and one real PR #10 review.
