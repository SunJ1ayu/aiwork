# Design: subgemini-review-leg

- Date: 2026-08-25

## 方向(不是开放分叉,不花 panel-explore)

形状已经被现有四条腿定死了:**厂商原生 agent CLI 当底座 + 换 HOME 隔离 + 裁决 gate + 只读评审**。
`subkimi` 就是同构样板(`kimi -p` ↔ `agy -p`)。这里没有几个"都说得通的方向",
唯一真正要定的是**隔离与凭证怎么接**,而那已被下面的实测钉死。
⇒ `design-uncertainty: low`,不花规划双出。

## 底座与调用形状

```
env HOME=$AGY_REVIEW_HOME agy -p "<评审任务书>" \
    --model gemini-3.7-flash-high --add-dir <可丢弃副本> --output-format text
```

- **默认模型 `gemini-3.7-flash-high`**(业主 2026-08-25 拍板)。
  依据不是直觉:同卷两轮 3.7-flash-high 抓 5/7 条、3.1-pro-high 抓 3/4 条,两轮同向。
  **我的直觉("Pro 一定更强")被这两轮推翻,差点写进设计。**
- **模型必须匹配 `^gemini-` —— 这是硬闸,不是默认值。** `agy models` 同时提供
  `claude-sonnet-4-6` / `claude-opus-4-6-thinking` / `gpt-oss-120b`;这条腿一旦跑 Claude,
  panel 归档闸的"不同模型家族覆盖"就被架空,**而闸查的是腿名、不是它实际调了谁**。
  `AGY_MODEL` 可覆盖档位,但非 `gemini-*` 一律拒跑。

## 隔离与凭证(全部已实测,2026-08-25)

agy 没有专用 home 变量,路径从 `$HOME` 拼。⇒ 换 `HOME` 即整体重定向,与 subglm 的
`OPENCODE_REVIEW_HOME` 同形。

- `AGY_REVIEW_HOME`,默认 `~/.cache/aiwork/agy-review-home`(**仓外**,受
  `_review-home-guard.sh` 管:运行期 home 落在被评审的仓里要拒跑)。
- **凭证用「复制」不用「符号链接」**,权限 600,每次派发前从业主 home 重新拷一份最新的。
  - 实测甲:换 HOME 且不给凭证 ⇒ `Please sign in` **正确失败**(隔离是真的)。
  - 实测乙:换 HOME + 只复制 token ⇒ `agy models` 正常列出(凭证够用)。
  - 实测丙:两次跑完,业主 `~/.gemini/.../antigravity-oauth-token` 时间戳未变(没被碰)。
  - token 内含 `refresh_token` ⇒ 副本能自己刷新,不会因 access_token 过期而死;
    **也因此副本是长期凭证,必须 600。**
  - **为什么不用 subkimi 那种符号链接**:链接是通向沙箱外的写通道。
    `panel-kimi-credential-wipe` 那一单的根因就是"夹具把通向沙箱外的链接带进来"。
    这里没有理由重蹈,复制是净胜。

## 只读边界(沿用现行架构,不新造锁)

`ro-lock-teardown`(08-19 归档)之后的现行形态 = **每腿一份可丢弃可写副本 + 原仓物理只读**。
实测 agy 的默认权限恰好契合:workspace 内读写全开、`--sandbox` 不拦文件写、
不给 workspace 时它写进自己的 `scratch/`。
⇒ **把 `--add-dir` 指到那份副本即可**,不跟它的权限系统搏斗,不为它单造第二把锁。
`--mode plan` 实测只出计划不执行,但**未验证它是机械锁还是模型自觉**
(opencode 的 plan 档就是自称禁编辑、实际全开)⇒ **本单不把它当防线用**。

## 失败模式(这条腿不老实,判据要盯死)

| 实测现象 | 后果 | 对策 |
|---|---|---|
| 未登录 `agy models` 仍 `rc=0` | rc 判死活 = 假绿 | **只看裁决行** |
| 未登录 `agy -p` 静默挂死(40s 零输出) | 腿"像在跑"其实永不返回 | 派发前预检 + 硬超时 |
| 工具拿不到批准 = soft-deny,继续跑 exit 0 | 同上 | 同上 |
| 闭源二进制会后台自我更新 | 判卷防线上有个自己会变的构件 | 本单记敞账,单开一单 |

## 测试策略(oracle —— 主 agent 亲自写,判据先行)

判据 `tests/test-subgemini.sh`,**先 commit 判据、红过、再 commit 实现**。至少覆盖:

1. **模型闸**:`AGY_MODEL=claude-opus-4-6-thinking` 必须**拒跑**并说出真因;
   `AGY_MODEL=gemini-3.6-flash-high` 放行;默认值确实是 `gemini-3.7-flash-high`。
2. **隔离闸**:整轮跑完,业主 `~/.gemini/antigravity-cli/` 下**没有任何文件被修改**
   (比对 mtime+sha);评审 home 里的凭证是**普通文件不是 symlink**;权限 600。
3. **仓外闸**:运行期 home 落在被评审仓内 ⇒ 拒跑(复用 `_review-home-guard.sh`)。
4. **响亮失败**:凭证缺失/失效时 **非零退出 + 明确错误**,不许挂死、不许静默 PASS。
5. **rc 不可信**:构造"rc=0 但输出里没有裁决行" ⇒ wrapper 必须判失败。
6. **裁决 gate**:三种结论都认得出;`Conclusion:` 全角冒号不许误判。
7. **fix 拒绝**:`subgemini fix` 必须拒绝(与其余四腿一致)。
8. **花名册**:`PANEL_LEGS_ORDER` 含 `subgemini`;`panel-roster` 能从盘上把它渲染出来。
9. **红检(变异测试)**:上述每条判据都要证明"改坏实现时它真的会红",
   尤其第 1、2、5 条 —— 这三条是本单的防线核心。

## 敞账(不在本单解决,写下来防止变成默认设计)

- **闭源二进制自我更新**:`agy update` + 后台自更新。判卷防线上出现会自己变的构件。
- **`--mode plan` 是不是机械锁**未验证;本单不依赖它。
- **数据收集已在首次向导里关闭**(业主选的),但这是 agy 自己的 settings,
  换 HOME 后评审 home 是一份新 settings —— **评审 home 里必须同样关掉**,否则
  业主关的那次对腿不生效。已列入 tasks。
