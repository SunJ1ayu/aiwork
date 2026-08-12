# Verify: worktree-sweep

- Date: 2026-08-12
- Verdict: **PASS**(主裁;四审 2/4 腿给了裁决,两腿在一条关键问题上意见相反,见仲裁)

## Mechanical checks

- [x] build passes(`bash -n bin/track bin/delegate-codex`)
- [x] tests pass
- [x] no secrets / unsafe ops

**机器打印的**(不是我的转述):

```
runlog: suite-all-final rc=0 commit=c7f85ae dirty=yes at=2026-08-11T16:14:56Z file=tracks/worktree-sweep/evidence/20260811T161456Z-01-suite-all-final.txt
runlog: redcheck-final rc=0 commit=c7f85ae dirty=yes at=2026-08-11T16:14:54Z file=tracks/worktree-sweep/evidence/20260811T161454Z-01-redcheck-final.txt
runlog: mutation-r4 rc=0 commit=c7f85ae dirty=yes at=2026-08-11T16:12:59Z file=tracks/worktree-sweep/evidence/20260811T161259Z-01-mutation-r4.txt
```

**跑红的那几遍**(一份都不许藏):

```
runlog: mutation-test rc=1 commit=549e914 dirty=yes at=2026-08-11T15:52:39Z file=tracks/worktree-sweep/evidence/20260811T155239Z-01-mutation-test.txt
runlog: mutation-test-r2 rc=1 commit=ac7e9fc dirty=no at=2026-08-11T15:56:02Z file=tracks/worktree-sweep/evidence/20260811T155602Z-01-mutation-test-r2.txt
runlog: redcheck rc=0 commit=549e914 dirty=no at=2026-08-11T15:51:59Z file=tracks/worktree-sweep/evidence/20260811T155159Z-01-redcheck.txt
runlog: mutation-test-r3 rc=0 commit=ab52f25 dirty=no at=2026-08-11T15:56:39Z file=tracks/worktree-sweep/evidence/20260811T155639Z-01-mutation-test-r3.txt
runlog: suite-all rc=0 commit=ab52f25 dirty=yes at=2026-08-11T15:57:00Z file=tracks/worktree-sweep/evidence/20260811T155700Z-01-suite-all.txt
```

两次变异跑红,查完是**三种病,没有一种是"判据不行"**:

- **我把靶子指错了 ×4**(W1/W4/W5 + 上一轮同型):判据其实红了,只是红在别的断言上。
  根因是我以为"拆掉这道闸 ⇒ 那条断言红",实际另有兜底(`git worktree remove` 自己会拒)。
- **我 design 里一句话不成立**:`git worktree remove` 只对 modified/untracked 拒,
  **被 ignore 的它连着一起删** ⇒ 那道"免费的第二道保险"在正常流程里**够不着**。
  连带发现 S8 那一幕的夹具把 `.gitignore` 建在建树之后 —— 它从头到尾问的都不是它想问的事。
- **我自己补的那行 `rmdir` 有 bug**:轮次目录非空时 rmdir 失败,而 `bin/track` 是 `set -e`
  ⇒ 整个归档**一声不吭地死掉**。新加的 S9 抓到,补 `|| true`,变异 W6 钉住。

最终:判据 **61/0**;总跑 9 个套件全绿(含老两套 102/0 + 80/0,没被弄回归);
退回红检红在目标断言;变异 **7/7 全被咬住**。

## Review

- lane: **full**(新增一个会**删东西**的写口 —— 硬规矩,针孔再薄也不打折)
- 派给: **codex 腿 `gpt-5.5`** —— **返工 0 轮,自身错误 0 处**。
  它自检报 44/1,那 1 条红是**我判据写错**(`track archive` 本来就会把 tracks/<name> 搬走
  ⇒ 主仓必然变脏),它**报回来了、没有自己改考卷**。
  **这一单同时是今天那套隔离流程的第一次真狗粮**:派 aiwork 自己的活、卷宗放仓外、
  树建在 `worktrees/` 下、闸① 的底账精确到只有 `bin/track` + `bin/delegate-codex`
  (没混进我自己那几笔判据修复 —— 隔离要买的就是这个)。
- 规格自查(读腿之前写的,原文入库 `my-review.md`):我自己列的最大风险 F3 是
  "整套机制挂在一个我得记得传的可选参数上",并附了一个"自动推断"的修法想听意见 ——
  评审把这个修法否掉了,理由比我想的更硬(见下)。
- 腿的花名册(原样粘):

```
submimo=PASS subdeepseek=PASS subglm=off subkimi=FAIL(rc=1)
```

  ⚠️ 仍是 **2/4**:subglm 欠费默认 off,subkimi 额度 403。别读成"四审过了"。

- findings（逐条仲裁）:
  - 🔴 **[两腿意见相反的那条 —— 采纳 subdeepseek]** 我提的"没给 `--track` 时,若仓里恰好
    只有一个 active track 就自动用它"。submimo 说可以(安全判据与归属无关,最坏只丢几兆
    已合并内容);subdeepseek 说别猜,给了四条失败模式。**我判 subdeepseek 对**:
    自动推断把"我没说"翻译成"我同意删" —— 归档时轮次目录下的树**可以被自动收掉**,
    而无主的树只点名不碰;猜错的代价落在**删**这一侧。这和我自己写死的
    "猜不出主线就 fail closed"是同一个坑位,只是理由体面些。
    ⇒ 改成**必须亲口说**:仓里有 active track 时 `--track X` 或 `--no-track` 必须给一个,
    否则拒发并列出候选;没有 active track 的仓不啰嗦(守卫一变噪音就没人看)。判据 S10。
  - 🔴 **[subdeepseek 发现 2,MEDIUM,真洞,采纳]** 归属键只有 track 名、**不带仓身份**
    ⇒ 两个项目各建一个同名 track 并共用 worktree 根时,A 的归档会删掉 B 的干净树、
    或被 B 的脏树拦死。⇒ "属于本轮"追加一条:树的所属仓必须就是正在归档的项目。判据 S6。
  - **[subdeepseek 发现 3,采纳]** 被 ignore 的东西会跟着树一起删,而我 design 里
    "它在主仓里同样会丢"**不对**(主仓没有任何动作会自动删它)。⇒ 不拦(生成物是常态),
    但**动手前逐个列出来**。判据 S11。
  - **[subdeepseek 发现 6,采纳]** 部分清理后那句"没有半归档状态"有误导 ⇒ 话术补一句。
  - **[subdeepseek 发现 8,采纳]** S2 的"说清卡在哪一条"太松(输出模板自带"干净判据"
    四个字就能过)⇒ 收紧到只在真原因里才出现的词。
  - **[subdeepseek 发现 4,PLAUSIBLE,记为已知边界]** 含 submodule 的树 `git worktree remove`
    会要 `--force` ⇒ 会被一棵真垃圾树拦住,而提示语是死胡同。本机没有 submodule 仓,
    我没有复现;出路(`--keep-trees` 或手工处理)在提示语里已经有。**不改,记账。**
  - **[subdeepseek 发现 5 / 7,记为已知边界]** reflog 独有的提交会随树丢(要求"提交后 reset
    到已合祖先"这种形状);默认分支判定是启发式(废弃的 `main` 会造成 fail-closed 误报,
    过期的 remote-tracking ref 会削弱"已合"的承诺)。两条都写进 design。
  - **[subdeepseek 发现 9,不改]** 变异没覆盖 `branch -d`→`-D`:能进 clean_entries 的分支
    必然已合,`-D` 与 `-d` 在这条路径上没有数据差别。记一笔。
  - 🔴 **[subdeepseek 发现 10,活证据,已处理]** **本仓当时就躺着一棵无主树** ——
    正是这一单自己的执行腿留下的(`worktrees/worktree-sweep-task-20260811-234252`),
    干净且已合进 master ⇒ 教科书级净垃圾,但因为挂在根下(派活时 `--track` 还不存在),
    新机制永远清不掉它,还会让**每一次**归档都多刷一行。⇒ 我按老办法手工收掉了(见下)。
  - **[submimo 发现 2,确认]** "两条判据都过但仍丢东西"的唯一形状就是 ignored 文件 ——
    与 subdeepseek 发现 3 同源,已处理。
  - **[主 agent 自审 F1/F2,腿没提]** 我自己补的 `rmdir` 会静默杀死归档(已修 + S9 钉住);
    design 里 "`git worktree remove` 是免费的第二道保险"那句不成立(已纠正,留了话)。
- arbitrated verdict (主裁): **PASS**。
  两腿的发现逐条对着代码验过,**没有一条不成立**;唯一分歧(自动推断)我按"删的一侧从严"
  裁给 subdeepseek,并把它换成一条**入口级**的显式要求 —— 这才符合本机"补入口有效、
  补约定无效"的教条。改动全部被机器钉住:61/0、变异 7/7、红检红在目标断言、总跑全绿。

## Accepted deviations

- **无主的树只点名、不自动收**(proposal 的 non-goal,用户划的范围):今天那种手工建的树
  仍要人来收。`--sweep-unowned` 这个提议**驳回**,理由不是技术:它会把"删无主的东西"
  变成常规动作,而那正是本单一开始就排除的方向。要开得用户点头。
- **含 submodule 的树**会被 `git worktree remove` 拒 ⇒ 拦住归档(fail closed,方向安全),
  出路是 `--keep-trees` 或手工。没有复现环境,记账不改。
- **reflog 独有的提交**、**默认分支判定的启发式**:两条低概率边界,写进 design,不做。
- 四审**只有 2/4 腿**(智谱欠费 / Kimi 额度)。这不是"四审过了"。
