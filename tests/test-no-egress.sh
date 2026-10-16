#!/usr/bin/env bash
# 判据:判卷面的「**跑判据的进程不许有外网出口**」不变量。
# 2026-08-10 建,track no-egress-judging。主 agent 拥有,执行腿不许改。
#
# 为什么有这份判据(08-10 事故):OpenClaw cron「评审工具链-每周防锈」每周一 08:00 跑
# `bin/rust-check-review-tooling`;`tests/test-review-tooling.sh` 的 V23/V24 为了考
# 反锚定闸,把**真的** subkimi/submimo/subchat/subagent 拷进临时目录直接跑,其中两种
# 情形是**故意让闸放行**的 —— 闸一放行,脚本就真的往外打。一上午 12 次真实 kimi 调用,
# 全花在一个内容是单字母 `x` 的假仓库上,机主当天额度归零。
# 08-08 那天本该暴露,但当时额度已空、全被 403 挡下 —— **失败得太安静,把 bug 藏了两天**。
#
# 这份判据要问的不是"V23/V24 补没补假 CLI"(那是靠人记得,下一份考卷照样漏),
# 而是那条唯一的不变量:**判据进程连不出去**。
#
# ⚠️ 这份判据自己必须**有网**才问得出东西:一个什么都不做的空守卫,在一台本来就
#    断网的机器上也能"通过"。所以 C0 是反空转控制组,它红了整份判据都不算数。
#    正因如此,本文件是**唯一**允许回到守卫外的判据(N3b 机械锁死):Linux 用 `nsenter`
#    回宿主命名空间;macOS 的沙箱进去就出不来,改由引守卫之前起的沙箱外代跑进程替它跑。
#
# **本文件是指定的分平台处**(和两份守卫一起),只许在三处分:
#   ① 怎么回到守卫外(in_host);② 怎么模拟「隔离做不到」(NO_ISOLATION);③ DNS 那条断言。
#   ③ 现在不用分:macOS 的规则禁掉了系统解析器的 unix socket,DNS 两边都查不到。
#
# Run:  bash /root/aiwork/tests/test-no-egress.sh
set -uo pipefail

TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$TESTS/_no-egress.sh"
PYGUARD="$TESTS/_no_egress.py"
OS="$(uname -s)"

# macOS 的沙箱外代跑进程(分平台 ① 用)。它是本判据的父进程,待在沙箱外;判据经继承来的
# fd 9(一对匿名 socket,没有路径、没有端口)把命令交给它跑,stdin/stdout/stderr 原样递过去,
# 拿回退出码 —— 和 Linux 上 nsenter 干的是同一件事。
#   · 只有判据主进程用得到:第一次「认领」拿到的令牌只放在判据 shell 的非导出变量里,
#     别的请求没令牌一律拒;它替判据起的命令拿不到 fd 9,判据直接起的探针也关掉 fd 9(N8)。
#   · 判据一结束(包括被杀),它收掉正在替判据跑的那条命令就退出,不留在后台。
#   · 守卫最后一步缺测试设置时会经 _test_settings.py 重跑一次,那次会关掉继承来的 fd、
#     通道就断了,所以测试设置由它先备好。
read -r -d '' NOEG_HOST_PY <<'PY' || true
import json, os, secrets, signal, socket, struct, subprocess, sys, threading
tests, fd, shell, script, args = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5:]
sys.path.insert(0, tests)
import _test_settings
_test_settings.ensure_settings()

mine, theirs = socket.socketpair()
os.dup2(theirs.fileno(), fd)
theirs.close()
oracle = subprocess.Popen([shell, script] + args, pass_fds=(fd,),
                          env=dict(os.environ, AIWORK_NOEG_HOST_FD=str(fd)))
os.close(fd)
token = secrets.token_hex(16)
lock = threading.Lock()
state = {"claimed": False, "running": None}


def read_exact(n, buf=b""):
    while len(buf) < n:
        chunk = mine.recv(n - len(buf))
        if not chunk:
            raise EOFError
        buf += chunk
    return buf


def reply(obj):
    data = json.dumps(obj).encode()
    try:
        mine.sendall(struct.pack("!I", len(data)) + data)
    except OSError:
        pass


def handle(req, fds):
    if req.get("op") == "hello":
        if state["claimed"]:
            return reply({"error": "已经被认领过"})
        state["claimed"] = True
        return reply({"token": token})
    if not (state["claimed"] and secrets.compare_digest(str(req.get("token", "")), token)):
        return reply({"error": "请求没带对令牌"})
    if len(fds) != 3:
        return reply({"error": "请求没带 stdin/stdout/stderr"})
    try:
        proc = subprocess.Popen(req["argv"], stdin=fds[0], stdout=fds[1], stderr=fds[2],
                                env=req["env"], cwd=req["cwd"])
    except OSError as e:
        return reply({"error": "起不来:%s" % e})
    with lock:
        state["running"] = proc
    rc = proc.wait()
    with lock:
        state["running"] = None
    reply({"rc": rc if rc >= 0 else 128 - rc})


def serve():
    while True:
        try:
            head, fds, _, _ = socket.recv_fds(mine, 4, 3)
        except OSError:
            return
        if not head:
            return
        try:
            req = json.loads(read_exact(struct.unpack("!I", read_exact(4, head))[0]))
        except (EOFError, OSError, ValueError):
            req = None
        try:
            if req is None:
                return
            handle(req, fds)
        finally:
            for f in fds:
                os.close(f)


threading.Thread(target=serve, daemon=True).start()


def forward(signum, _frame):
    try:
        oracle.send_signal(signum)
    except ProcessLookupError:
        pass


for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(signum, forward)
rc = oracle.wait()
with lock:
    proc = state["running"]
if proc is not None and proc.poll() is None:
    proc.terminate()
    try:
        proc.wait(5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
sys.exit(rc if rc >= 0 else 128 - rc)
PY
read -r -d '' NOEG_HOST_CLIENT_PY <<'PY' || true
import json, os, socket, struct, sys
fd, op, argv = int(sys.argv[1]), sys.argv[2], sys.argv[3:]


def fail(msg):
    sys.stderr.write("沙箱外代跑通道:%s\n" % msg)
    sys.exit(70)


def frame(obj):
    data = json.dumps(obj).encode()
    return struct.pack("!I", len(data)) + data


def answer():
    def read_exact(n):
        buf = b""
        while len(buf) < n:
            chunk = chan.recv(n - len(buf))
            if not chunk:
                fail("代跑进程没有回话")
            buf += chunk
        return buf
    return json.loads(read_exact(struct.unpack("!I", read_exact(4))[0]))


try:
    chan = socket.socket(fileno=os.dup(fd))
except OSError:
    fail("不在(本进程不是经沙箱外的代跑进程启动的判据主进程)")
if op == "hello":
    chan.sendall(frame({"op": "hello"}))
    ans = answer()
    if "token" not in ans:
        fail(ans.get("error", "认领失败"))
    print(ans["token"])
else:
    req = frame({"op": "run", "token": os.environ.pop("__NOEG_HOST_TOKEN", ""),
                 "argv": argv, "env": dict(os.environ), "cwd": os.getcwd()})
    socket.send_fds(chan, [req[:4]], [0, 1, 2])
    chan.sendall(req[4:])
    ans = answer()
    if "rc" not in ans:
        fail(ans.get("error", "没有结果"))
    sys.exit(ans["rc"])
PY

# 分平台 ①(前半):macOS 上先换成沙箱外的代跑进程,判据作为它的子进程重跑、再引守卫。
if [[ "$OS" == Darwin && -z "${AIWORK_NOEG_HOST_FD:-}" ]]; then
  exec python3 -I -c "$NOEG_HOST_PY" "$TESTS" 9 "${BASH:-bash}" "$0" "$@"
fi

# 本判据自己也遵守这条不变量,N3 一视同仁、不给自己开豁免(豁免会腐烂)。
# 唯一的松口是**守卫还不存在的时候**:那时整份判据应该红在 N3 的断言上,
# 而不是炸在 `source: 没有那个文件` 上 —— 「红在 TypeError 上等于没红检过」。
if [[ -f "$TESTS/_no-egress.sh" ]]; then
  # 字面路径 + `|| exit`:N3a 扫的就是这一行,自己也得扫得到、也得 fail-closed。
  # 外层的 `-f` 只负责"守卫还不存在时别炸,让 N3 去红";`|| exit` 负责"存在但引失败"。
  . "$TESTS/_no-egress.sh" || exit 78
fi

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

write_probe() {  # write_probe <路径> <yes|no:引不引守卫>
  local f="$1" useguard="$2"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -uo pipefail'
    [[ "$useguard" == yes ]] && echo ". \"$GUARD\""
    cat <<'PY'
python3 - <<'PYEOF'
import socket
opened = False
for hp in (("1.1.1.1", 443), ("8.8.8.8", 53)):
    try:
        socket.create_connection(hp, timeout=4).close()
        opened = True
    except Exception:
        pass
try:
    socket.getaddrinfo("api.moonshot.cn", 443)
    dns = "DNS_OK"
except Exception:
    dns = "DNS_BLOCKED"
import os, stat
try:
    held = stat.S_ISSOCK(os.fstat(9).st_mode)
except OSError:
    held = False
held = held or "AIWORK_NOEG_HOST_FD" in os.environ or "__NOEG_HOST_TOKEN" in os.environ
print("EGRESS_OPEN" if opened else "EGRESS_BLOCKED", dns,
      "HOST_CHANNEL_HELD" if held else "HOST_CHANNEL_NONE")
PYEOF
PY
  } > "$f"
  chmod +x "$f"
}


__noeg_suites() {  # 要覆盖的判据套件 = tests/ 下的命名约定 ∪ **总跑 SUITES 里点名的**
  # 08-10 四审 subdeepseek 指出:两条覆盖闸都按文件名 glob 扫,
  # 而总跑的 SUITES 是**手列**的 —— 往里加一个不叫 test-* 的判据,两条闸完全看不见,
  # 孤儿闸只查反方向(tests/ 里有没有落单的)。这里把两边取并集。
  {
    ls "$TESTS"/test-*.sh "$TESTS"/test_*.sh "$TESTS"/test-*.py "$TESTS"/test_*.py 2>/dev/null
    sed -n 's/^[[:space:]]*"[^|]*|[^|]*|\([^"]*\)".*/\1/p' "$TESTS/../bin/rust-check-review-tooling"
  } | sort -u
}

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

if [[ "$OS" == Darwin ]]; then
  # 分平台 ①(后半):认领代跑通道。令牌只放在本 shell 的非导出变量里,标记随即摘掉。
  NOEG_HOST_TOKEN=""
  if [[ -n "${AIWORK_NOEG_HOST_FD:-}" ]]; then
    NOEG_HOST_TOKEN="$(python3 -I -c "$NOEG_HOST_CLIENT_PY" 9 hello)" || NOEG_HOST_TOKEN=""
  fi
  unset AIWORK_NOEG_HOST_FD
  in_host() {  # 在沙箱外跑(判据要有网,才问得出"守卫切断了网")
    __NOEG_HOST_TOKEN="$NOEG_HOST_TOKEN" python3 -I -c "$NOEG_HOST_CLIENT_PY" 9 run "$@"
  }
  # 分平台 ②:sandbox-exec 写死了绝对路径,换不成假货;改为先套一层什么都放行的沙箱。
  # Mac 的沙箱套不了第二层,守卫只能看到「已经在沙箱里」而照样实测出口 —— 连得出去就该拒跑。
  # 这正是被别家 CLI 的不禁网沙箱包着时的真实处境。
  NO_ISOLATION=(/usr/bin/sandbox-exec -p '(version 1)(allow default)')
else
  in_host() {  # 在**宿主**网络命名空间里跑(判据要有网,才问得出"守卫切断了网")
    nsenter -t 1 -n -- "$@"
  }
  # 分平台 ②:把 `unshare` 换成必然失败的假货。
  mkdir -p "$D/fakebin"
  printf '#!/bin/bash\nexit 1\n' > "$D/fakebin/unshare"; chmod +x "$D/fakebin/unshare"
  NO_ISOLATION=(env PATH="$D/fakebin:$PATH")
fi

# ---------------------------------------------------------------- C0
c0_this_machine_has_egress_at_all() {
  echo "[C0] 反空转:宿主命名空间里本来就连得出去"
  write_probe "$D/probe_raw.sh" no
  local out; out="$(in_host bash "$D/probe_raw.sh" 2>&1)"
  grep -q "EGRESS_OPEN" <<<"$out"
  check "C0: 不引守卫时连得出去(它红 ⇒ 本判据问不出任何东西,下面全部不算数)" $?
}

# ---------------------------------------------------------------- N1
n1_no_egress_under_guard() {
  echo "[N1] 守卫下:真的没有出口"
  write_probe "$D/probe_guarded.sh" yes
  local out; out="$(in_host bash "$D/probe_guarded.sh" 2>&1)"
  grep -q "EGRESS_BLOCKED" <<<"$out"
  check "N1: 守卫下连不出外网(裸 IP 也不行)" $?
  grep -q "DNS_BLOCKED" <<<"$out"
  check "N1: 守卫下 DNS 也解析不了(不是只挡了路由)" $?
}

# ---------------------------------------------------------------- N2
n2_loopback_still_works() {
  echo "[N2] loopback 必须还通(全部现有套件的桩服务器都在 127.0.0.1 上)"
  cat > "$D/loop.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
. "$GUARD"
python3 - <<'PYEOF'
import threading, urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b"pong")
    def log_message(self, *a):
        pass
srv = HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
try:
    body = urllib.request.urlopen("http://127.0.0.1:%d/" % srv.server_port, timeout=5).read()
    print("LOOPBACK_OK" if body == b"pong" else "LOOPBACK_BAD")
except Exception as e:
    print("LOOPBACK_BAD", e)
PYEOF
EOF
  local out; out="$(in_host bash "$D/loop.sh" 2>&1)"
  grep -q "LOOPBACK_OK" <<<"$out"
  check "N2: 守卫下 127.0.0.1 的桩服务器仍连得上" $?
}

# ---------------------------------------------------------------- N3
n3_every_suite_carries_the_guard() {
  echo "[N3] 覆盖完备:靠'记得加'就等于没有闸"
  [[ -f "$GUARD" ]];   check "N3: bash 守卫存在($GUARD)" $?
  [[ -f "$PYGUARD" ]]; check "N3: python 守卫存在($PYGUARD)" $?

  # N3a 只是**便宜的先筛**:它是文本匹配,一行注释就能骗过去。
  #     真正说了算的是下面 N3c 的行为抽检 —— 别把 N3a 当保证。
  local missing="" f b
  for f in $(__noeg_suites); do
    [[ -f "$f" ]] || continue
    b="$(basename "$f")"
    # 必须是**能执行的**引入行(行首不是 #),不是提一嘴文件名的注释
    # bash 的引入行必须自带 `|| exit`:没开 set -e 时,source 失败会**若无其事地裸跑**
    # (08-10 四审 subkimi 抓到的静默 fail-open;python 的 import 失败自己就非零,不需要)
    grep -qE '^[[:space:]]*(\.|source)[[:space:]].*_no-egress\.sh.*\|\|[[:space:]]*exit' "$f" \
      || grep -qE '^[[:space:]]*(import|from|exec\(open)[^#]*_no_egress' "$f" \
      || missing="$missing $b"
  done
  [[ -z "$missing" ]]
  check "N3a: 每个判据套件都有一行**可执行的**守卫引入(缺:${missing:-无})" $?

  # N3c **行为抽检**:让隔离做不到(见分平台 ②),每个套件都必须当场拒跑。
  #     骗得过 N3a 的注释骗不过这里 —— 注释不会让套件拒跑。
  #     成本很低:fail-closed 会在第一个用例之前就退出,不会真跑完套件。
  local leaky="" runner out rc
  for f in $(__noeg_suites); do
    [[ -f "$f" ]] || continue
    b="$(basename "$f")"
    [[ "$b" == "test-no-egress.sh" ]] && continue   # 本判据的行为由 N4 直接考
    runner=bash; [[ "$f" == *.py ]] && runner=python3
    out="$(in_host "${NO_ISOLATION[@]}" "$TESTS/../bin/aiwork-timeout" 20 "$runner" "$f" 2>&1)"; rc=$?
    # 非零、且不是超时(超时说明它压根没理守卫、跑起来了)、且一条用例都没跑
    # 不只问"拒跑了",还要问"**是不是被这道闸**拒的" —— 因为别的原因早死也会非零,
    # 那样 N3c 会为了错误的理由变绿(08-10 四审 subkimi 与我自审 F3 同时点到)。
    if [[ $rc -eq 0 || $rc -eq 124 ]] \
       || grep -qE '^\s*(PASS|ok|FAIL):' <<<"$out" \
       || ! grep -qE "unshare|隔离|出口" <<<"$out"; then
      leaky="$leaky $b"
    fi
  done
  [[ -z "$leaky" ]]
  check "N3c: 隔离做不到时每个套件都当场拒跑(带着网跑起来的:${leaky:-无})" $?

  # N3b:守卫的已知逃逸口是 nsenter 本身,和 macOS 上本判据的沙箱外代跑进程。
  #      只有本判据用得着它们(C0 那个控制组),别处出现 = 有人用它绕出去打模型 ⇒ 硬红。
  local leak="" hostleak=""
  for f in "$TESTS"/test-* "$TESTS"/test_* "$TESTS"/_*; do
    [[ -f "$f" ]] || continue
    b="$(basename "$f")"
    [[ "$b" == "test-no-egress.sh" ]] && continue
    # 只看**能执行的**行:整行注释里提一句 nsenter 不是逃逸。
    # 08-10 四审 subdeepseek 抓到:守卫文件头部的强度声明里写了这个词,
    # N3b 于是把**守卫自己**报成逃逸口(而且那笔 commit 在我全部绿收据之后,
    # 收据没覆盖到它 —— verify.md 上写着 18/0,HEAD 上其实是 17/1)。
    grep -vE '^[[:space:]]*#' "$f" | grep -q "nsenter" && leak="$leak $b"
    grep -vE '^[[:space:]]*#' "$f" | grep -qi "noeg_host" && hostleak="$hostleak $b"
  done
  [[ -z "$leak" ]]
  check "N3b: 只有本判据允许用 nsenter 回宿主(逃逸口:${leak:-无})" $?
  [[ -z "$hostleak" ]]
  check "N3b: 只有本判据允许用沙箱外代跑进程(用到的:${hostleak:-无})" $?
}

# ---------------------------------------------------------------- N4
n4_fail_closed() {
  echo "[N4] fail-closed:隔离做不到就**拒跑**,不许静默带着网往下跑"
  write_probe "$D/probe_failclosed.sh" yes
  local out rc
  out="$(in_host "${NO_ISOLATION[@]}" bash "$D/probe_failclosed.sh" 2>&1)"; rc=$?
  [[ $rc -ne 0 ]]
  check "N4: 隔离做不到 ⇒ 非零退出" $?
  # ⚠️ 匹配词里**不许**出现 `egress`:守卫文件名就叫 `_no-egress.sh`,
  #    bash 的 "No such file or directory" 会把这个路径打出来,于是一条什么都没解释的
  #    报错也能"通过" —— 08-10 写这份判据时当场撞见的假绿,靠的是路径名而不是解释。
  grep -qE "unshare|隔离|出口" <<<"$out"
  check "N4: 拒跑时说清是为什么(不是一句无头的报错)" $?
  ! grep -q "EGRESS_OPEN" <<<"$out"
  check "N4: 拒跑时**没有**继续跑下面的用例(fail-open 是本机反复踩的坑)" $?
}

# ---------------------------------------------------------------- N5
n5_env_is_not_a_backdoor() {
  echo "[N5] 环境变量不是后门(V24 刚封过同一形状:export 一次 = 零成本、不留痕)"
  write_probe "$D/probe_env.sh" yes
  local out
  out="$(in_host env AIWORK_NO_EGRESS=1 NO_EGRESS=1 AIWORK_JUDGE_NETNS=1 \
          AIWORK_NO_EGRESS_TRIED=1 SKIP_NO_EGRESS=1 \
          bash "$D/probe_env.sh" 2>&1)"
  ! grep -q "EGRESS_OPEN" <<<"$out"
  check "N5: 人还在主命名空间时,光 export 标记不许换来一条出口" $?
}

# ---------------------------------------------------------------- N6
n6_idempotent_no_exec_loop() {
  echo "[N6] 已经隔离了就别再自举(否则 exec 死循环 / 整份判据挂住)"
  write_probe "$D/probe_again.sh" yes
  local out rc
  # 9<&-:判据直接起的探针不许拿到 macOS 上的代跑通道(N8)。
  out="$("$TESTS/../bin/aiwork-timeout" 25 bash "$D/probe_again.sh" 9<&- 2>&1)"; rc=$?
  [[ $rc -ne 124 ]]
  check "N6: 在已隔离的进程里再引一次守卫,不挂死" $?
  grep -q "EGRESS_BLOCKED" <<<"$out"
  check "N6: 且照常往下跑(仍然没有出口)" $?
  grep -q "HOST_CHANNEL_NONE" <<<"$out"
  check "N6: 判据直接起的探针拿不到沙箱外代跑通道" $?
}

# ---------------------------------------------------------------- N7
n7_transparent() {
  echo "[N7] 透传:守卫只拿走网络,别的什么都不许动"
  cat > "$D/pass.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
. "$GUARD"
echo "ARGS:\$*"
echo "STDIN:\$(cat)"
exit 7
EOF
  local out rc
  out="$(in_host bash "$D/pass.sh" a b "c d" <<< "hello" 2>&1)"; rc=$?
  [[ $rc -eq 7 ]]
  check "N7: 退出码原样透传(判据红了要还是红的)" $?
  grep -q 'ARGS:a b c d' <<<"$out"
  check "N7: 参数原样透传" $?
  grep -q 'STDIN:hello' <<<"$out"
  check "N7: stdin 原样透传" $?
}

# ---------------------------------------------------------------- N8
n8_host_channel_stays_with_the_oracle() {
  echo "[N8] 回到守卫外的通道只有本判据主进程用得到(macOS 的代跑进程;Linux 上本来就没有)"
  write_probe "$D/probe_channel.sh" yes
  local out rc
  out="$(in_host bash "$D/probe_channel.sh" 2>&1)"
  grep -q "HOST_CHANNEL_NONE" <<<"$out"
  check "N8: 替判据在守卫外跑的探针拿不到这条通道" $?
  # 子进程就算继承了 fd 9,没有令牌也用不了。
  out="$(python3 -I -c "$NOEG_HOST_CLIENT_PY" 9 run /usr/bin/true 2>&1)"; rc=$?
  [[ $rc -ne 0 ]]
  check "N8: 没有令牌的子进程用不了这条通道(rc=$rc)" $?
}

# ---------------------------------------------------------------- N9
n9_platform_checks_stay_in_the_designated_files() {
  echo "[N9] 平台判断只许出现在指定的分平台处(两份守卫和本判据)"
  local f b hits=""
  for f in "$TESTS"/* "$TESTS"/../bin/*; do
    [[ -f "$f" ]] || continue
    b="$(basename "$f")"
    case "$b" in _no-egress.sh|_no_egress.py|test-no-egress.sh) continue ;; esac
    # 只看能执行的行(整行注释里提一句不算)
    grep -vE '^[[:space:]]*(#|//)' "$f" 2>/dev/null \
      | grep -IqE 'uname|sys\.platform|platform\.(system|mac_ver)|os\.uname|OSTYPE|[Dd]arwin|process\.platform' \
      && hits="$hits $b"
  done
  [[ -z "$hits" ]]
  check "N9: 别的文件里没有平台判断(出现在:${hits:-无})" $?
}

echo "=== no-egress oracle ==="
c0_this_machine_has_egress_at_all
n1_no_egress_under_guard
n2_loopback_still_works
n3_every_suite_carries_the_guard
n4_fail_closed
n5_env_is_not_a_backdoor
n6_idempotent_no_exec_loop
n7_transparent
n8_host_channel_stays_with_the_oracle
n9_platform_checks_stay_in_the_designated_files
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
