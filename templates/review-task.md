# Task
Review the current change for risk.

# Round
- Round: <1 = full review | 2 = re-review> of a budget of <2>
- Acceptance boundary: <what this change promises; findings are judged against it>
- Re-review only — fixes to verify: <last round's fix list, with file:line>.
  New findings are still welcome; blocking ones will be handled, not deferred.

# Scope
- Read-only review.
- Do not modify files.
- Do not delete files.
- Do not run `git push`.
- Do not access production systems.
- Do not install dependencies.

# Focus Areas
- Correctness regressions
- Security or permission issues
- Data loss or state inconsistency
- Money/payment/order risks if applicable
- Missing tests

# Required Output
Conclusion: PASS / BLOCK / NEEDS_MORE_INFO

Findings:
- Severity: CRITICAL / HIGH / MEDIUM / LOW
- File:
- Line:
- Issue:
- Evidence:
- Is this introduced by the current change:
- Does it break the current promise, or only fail to catch a hypothetical future implementation:
- Suggested fix:

Coverage:
- Reviewed context:
- Important context not available:
