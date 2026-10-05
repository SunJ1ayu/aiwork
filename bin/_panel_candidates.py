"""Read-only candidate descriptions and explicit run-member resolution.

Adapter identity belongs to the shell roster; model defaults belong to the same
files the adapters read. No account probing or automatic selection happens here.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from _review_result import TOKEN_RE, cursor_model_family, leg_identity
from _aiwork_config import data_path, model as configured_model

BIN = Path(__file__).resolve().parent
# Config stem, override variable, modes, repository-reading modes, invocation prefix.
CAPABILITIES = {
    'submimo': ('mimo', 'MIMO_CLI_MODEL', ('review', 'explore'), ('review',), ''),
    'subdeepseek': ('deepseek', 'DEEPSEEK_MODEL', ('review', 'explore'), ('review', 'explore'), ''),
    'subglm': ('glm', 'ZHIPU_MODEL', ('review', 'explore'), ('review', 'explore'), 'go/'),
    'subkimi': ('kimi', 'KIMI_MODEL', ('review',), ('review',), ''),
    'subgemini': ('gemini', 'AGY_MODEL', ('review',), ('review',), ''),
    'subgrok': ('grok', 'GROK_MODEL', ('review', 'explore'), ('review', 'explore'), ''),
    'subcursor': ('cursor', 'CURSOR_MODEL', ('review', 'explore'), ('review', 'explore'), ''),
}


def roster():
    output = subprocess.check_output(
        ['bash', '-c', '. "$1/_panel-roster-lib.sh"; printf "%s\\n" "${PANEL_LEG_SPECS[@]}"', '_', str(BIN)],
        text=True)
    return [line.split('|') for line in output.splitlines()]


def health_rows():
    path = Path(os.environ.get('PANEL_STATE_DIR', str(data_path('logs/.panel-state')))) / 'health.tsv'
    if not path.exists():
        return {}
    return {row[0]: row[1:] for line in path.read_text().splitlines() if len(row := line.split('\t')) >= 3}


def describe(row, mode, cursor_model=None):
    name, family, adapter, chat, switch = row
    if name not in CAPABILITIES:
        raise ValueError(f'no capability description for {name}')
    stem, variable, modes, read_modes, prefix = CAPABILITIES[name]
    raw_model = configured_model(stem, cursor_model or os.environ.get(variable))
    model = prefix + raw_model
    identity = leg_identity(adapter, model)
    if name == 'subcursor':
        if identity is None:
            raise ValueError('Cursor requires an explicit known model family (no auto routing)')
        family = identity[0]
        name = 'subcursor.' + model
    elif identity is None or not TOKEN_RE.fullmatch(model) or not model.startswith(identity[1]):
        raise ValueError(f'model does not match adapter family: {adapter}')
    rows = health_rows()
    return {
        'id': 'subcursor@' + model if adapter == 'subcursor' else name,
        'name': name, 'family': family, 'adapter': adapter, 'switch': switch,
        'model': model, 'model_env': variable, 'model_value': raw_model,
        'modes': list(modes), 'reads_repository': mode in read_modes,
        'enabled': os.environ.get(switch, 'agent') == 'agent',
        'executable_available': os.access(BIN / adapter, os.X_OK),
        'health_history': rows.get(name),
        'quota_remaining': None,
        'account_scope': 'cursor-account' if adapter == 'subcursor' else adapter,
        'quota_pool': None,
    }


def select(members, mode):
    rows = {r[0]: r for r in roster()}
    selected = []
    seen = set()
    for member in members.split(','):
        base, sep, model = member.partition('@')
        if base not in rows or (sep and (base != 'subcursor' or not model)):
            raise ValueError(f'invalid member: {member!r}')
        candidate = describe(rows[base], mode, model if sep else None)
        if candidate['name'] in seen:
            raise ValueError(f'duplicate member: {member}')
        if mode not in candidate['modes']:
            raise ValueError(f'{member} does not support {mode}')
        if not candidate['enabled'] or not candidate['executable_available']:
            raise ValueError(f'{member} disabled or executable unavailable; explicit selection never falls back')
        seen.add(candidate['name'])
        selected.append(candidate)
    return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=('review', 'explore'), default='review')
    parser.add_argument('--adapter', choices=tuple(CAPABILITIES), help='show only this transport pool, e.g. subcursor')
    parser.add_argument('--discover-cursor', action='store_true', help='query CLI model IDs; not quota or login verification')
    parser.add_argument('--members', help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        if args.members is not None:
            for c in select(args.members, args.mode):
                # Pipe-separated data only. IDs/values cannot contain a delimiter or newline.
                print('|'.join(c[k] for k in ('name', 'family', 'adapter', 'switch', 'model_env', 'model_value', 'model')))
            return 0
        discovered = []
        if args.discover_cursor:
            output = subprocess.check_output(['cursor-agent', 'models'], text=True, timeout=30)
            output = re.sub(r'\x1b\[[0-9;]*m', '', output)
            discovered = [line.split()[0] for line in output.splitlines() if line.split() and cursor_model_family(line.split()[0])]
        candidates = []
        for row in roster():
            if args.adapter and row[0] != args.adapter:
                continue
            if row[0] not in CAPABILITIES:
                continue
            if args.mode not in CAPABILITIES[row[0]][2]:
                continue
            current = describe(row, args.mode)
            candidates.append(current)
            if row[0] == 'subcursor':
                candidates.extend(describe(row, args.mode, m) for m in dict.fromkeys(discovered) if m != current['model'])
        print(json.dumps({'mode': args.mode, 'candidates': candidates,
                          'availability': 'configured executables and past outcomes only; quota and authentication unverified'}, indent=2))
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f'panel-candidates: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
