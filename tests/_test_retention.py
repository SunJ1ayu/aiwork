"""Filesystem timestamp fixture shared by retention entry-point tests."""
from contextlib import contextmanager
import os
from unittest.mock import patch


@contextmanager
def extreme_mtime(path):
    """Use a real out-of-range mtime, or emulate stat when the FS clamps it."""
    timestamp = -1e15
    try:
        os.utime(path, (timestamp, timestamp))
    except (OSError, OverflowError):
        pass
    info = path.stat()
    if info.st_mtime < -62135596800:  # Before datetime's minimum year.
        yield info.st_mtime
        return
    identity = (info.st_dev, info.st_ino)
    real_stat = os.stat

    def measured(*args, **kwargs):
        current = real_stat(*args, **kwargs)
        if (current.st_dev, current.st_ino) == identity:
            values = list(current)
            values[8] = timestamp  # st_mtime, retaining the actual type/identity.
            return os.stat_result(values)
        return current

    with patch('os.stat', side_effect=measured):
        yield timestamp
