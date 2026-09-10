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
  加文件用 `DEEPSEEK_INCLUDE`(panel 里用 `PANEL_INCLUDE` 一次喂两条 chat 腿)。

两条路径的默认模型统一读取 **`bin/deepseek-model`**（一行 API 模型名）。
以后换 DS 默认档只改这个文件；agent、chat 回落和两条入口的 `--help` 自动跟随，
无需修改测试里的版本号或本说明。`DEEPSEEK_MODEL` 非空时仍优先用于本次调用。
测试用临时配置中的虚构模型名核对传参与事实记录，历史账本夹具不代表当前默认档。


## subglm (GLM 模型,跑在 OpenCode Go 上) — 第三条腿

**底座 = opencode CLI 自己**(2026-08-18 晚,track opencode-agent-base)。
和 subkimi 用原生 kimi-code、submimo 用官方 MiMoCode 是同一个形状 ——
当前池里只有 DeepSeek 还借 Claude Code 当壳,其余 agent 腿都跑各自的原生底座
(它的 Anthropic 面做工具格式转换,借壳对它是通的)。

`/root/aiwork/bin/subglm-agent`(底座腿,默认)/ `bin/subglm`(聊天腿),**只读评审**。

- **后端 = OpenCode Go**(2026-08-18 从智谱开放平台 bigmodel 换过来,业主的 $10/月订阅),
  **默认模型 `glm-5.3-flash`**。换的理由是 bigmodel 那把 key 欠费(1113),这条腿 08-04 起
  默认关着、四审实际只有三腿两周。后端沿革:bigmodel → 百炼(429)→ 火山方舟(07-17)
  → 07-25 切回 bigmodel → **08-18 OpenCode Go**。
  旧 key 原样留在 `~/.config/zhipu/auth.json`(另一家的账,充值可切回),方舟 key 在
  `auth.json.ark-bak`。
- **当前 agent 认证路径**:`subglm-agent` 把 key 写进隔离 OpenCode provider 配置的
  `apiKey` 字段(配置创建即 600，key 不走 argv)；chat 回落腿走
  `Authorization: Bearer`。供应商表里的 `AUTH_ENV=ANTHROPIC_API_KEY` 是旧 Claude 壳路径
  留下的休眠配置，不是当前 OpenCode agent 的认证通道。
- 端点:chat = `opencode.ai/zen/go/v1/chat/completions`,当前 agent =
  `opencode.ai/zen/go/v1`(OpenAI-compatible provider base)。历史 Claude 壳路径才使用
  不带 `/v1` 的 `opencode.ai/zen/go`，因为 claude CLI 会自己补 `/v1/messages`；两条路径
  不能混写，否则会把已退场底座的约束冒充成当前契约。
- **聊天腿必须带 User-Agent**:urllib 的默认 UA(`Python-urllib/3.x`)被 Cloudflare
  前置的端点 403(error code 1010)。同一个请求 curl 200 / urllib 403,只差这一行。
- **Go 上有哪些 glm 档**(08-27 实测 `/v1/models`):`glm-5` `glm-5.1` `glm-5.2`
  `glm-5.3` `glm-5.3-flash`。
  **`glm-4.6` 系在 Go 上不支持**(报 `ModelError: Model glm-4.6 is not supported`)——
  所以这次不是"顺便升个档",是老默认值在新后端上根本跑不起来。
  默认 08-20 切到 `glm-5.3`，08-27 经业主确认切到 `glm-5.3-flash`。两档走同一
  OpenAI-compatible 端点；变化的是模型 ID，不联动端点、认证、权限或底座。
- key 来自 `ZHIPU_API_KEY` 或 `~/.config/opencode-go/auth.json`(`{"key":"..."}`,权限 600);
  模型覆盖 `ZHIPU_MODEL`,加文件 `ZHIPU_INCLUDE`。
  (**env 变量名仍是 `ZHIPU_*`**:它是"第三条腿"的前缀,不是"智谱"的缩写。改名要动
  供应商表、判据、文档三处,这单不做 —— 但别被名字骗了,它现在打的是 OpenCode Go。)
- **agent 腿(默认)，底座是 opencode CLI**:`subglm-agent` 用隔离 HOME 生成只读 agent
  配置后 headless 运行 `opencode run`。评审员自己读仓库、在可丢弃副本里跑本地判据；
  Write/Edit/Task/联网工具关闭，原仓由外层只读挂载保护。无盲评、无需手工喂 INCLUDE，
  和 chat 引擎一样有裁决 gate。烧 OpenCode Go 订阅额度，不烧 Claude 额度。
- **为什么不再借 Claude Code 当壳**(08-18 白天踩的坑,记着别走回头路):Go 的
  Anthropic 面**不做工具格式转换**,带 Anthropic 形状的 tools 一律 400
  「Missing required input field: `tools[0].function.name`」(实测三档:无工具 200 /
  Anthropic 形状 400 / OpenAI 形状 200)。借壳那条路上这条腿只能退化成看不见仓库的聊天腿。
  换成 opencode 自己当底座之后,工具形状天然对得上,能力回来了。
- **panel-review / panel-explore 里默认开着,默认档 = 底座腿 `agent`**。
  `PANEL_GLM_LEG=chat` 强制回落聊天腿,`off` 关掉。
  当前官方估算每 5 小时约 1,580 次 Flash 请求,评审腿这种用量够用。
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

## subkimi (月之暗面 Kimi) — 轮换池成员

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

## subgemini (Gemini,跑在 Antigravity CLI 上) — 轮换池成员,2026-08-25 起加入

`/root/aiwork/bin/subgemini`,**只读评审**,没有 chat 回落。骑业主的 **Gemini 会员**
OAuth(`auth_method=consumer`),不烧 Claude 额度、也不需要 API key。
底座是 **Antigravity CLI(`agy`)** 的 headless 模式(`agy -p`),和 subkimi 的
`kimi -p` 同形 —— 评审员自己读仓库,无盲评、无需喂 INCLUDE。

- **为什么不是 gemini-cli**:Google 已把 gemini-cli 转到 Antigravity CLI,
  且 **2026-06-18 起 gemini-cli 对免费 / AI Pro / Ultra 个人账号停止服务**。
  那条路是死的,别再走回去。
- **默认模型 `gemini-3.8-flash-high`**(业主 2026-09-04 说换,track `gemini-leg-38`)。
  **注意 Flash 档一路更新,而 Pro 最高停在 3.1** —— "用最新的"和
  "用最大的"在这里是两个方向。
  ⚠️ **3.8 的证据档次低于 3.7,这是业主明确拍板接受的,不是疏忽**:
  3.7 当初过了**埋雷考卷**才定(同一份卷连考两轮,`gemini-3.7-flash-high` 抓 5 / 7 条,
  `gemini-3.1-pro-high` 抓 3 / 4 条,两轮同向);**3.8 只过了"存在 + 真链冒烟"**,没重考。
  **2026-09-04 业主决定:① 就用 3.8,不重考;② 以后同为 gemini 家族内换档,
  改一行即可,不必再走 track。** 这两条是业主签的字 ——
  评审腿(DeepSeek F2)当时的意见正是"这个取舍不能由提出放松的人自己认下",故记在此处。
  代价说清:**"默认档够不够强"从此不由机器保证**;真出现"评审突然变水"的现象,
  第一个该看的就是这里。
- 判据只钉"必须是 `gemini-*` 且 `--model` 真被传给 agy"(V46①②),**不钉版本号** ——
  版本号是本文件与 `bin/subgemini` 的第二份拷贝,钉了就会过期
  (2026-09-04 实证:3.7→3.8 那天本文件就是错的,而它没让任何判据变红)。
  现在 `tests/test-workflow-docs.sh` W3 加了 gemini 那一行,文档与代码对不上会红。
- **🔴 模型是硬闸,不是默认值**:`AGY_MODEL` 可覆盖,但 **非 `gemini-*` 一律拒跑**。
  `agy models` 同时供应 `claude-sonnet-4-6` / `claude-opus-4-6-thinking` /
  `gpt-oss-120b`。这条腿在花名册里代表 **Google 家族**,它跑成 Claude 会让归档闸的
  「覆盖 N 个不同模型家族」变成一句假话 —— **而那道闸查的是腿名,查不出模型**。
- **隔离靠换 `HOME`**:agy 没有专用 home 变量(路径从 `$HOME` 拼),
  所以 `AGY_REVIEW_HOME`(默认 `~/.cache/aiwork/agy-review-home`,**仓外**)
  整体重定向配置/数据/状态,与 subglm 的 `OPENCODE_REVIEW_HOME` 同形。
- **凭证用「复制」不用「符号链接」**,600,每次派发前重拷一份最新的,**跑完即删**。
  链接是通向沙箱外的写通道,`panel-kimi-credential-wipe` 的根因就是它;
  而掉 agy 登录**不可逆**,只有业主本人能开浏览器重走 OAuth(SSH 环境下 agy 会
  打印授权网址 + 要人贴回一次性码,`agy` 是 TUI,**没有 `login` 子命令**)。
  token 内含 `refresh_token` ⇒ 副本能自己刷新,不会因 access_token 过期而死 ——
  也正因为它是一份**能自己刷新的长期凭证**,跑完必须删掉,不许在盘上过夜:
  多一份泄漏面,而闭源二进制若做 refresh-token 轮换,副本抢先刷新就可能把业主的
  登录刷失效。2026-08-26 之前它跑完一直留着(四审两条腿都点了这处),判据 V46⑬。
- **同一个评审 home 同一时刻只许一条腿用**(非阻塞 `flock`,撞上就响亮拒跑)。
  固定 home + 每轮不同的副本路径 = 两条并发会互相覆盖 settings.json 里的读授权,
  先跑那条突然读不到自己的副本、交白卷,而错误长得像额度或凭证问题。
  判据 V46⑭ 实测过这条串味 —— 不是推论。要并行请给 `AGY_REVIEW_HOME` 另一个路径。
- **评审 home 必须写死 `enableTelemetry:false`**。业主在首次向导里亲手关掉了数据
  收集,但那条写在**他的** home;换 HOME 之后评审 home 是全新的、连 settings.json
  都没有 = 走默认值 = 他的选择被绕过,**而这条腿读的正是他的仓库代码**。
- **三个只有真跑才会撞见的坑**(都已焊死,判据 V46 盯着):
  ① **rc 完全信不得** —— 未登录跑 `agy models` 仍然 **rc=0**;官方文档也载明拿不到
     批准的工具是 soft-deny「继续跑、exit 0、只在 stderr 印一句」⇒ 判死活**只看裁决行**;
  ② **未登录时 `agy -p` 静默挂死**(实测 40 秒零输出、不退出)⇒ wrapper 派发前
     预检凭证,失效就**响亮失败**;没有这一步,失效凭证长得和额度耗尽一模一样;
  ③ **不给 workspace 时它读写自己的 `~/.gemini/antigravity-cli/scratch/`,不碰 cwd**
     ⇒ 必须显式 `--add-dir`,否则腿等于没看见被评审的仓(而它照样会交一份像样的卷)。

### headless 权限:这条腿最花时间的地方,别照文档写

⚠️ **早期那句"agy 在 workspace 内写权限默认全开、跟它的权限系统搏斗没有收益"是错的**,
写在这里当墓碑。那次探针跑在**业主自己的 home**(已经手工信任过 `/root`)上,
换进隔离 home 之后结论完全不成立 —— **隔离改变了权限基线,而我拿旧基线的结论做了设计。**

真链冒烟连挂四轮才收敛,每轮换一个拒法(全都是 `rc=0` + 零产出):

1. `RunCommand` 被 auto-deny —— headless 弹不出批准框;
2. `read_file` 被 auto-deny —— **`--add-dir` 给的目录不算 active workspace**,
   文档那句"workspace 内读写自动允许"不覆盖它,每个新目录要 project 授权;
3. `command(git (log|diff))` 被拒 —— **分组语法是死的**。实测
   `command(git log)` 通过 / `command(git (log|diff))` **被拒** / `command(git)` 通过,
   **而官方文档的例子写的正是分组**。照文档写 = 规则静默失效 = 腿每次交白卷;
4. 它想跑 `bash tests/mutation-subgemini.sh`(**它想跑我们的红检脚本来验证代码**)。

第 4 条逼出了真正的病根:**一次 soft-deny 就让整个 run 零产出**,不是"换个工具继续"。
所以修法不是把命令一条条加进白名单(追不完),而是**在提示词里写清沙箱边界**,
并明确告诉它"一次被拒你整轮就废了"。这是**引导不是保证**,记在 track 的 E4。

现在的配置(`write_agy_settings`,每次派发重写):
- `read_file(<副本路径>)` / `write_file(<副本路径>)` —— **必须是具体路径**。
  `read_file(*)` 和 `read_file(/)` 同样能解开,但那让腿读得到 `~/.ssh`、业主的 agy 凭证、
  机器上别的项目。判据 V46⑪a 机械挡住通配。
- 命令白名单**只留只读 git**(log/diff/status/show/ls-files/rev-parse/blame,一条一条写)。
  🔴 **不许放 cat/ls/grep/find 这类通用文件命令** —— 它们**完全绕过** `read_file` 的
  副本限定,`command(cat)` 一放行,腿就能 cat 业主的私钥。第一版白名单里正有这一串,
  而同一个文件的注释里写着"这条腿只看得见那份副本" —— 两句话同时在,只有一句是真的。
  判据 V46⑩d 盯着。
- 排查工具 **`bin/subgemini-diag`**:agy 的失败信息**从不说是哪个命令**,
  它从会话 SQLite 里挖出来。注意必须连 `-wal` 一起复制再打开,
  只拷 `.db` 会读不到刚跑完那轮、得出"没有失败记录"的假结论。

- **只读边界沿用现行架构**(可丢弃可写副本 + 原仓 `ro-repo-exec` 只读),没有另造锁。
  🔴 **墓碑:这句话 2026-08-25 写下时是假的** —— 那天 wrapper 里一个字都没接
  `ro-repo-exec`(subkimi/submimo/subagent 三条腿都包了,只有它没有),而文档和代码
  注释都照写"原仓只读"。四审两条腿各自 grep 出来,判据 V46⑫ 用假模型试写实测:
  **当时腿真能写进被评审的原仓**。08-26 已把命令放进 `ro-repo-exec` 的 namespace。
  **教训不是"漏了一行",是"我把设计意图写成了既成事实"**。
  `--mode plan` 只出计划,但没验过那是机械锁还是模型自觉,**因此不拿它当防线**。
- **仍然敞着(而且各 agent 腿都一样)**:namespace 只把被评审的**原仓**变只读,
  管不住仓**外**的读 —— `git diff --no-index /root/.ssh/id_rsa` 这类命令能把任意
  可读文件打进评审日志(08-19 已实证)。命令白名单是前缀匹配,挡不住 git 自己的参数,
  它从来不是边界。要堵得给 `ro-repo-exec` 加“遮住敏感路径”的能力 ⇒ 跨全部 agent 腿,单开一单。
- **腿目前不能跑判据/测试**(track 的 E3):放行 `bash` 等于放弃"只看得见副本"这条边界。
  而 `ro-lock-teardown` 的 proposal 写着评审腿应当"能运行本地判据、编译和诊断" ——
  这笔账敞着,单开一单。
- **裁决判定复用 `_panel-roster-lib.sh` 的 `verdict_of`**,不另写正则:
  花名册那条是严格的(裁决必须独立成行),而提示词里原样含有
  "Conclusion: PASS | BLOCK | NEEDS_MORE_INFO" —— 腿用宽松、花名册用严格,
  等于腿自认成功而花名册记 UNKNOWN。
- **敞账:`agy` 是闭源 Go 二进制,而且会在日常运行中后台自我更新**
  (`agy update` 子命令 + 安装脚本自述)。**判卷防线上出现了一个会自己变的构件**,
  这笔账还没还(track subgemini-review-leg 的 D1)。
- 超时 `AGY_TIMEOUT`(默认 1500s):**超时但裁决已落盘 = 收下**,同时往报告里追加一条
  「这是部分运行」的横幅 —— 一份写完裁决就被砍的报告,长得和完整评审一模一样,
  而它以后会被单独读到(归档、断线重连),那时终端上那句 stderr 早没了。判据 V46⑯。
- **任务文件不存在 ⇒ 拒跑**(判据 V46⑮)。原来是 `cat … 2>/dev/null || true`:路径写错
  时腿拿到一份没有任务的提示词,照样可能吐一个裁决行 ⇒ 收一个 PASS,而它什么都没审。
- 派发不再按腿名分支:`panel-review` 从 `_panel-roster-lib.sh` 的 `PANEL_LEG_SPECS`
  一张表里取家族/底座腿/聊天腿/开关,**加腿只改那一行**。08-26 之前这些事实散着六份
  拷贝,加第五条腿时漏了四份,其中最贵的一份让 panel **给一条从没跑过的腿记了 rc=0**。
- `fix` **故意不支持**。

## codex (GPT-5.6-Sol) — frontier 档(**不在轮换池里**,主 agent 手动并排拉起),2026-07-26 起

**还没有包成脚本,当前是主 agent 手动并排拉起;它不在 `PANEL_LEGS_ORDER` 里。** 参见 [[codex-as-employee]] 记忆。

```
codex exec -C REPO -s read-only -o PREFIX.codex.log "评审任务书(要求中文回答)"
```

- 与轮换池各腿的关键差别:**它不是弱模型**。池内腿的共同假阴性是它们结构上的盲区;
  补一条 frontier 腿的价值 > 再补一条同档腿。
- **`-s read-only` 必须带**——评审员不该有写权限。
- **额度**:走 ChatGPT 订阅(`auth_mode=chatgpt`),不烧 Claude 额度。
- `--output-schema FILE` 可以让它按 JSON Schema 输出裁决,比正则匹配 "Conclusion:" 稳
  (中文全角冒号误判那笔工具债的正解)。
- **不需要**再加 `-c project_doc_max_bytes=0`:2026-07-26 起本机说明书叫 `CLAUDE.md`,
  Codex 只认 `AGENTS.md`,结构上就读不到,忘不忘都一样。
- `panel-review` **不需要**为它改代码——那个工具只是个并行派发器,手动并排拉一条腿即可。
  等它变成常规动作再考虑包成 `subcodex`(理由只能是"让两个 flag 忘不掉",不是为了好看)。
