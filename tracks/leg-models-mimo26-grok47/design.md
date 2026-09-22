# Design: leg-models-mimo26-grok47

- Change: leg-models-mimo26-grok47
- Status: decided

## Goal-to-design check

- 当前行为 → 拟改变的行为:MiMo 腿跑 `xiaomi/mimo-v2.5-pro`(写死在 submimo),Cursor 腿跑 `cursor-grok-4.6-high`
  → 分别跑 `xiaomi/mimo-v2.6-pro` / `grok-4.7-high`;业主不付出任何新步骤。
- 检查深度与触发事实:直接验证 + 最小实验。不新增用户步骤、不改默认动作之外的契约,改名可一行撤回 ⇒ 不做独立方案挑战。
- 关键前提(均已实验,收据见 evidence/):
  1. `mimo-v2.6-pro` 是真 id:套餐 `/v1/models` 列出它;官方 mimo.mi.com 称 flagship `mimo-v2.6-pro`。
  2. 只改名跑不起来:`mimo run -m xiaomi/mimo-v2.6-pro` → `Model not found`(CLI 0.1.1 自带表 xiaomi 下只到 2.5)。
  3. 官方仓写法 `provider.xiaomi.models.<id>` 登记后可用;经 `MIMOCODE_CONFIG_CONTENT` 注入 → 真跑成功。
  4. 反向对照:登记假 id `mimo-v9.9-bogus` → 服务端 `Unsupported model` ⇒ id 确实由服务端校验,成功不是 CLI 自说自话。
  5. 锁不变:同一 XDG 锁配置下加/不加注入,`mimo debug agent aiwork-review` 排序后逐字节一致(只有技能目录枚举顺序不同)。
  6. Cursor:`cursor-agent --list-models` 有 `grok-4.7-high`;家族解析为 xai(与 4.6 同族,覆盖计数不变)。
- 完全实现仍可能失败:MiMo 官方更新 CLI 模型表后,我们的登记与表里的值冲突 —— 登记值照抄 2.5-pro(1M/128K/交错思考),
  与第三方表里 2.6-pro 一致,合并后不变。
- 未解决项:无。

## Approach

- `bin/cursor-model` → `grok-4.7-high`。
- `bin/mimo-model` = `xiaomi/mimo-v2.6-pro`;`submimo` 的 `DEFAULT_MODEL` 从它读(找不到时回落 `/root/aiwork/bin/mimo-model`,与同文件其他组件同一写法)。
- `submimo` 对 `xiaomi/*` 模型在命令前加 `env MIMOCODE_CONFIG_CONTENT=<只含 provider 段的登记>`;review/explore/fix 三种模式共用。

## Alternatives considered

- 升级 MiMo CLI:0.1.14 发布于 09-02,早于 2.6 发布,不带新表;且改动评审锁依赖的工具名面。否。
- 把登记写进评审锁那份 mimocode.json:只覆盖 review/explore,fix 与 submimo-iso 还得另写两处。否。
- 只改名等上游表更新:时间不可知。否。

## Test strategy (oracle)

- V36(已改):facts 里 requested/invoked == `bin/mimo-model`;假 mimo 收到的 `MIMOCODE_CONFIG_CONTENT` 只含 provider 段、登记了该模型。
- W3(已改):submimo 读 `/mimo-model`、不再写死 `DEFAULT_MODEL="xiaomi/`、legs.md 写的就是文件里的模型。
- 现场:真跑 `submimo review` 与 `subcursor`,看运行中的腿回报的模型。

**这个 oracle 能被什么骗过?** V36 用假 mimo,只证明 submimo 传了登记,不证明真 CLI 认;真认要靠现场真跑
(假 id 反向对照已证明服务端校验 id)。
