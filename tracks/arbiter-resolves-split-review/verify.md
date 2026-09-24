# Verify: arbiter-resolves-split-review

- Date: 2026-09-24

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
runlog -t arbiter-resolves-split-review -- <判据命令>
```

```
runlog: r11-criteria-red rc=1 commit=3b916e7 dirty=yes at=2026-09-24T04:52:03Z file=tracks/arbiter-resolves-split-review/evidence/20260924T045203Z-01-r11-criteria-red.txt
runlog: r11-criteria-red-2 rc=1 commit=2b39065 dirty=yes at=2026-09-24T04:53:39Z file=tracks/arbiter-resolves-split-review/evidence/20260924T045339Z-01-r11-criteria-red-2.txt
runlog: split-mutants rc=2 commit=e9aedfa dirty=yes at=2026-09-24T04:56:29Z file=tracks/arbiter-resolves-split-review/evidence/20260924T045629Z-01-split-mutants.txt
runlog: split-mutants-2 rc=0 commit=2936d7f dirty=yes at=2026-09-24T05:02:47Z file=tracks/arbiter-resolves-split-review/evidence/20260924T050247Z-01-split-mutants-2.txt
runlog: tooling-total rc=0 commit=0bb1665 dirty=yes final=yes at=2026-09-24T05:10:10Z file=tracks/arbiter-resolves-split-review/evidence/20260924T051010Z-01-tooling-total.txt
runlog: split-mutants-3 rc=0 commit=e551efe dirty=yes at=2026-09-24T05:22:25Z file=tracks/arbiter-resolves-split-review/evidence/20260924T052225Z-01-split-mutants-3.txt
runlog: tooling-total-2 rc=0 commit=3a47e27 dirty=yes final=yes at=2026-09-24T05:26:40Z file=tracks/arbiter-resolves-split-review/evidence/20260924T052640Z-01-tooling-total-2.txt
runlog: split-mutants-r1 rc=0 commit=10ed62e dirty=no at=2026-09-24T05:48:55Z file=tracks/arbiter-resolves-split-review/evidence/20260924T054855Z-01-split-mutants-r1.txt
```
- r11-criteria-red / -2:判据先行,未改实现上红(27 → 夹具改用真实收据形状后 29)。
- split-mutants rc=2:第一次变异自检 **2 条存活**(M3 摘录可在别的腿日志里 —— q3 夹具测不到;M14 staged 放行未跟踪 —— 被后一道挡兜住,
  顺查出 staged 视图拒收 100755 可执行脚本的真 bug)⇒ 先补判据(`2936d7f`)再修;split-mutants-2 全杀。
- 写自审时自己想到、R11c 复现:已归档的单重验找不到归档前路径的证据 ⇒ 判据 `dbf1bb3`(红)→ 修 `e551efe`;split-mutants-3 18 全杀。
- tooling-total-2 = 第 1 轮派发前 final 离线总跑,31 套件全绿。split-mutants-r1 = 第 1 轮修复后 20 变异全杀。


## Review

- 规格自查(读 panel 输出之前,自审原文在 /root/panel-my-reviews/arbiter-resolves-split-review-r1-my-review.md [仓外不承重]):
  用户成功条件 = 分裂时主裁写清理由证据即可归档、写不全照挡;最担心的是 ledger 吞错(③)—— 第 1 轮 Grok 正好点中。
- 腿的花名册(第 1 轮): subdeepseek=PASS(verdict=BLOCK) subcursor.grok-4.7-high=PASS(verdict=BLOCK)(日志 /root/aiwork/logs/panel-arbiter-split-r1-20260924-133814.* [仓外不承重])
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > **控制器没活到收尾时它压根不存在** —— 那时跑 `panel-roster <日志前缀>` 从盘上重建,
  > 与控制器自己写的**归一化后一致**(判据 R5b 守着;抬头有渲染时间戳,不是字面逐字节)。**一轮零记录的评审也粘得出这一行**,
  > 所以"那轮被砍了所以没有花名册"不再是理由(2026-08-23,track panel-roster-from-disk)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- 轮次记录(每次派发一行;实质评审与基础设施重试分开,重试不算轮但次数与耗时照记):

  | 轮 | 类型(实质 / 重试) | 派发前 `track preflight` | 日志前缀 | 新增有效阻断 |
  |---|---|---|---|---|
  | 1 | 实质 | rc=3,BLOCK=0(先修过一次 views BLOCK:tasks/ 未提交题面,`80641ee`) | panel-arbiter-split-r1-20260924-133814 | 2(#1 #2) |

- findings(**先处置、后动手**;一轮一份修复清单,一次修完再复审 —— panel 抽屉 4b):

  | # | 发现:触发条件与影响 | 核实证据 | 处置 | 理由 |
  |---|---|---|---|---|
  | 1 | (DeepSeek BLOCK)文档说分裂「不加腿不重派」,而不带 `--members` 的旧轮换入口遇冲突仍自动补一条 spare | 读 `bin/panel-review:1018-1056`(只在 `-z $MEMBERS` 时升级)、`:32` 帮助原文;判据 V43④ 钉着这行为 | 必须修(文档) | 文档与实现不一致会误导主裁。改文档说准两种入口;不改 panel-review(proposal 非目标)|
  | 2 | (Grok)裁决记录写错时归档挡(split.*),ledger 吞掉错误、另一组够数时仍报可归档 | 读 `bin/track-record` ledger 段属实;判据「裁决记录写错 ⇒ ledger 也报缺口」在 `a72f679` 红 | 必须修 | 承诺 4/5(ledger 与归档同口径);修:missing 加 `split_resolution:<rule>` |
  | 3 | (DeepSeek LOW2)只靠已裁分裂覆盖的单,ledger `authoritative_*` 报 null/0 | 同一判据提交里红 | 必须修(顺手) | 同一段代码、字段自相矛盾;权威组候选 = 不冲突组 + 已裁分裂 |
  | 4 | (Grok BLOCK)runlog 收据与同名 observation 都免指纹,评审后手写一对(或改已有收据)就能当证据 | 读 `_review_delivery.py:66-93`、`track-record` 收据判定,属实 | **驳回为缺陷**,文档写明边界 | 这需要**手工伪造**机器收据 + 观测记录 —— runlog 自己的强度声明就是「挡顺手凑数,不挡蓄意伪造」,本闸同一威胁模型(防主裁偷懒)。评审后跑复现留收据正是驳回最好的证据,不能禁。我在第 1 轮题面写「证据不在被审交付里 ⇒ BLOCK」说大了,设计原文本就把收据列为例外 |
  | 5 | (DeepSeek LOW3)文件名带冒号(`bin/a:b.py`)不能当证据 | 实测属实 | 延期 | 下一个使用者只有在要引用带冒号的文件时才碰到,改引同目录别的文件或 runlog 收据即可 |
  | 6 | (DeepSeek)R11 夹具是 schema 1(legacy-unbound),没走真实交付绑定 | 属实;DeepSeek 用 schema 2 夹具实跑:完整裁决 rc=0、评审后新加文件当证据被 `observation.review_delivery` 挡 | 延期 | 出货实现在真实路径上已被探针证实;属「挡不住将来改写」类 |
  | 7 | (DeepSeek)摘录可以极短(如 "o") | 属实 | 延期(设计已承认的 G1 剩余面) | 机器不判断摘录是否就是那条阻断 |

  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。延期 = 留在这里,不自动开新单。
- **第 2 轮(派发前写)**:核验 #1~#3 修法与文档改动;成员不变(DeepSeek + Grok,不换腿找 PASS);预算最后一轮。
  题面仍按 4b:闸对承诺的违背 / 误拒 / 文档误导才算 BLOCK;挡不住假想改写、蓄意伪造、G1/G4 照报不算。有真阻断 ⇒ 停下交业主。
- arbitrated verdict (主裁): <...>
  > 这里写理由；最终枚举写进 `decision.json.outcome.verdict`。归档时仍为空会被
  > `track-record validate --phase archive` 挡住，`track list` 也会打 ⚠️。

## Accepted deviations

- <接受的非关键偏差 + 原因 + 影响范围,或 None>

## 试行记录(review-convergence 试行,约五单;拿不到的写 unknown,别补 0)

- 总交付历时:<开工 commit 时刻 → 归档 commit 时刻>
- 每轮新增有效阻断:<第 1 轮 n / 第 2 轮 n>
- 基础设施等待:<重试次数;observations 里 panel-review 的 duration_ms 求和>
- 交付后返工:<归档后因本单再改过几次;不知道写 unknown>
