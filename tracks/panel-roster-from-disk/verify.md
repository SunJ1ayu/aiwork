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
```

**红的那几份一份没藏**(规矩 5b):

- `oracle-red-before-impl` rc=1 —— 实现还不存在时,11 红 2 绿。
- `oracle-red-r9-r10-r7d` rc=1 —— 第一轮评审的发现收成判据、修复还没写时,R7d/R9a/R9b 三条红。
  **顺带更正一句我自己写得比事实好看的话**:上游 commit `bbdcdcd` 的标题写
  "R9/R10 现在是红的",而这份机器收据显示 **R10 两条修复前就是绿的**
  (它正文其实自己写着"实测本来就是对的,纯粹没人守")。R10 是补守卫,不是修 bug。

最终三份(`oracle-green-final` / `redcheck-final` / `tooling-suite-final`)都跑在
**最后一次编辑之后**:最后一次编辑是回退 norm + 删死代码(08:3x),三份收据分别是
08:38:17 / 08:38:48 / 08:43:50。

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

- 第二轮花名册: <第二轮跑完后原样粘>

- findings: <第二轮回来后写>

- arbitrated verdict (主裁): <待定>

## Accepted deviations

- <待补>
