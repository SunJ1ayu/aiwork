# Proposal: phase-c-review-pr

Implement the Phase C `review-pr` publisher for OpenDesign. It reviews the exact current PR head, produces the gate's structured review block using the shared ReviewLegResult parser, and posts as the scoped review App. Include `gh-app-token` in aiwork's `bin/`.

The owner supplied the interface and seven acceptance checks in `workflow-migration/phase-c-review-pr.md` on the fetched implementation branch. The authorized external write is one COMMENT review on OpenDesign PR #10 and the recheck label required by the plan. No approve or merge operation.
