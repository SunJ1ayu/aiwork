# Verify: archive-tree-and-untracked-views

- Date: 2026-09-09 → 2026-09-10(第五轮评审跨了两次断线;时间线见文末)

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

## Mechanical checks

- [x] build passes(本仓是 shell/python 工具集,无 build;`bin/rust-check-review-tooling` 全量防锈通过 —— 见 suite-full-r5)
- [x] tests pass(`tests/test-track-guard.sh` 106/0;红检 `tests/mutation-review-delivery.sh` 32/0)
- [x] no secrets / unsafe ops(runlog 自带 secret 扫描,36 份收据无命中;本单只改 `bin/track`、`bin/track-guard` 与两份判据)

**机器打印的**(不是我的转述)—— 全部 36 份收据的收尾行,逐字节:

- `runlog: pins-red rc=1 commit=b5ac76d dirty=yes at=2026-09-09T07:02:07Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T070207Z-01-pins-red.txt`
- `runlog: suite-after-impl rc=0 commit=64a9863 dirty=yes at=2026-09-09T07:39:06Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T073906Z-01-suite-after-impl.txt`
- `runlog: g12-red rc=1 commit=64a9863 dirty=yes at=2026-09-09T07:55:57Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T075557Z-01-g12-red.txt`
- `runlog: mutation-red-check rc=0 commit=351426f dirty=yes at=2026-09-09T08:20:58Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T082058Z-01-mutation-red-check.txt`
- `runlog: t12-t14-red rc=1 commit=351426f dirty=yes at=2026-09-09T08:27:08Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T082708Z-01-t12-t14-red.txt`
- `runlog: t13-green rc=0 commit=1d49953 dirty=yes at=2026-09-09T08:28:45Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T082845Z-01-t13-green.txt`
- `runlog: suite-final rc=0 commit=41198db dirty=no final=yes at=2026-09-09T08:29:42Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T082942Z-01-suite-final.txt`
- `runlog: mutation-red-check-v2 rc=0 commit=41198db dirty=yes at=2026-09-09T08:46:20Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T084620Z-01-mutation-red-check-v2.txt`
- `runlog: mutation-red-check-v3 rc=0 commit=41198db dirty=yes at=2026-09-09T08:49:22Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T084922Z-01-mutation-red-check-v3.txt`
- `runlog: suite-final-r2 rc=0 commit=16b5d30 dirty=no final=yes at=2026-09-09T08:53:09Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T085309Z-01-suite-final-r2.txt`
- `runlog: r2-block-pins-red rc=1 commit=798ca78 dirty=yes at=2026-09-09T09:20:55Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T092055Z-01-r2-block-pins-red.txt`
- `runlog: r2-block-fixed-green rc=1 commit=6c07856 dirty=yes at=2026-09-09T09:22:49Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T092249Z-01-r2-block-fixed-green.txt`
- `runlog: r2-block-fixed-green-v2 rc=1 commit=6c07856 dirty=yes at=2026-09-09T09:24:17Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T092417Z-01-r2-block-fixed-green-v2.txt`
- `runlog: r2-block-fixed-green-v3 rc=0 commit=6c07856 dirty=yes at=2026-09-09T09:26:31Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T092631Z-01-r2-block-fixed-green-v3.txt`
- `runlog: mutation-r2-rerun rc=0 commit=724f29c dirty=yes at=2026-09-09T10:02:46Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T100246Z-01-mutation-r2-rerun.txt`
- `runlog: suite-final-r3 rc=0 commit=c52325a dirty=no final=yes at=2026-09-09T10:09:19Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T100919Z-01-suite-final-r3.txt`
- `runlog: g14-red rc=1 commit=fead709 dirty=yes at=2026-09-09T10:55:55Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T105555Z-01-g14-red.txt`
- `runlog: g14-green rc=0 commit=66bdedb dirty=yes at=2026-09-09T10:57:37Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T105737Z-01-g14-green.txt`
- `runlog: g14-advice-walkable rc=1 commit=66bdedb dirty=yes at=2026-09-09T10:59:27Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T105927Z-01-g14-advice-walkable.txt`
- `runlog: g14-advice-walkable-v2 rc=0 commit=66bdedb dirty=yes at=2026-09-09T11:00:33Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T110033Z-01-g14-advice-walkable-v2.txt`
- `runlog: mutation-r3 rc=0 commit=66bdedb dirty=yes at=2026-09-09T11:01:15Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T110115Z-01-mutation-r3.txt`
- `runlog: suite-final-r4 rc=0 commit=c5cfad3 dirty=no final=yes at=2026-09-09T11:05:43Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T110543Z-01-suite-final-r4.txt`
- `runlog: g14-subdir-red rc=1 commit=65e8eb8 dirty=yes at=2026-09-09T13:03:02Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T130302Z-01-g14-subdir-red.txt`
- `runlog: g14-subdir-red-v2 rc=1 commit=65e8eb8 dirty=yes at=2026-09-09T13:03:54Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T130354Z-01-g14-subdir-red-v2.txt`
- `runlog: g14-subdir-green rc=0 commit=80c62ae dirty=yes at=2026-09-09T13:05:08Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T130508Z-01-g14-subdir-green.txt`
- `runlog: mutation-r4 rc=0 commit=80c62ae dirty=yes at=2026-09-09T13:05:51Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T130551Z-01-mutation-r4.txt`
- `runlog: r4-findings-red rc=1 commit=37f956a dirty=yes at=2026-09-09T13:29:14Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T132914Z-01-r4-findings-red.txt`
- `runlog: r4-findings-green rc=0 commit=bc4f0dc dirty=yes at=2026-09-09T13:30:32Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T133032Z-01-r4-findings-green.txt`
- `runlog: mutation-r5b rc=1 commit=5d4fa5a dirty=no at=2026-09-09T14:07:41Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T140741Z-01-mutation-r5b.txt`
- `runlog: suite-r5 rc=0 commit=42ba914 dirty=no at=2026-09-09T14:14:58Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T141458Z-01-suite-r5.txt`
- `runlog: mutation-r5c rc=0 commit=42ba914 dirty=yes at=2026-09-09T14:15:14Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T141514Z-01-mutation-r5c.txt`
- `runlog: g15-order-red rc=1 commit=c372f8e dirty=yes at=2026-09-09T14:23:00Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T142300Z-01-g15-order-red.txt`
- `runlog: g15-order-green rc=0 commit=da2f782 dirty=yes at=2026-09-09T14:24:20Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T142420Z-01-g15-order-green.txt`
- `runlog: mutation-r5d rc=0 commit=bdd738c dirty=no at=2026-09-09T14:25:13Z file=tracks/archive-tree-and-untracked-views/evidence/20260909T142513Z-01-mutation-r5d.txt`
- `runlog: suite-full-r5 rc=0 commit=5cedd63 dirty=no at=2026-09-10T01:00:52Z file=tracks/archive-tree-and-untracked-views/evidence/20260910T010052Z-01-suite-full-r5.txt`
- `runlog: guard-at-dispatch-head rc=0 commit=8546799 dirty=no at=2026-09-10T01:21:14Z file=tracks/archive-tree-and-untracked-views/evidence/20260910T012114Z-01-guard-at-dispatch-head.txt`
- `runlog: g16-red rc=1 commit=8546799 dirty=yes at=2026-09-10T01:48:29Z file=tracks/archive-tree-and-untracked-views/evidence/20260910T014829Z-01-g16-red.txt`
- `runlog: g16-green rc=0 commit=9fdb938 dirty=yes at=2026-09-10T01:49:41Z file=tracks/archive-tree-and-untracked-views/evidence/20260910T014941Z-01-g16-green.txt`
- `runlog: mutation-r6 rc=0 commit=052529b dirty=yes at=2026-09-10T01:51:46Z file=tracks/archive-tree-and-untracked-views/evidence/20260910T015146Z-01-mutation-r6.txt`
- `runlog: mutation-r6 rc=0 commit=052529b dirty=yes at=2026-09-10T01:55:47Z file=tracks/archive-tree-and-untracked-views/evidence/20260910T015547Z-01-mutation-r6.txt`
- `runlog: suite-full-r6 rc=0 commit=823836b dirty=no final=yes at=2026-09-10T02:02:25Z file=tracks/archive-tree-and-untracked-views/evidence/20260910T020225Z-01-suite-full-r6.txt`

> 上面 14 份 `rc=1` 是本单的红收据(判据先行 / 红检对照组),一份没藏。
> **结论所依据的最后一遍**是 `suite-full-r6`:`commit=823836b dirty=no final=yes` ——
> 全量回归(不只是本单那两个套件)在最后一次承重编辑之后跑的那一遍,全绿。
> ⚠️ **两份同名 slug `mutation-r6` 的收据都在上面,如实说明**:第一份
> (`20260910T015146Z`)起跑时脚本里只有 32 条变异 —— 我在它跑到文件末尾之前把两条
> 变异**追加进了正在执行的脚本**,bash 边读边执行,于是它变成"前 32 条来自旧文件、
> 后 2 条来自新文件"的混合体,却照样印出 34/0 一切正常的样子(唯一提示是 `dirty=yes`)。
> **承重的是第二份(`20260910T015547Z`)。** 这是"跑收据时谁都不能写仓库"的新形态:
> 被写的不是被测代码,是判卷脚本自己。
> 另有两份 `VOID-*` 收据(断线砍在抬头处、零输出行)留在 evidence/ 里作为断点记录,
> 它们**不含收尾行**,所以既不算证据、也进不了上面这份清单。

## Review

- 规格自查(读任何 panel 输出之前先答):
  这一单的规格是「闸打印的药方必须照抄能跑 + 归档不许静默嵌套」。**规格可能错在哪:
  我一直在修一段"给人照抄的手工过程",而工具本可以自己做完。** 取回(unarchive)之所以
  反复留下残件,根因是 `git mv` 不搬未跟踪文件 —— 那是**流程缺一个命令**,不是文案不够好。
  如果规格错,它会错成:药方越写越长、每种文件名形状都要补一条判据,而"取回"仍然是
  手工拼的。真正的最小修法可能是 `track unarchive <name>`(整份搬回,跟踪+未跟踪一起),
  闸退回只做"检测"。**本轮不改方向**(会扩大 diff、且 D-a 那笔取舍要先定案),记成明账 A5。

- 腿的花名册(第五轮第三次派发 `panel-archive-tree-and-untracked-views-review-r5-20260910-091519`,
  控制器写出 `.final` 但没写 `.roster`,下面这行是 `panel-roster` 从盘上重建的,原样粘):

```
submimo=PASS(verdict=PASS) subdeepseek=SKIP(rotation) subglm=FAIL(rc=1,降级:回落聊天腿也没成) subkimi=FAIL(rc=124) subgemini=SKIP(health:dead:FAIL:6)
```

  `.final`:`escalation=failure` / `selected-count=3` / `head-after=8546799`。
  **这一轮只有 1 条 coverage-eligible 腿(submimo),high 档要 2 个不同家族 ⇒ 预算没满足;
  而且我随后改了内容(G16),它冻结的指纹也不再授权当前交付 ⇒ 必须再派一轮(第六轮)。**

### findings —— 主裁自审(2026-09-10 09:13~09:25,**在读任何腿输出之前**写下)

断线后接手时,我把三件"只有我能判、且能机械核"的事亲自核了一遍,不采信前一轮自述:

- **Q1「有没有放松原有判据」= 没有,机械可查。** 取 `37f956a` 与 `HEAD` 两侧判据文件里
  全部断言/变异**名字**做集合差:119 → 131 条,`只在 old 里` 的集合**是空的** —— 纯新增,
  零删除零改名。"payload 被悄悄改弱"那条路由红检自己兜着(变异咬不动就报 FAIL,
  `mutation-r5b` 30/1 就是这么抓出来的)。
  ⚠️ 这个方法的边界:它比的是**两个端点**,区间内部"加进来又删掉"的构件看不见 ——
  M2 那条被换掉的变异正是这种(在 `2e4716e` 加、`b5191e9` 换),所以它不出现在差集里。
  对 Q1 问的"有没有放松**原有**断言"来说,端点比较正是对的尺;要问"区间内有没有反复",
  得看 commit 序列(已在任务书里逐条摆出)。
- **M2 那个实验我独立重跑了一遍(而不是读前一轮的结论)。** git 2.43、仓外夹具、
  文件名 `收据 报告.md` / `it's.md`:`ls-files -z` 在 `core.quotepath=false|true|默认`
  三种设置下输出**逐字节相同**,`core.precomposeunicode=true` 也不影响;C-quote 只在
  **不带 `-z`** 时发生(`"d/\346\224\266..."`)。⇒ 删掉那条空操作变异 + 删掉实现里那行
  装饰性的 `-c core.quotepath=false`,有实测支撑,不是"改考卷让自己及格"。
  **但我只量到了本机这一版 git**:任务书 Q6 问的"有没有别的 git 版本/平台"我答不了,
  它比我的证据宽。这一条留给腿。
- **Q2(带单引号的文件名)我把它从推理变成了实测。** 抽出 `shq()` 单独喂进夹具:
  `it's.md` → `'it'\''s.md'`(标准 POSIX 形式),`a b.md`/`a"b.md`/`a$b.md`/`a\`b\`.md`/
  含换行的名字都正确;再把闸打印的那句药方 **`eval` 真跑了一遍**,三种形状
  (`it's.md`、`a b.md`、`a$b.md`)全部 rc=0、文件真的搬过去了(`git status` 见 R 三条)。
  ⇒ Q2 担心的那条路是通的。**该不该为它补一条判据是另一个问题**:补 = 动 `tests/`,
  会作废正在跑的这一轮指纹,所以记成账 A6,不在本轮改。
- 🆕 **我自己咬到一条新的(不在本轮 diff 里,是存量,但正好长在本单主题上):
  `VOID-` 这个命名约定会让 5b 的"最后一份"指错。** `bin/_evidence.sh:22` 的 `ev_files`
  用 glob 字典序当时间序,注释写着「文件名以 UTC 时间戳打头,runlog 保证」——
  而本单自己发明的作废改名 `VOID-<时间戳>-...` 把 `V` 放到了时间戳前面,
  字典序里 `V` > 数字 ⇒ **作废的那份排到最后**。仓外夹具实测:一份带收尾行的
  `VOID-20260909...` 与一份真正最新的 `20260910...` 并存时,只贴真正最后那份 ⇒ 闸挡下,
  并打印「最后那一遍才是结论所依据的那一遍」**指着那份我已经作废的**。
  本单侥幸没被咬到(两份 VOID 都断在收尾行之前,`grep -c '^runlog: '` = 0),
  但 5b' 的文案恰恰**鼓励**保留作废的完整收据("删掉它才是造假,贴出来说清楚不是"),
  所以这条路真能走到。最小修法:作废标记挪到时间戳**之后**(`<ts>-VOID-01-...`),
  或让 `ev_files` 按收据里的时间字段排。记成账 A7(动 `bin/`,不在本轮改)。
- **我派发这一轮时自己失手一处,如实记:** `PANEL_ORACLE_CMD` 我写成
  `tests/test-track-guard.sh`(该文件没有执行位,收据里一直是 `bash tests/...`),
  所以本轮 `.oracle.log` 只有一行 `Permission denied`、`ORACLE rc=126`。
  它"只记录不阻断",不影响腿;补法是上面那份 `guard-at-dispatch-head` 收据
  (同一条命令、同一个 head、干净树、106/0),比原来那份 `dirty=yes` 的引用更强。
- **任务书里有一句引用是旧的(我写的,不改了,如实标注):** 它把 "106 条全绿" 指向
  `*-01-g15-order-green.txt`,而那份跑在 `commit=da2f782 dirty=yes`(判据先行那一版 + 未提交的修复)。
  当前内容的权威绿是 `suite-full-r5`(`5cedd63`,干净)与 `guard-at-dispatch-head`(`8546799`,干净);
  已实测 `git diff 5cedd63..HEAD -- bin/ tests/` **为空**,所以那份绿没有过期,只是引用指旧了。
  任务书此刻不能改(它在交付指纹范围内,改了会作废正在跑的这一轮)。
  **如果有腿抓到这一处,那是它读得细,记进信任校准。**

#### 追加自审(09:30~09:45,仍在任何腿给出结论之前;期间我只看过 kimi 的进度旁白,未见其发现)

- 🔴 **D-b 复现了 —— 第四轮 subdeepseek 报对了,而前一轮的我记的是"主裁没复现"。**
  仓外夹具 + **对照组**(合法 `git mv` 整份 ⇒ 闸 rc=0,仓里一份):
  `cp -r tracks/t tracks/archive/t && git add tracks/archive/t`(只 stage archive 侧)
  ⇒ **闸也 rc=0**,落库后 `tracks/t/decision.json` 与 `tracks/archive/t/decision.json`
  **同时存在** —— 正是"track 名全生命周期必须唯一,归档必须 move 不能 copy"要防的形状。
  机制:`bin/track-guard:36-38` 的 `active_typed_dirs_changed` 只认**staged 的 active 路径**,
  而 copy 在 active 侧什么都不 stage ⇒ 整个循环(含那条唯一性断言)压根不进。
  爆炸半径也量了:交付投影**确实**认得出碰撞(`review-delivery: active/archive track collision`,
  真实 rc=1),但它只在 `bin/track-record:395` 的 `if required_reviews:` 里面被叫起来
  ⇒ **self 档(0 条评审预算)整块跳过 ⇒ 同名碰撞全程静默**(闸 rc=0、
  `track-record validate --phase archive` 报 status=valid,之后每次碰 archive 侧仍旧放行);
  standard/high 档会在 `delivery.capture` 那里 fail-closed(安全但报错指向不明)。
  最小修法方向:唯一性那一问要按 **index 视图**问(archive 侧 staged + active 在 index 里还有副本),
  和本单已经吃过的那一课(`git cat-file -e ":path"` 问的是 index、"两个条件缺一不可")同一类。
  **本轮不修**(动 `bin/`+`tests/` 会作废正在跑的这一轮指纹;且它与 D-a 是同一族问题,
  该并成下一单一起做),A3 从"报了但没复现"升级为**已复现、机制与半径已钉死**。

- 顺手记一笔工艺:上面量投影时我写了 `python3 … | tail -3; echo rc=$?`,读到的是 `tail` 的 rc=0,
  差点把"投影没报错"写下来。**管道吃 rc,这是本机第 6 次**(去掉管道后真实 rc=1)。

#### 派发过程中挖出的工具债(不属本单交付,记账免得丢)

- **A8 `failure_kind` 分类器会把腿读过的仓库正文当成自己的错误信息。** 本轮 glm 腿的真死因是
  **它自己的沙箱拒绝了一次 Bash 调用**(`permission requested: external_directory (/tmp/opencode/qtest/*…); auto-rejecting` [仓外不承重]
  ⇒ 工具调用报错 ⇒ 没写 `Conclusion:` 行 ⇒ `model returned no verdict`),
  而 `subglm.agent.result.json` 记的是 `failure_kind: "quota"`。根因:`bin/_review_result.py:59`
  的 `QUOTA_FAILURE_RE = /quota|额度|balance|billing/i` 扫的是 `failure_text`
  (stderr,否则整份日志),而腿的日志里混着**它引用的仓库正文**;本轮全日志唯一命中是第 1051 行
  `"api_cost": null, "billing_mode": null}` —— 那是 `_review_result.py` **自己的数据模型**。
  后果:量具指着"去充值",真正要修的是沙箱与任务书;腿的健康档案也被记脏。
- **A9 glm 的 chat 回退腿此刻结构性坏着。** `https://opencode.ai/zen/go/v1/chat/completions`
  返回 `HTTP 400 MissingSessionID`(缺 `x-opencode-session`)⇒ 回退腿 767ms 就死。
  加上 agent 腿这次的失败,glm **连败第 3 轮** ⇒ 按 `PANEL_HEALTH_DEAD_STREAK=3` 应停止轮换。
- **A10 任务书该告诉腿"夹具只能搭在你自己的快照里"。** 两条腿都想去 `/tmp` 搭实验台:
  glm 被 `external_directory` 拦住后**当场停了**;kimi 被 PreToolUse 拦住后**改写进快照继续干**。
  一句话的任务书补丁能省掉一整条腿。

### findings —— 腿的输出(第五轮三次派发的真实结局)

**派发史(三次,前两次零产出):**
1. 09-09 22:30 派出 ⇒ 3 分钟后整组被断线 SIGTERM 砍掉,零发现、无花名册。
2. 09-10 09:07 断线后接手重派 ⇒ **2 分 47 秒后又被砍**(两条腿 `.err` 同一秒 `Terminated`)。
   deepseek 那条留下 4.4MB 流水,读完只有 11 句工具旁白、零发现(我读过,如实记:
   这不构成"读了腿的结论",反锚定仍成立)。
3. 09-10 09:15 我把控制器 **reparent 到 init** 后重派 ⇒ 活到收尾。结果见上面花名册。

**subglm(zhipu):FAIL —— 但它自报的死因是错的,真死因我查出来了。**
`failure_kind: "quota"`,而日志里真正发生的是:它想在 `/tmp/opencode/qtest` 搭夹具 ⇒ [仓外不承重]
opencode 的 `external_directory` 权限 **auto-rejecting** ⇒ 工具调用报错 ⇒ 它当场停了 ⇒
`model returned no verdict`。误判根因见上面 A8(分类器扫到腿引用的仓库正文里的 `billing_mode`)。
回退聊天腿另有一个结构性坏点:`HTTP 400 MissingSessionID`(见 A9)。

**subkimi(moonshot):FAIL(rc=124,25 分钟墙钟砍掉)。** 它跑得**很实**:在快照内搭实验台
(被 PreToolUse 拦住写 `/tmp` 后自己改道,和 glm 撞同一堵墙但绕过去了),用 git 源码
(`builtin/ls-files.c` 的 `write_name_quoted` / `quote_c_style`)回答 Q6,并自认了两次
"我的夹具坏了、红在别处"。**被砍时正卡在一条它称为"反常"的探针上**:变异后的药方里
没有出现 `it's` 那一句。**那条线索我接手查完了,而它指向一个真洞 —— 见下面 G16。**

**submimo(xiaomi):PASS**,八问逐条作答。我逐条复核后的判读:
- **Q1「判据只收紧没放松」——与我的集合差方法独立同意。** 采信。
- 🆕 **它挖到一条我漏掉的真缺口(采纳并已修)**:`shq()` **本身没有任何变异咬着它** ——
  现有两条咬的是 `-z` 与"不加引号",而"shq 退回裸 printf"这条路没人测。
  我自己的 Q1 审计只比了断言名字,**没问"每条断言有没有变异咬着"**,所以看不见这个洞。
  已补变异「shq 退回裸输出(转义整个关掉)」,红检见 mutation-r6。
- **它削弱了我自己写的一条理由(接受)**:D-a 的第三条理由"删除在 diff 里看得见"
  只对**单次提交**成立 —— 拆成两笔提交,第二笔的 diff 里看不见第一笔的删除。
  ⇒ D-a 的取舍理由现在只剩两条,记进下一单的题面。
- ❌ **它在 D-b 上说错了,而且是"读了我的作业"那种错。** 它写"主裁没复现,我也复现不了…
  取舍站得住"——但我在它跑之前就带对照组复现了(见上面自审:合法 move rc=0 一份 /
  copy-not-move rc=0 两份)。它复述的"主裁没复现"来自任务书里我那句**过期的话**。
  ⇒ 这条不采信;信任校准记一笔:**附和我的腿要先问它是独立判断还是在读我的作业。**
- Q4/Q5/Q7 的结论与我各自独立的实测一致(Q5 它谈的是药方里那个 `[ -e "$left" ]`,
  我量的是 G15 那个 `[ -e ]`,两个不同的点,结论都是低风险)。

### 第五轮之后我自己咬到的洞(已在本单修掉)—— G16

kimi 那条"反常"线索接着查下去,是一个**真洞,而且它让本单前面所有工作打了折**:
`staged()` 是 `git diff --cached --name-only`,**对 rename 只印目标路径**。于是"部分取回"
(decision/verify 搬到 active,正文与收据留在 archive)那笔提交里,staged 一个
`tracks/archive/` 路径都没有 ⇒ `archive_typed_validation_dirs` 为空 ⇒ **整段归档复验
(含残件检查和本单反复打磨的那几句药方)压根不被叫起来**,半截取回静默落库(实测 rc=0)。

判据一直照不出它,是因为 **G13①/G14 全家的夹具都顺手 stage 了一笔 archive 侧文件** ——
那一笔才是让目录进名单的原因。**判据测的一直是"进了名单之后对不对",
没有一条测过"该进名单的时候进不进"。**

- 判据先行 `9fdb938`(G16①三条红 + G16②对照组绿,收据 `g16-red`,107/3);
- 实现 `052529b`(只往名单里**加** rename 的源,不动 `staged()` 本身;收据 `g16-green`,110/0);
- 红检:两条新变异(shq / 复验名单),收据 `mutation-r6`;
- 副作用探针:archive 内部给已归档 track 改名 —— **本来就被 `rule=track.identity` 拦着**,
  我的改动只是在这个已失败的场景里多印一行不清楚的话,没有新误报。

- arbitrated verdict (主裁): <待填:第六轮之后>

## Accepted deviations

- ~~**A1**~~ **已量掉,不是洞(2026-09-10 更正我自己先前写的那句)。** 我原先写的是
  "`-e` 为假 ⇒ 放行 ⇒ `mv` 覆盖那个链接"。实测两种形状都 fail-closed:
  链接指向**存在的目录** ⇒ `[ -e ]` 为真 ⇒ **G15 自己拒绝**,仓外目标零字节被写;
  **悬空**链接 ⇒ `[ -e ]` 为假 ⇒ G15 不响,但 **`mv` 自己拒绝**
  (`cannot overwrite non-directory`,rc=1,一个文件都没动)。
  唯一代价:悬空那种的报错文案不如闸自己的清楚。不再当账挂着。
- **A2(低,可移植性)** `printf '%s\n' "${archive_left_list[@]}"` 数组为空时:
  bash 5.2.21 实测 rc=0(打一个空行);bash <4.4 在 `set -u` 下会中止。本仓工具只跑在这台 Linux。
- **A3** D-a(整档删除 + 名号复用照样放行)与 D-b(copy-not-move 绕同名唯一)本轮未修,
  理由：非本轮引入，且现有协议允许整份档案作废；身份复用与纯复制需要独立定义生命周期约束。
  “删除在 diff 里看得见”不能证明跨提交的身份连续性，已撤回，不能作为延后依据。
- **A4** G15 是"物理存在就拒",空目录也拒。我认为空的残留目录本身就是症状、值得停一次;
  误报面见任务书 Q4。
- **A5** 方向账:`track unarchive` 才是根治,本轮只修文案与顺序(见上面规格自查)。
- **A6** `shq` 的 sed 转义分支没有判据钉住(我已实测走得通,见 findings)。
- **A7** `VOID-` 命名与 `ev_files` 排序的冲突(我这一轮自己咬到的,见 findings)。

## 时间线(为什么这一单跨了两次断线)

- 09-09 22:30 第五轮第一次派发 ⇒ 3 分钟后整组被断线 SIGTERM 砍掉,零发现、无花名册。
- 09-10 09:07 断线后接手、重派 ⇒ **又在 2 分 47 秒后被砍**(两条腿 `.err` 同一秒 `Terminated`)。
  两轮都不算"审过"。
- 09-10 09:15 再接手一次(本次)。改法:把控制器**整个 reparent 到 init**
  (`setsid --fork nohup`,实测 `PPID=1`),不再只依赖 panel-review 内部给腿套的
  `setsid --wait` —— 那层护甲挡得住打到进程组的 SIGTERM,挡不住顺着进程树走的清理。

## 2026-09-11 断线接手：路径解析红检

亲跑昨天留下的 G17/G18，重现 115 passed / 12 failed。ASCII 对照和无关 rename 对照通过；特殊文件名在 active、archive 复验、新增归档证据三个入口均漏选。保留昨天原始红收据（首轮夹具年龄修正也有独立记录），先提交判据，再修实现。

- `runlog: r7-resume-red rc=1 commit=c2bb789 dirty=yes at=2026-09-11T01:36:53Z file=tracks/archive-tree-and-untracked-views/evidence/20260911T013653Z-01-r7-resume-red.txt`

实现：三个目录选择入口以 NUL 分隔读取真实 Git 路径，目录集合及消费者也保留 NUL。归档复验路径采用 `--no-renames`，将 rename 展开为源删除与目标新增，无须自行猜相似度。原 `staged()` 的其他历史消费者不在本次修复范围。针对性回归 127/0。第一遍绿检被沙箱禁止 unshare，rc=78；获准在沙箱外建立断网隔离后通过。

- `runlog: r7-paths-green rc=78 commit=09c4a4f dirty=yes at=2026-09-11T01:38:25Z file=tracks/archive-tree-and-untracked-views/evidence/20260911T013825Z-01-r7-paths-green.txt`
- `runlog: r7-paths-green rc=0 commit=09c4a4f dirty=yes at=2026-09-11T01:38:33Z file=tracks/archive-tree-and-untracked-views/evidence/20260911T013833Z-01-r7-paths-green.txt`
