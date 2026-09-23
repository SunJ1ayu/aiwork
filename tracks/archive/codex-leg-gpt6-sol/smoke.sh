#!/bin/bash
# codex 腿冒烟:小仓里埋一个「加法写成减法」的 bug,subcodex 用 bin/codex-model 的模型真跑一次。
# 通过 = 日志回显的模型就是 bin/codex-model 里那个,且判 BLOCK(抓到了 bug)。
set -u
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
mkdir "$d/repo"; cd "$d/repo" && git init -q && printf 'def add(a, b):\n    return a - b\n' > m.py && git add . \
  && git -c user.email=x@x -c user.name=x commit -qm init || exit 1
printf '# 冒烟\n读 m.py:add 是否正确实现加法?一句话说明。\n最后一行:Conclusion: PASS / BLOCK / NEEDS_MORE_INFO\n' > "$d/task.md"
want=$(tr -d '[:space:]' < /root/aiwork/bin/codex-model)
REVIEW_NO_MY_REVIEW=1 timeout 600 /root/aiwork/bin/subcodex review "$d/task.md" "$d/log" "$d/repo" >/dev/null 2>&1; rc=$?
grep -E "^model:|^Conclusion" "$d/log"
[[ $rc -eq 0 ]] && grep -q "^model: $want " "$d/log" && grep -q "^Conclusion: BLOCK" "$d/log"
