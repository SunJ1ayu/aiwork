#!/usr/bin/env bash
# track codex-worktree-delegation 的判据(主 agent 亲写,执行腿逐字节 off-limits)。
#
# 判的是 `bin/delegate-codex` 的两件新能力(规格在 git 历史里):
#   H 攻题新鲜度从 **mtime** 换成**内容哈希**(P0 前置);
#   I 派活默认在**独立 worktree** 里跑(`--isolate` 默认开,`--no-isolate` 退出);
#   R 回执 + 收货闸① 全部改看那棵树。
#
# 这份判据锁死的"假绿路线"(每一条都对应 design 里一条被机器证明过的攻击):
#   ① 哈希两边一起错 ⇒ 判据**独立算一遍**(find + sha256sum,实现走 python os.walk),
#      不调被测代码。见 tests/_oracle_hash.sh 顶部。
#   ② "默认开"被写成"印一句话但没真建树" ⇒ 一律不看它的输出,看
#      **codex 命令行上的 -C 指到哪**、树在不在、树的 HEAD 是不是基线。
#   ③ 闸①改跑 worktree 了、底账却还留在主树 ⇒ 专门有一幕在主树里制造改动,断言底账里没有它。
#   ④ A3(这一单存在的理由)⇒ 派活后主 agent 在主树提交判据修复:隔离下必须放行,
#      **同一场景非隔离下必须红**。两边都断言,免得"隔离下放行"其实是闸整个瞎了。
#   ⑤ 卷宗规则从"不许进仓"放宽成"不许进腿能写的树"⇒ 专门有一幕证明它没放宽过头
#      (落进 worktree 根、或攻题记录**被 git 跟踪**从而会被 checkout 进树 ⇒ 照拒)。
#
# Run:  bash /root/aiwork/tests/test-delegate-isolate.sh
set -uo pipefail

# 判卷面的不变量:**跑判据的进程不许有外网出口**(track no-egress-judging)。
. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78   # source 失败=裸跑,必须硬退
. "$(dirname "${BASH_SOURCE[0]}")/_oracle_hash.sh"

BIN="${DELEGATE_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

# 假 codex:记调用、存 argv/任务书,并**按 -C 指的目录真去写文件** ——
# 隔离这件事只能靠"腿写下的东西落在哪"来证,不能靠脚本自己的输出。
make_fake_codex() {  # make_fake_codex <bin目录> <记录目录>
  local b="$1" rec="$2"
  mkdir -p "$b" "$rec"
  cat > "$b/codex" <<EOF
#!/usr/bin/env bash
rec="$rec"
echo "call" >> "\$rec/calls"
n="\$(wc -l < "\$rec/calls" | tr -d ' ')"
printf '%s\n' "\$@" > "\$rec/argv.\$n"
prompt="\${!#}"
printf '%s' "\$prompt" > "\$rec/prompt.\$n"
wd=""; prev=""
for a in "\$@"; do [[ "\$prev" == "-C" ]] && wd="\$a"; prev="\$a"; done
if [[ -n "\$wd" && -d "\$wd" ]]; then
  printf '%s\n' "\$wd" > "\$rec/cwd.\$n"
  printf 'leg was here\n' > "\$wd/LEG_WROTE.txt"
  [[ -f "\$wd/src/impl.sh" ]] && printf '#!/bin/bash\necho NEW\necho leg-touched\n' > "\$wd/src/impl.sh"
fi
exit 0
EOF
  chmod +x "$b/codex"
}
calls_of() { [[ -f "$1/calls" ]] && wc -l < "$1/calls" | tr -d ' ' || echo 0; }
# codex 命令行上 `-C` 的值 —— "它到底在哪棵树上跑"的唯一非自述证据
c_dir_of() { awk '$0=="-C"{getline; print; exit}' "$1"; }

make_repo() {  # make_repo <dir>
  local r="$1"; mkdir -p "$r/tests" "$r/src"
  ( cd "$r"
    git init -q -b main; git config user.email t@t; git config user.name t
    printf '#!/bin/bash\necho NEW\n' > src/impl.sh
    printf 'noise\n' > src/other.txt
    cat > tests/oracle.sh <<'EOF'
#!/bin/bash
out="$(bash "$(dirname "$0")/../src/impl.sh")"
[[ "$out" == NEW* ]] || { echo "FAIL: 期望 NEW,实际 $out"; exit 1; }
echo "ok"
EOF
    git add -A; git commit -qm "实现 + 判据" )
}

# ================================================================ H:内容哈希闸
h_hash_gate() {
  echo "[H1] 攻题新鲜度 = 判卷面的**内容哈希**,不是 mtime"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo" wt="$d/wt" rc
  make_fake_codex "$b" "$rec"; make_repo "$repo"
  printf '# 任务书\n干活\n' > "$d/task.md"
  printf '攻题记录:第 3 条断言在旧实现上也绿\n' > "$d/attack.md"
  local run="env PATH=$b:$PATH DELEGATE_WORKTREE_ROOT=$wt"

  # ① 攻题记录里没有当前判卷面的哈希 ⇒ 拒发,而且要把该贴的那一行原样给出来
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/a.log" >"$d/o1" 2>&1; rc=$?
  check "H1: 攻题记录里没有 oracle-sha256 ⇒ 拒发" $([[ $rc -ne 0 ]]; echo $?)
  check "H1: 拒发时 codex 零调用" $([[ "$(calls_of "$rec")" -eq 0 ]]; echo $?)
  local want; want="oracle-sha256: $(oracle_hash "$repo" tests/)"
  grep -Fq "$want" "$d/o1"
  check "H1: 拒发信息里给出**该贴的那一行**(判据独立算的哈希,不问它要)" $?
  # 攻我自己的题:闸必须排在**建树之前** —— 否则每拒一次就攒一棵半截树,
  # 正好复现 `worktrees/mcp-registry` 那种"没人收的树"(采纳·3 的反面证据)。
  check "H1: 拒发时不许留下半棵树" $([[ ! -d "$wt" || -z "$(ls -A "$wt" 2>/dev/null)" ]]; echo $?)

  # ② 贴上去就放行
  stamp_hash "$d/attack.md" "$repo" tests/
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/b.log" >"$d/o2" 2>&1; rc=$?
  check "H1: 贴上当前哈希 ⇒ 放行(rc=0)" $([[ $rc -eq 0 ]]; echo $?)
  check "H1: 放行时 codex 被调用了一次" $([[ "$(calls_of "$rec")" -eq 1 ]]; echo $?)

  # ③ **判卷内容变了就作废**(这是原 mtime 闸唯一真正管住的事,不许在换实现时丢掉)
  printf 'echo "多一条断言"\n' >> "$repo/tests/oracle.sh"
  git -C "$repo" commit -qam "我又改了判据,但忘了重攻"
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/c.log" >"$d/o3" 2>&1; rc=$?
  check "H1: 判卷改了、攻题记录没跟上 ⇒ 拒发(攻的是上一版考卷)" $([[ $rc -ne 0 ]]; echo $?)
  git -C "$repo" reset -q --hard HEAD~1

  # ④ 【A1 的根因】**mtime 新但内容没变 ⇒ 必须照发**。
  #    worktree 是 checkout 出来的,判卷文件 mtime 恒新于攻题记录 ——
  #    旧的 mtime 闸在这一幕上 100% 拒发,隔离层一次活都派不出去(design A1,有收据)。
  touch "$repo/tests/oracle.sh"
  local _c; _c="$(calls_of "$rec")"
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/d.log" >"$d/o4" 2>&1; rc=$?
  check "H1: 判卷文件被 touch 成最新、内容没变 ⇒ 照发(A1:否则隔离恒被拒)" $([[ $rc -eq 0 ]]; echo $?)
  check "H1: 那一发是真发出去的(调用数 +1)" $([[ "$(calls_of "$rec")" -eq $((_c+1)) ]]; echo $?)

  # ⑤ 判卷目录里**新增一个文件**(旧文件一个字节没动)⇒ 哈希必须变 ⇒ 拒发
  printf 'x\n' > "$repo/tests/helper.sh"; git -C "$repo" add -A; git -C "$repo" commit -qm "加一个判据夹具"
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/e.log" >"$d/o5" 2>&1; rc=$?
  check "H1: 判卷目录新增文件 ⇒ 拒发(路径本身也进哈希)" $([[ $rc -ne 0 ]]; echo $?)
  git -C "$repo" reset -q --hard HEAD~1

  # ⑥ 判卷之外的文件改了 ⇒ 不许误报(误报的守卫活不过一周)
  printf 'changed\n' > "$repo/src/other.txt"; git -C "$repo" commit -qam "改实现侧"
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/f.log" >"$d/o6" 2>&1; rc=$?
  check "H1: 非判卷文件改了 ⇒ 照发(哈希只覆盖 protect)" $([[ $rc -eq 0 ]]; echo $?)

  # ⑦ 判卷路径里的**符号链接**不许是盲区:链接目标变了 = 考卷变了
  ln -s ../src/impl.sh "$repo/tests/link.sh"
  git -C "$repo" add -A; git -C "$repo" commit -qm "判据里放一个符号链接"
  stamp_hash "$d/attack.md" "$repo" tests/
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/g.log" >"$d/o7" 2>&1; rc=$?
  check "H1: 含符号链接的判卷面,重新攻过 ⇒ 放行" $([[ $rc -eq 0 ]]; echo $?)
  rm -f "$repo/tests/link.sh"; ln -s ../src/other.txt "$repo/tests/link.sh"
  git -C "$repo" commit -qam "把链接改指到别处"
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/h.log" >"$d/o8" 2>&1; rc=$?
  check "H1: 只改了符号链接的**指向** ⇒ 拒发(链接目标进哈希)" $([[ $rc -ne 0 ]]; echo $?)
  git -C "$repo" reset -q --hard HEAD~2

  rm -rf "$d"
}

h_hash_edges() {
  echo "[H2] 内容哈希的边界:__pycache__ / .gitignore / 空清单 / --print-oracle-hash"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo" wt="$d/wt" rc
  make_fake_codex "$b" "$rec"; make_repo "$repo"
  printf '# 任务书\n干活\n' > "$d/task.md"
  printf '攻题记录:……\n' > "$d/attack.md"
  local run="env PATH=$b:$PATH DELEGATE_WORKTREE_ROOT=$wt"

  # ① `--print-oracle-hash`:只印一行、值和判据独立算的一致、**不启动 codex、不写回执**
  $run bash "$BIN/delegate-codex" --print-oracle-hash --repo "$repo" --protect tests/ \
      >"$d/p1" 2>"$d/p1e"; rc=$?
  check "H2: --print-oracle-hash rc=0" $([[ $rc -eq 0 ]]; echo $?)
  check "H2: stdout 只有一行(能直接 >> 进攻题记录)" $([[ "$(wc -l < "$d/p1")" -eq 1 ]]; echo $?)
  [[ "$(cat "$d/p1")" == "oracle-sha256: $(oracle_hash "$repo" tests/)" ]]
  check "H2: 印出来的哈希 == 判据独立算的哈希(两边一起错就红)" $?
  check "H2: 只读模式不启动 codex" $([[ "$(calls_of "$rec")" -eq 0 ]]; echo $?)

  # ② `__pycache__` 必须排除:python 仓跑一次判据就长出来,不排的话这道闸恒真、永远派不出活
  #    (2026-08-07 实事故,旧 mtime 闸踩过同一个坑)
  printf '__pycache__/\n' > "$repo/.gitignore"; git -C "$repo" add -A
  git -C "$repo" commit -qm "ignore pycache"
  mkdir -p "$repo/tests/__pycache__"; printf 'x' > "$repo/tests/__pycache__/o.pyc"
  stamp_hash "$d/attack.md" "$repo" tests/ .gitignore
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/q1.log" >"$d/q1" 2>&1; rc=$?
  check "H2: 判卷目录里有 __pycache__ ⇒ 照发(不排除它这道闸就恒真)" $([[ $rc -eq 0 ]]; echo $?)
  printf 'y' > "$repo/tests/__pycache__/o.pyc"     # 缓存变了
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/q2.log" >"$d/q2" 2>&1; rc=$?
  check "H2: __pycache__ 内容变了 ⇒ 哈希不变、照发" $([[ $rc -eq 0 ]]; echo $?)

  # ③ `.gitignore` 是被**自动并进 protect** 的(腿改它就能藏文件)⇒ 它必须落在哈希里
  printf '__pycache__/\n# 又加一行\n' > "$repo/.gitignore"
  git -C "$repo" commit -qam "改 .gitignore"
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/q3.log" >"$d/q3" 2>&1; rc=$?
  check "H2: .gitignore 变了 ⇒ 拒发(它是自动进 protect 的,必须进哈希)" $([[ $rc -ne 0 ]]; echo $?)
  git -C "$repo" reset -q --hard HEAD~1

  # ④ protect 指到一个**空目录** ⇒ 文件集为空 = 这道闸没有强度可言 ⇒ 拒发。
  #    ⚠️ 四审 subdeepseek 抓到:这一幕原来**绿在错误的原因上** —— 前面几幕建的 `.gitignore`
  #    会被自动并进 protect,文件集根本不空,rc≠0 其实来自哈希对不上。
  #    把 .gitignore 撤掉、并给空清单这一版盖上哈希,让"空清单"成为**唯一**能让它红的理由。
  git -C "$repo" rm -q --cached .gitignore 2>/dev/null; rm -f "$repo/.gitignore"
  git -C "$repo" commit -qm "撤掉 .gitignore" >/dev/null 2>&1
  local _c; _c="$(calls_of "$rec")"     # 相对计数:本幕之前已经派成功过,不能写死 0
  mkdir -p "$repo/emptydir"
  printf 'oracle-sha256: %s\n' "$(oracle_hash "$repo" emptydir)" >> "$d/attack.md"
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect emptydir --log "$d/q4.log" >"$d/q4" 2>&1; rc=$?
  check "H2: protect 匹配不到任何文件 ⇒ 拒发(空清单 = 没有闸)" $([[ $rc -ne 0 ]]; echo $?)
  check "H2: 空清单那次 codex 没被启动" $([[ "$(calls_of "$rec")" -eq "$_c" ]]; echo $?)

  # ⑤ 【四审 submimo + subdeepseek 各自独立指到】**哈希只覆盖 protect 清单里的路径本身**:
  #    链接指向的东西在清单外,就在闸外(改目标的**内容**哈希不变)。
  #    这是规格选择不是 bug(跟进链接会跑出仓、还会成环),但必须**钉住**,
  #    免得哪天悄悄变了没人知道;真要覆盖,就把目标一起列进 --protect。
  ln -s ../src/impl.sh "$repo/tests/lk.sh"
  git -C "$repo" add -A; git -C "$repo" commit -qm "判据里一个指向仓内实现的链接"
  local h_before; h_before="$(oracle_hash "$repo" tests/)"
  printf '#!/bin/bash\necho NEW-changed\n' > "$repo/src/impl.sh"
  git -C "$repo" commit -qam "改链接**目标**的内容"
  check "H2: 改符号链接**目标的内容** ⇒ 哈希不变(已知盲区,钉住当前行为)" \
    $([[ "$(oracle_hash "$repo" tests/)" == "$h_before" ]]; echo $?)
  check "H2: 把目标也列进 protect ⇒ 哈希就变了(这是覆盖它的办法)" \
    $([[ "$(oracle_hash "$repo" tests/ src/impl.sh)" != "$h_before" ]]; echo $?)

  rm -rf "$d"
}

# ================================================================ I:隔离
i_isolate_default() {
  echo "[I1] 默认就隔离:codex 跑在独立 worktree 里,主工作树逐字节不被碰"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo" wt="$d/wt" rc
  make_fake_codex "$b" "$rec"; make_repo "$repo"
  printf '# 任务书\n干活\n' > "$d/task.md"
  printf '攻题记录:……\n' > "$d/attack.md"
  stamp_hash "$d/attack.md" "$repo" tests/
  local head0; head0="$(git -C "$repo" rev-parse HEAD)"

  # **不传任何隔离旗标** —— 默认必须是隔离(design 九·2 拍板)
  env PATH="$b:$PATH" DELEGATE_WORKTREE_ROOT="$wt" bash "$BIN/delegate-codex" \
      --task "$d/task.md" --repo "$repo" --attack-log "$d/attack.md" \
      --protect tests/ --log "$d/run.log" >"$d/o" 2>&1; rc=$?
  check "I1: rc=0" $([[ $rc -eq 0 ]]; echo $?)
  local cdir; cdir="$(c_dir_of "$rec/argv.1")"
  check "I1: codex 的 -C **不是**原仓" $([[ "$cdir" != "$repo" ]]; echo $?)
  check "I1: codex 的 -C 落在 worktree 根下" $([[ "$cdir" == "$wt/"* ]]; echo $?)
  check "I1: 那棵树真的存在" $([[ -d "$cdir" ]]; echo $?)
  check "I1: 树的 HEAD == 派活时的基线" \
    $([[ "$(git -C "$cdir" rev-parse HEAD 2>/dev/null)" == "$head0" ]]; echo $?)
  check "I1: git 也认它是一棵 worktree" \
    $(git -C "$repo" worktree list --porcelain | grep -qx "worktree $cdir"; echo $?)

  # 腿在树里写了东西 —— 主树必须**一个字节都没动**
  check "I1: 腿写的文件在树里" $([[ -f "$cdir/LEG_WROTE.txt" ]]; echo $?)
  check "I1: 主工作树里没有那个文件" $([[ ! -f "$repo/LEG_WROTE.txt" ]]; echo $?)
  check "I1: 主工作树 git status 仍然全空" \
    $([[ -z "$(git -C "$repo" status --porcelain -uall)" ]]; echo $?)
  check "I1: 主工作树 HEAD 没被动过" \
    $([[ "$(git -C "$repo" rev-parse HEAD)" == "$head0" ]]; echo $?)

  # 回执:三个新键
  python3 - "$d/run.log.receipt.json" "$cdir" "$head0" <<'EOF'
import json,sys
r=json.load(open(sys.argv[1])); wt,head=sys.argv[2],sys.argv[3]
assert r.get("isolate") is True, r.get("isolate")
assert r.get("worktree","").rstrip("/")==wt.rstrip("/"), r.get("worktree")
assert r.get("branch"), r.get("branch")
assert r["head"]==head, r["head"]          # head 就是 base,不另造第二个同义键
EOF
  check "I1: 回执记下 isolate / worktree / branch(head 就是 base)" $?

  # **连派两发**(树名是秒级时间戳,同一秒派第二次是真会发生的:判据连着跑就是这形状,
  # 我拒发一次立刻改了再派也是)。不许覆盖上一棵树 —— 覆盖等于丢掉那里面唯一一份改动。
  printf 'MARKER_第一棵树\n' > "$cdir/keep-me.txt"
  env PATH="$b:$PATH" DELEGATE_WORKTREE_ROOT="$wt" bash "$BIN/delegate-codex" \
      --task "$d/task.md" --repo "$repo" --attack-log "$d/attack.md" \
      --protect tests/ --log "$d/run2.log" >"$d/o2" 2>&1; rc=$?
  check "I1: 紧接着再派一发 ⇒ rc=0(不许因为撞名就派不出去)" $([[ $rc -eq 0 ]]; echo $?)
  local cdir2; cdir2="$(c_dir_of "$rec/argv.2")"
  check "I1: 第二发建的是**另一棵**树" $([[ -n "$cdir2" && "$cdir2" != "$cdir" ]]; echo $?)
  check "I1: 第一棵树没被顶掉(里面的东西还在)" $([[ -f "$cdir/keep-me.txt" ]]; echo $?)
  check "I1: 两棵树 git 都认" \
    $([[ "$(git -C "$repo" worktree list --porcelain | grep -c '^worktree ')" -eq 3 ]]; echo $?)
  rm -rf "$d"
}

i_isolate_refusals() {
  echo "[I2] 隔离的四条拒发条件:判卷脏 / 建树失败 / dry-run 不建树 / 嵌套没被 ignore"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo" wt="$d/wt" rc
  make_fake_codex "$b" "$rec"; make_repo "$repo"
  printf '# 任务书\n干活\n' > "$d/task.md"
  printf '攻题记录:……\n' > "$d/attack.md"
  local run="env PATH=$b:$PATH DELEGATE_WORKTREE_ROOT=$wt"

  # ① 判卷路径**有未提交改动** ⇒ 拒发。
  #    树是从 base 建的 ⇒ 腿看到的是已提交那版,而哈希算的是工作区那版 ——
  #    两者不一致时这道闸量的是另一份考卷。顺便把本机规矩"判据先单独 commit"焊进入口。
  printf 'echo wip\n' >> "$repo/tests/oracle.sh"
  stamp_hash "$d/attack.md" "$repo" tests/
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/a.log" >"$d/o1" 2>&1; rc=$?
  check "I2: 判卷路径有未提交改动 ⇒ 拒发" $([[ $rc -ne 0 ]]; echo $?)
  check "I2: 拒发时 codex 零调用" $([[ "$(calls_of "$rec")" -eq 0 ]]; echo $?)
  grep -q "单独 commit" "$d/o1"; check "I2: 说清该怎么办(判据先单独 commit)" $?
  check "I2: 拒发时不许留下半棵树" $([[ ! -d "$wt" || -z "$(ls -A "$wt" 2>/dev/null)" ]]; echo $?)
  git -C "$repo" checkout -- tests/oracle.sh

  # ①b 判卷路径下有**未跟踪文件**(git diff 看不见它)⇒ 同样拒发
  printf 'x\n' > "$repo/tests/newfile.sh"
  stamp_hash "$d/attack.md" "$repo" tests/
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/b.log" >"$d/o2" 2>&1; rc=$?
  check "I2: 判卷路径下有未跟踪文件 ⇒ 拒发" $([[ $rc -ne 0 ]]; echo $?)
  rm -f "$repo/tests/newfile.sh"
  stamp_hash "$d/attack.md" "$repo" tests/

  # ② 判卷**之外**的未提交改动 ⇒ 照发,但必须**吼一声**(腿在树里看不到这些改动)
  printf 'wip\n' > "$repo/src/other.txt"
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/c.log" >"$d/o3" 2>&1; rc=$?
  check "I2: 非判卷路径脏 ⇒ 照发" $([[ $rc -eq 0 ]]; echo $?)
  grep -q "src/other.txt" "$d/o3"
  check "I2: 但要列出腿看不到的那些未提交改动" $?
  git -C "$repo" checkout -- src/other.txt

  # ③ `--dry-run` **不建树**(dry-run 留一棵垃圾树是净负)
  local before; before="$(ls -1 "$wt" 2>/dev/null | wc -l)"
  local _c; _c="$(calls_of "$rec")"
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/e.log" --dry-run >"$d/o4" 2>&1; rc=$?
  check "I2: --dry-run rc=0" $([[ $rc -eq 0 ]]; echo $?)
  check "I2: --dry-run 一棵树都没建" \
    $([[ "$(ls -1 "$wt" 2>/dev/null | wc -l)" -eq "$before" ]]; echo $?)
  check "I2: --dry-run 没启动 codex" $([[ "$(calls_of "$rec")" -eq "$_c" ]]; echo $?)
  grep -q "$wt/" "$d/o4"; check "I2: --dry-run 印出**将要**建在哪" $?
  # 自审 F1:dry-run 也会写回执,而它记的树**从来没建过**。
  # 拿它去收货时,不许说成"现场没了"——把"没做"说成"丢了"是指错方向的报警器。
  bash "$BIN/delegate-codex" --receive "$d/e.log.receipt.json" >"$d/o4r" 2>&1; rc=$?
  check "I2: 拿 --dry-run 的回执收货 ⇒ 非零" $([[ $rc -ne 0 ]]; echo $?)
  grep -qi "dry-run\|没派过\|没建过" "$d/o4r"
  check "I2: 而且要说清是「这是 dry-run 的回执,压根没派过活」,不是「现场没了」" $?

  # ④ 建树失败 ⇒ 拒发 + 零调用(不许"树没建成但活照派",那会静默退回非隔离)。
  #    确定性的失败注入:先占掉 `delegate` 这个分支名 ⇒ `delegate/<job>` 因 D/F 冲突建不出来。
  #    ⚠️ 注入必须用**干净的仓**:这一幕之前已经成功派过一发,refs/heads/delegate/<job> 就存在了,
  #    那时 `git branch delegate` 自己会失败 ⇒ 注入根本没生效(我第一版判据就是这么写的,
  #    它"红"在实现头上,其实错在我的夹具)。
  local repo3="$d/repo3"; make_repo "$repo3"
  printf '攻题记录:……\n' > "$d/attack3.md"; stamp_hash "$d/attack3.md" "$repo3" tests/
  git -C "$repo3" branch delegate
  _c="$(calls_of "$rec")"
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo3" \
      --attack-log "$d/attack3.md" --protect tests/ --log "$d/f.log" >"$d/o5" 2>&1; rc=$?
  check "I2: 建树失败 ⇒ 拒发" $([[ $rc -ne 0 ]]; echo $?)
  check "I2: 建树失败时 codex 一次都没启动" $([[ "$(calls_of "$rec")" -eq "$_c" ]]; echo $?)

  # ④b 【四审 subdeepseek】直通参数能**静默撤销隔离**:`-- -C <别处>` / `-- -s <别的沙箱>`
  #     排在工具自己给的 `-C "$RUNDIR"` `-s workspace-write` **后面**,last-wins。
  #     只有我自己会传直通参数(是脚枪不是攻击面),但"我以为它隔离了、其实没有"正是
  #     本单最不能出的错 ⇒ 隔离下直接拒发,想传就显式 --no-isolate。
  local _c2
  for _bad in -C -s; do
    _c2="$(calls_of "$rec")"
    $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
        --attack-log "$d/attack.md" --protect tests/ --log "$d/p$_bad.log" \
        -- "$_bad" /tmp >"$d/op$_bad" 2>&1; rc=$?
    check "I2: 直通参数里带 $_bad ⇒ 隔离下拒发(它会 last-wins 撤销隔离)" $([[ $rc -ne 0 ]]; echo $?)
    check "I2: 那次零调用($_bad)" $([[ "$(calls_of "$rec")" -eq "$_c2" ]]; echo $?)
  done

  # ⑤ worktree 落在**仓里**且没被 gitignore ⇒ 拒发(否则主树 status 被它污染,闸③ 底账跟着脏)
  _c="$(calls_of "$rec")"
  env PATH="$b:$PATH" DELEGATE_WORKTREE_ROOT="$repo/wtdir" bash "$BIN/delegate-codex" \
      --task "$d/task.md" --repo "$repo" --attack-log "$d/attack.md" \
      --protect tests/ --log "$d/g.log" >"$d/o6" 2>&1; rc=$?
  check "I2: 树落在仓里、又没被 gitignore ⇒ 拒发" $([[ $rc -ne 0 ]]; echo $?)
  check "I2: 那次也没启动 codex" $([[ "$(calls_of "$rec")" -eq "$_c" ]]; echo $?)
  # 显式被 ignore 了就允许。
  printf 'wtdir/\n' > "$repo/.gitignore"; git -C "$repo" add -A
  git -C "$repo" commit -qm "ignore 掉 worktree 根"
  stamp_hash "$d/attack.md" "$repo" tests/ .gitignore
  env PATH="$b:$PATH" DELEGATE_WORKTREE_ROOT="$repo/wtdir" bash "$BIN/delegate-codex" \
      --task "$d/task.md" --repo "$repo" --attack-log "$d/attack.md" \
      --protect tests/ --log "$d/h.log" >"$d/o7" 2>&1; rc=$?
  check "I2: 树落在仓里但被 gitignore ⇒ 放行" $([[ $rc -eq 0 ]]; echo $?)
  check "I2: 主树 status 没被那棵树污染" \
    $([[ -z "$(git -C "$repo" status --porcelain -uall)" ]]; echo $?)

  rm -rf "$d"
}

i_no_isolate() {
  echo "[I3] --no-isolate:老行为原样保留(退出口必须真能退出去)"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo" wt="$d/wt" rc
  make_fake_codex "$b" "$rec"; make_repo "$repo"
  printf '# 任务书\n干活\n' > "$d/task.md"
  printf '攻题记录:……\n' > "$d/attack.md"
  stamp_hash "$d/attack.md" "$repo" tests/

  env PATH="$b:$PATH" DELEGATE_WORKTREE_ROOT="$wt" bash "$BIN/delegate-codex" \
      --task "$d/task.md" --repo "$repo" --attack-log "$d/attack.md" --no-isolate \
      --protect tests/ --log "$d/run.log" >"$d/o" 2>&1; rc=$?
  check "I3: rc=0" $([[ $rc -eq 0 ]]; echo $?)
  check "I3: codex 的 -C 就是原仓" $([[ "$(c_dir_of "$rec/argv.1")" == "$repo" ]]; echo $?)
  check "I3: 一棵树都没建" $([[ ! -d "$wt" || -z "$(ls -A "$wt" 2>/dev/null)" ]]; echo $?)
  check "I3: 腿写在主树里(老行为)" $([[ -f "$repo/LEG_WROTE.txt" ]]; echo $?)
  python3 - "$d/run.log.receipt.json" <<'EOF'
import json,sys
r=json.load(open(sys.argv[1]))
assert r.get("isolate") is False, r.get("isolate")
assert not r.get("worktree"), r.get("worktree")
EOF
  check "I3: 回执里 isolate=false、没有 worktree" $?
  rm -rf "$d"
}

i_case_files() {
  echo "[I4] 卷宗位置:规则从「不许进仓」换成「不许进**腿能写的树**」,不许放宽过头"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo" wt="$d/wt" rc
  make_fake_codex "$b" "$rec"; make_repo "$repo"
  printf '# 任务书\n干活\n' > "$d/task.md"
  mkdir -p "$wt"
  printf '攻题记录:……\n' > "$d/attack.md"
  stamp_hash "$d/attack.md" "$repo" tests/
  local run="env PATH=$b:$PATH DELEGATE_WORKTREE_ROOT=$wt"

  # ① 隔离下,日志落进 **worktree 根** ⇒ 拒发(那是腿的地盘,它能改回执给自己开绿灯)
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$wt/inside.log" >"$d/o1" 2>&1; rc=$?
  check "I4: 隔离下日志落进 worktree 根 ⇒ 拒发" $([[ $rc -ne 0 ]]; echo $?)
  check "I4: 拒发时零调用" $([[ "$(calls_of "$rec")" -eq 0 ]]; echo $?)

  # ② 【2026-08-11 探针证伪,原来这里断言的是"放行"】
  #    我本来把规则放宽成"卷宗只要不在**树**里就行,落在主仓里可以" ——
  #    理由是"腿的沙箱就是那棵树,主仓它写不到"。**真 codex 探针把这条打掉了**:
  #    `codex exec -C <worktree> -s workspace-write` 能往**主仓**写文件、改文件
  #    (它把"项目根"向上解析到了主仓,因为 worktree 的 .git 是个文件),
  #    只有无关路径才被拒(`writing outside of the project`)。
  #    ⇒ 卷宗落在主仓 = 腿能改回执/日志 = 闸① 自证。老规则一个字都不能松。
  local _c; _c="$(calls_of "$rec")"
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$repo/main-tree.log" >"$d/o2" 2>&1; rc=$?
  check "I4: 隔离下日志落在主仓里 ⇒ **照样拒发**(探针实测:腿写得到主仓)" $([[ $rc -ne 0 ]]; echo $?)
  check "I4: 那次零调用" $([[ "$(calls_of "$rec")" -eq "$_c" ]]; echo $?)

  # ③ 攻题记录放在主仓里 ⇒ 照拒(跟踪不跟踪都一样)。
  #    探针的另一半:腿**读得到**主仓里未跟踪的文件(写沙箱管不了读)——
  #    它在报告里把我塞的那份"秘密攻题记录"原文贴了出来。
  cp "$d/attack.md" "$repo/attack-untracked.md"
  _c="$(calls_of "$rec")"
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$repo/attack-untracked.md" --protect tests/ --log "$d/c.log" >"$d/o3" 2>&1; rc=$?
  check "I4: 隔离下攻题记录放在主仓(未跟踪)⇒ **照样拒发**(探针实测:腿读得到)" $([[ $rc -ne 0 ]]; echo $?)
  check "I4: 那次零调用" $([[ "$(calls_of "$rec")" -eq "$_c" ]]; echo $?)
  rm -f "$repo/attack-untracked.md"

  # ④ 卷宗落进 worktree 根 ⇒ 拒(见 ①);落在两者之外 ⇒ 放行。两边都要有,免得写成"全拒"。
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" \
      --attack-log "$d/attack.md" --protect tests/ --log "$d/ok.log" >"$d/o4" 2>&1; rc=$?
  check "I4: 卷宗在仓外也在树外 ⇒ 放行(不许写成全拒)" $([[ $rc -eq 0 ]]; echo $?)

  # ⑤ `--no-isolate` 下老规则一个字不许松:卷宗落在仓里 ⇒ 照拒
  stamp_hash "$d/attack.md" "$repo" tests/
  _c="$(calls_of "$rec")"
  $run bash "$BIN/delegate-codex" --task "$d/task.md" --repo "$repo" --no-isolate \
      --attack-log "$d/attack.md" --protect tests/ --log "$repo/in.log" >"$d/o5" 2>&1; rc=$?
  check "I4: --no-isolate 下日志落在仓里 ⇒ 仍然拒发(老规则没被放松)" $([[ $rc -ne 0 ]]; echo $?)
  check "I4: 那次零调用" $([[ "$(calls_of "$rec")" -eq "$_c" ]]; echo $?)
  rm -rf "$d"
}

# ================================================================ R:收货
r_receive_on_worktree() {
  echo "[R1] 收货闸①(四条臂 + 底账)整体搬到 worktree 上"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo" wt="$d/wt" rc
  make_fake_codex "$b" "$rec"; make_repo "$repo"
  printf '# 任务书\n干活\n' > "$d/task.md"
  printf '攻题记录:……\n' > "$d/attack.md"
  stamp_hash "$d/attack.md" "$repo" tests/
  env PATH="$b:$PATH" DELEGATE_WORKTREE_ROOT="$wt" bash "$BIN/delegate-codex" \
      --task "$d/task.md" --repo "$repo" --attack-log "$d/attack.md" \
      --protect tests/ --log "$d/run.log" >/dev/null 2>&1
  local receipt="$d/run.log.receipt.json"
  local tree; tree="$(c_dir_of "$rec/argv.1")"

  # ① 腿只动了实现 ⇒ 放行,且底账列出它写的文件
  bash "$BIN/delegate-codex" --receive "$receipt" >"$d/r1" 2>&1; rc=$?
  check "R1: 腿只动实现 ⇒ 闸①放行" $([[ $rc -eq 0 ]]; echo $?)
  grep -q "src/impl.sh" "$d/r1" && grep -q "LEG_WROTE.txt" "$d/r1"
  check "R1: 底账列出腿在树里写的文件(含未跟踪的)" $?

  # ② 腿在树里改了判卷 ⇒ 拦,并点名
  printf 'echo tampered\n' >> "$tree/tests/oracle.sh"
  bash "$BIN/delegate-codex" --receive "$receipt" >"$d/r2" 2>&1; rc=$?
  check "R1: 树里改了判卷 ⇒ 拦下" $([[ $rc -ne 0 ]]; echo $?)
  grep -q "tests/oracle.sh" "$d/r2"; check "R1: 拦下时点名哪个文件" $?
  git -C "$tree" checkout -- tests/oracle.sh

  # ③ 只在树里**新增未跟踪文件**(conftest.py 那招)⇒ 必须拦(第二臂在树上也要活着)
  printf 'import pytest\n' > "$tree/tests/conftest.py"
  bash "$BIN/delegate-codex" --receive "$receipt" >"$d/r3" 2>&1; rc=$?
  check "R1: 树里往判卷目录塞未跟踪文件 ⇒ 拦下(git diff 看不见它)" $([[ $rc -ne 0 ]]; echo $?)
  grep -q "conftest.py" "$d/r3"; check "R1: 点名那个未跟踪文件" $?
  rm -f "$tree/tests/conftest.py"

  # ④ 判卷被挂 skip-worktree ⇒ 第四臂在树上也要活着
  git -C "$tree" update-index --skip-worktree tests/oracle.sh
  printf 'echo tampered\n' >> "$tree/tests/oracle.sh"
  bash "$BIN/delegate-codex" --receive "$receipt" >"$d/r4" 2>&1; rc=$?
  check "R1: 树里挂 skip-worktree 后改判卷 ⇒ 仍然拦" $([[ $rc -ne 0 ]]; echo $?)
  git -C "$tree" update-index --no-skip-worktree tests/oracle.sh
  git -C "$tree" checkout -- tests/oracle.sh

  # ⑤ **老回执**(这次改动之前落盘的那些,压根没有 isolate/worktree 键)⇒ 退回主仓,老行为不变。
  #    盘上现在就躺着这种回执,收货时读不了它 = 把昨天的活卡死。
  python3 - "$receipt" "$d/old-receipt.json" <<'EOF'
import json,sys
r=json.load(open(sys.argv[1]))
for k in ("isolate","worktree","branch","actual_write_set"): r.pop(k, None)
json.dump(r, open(sys.argv[2],"w"), ensure_ascii=False, indent=2)
EOF
  printf 'echo tampered\n' >> "$repo/tests/oracle.sh"      # 主仓里改判卷
  bash "$BIN/delegate-codex" --receive "$d/old-receipt.json" >"$d/r5" 2>&1; rc=$?
  check "R1: 老回执(没有 worktree 键)⇒ 退回主仓判,老行为不变" $([[ $rc -ne 0 ]]; echo $?)
  grep -q "tests/oracle.sh" "$d/r5"; check "R1: 老回执下点名的是主仓那个文件" $?
  git -C "$repo" checkout -- tests/oracle.sh

  # ⑤b 【探针逼出来的新洞,两条评审腿都没提】腿**能写到主仓**(实测)。
  #     闸① 改看那棵树之后,主树的判卷文件就没人看了 —— 腿伸手过去改主树的判据,
  #     闸① 全绿,而我随后**在主树上**跑判据 = 跑的是被改过的考卷。
  #     所以隔离下闸① 还要看主树,但只看"**没提交的**动静":
  #     我自己的判据修复是提交过的(A3 那一幕),不许因为这条又把误报请回来。
  printf 'echo "腿伸手改了主树的判卷"\n' >> "$repo/tests/oracle.sh"
  bash "$BIN/delegate-codex" --receive "$receipt" >"$d/r5b" 2>&1; rc=$?
  check "R1: 腿越界改了**主树**的判卷(未提交)⇒ 闸① 拦下" $([[ $rc -ne 0 ]]; echo $?)
  grep -q "主树\|主仓" "$d/r5b"; check "R1: 说清动静在**主树**那边,不是树里" $?
  git -C "$repo" checkout -- tests/oracle.sh

  # ⑥ 回执里记了树、盘上却没了 ⇒ **exit 2**,不许当"干净"放行
  git -C "$repo" worktree remove --force "$tree"
  bash "$BIN/delegate-codex" --receive "$receipt" >"$d/r6" 2>&1; rc=$?
  check "R1: 回执指的树不在了 ⇒ exit 2(不许静默放行)" $([[ $rc -eq 2 ]]; echo $?)
  rm -rf "$d"
}

r_a3_no_false_positive() {
  echo "[R2] 【A3,这一单存在的理由】派活后主 agent 在主树提交判据修复 ⇒ 闸① 不许再红在我头上"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo" wt="$d/wt" rc
  make_fake_codex "$b" "$rec"; make_repo "$repo"
  printf '# 任务书\n干活\n' > "$d/task.md"
  printf '攻题记录:……\n' > "$d/attack.md"
  stamp_hash "$d/attack.md" "$repo" tests/

  # —— 隔离模式:今天真实发生过的那一幕(腿说考卷错了 ⇒ 我改考卷并提交)
  env PATH="$b:$PATH" DELEGATE_WORKTREE_ROOT="$wt" bash "$BIN/delegate-codex" \
      --task "$d/task.md" --repo "$repo" --attack-log "$d/attack.md" \
      --protect tests/ --log "$d/run.log" >/dev/null 2>&1
  printf 'echo "腿指出来的判据错,我修了"\n' >> "$repo/tests/oracle.sh"
  git -C "$repo" commit -qam "判据修复(主 agent 自己提交的)"
  printf 'main-tree-noise\n' > "$repo/src/other.txt"     # 我在主树上的别的改动
  bash "$BIN/delegate-codex" --receive "$d/run.log.receipt.json" >"$d/r1" 2>&1; rc=$?
  check "R2: 隔离下 ⇒ 闸①放行(误报消失)" $([[ $rc -eq 0 ]]; echo $?)
  ! grep -q "tests/oracle.sh" "$d/r1"
  check "R2: 底账里**没有**我自己改的判据文件" $?
  ! grep -q "src/other.txt" "$d/r1"
  check "R2: 底账里也没有我在主树上的其它改动(底账只含腿写的)" $?
  git -C "$repo" checkout -- src/other.txt
  # ⑤b 加了"主树未提交判卷改动也拦"之后,这一条要重新问一遍:
  # 我**提交过**的判据修复不许被它当成腿的越界(否则 A3 的误报原样回来)。
  check "R2: 主树上**已提交**的判据修复仍然放行(新加的主树臂不许把误报请回来)" \
    $([[ $rc -eq 0 ]]; echo $?)

  # —— 对照组:同一场景走 `--no-isolate` **必须红**。
  #    少了这一半,"隔离下放行"可能只是因为闸整个瞎了。
  local repo2="$d/repo2"; make_repo "$repo2"
  printf '攻题记录:……\n' > "$d/attack2.md"
  stamp_hash "$d/attack2.md" "$repo2" tests/
  env PATH="$b:$PATH" DELEGATE_WORKTREE_ROOT="$wt" bash "$BIN/delegate-codex" \
      --task "$d/task.md" --repo "$repo2" --attack-log "$d/attack2.md" --no-isolate \
      --protect tests/ --log "$d/run2.log" >/dev/null 2>&1
  printf 'echo "同样的判据修复"\n' >> "$repo2/tests/oracle.sh"
  git -C "$repo2" commit -qam "判据修复(主 agent 自己提交的)"
  bash "$BIN/delegate-codex" --receive "$d/run2.log.receipt.json" >"$d/r2" 2>&1; rc=$?
  check "R2: 同一场景 --no-isolate ⇒ 照旧判红(证明上面那条不是闸瞎了)" $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"
}

r_writeback_and_handoff() {
  echo "[R3] 收货通过后:写回实际写集 + 打印交回/回收命令,**不自动 merge、不自动删**"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo" wt="$d/wt" rc
  make_fake_codex "$b" "$rec"; make_repo "$repo"
  printf '# 任务书\n干活\n' > "$d/task.md"
  printf '攻题记录:……\n' > "$d/attack.md"
  stamp_hash "$d/attack.md" "$repo" tests/
  mkdir -p "$wt/一棵从前挂着没收的旧树"          # 采纳·3 的反面证据(mcp-registry 挂了 8 天)
  env PATH="$b:$PATH" DELEGATE_WORKTREE_ROOT="$wt" bash "$BIN/delegate-codex" \
      --task "$d/task.md" --repo "$repo" --attack-log "$d/attack.md" \
      --protect tests/ --log "$d/run.log" >/dev/null 2>&1
  local tree; tree="$(c_dir_of "$rec/argv.1")"
  local head0; head0="$(git -C "$repo" rev-parse HEAD)"

  bash "$BIN/delegate-codex" --receive "$d/run.log.receipt.json" >"$d/r" 2>&1; rc=$?
  check "R3: 放行" $([[ $rc -eq 0 ]]; echo $?)

  python3 - "$d/run.log.receipt.json" <<'EOF'
import json,sys
r=json.load(open(sys.argv[1]))
ws=r.get("actual_write_set")
assert isinstance(ws,list) and ws, ws
assert "LEG_WROTE.txt" in ws and "src/impl.sh" in ws, ws
assert "tests/oracle.sh" not in ws, ws
EOF
  check "R3: 实际写集被**写回回执**(机器算的,不是我打字)" $?

  grep -q "worktree remove" "$d/r" && grep -q "$tree" "$d/r"
  check "R3: 打印回收命令(采纳·3:隔离必须自带**打印出来的**回收路径)" $?
  grep -q "merge" "$d/r"; check "R3: 打印集成命令" $?
  grep -q "120000" "$d/r"; check "R3: 提醒查 create mode 120000 符号链接(本机出过事故)" $?
  grep -q "一棵从前挂着没收的旧树" "$d/r"
  check "R3: 盘点 worktree 根下还挂着的旧树" $?

  check "R3: 收货**没有**自动删掉那棵树" $([[ -d "$tree" ]]; echo $?)
  check "R3: 收货**没有**动主树 HEAD" $([[ "$(git -C "$repo" rev-parse HEAD)" == "$head0" ]]; echo $?)
  check "R3: 收货没往主树里合任何东西" \
    $([[ -z "$(git -C "$repo" status --porcelain -uall)" ]]; echo $?)
  rm -rf "$d"
}

echo "=== delegate-codex 隔离 + 内容哈希 oracle ==="
h_hash_gate
h_hash_edges
i_isolate_default
i_isolate_refusals
i_no_isolate
i_case_files
r_receive_on_worktree
r_a3_no_false_positive
r_writeback_and_handoff
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
