# Verify: no-egress-judging

- Date: 2026-08-10
- Verdict: PASS(主裁;三条腿两条各出一个真 BLOCK,均已修 + 变异测试)

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再跑 panel-review 的全部评审腿,主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes(bash -n / 全部套件可执行)
- [x] tests pass(总跑 8 套全绿:275/17/ALL/62/79/4/31/18)
- [x] no secrets / unsafe ops(无凭证改动;守卫只减网络能力,不加)

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t no-egress-judging -- <判据命令>
```

```
runlog: oracle-red rc=1 commit=d5ee9a1 dirty=yes at=2026-08-10T07:30:32Z file=tracks/no-egress-judging/evidence/20260810T073032Z-01-oracle-red.txt
runlog: oracle-red2 rc=1 commit=d5ee9a1 dirty=yes at=2026-08-10T07:34:34Z file=tracks/no-egress-judging/evidence/20260810T073434Z-01-oracle-red2.txt
runlog: oracle-red3 rc=1 commit=d5ee9a1 dirty=yes at=2026-08-10T07:36:40Z file=tracks/no-egress-judging/evidence/20260810T073640Z-01-oracle-red3.txt
```

**红检**(实现落地前判据必须红),三遍都留着、一遍没藏:

- `oracle-red` 10 红/7 绿 —— 跑完当场抓到我自己一条**假绿**:N4「拒跑时说清原因」
  的匹配词里有 `egress`,而 bash 的 "No such file" 报错会把守卫的**路径名**打出来 ⇒
  一句什么都没解释的报错也能"通过"。已删掉那个词。
- `oracle-red2` 11 红 —— 把 N3 从 `grep` 文本匹配(**一行注释就骗过去了**)换成
  N3a 可执行引入行 + **N3c 行为抽检**(假 `unshare` ⇒ 每个套件必须当场拒跑)。
  这个洞是在填「派给」那一格、想清楚"判卷文件和被改文件是同一批"时照出来的。
- `oracle-red3` 11 红 —— N3a 连**判据自己**都标红了(我写的是 `. "$GUARD"` 变量、
  不是字面路径)。改的是我自己那一行,**没有给自己开豁免**(豁免会腐烂)。
  全部 11 条红在断言上,没有一条炸在报错上。

**实现落地后**:

```
runlog: oracle-after-impl rc=1 commit=4af6f91 dirty=yes at=2026-08-10T07:42:38Z file=tracks/no-egress-judging/evidence/20260810T074238Z-01-oracle-after-impl.txt
runlog: oracle-green rc=0 commit=4af6f91 dirty=yes at=2026-08-10T07:48:15Z file=tracks/no-egress-judging/evidence/20260810T074815Z-01-oracle-green.txt
runlog: full-suite rc=0 commit=4af6f91 dirty=yes at=2026-08-10T07:49:09Z file=tracks/no-egress-judging/evidence/20260810T074909Z-01-full-suite.txt
runlog: full-suite-fast rc=0 commit=4af6f91 dirty=yes at=2026-08-10T08:08:50Z file=tracks/no-egress-judging/evidence/20260810T080850Z-01-full-suite-fast.txt
runlog: full-suite-final rc=0 commit=4b86efa dirty=yes at=2026-08-10T08:51:51Z file=tracks/no-egress-judging/evidence/20260810T085151Z-01-full-suite-final.txt
runlog: spend-reconcile rc=0 commit=4b86efa dirty=yes at=2026-08-10T08:55:54Z file=tracks/no-egress-judging/evidence/20260810T085554Z-01-spend-reconcile.txt
```

- `oracle-after-impl` 12/6 —— **判据抓到实现一个真 bug**:自举时 export 的
  「试过一次」标记被子进程继承,子进程回到主命名空间就被误判成"自举失败"而拒跑。
  N1/N2/N7 全红,而 N5 会因为**错误的原因**变绿。⇒ 隔离成功后 unset。
- `oracle-green` **18/0**。
- `full-suite` 总跑 8 套全绿,但**耗时 346s**,超过每周 cron 的 300s 超时
  ⇒ proposal 里「堵住之后自然变快」那条假设**被自己的测量证伪**(见 F6)。
- `full-suite-fast` 25s→5s 之后 **215s**,8 套全绿,重新落回超时以内。
- `full-suite-final` = **四审两条 BLOCK 修完之后**的那一遍,8 套全绿(no-egress 18/0)。
- `spend-reconcile` 是 subkimi 点出来的窟窿:「额度没掉」是这一单最强的主张,
  **此前只活在我的汇报里、没有任何收据**。现在它自己算、自己 assert
  (`成功建立连接的调用: 0`,非零就红)。
  > 这两行差点也没贴上 —— 我以为贴了,是 `track archive` 的规矩 5b 把我拦下来的
  > (**同一天第二次**「我以为的状态 ≠ 机器上的状态」,第一次是 subdeepseek 抓的过期绿)。

**这一单真正的验收是"钱"**(判据接不住,只能实测对账):

```
本次总跑之后 kimi 进程启动: 3
其中启动即失败(连不出去): 3
成功建立连接的调用: 0
```

> ⚠️ 顺带更正我自己定的验收口径:一开始我数的是日志里 `kimi-code starting` 的条数,
> 那是**进程启动数**,分不出"花了钱"和"被挡住"(它从 172 涨到 175,吓了一跳)。
> 正确口径是**成功建立连接的次数**:3 次启动全部在 7 秒后死于
> `provider.connection_error ... auth.kimi.com ... fetch failed`,**零次往返、零额度**。

## Review

- lane: full
  > **碰了新写口 / 权限 / auth / 钱 / 数据一致性 → full,针孔再薄也不打折**(硬规矩,别在这降档)。
  > fast = 主+1,中等风险;self = 主自审(闸③ + 截图 + 全量回归),
  > 限纯前端/纯观感、后端一字未动、只新增已过审针孔的调用方。
- 派给: **主 agent 直接干** —— 返工 0 轮,自身错误 3 处(全在判据里,见红检三遍那段)。
  开工前开了 delegate 抽屉逐档过,两条**结构性**理由,不是"排除了 codex 就跳到自己干":
  ① **考卷跑不了**:C0 反空转要求宿主**真有外网**,还要 `unshare`/`nsenter`(root)。
     codex 沙箱默认禁网 ⇒ 它交回来的绿是它自己没验过的。抽屉那条"不要为一个本地端口
     拆墙"在这里更强:这单要的不是端口,是**真出口**。
  ② **机械闸在这单上不成立**:要改的 7 个 `tests/test-*` **同时就是判卷文件**
     (N3a/N3c 读它们)。`--protect` 清单和任务范围直接冲突,闸①的 byte-diff 也分不出
     「加守卫那一行」和「动断言」—— 唯一防"改考卷"的机械手段在这单上失效。
  ③ Sonnet worktree 腿**能**跑这份考卷(本机无沙箱),但闸①仍要退化成人眼逐行比对,
     而实现只有 2 个新文件 + 7 行插入 ⇒ 省不下什么,风险却全留着。
  ④ 实现本体是**防线自己**,且规格里全是弱模型最爱做松的地方(fail-closed、不认环境
     变量、幂等、透传)。
- 规格自查(读任何 panel 输出之前先答):
  规格 = 「跑判据的进程不许有外网出口」。它**错在哪都可能**:
  ① **范围错**:真正烧钱的路径可能不止 `tests/`。判据只看 `tests/`,
     要是哪天有人把判据内联进 `bin/` 的某个脚本里跑,这条不变量照不到。
     怎么发现:归档前对着 `bin/` 里所有会跑判据的入口数一遍(总跑是唯一一个,已确认)。
  ② **过紧**:某个套件将来真需要外网 ⇒ 它会红。这是故意的(总跑头部契约本就写着
     "只跑桩/离线套件"),但如果**红得没头没脑**,下一个人会去拆守卫而不是修套件 ⇒
     所以 N4 里"拒跑时要说清原因"是规格的一部分,不是装饰。
  ③ **层级错**:也许该堵的是"判据不许调 `sub*`"而不是"不许有出口"。
     否掉的理由写在 design 的 Alternatives:按工具名堵,新工具名一出现就漏;
     出口只有一个,堵它一次全覆盖。
- 腿的花名册(原样粘自 `logs/panel-no-egress-20260810.roster`):

```
submimo=PASS subdeepseek=PASS subglm=off subkimi=PASS
# ⚠️ 评审期间 HEAD 从 09f36af 移到 4b86efa —— 各腿未必评的同一棵树。
```

  `subglm=off` = 智谱欠费,**这条腿压根没派,不许读成通过**。所以这是 3/4 腿的 full。
  HEAD 漂移那条警告是真的:我在派发后又提交了 verify 收据(4b86efa)。
  subdeepseek 的 BLOCK 恰恰打在派发时的 HEAD(09f36af)上,复现无误,不受影响。
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - **[subdeepseek,BLOCK,已修]** 最后一个 commit(`09f36af` 强度声明)在守卫文件的
    注释里写了字面量 `nsenter`,而 N3b 的扫描 glob 含 `_*` ⇒ **判据把守卫自己报成逃逸口**,
    HEAD 上其实是 **17/1,不是我在任务书里写的 18/0**。它还指出:**我全部绿收据都跑在
    那笔 commit 之前,证据没覆盖交付状态。** 这条是本轮最值钱的发现 ——
    它抓的不是代码,是**我把一次过期的绿当成了现状**(和 08-05 turn_id「汇总会撒谎」同形)。
    修:N3b 跳过整行注释(注释里提一句不是"使用")。变异测试:把 `nsenter` 变成真的
    可执行行 ⇒ N3b 立刻转红,证明没被我改钝。
  - **[subkimi,BLOCK,已修]** 套件里那行 `. ".../_no-egress.sh"` **source 失败会静默裸跑**
    (没开 `set -e`)。套件被拷到别处 / 守卫文件不在 ⇒ 带着全网跑判据,而 N3a 只看文本、
    看不见。这是**事故形状(手滑),不是蓄意形状**,正落在这道闸的射程里。
    修:6 个 bash 套件 + 判据自己的引入行一律 `|| exit 78`,并把「引入行必须自带 `|| exit`」
    写成 N3a 的机械要求(python 的 import 失败本来就非零,不需要)。
    变异测试:拿掉任一处 ⇒ N3a 转红。
  - **[subkimi + 我自审 F3,采纳]** N3c 只问"拒跑了没",不问"**是不是被这道闸**拒的" ——
    别的原因早死也会非零 ⇒ 为错误的理由变绿。修:加断言"拒跑信息要提到
    unshare/隔离/出口"(和 N4 同一把尺)。
  - **[subdeepseek,采纳]** N3a/N3c 按文件名 glob 扫,而总跑的 `SUITES` 是**手列**的 ⇒
    往 SUITES 里加一个不叫 `test-*` 的判据,两条覆盖闸完全看不见(孤儿闸只查反方向)。
    修:扫描来源改成 `glob ∪ SUITES`。**这是本仓反复记账的「名单 vs 实际」老形状。**
  - **[submimo,采纳]** `design.md` 的 N8 与实现对不上(判据里没有 N8,它由
    `test-review-tooling.sh` 自己证)。已改文档。
  - **[subkimi,采纳]** 「额度没掉」这条最强的主张**没有落盘证据**,只活在我的汇报里。
    已补 `spend-reconcile` 收据(自己算、自己 assert,非零就红)。
  - **[我的孤发现,已修]** 守卫头部缺一条**强度声明**:这不是安全边界(root 一行
    `nsenter` 就出去,判据自己就在这么干),它只挡手滑。三条腿都没提这条。
    照 `bin/runlog` 的先例补上,免得后人当安全边界依赖。
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): **PASS**。
  不变量本身三条腿都判站得住(层级选择 = 堵出口而不是堵工具名;fail-closed 三处;
  不认环境变量)。两条 BLOCK 都是**闸的完备性**问题、不是方向问题,均已修 + 变异测试。
  **全票没让我降标准**:submimo 那条只给了"实现正确、判据有效"和一条文档建议,
  而同一棵树上另外两条腿各自挖出一个真洞 —— 又一次印证「全票 PASS 不等于题是对的」,
  以及**孤腿的发现才是信号**(subdeepseek 那条 BLOCK 只有它一条腿看见)。
  > **归档时这一条和顶部的 `Verdict:` 都不许还是占位符**,`track-guard` 规矩3 会挡;
  > 没归档但已经合并上线的,`track list` 会打 ⚠️(stage-timer 就这么漏了两个月)。

## Accepted deviations

- **N3a 不要求守卫引入行"靠前"**(我自审 F2 + subdeepseek 独立点到)。
  守卫是 `exec` 重跑整个脚本 ⇒ 写在它前面的代码会跑两遍。subdeepseek 给了一条具体的
  假绿路径:守卫前 `touch marker` + 后面断言 `[[ -f marker ]]`,双跑会让它假绿。
  **不加断言**:现在 7 个套件守卫前只有 `set -uo pipefail`;而"引入行必须在第一个有
  副作用的语句之前"这条很难不误报,而**误报 = 噪音 = 下次没人看**,是本仓记过账的反模式。
  按 CLAUDE.md「别在没出事的时候继续加闸」记账不修 → 已写进 `tasks/`。
- **`exec` 会丢掉命令行上的 shell 选项**(`bash -x tests/foo.sh` 的 `-x`)。调试时困惑,不修。
- **判据依赖 root + `nsenter -t 1`**。换机器会 C0 红(fail-loud:"我在这里问不出东西"),
  不会静默变绿。这份判据是本机专用的。
- **没有任何机械手段盯"总跑耗时逼近定时任务超时"**(F6)。这次 346s 撞了 300s 的墙,
  是我跑一遍计时才发现的,判据接不住。已调到 215s,但下次谁加个慢套件,
  同一形状会再来一次(不烧钱,但那个 cron 从此长红)。记账不修。
- **`subglm` 这条腿欠费关着** ⇒ 本单是 3/4 腿的 full,不是满编。
