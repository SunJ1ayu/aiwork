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


_ASSIGNMENT = re.compile(r'^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$')


def setting_value(filename: str, variable: str) -> str:
    """Read one assignment from a settings file. Lines are data, never sourced."""
    path = setting_path(filename)
    try:
        content = path.read_text(encoding='utf-8')
    except OSError as exc:
        raise ConfigError(f'{path}: cannot read {variable}') from exc
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        match = _ASSIGNMENT.fullmatch(line)
        if match is None or match.group(1) != variable:
            continue
        value = match.group(2).strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        if value == '':
            raise ConfigError(f'{path}: empty {variable}')
        return value
    raise ConfigError(f'{path}: missing {variable}')


def model(leg: str, override: str | None = None) -> str:
    path = setting_path('models.env')
    try:
        content = path.read_text(encoding='utf-8')
    except OSError as exc:
        raise ConfigError(f'{path}: cannot read model settings for leg {leg}') from exc
    rows = {}
    for number, line in enumerate(content.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        name, separator, value = line.partition('=')
        name, value = name.strip(), value.strip()
        if not separator or not re.fullmatch(r'[a-z][a-z0-9_]*', name):
            raise ConfigError(f'{path}:{number}: invalid setting for leg {leg}')
        if name in rows:
            raise ConfigError(f'{path}:{number}: duplicate model for leg {name}')
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
