# 各评审腿的后端细节

平时不用读。改模型 / 换 key / 某条腿死了排查时再看。

**所有腿共同的安全姿态**:输出只是**证据**,不是决定;绝不让它自己拍板;
task 存 `/root/aiwork/tasks/`,log 存 `/root/aiwork/logs/`。
**`fix` 只由 `submimo fix` 承担**——其余各腿的 `fix` 都是**故意不支持**的,评审员保持只读。

---

## submimo (MiMo) — 第一条腿,且是唯一的 fix 腿

`/root/aiwork/bin/submimo`,默认模型 `xiaomi/mimo-v2.5-pro`。
`submimo review TASK LOG REPO` 用于评审;`submimo fix` 的规矩见 **`delegate` skill**。

## subdeepseek (DeepSeek) — 第二条腿

`/root/aiwork/bin/subdeepseek`,DeepSeek 官方 API,两条腿共用一把 key
(`~/.config/deepseek/auth.json`)。**只读评审**。
旧名(`subsense`、`PANEL_SENSE_LEG`、provider `sensenova`)**已彻底删除,没有别名**。

- **agent 腿(默认)**:`subdeepseek-agent`,DeepSeek 跑在 Claude Code 壳上,打
  Anthropic 兼容端点 `api.deepseek.com/anthropic`。评审员**自己读仓库**(只读工具白名单),
  所以没有盲评、也没有"commit 之后 diff 变空"的问题。`panel-review` 自动选它;
  `PANEL_DEEPSEEK_LEG=chat` 强制回落 chat 腿。默认轮次上限 **200**(40、80 都撞过墙，
  后按单文件实测 56 轮外推并钉住)。
- **chat 腿(回落)**:`subdeepseek review TASK LOG REPO`,走官方 chat-completions
  (`api.deepseek.com`),自动附上 REPO 的 `git diff`。
  默认模型 **`deepseek-v4-flash`**，轮次上限 **200**(2026-07-25 起;官方端点只认 `deepseek-v4-flash` /
  `deepseek-v4-pro`,老的 `deepseek-chat`/`deepseek-reasoner` 已下架——两条腿当天双双 400
  就是这个原因)。要更强一档用 `DEEPSEEK_MODEL=deepseek-v4-pro`。
  加文件用 `DEEPSEEK_INCLUDE`(panel 里用 `PANEL_INCLUDE` 一次喂两条 chat 腿)。

## subglm (GLM 模型,跑在 OpenCode Go 上) — 第三条腿

**底座 = opencode CLI 自己**(2026-08-18 晚,track opencode-agent-base)。
和 subkimi 用原生 kimi-code、submimo 用官方 MiMoCode 是同一个形状 ——
四条腿里三条现在都跑在厂商自己的 agent 底座上,只有 DeepSeek 还借 Claude Code 当壳
(它的 Anthropic 面做工具格式转换,借壳对它是通的)。

`/root/aiwork/bin/subglm-agent`(底座腿,默认)/ `bin/subglm`(聊天腿),**只读评审**。

- **后端 = OpenCode Go**(2026-08-18 从智谱开放平台 bigmodel 换过来,业主的 $10/月订阅),
  **默认模型 `glm-5.3`**。换的理由是 bigmodel 那把 key 欠费(1113),这条腿 08-04 起
  默认关着、四审实际只有三腿两周。后端沿革:bigmodel → 百炼(429)→ 火山方舟(07-17)
  → 07-25 切回 bigmodel → **08-18 OpenCode Go**。
  旧 key 原样留在 `~/.config/zhipu/auth.json`(另一家的账,充值可切回),方舟 key 在
  `auth.json.ark-bak`。
- **认证 header 风格不一样,这是换后端时最容易栽的地方**:Go 的 Anthropic 面**只认
  `x-api-key`**(= `ANTHROPIC_API_KEY`);用 `Authorization: Bearer`(= `ANTHROPIC_AUTH_TOKEN`,
  deepseek 腿走的那种)实测直接 401 `Missing API key`。key 传对、header 传错 ⇒ 腿是死的,
  而日志上只看得见"模型没回话"。`subagent` 供应商表里的 `AUTH_ENV` 一格就是为它设的。
- 端点:chat = `opencode.ai/zen/go/v1/chat/completions`,agent = `opencode.ai/zen/go`
  **(底座腿这个不带 `/v1`)**。claude CLI 自己会补 `/v1/messages`,写成 `.../go/v1`
  会打到 `/zen/go/v1/v1/messages`(404),而 CLI 把这个 404 报成**「模型不存在」**——
  地址 bug 伪装成模型名 bug,08-18 照着"模型名错"查了半天。
- **聊天腿必须带 User-Agent**:urllib 的默认 UA(`Python-urllib/3.x`)被 Cloudflare
  前置的端点 403(error code 1010)。同一个请求 curl 200 / urllib 403,只差这一行。
- **Go 上有哪些 glm 档**(08-18 实测 `/v1/models`):`glm-5` `glm-5.1` `glm-5.2` `glm-5.3`。
  **`glm-4.6` 系在 Go 上不支持**(报 `ModelError: Model glm-4.6 is not supported`)——
  所以这次不是"顺便升个档",是老默认值在新后端上根本跑不起来。
  默认已在 08-20 经业主确认切到 `glm-5.3`；模型变化必须同时改实现、判据与本唯一源。
- key 来自 `ZHIPU_API_KEY` 或 `~/.config/opencode-go/auth.json`(`{"key":"..."}`,权限 600);
  模型覆盖 `ZHIPU_MODEL`,加文件 `ZHIPU_INCLUDE`。
  (**env 变量名仍是 `ZHIPU_*`**:它是"第三条腿"的前缀,不是"智谱"的缩写。改名要动
  供应商表、判据、文档三处,这单不做 —— 但别被名字骗了,它现在打的是 OpenCode Go。)
- **agent 腿(07-05 起是默认,08-18 起不是了 —— 见下一条)**:`subglm-agent`,GLM 跑在 Claude Code 壳上
  (headless `claude -p` 打 OpenCode Go 的 Anthropic 兼容端点,env **只按次注入,绝不写进
  `~/.claude/settings.json`**)。评审员自己读仓库(Read/Glob/Grep + 只读 git;
  Write/Edit/subagent 硬禁),无盲评、无需手工喂 INCLUDE,和引擎一样有裁决 gate。
  `PANEL_GLM_LEG=chat` 强制回落,`PANEL_GLM_LEG=off` 关掉。烧订阅额度,不烧 Claude 额度。
- **为什么不再借 Claude Code 当壳**(08-18 白天踩的坑,记着别走回头路):Go 的
  Anthropic 面**不做工具格式转换**,带 Anthropic 形状的 tools 一律 400
  「Missing required input field: `tools[0].function.name`」(实测三档:无工具 200 /
  Anthropic 形状 400 / OpenAI 形状 200)。借壳那条路上这条腿只能退化成看不见仓库的聊天腿。
  换成 opencode 自己当底座之后,工具形状天然对得上,能力回来了。
- **panel-review / panel-explore 里默认开着,默认档 = 底座腿 `agent`**。
  `PANEL_GLM_LEG=chat` 强制回落聊天腿,`off` 关掉。
  每 5 小时约 880 次请求的订阅额度,评审腿这种用量够用。
- **只读是机械锁,不是模型自觉**:配置里 write/edit/patch/task/todowrite/webfetch/
  websearch/skill 全关;bash 留着跑只读 git,但是白名单(`*` deny + 只放行
  git diff/log/status/show)。实测这是真闸(模型真去调、被 harness 拦回),
  连 `git log && echo x > f` 这种链式绕法也拒得掉(它解析命令,不是傻前缀匹配)。
  ⚠️ **别用 opencode 内置的 `plan` 档**:它自称「禁掉所有编辑工具」,实际解析出来
  write/edit/bash 全开 + 权限 `*` allow,两次不写文件靠的都是模型自觉。
- **三个只有真跑才会撞见的坑**(都已在代码里焊死,写这儿是给下一个换底座的人):
  ① **rc 信不得** —— 余额不足时它把错误打在 stdout、退出码仍是 0 ⇒ 判死活只能看裁决行;
  ② **stdin 必须接 `/dev/null`** —— stdin 是开着的管道时它会一直等输入,
     直接跑正常、经 runlog(走 tee 管道)就挂死 12 分钟,而日志头已写好、像在跑;
  ③ **默认 provider 是按量付费网关**(`Insufficient balance`),订阅要自定义 provider
     指到 `/zen/go/v1`;首次在全新的隔离 home 里跑会下 ~156M 运行时,会明显慢一次。
- 隔离:`OPENCODE_REVIEW_HOME`(默认 `~/.cache/aiwork/opencode-review-home`)——
  换 HOME 即整体重定向配置/数据/状态,和 subkimi 的 `KIMI_CODE_HOME` 同形。
  配置每次重写(它就是只读锁本身,不留隔夜残留),权限 600(里面有 key)。
- 轮次上限在配置的 `steps` 字段(opencode 没有命令行开关,schema 里 `maxSteps` 已废弃),
  取供应商表里那个历史值 40 —— 换底座不许把上限弄丢。

## subkimi (月之暗面 Kimi) — 第四条腿

`/root/aiwork/bin/subkimi`,Kimi 会员 OAuth,**从第一天起就是 agent 底座**:跑原生
`kimi-code` CLI 的 headless 模式(`kimi -p`),评审员自己读仓库,无盲评、无需喂 INCLUDE。

- `subkimi review TASK LOG REPO`,裁决 gate 为 `Conclusion: PASS|BLOCK|NEEDS_MORE_INFO`。
  默认模型 `kimi-code/k3`(K3,1M 上下文,effort=max);
  `KIMI_MODEL=kimi-code/kimi-for-coding` 切到 K2.7 编程调优版。超时 `KIMI_TIMEOUT`(默认 1500s)。
- **隔离**:跑在 `KIMI_CODE_HOME=/root/aiwork/kimi-review-home`(绝不碰全局 `~/.kimi-code`)。
  该 home 的配置带一个 PreToolUse 守卫 hook(`hooks/guard.mjs`,**默认 DENY**):只放行
  Read/Glob/Grep/todo 类工具 + 不含元字符的只读 git;Write/Edit/Agent/AgentSwarm/Skill/
  Cron*/FetchURL/WebSearch 及任何未知工具一律拦截。
  **kimi-code 的 hook 协议是 FAIL-OPEN 的**(非 0/2 退出码 = 放行),所以 `subkimi` 会先用
  一次 canary Write 预检守卫,**不 DENY 就拒绝派发**——沙箱坏了要让工具停,而不是悄悄变弱。
- auth:Kimi 会员 OAuth token,通过 `credentials` 符号链接共享进评审 home(`kimi login`
  刷新一次即可)。烧 Kimi 会员额度,不烧 Claude。
- `panel-review` 把它纳入健康轮换池(`PANEL_KIMI_LEG=off` 关闭)，只有被预算选中或条件
  升级时才实际派出；**没有 chat 回落**。

## codex (GPT-5.6-Sol) — 第五条腿,frontier 档,2026-07-26 起

**还没有包成脚本,当前是主 agent 手动并排拉起。** 参见 [[codex-as-employee]] 记忆。

```
codex exec -C REPO -s read-only -o PREFIX.codex.log "评审任务书(要求中文回答)"
```

- 与前四条的关键差别:**它不是弱模型**。前四条是弱模型,共同假阴性是它们结构上的盲区;
  补一条 frontier 腿的价值 > 补第五条弱腿。
- **`-s read-only` 必须带**——评审员不该有写权限。
- **额度**:走 ChatGPT 订阅(`auth_mode=chatgpt`),不烧 Claude 额度。
- `--output-schema FILE` 可以让它按 JSON Schema 输出裁决,比正则匹配 "Conclusion:" 稳
  (中文全角冒号误判那笔工具债的正解)。
- **不需要**再加 `-c project_doc_max_bytes=0`:2026-07-26 起本机说明书叫 `CLAUDE.md`,
  Codex 只认 `AGENTS.md`,结构上就读不到,忘不忘都一样。
- `panel-review` **不需要**为它改代码——那个工具只是个并行派发器,手动并排拉一条腿即可。
  等它变成常规动作再考虑包成 `subcodex`(理由只能是"让两个 flag 忘不掉",不是为了好看)。
