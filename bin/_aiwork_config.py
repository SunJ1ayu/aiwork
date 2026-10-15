"""One reader for machine settings; env files are data, never shell programs."""
from __future__ import annotations

import os
from contextlib import closing, contextmanager
from datetime import datetime, timezone
import errno
from pathlib import Path
import re
import stat
import sys
import time


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
# kind 只取 工作产物 / 运行目录 / 其他。数据目录不放凭证。
# 每次运行的产物各占登记项下第一层的一个单位，只由创建它的那次运行写入；不共用多次运行的容器。
DATA_ENTRIES = (
    {
        'name': 'logs',
        'purpose': '任务和评审留下的日志。',
        'kind': '工作产物',
        'keep_days': 60,
    },
    {
        'name': 'review-failures',
        'purpose': '每次评审失败的独立诊断档案。',
        'kind': '工作产物',
        'keep_days': 60,
    },
    {
        'name': 'worktrees',
        'purpose': '执行方开 PR 时保留改动的独立工作树。',
        'kind': '工作产物',
        'keep_days': None,  # 按 workflow/CLAUDE.md 的工作树流程清理，不按天数。
    },
    {
        'name': 'explore',
        'purpose': '发散时每条腿的最后一条消息。',
        'kind': '工作产物',
        'keep_days': 60,
    },
    {
        'name': 'tasks',
        'purpose': '交给评审的任务书。',
        'kind': '工作产物',
        'keep_days': 60,
    },
)


@contextmanager
def _data_directory(name, parent_fd=None):
    """Pin a directory without traversing a symlink, including during deletion."""
    try:
        fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
    except OSError as exc:
        if exc.errno not in (errno.ENOENT, errno.ENOTDIR, errno.ELOOP):
            raise
        yield None
        return
    try:
        yield fd
    finally:
        os.close(fd)


def _walk_data_item(parent_fd, name, expected_identity=None):
    """Yield a pinned, same-filesystem tree in postorder, without recursion."""
    device = os.fstat(parent_fd).st_dev
    stack = [(parent_fd, name, expected_identity, None)]
    opened = set()
    try:
        while stack:
            parent, child, expected, directory_fd = stack.pop()
            try:
                info = os.stat(child, dir_fd=parent, follow_symlinks=False)
                identity = (info.st_dev, info.st_ino)
                if info.st_dev != device:
                    raise OSError(errno.EXDEV, f'different filesystem at {child}')
                if expected is not None and identity != expected:
                    raise OSError(errno.ESTALE, 'item changed during cleanup')
                if directory_fd is not None or not stat.S_ISDIR(info.st_mode):
                    yield parent, child, info
                else:
                    fd = os.open(child, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
                    opened.add(fd)
                    pinned = os.fstat(fd)
                    if (pinned.st_dev, pinned.st_ino) != identity:
                        raise OSError(errno.ESTALE, 'item changed during cleanup')
                    with os.scandir(fd) as children:
                        names = [entry.name for entry in children]
                    stack.append((parent, child, identity, fd))
                    stack.extend((fd, entry, None, None) for entry in names)
            except FileNotFoundError:
                pass  # Another cleaner already removed it.
            finally:
                if directory_fd is not None:
                    os.close(directory_fd)
                    opened.remove(directory_fd)
    finally:
        for fd in opened:
            os.close(fd)


def _data_item_stats(parent_fd, name):
    """Logical bytes, newest file/link time, empty-tree fallback, and identity."""
    size, newest_file, newest_directory, identity = 0, None, 0, None
    with closing(_walk_data_item(parent_fd, name)) as items:
        for parent, child, info in items:
            if parent == parent_fd and child == name:
                identity = (info.st_dev, info.st_ino)
            if stat.S_ISDIR(info.st_mode):
                newest_directory = max(newest_directory, info.st_mtime)
            else:
                size += info.st_size
                newest_file = info.st_mtime if newest_file is None else max(newest_file, info.st_mtime)
    return (size, newest_file, newest_directory, identity) if identity is not None else None


def _remove_data_item(parent_fd, name, expected_identity=None):
    removed = False
    with closing(_walk_data_item(parent_fd, name, expected_identity)) as items:
        for parent, child, info in items:
            try:
                if stat.S_ISDIR(info.st_mode):
                    os.rmdir(child, dir_fd=parent)
                else:
                    os.unlink(child, dir_fd=parent)
                if parent == parent_fd and child == name:
                    removed = True
            except FileNotFoundError:
                pass
    return removed


def _prune_warning(path, exc):
    print(f'aiwork-config: skipping cleanup of {path}: {exc.strerror or str(exc)}', file=sys.stderr)


def prune_data(*, dry_run: bool = False) -> list[dict]:
    """Prune expired first-level artifacts using DATA_ENTRIES, or list them only.

    Directories age by their newest contained file/link. Empty trees use their
    newest directory time. Sizes are logical file/link bytes; contents are never read.
    """
    root = data_dir()
    now = time.time()
    records = []
    try:
        with _data_directory(root) as root_fd:
            if root_fd is None:
                raise ConfigError(_missing_data_dir(root))
            for entry in DATA_ENTRIES:
                if entry['keep_days'] is None:
                    continue
                name = entry['name']
                if not name or '/' in name or name in ('.', '..'):
                    raise ConfigError('invalid data registry child name')
                cutoff = now - entry['keep_days'] * 24 * 60 * 60
                try:
                    with _data_directory(name, root_fd) as entry_fd:
                        if entry_fd is None:
                            continue
                        if os.fstat(entry_fd).st_dev != os.fstat(root_fd).st_dev:
                            raise OSError(errno.EXDEV, 'different filesystem')
                        with os.scandir(entry_fd) as children:
                            names = sorted(child.name for child in children)
                        for child in names:
                            path = root / name / child
                            try:
                                measured = _data_item_stats(entry_fd, child)
                                if measured is None:
                                    continue
                                size, file_time, directory_time, identity = measured
                                modified = file_time if file_time is not None else directory_time
                                if modified >= cutoff:
                                    continue
                                if not dry_run:
                                    checked = _data_item_stats(entry_fd, child)
                                    if checked is None:
                                        continue
                                    if checked[3] != identity:
                                        raise OSError(errno.ESTALE, 'item changed during cleanup')
                                    size, file_time, directory_time, _identity = checked
                                    modified = file_time if file_time is not None else directory_time
                                    if modified >= cutoff or not _remove_data_item(entry_fd, child, identity):
                                        continue
                                records.append({'path': str(path), 'size_bytes': size,
                                                'last_modified': datetime.fromtimestamp(modified, timezone.utc).isoformat()})
                            except OSError as exc:
                                _prune_warning(path, exc)
                except OSError as exc:
                    _prune_warning(root / name, exc)
    except OSError as exc:
        _prune_warning(root, exc)
    return records


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
