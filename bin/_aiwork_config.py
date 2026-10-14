"""One reader for machine settings; env files are data, never shell programs."""
from __future__ import annotations

import os
from pathlib import Path
import re


class ConfigError(ValueError):
    pass


def config_dir() -> Path:
    return Path(os.environ.get('AIWORK_CONFIG_DIR') or Path.home() / '.config/aiwork').expanduser()


def data_dir() -> Path:
    # Provider wrappers override XDG_* for their own isolation. Keep aiwork's
    # machine data stable across those child environments.
    # The directory itself must already exist. Creating it here would turn a
    # missing external disk into a same-named directory on the internal disk.
    configured = Path(os.environ.get('AIWORK_DATA_DIR') or Path.home() / '.local/share/aiwork').expanduser()
    try:
        path = configured.resolve()
    except (OSError, RuntimeError) as exc:
        raise ConfigError(_missing_data_dir(configured)) from exc
    if not path.is_dir():
        raise ConfigError(_missing_data_dir(path))
    return path


def _missing_data_dir(path: Path) -> str:
    return (f'{path}: 数据目录不存在或不是目录。'
            '新机器第一次用时自己手动建一次;如果它在外接盘上，先确认盘已经挂好')


def data_path(name: str = '') -> Path:
    # 不查 DATA_ENTRIES。没登记的名字也返回路径，运行时不因为名字报错。
    return data_dir() / name


# 数据目录里应该有哪些东西。只在这里登记。
# kind 只取 工作产物 / 运行目录 / 其他。credentials 表示这个目录里可能放凭证。
DATA_ENTRIES = (
    {
        'name': 'logs',
        'purpose': '任务、评审和委托留下的日志，包括失败记录。',
        'kind': '工作产物',
        'credentials': False,
    },
    {
        'name': 'worktrees',
        'purpose': 'delegate-codex 为每个任务建的独立检出。',
        'kind': '运行目录',
        'credentials': False,
    },
    {
        'name': 'explore',
        'purpose': '发散时每条腿的最后一条消息。',
        'kind': '工作产物',
        'credentials': False,
    },
    {
        'name': 'kimi-review-home',
        'purpose': 'Kimi 评审的运行期 home，含从种子同步的配置和本机凭证。',
        'kind': '运行目录',
        'credentials': True,
    },
    {
        'name': 'mimo-review-home',
        'purpose': 'MiMo 评审的运行期配置目录。',
        'kind': '运行目录',
        'credentials': False,
    },
    {
        'name': 'mimo-home',
        'purpose': 'submimo-iso 给每个 agent 的隔离 home，会从本机拷入凭证。',
        'kind': '运行目录',
        'credentials': True,
    },
    {
        'name': 'tasks',
        'purpose': '交给评审和委托的任务书。',
        'kind': '工作产物',
        'credentials': False,
    },
    {
        'name': 'attack-logs',
        'purpose': '委托前对判据的攻题记录。',
        'kind': '工作产物',
        'credentials': False,
    },
)


def setting_path(name: str) -> Path:
    return config_dir() / name


_LINE = re.compile(r'(?:export[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)\Z')
_TOKEN = re.compile(r'''[^"'#\s]+''')


def _exact_value(token: str) -> str | None:
    """Return the value, '' when it is empty, or None when the token is not exact."""
    if token == '':
        return ''
    if len(token) >= 2 and token[0] == token[-1] and token[0] in {'"', "'"}:
        inner = token[1:-1]
        if inner == '':
            return ''
        return inner if _TOKEN.fullmatch(inner) else None
    return token if _TOKEN.fullmatch(token) else None


def _assignments(filename: str) -> tuple[Path, list[tuple[int, str, str]]]:
    """Every non-comment line is one exact assignment. Nothing is stripped or sourced."""
    path = setting_path(filename)
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise ConfigError(f'{path}: cannot read') from exc
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError as exc:
        line = raw[:exc.start].count(b'\n') + 1
        raise ConfigError(f'{path}:{line}: file is not UTF-8') from exc
    rows: list[tuple[int, str, str]] = []
    seen: dict[str, int] = {}
    for number, raw_line in enumerate(text.splitlines(), 1):
        line = raw_line.lstrip(' \t')
        if not line or line.startswith('#'):
            continue
        match = _LINE.fullmatch(line)
        if match is None:
            raise ConfigError(f'{path}:{number}: invalid setting')
        name, token = match.group(1), match.group(2)
        value = _exact_value(token)
        if value is None:
            raise ConfigError(f'{path}:{number}: invalid setting')
        if value == '':
            raise ConfigError(f'{path}:{number}: empty {name}')
        if name in seen:
            raise ConfigError(f'{path}:{number}: duplicate {name}')
        seen[name] = number
        rows.append((number, name, value))
    return path, rows


def setting_value(filename: str, variable: str) -> str:
    """Read one assignment from a settings file. Lines are data, never sourced."""
    path = setting_path(filename)
    try:
        _, rows = _assignments(filename)
    except ConfigError as exc:
        if str(exc) == f'{path}: cannot read':
            raise ConfigError(f'{path}: cannot read {variable}') from exc
        raise
    for _, name, value in rows:
        if name == variable:
            return value
    raise ConfigError(f'{path}: missing {variable}')


def model(leg: str, override: str | None = None) -> str:
    path = setting_path('models.env')
    try:
        _, rows_list = _assignments('models.env')
    except ConfigError as exc:
        if str(exc) == f'{path}: cannot read':
            raise ConfigError(f'{path}: cannot read model settings for leg {leg}') from exc
        raise
    rows = {}
    for number, name, value in rows_list:
        if not re.fullmatch(r'[a-z][a-z0-9_]*', name):
            raise ConfigError(f'{path}:{number}: invalid setting for leg {leg}')
        rows[name] = value
    if not rows.get(leg):
        raise ConfigError(f'{path}: missing model for leg {leg}')
    selected = override or rows[leg]
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*', selected):
        raise ConfigError(f'{path}: invalid model for leg {leg}')
    return selected


def apps_dir() -> Path:
    return Path(os.environ['AIWORK_APPS_DIR']).expanduser() if os.environ.get('AIWORK_APPS_DIR') else setting_path('apps')


def app_key(configured: str) -> Path:
    """Relative keys live under the selected apps directory; absolute keys stay absolute."""
    path = Path(configured)
    return path if path.is_absolute() else apps_dir() / path


def model_family(adapter: str, selected: str) -> str:
    from _review_result import leg_identity
    identity = leg_identity(adapter, selected)
    if identity is None or not selected.startswith(identity[1]):
        raise ConfigError(f'model does not belong to adapter {adapter}')
    return identity[0]
