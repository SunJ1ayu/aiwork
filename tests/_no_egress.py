"""Linux 无出口守卫；独立网络命名空间见 `_no-egress.sh`。导入即生效。"""
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


_NOT_ISOLATED = "已经自举过一次,却仍然不在独立的网络命名空间里(unshare 没生效?)"
_LEAK = "已经进了命名空间,却**仍然连得出去** ⇒ 拒跑(这道闸没生效,别当它生效了)"

def _isolated():
    """已经在独立网络命名空间里?——看内核,不看环境变量(环境变量是零成本后门)。"""
    try:
        return os.readlink("/proc/self/ns/net") != os.readlink("/proc/1/ns/net")
    except OSError:
        return False

def _prepare():
    try:
        rc = subprocess.call(["unshare", "-n", "--", "true"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        _die("找不到 unshare,做不到网络隔离 ⇒ 拒跑")
    if rc != 0:
        _die("unshare -n 用不了(没权限?内核不支持?)⇒ 拒跑")

def _reexec(env, script):
    os.execvpe(
        "unshare",
        ["unshare", "-n", "--", "bash", "-c",
         'ip link set lo up 2>/dev/null || true; exec "$0" "$@"',
         sys.executable, script] + sys.argv[1:],
        env,
    )

def _egress_open():
    try:
        socket.create_connection(("1.1.1.1", 443), timeout=3).close()
        return True
    except OSError:
        return False

def _enforce():
    if not _isolated():
        if os.environ.get("AIWORK_NO_EGRESS_TRIED"):
            _die(_NOT_ISOLATED)
        # 先探再 exec:直接 exec 的话隔离失败会替换掉本进程,一句解释都留不下。
        _prepare()

        env = dict(os.environ, AIWORK_NO_EGRESS_TRIED="1")
        _reexec(env, os.path.abspath(sys.argv[0]))
        _die("exec 没能替换掉本进程 ⇒ 拒跑")  # 正常到不了

    # 隔离成功就摘掉"试过一次"的标记:它是给本进程打断死循环用的,不是身份牌。
    # 留着会被子进程继承,子进程若回到主命名空间会被误判成"自举失败"而拒跑。
    os.environ.pop("AIWORK_NO_EGRESS_TRIED", None)

    if _egress_open():
        _die(_LEAK)


_enforce()
from _test_settings import clear_inherited_environment, ensure_settings
clear_inherited_environment()
ensure_settings()
