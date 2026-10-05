"""无出口守卫(python 版)—— 2026-08-10,track no-egress-judging。

不变量只有一句:**跑判据的进程不许有外网出口。**

用法(判据顶部,任何别的事情之前):

    import os, sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import _no_egress  # noqa: F401  ← 无出口守卫

导入即生效。逻辑与 bash 版 `_no-egress.sh` 逐条对应,两份的取舍写在那边:
fail-closed、不认环境变量(比 /proc/*/ns/net)、每次实测一次出口。
"""

import os
import socket
import subprocess
import sys

_EXIT_REFUSED = 78


def _die(msg):
    sys.stderr.write("🔴 无出口守卫:%s\n" % msg)
    sys.stderr.write("   判据进程必须没有外网出口(不许在跑判据时把额度花出去)。\n")
    sys.stderr.write("   来源:tests/_no_egress.py,track no-egress-judging(2026-08-10)。\n")
    sys.stderr.flush()
    os._exit(_EXIT_REFUSED)


def _isolated():
    """已经在独立网络命名空间里?——看内核,不看环境变量(环境变量是零成本后门)。"""
    try:
        return os.readlink("/proc/self/ns/net") != os.readlink("/proc/1/ns/net")
    except OSError:
        return False


def _egress_open():
    try:
        socket.create_connection(("1.1.1.1", 443), timeout=3).close()
        return True
    except OSError:
        return False


def _enforce():
    if not _isolated():
        if os.environ.get("AIWORK_NO_EGRESS_TRIED"):
            _die("已经自举过一次,却仍然不在独立的网络命名空间里(unshare 没生效?)")
        # 先探再 exec:直接 exec 的话 unshare 失败会替换掉本进程,一句解释都留不下。
        try:
            rc = subprocess.call(["unshare", "-n", "--", "true"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            _die("找不到 unshare,做不到网络隔离 ⇒ 拒跑")
        if rc != 0:
            _die("unshare -n 用不了(没权限?内核不支持?)⇒ 拒跑")

        env = dict(os.environ, AIWORK_NO_EGRESS_TRIED="1")
        script = os.path.abspath(sys.argv[0])
        os.execvpe(
            "unshare",
            ["unshare", "-n", "--", "bash", "-c",
             'ip link set lo up 2>/dev/null || true; exec "$0" "$@"',
             sys.executable, script] + sys.argv[1:],
            env,
        )
        _die("exec unshare 没能替换掉本进程 ⇒ 拒跑")  # 正常到不了

    # 隔离成功就摘掉"试过一次"的标记:它是给本进程打断死循环用的,不是身份牌。
    # 留着会被子进程继承,子进程若回到主命名空间会被误判成"自举失败"而拒跑。
    os.environ.pop("AIWORK_NO_EGRESS_TRIED", None)

    if _egress_open():
        _die("已经进了命名空间,却**仍然连得出去** ⇒ 拒跑(这道闸没生效,别当它生效了)")


_enforce()

from _test_settings import ensure_settings
ensure_settings()
