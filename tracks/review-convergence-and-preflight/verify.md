# Verify: review-convergence-and-preflight

- Date: 2026-09-16

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再按 impact-risk 预算跑 panel-review；只有特殊控制面
> 才显式 `--all` 做全池评审。最后仍由主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [ ] build passes
- [ ] tests pass
- [ ] no secrets / unsafe ops

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t review-convergence-and-preflight -- <判据命令>
```

```
<粘收据行,逐字节,别改数。**每次提交**都会跟 evidence/ 里的收据逐字节比对(5a);
 **归档时**还要求:最后跑的那一遍必须在这儿、跑红的那几遍一份都不许藏(5b)、
 收据得进 git(5d)。一份收据都没有的话,写一行
 「- 无机器证据:<理由>」认账 —— 沉默不算理由(5c)。>
```

## Review

- 规格自查(读任何 panel 输出之前先答):<如果规格本身就是错的,会错成什么样、我怎么发现?
  panel 只验"实现合不合规格",验不了"规格对不对" —— 全池一致 PASS 也不等于题是对的。>
- 腿的花名册: <把 `<日志前缀>.roster` 里那一行**原样粘过来**,别手写>
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > **控制器没活到收尾时它压根不存在** —— 那时跑 `panel-roster <日志前缀>` 从盘上重建,
  > 与控制器自己写的**归一化后一致**(判据 R5b 守着;抬头有渲染时间戳,不是字面逐字节)。**一轮零记录的评审也粘得出这一行**,
  > 所以"那轮被砍了所以没有花名册"不再是理由(2026-08-23,track panel-roster-from-disk)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- 轮次记录(每次派发一行;实质评审与基础设施重试分开,重试不算轮但次数与耗时照记):

  | 轮 | 类型(实质 / 重试) | 派发前 `track preflight` | 日志前缀 | 新增有效阻断 |
  |---|---|---|---|---|
  | 1 | 实质(Kimi+Grok 派出;两腿基础设施死,自动补 MiMo) | rc=3,BLOCK 0(再往前一次 dogfood 抓到 design.md 3 行,已修) | `logs/panel-review-convergence-and-preflight-review-r1-20260916-2143` | 0(MiMo) |
  | 1 | **重试**(内容零改动;Grok `Not signed in`、Kimi 周额度用光 ⇒ 显式关掉,派 MiMo+DeepSeek) | rc=3,BLOCK 0 | `logs/panel-review-convergence-and-preflight-review-r1-retry-20260916-2155` | 1(DeepSeek #4)+ 主审自查 1 |

  | 2 | 实质(复审:核验 F1/F2;MiMo+DeepSeek) | rc=3,BLOCK 0 | `logs/panel-review-convergence-and-preflight-review-r2-20260916-2208` | 3(DeepSeek P1/P5/P6:F1、F2 没修完整);MiMo PASS 未见 |
  | 3 | **追加**实质(见下方「追加评审声明」) | <派发前填> | <…> | <…> |

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
  | D9 | [DeepSeek P4] R2 新断言是子串匹配,措辞写反的实现(「N 数的是实质评审轮,重试也算」)也能绿 | `tests/test-panel-round-discipline.sh` R2 | 延期 | 挡不住假想的未来实现;当前实现正确。下一个使用者:有人把那句改反时判据不会红 |
  | —  | [DeepSeek P2 / P3] 「删掉」药方对在写收据是错的 / PENDING 顶行措辞 | 同 D6 / D2 | 维持延期 | 两腿复审都认可 D6、D2 的延期理由;不因"顺手"施工 |
  | —  | [MiMo] 「无新发现」 | G1 亲读成立 | 不采信 | 共同假阴性的实例:MiMo 两份报告都没看到 306 行 |

  **追加评审声明(派发前写,4b ④)**:
  - 具体阻断:G1(工具打印与 4b ④ 冲突)、G2(同一抽屉两处节奏与 4b ② 冲突)、G3(修复句说大)。
  - 追加目的:**只**核验 G1~G3 的修复及其影响面(读数两行 + 反锚定两句 + 判据 R2 一条),其余实现自第 2 轮起零改动。
  - 新的有限预算:**1 轮**(MiMo + DeepSeek,当前只有这两家健康)。**不再追加**:若这一轮再出「本单必须修」,
    本单保持未完成(不归档、不写 PASS),把 `bin/panel-review` 读数文案这一块拆出本单,回头找业主。
  - 为什么不缩范围代替追加:不管怎么缩,改了 panel-review/SKILL 任何一个字都要重新绑定评审;
    归档 high 还要求同一次评审两家无冲突,第 2 轮 PASS/BLOCK 冲突那次本来就不能算覆盖。

  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。延期 = 留在这里,不自动开新单。
- arbitrated verdict (主裁): <...>
  > 这里写理由；最终枚举写进 `decision.json.outcome.verdict`。归档时仍为空会被
  > `track-record validate --phase archive` 挡住，`track list` 也会打 ⚠️。

## Accepted deviations

- <接受的非关键偏差 + 原因 + 影响范围,或 None>
