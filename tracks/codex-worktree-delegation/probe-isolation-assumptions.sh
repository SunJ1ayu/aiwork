#!/usr/bin/env bash
# 设计期探针(不是 oracle)—— 攻 codex design.md 的三条前提,用机器答,不用嘴答。
#
# 跑法:runlog -t codex-worktree-delegation -n probe -- \
#         tracks/codex-worktree-delegation/probe-isolation-assumptions.sh
#
# 三条都在**临时仓**里跑,一个字节都不碰真仓;P2 只对 /root/aiwork 做拒发路径的
# --dry-run(它在起 codex 之前就 exit 2,不花额度、不写文件)。
set -uo pipefail
D="$(mktemp -d /tmp/probe-iso.XXXXXX)"
trap 'rm -rf "$D"' EXIT
DC=/root/aiwork/bin/delegate-codex

echo "############ P1:新建 worktree 会不会被「攻题记录过期」闸恒真拒发 ############"
cd "$D"
mkdir repo && cd repo && git init -q . && git config user.email t@t && git config user.name t
mkdir tests && echo 'def test_x(): assert 1' > tests/test_o.py
echo hi > impl.py && git add -A && git commit -qm "oracle first"
cd "$D"
sleep 1; echo "攻题记录:我攻过了" > attack.md; echo "# 任务" > task.md
echo "--- 控制组:派主工作树(判据比攻题记录旧 ⇒ 应放行)"
"$DC" --dry-run --repo "$D/repo" --task "$D/task.md" --attack-log "$D/attack.md" \
      --protect tests --log "$D/ctl.log" >/dev/null 2>&1
echo "    控制组 rc=$?  (0 = 放行)"
git -C repo worktree add -q "$D/wt" HEAD
echo "--- 实验组:同一份判据、同一份攻题记录,只是派进刚建的 worktree"
out="$("$DC" --dry-run --repo "$D/wt" --task "$D/task.md" --attack-log "$D/attack.md" \
             --protect tests --log "$D/wt.log" 2>&1)"; rc=$?
echo "    实验组 rc=$rc  (2 = 拒发)"
printf '%s\n' "$out" | sed -n '1,3p' | sed 's/^/    /'
echo "    判卷文件 mtime:$(stat -c %y "$D/wt/tests/test_o.py")"
echo "    攻题记录 mtime:$(stat -c %y "$D/attack.md")"
echo "    ⇒ worktree 是 checkout 出来的,判卷文件 mtime 恒等于建树那一刻 ⇒ 恒新于攻题记录。"

echo
echo "############ P2:目标仓就是 /root/aiwork 时,现有入口能不能派 ############"
"$DC" --dry-run --repo /root/aiwork --task "$D/task.md" --attack-log "$D/attack.md" \
      --protect bin/delegate-codex 2>&1 | sed -n '1,3p' | sed 's/^/    /'
echo "    ⇒ 默认日志落在 /root/aiwork/logs/ = 仓内 ⇒ 被「卷宗不许进仓」闸拒发。"

echo
echo "############ P3:派活后主 agent 改判据,闸① 算在谁头上 ############"
cd "$D/repo"
head_at_dispatch="$(git rev-parse HEAD)"
python3 - "$D/r.json" "$D/repo" "$head_at_dispatch" <<'PY'
import json,sys
r,repo,head=sys.argv[1:]
json.dump({"repo":repo,"head":head,"protect":["tests"]},open(r,"w"))
PY
echo "leg wrote this" > impl.py                                   # 腿改实现
echo 'def test_y(): assert 1' >> tests/test_o.py                  # 主 agent 修判据
git add -A tests && git commit -qm "主agent:修判据自己的漏"
echo "scratch" > my_note.txt                                      # 主 agent 的脏文件
"$DC" --receive "$D/r.json" 2>&1 | sed 's/^/    /'
echo "    ⇒ 腿一个判卷字节没碰,闸① 照样红;红的是主 agent 派活后自己那笔。"
