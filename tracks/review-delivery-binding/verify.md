# 验证记录

实现已在树上,主裁裁决 PASS(2026-09-09)。机器裁决字段仍只在 decision.json —— 这里的散文不承担裁决。
⚠️ 上面这句在 09-09 下午之前一直写着「尚处设计阶段;没有实现或完成结论」,而那时实现早已提交 —— **散文比事实旧**,接手时按它判断会错。

## 基线

第一遍因沙箱禁止 unshare，各套件在执行测试前拒跑。第二遍在宿主跑，但我同时运行了真实 panel-explore，改动了 MiMo 评审配置；V45 正确发现环境变化，该次回归不能作为干净基线。外审结束后单独重跑受影响套件。

runlog: baseline rc=1 commit=553e7ba dirty=yes at=2026-09-09T02:02:25Z file=tracks/review-delivery-binding/evidence/20260909T020225Z-01-baseline.txt

runlog: baseline-host rc=1 commit=553e7ba dirty=yes at=2026-09-09T02:03:31Z file=tracks/review-delivery-binding/evidence/20260909T020331Z-01-baseline-host.txt

## 新判据红检

旧实现没有交付指纹 API，10 条新行为测试在缺模块处红；另 1 条直接证明 decision v2 可被降回 v1、旧 shape 校验仍返回成功。实现后还需对归档比较做变异红检，不能把缺模块当成逻辑闸有效的证明。

runlog: delivery-red rc=1 commit=553e7ba dirty=yes at=2026-09-09T02:12:53Z file=tracks/review-delivery-binding/evidence/20260909T021253Z-01-delivery-red.txt

## 接手后补的判据(主裁换人:第 3~5 步由 Claude 接手,GPT 腿额度耗尽停在实现中途)

前一轮的红检只证明"模块不在"(缺件红),证明不了"闸咬得动",也没有任何判据问过
**这道闸有没有接上线**。补三条行为级判据 + 一份变异红检,并先证明它们此刻是红的:

- P9a/P9b(tests/test-panel-observation.sh):派发端。panel-review 必须把归属 track
  传进腿的环境,否则每条腿都产 v1 subject、归档闸的比较永远走不到。**此刻红。**
- 模板端(tests/test_review_delivery.py):`track new` 出来的 track 必须要求绑定。
  **此刻红**(实测打印 `delivery=legacy-unbound`)。
- RW8(tests/test-review-workspace.sh):喂料端整链(workspace→facts→subject),
  外加**两套扫描实现同解**的对账。这段实现已在,**此刻绿 = 锚断言**;
  第 4 段用副本把 delivery 段拆掉,证明它咬得动(2 条转红)。
- tests/mutation-review-delivery.sh:6 个变异逐条放松闸,证明判据咬得住。
  与 mutation-review-result.sh 同形态(只动仓外副本、不就地变异),同样是手动红检工具。

第一份收据里 RW8 有一条红在别处(我自己判据的 bug:`--task-sha256` 少写 `sha256:` 前缀),
已修;以 v2 那份为准。**两份都留着,不删。**
⚠️ 两份收据行的 `rc` 是外层 bash 的退出码,不是"判据全绿"的意思 —— 红在正文里逐条列着。

runlog: wiring-pins-red rc=1 commit=a91a65d dirty=yes at=2026-09-09T02:43:17Z file=tracks/review-delivery-binding/evidence/20260909T024317Z-01-wiring-pins-red.txt

runlog: wiring-pins-red-v2 rc=0 commit=a91a65d dirty=yes at=2026-09-09T02:44:23Z file=tracks/review-delivery-binding/evidence/20260909T024423Z-01-wiring-pins-red-v2.txt

runlog: baseline-review-tooling-serial rc=0 commit=553e7ba dirty=yes at=2026-09-09T02:10:42Z file=tracks/review-delivery-binding/evidence/20260909T021042Z-01-baseline-review-tooling-serial.txt

## 断线接手与收口(09-09 下午,主裁)

### 断线砍掉了什么(以及为什么必须重跑)
r4(041323Z)派 submimo+subdeepseek:submimo rc=0 给 PASS,subdeepseek 被 SIGTERM
砍在思考中途(`.err` 尾行 `Terminated`);**控制器同时被砍 ⇒ 没写 observation**。
花名册用 `panel-roster` 从盘上重建(它把 subdeepseek 印成「未收尾」,不猜死因,对);
但 observation 无法从盘上重建 —— 已核 observations/,最后一份 panel 事件是 r3 的
041213Z。**r4 对归档闸不存在**。`panel_review_coverage` 的分组键是
(run_id, subject_digest),跨 run 同 subject 只进 same_subject_shadow 诊断,
拿 r4 的 submimo 去和新腿拼票在机制上就不成立 ⇒ 只能整轮重跑。

### 本单两次被自己交付的闸卡住(自证)
1. r2(035748Z)是一轮**完全合格**的双家族 PASS(submimo+subkimi,均 v2,
   delivery=ac465ecc…)。此后 ba00ad0 改判据 ⇒ 指纹变 e0d00c54… ⇒ r2 授权不了归档。
2. r5(044823Z)双家族 PASS(delivery=e0d00c54…)之后,我采纳评审发现改了一行源码
   ⇒ 指纹变 486757…、更新任务书后再变 dc7e282b… ⇒ **r5 也随即过期**,重派 r6。
闸不是空转的:它先卡住了自己两次。

### aiwork 审自己时的两条特殊性(记账,别人接手会踩)
- `--require-my-review` 必须指向仓外(`/root/panel-my-reviews/`):约定路径在被审仓内,
  闸会拒绝,而它建议的正是它拒绝的那条路径。
- **panel 任务书 `tasks/*.md` 未被 .gitignore 忽略 ⇒ 它在交付指纹里**。改任务书
  就会改指纹(本轮实测:改完从 486757 变 dc7e282b)。`logs/*` 被忽略,评审日志不污染。

### 闸③ 亲读(自审之后新增的提交)
自审落盘 11:03、覆盖到 f01a447,而 r4/r5 快照是 ba00ad0。中间两个提交我补读了:
- 9808d1e:decision schema 1→2 + 打勾。成立。
- ba00ad0(**动判据**):P9a/P9b 两处注入 `AIWORK_REVIEW_TRACK=ghost`。成立 —— 注入前
  "env -u 抹掉了"与"调用环境本来就没有"不可区分,拆掉 `-u` 判据照样全绿;awk 的
  `n > 0` 同时防住"零腿派发 ⇒ 空文件 ⇒ 恒真"。红检收据(040036Z)亲读:变异副本
  70/1(P9b 红)、真实现 71/0,锚点用 `count(old)==1` 防漂移。

### 逐条对账
**D1(subdeepseek r5 孤发现,复核属实,已修)**:`REVIEW_DELIVERY_DIGEST` 是同族 7 个
`REVIEW_*` 里唯一没进 export 清单的;当前 adapter 都在同一 sourced shell 里先后调
prepare/write_facts,靠全局变量**恰好**可见。写 facts 一旦被挪进子进程,这条链会
**静默**产出 v1 subject(带 source、照样计入 coverage),归档端要等比较时才响,
观测侧那时已经是"看起来健康、其实没绑定" —— 正是本单要消灭的失败类别。
**submimo 与我自审两遍都没看见这条**,这正是 panel 的价值。
已上 RW9(必须用**新 bash 进程**问:subshell 会 fork 走非导出变量 ⇒ 判据永远绿=白写)
+ 一行 export。判据 01730be 与修复 b7dc080 **分开提交**。
**D2(subdeepseek,信息级,不修)**:`schema_version` 是手写整数,只在工作树里"借"v2
派评审、归档前改回 v1 可走 legacy-unbound。核 track-record:220-235:降级守卫同时查
`HEAD:` 与 index,**本单 v2 已在 9808d1e 提交,改不回去**;对本单不成立,作为全局
设计边界记账(CONVENTION 本就允许 v1/legacy)。
**我标了、腿没标的(依然成立)**:`observations/[^/]+\.json` 排除在指纹之外是**必要**
设计(否则每写一份 observation 都让评审过期,机制无法收敛),代价是它成为信任边界 ——
归档闸信任"observations 只由控制器写入",该前提由 track `repo-write-audit`(08-19)
保障而非本单。`load_observations` 对条目本身严格(拒符号链接、拒非 .json、有大小上限、
目录是链接直接报错),伪造需要业主级写权限,与自审取舍 1 同一威胁模型。载明,不藏。

### 反锚定(如实记账,不写"已反锚定")
两轮都报 anchor leak:`tracks/review-delivery-binding/verify.md` 早已在树上,底座腿
自己读树就够得着;`tasks/` 下另有 11 份**别的 track** 的 my-review(未跟踪,会被内联)。
泄漏的是"我做了哪些判据",裁决本身在仓外 my-review。两腿都真跑了判据并给出行号与
可复现命令,不像照抄。做不到干净就记账,这比写一句"已反锚定"诚实。

### r6 失败:两条腿同时撞墙钟(根因不是"腿慢")
r6(051123Z)submimo **rc=124**、subdeepseek 的 agent 腿 **rc=124** 后回落聊天腿
(降级、只看得见 diff)⇒ 裁决 NEEDS_MORE_INFO ⇒ 按规矩降级与 NMI 都不能补预算,
这一轮凑不出覆盖。escalation=failure(no-healthy-spare)。
**根因**:submimo 被砍时正在跑判据(日志最后是 test-panel-observation.sh 的 71 条跑完)。
我在 r6 的任务书里加了"重点看这两个新提交",却**没告诉它主裁已经跑过整套回归**,
于是两条腿各自去重跑 `bin/rust-check-review-tooling`(它自己就要 5 分 50 秒)⇒ 撞上 900s。
**这是任务书的缺陷,不只是墙钟太短。** 两手都做:任务书加"时间预算"段(列出主裁已跑过的
四组数字与收据号、点名不要跑整套回归)+ `MIMO_CLI_TIMEOUT=1800 DEEPSEEK_TIMEOUT=1800`。
效果:submimo 从超时(>900s)降到 **245s**。
> 这条给记忆里那笔敞账(「评审腿的墙钟上限该换成停滞检测」)补了一个新事实:
> 900s 对"腿会真去跑判据"的任务本来就不够,而任务书不说清主裁跑过什么,腿只能重跑。

### r7:合格的一轮(本单的归档凭据)
run_id=20260909-133000-868803-panel-review,exit_code=0,escalation=none,snapshot=b7dc080。
- submimo(xiaomi)rc=0 **PASS** 245s / subdeepseek(deepseek)rc=0 **PASS** 724s
- 两条腿均 schema_version=2、manifest_version=2、**degraded=False**
- 两条腿 `subject.delivery.digest` = `sha256:9dd0fb98…` = **主裁独立重算的当前指纹**(逐字符核对)
observation 已落账:`observations/20260909T054206Z-panel-review-execution_finished-001.json`。

### r7 的新发现:Finding 1(subdeepseek 孤发现,LOW,**不在本单修,开后续单**)
**位置** `bin/track-record:465-470`。复验已归档 track 时取
`git log --no-renames --reverse --diff-filter=A` 的**首行** —— 即该路径 decision.json
**第一次**被 add 的提交,而非本次归档那一次。腿用探针复现:同一 track 名经手工
unarchive→re-archive 两次生命周期后,内容已从 answer=1 改成 2,
`validate --phase archive --source staged` 对第二次归档仍 exit 0。
**主裁读代码独立复核,结论比腿说的更狠一点**:释放链上有两道闸,
① `bin/track archive` 在 mv **之前**校验,那时 track_dir 还是 `tracks/<name>` ⇒ tree=None
⇒ 用 working 视图 ⇒ **拦得住**;
② commit hook(`bin/track-guard`)校验 staged —— 首次归档时 HEAD 里还没有
`tracks/archive/<name>/decision.json` ⇒ `cat-file -e` 失败 ⇒ tree=None ⇒ 也拦得住;
**但在手工 `git mv` + commit 的 re-archive 路径上**,HEAD 里已有第一次归档留下的那份
⇒ 走历史树分支 ⇒ 拿第一次归档的内容当 target ⇒ 第一次那轮(已过期的)评审匹配成功
⇒ 这道闸被旁路。触发需要业主级手工操作(曾归档 → 手工 unarchive → 改内容 → 手工 re-archive),
**对本单不成立**(本单是首次归档,走的是上面①②两条都 tree=None 的路径)。
按 proposal 写明的范围("不追溯改变历史裁决"),记为后续单:把树钉在**归档当次**提交
(取 `--diff-filter=A` 最后一行,或由 archive 工具写入提交标记),并补一条能造出
"两次生命周期"的判据 —— 夹具成本正是它不进本单的原因。
> 附带一条同源事实:归档**之后**对 `tracks/archive/<name>/` 下文件的提交修改,
> 对该复验同样不可见(它永远比对第一次 add 的内容)。同一处修。
> 这也修正了 `tests/mutation-review-delivery.sh:12-14` 头部那句作者自述
>("历史归档用原始提交树放松后是响亮失败"):存在一个**不响亮的中间态**。

### 收据(机器写的,逐字节粘,别改数)

runlog: rw9-red rc=1 commit=ba00ad0 dirty=yes at=2026-09-09T05:01:43Z file=tracks/review-delivery-binding/evidence/20260909T050143Z-01-rw9-red.txt

runlog: rw9-green rc=0 commit=01730be dirty=yes at=2026-09-09T05:02:40Z file=tracks/review-delivery-binding/evidence/20260909T050240Z-01-rw9-green.txt

runlog: full-after-rw9 rc=0 commit=b7dc080 dirty=yes at=2026-09-09T05:03:16Z file=tracks/review-delivery-binding/evidence/20260909T050316Z-01-full-after-rw9.txt

runlog: mutation-verified rc=0 commit=b7dc080 dirty=yes at=2026-09-09T05:09:35Z file=tracks/review-delivery-binding/evidence/20260909T050935Z-01-mutation-verified.txt
