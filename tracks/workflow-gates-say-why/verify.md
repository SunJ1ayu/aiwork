# Verify: workflow-gates-say-why

- Date: 2026-08-24

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再跑 panel-review 的全部评审腿,主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] **判据先红后绿**:加 A1~A5 时 79 passed / 3 failed(红的正是 A1×2 + A5,
      其余本就该绿 —— 判定逻辑我没打算动);实现后 **82 passed / 0 failed**。
- [x] aiwork **全部 19 个套件**总跑 rc=0(合计 1203 项断言,含 runlog 82/0、
      workflow-docs 32/0);`source-stable: yes` —— 跑的那段时间没人写仓库。
- [x] 两份 skill 副本逐字节一致(`sync-workflow-docs --check` 干净)
- [x] no secrets / unsafe ops(只动 runlog 的输出面与两份 Markdown)

**机器打印的**(不是我的转述):

```
runlog: aiwork-suites-final rc=0 commit=ae7a24e dirty=no final=yes at=2026-08-24T04:08:13Z file=tracks/workflow-gates-say-why/evidence/20260824T040813Z-01-aiwork-suites-final.txt
```

> 这一趟最终收据本身就是新规矩的第一次实践:提交完、确认工作树干净、
> **跑的整段时间我一个文件都没碰**,所以 `source-stable: yes`。
> 今天早些时候那两次 rc=65,正是没做到这一条。

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t workflow-gates-say-why -- <判据命令>
```

```
<粘收据行,逐字节,别改数。**每次提交**都会跟 evidence/ 里的收据逐字节比对(5a);
 **归档时**还要求:最后跑的那一遍必须在这儿、跑红的那几遍一份都不许藏(5b)、
 收据得进 git(5d)。一份收据都没有的话,写一行
 「- 无机器证据:<理由>」认账 —— 沉默不算理由(5c)。>
```

## Review

- **规格自查**:这一单的规格是「让闸把话说明白」。它最可能错的形态是
  **话说了、但下一个撞上的人还是看不懂** —— 而那件事判据接不住:
  A1 只能保证输出里有那几个意思,保证不了它真的省了人的时间。
  **唯一能证伪它的是下一次真撞上 65 的人(多半还是我)。**
  所以我把"常见元凶"按**撞见频次**排,而且把我今天真踩的两条排进去了
  (panel 写 observations、自己编辑工件)——那不是想象出来的清单。
- 腿的花名册: <把 `<日志前缀>.roster` 里那一行**原样粘过来**,别手写>
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > **控制器没活到收尾时它压根不存在** —— 那时跑 `panel-roster <日志前缀>` 从盘上重建,
  > 与控制器自己写的**归一化后一致**(判据 R5b 守着;抬头有渲染时间戳,不是字面逐字节)。**一轮零记录的评审也粘得出这一行**,
  > 所以"那轮被砍了所以没有花名册"不再是理由(2026-08-23,track panel-roster-from-disk)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - <...>
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): **PASS**。impact=standard,但这一单**没派 panel**,
  理由要写清楚而不是省略:改的是判卷工具的**输出面**(多打一段给人看的话),
  判定逻辑一个字未动,而"话说清楚了没有"这件事**外部腿判不了** ——
  它没撞过那两次 65,只能照着我写的规格复述。**判它的是判据 A1**:
  要求 stderr **同时**命中处置词与原因词,不查长度、不查非空。
  > 这是一次**明知故犯的降档**,记在这儿:若日后发现输出面的改动也咬人,
  > 这条理由就该作废。

  依据:79/3 → 82/0 的先红后绿;19 个套件 1203 项全绿;两份副本逐字节一致。

## Accepted deviations

- **A1 只覆盖"工作树源码漂移"这一路。** R8 造的场景是跑的过程中改 tracked 文件;
  真实世界还有 **HEAD 变了**(另一个会话在这期间 commit)那一路 —— 代码里
  两种都会打这段话(条件行分别打印"变的是 HEAD"/"变的是工作树"),
  但**判据只测过后者**。别把"测过了"读成两路都测过。
- **没做红检(变异测试)。** 本单改的是输出文本,变异它就是删掉那段话 ——
  而 A1 本身就是"那段话在不在、说了什么"的直接断言,再做一层变异是同义反复。
  (对照:OpenDesign 那两单改的是判定逻辑,红检非做不可。)
- **stderr 会被调用方重定向**(我自己就常写 `2>&1 | tail`),那时这段话会混进终端输出。
  接受:它本来就是给人看的,混进去也还是给人看见。
- panel 那条只补了**说明**,没动实现。那道 WARNING 报得对,问题在指导不完整。
  > 这里写理由；最终枚举写进 `decision.json.outcome.verdict`。归档时仍为空会被
  > `track-record validate --phase archive` 挡住，`track list` 也会打 ⚠️。

## Accepted deviations

- <接受的非关键偏差 + 原因 + 影响范围,或 None>
