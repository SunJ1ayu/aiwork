"""Fixed-order dispatch. The gate owns PASS qualification and merge decisions."""
from __future__ import annotations


def dispatch(read_state, identify, run, builder_family):
    state = read_state()
    head, policy_sha = state['head'], state['policy_sha']
    plan = state['plan']
    if not plan['order']:
        raise ValueError('project main policy has no review_dispatch order')
    excluded = set(state['excluded']) | {builder_family}
    completed = set(state['passes']) - excluded
    tried = set()
    attempts = []

    def refresh():
        value = read_state()
        if value['head'] != head:
            raise ValueError('PR head changed during dispatch; stop and rerun for the new head')
        if value['policy_sha'] != policy_sha:
            raise ValueError('main policy changed during dispatch; stop and rerun')
        return value

    for leg in plan['order']:
        state = refresh()
        passes = set(state['passes']) - excluded
        if len(completed) >= plan['target'] and len(passes) >= plan['minimum']:
            break
        try:
            family, model = identify(leg)
        except (ValueError, OSError) as exc:
            attempts.append(dict(leg=leg, ok=False, reason=str(exc)))
            continue
        if family in excluded or family in tried or family in completed:
            attempts.append(dict(leg=leg, family=family, skipped=True,
                                 reason='excluded builder family or already reviewed/tried family'))
            continue
        tried.add(family)
        outcome = run(leg, model, head)
        attempts.append(dict(leg=leg, family=family, **outcome))
        if outcome['ok']:
            completed.add(family)
        # A failed publication may nevertheless have reached GitHub. Read actual
        # current reviews before deciding whether another family is needed.
        state = refresh()
    state = refresh()
    passes = set(state['passes']) - excluded
    minimum_met = len(passes) >= plan['minimum']
    return dict(head=head, policy_sha=policy_sha, plan=plan, attempts=attempts,
                reviewed_families=sorted(completed), pass_families=sorted(passes),
                minimum_met=minimum_met, target_met=len(completed) >= plan['target'],
                missing_target=max(0, plan['target'] - len(completed)),
                next_step='等汇总' if minimum_met else '交业主', gate=state['gate'])
