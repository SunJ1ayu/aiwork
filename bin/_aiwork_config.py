"""One reader for machine settings; env files are data, never shell programs."""
from __future__ import annotations

import os
from pathlib import Path
import re


class ConfigError(ValueError):
    pass


def config_dir() -> Path:
    return Path(os.environ.get('AIWORK_CONFIG_DIR') or Path.home() / '.config/aiwork').expanduser()


def setting_path(name: str) -> Path:
    return config_dir() / name


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
