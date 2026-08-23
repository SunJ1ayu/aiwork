# Verify: panel-roster-from-disk

- Date: 2026-08-23

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

## Mechanical checks

- [x] build passes(无构建物;工具是脚本)
- [x] tests pass
- [x] no secrets / unsafe ops

**机器打印的**(不是我的转述):

```
runlog: oracle-red-before-impl rc=1 commit=d289e27 dirty=yes at=2026-08-23T05:12:18Z file=tracks/panel-roster-from-disk/evidence/20260823T051218Z-01-oracle-red-before-impl.txt
runlog: oracle-red-r9-r10-r7d rc=1 commit=bbdcdcd dirty=yes at=2026-08-23T07:52:51Z file=tracks/panel-roster-from-disk/evidence/20260823T075251Z-01-oracle-red-r9-r10-r7d.txt
runlog: redcheck-mutation-final rc=0 commit=fa31867 dirty=yes at=2026-08-23T07:54:11Z file=tracks/panel-roster-from-disk/evidence/20260823T075411Z-01-redcheck-mutation-final.txt
runlog: tooling-suite-full-final rc=0 commit=fa31867 dirty=yes at=2026-08-23T07:56:04Z file=tracks/panel-roster-from-disk/evidence/20260823T075604Z-01-tooling-suite-full-final.txt
runlog: redcheck-m11-and-target-gate rc=0 commit=a464d6c dirty=yes at=2026-08-23T08:20:35Z file=tracks/panel-roster-from-disk/evidence/20260823T082035Z-01-redcheck-m11-and-target-gate.txt
runlog: redcheck-after-polling rc=0 commit=7c838dc dirty=yes at=2026-08-23T08:26:20Z file=tracks/panel-roster-from-disk/evidence/20260823T082620Z-01-redcheck-after-polling.txt
runlog: oracle-green-final rc=0 commit=7c838dc dirty=yes at=2026-08-23T08:38:17Z file=tracks/panel-roster-from-disk/evidence/20260823T083817Z-01-oracle-green-final.txt
runlog: redcheck-final rc=0 commit=7c838dc dirty=yes at=2026-08-23T08:38:48Z file=tracks/panel-roster-from-disk/evidence/20260823T083848Z-01-redcheck-final.txt
runlog: tooling-suite-final rc=0 commit=7c838dc dirty=yes at=2026-08-23T08:43:50Z file=tracks/panel-roster-from-disk/evidence/20260823T084350Z-01-tooling-suite-final.txt
runlog: oracle-red-round2 rc=1 commit=4fd28b4 dirty=yes at=2026-08-23T09:28:01Z file=tracks/panel-roster-from-disk/evidence/20260823T092801Z-01-oracle-red-round2.txt
runlog: redcheck-round2 rc=0 commit=c5750c0 dirty=yes at=2026-08-23T09:30:40Z file=tracks/panel-roster-from-disk/evidence/20260823T093040Z-01-redcheck-round2.txt
runlog: oracle-green-round2 rc=0 commit=c5750c0 dirty=yes at=2026-08-23T09:36:38Z file=tracks/panel-roster-from-disk/evidence/20260823T093638Z-01-oracle-green-round2.txt
runlog: tooling-suite-round2 rc=0 commit=c5750c0 dirty=yes at=2026-08-23T09:36:57Z file=tracks/panel-roster-from-disk/evidence/20260823T093657Z-01-tooling-suite-round2.txt
runlog: redcheck-after-doc-sync rc=0 commit=2d9b076 dirty=yes at=2026-08-23T10:05:19Z file=tracks/archive/panel-roster-from-disk/evidence/20260823T100519Z-01-redcheck-after-doc-sync.txt
runlog: tooling-suite-after-doc-sync rc=0 commit=2d9b076 dirty=yes at=2026-08-23T10:11:24Z file=tracks/archive/panel-roster-from-disk/evidence/20260823T101124Z-01-tooling-suite-after-doc-sync.txt
```

**归档之后又追加的两份**(`*-after-doc-sync`):归档当天按第一性把「这一单改变的事实
被复制到了几处」机械搜了一遍,改准了五处文档 + 一处**判据自相矛盾**
(R7 仍把 `KILLED` 列成合格写法,而 R7d 禁止它)。动了判据就得重跑:
红检 16 咬住 0 漏网、判据 33/33、19 套件全绿(含 workflow-docs 32)。
> ⚠️ 两件事记在这儿:① **归档后的工件仍可被追加**(runlog 照样往 archive/ 里写),
> 所以"归档=冻结"是错觉;② 正因为如此,**收据区会在归档之后过期** ——
> 这次就是 `track-guard` 规矩 5b 当场拦下我的,不是我自己想起来的。

**红的那几份一份没藏**(规矩 5b):

- `oracle-red-before-impl` rc=1 —— 实现还不存在时,11 红 2 绿。
- `oracle-red-r9-r10-r7d` rc=1 —— 第一轮评审的发现收成判据、修复还没写时,R7d/R9a/R9b 三条红。
- `oracle-red-round2` rc=1 —— 第二轮的发现收成判据、修复还没写时,R12 五条红(28 绿 5 红)。
  **顺带更正一句我自己写得比事实好看的话**:上游 commit `bbdcdcd` 的标题写
  "R9/R10 现在是红的",而这份机器收据显示 **R10 两条修复前就是绿的**
  (它正文其实自己写着"实测本来就是对的,纯粹没人守")。R10 是补守卫,不是修 bug。

**最终三份是第二轮那组**(`redcheck-round2` / `oracle-green-round2` / `tooling-suite-round2`),
跑在最后一次编辑之后:最后一次编辑是清掉 R12b 的误报(09:3x),三份收据
09:30:40 / 09:36:38 / 09:36:57,判据 33/33、红检 16 咬住 0 漏网、19 套件全绿。
(`*-final` 那三份是第一轮收口时的,**不是**最终态 —— 名字里的 "final" 是我起的,
rc 和时间戳才是机器写的。本机记过账:收据名字会撒谎。)

## Review

- **规格自查(在读任何第二轮 panel 输出之前作答)**:
  如果规格本身就是错的,会错成什么样?

  规格是「花名册 = f(盘上状态),不依赖任何进程活着」。它可能错在**目标选偏**:
  保住的是"派了谁、谁跑到哪儿",**没保住"控制器为什么死"**。08-19 那次死因至今不明,
  本单做完之后**下一次**同样死法仍然是死因不明 —— 只是这次至少知道腿跑完了。
  我怎么发现它错了?判据全绿而**下一次事故仍然查不出根因**就是证据。
  这一点我在本单是**明知而接受**的(proposal 的"明确不做"第一条),
  理由:控制器死因需要的是它自己的 stdout/stderr 落盘 + pid 记录,那是另一单;
  而本单不做那件事也能独立成立(记录不再随控制器一起消失)。
  第一轮 subglm 答过"规格自洽",但它是在**读不到 panel-review 全文**的前提下答的,
  权重我不给满。
  **另一种错法**:R7d 那条。花名册现在对缺 state 的腿说"未收尾(被砍或仍在跑)" ——
  这是把一件**本可查清的事**永久变成了"说不知道"。我选它是因为可查的两条路
  (pid / 心跳)都有各自的假阳性(pid 会被复用),而**说错死因比说不知道更坏**:
  第一轮我就用它把两条活着的腿印成了 `KILLED`。

- **腿的花名册**(第一轮那次事故,由 `panel-roster` 事后从盘上重建 —— 控制器被
  `timeout 120` 砍,当时**没有** `.roster` 文件):

```
# panel-review 花名册(2026-08-23 16:49:51)task=panel-roster-from-disk
# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
# impact-risk=high requested-budget=4 selected-count=4
# selected=submimo(xiaomi/submimo),subdeepseek(deepseek/subdeepseek-agent),subglm(zhipu/subglm-agent),subkimi(moonshot/subkimi)
# escalation=unknown(控制器没活到收尾)
# snapshot=head:0780c49
# 日志:logs/panel-roster-0823.*.log
submimo=FAIL(rc=124) subdeepseek=PASS(verdict=BLOCK) subglm=PASS(verdict=UNKNOWN,降级:回落聊天腿,只看得见 diff) subkimi=FAIL(rc=1)
```

  > **这一行本身就是本单的验收**:一轮**零记录**的评审(没有 roster、没有 observation、
  > 控制器死在第一条腿交卷之前),事后从盘上完整重建了出来。改动之前这些信息只存在于
  > 控制器内存里,随它一起没。

- **第二轮花名册**(这一次控制器活到了收尾,`.roster` 是它自己写的,与
  `panel-roster` 事后重建**归一化后一致** —— R5b 守着这一条。
  2026-08-23 track `panel-roster-doc-sync` 更正:原文写"逐字节一致"是言过其实,
  R5b 两边都过 `norm`,抬头嵌着渲染时间戳,字面逐字节根本不可能):

```
# panel-review 花名册(2026-08-23 17:26:38)task=panel-roster-from-disk
# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
# impact-risk=high requested-budget=4 selected-count=4
# selected=submimo(xiaomi/submimo),subdeepseek(deepseek/subdeepseek-agent),subglm(zhipu/subglm-agent),subkimi(moonshot/subkimi)
# escalation=none
# snapshot=head:4fd28b4
# 日志:logs/panel-roster2-0823.*.log
submimo=PASS(verdict=UNKNOWN) subdeepseek=PASS(verdict=PASS) subglm=FAIL(rc=1,降级:回落聊天腿也没成) subkimi=FAIL(rc=1)
```

  两条腿成功、两条腿挂了。挂的原因都读过(**失败腿的日志也要读**,本单最值钱的
  两条发现就是从失败腿里挖出来的):subglm 底座腿 900s 超时、回落的聊天腿撞上
  opencode 网关 HTTP 503(服务端,不是我们的问题);subkimi 是
  `provider managed:kimi-code has no credential configured`(和第一轮同因)。
  submimo 的 `verdict=UNKNOWN` 不是它没结论,是它没打独立的结论行 ——
  花名册按契约保守记 UNKNOWN,我读了日志才确认它实质通过。**保守是对的:
  宁可让我去开日志,也不许把"看起来像 PASS"记成 PASS。**

- findings:

  **第一轮(四条腿,已全部落地)**
  - F1 [HIGH,subdeepseek] 升级追加的增补腿在花名册里隐身(`SKIP(rotation)`),
    连它的失败也一起消失 —— **真回归**,改动前的老代码印得是对的。
    腿在真控制器上复现了。⇒ R9 + 两头修(盘上有 state 即认定跑过 / `.final` 补最终 selected)。
  - F2 [MED,subdeepseek] R4 自己会抖(嵌了秒级 `date`),它那次全套跑里**真红了**,
    而我那份"19 套件全绿"的收据是运气。⇒ 比之前先抹渲染时间戳。
  - F3 [LOW] state 写入非原子 ⇒ 半截 state 会印出没设计过的 `FAIL(rc=)`。⇒ 原子写。
  - F4 [LOW] 全 off 那条路没断言。⇒ R10(渲染路径)+ 后来的 R13(控制器路径)。
  - F5 [INFO] A-1 引号/参数传递**不成立** —— 腿拿真参数试过,标准写法是安全的。
    我后来又用含空格 / `$` / 引号的**路径**单独复现了一遍,头和腿都正确。
  - [subglm] 固定 sleep 会在负载下假红 ⇒ 改轮询;`LEG=(setsid --wait)` 是死代码 ⇒ 删。
  - [subglm] R5 的 `norm` 抹过头 ⇒ **我照着改了,又被自己的对照组证伪**(旧写法
    一样咬得住),已回退,只留下它逼出来的红检 M12。**这是本单第二次"腿说的
    听起来对,量一下才知道"。**

  **我自己挖的两条(线索来自一条超时被砍的失败腿留下的探针)**
  - **判据缺一整种杀法**:只测了"只杀控制器"(timeout),没测"杀整个进程组"(断线)。
    把落盘从 setsid 里挪进 `run_leg` 的后台子 shell,**旧判据 21 条全绿放行** ——
    而 `panel-review:540` 的规格白纸黑字写着"也不能在那里"。⇒ R11 + M11。
    **又一次「该问的写进了规格却没写进判据」。**
  - **红检工具自己坏了**:`grep -q "FAIL:.*$target"` 把靶子当正则,
    断言名里的 `**整组**` 让 `*` 变量词 ⇒ **一条真咬住的变异被报成漏网**。
    ⇒ `grep -F` + "靶子名过期"自检(两条都做了红检的红检)。

  **第二轮(两条腿,已全部落地)**
  - F1 [LOW,**submimo 与 subdeepseek 独立命中同一处**] `panel-roster` 帮助文本
    还写着"印成 KILLED",而 R7d 专门禁止这个词。**判据只看输出、看不见文档。**
  - F2 [LOW,subdeepseek] `.final` 缺失时 `selected`/`selected-count` 是派发前快照,
    读起来像事实。⇒ 头上标注。
  - F3 [LOW,subdeepseek] R10 只测渲染路径,`panel-review` 自己全 off 时没人守。⇒ R13。
  - F4 [LOW,subdeepseek] `escalation=unknown(控制器没活到收尾)` 对**还在跑**的控制器
    误读成"已死" —— **这道闸对腿守了 R7d,对控制器自己没守**。⇒ R12c/R12c2。
    (这句话在第二轮评审进行中就真的印出来过。)
  - [subdeepseek] 我在真盘上复现了它构造的"升级 spare 后控制器死"状态,腿那行正确。
  - [submimo] A-5~A-8 逐条回答,无阻塞;新提 F-2(`date` 格式与 R4 的 `strip_ts` 隐式耦合)
    —— 属实,当前贪婪匹配不会断,记账不修。

- **arbitrated verdict (主裁):PASS**

  理由:承重的两条(R1/R2 控制器死后花名册仍算得出、且退出码是真的)有**真事故**
  当场验收 —— 第一轮那次零记录的评审,事后从盘上完整重建了花名册,那一行就贴在上面。
  判据 33 条、红检 16 个变异 0 漏网、19 个套件全绿,承重断言每条都有变异咬着。
  两轮外审共 6 条腿次,第二轮 2 个不同家族(xiaomi / deepseek)成功且都无阻塞结论。
  **两轮之间我自己挖到的两条比腿报的更狠**(判据缺一整种杀法、红检工具自己坏了),
  这符合本机的老经验:panel 是盲点网,不是裁决,也替代不了我自己的第一遍。

  **不给满分的地方**:最终代码 `35cffd1` 比腿审过的快照 `4fd28b4` 新,新增的是
  落实它们自己发现的三处措辞 + R12/R13 判据 + M13~M16 红检。这部分**没有腿看过**,
  由我主裁 —— 都是文档/输出措辞与新判据,不改承重逻辑,且每条都有变异咬着。
  真要挑,这是本单唯一一处"我说了算"的地方,记在这儿。

- arbitrated verdict (主裁): <待定>

## Accepted deviations

- **控制器死因仍然不落盘**(第一/二轮都提,proposal 的"明确不做"第一条)。
  本单让**记录**不再随控制器一起消失,但"它为什么死"仍要靠调用方的重定向。
  08-19 那次的死因至今不明,**做完本单也仍然不明** —— 只是下一次至少留得下
  "派了谁、谁跑到哪儿"。**这是敞着的账,不是已解决。**
- **`.final` / health / observation 仍然只在控制器活到收尾时才写。** 花名册脱钩了,
  这三样没有。(subdeepseek F5)
- **`verdict_of` 严格匹配会把中文结论记成 UNKNOWN**(第一轮 subglm 的
  `结论:需要更多信息` 就是这样)。保守设计,不是本单引入,不改。
- **R11 依赖 `ps -o pgid=`**:非交互判据里实测拿得到,但**交互 shell 里 `setsid ... &`
  会 fork,`$!` 指的进程当场就退** —— 我写探针时真踩到过,两次实验都给了假结果。
  判据总是非交互跑的,fail-closed 也焊了(拿不到 pgid 就不开枪),不阻塞。
- **`run_leg` 回落窗口有个微秒级信息缺口**(subdeepseek F6):控制器若死在
  "底座腿失败、`.agent.state` 已挪好、聊天腿还没起"之间,花名册只印"未收尾",
  不提底座腿其实跑过。数据在盘上可查,极窄窗口。
- **`date` 格式与 R4 的 `strip_ts` 隐式耦合**(submimo F-2):改花名册抬头格式会让
  R4 假红而不是报出真问题。当前贪婪匹配不会断,记账不修。
- **my-review 闸在"审 aiwork 自己"时无解**:约定路径是 `<tool-root>/tasks/<name>-my-review.md`,
  而被审的仓就是 aiwork ⇒ 约定路径**必然**落在仓内 ⇒ 闸拒绝派发
  (它给的建议路径正是它拒绝的那个,提示自相矛盾)。本轮用 `--require-my-review`
  指到 `/root/panel-my-reviews/` 绕过,仓内保留正本。**这是工具的真限制,值得单开一单。**
  顺带:它拒绝时 `rc=1`(fail-closed 正确)—— 我一开始以为是 rc=0,那是 `| tail` 吃掉的,
  **管道吃 rc,本机第五次**。
