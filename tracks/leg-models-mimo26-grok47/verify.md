# Verify: leg-models-mimo26-grok47

- Date: 2026-09-22

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

## 为什么是 ARCHIVED-SUPERSEDED

本单代码(`255c246` 判据先行 / `1ddd7a4` 换模型)早上提交后我断线(Claude 服务 529),
GPT 接手把它合进了 `model-selection`(`6028c98`)。之后 `model-selection` 的外审题面
**明确点名**审「MiMo xiaomi/mimo-v2.6-pro 的 provider-only 运行时登记、Cursor grok-4.7-high
与目录选择的集成」,审的 delta 是 `003563c..HEAD`,完整包含本单两个提交;
第 3 轮 Kimi + Grok 4.7 同一轮两家合格 PASS,主裁 PASS,已归档
(`tracks/archive/model-selection/verify.md`)。本单不再单独花一轮 high 外审
—— 那是同一份代码第二次被审,而本单的机器覆盖不能跨 track 借用,所以诚实的记法是被取代,不是 PASS。

## 验收(proposal 写的「用户可观察的成功」)

真跑时运行中的腿回报的是新模型 —— 今天 model-selection 的两次 panel 各真跑一次:

- Cursor 服务端自报(`*.subcursor.stream-summary.json`):`Grok 4.7 256K High`,success=true,family_ok=true。
- MiMo 日志抬头:`> aiwork-review · mimo-v2.6-pro`(评审锁档 + 新模型);typed result invoked=`xiaomi/mimo-v2.6-pro`;
  重试轮交了完整报告(PASS),第 3 轮跑满 25 分钟超时(慢,不是认不出模型)。
- 日志前缀:`/root/aiwork/logs/panel-model-selection-sep22-r2retry`、`/root/aiwork/logs/panel-model-selection-r3`。
- 换模型只改一行:`bin/mimo-model` 由 `submimo` 与 `panel-candidates` 共读(model-selection 已验收)。

## 机器收据

```text
runlog: bash rc=0 commit=1ddd7a4 dirty=yes at=2026-09-22T00:45:11Z file=tracks/leg-models-mimo26-grok47/evidence/20260922T004511Z-01-bash.txt
runlog: bash rc=1 commit=1ddd7a4 dirty=yes at=2026-09-22T00:45:22Z file=tracks/leg-models-mimo26-grok47/evidence/20260922T004522Z-01-bash.txt
runlog: live-probe rc=1 commit=1ddd7a4 dirty=yes at=2026-09-22T00:46:21Z file=tracks/leg-models-mimo26-grok47/evidence/20260922T004621Z-01-live-probe.txt
runlog: resume-tooling rc=78 commit=1ddd7a4 dirty=yes at=2026-09-22T01:12:21Z file=tracks/leg-models-mimo26-grok47/evidence/20260922T011221Z-01-resume-tooling.txt
runlog: resume-tooling rc=0 commit=1ddd7a4 dirty=yes at=2026-09-22T01:13:52Z file=tracks/leg-models-mimo26-grok47/evidence/20260922T011352Z-01-resume-tooling.txt
```

- `bash rc=0`(00:45:11):test-workflow-docs 全绿。
- `bash rc=1`(00:45:22):review-tooling 561/1,唯一红是 V45「判据动了业主真实环境」——
  `mimo/mimocode.json` 内容哈希不变、只有 mtime 在跑的期间变了。同代码串行重跑 562/0(最后一份),
  model-selection 今天三次断网全量(含本单代码)V45 也都绿 ⇒ 不是判据写了它,是同时段别的进程碰了时间戳;是谁没查到。
- `live-probe rc=1`:**探针自己坏了,结论是「没测成」不是「不通」**。L1/L2 两条腿连日志都没生成
  (被拒的原因被探针 `2>&1 >/dev/null` 吞了),P3 那次 MiMo 无任何输出。真跑证据改看上面「验收」一节。
- `resume-tooling rc=78`:GPT 接手时的沙箱不许 `unshare -n`,无出口守卫当场拒跑(守卫在正常工作)。
- `resume-tooling rc=0`:宿主断网重跑,562/0。**这是最后一份。**

## Review

- 外审:见上,由 model-selection 第 3 轮覆盖;本 track 自己没有 panel 绑定。
- 业主追问「换个模型为啥这么麻烦」(GPT 会话里):这次多改脚本是因为 MiMo CLI 0.1.1 的内置表不认当天发布的 2.6;
  以后同类换模型只改 `bin/mimo-model` 一行。已记在 legs.md。
- arbitrated verdict(主裁):**ARCHIVED-SUPERSEDED** —— 实现与验收成立,外审覆盖在 model-selection。

## Accepted deviations

- 本 track 无独立 panel 覆盖(理由见第一节)。
