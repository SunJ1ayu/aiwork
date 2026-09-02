# 工作流欠账(攒着,择期一起改;别在干活中途顺手改流程)

> 业主 2026-08-19 拍的:「工作流还是不够完善,等你做完这些我们再优化一下工作流吧」。
> 这份文件的存在理由:**跳出干活循环的动作最容易被丢掉**(本机记录在案的老毛病)。
> 观察写在这儿,不写进任何 skill/CLAUDE.md —— 那是优化那一轮的事。

## 来源:track `deepseek-leg-bash-hole`(08-18~08-19)

这一单方向错了一天半:我在"关掉评审腿的 bash、再自己算 diff 喂给它"这条路上做了
预算/截断/通道/工件排除一整套,而根本问题是**评审腿有什么动机改判据**——
它的产出是意见,没人拿判据绿不绿衡量它。推翻这个前提的是业主,不是四条评审腿。

### D1 —— 「规划双出」没有机械触发器,和自述型字段一个毛病

design 模板里那格写着触发条件"lane=full 的同一批面",这一单 verify 我自己填的就是
full,**而那一格从开单到收口一直是空模板,没有任何东西拦我**。
track-guard 现在查 lane/派给非空,唯独不查它。
形状和 [[self-narrated-fields-dont-guard]] 记的完全一样:自由填空 = 挡不住惯性。
候选修法(**未拍板**):track-guard 加一条 —— lane=full 且 design 那格为空/无日志路径
⇒ 拒绝 commit。

### D2 —— 没有任何工件逼我问「这个对手有什么动机」

proposal 我写的是"腿能写 tests/ ⇒ 能动判据",一句话立住了威胁模型,
**而整条工件链里没有一格问"它为什么要动"**。本机那条硬规矩(弱模型会改考卷让自己
及格)说的是**执行腿**(有动机),我把它套到了**评审腿**(没动机)身上,没人拦。
候选修法(**未拍板**):proposal 模板加一格「对手是谁 / 它的动机是什么 / 它不干这事的
成本是多少」,答不上来就不算立住。

### D3 —— 四审很强,但它站在成本花掉之后(老账,又实证一次)

subkimi 这轮确实抓到了最大的洞(submimo 被我误分类),但那是**一天半之后**。
四条腿都在我的框子里挑毛病,没有一条说过"这个方向本身错了"。
和 [[guards-must-watch-the-right-door]] 记的"有能力的检查站在成本花掉之后"同一个形状。
候选修法(**未拍板**):开单时(proposal 落盘后、动手前)先跑一次**只问前提**的
panel-explore —— 不评审实现,只问"这个问题该不该这么解"。

## 规矩(给优化那一轮的自己)

按 CLAUDE.md 的准入线,上面三条都还只是**建议**,不是硬规矩:
刹车类要"真出过事 + git 一眼可查";D1/D2/D3 都真出过事,但修法都还没验证过副作用。
**别一次全上**;而且总量不许只进不出,上新的要说清替下哪条。

## 来源:track `opendesign-shell-reselect`(08-25,一轮 panel-explore)

### D4 —— `panel-roster` 对 explore 轮次会说假话

这轮四条腿全部 rc=0、日志完好,而 `panel-roster <前缀>` 印的是:

```
🔴 panel-roster: 没有 <前缀>.plan —— 这一轮连派发都没走到,无从重建。
```

真相:`.plan` / `.state` 是 **`panel-review`** 的机制,`panel-explore` 根本不写它们。
所以这句话不是"不知道",是**对着一个它管不着的轮次断言了一件没发生的事** ——
和「误报和假绿一样坏」同族,而且它伪装成的正是 08-23 那一单刚立起来的那道
"零记录也说得出话"的防线。
候选修法(**未拍板**):① `panel-roster` 认出 explore 前缀就改口说"这一轮是 explore,
本工具不适用",不许说"连派发都没走到";或 ② 让 `panel-explore` 也写 `.plan`/`.state`,
花名册对两种轮次一视同仁。②更彻底但要动派发路径。

### D3 今天头一次真跑了(不是新账,是给老账记一笔证据)

D3 的候选修法是「开单时先跑一次只问前提的 panel-explore」。今天这一单**正好是这个形状**
(还没有 diff、先问"这个问题该不该这么解"),结果:**4/4 腿一致判定我把"选型"当成了
"验证问题"的解法**,而我自己派发前落盘的自述里第 3 条写的就是同一件事 ——
我写下了它,然后仍然给出了与它矛盾的推荐。
⇒ 这条证据支持 D3 的修法**有用**,但也暴露它的边界:**发散能把前提问出来,
挡不住我明明写下了却不照做**。真要机械化,该管的是"自述里写下的疑虑有没有被回答",
不是再加一轮发散。

## 来源:track `panel-kimi-credential-wipe`(08-25,已归档 `e0ee8ac`)

> ⚠️ **先记一条元账**:这一单的敞账我原本只写进了**归档后的 `verify.md`** 和记忆,
> **没写进这个文件** —— 而这个文件的存在理由就是"跳出干活循环的动作最容易被丢掉"。
> 归档区的 verify.md 没人会主动翻。是业主一句「这些有记载 aiwork 待办里吧」问出来的。
> ⇒ **收口清单里缺一步:敞账要落到 WORKFLOW-DEBT.md,不是落在归档件里。**

### D5 —— 冷却 6h 对「腿坏了」和「腿干完活只是格式没对上」一视同仁

`bin/panel-review` 的 `cooldown_health()`:`case "$status" in PASS|healthy) return 1`
⇒ **除 PASS 外全部冷却 `PANEL_HEALTH_COOLDOWN_SEC`(默认 21600s = 6 小时)**。
而 08-24 刚上的 dead-streak 机制**特意区分了** rc≠0 与 `INCOMPLETE`/`DEGRADED`,
理由就写在代码注释里:*"把它们算进来,就会把正在干活的腿踢掉"*。
**同一个道理,冷却这一侧漏了 ⇒ 08-24 那一单只修了一半。**
本单实证:第一轮 `impact-risk=high` 要 2 个家族,**只派出 1 条**
(submimo `cooldown:INCOMPLETE` / subglm `cooldown:DEGRADED` 双双被关在门外),
只能靠 `PANEL_HEALTH_OVERRIDE` 手动放回才凑够。
另:`21600` 这个默认值查了引入它的那一单(`workflow-control-plane`),**工件里一个字都没提**,
是随手定的。
候选修法(**未拍板**):软失败(rc=0 但裁决行没匹配)用短得多的冷却、或干脆不冷却。

### D6 —— 机制记得"它坏了",却没有办法知道"它被修好了"

subkimi 的根因今晚修掉、业主重新登录、冒烟通过(读得到仓库、答得出问题、`Conclusion: PASS`),
而 `health.tsv` 里它仍是 `FAIL … 冷却到 22:28`。**腿好了,健康池不知道。**
出路只有两条:等冷却自然过期,或派发时手动带 `PANEL_HEALTH_OVERRIDE=<leg>=healthy`。
与 D5 同族,但**不是同一件事**:D5 是"分类太粗",D6 是"没有回写通道"。
候选修法(**未拍板**):给 `subkimi`/`subglm` 等加一个 `--smoke` 子命令,成功即写回 healthy;
或让任何一次成功的直调也记 health(现在只有 `panel-review` 派发才记)。

### D7 —— 判据只进不出(**这条是业主当场问出来的,也是这几条里最大的一条**)

量出来的:主判据文件 `tests/test-review-tooling.sh` 建仓日(07-27)**969 行 → 08-25 4532 行**,
一个月 **4.7 倍**;`tests/` 22 个文件共 **11090 行**;`bin/` 35 个工具。
CLAUDE.md 对**硬规矩**写着"总量不许只进不出"且真退过场(08-08 退过一轮),
**而判据 V1..V45 一条没退过,没有任何退场机制**。
今天的代价可数:全量跑一遍 ~3 分钟 × 本单 8 遍;
**且有整整一轮是在修 V45 自己的毛病**(看不见 link-to-dir / 误报面太大 /
把凭证指纹打进要入库的收据)—— **判据成了需要被判据保护的东西**。
同一个病也长在记忆索引上:`MEMORY.md` 47.8KB(限 24.4KB),**超出的部分下次会话根本读不到**,
今天只压到 42.8KB,是止血不是治。
候选修法(**未拍板**):单独开一单,先**量**——V1..V45 逐条问"它防的 bug 在当前代码里
还可能复发吗"(那段代码是否已被重写/删除),**先量再删,不凭感觉砍**;
删一条要留会说话的墓碑(本机记过账:删掉别人还指着的入口要留墓碑)。

### D8 —— 判据夹具测的不是受测版本

`v40_second_panel_findings` 的 `$b` 没拷 `_review-workspace.sh`(V36 在同文件里拷了)
⇒ subkimi 落到 `bin/subkimi:183` 的硬编码回退 `/root/aiwork/bin/_review-workspace.sh`
⇒ **在业主机上测的是活仓那份,不是夹具里那份受测版本**(subglm 用 `bash -x` 实证)。
正是这个文件自己在别处警告过的"写死绝对路径"坑。
候选修法(**未拍板**):夹具补一行 `cp`;或让 `bin/subkimi` 的回退在找不到时**拒跑**而不是
静默去用绝对路径那份。

### D9 —— 判据里几处潜伏的"通向真实环境"(本单已修主干,这些是剩下的)

- `kimi-review-home/hooks/probe.sh` 硬编码往**仓里**写 `logs/probe.jsonl`;当前
  `config.toml` 只挂 `guard.mjs`,没有任何东西执行它 = 死文件,但形状与本单根因同族。
- `V27①` 跑真 `subglm-agent` 未隔离 `HOME`,现在只因 `AUTH_ENV=""` 在写配置**之前**就 die
  才没落地 —— **是运气不是设计**;V45 也不盯 opencode home。
- `V45` 靠"排在调用列表最后"的约定保证覆盖(新增 v46 追加在它后面就会缩小覆盖)。
  **不改成 `trap EXIT` 是刻意的**:trap 在汇总行和 `[[ $FAIL -eq 0 ]]` 之后才响,
  那才是真的"闸说了话但不改判"。接受为已知限制,记在这儿以免下个人以为是漏的。

## 来源:track `opendesign-slow-lock-scan` 第三轮(09-02,断线接手那一趟)

### D4 —— `panel-roster` 把**被砍的腿**印成"压根没派"

第二轮 `panel-slowlock-r2`:subkimi 盘上有 `facts.json`、86KB 的 `.log`、
`.log.err` 内容是 `Terminated` —— 它真跑了七分钟,是断线砍的。
但它没写 `.state`,而 `panel-roster` 判"派没派"看的就是 `.state` 在不在 ⇒ 它印出
`subkimi=SKIP(rotation)`。抬头那几行**确实**写了 `escalation=unknown(控制器没活到收尾)`
和"不含升级追加的腿",可**每条腿那一行照样给断言**。
两句话打架时下面那句更响 —— 这就是记忆里 [[panel-dead-leg-streak-track]] 那条
"机器打印的一句话,和这句话是真的,是两件事"的第三个实例。
本单的处置是**在 verify.md 里当场把这行标成假的**(工件层面补救),工具没改。
候选修法(**未拍板**):`.log`/`.log.err` 存在但 `.state` 缺失 ⇒ 印
`KILLED?(有日志无 state)` 而不是 `SKIP(rotation)`;要有判据 + 对照组
(对照组必须钉死"真的没派"仍然印 SKIP,别把两种状态糊成一种)。

**2026-09-02 第三轮:同一笔账的第二个实例,而且这次信息就在盘上没人读。**
`panel-slowlock-r3` 的 `driver.log` 里白纸黑字写着 `escalation: degraded -> add subkimi`,
盘上有 `.subkimi.facts.json`/`.log`(15.7KB)/`.log.err`(`Terminated`)—— 它被派了、
跑了五分钟、被砍。`panel-roster` 仍然印 `subkimi=SKIP(rotation)`,
抬头仍然写"不含升级追加的腿"。
⇒ 上一条写的"盘上分辨不出它是不是升级追加的腿"**这次不成立**:
`driver.log` 的 escalation 行就是第二个独立信源,只是花名册不读它。
候选修法因此更便宜:除了"有日志无 state ⇒ `KILLED?`",还可以直接读 `driver.log`
的 escalation 行补进花名册,连带把抬头那句免责改成有条件的。

### D7 —— 🔴 **瞎审的腿照样 rc=0、照样给裁决,而裁决会进预算**

同一轮 subglm 回落聊天腿之后,`git diff` 是**空的**(工作树 == HEAD,而
`PANEL_DIFF_BASE` 默认不设),`PANEL_INCLUDE` 也没给 ⇒ 它拿到的是
**零个文件、零行 diff**。工具确实打了一行 `WARNING: ... will review BLIND`,
然后**照常跑完、rc=0、给出裁决**。这次它诚实地判了 `NEEDS_MORE_INFO`
(报告开头就写"本轮提供的上下文里没有任何可审的树状态"),
**但那是模型自己讲道德换来的,不是机制保证的**。

危险形状:同样这条路径上,一条瞎着的腿完全可以吐出 `PASS` —— 它没看见任何东西,
所以也没看见任何问题。而 `PASS` 是要**进 coverage 预算**的。
降级腿目前不算 eligible,挡住了这一次;但**主腿本身就是 chat 腿**的场合
(某些腿默认就是聊天档)没有这层保护:空 diff + 空 include + PASS = 白拿一格预算。
⇒ 这是**判卷防线的洞**,不是体验问题。

候选修法(**未拍板**):① chat 腿在"零 diff 且零 include"时**拒跑**(rc≠0),
让它显式失败而不是产出一份没有依据的裁决 —— fail-closed;
② 或者仍然跑,但把裁决**机械降级**成 `NO_CONTEXT`,永远不 eligible;
③ 顺带:`panel-review` 在检测到零上下文时应该自己去设 `PANEL_DIFF_BASE`
(至少回落到 `merge-base(默认分支, HEAD)`),而不是只打一行 WARNING 就往下走。
要判据 + 对照组(对照组钉死"真有 diff 的 chat 腿不受影响")。

### D5 —— 题面里写被审仓的**绝对路径**,会把底座腿从快照引到活仓

09-02 第三轮:subglm 的 agent 腿 rc=1、没给裁决,死因是它去
`cat /root/.openclaw/workspace/projects/design-studio/tracks/.../evidence/*.txt`
—— 那是**源仓**,不是它自己那份可写快照,撞上只读边界被 auto-reject,然后它就停了。
同一份日志里它还 `git log` 了源仓,**列出了派发之后我新提交的几笔** ⇒ 它审的是移动靶。
根因在我:任务书第一行就写着「仓库:`/root/.openclaw/...`」,等于请它去活仓。
(subdeepseek 同轮也去够过源仓,但它自己退回快照,所以只表现为浪费几个 turn。)
候选修法(**未拍板**):任务书模板里**不写源仓绝对路径**,改写"你的工作副本就在
`$PWD`,原仓不可达也不需要";或者派发时机械扫一遍任务书里有没有源仓路径,有就拒。

🔴 **09-02 第五轮:我自己又犯了一遍(见 D10)。** 我在写 D10 的一小时前才读过这一条,
然后在同一小时里派出的题面第一行照样是源仓绝对路径。**"记成债"没有拦住我第二次犯它**
—— 这就是这条债该从"候选修法"升级成"机械扫一遍任务书"的实证:
靠记得的规矩,连刚读过的人都挡不住。

### D6 —— 我在 panel 跑着的时候写了被审的仓

同一轮:腿 09:02 派出去,我 09:07/09:09/09:11 各提交了一笔(都是在办第二轮的发现)。
快照本来护得住,但 D5 那条一旦成立,腿看见的就是移动靶;而且事后**发现该归给哪一版**
也变模糊了(deepseek 的 MEDIUM 第 1 条报的正是我在它派出去之后自己改掉的那句话)。
`runlog --final` 有"跑的时候谁都不许写仓"的硬规矩,**panel 期间没有对应的一条**。
候选修法(**未拍板**):panel 跑着时对被审仓的写入至少要**响亮提示**;
或者约定"派完就别动树,有发现先攒着"。

### D8 —— 🔴 **控制器一死,整轮证据就作废 —— 哪怕腿的结论完整躺在盘上**

09-02 连着两轮实证(**代价是两轮外部评审白花**):

- 第三轮:断线在 09:14。三条腿是 `setsid` 出去的,**活过了断线**并各自跑完
  (subdeepseek 09:10、subglm 09:29、subkimi 09:34 被砍);控制器没活过,
  ⇒ 没写 compact observation。
- 第四轮:断线在 10:08。subkimi **10:08:17 rc=0、证据完整、判 PASS、跑了 803 秒**,
  `result.json` 好端端躺在 `/root/aiwork/logs/` 里;控制器同样没活过 ⇒ 同样没有 observation。

机器侧的后果不是"少一条记录",是**这一轮等于没发生**:`track-record` 的
`panel_review_coverage` 把 authoritative group 的 key 取成
`(result["run_id"], subject_digest)`,同 subject 跨 run 只作 `same_subject_shadow`
诊断、**不进预算** ⇒ 第三轮的 subdeepseek(PASS)和第四轮的 subkimi(PASS)
拼不起来,high 的 2 条预算一条都不算。**只能重跑第五轮。**

要命的地方在于**这条洞是静默的**:腿的日志、`result.json`、`.state` 全都在,
`panel-roster` 也能从盘上把花名册印出来 —— 屏幕上一切正常,唯独机器看不见。
(它和记忆里那条"observation 不能从盘上重建"是同一件事,但那条记的是限制,
 这里记的是**它已经吃掉两轮**。)

**这一轮的临时绕法(已用,有效)**:控制器自己 `setsid nohup` 出去,
派完当场 `ps -o sess` 核它 `sess` 是不是自己的号(实测 2142603/ppid=1,断线够不着)。
**绕法不是修法**:它靠我每次记得加,而"靠记得"正是这台机器不信的东西。

候选修法(**未拍板**,按我现在的偏好排序):
1. **panel-review 自己 `setsid` 重入** —— 控制器一启动就把自己挪进新会话,
   谁调它都杀不掉。最省事、且不需要任何人记得。
2. **observation 增量写** —— 每条腿收尾就更新一次,而不是全轮结束才写一次。
   这样"控制器中途死"最多丢掉还没跑完的腿,已经站住的腿不作废。
3. `panel-review --collect <prefix>`:事后从 `.plan` + 各腿 `.result.json` 补写。
   ⚠️ **这条要小心**:它等于允许"没有控制器活到收尾"的一轮照样进预算,
   而 observation 之所以由控制器写,就是因为它是"这一轮真的按预算派出去了"的
   唯一见证。真要做,必须在 observation 里机械标注 `reconstructed=true` 并
   **默认不 eligible**,否则是在给自己开一条把死轮洗成活轮的后门。

### D9 —— 每轮 panel 都会印一句"反锚定闸被跳过而自审不存在",而它是假的

`_my-review-gate.sh` 在 `--panel-dispatch` 分支里按**腿收到的那份任务文件名**
去推自审路径:`/root/aiwork/tasks/$(basename "${task%.*}")-my-review.md`。
但 panel-review 派发时给腿的是**它复制到 logs/ 的那份**
(`logs/panel-slowlock-r4-<ts>.task.md`),于是推出来的路径永远是
`/root/aiwork/tasks/panel-slowlock-r4-<ts>.task-my-review.md` —— **结构上不可能存在**。
所以每条腿的 `.err` 顶部都躺着一句"注意 —— 跳过了反锚定闸,而 XXX 并不存在",
而控制器那一层其实**照真名查过、也确实拦得住**(09-02 两轮自审都按约定名写在
`tasks/slow-lock-scan-r4-my-review.md`)。

这不是功能 bug,是**机器打印的一句假话**:接手的人(包括我自己)读 `.err` 时,
第一眼看到的是"反锚定没做" —— 而事实相反。同一条老账的又一个形态。
候选修法(**未拍板**):腿这一层拿到原始任务名(派发时多传一个变量),
或者干脆在 `--panel-dispatch` 分支里**只说"由控制器代查"**,不去推路径、不报不存在。

### D10 —— gemini 腿被沙箱拒读时**不说拒的是哪个路径**,于是不可诊断

09-02 第五轮:subgemini 起跑 20 秒就零产出退出(rc=1、verdict=UNKNOWN、
failure_kind=runtime),日志里只有一句:

> `jetski: no output produced — a tool required the "read_file" permission that
> headless mode cannot prompt for, so it was auto-denied.`

**它没说被拒的是哪个文件**。我去翻它自己的会话记录(`.gemini/antigravity-cli/`)
也没有落盘的工具调用参数 ⇒ 根因**当场钉不死**。它的 settings.json 是对的
(allow 里那条 `read_file(/tmp/aiwork-review-workspaces/subgemini.2lCZVkEa/repo)`
路径与本轮 workspace 逐字节一致),所以问题不在配置漂移,而在**它想读沙箱外的东西**。

🔴 **两条候选诱因都是我自己写进题面的**:
① 任务书第一行的源仓绝对路径 —— **这正是上面 D5 记着的那条账**,我一小时前刚读过它、
   刚写下"候选修法:题面里不写源仓绝对路径",然后**在同一小时里照原样又写了一遍**;
② 攻击点 4 我直接叫它"请自己读 `/root/aiwork/bin/track-record` 的
   `panel_review_coverage`" —— 那是**仓外文件**,任何只读沙箱腿都够不着。
②比①更硬:它百分之百在沙箱外,而且是我为了让腿核我的说法而特意加的。

⇒ 这条不只是 gemini 的工具账,更是**题面纪律**的账:
"我想让腿核的东西"和"腿够得着的东西"是两个集合,我写题时没做这个交集。
如果要腿核仓外的判据源码,得把那段源码**摘进题面**或复制进它的工作副本,不能给路径。

候选修法(**未拍板**):
1. 腿这一层把被拒的目标路径打进日志(能不能拿到取决于 jetski 的输出,可能要提工单);
2. `panel-review` 派发前**机械扫一遍任务书**:出现被审仓绝对路径、或 `/root/aiwork/`
   路径,就打一行响亮的警告(甚至拒发)—— 这一条同时收口 D5 和这里的 ②;
3. 题面模板里加一句"你的工作副本就在 $PWD;凡是要你核的仓外内容,都已摘录在下面"。

### D11 —— 🔴 **submimo 的 review 提示词没有裁决行契约,而机器只认那一行**

09-02 第五轮:submimo rc=0、报告完整(66 KB,逐条核树 + 六条重点攻 + 硬事实核查)、
结尾自己写着"**本轮 PASS**",而机器判 `verdict=UNKNOWN` / `failure_kind=no_verdict`
⇒ **整份报告不进预算**,这一轮 coverage-eligible 从 1 掉到 0。

根因不在模型:`bin/submimo` 的 review 档提示词(`MESSAGE`,agent 底座那支)只说
"Output the complete report now as plain text",**没有
`Conclusion: PASS | BLOCK | NEEDS_MORE_INFO` 这一行**;
`bin/subkimi`、`bin/subagent`、`bin/subgemini` 的对应提示词里**都有**。

量出来的相关(不是推的)—— 盘上全部 6 份 `*.submimo.result.json` 对着各自题面数:

| 题面里出现过 `Conclusion` | 份数 | verdict |
|---|---|---|
| 是 | 2 | PASS、PASS |
| 否 | 4 | UNKNOWN ×4 |

**6/6**。四份 UNKNOWN 里有两份就是 `opendesign-slow-lock-scan` 的第一轮和第五轮 ——
**同一条腿在同一单上白跑两次**,每次都花掉一轮 20 分钟的墙钟和一次外部额度。

要命的地方和 D8 同形:**屏幕上一切正常**。driver.log 印 `submimo rc=0`,
花名册印 `submimo=PASS(verdict=UNKNOWN)` —— 后半句是真话,但读起来像"通过了"。

候选修法(**未拍板**,按偏好排序):
1. **`bin/submimo` 的 review `MESSAGE` 补上契约行**,和另外三条腿对齐。最小、最直接;
   属判卷面改动 ⇒ 要挂 track、要跑 `tests/test-review-tooling.sh`。
2. 契约行不放在各腿各自的提示词里,而是 `panel-review` 派发前**统一追加到题面副本**——
   根治"新增一条腿又忘了写"这个形状,但改动面大。
3. `panel-review` 收尾时,对 `verdict=UNKNOWN` 且 `evidence.completeness=complete` 的腿
   **响亮打印一行**"这条腿交了完整报告但没给裁决行 ⇒ 不进预算",别让它混在 rc=0 里。
   (这条不修根因,只是让它不再静默 —— 但正是它静默才吃掉了两轮。)
