# Proposal: leg-models-mimo26-grok47

- Date: 2026-09-22
- Status: open

## Goal

MiMo 评审/执行腿默认模型换成今天发布的 `mimo-v2.6-pro`;Cursor 评审/发散腿换成 `grok-4.7-high`。
MiMo 顺带改成和 Kimi/Cursor/Grok 同一约定:模型名只放 `bin/mimo-model` 一行。

## 真问题(第一性)

- 用户原话:「先帮我吧mimo的腿模型换成2.6pro」「还有cursor腿是不是出grok4.7了也换一下吧」
  「你看一下mimo的文档啊」「模型名要对吧」「我们之前不是搞过了吗 只要改模型名就可以用」「为什么还是这么复杂」
- 真正要解决的是:两条腿跑上新模型,且以后换模型只改一个名字(09-13 业主原话同一诉求,见 archive/grok-leg-kimi-model)。
- 我在这中间翻译了什么:「2.6pro」→ 服务端 `/v1/models` 与官方页面给出的 id `mimo-v2.6-pro`;
  「grok4.7」→ Cursor 模型表里与现役 `cursor-grok-4.6-high` 同档的 `grok-4.7-high`。
- 用户可观察的成功:真跑两条腿时,运行中的腿回报的是新模型(Cursor 摘要里的模型名 / MiMo 真打到服务端的 id),不报错。

## Scope

- in: `bin/cursor-model` 一行;`bin/mimo-model` 新文件 + `submimo` 读它并在运行时把 `xiaomi/` 模型登记给 MiMo CLI;
  对应判据 V36/W3;`legs.md` 两处默认值。

## Non-goals

- 不升级 MiMo CLI(0.1.1 → 0.1.14 跨 13 版,评审锁的工具名清单可能变;且新版也早于 2.6 发布,不解决问题)。
- 不动 `submimo-review`(chat 引擎的 `MIMO_MODEL` 默认值,那是 subchat 的另一条路,不是 MiMo 腿)。
- 不动 OpenClaw/定时任务用的 MiMo 模型。

## 验收边界与轮次预算

- 这一单承诺:两条腿默认模型为新 id 且真跑通;MiMo 换模型只改 `bin/mimo-model`;运行时登记不改变评审档的锁。
- 不承诺:MiMo CLI 以后的版本仍认 `MIMOCODE_CONFIG_CONTENT`(升级 CLI 时 V36 那条登记断言只测到 submimo 传没传,真认不认要真跑)。
- 实质评审上限:2 轮。每轮派发前先跑 `track preflight leg-models-mimo26-grok47`。
