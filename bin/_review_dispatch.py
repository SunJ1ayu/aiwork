"""Fixed-order invocation; all review decisions come from the gate's state."""
from __future__ import annotations


def dispatch(read_state, identify, run, builder_family):
    state = read_state(builder_family)
    head, policy_sha = state['head'], state['policy_sha']
    plan = state['plan']
    if not plan['order']:
        raise ValueError('project default-branch policy has no review_dispatch order')
    tried = set()
    attempts = []

    def refresh():
        value = read_state(builder_family)
        if value['head'] != head:
            raise ValueError('PR head changed during dispatch; stop and rerun for the new head')
        if value['policy_sha'] != policy_sha:
            raise ValueError('default-branch policy changed during dispatch; stop and rerun')
        return value

    for leg in plan['order']:
        state = refresh()
        if state['target_met'] and state['minimum_met']:
            break
        try:
            family, model = identify(leg)
        except (ValueError, OSError) as exc:
            attempts.append(dict(leg=leg, ok=False, reason=str(exc)))
            continue
        if family in state['excluded'] or family in tried or family in state['reviewed_families']:
            attempts.append(dict(leg=leg, family=family, skipped=True,
                                 reason='excluded builder family or already reviewed/tried family'))
            continue
        tried.add(family)
        attempts.append(dict(leg=leg, family=family, **run(leg, model, head)))
        # Publication responses can be lost; only the next gate read confirms
        # whether a complete review actually reached this head.
    state = refresh()
    return dict(head=head, policy_sha=policy_sha, plan=state['plan'], attempts=attempts,
                reviewed_families=state['reviewed_families'], pass_families=state['pass_families'],
                minimum_met=state['minimum_met'], target_met=state['target_met'],
                missing_target=state['missing_target'], next_step=state['next_step'], gate=state['gate'])
