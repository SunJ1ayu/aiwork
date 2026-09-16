# Verify: review-convergence-and-preflight

- Date: 2026-09-16

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再按 impact-risk 预算跑 panel-review；只有特殊控制面
> 才显式 `--all` 做全池评审。最后仍由主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes(纯脚本仓;`bash -n` / Python 解析随各套件跑)
- [x] tests pass(最终全量总跑 `full-tooling-suite-final` rc=0,@`a43f895` 已含 G1~G4;之后只改了题面与收尾记录)
- [x] no secrets / unsafe ops(预检零写盘由判据快照钉住;没碰密钥、网络、生产)

**机器打印的**(不是我的转述):

判据先行 —— `tests/test_track_preflight.py` 旧实现下 **16/16 红**(新命令只能浅红,深度靠下面的红检与变异):

```
runlog: red-oracle-preflight rc=1 commit=fc8c4e4 dirty=yes at=2026-09-16T13:25:08Z file=tracks/review-convergence-and-preflight/evidence/20260916T132508Z-01-red-oracle-preflight.txt
```

实现之后 **17/17**(含更正后的 P12 + 更强的 P12b);红检:退回实现 ⇒ 正好 **17 红**,红在目标断言上:

```
runlog: oracle-after-impl rc=0 commit=b578d89 dirty=yes at=2026-09-16T13:29:06Z file=tracks/review-convergence-and-preflight/evidence/20260916T132906Z-01-oracle-after-impl.txt
runlog: redcheck-preflight rc=0 commit=6c4a68e dirty=no at=2026-09-16T13:29:27Z file=tracks/review-convergence-and-preflight/evidence/20260916T132927Z-01-redcheck-preflight.txt
```

变异自攻 9 种错实现:第一轮 **7 红 2 活**(「未知规则也放成 PENDING」「去掉 GIT_OPTIONAL_LOCKS=0」)⇒ 补 P15/P16 ⇒ 第二轮 **9/9 红**;判据 19/19:

```
runlog: mutate-preflight-selfattack rc=1 commit=6c4a68e dirty=yes at=2026-09-16T13:30:05Z file=tracks/review-convergence-and-preflight/evidence/20260916T133005Z-01-mutate-preflight-selfattack.txt
runlog: mutate-preflight-selfattack-r2 rc=0 commit=efc18dc dirty=yes at=2026-09-16T13:31:18Z file=tracks/review-convergence-and-preflight/evidence/20260916T133118Z-01-mutate-preflight-selfattack-r2.txt
runlog: oracle-preflight-p16 rc=0 commit=efc18dc dirty=yes at=2026-09-16T13:31:41Z file=tracks/review-convergence-and-preflight/evidence/20260916T133141Z-01-oracle-preflight-p16.txt
```

相关旧判据回归(archive / worktree 清理 / 证据寿命 / 提交守卫 / 交付绑定 / 文档 / 轮次读数)全绿,第一次全量总跑绿:

```
runlog: regress-test-track-record rc=0 commit=efc18dc dirty=yes at=2026-09-16T13:31:47Z file=tracks/review-convergence-and-preflight/evidence/20260916T133147Z-01-regress-test-track-record.txt
runlog: regress-test-worktree-sweep rc=0 commit=efc18dc dirty=yes at=2026-09-16T13:31:53Z file=tracks/review-convergence-and-preflight/evidence/20260916T133153Z-01-regress-test-worktree-sweep.txt
runlog: regress-test-evidence-lifetime rc=0 commit=efc18dc dirty=yes at=2026-09-16T13:31:57Z file=tracks/review-convergence-and-preflight/evidence/20260916T133157Z-01-regress-test-evidence-lifetime.txt
runlog: regress-test-track-guard rc=0 commit=efc18dc dirty=yes at=2026-09-16T13:31:59Z file=tracks/review-convergence-and-preflight/evidence/20260916T133159Z-01-regress-test-track-guard.txt
runlog: regress-review-delivery rc=0 commit=efc18dc dirty=yes at=2026-09-16T13:32:13Z file=tracks/review-convergence-and-preflight/evidence/20260916T133213Z-01-regress-review-delivery.txt
runlog: regress-workflow-docs rc=0 commit=efc18dc dirty=yes at=2026-09-16T13:34:22Z file=tracks/review-convergence-and-preflight/evidence/20260916T133422Z-01-regress-workflow-docs.txt
runlog: regress-panel-round-discipline rc=0 commit=efc18dc dirty=yes at=2026-09-16T13:34:22Z file=tracks/review-convergence-and-preflight/evidence/20260916T133422Z-02-regress-panel-round-discipline.txt
runlog: full-tooling-suite rc=0 commit=38b2c84 dirty=no at=2026-09-16T13:34:56Z file=tracks/review-convergence-and-preflight/evidence/20260916T133456Z-01-full-tooling-suite.txt
```

第 1 轮修复清单 F1(读数 R2 两条先红后绿)/ F2(文档):

```
runlog: red-f1-round-readout rc=1 commit=5c3f8ca dirty=yes at=2026-09-16T14:06:36Z file=tracks/review-convergence-and-preflight/evidence/20260916T140636Z-01-red-f1-round-readout.txt
runlog: f1-round-readout-after-fix rc=0 commit=4a55d9f dirty=yes at=2026-09-16T14:07:15Z file=tracks/review-convergence-and-preflight/evidence/20260916T140715Z-01-f1-round-readout-after-fix.txt
runlog: f2-workflow-docs-after-fix rc=0 commit=4a55d9f dirty=yes at=2026-09-16T14:07:30Z file=tracks/review-convergence-and-preflight/evidence/20260916T140730Z-01-f2-workflow-docs-after-fix.txt
```

第 2 轮修复清单 G1/G3(R2 三条先红后绿)、G4(V15 一条先红:560 绿 1 红)、G2(文档):

```
runlog: red-g1-g3-round-readout rc=1 commit=ef9f0fd dirty=yes at=2026-09-16T14:16:30Z file=tracks/review-convergence-and-preflight/evidence/20260916T141630Z-01-red-g1-g3-round-readout.txt
runlog: g1-g3-round-readout-after-fix rc=0 commit=1b37abb dirty=yes at=2026-09-16T14:17:03Z file=tracks/review-convergence-and-preflight/evidence/20260916T141703Z-01-g1-g3-round-readout-after-fix.txt
runlog: g2-workflow-docs-after-fix rc=0 commit=1b37abb dirty=yes at=2026-09-16T14:17:18Z file=tracks/review-convergence-and-preflight/evidence/20260916T141718Z-01-g2-workflow-docs-after-fix.txt
runlog: red-g4-anchor-warning rc=1 commit=1b37abb dirty=yes at=2026-09-16T14:18:06Z file=tracks/review-convergence-and-preflight/evidence/20260916T141806Z-01-red-g4-anchor-warning.txt
```

最终全量总跑(**结论所依据的那一遍**,review-tooling 561/0,含 G4 那条):

```
runlog: full-tooling-suite-final rc=0 commit=a43f895 dirty=no at=2026-09-16T14:22:36Z file=tracks/review-convergence-and-preflight/evidence/20260916T142236Z-01-full-tooling-suite-final.txt
```

- 判据夹具更正一次:P12 第一版把「删掉已提交的 decision」当成 legacy track,实现之后才红出来;单独 commit(`b578d89`)改成从没有 decision 的 track 问,并加更强的 P12b。
- 部署副本:`sync-workflow-docs --check` 零漂移(每次改抽屉后 `--force` 同步;改动前 `--check` 为零漂移,覆盖的就是旧规范源)。

## Review

- 规格自查(读任何 panel 输出之前先答,全文在仓外自审 [仓外不承重]):**最可能错在「协议是纪律不是闸」** ——
  处置分类、修复清单、轮次预算、派发前预检全靠我执行。本单自己就给了两次反例:第 2 轮修 F1 只改那一行、没扫同类(G1);
  第 1 次派发前 panel-review 不提醒预检(D8)。能接住它的只有接下来的真实任务与试行记录,不是本单的断言。
- 腿的花名册(每次派发各一行,原样粘自 `<前缀>.roster`):
  - 第 1 轮 `logs/panel-review-convergence-and-preflight-review-r1-20260916-2143`:
    `submimo=PASS(verdict=PASS) subdeepseek=SKIP(rotation) subglm=SKIP(health:cooldown:rate_limit) subkimi=FAIL(rc=1) subgemini=SKIP(health:dead:FAIL:6) subgrok=FAIL(rc=1)`
  - 第 1 轮重试 `…-review-r1-retry-20260916-2155`:
    `submimo=PASS(verdict=PASS) subdeepseek=PASS(verdict=PASS) subglm=SKIP(health:cooldown:rate_limit) subkimi=off subgemini=SKIP(health:dead:FAIL:6) subgrok=off`
  - 第 2 轮 `…-review-r2-20260916-2208`:
    `submimo=PASS(verdict=PASS) subdeepseek=PASS(verdict=BLOCK) subglm=SKIP(health:cooldown:rate_limit) subkimi=off subgemini=SKIP(health:dead:FAIL:6) subgrok=off`
  - 追加第 3 轮 `…-review-r3-20260916-2231`:
    `submimo=PASS(verdict=PASS) subdeepseek=PASS(verdict=PASS) subglm=SKIP(health:cooldown:rate_limit) subkimi=off subgemini=SKIP(health:dead:FAIL:6) subgrok=off`
- 反锚定:每次派发都报 anchor leak。第 1 轮命中的是 design-studio 两单的旧自审副本(tasks/,与本单无关)、本单**空模板** verify.md、
  模板文件本身;本单自审一直在仓外 [仓外不承重]。第 2、3 轮 verify.md 已有处置表 —— 按 4b ② 复审轮读到它是预期内的,如实记账。
- 轮次记录(每次派发一行;实质评审与基础设施重试分开,重试不算轮但次数与耗时照记):

  | 轮 | 类型(实质 / 重试) | 派发前 `track preflight` | 日志前缀 | 新增有效阻断 |
  |---|---|---|---|---|
  | 1 | 实质(Kimi+Grok 派出;两腿基础设施死,自动补 MiMo) | rc=3,BLOCK 0(再往前一次 dogfood 抓到 design.md 3 行,已修) | `logs/panel-review-convergence-and-preflight-review-r1-20260916-2143` | 0(MiMo) |
  | 1 | **重试**(内容零改动;Grok `Not signed in`、Kimi 周额度用光 ⇒ 显式关掉,派 MiMo+DeepSeek) | rc=3,BLOCK 0 | `logs/panel-review-convergence-and-preflight-review-r1-retry-20260916-2155` | 1(DeepSeek #4)+ 主审自查 1 |

  | 2 | 实质(复审:核验 F1/F2;MiMo+DeepSeek) | rc=3,BLOCK 0 | `logs/panel-review-convergence-and-preflight-review-r2-20260916-2208` | 3(DeepSeek P1/P5/P6:F1、F2 没修完整);MiMo PASS 未见 |
  | 3 | **追加**实质(派发前已声明,预算 1 轮;MiMo+DeepSeek) | rc=3,BLOCK 0 | `logs/panel-review-convergence-and-preflight-review-r3-20260916-2231` | 0 |

  > panel-review 当场把第 1 轮那次重试印成「这是第 2 轮」—— 正是修复清单 F1 要修的那个词义冲突。
  > 第 2 轮 F1 修复生效后,同一处印成「这是第 3 轮」并紧跟一句「这个 N 数的是 panel 派发……不是实质评审轮」。

- findings(**先处置、后动手**;一轮一份修复清单,一次修完再复审 —— panel 抽屉 4b):

  | # | 发现:触发条件与影响 | 核实证据 | 处置 | 理由 |
  |---|---|---|---|---|
  | F1 | [DeepSeek #4] `panel-review` 读数「这是第 N 轮」数的是 panel **派发**(重试也算),4b 预算数的是**实质评审**;同一个「轮」字两个集合 | 本单亲历:重试被印成「这是第 2 轮」(`bin/panel-review` round_readout);4b ④「默认 2 轮实质评审」 | **必须修** | 验收边界 1「不与其他工具打印矛盾」不成立;照字面读会以为预算已用完 |
  | F2 | [主审自查] 4b ② 要求先把处置落 verify.md 再修再复审;同一抽屉反锚定一节说「真干净只有派发那一刻 verify.md 还没写」⇒ 复审轮必然"违规",文档没说哪句优先 | `workflow/skills/panel/SKILL.md` 4b ② 与反锚定一节 | **必须修** | 同一份权威协议自相矛盾(验收边界 1);下一个使用者会在复审前把处置表删掉或推迟落盘,两样都坏 |
  | D1 | [DeepSeek #1] `proposal.md` Scope 把判据写成 `tests/test-track-preflight.sh`,实际是 `tests/test_track_preflight.py` | design.md / tasks.md / 总跑清单都是 `.py` | 延期 | 更正就记在这里(豁免文件,不作废绑定);下一个读 proposal 的人会先扑空,再在总跑清单里找到 |
  | D2 | [DeepSeek #2] decision 的 PENDING 顶行一律写「要等最终评审 / 主 agent 仲裁」,对 main/delegate/received/success_required 不准(解药是补跑执行) | `bin/track` decision 分支;明细行 `rule=… expected=…` 是对的 | 延期 | 补执行收据进 observations/ 与 evidence/,都是豁免件 ⇒ 看错顶行不会白跑一轮;下一个使用者:扫顶行会先去派评审,再从明细看到还缺 runlog |
  | D3 | [DeepSeek #3] preflight 没有 `--keep-trees` 口径,本打算 `archive --keep-trees` 保留的脏树也报 BLOCK | `bin/track` worktrees 分支恒传 keep=0 | 延期 | 多挡方向;下一个使用者:多看到一行 BLOCK,要自己知道归档时会加 --keep-trees |
  | D4 | [DeepSeek #5 + MiMo 两份] 判据强度:sweep rc=3(ignored)没有一幕走到;ERROR 不降格只钉了 decision 一条;destination 为文件未测;非 PASS verdict 早返回未测;view_mismatch 与 review-delivery 拒绝/崩溃分类未测 | 读代码:各分支当前实现正确(两腿与我各读一遍) | 延期 | 「挡不住假想的未来实现」,不扩大本单承诺;下一个使用者:有人把这些分支改错时判据不会红 |
  | D5 | [主审自查] sweep 在 archive 里 `set -e` 生效,在 preflight 的 `$(…) && … \|\|` 里失效 ⇒ 函数内某条命令意外失败时 archive 中止、preflight 继续 | `bin/track` 两个调用点 | 延期 | 函数全用显式 return,现有分支无差;方向是 preflight 少报一个"这里会中止",不涉写盘 |
  | D6 | [主审自查,dogfood 实见] runlog 正在写的收据还没有 `runlog:` 行 ⇒ 不算豁免件 ⇒ views 报暂时 BLOCK,药方「git add / 删掉」对它是错的 | 本单 13:43Z dogfood 输出 | 延期 | 跑完即消失;下一个使用者:长跑期间跑预检多一行误报,**照药方删掉会丢一份在写的收据** —— 延期项里最该先做的一条 |
  | D7 | [主审自查] `[仓外不承重]` 必须一字不差,`[仓外不承重:理由]` 被拒,闸的提示没说"一字不差" | 09-16 晚在 design-studio 与本单各栽一次 | 延期 | 不在本单范围(证据寿命闸);下一个使用者:评审后在非豁免文件上写错会多改一次、可能多一轮 |
  | D8 | [主审自查] 第 1 次派发时 panel-review 不打印预检提醒(读数只在 ≥2 次派发才出现),最容易忘的正是第 1 轮之前那一次 | `bin/panel-review` round_readout `n>0` 才打印 | 延期 | 协议是纪律;下一个使用者:忘跑预检时第 1 轮照样可能白花 |
  | X1 | [DeepSeek #6] preflight 在 verdict=null 时就比两视图,比 archive 严 | 设计如此(design D 表) | 驳回 | 正是要在评审前暴露的那类问题,方向安全 |
  | X2 | [MiMo 重试] 「与 panel-review 打印没有矛盾」 | F1 亲历 | 驳回 | 与本单亲历的「重试印成第 2 轮」相反 |

  修复清单(第 1 轮 → 第 2 轮核验):**F1、F2**。延期项不施工、不开新单。

  **第 2 轮(复审)处置**:

  | # | 发现:触发条件与影响 | 核实证据 | 处置 | 理由 |
  |---|---|---|---|---|
  | G1 | [DeepSeek P1,孤腿 BLOCK] `bin/panel-review` 其它=0 那句「这一轮算进开工写的轮次预算」无条件打印;基础设施重试正是其它=0 ⇒ 等于说重试吃预算,与 4b ④ 正面冲突 | 读 `bin/panel-review:306`(本单 `38b2c84` 写入);本单第 1 轮重试就是其它=0 的形状 | **必须修** | F1 没修完整:与 F1 同一把尺子(验收边界 1),而且就是 F1 亲历的那个误读 |
  | G2 | [DeepSeek P5] 反锚定一节两处(「正确节奏是先派发、后写 verify.md」「真干净只有一条路」)没限定初审;F2 只在 4b 里说清 | `workflow/skills/panel/SKILL.md:166,180-181` | **必须修** | F2 没修完整:只读反锚定那节的人拿到的节奏与 4b ② 相反(验收边界 1) |
  | G3 | [DeepSeek P6] F1 新加那句说 N「数的是 panel 派发」,实际数的是**已落盘**的派发 —— 控制器没活到收尾那次不计 | `bin/panel-review` round_readout 数 `observations/*panel-review*.json` | **必须修** | F1 的修复句说大了一点;本抽屉「机制要说准,别说大」 |
  | G4 | [主审派发前自扫,同类残留] `bin/panel-review` 反锚定报警原文无条件印「先派发、后写 verify.md」;复审轮必然触发它(处置表已落盘),与 4b ② 正面相反 | `bin/panel-review` anchor leak 段;本单第 1 轮重试与第 2 轮派发都印过这句 | **必须修** | 与 G2 同类(工具打印 vs 4b ②,验收边界 1);派追加轮之前按"同一类问题"把活文档与工具打印全扫一遍才找到,不让追加轮再被同类卡住 |
  | D9 | [DeepSeek P4] R2 新断言是子串匹配,措辞写反的实现(「N 数的是实质评审轮,重试也算」)也能绿 | `tests/test-panel-round-discipline.sh` R2 | 延期 | 挡不住假想的未来实现;当前实现正确。下一个使用者:有人把那句改反时判据不会红 |
  | D10 | [主审自查] 第 2 轮我修 F1 只改了那一行、没先扫同函数同类句子,才让 DeepSeek 替我找到邻行(G1);G4 是追加轮前按同类扫出来的 | G1 与 F1 相隔 65 行,同一函数同一批打印 | 延期 | 「修一处先扫同类」该是 4b ③ 修复清单的一步;本单再加协议文字又要评审,不在追加轮施工。下一个使用者:修复清单照旧可能漏邻行,多花一轮 |
  | —  | [DeepSeek P2 / P3] 「删掉」药方对在写收据是错的 / PENDING 顶行措辞 | 同 D6 / D2 | 维持延期 | 两腿复审都认可 D6、D2 的延期理由;不因"顺手"施工 |
  | —  | [MiMo] 「无新发现」 | G1 亲读成立 | 不采信 | 共同假阴性的实例:MiMo 两份报告都没看到 306 行 |

  **追加评审声明(派发前写,4b ④)**:
  - 具体阻断:G1(工具打印与 4b ④ 冲突)、G2(同一抽屉两处节奏与 4b ② 冲突)、G3(修复句说大)、
    G4(派发前主审自扫补入:反锚定报警原文与 4b ② 冲突)。
  - 追加目的:**只**核验 G1~G4 的修复及其影响面(读数两行 + 报警一行 + 反锚定两句 + 判据 R2/V15),其余实现自第 2 轮起零改动。
  - 新的有限预算:**1 轮**(MiMo + DeepSeek,当前只有这两家健康)。**不再追加**:若这一轮再出「本单必须修」,
    本单保持未完成(不归档、不写 PASS),把 `bin/panel-review` 读数文案这一块拆出本单,回头找业主。
  - 为什么不缩范围代替追加:不管怎么缩,改了 panel-review/SKILL 任何一个字都要重新绑定评审;
    归档 high 还要求同一次评审两家无冲突,第 2 轮 PASS/BLOCK 冲突那次本来就不能算覆盖。

  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。延期 = 留在这里,不自动开新单。
  **追加第 3 轮处置**:两腿均 PASS,无必须修。DeepSeek 两条 low/info(V15 新断言是宽子串 —— 并入 D9;读数两行「已落盘的 panel 轮次 / 派发」措辞差异 —— 不矛盾,无动作);
  它隔离复跑时 V15 旧断言「报警不阻断派发」在新旧两版 bin 上**都红** ⇒ 非本次引入的夹具/环境差异,真实环境全量总跑 561/0,不采信为缺陷。

- arbitrated verdict (主裁): **PASS**。
  验收边界四条逐条成立:① 4b 是唯一权威,其余文档/模板/工具打印与它对齐(F1/F2/G1~G4 修完后,第 3 轮两腿与我各自 grep 活文档与工具打印,无同类残留);
  ② 模板表达了初审/复审、验收边界、轮次预算、处置与延期理由,不复制机器枚举;③ `track preflight` 七项不短路、ERROR 不降格、退出码按 design,
  判据 19 条 + 变异 9/9;④ 零持久副作用(快照判据 + DeepSeek 整棵 `.git` 哈希复核),预检后 archive 照拒,archive/dispatch/shape 行为未变。
  三轮外审里唯一成立的阻断来自 DeepSeek 孤腿(第 2 轮),MiMo 三份都没看到 —— 共同假阴性的现场实例。
  **轮次**:预算 2 轮用完时有真实阻断,按 4b ④ 派发前写了追加声明(1 轮、只核 G1~G4、再出必须修就保持未完成);追加轮无阻断 ⇒ 结束。
  另有 1 次基础设施重试(Kimi 周额度用光、Grok 登录失效),不算实质轮。派发共 4 次,panel 总耗时 1915 秒。

## Accepted deviations

- 延期 D1~D10 全部留在上面的处置表,**不开新单**。延期里最该先做的是 D6(预检药方「删掉」对在写收据是错的)与 D10(修复清单先扫同类)。
- 追加了 1 轮实质评审(超出开工写的 2 轮),理由与预算在「追加评审声明」里,派发前落盘。

## 试行记录(review-convergence 试行,约五单;拿不到的写 unknown,别补 0)

- 总交付历时:开工 `fc8c4e4` 21:23 → 归档 commit(本记录写于 22:40 前后,归档时刻以 git log 为准)≈ 1 小时 20 分
- 每轮新增有效阻断:第 1 轮 2(F1 来自 DeepSeek,F2 主审自查)/ 第 2 轮 4(G1~G3 来自 DeepSeek,G4 主审派发前自扫)/ 追加第 3 轮 0
- 基础设施等待:1 次重试;4 次派发 panel duration_ms 合计 1915 秒(692 / 475 / 374 / 372),其中第 1 轮 692 秒含两条死腿与自动补腿
- 交付后返工:unknown(归档后才知道)
