# Verify: grok-leg-kimi-model

- Date: 2026-09-14

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

## 主 agent 亲跑/亲读发现(09-14 断线接手,读任何 panel 之前)

- **K1 Kimi 型号:GPT 的说法核实成立。** 官方 Kimi Code 文档(models 页 + What's New 09-11):
  `kimi-for-coding` = K2.8 Preview、context `1048576`、effort low/high/max 默认 max、「所有会员档」。
  模板里 1M + max 与之一致。13:12 真跑 subkimi PASS,会话日志 `model=kimi-for-coding thinkingEffort=max`。
  - **V1 运行时回显(14:10,主 agent 亲跑,非判据收据)**:真跑 subkimi(tiny 仓)rc=0、`Conclusion: PASS`;
    随即用它刷新出的 access token(剩 865s,不手动刷新)GET `https://api.kimi.com/coding/v1/models`,HTTP 200,逐字:
    ```
    {"id": "kimi-for-coding", "display_name": "K2.8 Preview", "context_length": 1048576, "supports_reasoning": true}
    {"id": "kimi-for-coding-highspeed", "display_name": "K2.7 Code Highspeed", "context_length": 262144, "supports_reasoning": true}
    {"id": "k3-256k", "display_name": "K3-256k", "context_length": 262144, "supports_reasoning": true}
    {"id": "k3", "display_name": "K3", "context_length": 262144, "supports_reasoning": true}
    ```
    ⇒ 本账号默认模型名字与 1M 上下文都对得上。
  - 顺带坐实:本账号 `k3` 只有 262144 ⇒ **旧默认「k3 = 1M」是写多了**(官方写 K3 的 1M 要 Allegretto+)。
- **K2 「只改一个模型名」只做到一半(不阻断,文档如实写 + 进修腿单)。** 模板对**任何**模型都声明
  `max_context_size = 1048576`、`support_efforts = ["max"]`;名字单源了,能力声明没有。
  换成本账号的 `k3` 或 highspeed,只改 `bin/kimi-model` ⇒ 配置照样声明 1M/max,与服务端不符。
  V40⑦ 还把 1M 断言成常量 ⇒ 这种错**测试全绿**。`kimi-for-coding` 是会被官方原地换指向的别名(09-11 就换过一次)。
  根治方向(修腿单):能力声明取自服务端 `/models`,而不是模板常量。
- **G1 Grok 登录已死,且 subgrok 的凭证处理可疑。** 13:13 debug:`token refresh HTTP error http_status=400
  oauth2_error=invalid_grant` → `auth.refresh.permanent_failure reason=RefreshTokenRejected`。
  subgrok 每次把 `~/.grok/auth.json` 复制进临时 home、跑完连同刷新后的凭证一起删,**从不回写**;
  原件 mtime 仍是 09-09 16:42(=登录时刻)。
  - 已证伪:「刷新令牌一复用就吊销」—— 09-13 13:12~14:06 同一份原件起跑 6 次、5 次 success。
  - 未分辨:绝对寿命到期(约 4 天,落在 09-13 06:06Z 后、09-14 05:13Z 前)vs 轮换+延迟吊销。
  - 判法(要业主先重登):跑一次后比较临时 home 里 refresh_token 的哈希是否变了;变了 ⇒ 丢弃新凭证是 bug。
  - 09-14 业主「算了先不登录grok了 先跳过」⇒ 本单 **Grok 未真跑**;本会话发起的 device-code 登录已停,
    `~/.grok/auth.json` mtime 与刷新令牌哈希前后一致(没被动过)。
- **G2 未登录的腿在轮换池里(不阻断)。** `panel-review` 只看可执行文件在不在就算可用;被轮到时
  1 秒内失败 → 冷却 21600s + 追加备用腿;连败 3 次停轮换。当前健康池只剩 submimo/subdeepseek(glm/kimi/gemini 已停轮换),
  备用腿够用。本单自己的外审显式 `PANEL_GROK_LEG=off`,花名册里会如实印 off。
- **S1 shell + always-approve 不是 Grok 新开的口子。** 快照可写、原仓只读、工具层不断网、临时 home 里的凭证副本
  shell 读得到 —— 与 submimo(review 模式 `bash_perm = "allow"`)、subkimi(Bash 跑本地测试)同一姿态。
  这份共同姿态的风险(提示注入 → 读凭证 → 外发)不在本单范围,记在这里免得被当成 Grok 独有。
- **T 亲读判据改动(闸① 的补偿,因为判据是 GPT 自己写的)**:现有测试**无删断言、无 skip**;
  唯一改写的断言是 V36 `== 'kimi-code/k3'` → `== <bin/kimi-model 的内容>`,默认值从字面量变成配置,等价泛化。
  其余是给新腿补 env 清洗、桩模型名、金样多一格 `subgrok=SKIP(rotation)`。

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
runlog -t grok-leg-kimi-model -- <判据命令>
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
- findings:
  - <...>
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): <...>
  > 这里写理由；最终枚举写进 `decision.json.outcome.verdict`。归档时仍为空会被
  > `track-record validate --phase archive` 挡住，`track list` 也会打 ⚠️。

## Accepted deviations

- <接受的非关键偏差 + 原因 + 影响范围,或 None>
