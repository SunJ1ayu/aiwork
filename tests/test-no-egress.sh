#!/usr/bin/env bash
# 判据:判卷面的「**跑判据的进程不许有外网出口**」不变量。
# 2026-08-10 建,track no-egress-judging。主 agent 拥有,执行腿不许改。
#
# 为什么有这份判据(08-10 事故):OpenClaw cron「评审工具链-每周防锈」每周一 08:00 跑
# `bin/rust-check-review-tooling`;`tests/test-review-tooling.sh` 的 V23/V24 为了考
# 反锚定闸,把**真的** subkimi/submimo/subagent/subagent 拷进临时目录直接跑,其中两种
# 情形是**故意让闸放行**的 —— 闸一放行,脚本就真的往外打。一上午 12 次真实 kimi 调用,
# 全花在一个内容是单字母 `x` 的假仓库上,机主当天额度归零。
# 08-08 那天本该暴露,但当时额度已空、全被 403 挡下 —— **失败得太安静,把 bug 藏了两天**。
#
# 这份判据要问的不是"V23/V24 补没补假 CLI"(那是靠人记得,下一份考卷照样漏),
# 而是那条唯一的不变量:**判据进程连不出去**。
#
# ⚠️ 这份判据自己必须**有网**才问得出东西:一个什么都不做的空守卫,在一台本来就
#    断网的机器上也能"通过"。所以 C0 是反空转控制组,它红了整份判据都不算数。
#    正因如此,本文件是**唯一**允许用 `nsenter` 回宿主命名空间的判据(N3b 机械锁死)。
#
# Run:  bash /root/aiwork/tests/test-no-egress.sh
set -uo pipefail

TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$TESTS/_no-egress.sh"
PYGUARD="$TESTS/_no_egress.py"

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

in_host() {  # 在**宿主**网络命名空间里跑(判据要有网,才问得出"守卫切断了网")
  nsenter -t 1 -n -- "$@"
}

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
print("EGRESS_OPEN" if opened else "EGRESS_BLOCKED", dns)
PYEOF
PY
  } > "$f"
  chmod +x "$f"
}


__noeg_suites() {  # 要覆盖的判据套件 = tests/ 下的命名约定 ∪ **总跑 SUITES 里点名的**
  # 08-10 四审 指出:两条覆盖闸都按文件名 glob 扫,
  # 而总跑的 SUITES 是**手列**的 —— 往里加一个不叫 test-* 的判据,两条闸完全看不见,
  # 孤儿闸只查反方向(tests/ 里有没有落单的)。这里把两边取并集。
  {
    ls "$TESTS"/test-*.sh "$TESTS"/test_*.sh "$TESTS"/test-*.py "$TESTS"/test_*.py 2>/dev/null
    sed -n 's/^[[:space:]]*"[^|]*|[^|]*|\([^"]*\)".*/\1/p' "$TESTS/../bin/rust-check-review-tooling"
  } | sort -u
}

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

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

  # N3c **行为抽检**:把 `unshare` 换成必然失败的假货,每个套件都必须当场拒跑。
  #     骗得过 N3a 的注释骗不过这里 —— 注释不会让套件拒跑。
  #     成本很低:fail-closed 会在第一个用例之前就退出,不会真跑完套件。
  local fb2="$D/fakebin2"; mkdir -p "$fb2"
  printf '#!/bin/bash\nexit 1\n' > "$fb2/unshare"; chmod +x "$fb2/unshare"
  local leaky="" runner out rc
  for f in $(__noeg_suites); do
    [[ -f "$f" ]] || continue
    b="$(basename "$f")"
    [[ "$b" == "test-no-egress.sh" ]] && continue   # 本判据的行为由 N4 直接考
    runner=bash; [[ "$f" == *.py ]] && runner=python3
    out="$(in_host env PATH="$fb2:$PATH" timeout 20 "$runner" "$f" 2>&1)"; rc=$?
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

  # N3b:守卫的唯一已知逃逸口就是 nsenter 本身。只有本判据用得着它(C0 那个控制组),
  #      别处出现 = 有人用它绕出去打模型 ⇒ 硬红。
  local leak=""
  for f in "$TESTS"/test-* "$TESTS"/test_* "$TESTS"/_*; do
    [[ -f "$f" ]] || continue
    b="$(basename "$f")"
    [[ "$b" == "test-no-egress.sh" ]] && continue
    # 只看**能执行的**行:整行注释里提一句 nsenter 不是逃逸。
    # 08-10 四审 抓到:守卫文件头部的强度声明里写了这个词,
    # N3b 于是把**守卫自己**报成逃逸口(而且那笔 commit 在我全部绿收据之后,
    # 收据没覆盖到它 —— verify.md 上写着 18/0,HEAD 上其实是 17/1)。
    grep -vE '^[[:space:]]*#' "$f" | grep -q "nsenter" && leak="$leak $b"
  done
  [[ -z "$leak" ]]
  check "N3b: 只有本判据允许用 nsenter 回宿主(逃逸口:${leak:-无})" $?
}

# ---------------------------------------------------------------- N4
n4_fail_closed() {
  echo "[N4] fail-closed:隔离做不到就**拒跑**,不许静默带着网往下跑"
  local fb="$D/fakebin"; mkdir -p "$fb"
  printf '#!/bin/bash\nexit 1\n' > "$fb/unshare"; chmod +x "$fb/unshare"
  write_probe "$D/probe_failclosed.sh" yes
  local out rc
  out="$(in_host env PATH="$fb:$PATH" bash "$D/probe_failclosed.sh" 2>&1)"; rc=$?
  [[ $rc -ne 0 ]]
  check "N4: unshare 不可用 ⇒ 非零退出" $?
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
  out="$(timeout 25 bash "$D/probe_again.sh" 2>&1)"; rc=$?
  [[ $rc -ne 124 ]]
  check "N6: 在已隔离的进程里再引一次守卫,不挂死" $?
  grep -q "EGRESS_BLOCKED" <<<"$out"
  check "N6: 且照常往下跑(仍然没有出口)" $?
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

echo "=== no-egress oracle ==="
c0_this_machine_has_egress_at_all
n1_no_egress_under_guard
n2_loopback_still_works
n3_every_suite_carries_the_guard
n4_fail_closed
n5_env_is_not_a_backdoor
n6_idempotent_no_exec_loop
n7_transparent
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
