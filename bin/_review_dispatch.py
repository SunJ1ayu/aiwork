"""Random family draw and bounded parallel execution; qualification belongs to the gate."""
from __future__ import annotations

from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from copy import deepcopy
from random import SystemRandom


def dispatch(read_state, identify, run, builder_family, *, shuffle=None, record=None):
    state = read_state(builder_family)
    head, policy_sha = state['head'], state['policy_sha']
    plan = state['plan']
    if not plan['order']:
        raise ValueError('project default-branch policy has no review_dispatch candidates')
    attempts, candidates = [], []
    families = set(state['excluded']) | {builder_family} | set(state['reviewed_families'])
    for leg in plan['order']:
        try:
            family, model = identify(leg)
        except (ValueError, OSError) as exc:
            attempts.append(dict(leg=leg, ok=False, reason=str(exc)))
            continue
        if family in families:
            continue
        families.add(family)
        candidates.append((leg, family, model))
    (shuffle or SystemRandom().shuffle)(candidates)
    draw = [item[0] for item in candidates]
    slots = state['missing_target']
    initial, reserve = draw[:slots], draw[slots:]
    running = {}

    def refresh():
        value = read_state(builder_family)
        if value['head'] != head:
            raise ValueError('PR head changed during dispatch; stop and rerun for the new head')
        if value['policy_sha'] != policy_sha:
            raise ValueError('default-branch policy changed during dispatch; stop and rerun')
        return value

    def report():
        outcomes = deepcopy(attempts)
        for attempt in outcomes:
            if attempt.get('status') == 'finished':
                attempt['confirmed'] = attempt['family'] in state['reviewed_families']
                if not attempt['confirmed']:
                    attempt['confirmation_reason'] = 'no complete review confirmed by gate'
        return deepcopy(dict(head=head, policy_sha=policy_sha, plan=plan,
                             draw=draw, initial=initial, reserve=reserve, attempts=outcomes,
                             **{key: state[key] for key in ('reviewed_families', 'pass_families',
                                'minimum_met', 'target_met', 'missing_target', 'next_step', 'gate')}))

    def emit():
        if record:
            record(report())

    # Publish the draw before starting any model; publish each outcome before
    # spending a replacement slot. Only the main thread touches the gate/record.
    emit()
    with ThreadPoolExecutor(max_workers=max(1, slots)) as pool:
        while True:
            state = refresh()
            pending = sum(attempt['family'] not in state['reviewed_families']
                          for attempt in running.values())
            available = max(0, state['missing_target'] - pending)
            while available and candidates:
                leg, family, model = candidates.pop(0)
                if family in state['excluded'] or family in state['reviewed_families']:
                    continue
                attempt = dict(leg=leg, family=family, status='running')
                attempts.append(attempt)
                running[pool.submit(run, leg, model, head)] = attempt
                available -= 1
            if not running:
                break
            done, _ = wait(running, return_when=FIRST_COMPLETED)
            for future in done:
                attempt = running.pop(future)
                try:
                    outcome = future.result()
                except (ValueError, OSError) as exc:
                    outcome = dict(ok=False, reason=str(exc))
                attempt.update(outcome, status='finished')
            state = refresh()
            emit()
    state = refresh()
    emit()
    return report()
