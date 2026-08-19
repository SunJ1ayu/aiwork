#!/usr/bin/env bash
# 探针:方案 C(只读挂载)的三条未知,一条条问真机,不靠推理。
#   C.2 git 在只读工作树上还能不能 diff/log/show/status(最可能判 C 死刑的一条)
#   C.1 腿往仓内写的那几处(logs/、.submimo-task-$$.md)会不会当场炸
#   写口是不是真的被物理挡住(含已知绕过 `git diff --output=`)
# 只读挂载只存在于 unshare 出来的 namespace 里,`--make-rprivate` 保证不传播回主机。
set -uo pipefail
REPO=/root/aiwork
say() { printf '\n=== %s ===\n' "$*"; }

say "0. 前置:制造脏工作树(今天四轮 panel 全是 dirty=yes,干净树测不出真实场景)"
echo "probe-untracked" > "$REPO/.probe-dirty-untracked"
touch "$REPO/bin/panel-review"   # 只改 mtime、不改内容 ⇒ git 会想刷新 index(写 .git/index)
git -C "$REPO" status --short | head -3
echo "(上面应当至少有一行 ?? .probe-dirty-untracked)"

say "1. 进只读 namespace"
unshare -m bash -s <<'INNS'
set -uo pipefail
REPO=/root/aiwork
mount --make-rprivate /
mount --bind "$REPO" "$REPO"
mount -o remount,ro,bind "$REPO"
cd "$REPO"
r() { printf '  rc=%s  %s\n' "$1" "$2"; }

echo "-- C.2 只读工作树上的 git(核心问题)--"
out=$(git status --short 2>&1); r $? "git status --short"; echo "$out" | head -3 | sed 's/^/     /'
out=$(git diff --stat 2>&1);     r $? "git diff --stat";     echo "$out" | tail -2 | sed 's/^/     /'
out=$(git log --oneline -2 2>&1); r $? "git log";            echo "$out" | sed 's/^/     /'
out=$(git show --stat HEAD 2>&1); r $? "git show --stat HEAD"
out=$(git rev-parse HEAD 2>&1);   r $? "git rev-parse HEAD"
out=$(git blame -L1,2 bin/panel-review 2>&1); r $? "git blame(v1 挑了 CLAUDE.md,那文件在 /root/ 不在仓里 ⇒ 128 是探针自己的 bug,不是只读)"
out=$(git diff HEAD~1 --stat 2>&1); r $? "git diff HEAD~1(要读对象库)"

echo "-- 写口:应当**全部失败** --"
touch "$REPO/PROBE_SHOULD_FAIL" 2>/dev/null;                    r $? "touch 仓内新文件(期望非 0)"
git diff --output=/root/aiwork/PROBE_OUTPUT HEAD 2>/dev/null;   r $? "git diff --output=(已知绕过,期望非 0)"
echo x >> "$REPO/README.md" 2>/dev/null;                         r $? "追加已跟踪文件(期望非 0)"
git commit --allow-empty -m probe 2>/dev/null;                  r $? "git commit(期望非 0)"

echo "-- C.1 腿的合法写需求:这几处在只读下会炸 --"
touch "$REPO/logs/probe.log" 2>/dev/null;                       r $? "写 logs/(腿日志就在仓内)"
touch "$REPO/.submimo-task-probe.md" 2>/dev/null;               r $? "写 .submimo-task-\$\$.md(submimo 要建)"

echo "-- 仓外仍可写(确认只挡了仓)--"
touch /root/probe-outside-ok 2>/dev/null; r $? "写 /root/(期望 0)"; rm -f /root/probe-outside-ok
INNS
echo "unshare 整体 rc=$?"

say "1b. 对照组 —— 同样的读命令在**可写**状态下跑(差异只许来自只读)"
for c in "git status --short" "git diff --stat" "git log --oneline -2" \
         "git show --stat HEAD" "git rev-parse HEAD" "git blame -L1,2 bin/panel-review" \
         "git diff HEAD~1 --stat"; do
  ( cd "$REPO" && eval "$c" >/dev/null 2>&1 ); printf '  rc=%s  可写: %s\n' "$?" "$c"
done

say "2. 回到主 namespace:确认仓没被留成只读"
touch "$REPO/.probe-mainns-write" && echo "主 namespace 仍可写 ✓" && rm -f "$REPO/.probe-mainns-write"

say "3. 清理"
rm -f "$REPO/.probe-dirty-untracked" "$REPO/PROBE_SHOULD_FAIL" "$REPO/PROBE_OUTPUT"
git -C "$REPO" status --short | head -3
echo "(这里应当只剩 evidence 收据本身;CLAUDE.md 若被改动过就是探针漏了)"
git -C "$REPO" diff --stat -- CLAUDE.md

# ── 探针 2(2026-08-19 追加):整仓 ro 之后,能不能把 logs/ 单独开成可写?
#    这是实现的前提:腿日志就在仓内 logs/,写不了 = 防线把腿弄死了。
#    bind mount 的 ro 是 per-mount 的,子目录能不能 remount 回 rw —— 问真机,不推理。
say "4. 探针 2:整仓 ro + logs/ 单独 rw"
unshare -m bash -s <<'INNS2'
set -uo pipefail
REPO=/root/aiwork
mount --make-rprivate /
mount --bind "$REPO" "$REPO"
mount -o remount,ro,bind "$REPO"
r() { printf '  rc=%s  %s\n' "$1" "$2"; }

mount --bind "$REPO/logs" "$REPO/logs" 2>/dev/null;      r $? "bind logs/ 到自己"
mount -o remount,rw,bind "$REPO/logs" 2>/dev/null;       r $? "把 logs/ remount 回 rw"

echo "-- 期望:logs/ 可写,其余仍然只读 --"
touch "$REPO/logs/probe-rw.log" 2>/dev/null;             r $? "写 logs/(期望 0)"
rm -f "$REPO/logs/probe-rw.log" 2>/dev/null;             r $? "删 logs/ 里的文件(期望 0)"
touch "$REPO/PROBE_ROOT" 2>/dev/null;                    r $? "写仓根(期望非 0)"
touch "$REPO/bin/PROBE_BIN" 2>/dev/null;                 r $? "写 bin/(期望非 0)"
touch "$REPO/tests/PROBE_TESTS" 2>/dev/null;             r $? "写 tests/ 判据(期望非 0)"
git -C "$REPO" diff --output=/root/aiwork/PROBE_OUT HEAD 2>/dev/null; r $? "git diff --output=(期望非 0)"
echo "-- 读能力仍在?--"
( cd "$REPO" && git status --short >/dev/null 2>&1 );    r $? "git status"
( cd "$REPO" && git diff --stat >/dev/null 2>&1 );       r $? "git diff"
INNS2
echo "探针 2 整体 rc=$?"
rm -f "$REPO/PROBE_ROOT" "$REPO/PROBE_OUT" "$REPO/bin/PROBE_BIN" "$REPO/tests/PROBE_TESTS" 2>/dev/null
