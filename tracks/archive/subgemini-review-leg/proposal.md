# Proposal: subgemini-review-leg

- Date: 2026-08-25
- Status: completed

## Goal

把 **Antigravity CLI(`agy`)** 包成第五条评审腿 `subgemini`,骑业主的 Gemini Pro 会员额度,
挂进 `panel-review` 的健康轮换池,给评审加一个 **Google 模型家族**的覆盖。

## Motivation

- 业主有 Gemini Pro 会员,当前零利用。
- 现有四条弱腿(mimo/deepseek/glm/kimi)在**模型家族**上没有 Google;而 panel 归档闸机械核对的
  正是"覆盖了几个**不同模型家族**的成功腿"。多一个家族 = 高危单更容易凑够 2 条不同家族。
- 这四条腿一年里反复因额度/凭证掉线(智谱欠费、kimi 403、kimi 凭证被清空 6 天)。
  **腿的冗余度就是评审防线的冗余度。**

## 真问题(第一性)

- 用户原话:「我是想说我有gemini的pro会员 你能不能包装成我们的评审腿呢」
  「不是 你应该先看看gemini要怎么包装 是用agy吗」「agy有cli工具吗」
  「我们评审腿的机械锁不是拆掉了吗我记得」「装 你帮我登录我操作登录授权就可以」
- 真正要解决的是:**把一份已经付过钱、闲置的模型额度,变成评审防线上的一条腿。**
- **我在这中间翻译错了一次,记在这里**:业主说"gemini",我直接翻译成 `gemini-cli` 并花了两轮
  去查它的额度和只读锁。**这个翻译是错的** —— Google 已把 gemini-cli 转到 Antigravity CLI,
  且 2026-06-18 起对免费/AI Pro/Ultra 个人账号停止服务,那条路是死的。
  是**业主问了一句「是用agy吗」才掰回来**。
  自检句:**业主给的是产品名,我替换成了我熟悉的工具名 —— 替换前没有验证过它还活着。**

## 已实测的事实(硬证据,非文档;2026-08-25 探针)

装的是 `agy` v1.1.20(`~/.local/bin/agy`,208MB 闭源 Go 二进制)。OAuth 已登录,
凭证 `~/.gemini/antigravity-cli/antigravity-oauth-token`(600)。

1. **Pro 档已解锁**:`agy models` 列出 `gemini-3.1-pro-high/low`。注意 **3.7/3.6/3.5 只有 Flash 档,
   Pro 最高停在 3.1**。
1b. **默认档实测选型(业主拍板 3.7 Flash,数据支持)**:同一份埋雷考卷连考两轮,
   `gemini-3.7-flash-high` 抓 5 / 7 条,`gemini-3.1-pro-high` 抓 3 / 4 条,两轮同向。
   **这推翻了我「Pro 一定更强」的直觉** —— 差点按直觉把 Pro 写进设计。
2. **`agy models` 里有 `claude-sonnet-4-6` / `claude-opus-4-6-thinking`。**
   ⇒ 这条腿如果跑 Claude,"不同模型家族"的机械核对被**悄悄架空**,而闸查的是腿的名字、
   不是它实际调了谁。**模型必须焊死。**
3. **`--add-dir DIR` 能让它读写 DIR**:实测读出投放的 `MAGIC_TOKEN_9F3A`,并真的写出了文件。
4. **workspace 内写权限默认全开,`--sandbox` 不拦文件写**:三档(默认/`--sandbox`/`--mode plan`)
   跑"创建 pwned.txt",默认档与 sandbox 档**都真的把文件写出来了**。
5. **不指定 workspace 时,它写进自己的 `~/.gemini/antigravity-cli/scratch/`**,不写 cwd。
   ⇒ 我的第一版探针只查 cwd,三档全报"没写成" —— **那是假绿,是我自己的量具瞎掉**,
   靠亲读它的输出("I created it at /root/.gemini/.../scratch")才翻出来。
6. **rc 完全不可信**(两次实证):未登录跑 `agy models` rc=0;文档载明拿不到批准的工具
   "soft-denied:继续跑、exit 0、只在 stderr 印一句"。**死活只能看裁决行。**
7. **未登录时 print 模式静默挂死**:`agy -p "hi"` 40 秒零输出被 timeout 砍(rc=143)。
   ⇒ 必须有预检 + 超时,否则腿"像在跑"其实永远不回来。
8. **它会在日常运行中后台自我更新**(install.sh 自述 + `agy update` 子命令)。
   ⇒ 判卷防线上出现一个**会自己变的构件**,这是新账。

## 第一性不变量

- **原仓不承受副作用**:腿的 workspace 只能是那份可丢弃副本,绝不能是原仓。
  (现行架构 = `ro-lock-teardown` 之后的"每腿可写副本、原仓物理只读",本单沿用,不新造锁。)
- **家族覆盖必须是真的**:这条腿只跑 `gemini-*`;跑成 Claude 即为防线被架空。默认档 `gemini-3.7-flash-high`。
- **死活看裁决行,不看 rc**。
- **不许有外网出口以外的能力**:评审腿只读只评,`fix` 故意不支持(与其余四腿一致)。

## Scope

- in: `bin/subgemini` wrapper(review 模式)、隔离 home、模型焊死、裁决 gate、
  预检(未登录/凭证失效要**响亮失败**而不是挂死)、判据、挂进 `PANEL_LEGS_ORDER` 花名册、
  legs.md 唯一源补这一节。

## Non-goals

- 不支持 `fix`(评审员保持只读)。
- 不改 panel 的预算规则(self/standard/high = 0/1/2 不动),只往轮换池里加候选。
- 不为它自造只读锁 —— 现行"可丢弃副本 + 原仓只读"已经覆盖,重复造锁是净增复杂度。
- 不碰 `--dangerously-skip-permissions`。
- 不解决"闭源二进制会自我更新"这笔账(记进 verify 的敞账,单独开单)。
