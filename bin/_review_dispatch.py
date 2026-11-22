"""Random family draw and bounded parallel execution; qualification belongs to the gate."""
from __future__ import annotations

from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from copy import deepcopy
from enum import Enum
from random import SystemRandom


class StopReason(str, Enum):
    """Dispatcher control-flow codes and their safe public descriptions."""
    def __new__(cls, code, description):
        obj = str.__new__(cls, code)
        obj._value_ = code
        obj.description = description
        return obj

    HEAD_CHANGED = ('head_changed', 'PR 提交已变化')
    POLICY_CHANGED = ('policy_changed', '项目策略已变化')
    STATE_UNAVAILABLE = ('state_unavailable', '无法确认当前关卡状态')
    DISPATCH_ERROR = ('dispatch_error', '派发流程中止，状态待核实')


class DispatchStopped(ValueError):
    """A known dispatcher stop, independent of any individual leg outcome."""
    def __init__(self, reason):
        self.reason = StopReason(reason).value
        super().__init__(self.reason)


def dispatch(read_state, identify, run, builder_family, *, shuffle=None, record=None):
    def read():
        try:
            return read_state(builder_family)
        except DispatchStopped:
            raise
        except (ValueError, OSError) as exc:
            raise DispatchStopped(StopReason.STATE_UNAVAILABLE) from exc

    state = read()
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
        value = read()
        if value['head'] != head:
            raise DispatchStopped(StopReason.HEAD_CHANGED)
        if value['policy_sha'] != policy_sha:
            raise DispatchStopped(StopReason.POLICY_CHANGED)
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

    # Attempt the draw/outcome record before starting models or replacements.
    # Only the main thread touches the gate/record; the caller handles write failures.
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
            emit()
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
