#!/usr/bin/env bash
# track delegate-entry-redcheck 的判据(主 agent 亲写,执行腿逐字节 off-limits)。
#
# 判的是两件"把检查搬到成本花掉之前"的工具:
#   D `bin/delegate-codex` —— 派活入口:缺攻题记录 / 缺判卷清单就**拒发**(codex 一次都不启动),
#      自动注入派活三件套,派活时把 HEAD + protect 清单存进回执;
#      `--receive` 用同一份清单机械跑收货闸①。
#   E `bin/redcheck`     —— 退回红检:把实现真退回基线再 build 再跑 oracle,**必须红**;
#      跑完无条件恢复,并自证工作树干净。
#
# 判据锁死的几条"假绿路线":
#   ① 拒发只印了警告、其实还是把活派出去了  ⇒ 用**假 codex 的调用计数文件**证零调用,
#      不看脚本自己的输出(执行腿的自述一概不作数,这条对工具也一样)。
#   ② 闸①只跑 `git diff` ⇒ 往 protect 目录里塞一个未跟踪文件(conftest.py 那招)就能
#      让"亲跑全绿"变假绿。所以专门有一幕**只**新增未跟踪文件。
#   ③ 闸①宽到什么都报(误报=噪音=下次没人看) ⇒ 有一幕改的是非 protect 文件,必须放行。
#   ④ redcheck 说"红了"其实是自己炸了 ⇒ 有一幕让 oracle 在旧实现上**仍然绿**,必须判失败。
#   ⑤ redcheck 跑完把树留在"基线构建"的状态(本机 dist 入库,这是真会咬人的) ⇒
#      每一幕结束都查 `git status --porcelain`,还有一幕直接把它**中途杀掉**看恢不恢复。
#
# Run:  bash /root/aiwork/tests/test-delegate-entry.sh
set -uo pipefail

# 判卷面的不变量:**跑判据的进程不许有外网出口**(2026-08-10,track no-egress-judging)。
# 这一行把整个套件 exec 进一个没有出口的网络命名空间;做不到就拒跑。
. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78   # source 失败=裸跑,必须硬退
# 2026-08-11(track codex-worktree-delegation):派活闸的"攻题记录必须新过判卷"从 mtime
# 换成**内容哈希**,于是这份套件里每一次派活都得先给攻题记录盖上当前哈希。
# 本套件判的是**非隔离**那条老路(隔离由 tests/test-delegate-isolate.sh 判),
# 所以下面每一发都显式带 `--no-isolate`。
. "$(dirname "${BASH_SOURCE[0]}")/_oracle_hash.sh"

BIN="${DELEGATE_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

# 假 codex:把 argv 和收到的任务书落盘,并**记一次调用**。
# 计数文件是"它到底被调用了没有"的唯一证据 —— 拒发那几幕全靠它。
make_fake_codex() {  # make_fake_codex <bin目录> <计数/记录目录>
  local b="$1" rec="$2"
  mkdir -p "$b" "$rec"
  cat > "$b/codex" <<EOF
#!/usr/bin/env bash
rec="$rec"
echo "call" >> "\$rec/calls"
printf '%s\n' "\$@" > "\$rec/argv.\$(wc -l < "\$rec/calls" | tr -d ' ')"
# 任务书是最后一个位置参数
prompt="\${!#}"
printf '%s' "\$prompt" > "\$rec/prompt.\$(wc -l < "\$rec/calls" | tr -d ' ')"
exit 0
EOF
  chmod +x "$b/codex"
}
calls_of() { [[ -f "$1/calls" ]] && wc -l < "$1/calls" | tr -d ' ' || echo 0; }

# 一个有历史的临时仓:HEAD = 新实现,HEAD~1 = 旧实现(缺功能)。
make_repo() {  # make_repo <dir>
  local r="$1"; mkdir -p "$r/tests" "$r/src"
  ( cd "$r"
    git init -q -b main; git config user.email t@t; git config user.name t
    printf '#!/bin/bash\necho old\n' > src/impl.sh
    # 判卷:要求实现打印 NEW(旧实现打印 old ⇒ 旧实现下必红)
    cat > tests/oracle.sh <<'EOF'
#!/bin/bash
out="$(bash "$(dirname "$0")/../src/impl.sh")"
[[ "$out" == "NEW" ]] || { echo "FAIL: 期望 NEW,实际 $out"; exit 1; }
echo "ok - impl 输出 NEW"
EOF
    git add -A; git commit -qm "旧实现 + 判据"
    printf '#!/bin/bash\necho NEW\n' > src/impl.sh
    git add -A; git commit -qm "新实现" )
}

# ---------------------------------------------------------------- D:拒发
d_refuses_without_evidence() {
  echo "[D1] delegate-codex:缺攻题记录 / 缺判卷清单 ⇒ 拒发,且 codex 一次都不启动"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo"
  make_fake_codex "$b" "$rec"; make_repo "$repo"
  printf '# 任务书\n把 impl 改成打印 NEW\n' > "$d/task.md"
  printf '攻题记录:第 3 条断言在旧实现上也绿\n' > "$d/attack.md"
  local rc

  # ① 完全不给 --attack-log
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --protect tests/oracle.sh >"$d/o1" 2>&1; rc=$?
  check "D1: 没给 --attack-log ⇒ 非零" $([[ $rc -ne 0 ]]; echo $?)
  check "D1: 没给 --attack-log ⇒ codex 零调用" $([[ "$(calls_of "$rec")" -eq 0 ]]; echo $?)
  # 四审 subkimi F11:光断言"非零退出"的话,一个 `exit 2` 的空壳(甚至文件被删,bash 报 127)
  # 就能让 D1 全家恒绿 —— D1 问的必须是"它认出了缺什么",不是"它退出码非零"。
  grep -q -- "--attack-log" "$d/o1"; check "D1: 拒发时点名缺的是 --attack-log" $?

  # ② 给了但文件不存在
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/nope.md" --protect tests/oracle.sh >"$d/o2" 2>&1; rc=$?
  check "D1: attack-log 不存在 ⇒ 非零 + 零调用" \
    $([[ $rc -ne 0 && "$(calls_of "$rec")" -eq 0 ]]; echo $?)
  grep -qi "不存在" "$d/o2"; check "D1: 说清是攻题记录**不存在**" $?

  # ③ 存在但是空的("我写了个空文件应付"这条路要堵死)
  : > "$d/empty.md"
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/empty.md" --protect tests/oracle.sh >"$d/o3" 2>&1; rc=$?
  check "D1: attack-log 是空文件 ⇒ 非零 + 零调用" \
    $([[ $rc -ne 0 && "$(calls_of "$rec")" -eq 0 ]]; echo $?)
  grep -qi "空文件" "$d/o3"; check "D1: 说清是**空文件**应付" $?

  # ④ 攻题记录放在**仓内** = 把考卷的洞递给考生(和 panel-review 的 my-review 闸同源)
  cp "$d/attack.md" "$repo/attack.md"
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$repo/attack.md" --protect tests/oracle.sh >"$d/o4" 2>&1; rc=$?
  check "D1: attack-log 在仓内 ⇒ 非零 + 零调用(漏洞清单不许进考场)" \
    $([[ $rc -ne 0 && "$(calls_of "$rec")" -eq 0 ]]; echo $?)
  grep -qi "仓里\|仓内" "$d/o4"; check "D1: 说清是**在仓里**" $?
  rm -f "$repo/attack.md"

  # ⑤ 不给 --protect(守卫的强度只等于这份清单,没清单就没守卫)
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" >"$d/o5" 2>&1; rc=$?
  check "D1: 没给 --protect ⇒ 非零 + 零调用" \
    $([[ $rc -ne 0 && "$(calls_of "$rec")" -eq 0 ]]; echo $?)
  grep -q -- "--protect" "$d/o5"; check "D1: 拒发时点名缺的是 --protect" $?

  # ⑥ 攻题记录必须对得上**当前这版判卷**,否则攻的是上一版考卷,等于没攻
  #    (gpt-5.6-sol 双出方案点破的洞:我原来只查"非空 + 在仓外",
  #     而"攻完之后我又改了 oracle"这条路整条是敞开的)。
  #    2026-08-11 起判据从 **mtime** 换成**内容哈希**(track codex-worktree-delegation A1:
  #    worktree 是 checkout 出来的,mtime 恒新 ⇒ 那道 mtime 闸让隔离一次活都派不出去)。
  #    这一幕只钉"没盖当前哈希就拒发";哈希本身的全部性质在 test-delegate-isolate.sh 里判。
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/oracle.sh >"$d/o6" 2>&1; rc=$?
  check "D1: 攻题记录没盖当前判卷的哈希 ⇒ 非零 + 零调用(攻的是旧版考卷)" \
    $([[ $rc -ne 0 && "$(calls_of "$rec")" -eq 0 ]]; echo $?)
  grep -qi "oracle-sha256\|过期\|重新攻" "$d/o6"; check "D1: 说清是「攻题记录过期」,不是笼统报错" $?
  # 盖上就该放行 —— 少了这一半,一个"永远拒发"的实现也能让上面全绿
  stamp_hash "$d/attack.md" "$repo" tests/oracle.sh
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/oracle.sh --log "$d/o6b.log" >"$d/o6b" 2>&1; rc=$?
  check "D1: 盖上当前哈希 ⇒ 放行" $([[ $rc -eq 0 && "$(calls_of "$rec")" -eq 1 ]]; echo $?)
  rm -rf "$d"
}

# ---------------------------------------------------------------- D:派活
d_injects_and_records() {
  echo "[D2] delegate-codex:齐了就发,三件套逐字注入,回执记下派活那一刻"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo"
  make_fake_codex "$b" "$rec"; make_repo "$repo"
  printf '# 任务书\nMARKER_TASK_BODY\n' > "$d/task.md"
  printf '攻题记录:第 3 条断言在旧实现上也绿\n' > "$d/attack.md"
  local head_at_dispatch; head_at_dispatch="$(git -C "$repo" rev-parse HEAD)"
  local rc
  stamp_hash "$d/attack.md" "$repo" tests/oracle.sh tests/
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/oracle.sh --protect tests/ \
      --log "$d/run.log" >"$d/out" 2>&1; rc=$?
  check "D2: 材料齐 ⇒ rc=0" $([[ $rc -eq 0 ]]; echo $?)
  check "D2: codex 被调用了一次" $([[ "$(calls_of "$rec")" -eq 1 ]]; echo $?)

  local prompt="$rec/prompt.1" argv="$rec/argv.1"
  grep -q "MARKER_TASK_BODY" "$prompt"; check "D2: 原任务书正文在里面" $?
  grep -q "tests/oracle.sh" "$prompt"; check "D2: 每条 protect 路径逐条写进任务书" $?
  grep -qi "off-limits\|一个字都不许改\|不许改动" "$prompt"; check "D2: 三件套①判卷 off-limits" $?
  grep -q "回归" "$prompt" && grep -q "build" "$prompt"; check "D2: 三件套②自检清单" $?
  grep -q "push" "$prompt" && grep -q "merge" "$prompt"; check "D2: 三件套③不 push / 不 merge" $?
  grep -q "project_doc_max_bytes=0" "$argv"; check "D2: 命令行带 project_doc_max_bytes=0" $?
  grep -q '^\-m$' "$argv" || grep -q '^-m ' "$argv"; check "D2: 模型显式给 -m(不吃默认值)" $?

  # 回执:收货闸①要用的东西必须在派活那一刻就定死
  local receipt="$d/run.log.receipt.json"
  [[ -s "$receipt" ]]; check "D2: 写出回执 <log>.receipt.json" $?
  python3 - "$receipt" "$repo" "$head_at_dispatch" <<'EOF'
import json,sys
r=json.load(open(sys.argv[1])); repo,head=sys.argv[2],sys.argv[3]
assert r["repo"].rstrip("/")==repo.rstrip("/"), r["repo"]
assert r["head"]==head, (r["head"],head)
assert "tests/oracle.sh" in r["protect"] and "tests/" in r["protect"], r["protect"]
assert r["attack_log"].endswith("attack.md") and len(r["attack_log_sha256"])==64
EOF
  check "D2: 回执字段齐(repo/派活时 HEAD/protect 清单/攻题记录+sha256)" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- D:收货闸①
d_receive_gate() {
  echo "[D3] delegate-codex --receive:闸①机械版(diff 为空 **且** status 为空)"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo"
  make_fake_codex "$b" "$rec"; make_repo "$repo"
  printf '# 任务书\n干活\n' > "$d/task.md"
  printf '攻题记录:……\n' > "$d/attack.md"
  stamp_hash "$d/attack.md" "$repo" tests/
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/run.log" >/dev/null 2>&1
  local receipt="$d/run.log.receipt.json" rc

  # ① 执行腿只动了实现 ⇒ 放行
  printf '#!/bin/bash\necho NEW\necho more\n' > "$repo/src/impl.sh"
  bash "$BIN/delegate-codex" --receive "$receipt" >"$d/r1" 2>&1; rc=$?
  check "D3: 只动实现 ⇒ 闸①放行(不误报)" $([[ $rc -eq 0 ]]; echo $?)

  # ② 改了判卷文件(未提交)⇒ 拦
  printf 'echo tampered\n' >> "$repo/tests/oracle.sh"
  bash "$BIN/delegate-codex" --receive "$receipt" >"$d/r2" 2>&1; rc=$?
  check "D3: 改了判卷文件 ⇒ 拦下" $([[ $rc -ne 0 ]]; echo $?)
  grep -q "tests/oracle.sh" "$d/r2"; check "D3: 拦下时点名是哪个文件" $?
  git -C "$repo" checkout -- tests/oracle.sh

  # ③ 改了判卷文件**并提交** ⇒ 照样拦(diff 那一臂)
  printf 'echo tampered\n' >> "$repo/tests/oracle.sh"
  git -C "$repo" commit -qam "偷偷改判卷"
  bash "$BIN/delegate-codex" --receive "$receipt" >"$d/r3" 2>&1; rc=$?
  check "D3: 改判卷并提交了 ⇒ 照样拦" $([[ $rc -ne 0 ]]; echo $?)
  git -C "$repo" reset -q --hard HEAD~1

  # ④ **只**新增一个未跟踪文件(conftest.py 那招)⇒ 必须拦
  #    这一幕是整份判据里最值钱的:git diff 看不见它,亲读 diff 也照不到它。
  printf 'import pytest\n@pytest.fixture(autouse=True)\ndef always_pass(): pass\n' \
    > "$repo/tests/conftest.py"
  bash "$BIN/delegate-codex" --receive "$receipt" >"$d/r4" 2>&1; rc=$?
  check "D3: protect 目录下新增未跟踪文件 ⇒ 拦下(git diff 看不见它)" $([[ $rc -ne 0 ]]; echo $?)
  grep -q "conftest.py" "$d/r4"; check "D3: 拦下时点名那个未跟踪文件" $?
  rm -f "$repo/tests/conftest.py"

  # ⑤ 仓外的、非 protect 的改动 ⇒ 不许误报
  # ⚠️ 上一幕的 `git reset --hard` 会把第①幕对实现的改动一起 revert 掉 ——
  #    所以这里重新改一次,否则下面那条"列出改动清单"的断言**在这一幕里问不出来**
  #    (08-06 红检时先发现的就是这个夹具 bug,不是实现的问题)。
  printf '#!/bin/bash\necho NEW\necho more\n' > "$repo/src/impl.sh"
  printf 'noise\n' > "$repo/src/other.txt"
  bash "$BIN/delegate-codex" --receive "$receipt" >"$d/r5" 2>&1; rc=$?
  check "D3: 非 protect 路径的新增文件 ⇒ 放行(误报会让警告变噪音)" $([[ $rc -eq 0 ]]; echo $?)

  # ⑥ 放行时也要**列出执行腿到底动了哪些文件** —— 闸③(亲读 diff)需要这份清单,
  #    而"它自己说改了什么"一概不作数。gpt-5.6-sol 的双出方案用白名单
  #    (--allow-impl)做这件事;这里只列不判(白名单会在"执行腿合理新建文件"时误报)。
  grep -q "src/impl.sh" "$d/r5" && grep -q "src/other.txt" "$d/r5"
  check "D3: 放行时列出改动清单(含新增的未跟踪文件),给闸③当底账" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E:退回红检
e_redcheck() {
  echo "[E1] redcheck:把实现真退回基线再跑判据,必须红;跑完树要干净"
  local d; d="$(mktemp -d)"; local repo="$d/repo" rc
  make_repo "$repo"

  # ① 正常:旧实现下判据红 ⇒ 红检通过(rc=0)
  bash "$BIN/redcheck" --repo "$repo" --base HEAD~1 --impl src/impl.sh \
       --oracle 'bash tests/oracle.sh' >"$d/e1" 2>&1; rc=$?
  check "E1: 旧实现下判据红 ⇒ 红检通过(rc=0)" $([[ $rc -eq 0 ]]; echo $?)
  check "E1: 跑完工作树干净" $([[ -z "$(git -C "$repo" status --porcelain)" ]]; echo $?)
  [[ "$(bash "$repo/src/impl.sh")" == "NEW" ]]
  check "E1: 跑完实现真的恢复成 HEAD 那版" $?

  # ② 恒真判据:旧实现下也绿 ⇒ 必须报失败(这正是 08-05 手写桩没抓到的那种)
  cat > "$repo/tests/oracle.sh" <<'EOF'
#!/bin/bash
echo "ok - 前置恒真的断言"
exit 0
EOF
  git -C "$repo" commit -qam "把判据换成恒真的"
  bash "$BIN/redcheck" --repo "$repo" --base HEAD~2 --impl src/impl.sh \
       --oracle 'bash tests/oracle.sh' >"$d/e2" 2>&1; rc=$?
  check "E1: 旧实现下判据仍绿 ⇒ 报失败(rc≠0)" $([[ $rc -ne 0 ]]; echo $?)
  grep -qi "仍然绿\|没红\|恒真" "$d/e2"; check "E1: 失败时说清是「旧实现也过」" $?
  check "E1: 失败那次也把树恢复干净" $([[ -z "$(git -C "$repo" status --porcelain)" ]]; echo $?)
  git -C "$repo" reset -q --hard HEAD~1

  # ③ --build 真的被跑了,且恢复之后**再 build 一次**(本机 dist 入库,不重 build 就留了
  #    一棵"基线构建的树")
  bash "$BIN/redcheck" --repo "$repo" --base HEAD~1 --impl src/impl.sh \
       --build "echo built >> $d/builds" --oracle 'bash tests/oracle.sh' >"$d/e3" 2>&1
  check "E1: --build 跑了两次(退回后一次、恢复后一次)" \
    $([[ -f "$d/builds" && "$(wc -l < "$d/builds")" -eq 2 ]]; echo $?)

  # ④ 工作树脏 ⇒ 拒跑(不替人猜哪些改动该留),且一个字都不许动
  printf '#!/bin/bash\necho WIP\n' > "$repo/src/impl.sh"
  bash "$BIN/redcheck" --repo "$repo" --base HEAD~1 --impl src/impl.sh \
       --oracle 'bash tests/oracle.sh' >"$d/e4" 2>&1; rc=$?
  check "E1: impl 有未提交改动 ⇒ 拒跑" $([[ $rc -ne 0 ]]; echo $?)
  [[ "$(bash "$repo/src/impl.sh")" == "WIP" ]]
  check "E1: 拒跑时没动过工作区那份改动" $?
  git -C "$repo" checkout -- src/impl.sh

  # ⑤ 中途被杀 ⇒ 照样恢复(trap 那条)。这是"恢复"最难的一种,也是真会发生的一种。
  ( bash "$BIN/redcheck" --repo "$repo" --base HEAD~1 --impl src/impl.sh \
        --oracle 'sleep 30' >"$d/e5" 2>&1 ) &
  local pid=$!
  sleep 2; kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  sleep 1
  check "E1: 中途被 TERM 掉,工作树照样恢复" \
    $([[ -z "$(git -C "$repo" status --porcelain)" ]]; echo $?)
  [[ "$(bash "$repo/src/impl.sh")" == "NEW" ]]
  check "E1: 中途被杀后实现也回到 HEAD 那版" $?

  # ⑥ build 都没过 ⇒ **不算有效红检**(红在 build 上等于没红检过)。
  #    08-04 本机实证过同型:"红在 TypeError 上等于没红检过"。
  #    双出方案(gpt-5.6-sol)把这条拆得更细:超时/崩溃/收集失败/依赖缺失都不算红。
  bash "$BIN/redcheck" --repo "$repo" --base HEAD~1 --impl src/impl.sh \
       --build 'exit 1' --oracle 'bash tests/oracle.sh' >"$d/e6" 2>&1; rc=$?
  check "E1: build 失败 ⇒ 红检无效(非零)" $([[ $rc -ne 0 ]]; echo $?)
  grep -qi "build" "$d/e6" && grep -qi "无效\|不算" "$d/e6"
  check "E1: 说清是「build 没过,这次红检不算数」" $?
  check "E1: build 失败那次也把树恢复干净" $([[ -z "$(git -C "$repo" status --porcelain)" ]]; echo $?)

  # ⑦ --must-fail:红要红在**目标断言**上,不是红在别处。
  #    给一个判据里根本不会出现的标记 ⇒ 必须判失败(红错了地方)。
  bash "$BIN/redcheck" --repo "$repo" --base HEAD~1 --impl src/impl.sh \
       --must-fail "这句话判据里没有" --oracle 'bash tests/oracle.sh' >"$d/e7" 2>&1; rc=$?
  check "E1: 红了但不是目标断言红的 ⇒ 判失败" $([[ $rc -ne 0 ]]; echo $?)
  #    给真实的失败标记 ⇒ 通过
  bash "$BIN/redcheck" --repo "$repo" --base HEAD~1 --impl src/impl.sh \
       --must-fail "期望 NEW" --oracle 'bash tests/oracle.sh' >"$d/e8" 2>&1; rc=$?
  check "E1: 红在目标断言上 ⇒ 通过" $([[ $rc -eq 0 ]]; echo $?)
  #    ⑦b 判据输出很长、目标断言排在前面(真实回归套件就是这形状)⇒ 照样认得出。
  #    2026-09-14 实事故(track grok-leg-kimi-model):test-review-tooling.sh 红在
  #    「只改模型文件就改变实际 CLI 调用」上,redcheck 却报 rc=5「没红在该红的地方」。
  #    `printf "$OUT" | grep -q` 在 pipefail 下:grep 一命中就退,printf 还在写 ⇒ SIGPIPE
  #    ⇒ 管道 rc=141 ⇒ 「命中」被读成「没命中」。实测 40 次错 11~19 次;
  #    这里让命中之后还有 ~1MB 输出,把竞态变成确定事件。
  bash "$BIN/redcheck" --repo "$repo" --base HEAD~1 --impl src/impl.sh --must-fail "期望 NEW" \
       --oracle 'bash tests/oracle.sh; rc=$?; head -c 1000000 /dev/zero | tr "\0" x | fold -w 100; exit $rc' \
       >"$d/e8b" 2>&1; rc=$?
  check "E1: 目标断言在长输出前面 ⇒ 仍判红在目标上(rc=0,不许被 SIGPIPE 读成没命中)" $([[ $rc -eq 0 ]]; echo $?)

  # ⑧ --impl 里有**基线上还不存在的新文件**(整单新增一个工具就是这形状)。
  #    "退回"对它的正确含义是**删掉**,不是 checkout 报错就算了 ——
  #    08-06 拿 redcheck 红检 redcheck 自己时当场撞到的(git checkout <base> -- <新文件>
  #    直接 pathspec 报错)。这一幕同时钉死"跑完它要回来"。
  cat > "$repo/src/helper.sh" <<'EOF'
#!/bin/bash
echo helper
EOF
  cat > "$repo/tests/oracle.sh" <<'EOF'
#!/bin/bash
[[ -f "$(dirname "$0")/../src/helper.sh" ]] || { echo "FAIL: helper.sh 不存在"; exit 1; }
echo "ok - helper 在"
EOF
  git -C "$repo" add -A; git -C "$repo" commit -qm "新增 helper + 对应判据"
  bash "$BIN/redcheck" --repo "$repo" --base HEAD~1 --impl src/helper.sh \
       --must-fail "helper.sh 不存在" --oracle 'bash tests/oracle.sh' >"$d/e9" 2>&1; rc=$?
  check "E1: 基线上不存在的新实现 ⇒ 退回=删掉它,判据照样红" $([[ $rc -eq 0 ]]; echo $?)
  check "E1: 跑完那个新文件回来了" $([[ -f "$repo/src/helper.sh" ]]; echo $?)
  check "E1: 跑完工作树仍然干净" $([[ -z "$(git -C "$repo" status --porcelain -uall)" ]]; echo $?)

  # ⑨ `--impl a b`(变长)要和 `--impl a --impl b` 一样认 —— 用法里写的就是 `--impl PATH...`,
  #    而 08-06 第一次真用它时我照着用法敲,被"不认识的参数"顶了回来。
  #    工具的用法说明和它的解析对不上,下次照样会撞;这一条把两者钉在一起。
  bash "$BIN/redcheck" --repo "$repo" --base HEAD~1 --impl src/helper.sh src/impl.sh \
       --oracle 'bash tests/oracle.sh' >"$d/e10" 2>&1; rc=$?
  check "E1: --impl 接多个路径(变长写法)也认" $([[ $rc -eq 0 ]]; echo $?)

  # ⑩ **构建产物按内容改名**(vite 那种 index-<hash>.js,而且 dist 入库)。
  #    08-06 在 design-studio 上真跑一次真 build 时抓到的:退回后 build 出的是
  #    **基线那个文件名**,恢复时 `git checkout HEAD -- <路径>` 只按 HEAD 的文件名铺,
  #    基线那份留在索引里 ⇒ 工作树没干净。当时是"恢复自证"那道闸响的(rc=9,大声退出),
  #    没有静默把一棵混合树留在盘上 —— 但**响了不等于修了**,这一幕要求它真的收拾干净。
  local r2="$d/repo2"; mkdir -p "$r2/src" "$r2/out" "$r2/tests"
  # ⚠️ BUILD **不带** `rm -f out/asset-*.js`(四审 subdeepseek F11 抓的):
  #    带了的话,恢复时那次 build 会把基线残留的产物顺手删掉 ⇒
  #    就算把 restore 里的 `git clean` 整步删掉,这一幕照样全绿 —— 判据钉不住它。
  #    真实的 vite 会清 dist,但**红检要问的是恢复逻辑自己干不干净**,不是靠 build 兜底。
  local BUILD='mkdir -p out; echo built > "out/asset-$(md5sum < src/impl.sh | cut -c1-6).js"'
  ( cd "$r2"
    git init -q -b main; git config user.email t@t; git config user.name t
    printf '#!/bin/bash\necho old\n' > src/impl.sh
    cat > tests/oracle.sh <<'EOF'
#!/bin/bash
out="$(bash "$(dirname "$0")/../src/impl.sh")"
[[ "$out" == "NEW" ]] || { echo "FAIL: 期望 NEW,实际 $out"; exit 1; }
echo "ok"
EOF
    bash -c "$BUILD"; git add -A; git commit -qm "旧实现 + 旧产物"
    printf '#!/bin/bash\necho NEW\n' > src/impl.sh
    rm -f out/asset-*.js                      # 建仓时手工清(模拟 vite 清 dist)
    bash -c "$BUILD"; git add -A; git commit -qm "新实现 + 新产物" )
  bash "$BIN/redcheck" --repo "$r2" --base HEAD~1 --impl src/impl.sh out \
       --build "$BUILD" --oracle 'bash tests/oracle.sh' >"$d/e11" 2>&1; rc=$?
  check "E1: 产物按内容改名时红检照常通过" $([[ $rc -eq 0 ]]; echo $?)
  check "E1: **基线那份产物被收拾干净**(git status 为空,不是只喊一声)" \
    $([[ -z "$(git -C "$r2" status --porcelain -uall)" ]]; echo $?)

  # ⑪ 【高危】`--impl` 指到仓外 ⇒ 必须拒跑,**一个字节都不许删**。
  #    四审 subkimi 抓的(subdeepseek 判成"低危、预检已挡"是错的,我核实过:
  #    预检 `git status ... -- ../x` 的报错走 stderr,stdout 为空 ⇒ 静默放行,
  #    然后 `rm -rf "$REPO/../x"` 真删,收尾自证同样 stdout 为空 ⇒ 还打印"✅ 已恢复")。
  #    这条不需要攻击者,**敲错一个路径就够**。
  local victim="$d/仓外的重要文件.txt"
  printf 'DO_NOT_DELETE\n' > "$victim"
  bash "$BIN/redcheck" --repo "$r2" --base HEAD~1 --impl ../../"$(basename "$d")"/仓外的重要文件.txt \
       --oracle 'true' >"$d/e12" 2>&1; rc=$?
  check "E1: --impl 指到仓外 ⇒ 拒跑(rc≠0)" $([[ $rc -ne 0 ]]; echo $?)
  check "E1: **仓外那个文件必须还在**(不许 rm -rf 出去)" $([[ -f "$victim" ]]; echo $?)
  grep -qi "仓外\|仓库之外\|outside" "$d/e12"; check "E1: 拒跑时说清是「路径在仓外」" $?

  # ⑫ 恢复时 build 失败 ⇒ **不许说"已恢复,干净"**(自证的意义就在这)。
  #    subdeepseek F6:原来只 echo 一句警告就照常 exit 0。
  local r3="$d/repo3"; cp -a "$r2" "$r3"
  bash "$BIN/redcheck" --repo "$r3" --base HEAD~1 --impl src/impl.sh \
       --build "if [ -f $d/first_build_done ]; then exit 1; fi; touch $d/first_build_done" \
       --oracle 'bash tests/oracle.sh' >"$d/e13" 2>&1; rc=$?
  check "E1: 恢复时 build 失败 ⇒ 非零退出(不许照常报成功)" $([[ $rc -ne 0 ]]; echo $?)
  if grep -q "已恢复,工作树干净" "$d/e13"; then
    bad "E1: 恢复 build 失败时**不许**打印「已恢复,工作树干净」"
  else
    ok "E1: 恢复 build 失败时**不许**打印「已恢复,工作树干净」"
  fi

  # ⑬ 【2026-08-07 实事故】**判据必须跑盘上那份源码,不许跑残留的字节码缓存。**
  #    那天晚上我手搓红检:把 `fence_end = f"…{nonce}…"` 换成 `"…deadbeef…"`,
  #    **两串恰好一样长**,加上还原时 mtime 落在同一秒 —— CPython 的 .pyc 有效性
  #    检查(源文件 mtime + size)整个通过,于是"红检"跑的是**旧字节码**:
  #    先报了一句"这是死判据"(假绿),还原之后又在干净的树上假红。
  #    `redcheck` 走的是同一条路(`git checkout` 之后 mtime 也是新的、同长度回退
  #    照样撞得上),只是概率事件,没撞上不代表它对。
  #
  #    这一幕**不复现那个概率**:用 unchecked-hash 的 .pyc(PEP 552,Python 从不
  #    拿它跟源码比对)把"缓存被信任"变成确定事件。问的是同一件事 ——
  #    缓存还在,判据跑的就不是盘上那份代码。
  local pr="$d/pyrepo"; mkdir -p "$pr/src" "$pr/tests"
  ( cd "$pr"
    git init -q -b main; git config user.email t@t; git config user.name t
    printf 'VALUE = "old!"\n' > src/impl.py          # 和新版**同样长度**,就像那天晚上
    cat > tests/oracle.py <<'EOF'
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
import impl
assert impl.VALUE == "NEW!", f"FAIL: 期望 NEW!,实际 {impl.VALUE}"
print("ok - impl.VALUE 是 NEW!")
EOF
    git add -A; git commit -qm "旧实现 + 判据"
    printf 'VALUE = "NEW!"\n' > src/impl.py
    git add -A; git commit -qm "新实现" )
  # 在**新实现**上先跑一遍判据(真实工作流里本来就会先跑),并把缓存钉成"永远可信"
  ( cd "$pr" && python3 -c "
import py_compile
py_compile.compile('src/impl.py', doraise=True,
                   invalidation_mode=py_compile.PycInvalidationMode.UNCHECKED_HASH)" )
  check "E1: 夹具就位(缓存里存着新实现的字节码)" \
    $([[ -n "$(find "$pr/src/__pycache__" -name 'impl*.pyc' 2>/dev/null)" ]]; echo $?)
  bash "$BIN/redcheck" --repo "$pr" --base HEAD~1 --impl src/impl.py \
       --oracle 'python3 tests/oracle.py' >"$d/e14" 2>&1; rc=$?
  check "E1: 退回后判据跑的是**盘上的源码**,不是残留的 .pyc(否则假绿说它是死判据)" \
    $([[ $rc -eq 0 ]]; echo $?)
  #    这一条断的是"缓存**没被留在盘上**":`src/__pycache__` 是未跟踪的,
  #    留着它 `git status` 就不空。顺带钉住"清缓存不许把树弄脏"。
  check "E1: 跑完盘上没留下 .pyc 缓存(git status 空)" \
    $([[ -z "$(git -C "$pr" status --porcelain)" ]]; echo $?)

  # ⑭ 【四审 subdeepseek F4】事故的**另一半**:还原之后在**干净的树**上假红。
  #    ⑬ 只钉住了"退回之后跑的是盘上的源码";`restore()` 里那次清缓存它证明不了 ——
  #    一个"只在退回后清一次 + `PYTHONDONTWRITEBYTECODE=1`"的实现也能让 ⑬ 全绿。
  #    这里让**判据自己**每跑一次就把当前源码钉成 unchecked-hash 的字节码
  #    (复刻"缓存被信任",只是确定而非概率),redcheck 跑完之后**再单独跑一次
  #    只 import 不编译**的检查:restore 不清缓存的话,盘上留的是**基线**那版被钉死的
  #    字节码 ⇒ 干净树上假红,正是那天晚上我以为"自己刚提交的改动把它弄坏了"那一幕。
  local pr2="$d/pyrepo2"; mkdir -p "$pr2/src" "$pr2/tests"
  ( cd "$pr2"
    git init -q -b main; git config user.email t@t; git config user.name t
    cat > tests/oracle.py <<'EOF'
import os, sys, py_compile
SRC = os.path.join(os.path.dirname(__file__), "..", "src")
py_compile.compile(os.path.join(SRC, "impl.py"), doraise=True,
                   invalidation_mode=py_compile.PycInvalidationMode.UNCHECKED_HASH)
sys.path.insert(0, SRC)
import impl
assert impl.VALUE == "NEW!", f"FAIL: 期望 NEW!,实际 {impl.VALUE}"
print("ok - impl.VALUE 是 NEW!")
EOF
    cat > tests/check_clean.py <<'EOF'
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
import impl          # 只 import,**不重新编译** —— 残留的字节码在这里说话
assert impl.VALUE == "NEW!", f"FAIL: 干净树上却读到 {impl.VALUE}(假红)"
print("ok - 干净树上判据是绿的")
EOF
    printf 'VALUE = "old!"\n' > src/impl.py
    git add -A; git commit -qm "旧实现 + 判据"
    printf 'VALUE = "NEW!"\n' > src/impl.py
    git add -A; git commit -qm "新实现" )
  bash "$BIN/redcheck" --repo "$pr2" --base HEAD~1 --impl src/impl.py \
       --oracle 'python3 tests/oracle.py' >"$d/e15" 2>&1; rc=$?
  check "E1: (另一半)退回那一跑照样判红" $([[ $rc -eq 0 ]]; echo $?)
  ( cd "$pr2" && python3 tests/check_clean.py ) >"$d/e15b" 2>&1; rc=$?
  check "E1: 还原之后在**干净的树**上判据必须绿 —— 否则就是那天晚上的假红" \
    $([[ $rc -eq 0 ]]; echo $?)

  # ⑮ 【四审 subdeepseek F3 起的头,方向我核对过一遍才落这一幕】
  #    "被 git 跟踪就跳过"那一判用的是 **pathspec,默认按 glob 解释**
  #    (实测 `git ls-files -- 'bin/[r]edcheck'` 命中 `bin/redcheck`)。
  #    危险方向是 **fail-open**:目录名带 glob 字符的**未跟踪**缓存,
  #    撞上一个 glob 匹配得上的**已跟踪**路径 ⇒ 误判"被跟踪" ⇒ 跳过不清
  #    ⇒ 残留旧字节码 ⇒ **假绿**(防线的洞,不是响亮的报错)。
  #    腿给的例子(跟踪的是 `a1/__pycache__/*.pyc`)我试过**不成立**:
  #    带通配符的 pathspec 不做目录前缀展开,匹不上目录下的文件。
  #    真能撞上的形状是**已跟踪的同名普通文件**(`a1/__pycache__` 是个 file)——
  #    造作,但确定可复现,而 `:(literal)` 正好整类清掉。
  local pr3="$d/pyrepo3"; mkdir -p "$pr3/src" "$pr3/tests" "$pr3/a1"
  ( cd "$pr3"
    git init -q -b main; git config user.email t@t; git config user.name t
    printf 'VALUE = "old!"\n' > src/impl.py
    printf 'grep -q "NEW!" src/impl.py\n' > tests/oracle.sh
    printf 'not a dir\n' > a1/__pycache__          # **已跟踪的普通文件**,故意的
    mkdir -p b1/__pycache__; printf 'keep\n' > b1/__pycache__/keep.pyc  # **已跟踪的真缓存目录**
    git add -A; git commit -qm "旧实现 + 判据"
    printf 'VALUE = "NEW!"\n' > src/impl.py
    git add -A; git commit -qm "新实现" )
  mkdir -p "$pr3/a[1]/__pycache__"; printf 'stale\n' > "$pr3/a[1]/__pycache__/stale.pyc"
  bash "$BIN/redcheck" --repo "$pr3" --base HEAD~1 --impl src/impl.py \
       --oracle 'bash tests/oracle.sh' >"$d/e16" 2>&1
  check "E1: 目录名带 glob 字符时缓存照样清掉(pathspec 必须按字面量比,不然假绿)" \
    $([[ ! -e "$pr3/a[1]/__pycache__/stale.pyc" ]]; echo $?)
  check "E1: 被跟踪的那个同名文件一个字节都不许动" \
    $([[ -f "$pr3/a1/__pycache__" ]]; echo $?)
  # "跟踪就跳过"那条分支本身也要有人钉住,否则一个"全删"的实现照样能让上面两条绿。
  check "E1: **被跟踪的**真 __pycache__ 目录跳过不清(删了会把树弄脏)" \
    $([[ -f "$pr3/b1/__pycache__/keep.pyc" ]]; echo $?)
  check "E1: 跳过时要吼一声,不许静默(那个目录就是这道防线的洞)" \
    $([[ "$(grep -c '被 git 跟踪,没清' "$d/e16")" -ge 1 ]]; echo $?)

  rm -rf "$d"
}

# ---------------------------------------------------- D:四审补的拒发/闸①盲区
d_gate_blind_spots() {
  echo "[D4] 四审补的洞:判卷被 gitignore / skip-worktree / 回执落仓内 / 沙箱参数"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo" rc
  make_fake_codex "$b" "$rec"; make_repo "$repo"
  printf '# 任务书\nMARKER\n' > "$d/task.md"
  printf '攻题记录:……\n' > "$d/attack.md"

  # ① 沙箱参数必须显式(subkimi F12:丢掉 -s workspace-write / -C 判据照样全绿,
  #    而那等于把腿升成全权限)
  stamp_hash "$d/attack.md" "$repo" tests/oracle.sh
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/oracle.sh --log "$d/run.log" >/dev/null 2>&1
  grep -q 'workspace-write' "$rec/argv.1"; check "D4: 命令行显式给 -s workspace-write" $?
  grep -qx -- "-C" "$rec/argv.1" && grep -qx -- "$repo" "$rec/argv.1"
  check "D4: 命令行显式给 -C <仓>(不靠 cwd)" $?

  # ② 判卷文件被 .gitignore 藏起来 ⇒ 拒发(subdeepseek F2:执行腿只要往 .gitignore
  #    追一行,再塞 conftest.py,闸①两臂全空 —— D3④ 那招被绕过)
  printf 'tests/conftest.py\n' > "$repo/.gitignore"
  git -C "$repo" add -A >/dev/null 2>&1; git -C "$repo" commit -qm "ignore 一条"
  printf 'import pytest\n' > "$repo/tests/conftest.py"   # ← 真造出那个被藏起来的文件
  stamp_hash "$d/attack.md" "$repo" tests/
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/g1.log" >"$d/g1" 2>&1; rc=$?
  check "D4: 判卷路径下有被 ignore 的东西 ⇒ 拒发" $([[ $rc -ne 0 ]]; echo $?)
  grep -qi "ignore\|忽略" "$d/g1"; check "D4: 说清是被 gitignore 藏住了" $?
  # 收拾干净:留着它的话,下一幕撤掉 .gitignore 后那个 `git add -A` 会把它**提交进仓**,
  # 于是 ②c 里"被 ignore 的 conftest.py 仍要拒"就问不出来了(tracked 文件不算被藏)。
  rm -f "$repo/tests/conftest.py"
  git -C "$repo" rm -q --cached .gitignore >/dev/null 2>&1; rm -f "$repo/.gitignore"
  git -C "$repo" commit -qm "撤掉 ignore" >/dev/null 2>&1

  # ②b `__pycache__` 是**唯一的例外**,而且必须是例外(2026-08-07 实事故):
  #    python 仓库跑一次判据就会在判卷目录里生成 `tests/__pycache__/*.pyc`,它们被
  #    gitignore 忽略 ⇒ 上面那道闸**永远过不去**,删了也立刻长回来。
  #    放行它安全的理由是**验过的,不是想当然**:PEP 3147 布局下,
  #    `__pycache__/x.pyc` 没有对应的 `x.py` 就 import 不进来(当场试过:
  #    只留 .pyc 删掉源码 ⇒ `No module named 'ghost'`)⇒ 藏不了判卷逻辑。
  #    **只放 `__pycache__`,别的 ignored 文件照拒。**
  printf '__pycache__/\n' > "$repo/.gitignore"
  git -C "$repo" add -A >/dev/null 2>&1; git -C "$repo" commit -qm "ignore pycache"
  mkdir -p "$repo/tests/__pycache__"; printf 'x' > "$repo/tests/__pycache__/o.cpython-312.pyc"
  stamp_hash "$d/attack.md" "$repo" tests/   # 改过 .gitignore ⇒ 重新攻一遍再盖哈希(那道过期闸是对的,不绕它)
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/g2.log" >"$d/g2" 2>&1; rc=$?
  check "D4: 判卷目录里只有 __pycache__ 被 ignore ⇒ 照发(否则 python 仓永远派不出活)" \
        $([[ $rc -eq 0 ]]; echo $?)
  # 同一份 .gitignore 下,真正会藏东西的文件仍要拒 —— 防止上面那条被写成"全放行"
  printf '__pycache__/\ntests/conftest.py\n' > "$repo/.gitignore"
  git -C "$repo" add -A >/dev/null 2>&1; git -C "$repo" commit -qm "再 ignore conftest"
  printf 'x\n' > "$repo/tests/conftest.py"; stamp_hash "$d/attack.md" "$repo" tests/
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/g3.log" >"$d/g3" 2>&1; rc=$?
  check "D4: 放行 __pycache__ 之后,被 ignore 的 conftest.py 仍然拒发" \
        $([[ $rc -ne 0 ]]; echo $?)

  # ②c 【四审 subdeepseek F5;subkimi 额度用尽前的日志里也独立指到同一处;主 agent 亦然】
  #    上面那条放行当初写成了 `grep -v '__pycache__'` —— **子串匹配,不是路径成分匹配**。
  #    执行腿同时握着 `.gitignore` 和文件名 ⇒ 只要名字里带上这个子串,它就能在判卷目录里
  #    放一个闸①三条臂全照不到的文件。而放行的安全性论证(PEP 3147:没有源码的 .pyc
  #    import 不进来)对这种文件**根本不成立** —— 它压根不是字节码。
  printf '__pycache__/\ntests/__pycache__-evil/\n' > "$repo/.gitignore"
  git -C "$repo" add -A >/dev/null 2>&1; git -C "$repo" commit -qm "ignore 伪缓存目录"
  mkdir -p "$repo/tests/__pycache__-evil"
  printf 'x\n' > "$repo/tests/__pycache__-evil/conftest.py"
  stamp_hash "$d/attack.md" "$repo" tests/
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/g4.log" >"$d/g4" 2>&1; rc=$?
  check "D4: 名字里带 __pycache__ 的**伪**缓存目录不算例外,照样拒发" \
        $([[ $rc -ne 0 ]]; echo $?)
  printf '__pycache__/\ntests/x__pycache__conftest.py\n' > "$repo/.gitignore"
  git -C "$repo" add -A >/dev/null 2>&1; git -C "$repo" commit -qm "ignore 伪缓存文件"
  printf 'x\n' > "$repo/tests/x__pycache__conftest.py"
  stamp_hash "$d/attack.md" "$repo" tests/
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/g5.log" >"$d/g5" 2>&1; rc=$?
  check "D4: 文件名里带 __pycache__ 也不算例外,照样拒发" \
        $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$repo/tests/__pycache__-evil" "$repo/tests/x__pycache__conftest.py"

  rm -rf "$repo/tests/__pycache__" "$repo/tests/conftest.py"
  git -C "$repo" rm -q --cached .gitignore >/dev/null 2>&1; rm -f "$repo/.gitignore"
  git -C "$repo" commit -qm "撤掉 ignore2" >/dev/null 2>&1

  # ③ 判卷被 skip-worktree/assume-unchanged 标记 ⇒ 闸① 两臂同时失明(subdeepseek F1)
  stamp_hash "$d/attack.md" "$repo" tests/
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/s1.log" >/dev/null 2>&1
  git -C "$repo" update-index --skip-worktree tests/oracle.sh
  printf 'echo tampered\n' >> "$repo/tests/oracle.sh"
  bash "$BIN/delegate-codex" --receive "$d/s1.log.receipt.json" >"$d/s1" 2>&1; rc=$?
  check "D4: 判卷被 skip-worktree 标记后改动 ⇒ 闸①仍要拦" $([[ $rc -ne 0 ]]; echo $?)
  git -C "$repo" update-index --no-skip-worktree tests/oracle.sh
  git -C "$repo" checkout -- tests/oracle.sh

  # ④ 回执/日志落在**被派活的仓里** ⇒ 执行腿能改回执让闸①自证(subdeepseek F15 / subkimi F3)
  # 调用数写成"这一次没变",不写累计常数:常数会让"加一幕"顺带改断言,
  # 而改断言正是最容易把闸悄悄放松的动作(2026-08-07 加 __pycache__ 那一幕时撞到)。
  _calls_before="$(calls_of "$rec")"
  stamp_hash "$d/attack.md" "$repo" tests/
  env PATH="$b:$PATH" bash "$BIN/delegate-codex" --no-isolate --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$repo/inside.log" >"$d/i1" 2>&1; rc=$?
  check "D4: 日志/回执落在仓内 ⇒ 拒发(和攻题记录同源:考生不许碰卷宗)" $([[ $rc -ne 0 ]]; echo $?)
  check "D4: 拒发时 codex 也没被调用" \
        $([[ "$(calls_of "$rec")" -eq "$_calls_before" ]]; echo $?)
  rm -rf "$d"
}

echo "=== delegate-entry / redcheck oracle ==="
d_refuses_without_evidence
d_injects_and_records
d_receive_gate
d_gate_blind_spots
e_redcheck
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
