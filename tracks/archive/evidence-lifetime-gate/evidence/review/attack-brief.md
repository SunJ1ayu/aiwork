# 攻题:evidence-lifetime-gate 的判据有没有"全绿了仍然错"的洞

请只读、不要改任何文件。用中文回答。

## 背景

`/root/aiwork` 是一台单人 AI 工作站的工具仓。track = 一个 PR 级改动的工件目录
(`tracks/<名>/` 下有 proposal/design/tasks/verify.md 和 evidence/ 收据)。
`bin/track archive <名>` 把它移进 `tracks/archive/<名>/`,并在移动**之前**跑几道闸
(verify.md 必须有结论、runlog 收据必须对齐),任一条不过就拒绝归档、目录留原地。

## 这一单要加的规矩

归档时扫 `tracks/<名>/` 下所有 `*.md`,**命中会话临时目录的行就拒绝归档**:
- 命中什么:`/tmp/`、`scratchpad`(大小写不敏感)、`$TMPDIR` [仓外不承重]
- 唯一放行方式:**该行自带 `[仓外不承重]` 标记**(逐行,不许一句话打包放行整份文件)
- 拒绝时逐条打印 `文件:行号` + 原文,并说明放行写法
- 拒绝必须发生在 `mv` 之前(不留半归档状态)
- helper 缺件 ⇒ fail closed(拒绝归档)
- **只在归档触发,不进 pre-commit**(干活期间引用 scratchpad 是正常的) [仓外不承重]

动机:一份 design.md 引用了 `/tmp/claude-0/<会话id>/scratchpad/codex-plan.log` [仓外不承重]
(外部模型的完整输出),那个会话断了、目录会被清 ⇒ 工件还在、它引的证据没了,
而且**不报错**。全机 348 份 track md 里有 22 份有这类引用,其中 9 处是承重证据
(比如"读评审腿之前先落盘的自审全文在 scratchpad")。 [仓外不承重]

## 判据(要攻的对象)

`/root/aiwork/tests/test-evidence-lifetime.sh`(已 commit,10 幕 E1-E10)。
配套设计:`/root/aiwork/tracks/evidence-lifetime-gate/design.md`。
现有同形判据可参考:`tests/test-worktree-sweep.sh`、`tests/test-track-guard.sh`。
被改对象:`bin/track`(archive 分支)、新文件 `bin/_ephemeral-refs.sh`。

## 请回答(只问考卷,不要写实现)

1. **哪一条断言是"恒真"的**?即:实现写成一坨什么都不干的东西,它照样绿。
2. **有没有"全部 10 幕绿、但规矩其实没落实"的实现**?请给出最省事的那种作弊实现,
   越具体越好(例如:只查 verify.md 不查其它 md;只查第一处命中就返回;
   把标记判定写成"整份文件里出现过标记就放行";用 `grep -l` 而不是 `grep -n`
   导致行号是编的;等等)。**每指出一种,请说清哪一幕本该拦住它、为什么没拦住。**
3. **有没有该拦却拦不住的真实工件形状**?(想想 markdown 的写法:行内代码、
   围栏代码块、表格、引用块、HTML 注释、多个命中在同一行、
   相对路径 `../scratchpad/x`、大小写 `/TMP/`、`$TMPDIR` 变量形式) [仓外不承重]
4. **有没有会误报的正常工件形状**?误报会让归档卡死,是这道闸最可能的死法。
   特别想想:evidence/ 里的收据文件正文含 `/tmp` 会不会被扫到(判据说只扫 *.md,
   请核对这个假设在 E7 里真的被锚住了没有)。
5. E9(helper 缺件 fail closed)的夹具是 `cp "$BIN"/*` 到临时目录再删掉 helper ——
   这个造法有没有问题?比如 `cp` 漏掉子目录、或者 track 会去别处找 helper 导致假绿。
6. E8 断言错误信息里出现 `design.md:4`。**行号 4 是我数出来的**,
   请核对判据里那份夹具的正文,第 4 行是不是真的是含 scratchpad 的那行。 [仓外不承重]
