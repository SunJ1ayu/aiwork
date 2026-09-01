# Verify: mimo-key-single-source

- Date: 2026-09-01

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`;这里保留检查、理由、发现与主 Agent 仲裁说明,不复制枚举。

## Mechanical checks

- [x] build passes(纯 shell/python,无构建步骤;`bash -n` 过)
- [x] tests pass(判据 29/29、变异 19/19、仓外原子写检查 13/13,外加整套周跑 22 个套件全绿)
- [x] no secrets / unsafe ops(工件里没有任何字面 key;见下面"删过一份收据"那条)

**机器打印的**(不是我的转述):

最终**四**份(都跑在最后一次代码提交 `276ebf7` 之后,四份全 `source-stable: yes`):
```
runlog: final-oracle rc=0 commit=276ebf7 dirty=yes final=yes at=2026-09-01T04:37:57Z file=tracks/mimo-key-single-source/evidence/20260901T043757Z-01-final-oracle.txt
runlog: final-mutation rc=0 commit=276ebf7 dirty=yes final=yes at=2026-09-01T04:38:12Z file=tracks/mimo-key-single-source/evidence/20260901T043812Z-01-final-mutation.txt
runlog: final-switch-model-atomic rc=0 commit=276ebf7 dirty=yes final=yes at=2026-09-01T04:38:28Z file=tracks/mimo-key-single-source/evidence/20260901T043828Z-01-final-switch-model-atomic.txt
runlog: final-full-weekly-suite rc=0 commit=276ebf7 dirty=yes final=yes at=2026-09-01T04:38:44Z file=tracks/mimo-key-single-source/evidence/20260901T043844Z-01-final-full-weekly-suite.txt
```
`dirty=yes` 是因为收据自己会往 evidence/ 落文件 —— 这是这条管道的固有性质;
判"这遍算不算数"看的是 `source-stable`,四份都是 `yes`。

第四份是**整套周跑**(22 个套件),`switch-model-atomic: total: 13 passed, 0 failed` 在列
—— 它证明的不是"这道闸绿",而是**这道闸从此会被每周叫起来**,见下面发现 H。

⚠️ **断线那一刻的三份最终收据(`…T0355xx`)已作废,但留在 evidence/ 里没删**:
它们跑在 `5b32c32` 上,而第四轮又动了 `tests/` 与 `bin/rust-check-review-tooling`。
留着是为了让"这里重跑过一遍、为什么重跑"看得见 —— 作废 = 不许当绿用,不是不许留。

**跑红的那几遍,一份不藏**(判据先行 + 红检 + 对照组):
```
runlog: redcheck-oracle-before-impl rc=1 commit=b5de25f dirty=yes at=2026-09-01T02:35:52Z file=tracks/mimo-key-single-source/evidence/20260901T023552Z-01-redcheck-oracle-before-impl.txt
runlog: redcheck-new-assertions-before-io rc=1 commit=be0683c dirty=yes at=2026-09-01T03:29:40Z file=tracks/mimo-key-single-source/evidence/20260901T032940Z-01-redcheck-new-assertions-before-io.txt
runlog: redcheck-mutations-before-io rc=1 commit=be0683c dirty=yes at=2026-09-01T03:29:44Z file=tracks/mimo-key-single-source/evidence/20260901T032944Z-01-redcheck-mutations-before-io.txt
runlog: mutation-after-io rc=1 commit=5d9de92 dirty=yes at=2026-09-01T03:32:38Z file=tracks/mimo-key-single-source/evidence/20260901T033238Z-02-mutation-after-io.txt
runlog: redcheck-switch-model-control-old-version rc=1 commit=e8ef431 dirty=yes at=2026-09-01T03:52:42Z file=tracks/mimo-key-single-source/evidence/20260901T035242Z-01-redcheck-switch-model-control-old-version.txt
runlog: redcheck-switch-model-control-old-version rc=1 commit=e8ef431 dirty=yes at=2026-09-01T03:53:01Z file=tracks/mimo-key-single-source/evidence/20260901T035301Z-01-redcheck-switch-model-control-old-version.txt
runlog: redcheck-orphan-guard-unregistered rc=1 commit=5b32c32 dirty=yes at=2026-09-01T04:29:12Z file=tracks/mimo-key-single-source/evidence/20260901T042912Z-01-redcheck-orphan-guard-unregistered.txt
runlog: orphan-guard-registered rc=0 commit=5b32c32 dirty=yes at=2026-09-01T04:29:36Z file=tracks/mimo-key-single-source/evidence/20260901T042936Z-01-orphan-guard-registered.txt
runlog: full-suite-with-new-entry rc=1 commit=5b32c32 dirty=yes at=2026-09-01T04:30:06Z file=tracks/mimo-key-single-source/evidence/20260901T043006Z-01-full-suite-with-new-entry.txt
```
逐份说它红在哪(别只贴好看的):
- `redcheck-oracle-before-impl` 1 红 —— 清单文件还不存在,判据在第一条就硬退。
  **这条红得很浅**(0 passed / 1 failed),它只证明"清单缺席会红",证明不了别的断言咬得动;
  真正的红检是下面那几条变异。
- `redcheck-new-assertions-before-io` 25/1 —— 新断言 ⑦(写/恢复原语要单独成文件)此刻红。
- `redcheck-mutations-before-io` 13/3 —— m0/m6 两条**对照组**被 ⑦ 拖红、m15 红错地方。
- `mutation-after-io` 15/1 —— m15 "红了但红错地方":我第一版只删了 bash 那道守卫,
  而原语有两道(python 里还有一道)。**不是断言咬不动,是我的变异只拆了一半防线。**
- 两份 `redcheck-switch-model-control-old-version` **各 9 绿 4 红**(同一件事跑了两遍:
  第一遍靶子在会话 scratchpad 里,第二遍换成仓内 `fixtures/switch-model.sh.pre-atomic`
  —— 靶子放仓外的话,下次就复现不出来了)。这是全单最有说服力的一份:拿**修复之前**
  那一版 `switch-model.sh` 跑新检查,①②③④(内容对不对、fail-closed、不留临时文件)
  **全绿**,只有新加的 ⑤⑥ 四条红,其中一条就是
  「**盘上被写成了带占位符的样子**」—— kimi 说的那个洞被当场复现了。
- `redcheck-orphan-guard-unregistered` **rc=1** —— 第四轮:把那道闸只搬进 `tests/` 不登记,
  覆盖报告当场红在「有判据套件不在 SUITES 里(写了没人跑 = 从此静默腐烂)」。登记后转绿。
- `full-suite-with-new-entry` **rc=1** —— **这一条最值钱**:覆盖报告已经绿了,我要是停在那儿
  就会写下一句"接好了"。真跑整套周跑才红出来 —— `no-egress` 判据点名 N3a/N3c,
  说这个套件**带着网跑起来的**。也就是说这道闸住在 track 目录里的那段时间(含它自己那几份
  绿收据),**一直是带外网出口在判卷的**,因为那时没有任何东西要求它满足判卷面的规矩。
  补上守卫引入行后:no-egress 18/0、闸自身隔离下 13/13、对照组仍 9 绿 4 红(没被搬成恒真)。
  ⇒ **「登记了」不等于「跑得起来」,和「接线测试证明不了接上了」是同一条老账。**

其余过程收据(oracle-after-impl 22/0、mutation-check 11/0、oracle-after-io 27/0、
github-watch-ai-smoke rc=0、switch-model-atomic-check **9/0**)都在 evidence/ 里。
(⚠️ 断线接手时自查出来的:这一行原先把那份过程收据写成 `13/0` —— **13 是最终那份**,
 过程那份跑在 ⑤⑥ 四条断言补进来之前,机器写的是 `9 passed, 0 failed`。数字是我抄串的,
 而串的方向正好是把覆盖面说大。)

**删过一份收据,这里认账**:`20260901T033530Z-01-github-watch-ai-smoke.txt` 把 key 的
前 6 位印进了工件(要进 git)。改成只印长度后原样重跑(`…T033549Z`,rc 与结论完全相同),
删的是前一份。它的 observation(`…T033533Z-runlog-…json`)**故意留着** ——
留着才看得出"这里跑过一遍、收据被我拿掉了"。

## Review

- **规格自查(在读任何 panel 输出之前答的,正本见 `tasks/mimo-key-single-source-review-my-review.md`)**:
  规格本身可能错在三处,而 panel 验不了这一层(它只验"实现合不合规格",规格是我写的)——
  ① **判据治的是"漂",不治"绕过工具改"**:手改源头再手改 4 处副本,29 条全绿;
  ② **全绿 ≠ key 能用**:判卷面不许有外网出口,所以"全机统一一把**死** key"是绿的,
     有效性只在 rotate 的那一瞬间验过 —— 本单标题里"9 处漏 3 处"的痛点只解决了一半:
     **漏改会红,换错不会**;
  ③ **工具存在 ≠ 工具被用**:没有任何机制让"下次手工换 key"变难或变红。
  三条都进了 Accepted deviations,不是被发现的漏,是被选择的边界。

- **腿的花名册**(第二轮,`.roster` 原样粘):
```
submimo=SKIP(rotation) subdeepseek=SKIP(rotation) subglm=SKIP(rotation) subkimi=PASS(verdict=PASS) subgemini=PASS(verdict=PASS)
```
  第一轮(被断线砍掉那一轮)控制器没活到收尾,花名册是事后用 `panel-roster` 从盘上重建的:
```
submimo=SKIP(rotation) subdeepseek=SKIP(rotation) subglm=未收尾(无 state:被砍或仍在跑) subkimi=未收尾(无 state:被砍或仍在跑) subgemini=SKIP(rotation)
```
  🔴 **第一轮零个 coverage-eligible 腿,一份预算都没花到**:subglm 的 result.json 写着
  `verdict=UNKNOWN failure_kind=auth`,而日志里根本不是 auth —— 它是被沙箱
  `auto-rejecting` 挡在 `Read /root/.claude/switch-model.sh` 外面、又被一条 120s 的
  全盘 grep 拖超时,最后没出裁决。**那个 `failure_kind` 是假话**;好在它 rc≠0,
  不管归成哪一类都进不了预算。subkimi 的 `.err` 只有一行 `Terminated`,就是断线的剪刀。
  high 的 2 份预算是**第二轮**由 subkimi(moonshot)+ subgemini(google)两个家族满足的,
  两条都 `verdict=PASS`、`evidence.completeness=complete`、`degraded=false`。

- **findings**(逐条给依据,不抄结论):

  *主 agent 自审抓到、腿没提的(它们的沉默不是放行,这几条依然成立并已修)*
  - **A ⑥ 的 `rc -ne 0` 近似恒真** —— 已核 `tests/…:⑥` 段:任何原因的非零都会被记成
    "它拒绝了坏 key"(清单读不到=64、语法错、空壳 `exit 1`)。改成钉 `rc=2` **且**
    输出里说得出"形状不对"。变异 m12 证明老断言在那种情况下是绿的。
  - **B ⑤ 扫描面缩水静默** —— 已核:`[[ -e "$d" ]] &&` 逐项丢弃,只有全空才红。补
    `scan_missing` 断言,m11 钉住。
  - **C ④ 只查 `LLM_API_KEY=`,cron 库又不在⑤扫描面里** —— 已核:第 10 处正是在这个
    sqlite 里发现的。补 ④b 查字面 key,m13 钉住。
  - **D `rollback()` 自己是 truncate-then-write** —— 已核 `bin/rotate-mimo-key` 旧版
    `printf | base64 -d > "$f"`,而同文件 105 行的注释正禁止这种写法。拆出
    `bin/_mimo-key-io.sh` 走同一套原子写,并补"空快照拒绝恢复"(m15)。
  - **E key 走 argv** —— 已核:`/proc/<pid>/cmdline` 全局可读、`environ` 只有属主可读。
    写值改走环境变量,curl 的 Authorization 改走 `-K -` 的 stdin 配置。
  - **F 判据手抄了第二份取值路径** —— 保留手抄(判据不该依赖被测实现的 helper),
    但把它钉在清单上(m14),漂了红在它自己身上。
  - **G 变异夹具的 `MUT` 写死了一个已死会话的 scratchpad id** —— 换 `mktemp -d`。

  *subkimi(moonshot)提的,逐条核过*
  - **F1 ②b 占位符绿 + switch-model.sh 非原子写(Medium)—— 成立,已修。**
    我不是照单收的:拿修复前那版跑对照组,**当场复现**「盘上被写成了带占位符的样子」
    (收据 `…T035301Z`)。刺眼的是**我这一轮刚把 rotate 的同一个毛病修成原子写,
    而 switch-model.sh 里那份原样留着,我还通读过那个文件** —— 一条管道修了一头。
  - **F2 端点字段没人守(Medium-low)—— 成立,已修。** 已核 `watch.py:37-51`:
    回落只在 `api_key` 为空时发生,`api_base`/`model` 缺席就静默用 OpenAI 默认值。
    补清单 `MIMO_KEY_ENDPOINT_FIELDS` + 判据 ④c(非空 + "带小米 key 却指向 OpenAI"),
    m17/m18 钉住。**这条和本单起因是同一个形状:key 是对的,只是被送错了地方。**
  - **F3 缺目录 fsync(Low)—— 成立,已修**(`os.replace` 原子,但目录项要 fsync 才耐掉电)。
  - **F4 `grep -I` 跳过二进制(Low)—— 成立,不修**,理由见 Accepted deviations。
  - **F5 `select *` 扫全列、措辞却说"提示词里"(Low)—— 成立,改的是措辞。**
    已核 `cron_jobs` 有 70+ 列(含 `last_error`/`job_json`),命中历史列时旧措辞会指错方向。
  - **F6 网关等待环软失败(Low)—— 成立,已修**:15 次全败照样往下走,等于把
    "运行中的目标没回话"降级成一行日志,而这单的规矩正相反。
  - **F7 隔离树刷新静默吞失败(Low)—— 成立,已修**(失败会点名)。
  - **F8 verify/tasks 还是空模板、m15 修正后没有绿收据(Info)—— 成立**,本文件与
    `final-mutation` 收据即是补上。
  - kimi 还独立复核了三件我声称过的事并**证实**:`submimo-iso` 确实每次从 canonical
    home re-seed(源头选型的承重前提)、`sed` 注入面不成立、`--stdin` 与位置参数
    汇合到同一个形状校验。这些不是新发现,但它把我的"推断"变成了"核过"。
  - **驳回 0 条。** kimi 这一轮没有我认为不成立的条目。

  *subgemini(google)提的*
  - 十问全部判 PASS、未给独立缺陷。唯一实质建议(第 5 问:给 `api_base`/`model` 加断言)
    与 kimi F2 **独立同指一处** —— 两个家族独立命中同一点,通常是真的;已修。
  - ⚠️ 这份报告的信息量明显低于 kimi 那份(逐条肯定、无反例)。我没有因为"两票 PASS"
    就降低标准:上面 A~G 七条是我自己审出来的,腿一条都没提;F1 那条更是**在两票 PASS
    的报告里**藏着的 Medium。

  *从第一轮那条被砍的腿的 94KB 半截日志里捞出来的(不当预算,只当线索)*
  - `refs/nodepath-fix-20260728-143246/switch-model.sh` 里躺着一把**旧 key**。
    我自己核过:和当前源头**不是同一把**(哈希不同),是 07-28 的历史备份,且 `refs/`
    不在扫描面里(刻意)。**死 key,不修**,记进 Accepted deviations。
  - `bin/rotate-mimo-key` 不在 `_tooling-paths.sh` 的判卷面名单里 ⇒ 每周总跑的"漏网报告"
    会永远列它一次。**这是按设计工作**:那份名单的注释白纸黑字写着"硬堵会把运维脚本
    也拖进来 ⇒ 误报",而 rotate 正是运维脚本。kimi 顺带点出的隐忧成立——**一条常驻的
    已知条目会把报告训练成噪音**——但那是 `rust-check-review-tooling` 的事,不在本单收口,
    记 backlog。

  *断线接手复核时我自己抓到的(09-01 下午,第四轮;两条腿都没看过这一轮)*
  - **H 这一单交付的那道闸,归档后没人叫得动。** `switch-model-atomic-check.sh` 住在
    track 目录里,**全仓没有第二处引用** —— 它守的正是本单 F1 的修复(仓外
    `~/.claude/switch-model.sh` 的原子写),归档即失效。讽刺的是
    `bin/rust-check-review-tooling` 开头第 10 行的注释骂的就是这种孤儿脚本,
    而我一整天都在改这个文件旁边的东西、没往这儿看一眼。
    修法:`git mv` 进 `tests/test-switch-model-atomic.sh` + 登记进 SUITES;
    配套靶子 `fixtures/switch-model.sh.pre-atomic` 跟着搬进 `tests/fixtures/`,
    让"闸"和"证明闸咬得动的靶子"待在一起。
    ⚠️ 代价说清楚:早先几份收据的 `cmd:` 仍写着旧路径,那是历史记录、照着跑不动了;
    **当前路径以最终收据为准**。
  - **H2 它一直带着网在判卷**(接上去才被 `no-egress` 抓到,见上面那份 rc=1 的收据)。
    这不是我搬家搬坏的,是**它从来就没被要求过** —— 判卷面的规矩只对住在 `tests/` 的
    套件生效,而它住在 track 目录里。**同一个形状:防线只守它看得见的那扇门。**
  - 顺带核了断线前打的那些勾,**有一处我写得比事实好看**:过程收据
    `switch-model-atomic-check` 是 `9/0`,被我写成了 `13/0`(13 是最终那份)。已改正留痕。

- **arbitrated verdict(主裁):PASS。**
  理由:① **四份**最终收据都跑在最后一次代码提交 `276ebf7` 之后,29/19/13 全绿,
  外加整套周跑 22 个套件全绿;② 19 条变异证明判据
  咬得动,含 2 条对照组不误报;③ 这一单最硬的一份证据不是任何一个"绿",而是那份
  **对照组**——拿修复前的 `switch-model.sh` 跑,新检查的 ⑤⑥ 四红、老角度的 ①②③④ 全绿,
  说明这次收紧确实看见了以前看不见的东西;④ high 的 2 份外部预算由两个不同模型家族的
  eligible PASS 腿满足,且我对每一条发现都自己复现过、没有一条是照单收的;
  ⑤ **交付面在使用现场验过**:GitHub-Watch 的 AI 摘要用 `env -i` 模拟 cron 环境跑通,
  拿到真的中文摘要(收据 `…T033549Z`)——那是本单顺手声称"修好了"的东西,
  在此之前只有机制推演。
  ⑥ 第四轮把这一单交付的那道闸从孤儿脚本接进了常设判据面,**红检两次、且第二次
  推翻了第一次的结论**(覆盖报告绿 ≠ 真跑得起来)。
  **仍然要说清 PASS 的边界**,三条:
  (a) 它证明的是"合乎规格",而规格自查那三条(不治绕过、不验有效性、不保证工具被用)
      是我自己写下的洞,过审不等于它们消失了;
  (b) 🔴 **两条外部腿看的是 `5369e0e`,第三轮的实现(`51354f1`)和第四轮的接线
      (`276ebf7`)它们都没看过。** 第三轮改的正是它们提的那两条(F1/F2),
      属于"照着腿的意见改"而不是"新开了面";第四轮动的是判卷面的接线,
      **按本机规矩这本该更谨慎**,我判它够不上再花一轮预算的理由是:
      没有新写口、改动全部由机器判据双向红检过(不登记会红、带网会红)。
      **这是我的判断,不是腿的背书** —— 而且归档闸**查不出**这件事:
      panel observation 里 `subject` 是 `null`,评审冻结的那棵树从来没跟归档的树比过
      (这是已知的结构缺口,不是本单造成的);
  (c) 那道闸此前一直带外网出口在判卷(H2),**它自己那几份绿收据是在没有断网的
      情况下拿到的**。结论不受影响(它一次外呼都没有,内容只读本地文件),
      但"在合规判卷面上拿到的绿"这句话,严格说只有第四轮之后的那份当得起。

## Accepted deviations

- **不治"绕过工具手改"。** 判据比的是副本与源头一致,手改源头+手改副本可以全绿。
  单人机,且 rotate 是唯一被文档化的入口;真要堵得给凭证文件上写锁,代价大于收益。
- **判卷面不验 key 有效性。** 判卷面不许有外网出口(track no-egress-judging),
  所以"全机一把死 key"是绿的。有效性由 rotate 在换的当下验(HTTP 200 才动文件)。
- **扫描面与排除项是手列的。** ⑤ 只扫 11 处活配置面;历史备份/日志/会话记录里有旧 key
  是正常的,扫进来等于把报警器调成噪音。代价:副本落在扫描面之外则一声不吭
  (现在至少"清单里列了、盘上没有"会响 —— 那是 m11)。
- **`grep -I` 跳过二进制**(kimi F4)。扫描面里的二进制(`.pyc`、别的 sqlite)看不见字面 key。
  唯一真正要紧的那个二进制——cron 库——由 ④/④b 单独查。其余扫进来噪音大于收益。
- **`refs/` 里那把 07-28 的旧 key 不清理。** 已核实是死 key(与当前源头哈希不同),
  且 refs/ 是历史备份目录。清理它等于开始清理历史,而历史里的死 key 是证据不是风险。
- **冒烟任务名 `gmail-check-30m` 仍写死**(可用 `MIMO_KEY_SMOKE_JOB` 覆盖)。
  现在至少"任务不存在"和"任务跑红了"会说成两句话。
- **`MIMO_KEY_CRON_DB` / `MIMO_KEY_SCAN_TIMEOUT` 是判据上的 env 旋钮**,变异测试需要它们。
  `SCAN_TIMEOUT` 是 fail-closed(调小只会更红);`CRON_DB` 指向别处能让 ④/④b 空转 ——
  这是一个真实存在的零痕迹旁路面,记在这里而不是假装没有。
- **`bin/rotate-mimo-key` 不进 `_tooling-paths.sh`**(它是运维脚本,那份名单刻意不收运维脚本)。
  代价是每周"漏网报告"会永远列它一次;"常驻已知条目会把报告训练成噪音"这个隐忧
  记 backlog,归 `rust-check-review-tooling` 收口。

- **评审腿的 `failure_kind` 会撒谎 —— 记 backlog,不在本单修。**
  第一轮 subglm 的 result.json 写着 `failure_kind=auth`,真因是沙箱 auto-reject + 120s 超时。
  根因**量出来了、不是推的**:`bin/_review_result.py` 在自家诊断为空时回落到腿的**正文**,
  而 `AUTH_FAILURE_RE = unauthori[sz]ed|forbidden|invalid.{0,20}key|\bauth\b|\b401\b|\b403\b`
  在那份日志里命中 6 次 —— 命中的是**文件名 `auth.json` 里的 `auth`**(`.` 是非词字符,
  `\bauth\b` 照样匹配)和腿自己报告里讨论的 `401`。
  同一形状 08-28 记过一次(那次的修法就是"先只读自己的诊断"),**这次从回落路径原样复发**,
  而且本单的主题恰好就是 auth 与 401 —— 主题词撞上分类词,是最容易复发的那类。
  危害:把"腿被沙箱挡住/超时"报成"凭证坏了",会把下一个人引去查错的方向
  (本机为这个形状浪费过一整天)。**归 `_review_result.py`,要单独开单**:
  动的是判卷防线,得有自己的判据和红检,不能在这一单顺手改。
