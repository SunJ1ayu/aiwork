"""无出口守卫(python 版)—— 2026-08-10,track no-egress-judging。

不变量只有一句:**跑判据的进程不许有外网出口。**

用法(判据顶部,任何别的事情之前):

    import os, sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import _no_egress  # noqa: F401  ← 无出口守卫

导入即生效。逻辑与 bash 版 `_no-egress.sh` 逐条对应,两份的取舍写在那边:
fail-closed、不认环境变量(问内核)、每次实测一次出口。

**这是指定的分平台处**(和 bash 版、它们的判据 `test-no-egress.sh` 一起;别的套件不分平台)。
Linux 用 `unshare -n`,细节写在 bash 版文件头。

macOS 上的做法只在本文件定义一次,bash 版在 Mac 上经 `python3 _no_egress.py <子命令>` 问这里
(当脚本跑时不做导入时那套检查):
  · 没隔离:用系统自带的 `/usr/bin/sandbox-exec`(写死绝对路径)带一份现场生成的「只禁外网」
    规则重跑自己。规则放行 127.0.0.1 和 unix socket(桩服务器要用);系统解析器的 unix socket
    (`/var/run/mDNSResponder`,规则里写真实路径)单独禁掉,DNS 查询也出不去。
  · "已隔离" = 内核的 sandbox_check 说本进程在沙箱里,**而且**是本守卫这份规则:规则里多拒绝
    一个只有我们拒绝的路径,读它得到权限错才算。在别人的沙箱里(比如别家 CLI 的)就拒跑:
    Mac 的沙箱套不了第二层,别人的规则又验证不了。
  · 出口实测只认「被明确拒绝」(权限错)为没出口,超时之类都当可能连得出去;用 python 的
    连接超时(Mac 上没有 GNU timeout)。
"""

import ctypes
import os
import socket
import subprocess
import sys

_EXIT_REFUSED = 78
_MACOS = sys.platform == "darwin"
_SANDBOX_EXEC = "/usr/bin/sandbox-exec"


def _die(msg):
    sys.stderr.write("🔴 无出口守卫:%s\n" % msg)
    sys.stderr.write("   判据进程必须没有外网出口(不许在跑判据时把额度花出去)。\n")
    sys.stderr.write("   来源:tests/_no_egress.py,track no-egress-judging(2026-08-10)。\n")
    sys.stderr.flush()
    os._exit(_EXIT_REFUSED)


if _MACOS:
    _NOT_ISOLATED = "已经自举过一次,却仍然不在沙箱里(%s 没生效?)" % _SANDBOX_EXEC
    _LEAK = ("已经在本守卫的沙箱里,连外网却没被明确拒绝(连上了,或者超时之类)⇒ 拒跑"
             "(这道闸没生效,别当它生效了)")
    _FOREIGN = ("在沙箱里,却认不出是本守卫只禁外网的那份规则(被别的工具的沙箱包着?)⇒ 拒跑:"
                "那层规则禁没禁外网,本守卫验证不了,Mac 的沙箱又套不了第二层。要在那个沙箱外跑测试")
    # 只有本守卫的规则拒绝读它的元数据:每台 Mac 都有、测试从来不碰。旁边的 /var/run 谁都不拒,
    # 用来排除「整片目录都读不了」的别人家沙箱。规则里要写真实路径(/var 是指向 /private/var 的链接)。
    _MARK = os.path.realpath("/var/empty")
    _MARK_NEIGHBOUR = os.path.realpath("/var/run")

    def _ours():
        """内核能证明的「是本守卫这份规则」:只被我们拒绝的那个路径报权限错,旁边的照常读得到。"""
        try:
            os.stat(_MARK)
            return False
        except PermissionError:
            pass
        except OSError:
            return False
        try:
            os.stat(_MARK_NEIGHBOUR)
        except OSError:
            return False
        return True

    def _isolated():
        """在本守卫自己的沙箱里?——看内核,不看环境变量(环境变量是零成本后门)。
        在别人的沙箱里就拒跑:别人的规则验证不了,只靠一个探测地址连不连得上分不出有没有网。"""
        try:
            check = ctypes.CDLL(None).sandbox_check
            check.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int)
            check.restype = ctypes.c_int
            verdict = check(os.getpid(), None, 0)
        except (OSError, AttributeError):
            verdict = None
        if verdict not in (0, 1):
            _die("问不到内核本进程在不在沙箱里(调 sandbox_check 失败)⇒ 拒跑")
        if verdict == 0:
            return False
        if not _ours():
            _die(_FOREIGN)
        return True

    def _rules():
        """只禁外网。规则里的路径要写真实路径(/var 是指向 /private/var 的链接)。"""
        run = os.path.realpath("/var/run")
        return "\n".join([
            "(version 1)", "(allow default)", "(deny network*)",
            '(allow network-bind (local ip "localhost:*"))',
            '(allow network-inbound (local ip "localhost:*"))',
            '(allow network-outbound (remote ip "localhost:*"))',
            "(allow network* (local unix-socket))",
            "(allow network* (remote unix-socket))",
            '(deny network-outbound (remote unix-socket (path-literal "%s/mDNSResponder")))' % run,
            '(deny file-read-metadata (literal "%s"))' % _MARK,
        ]) + "\n"

    def _egress_open():
        """只有被明确拒绝(权限错)才算没出口:本守卫的规则下直连外网立刻被拒;
        超时之类只说明这一个地址不通,不说明没网。"""
        try:
            socket.create_connection(("1.1.1.1", 443), timeout=3).close()
        except PermissionError:
            return False
        except OSError:
            pass
        return True

    def _prepare():
        if not os.access(_SANDBOX_EXEC, os.X_OK):
            _die("找不到 %s,做不到网络隔离 ⇒ 拒跑" % _SANDBOX_EXEC)
        rc = subprocess.call([_SANDBOX_EXEC, "-p", _rules(), "/usr/bin/true"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if rc != 0:
            _die("%s 套不上只禁外网的规则,做不到网络隔离 ⇒ 拒跑" % _SANDBOX_EXEC)

    def _reexec(env, script):
        os.execve(_SANDBOX_EXEC,
                  [_SANDBOX_EXEC, "-p", _rules(), sys.executable, script] + sys.argv[1:], env)
else:
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


def _cli(argv):
    """macOS 上 bash 版守卫问的就是这几样;python3 是它起的子进程,沙箱随进程继承、去不掉,
    所以这里问自己在不在沙箱里,就是在问那个 bash。"""
    usage = "用法(只给 macOS 上的 bash 版守卫用):_no_egress.py isolated|egress|prepare|messages"
    if not _MACOS or len(argv) != 1:
        sys.exit(usage)
    if argv[0] == "isolated":
        print(1 if _isolated() else 0)
    elif argv[0] == "egress":
        print("open" if _egress_open() else "closed")
    elif argv[0] == "prepare":
        _prepare()
        print(_SANDBOX_EXEC)
        sys.stdout.write(_rules())
    elif argv[0] == "messages":
        print(_NOT_ISOLATED)
        print(_LEAK)
    else:
        sys.exit(usage)


if __name__ == "__main__":
    _cli(sys.argv[1:])
else:
    _enforce()

    from _test_settings import clear_review_environment, ensure_settings
    clear_review_environment()
    ensure_settings()
