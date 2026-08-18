# Design: opencode-go-leg

- Change: opencode-go-leg
- Status: draft
- 规划双出: 不适用(不是新写面:换的是供应商表里三个默认值 + 一格 header 风格)

## 官方底座调研(业主点名要查的那一步)

**结论:GLM 没有官方 agent 底座可包,现有的壳已经是官方推荐路径。**

- 智谱官方仓 `MetaGLM/glm-cc` 的自述就是「把 GLM 接进 Claude Code 这类 vibe coding
  工具」⇒ 官方给的路子就是**拿 Claude Code 当壳换端点**,和 `subglm-agent` 现在做的一样;
- `@z_ai/zai-cli` 是通用工具箱(chat/media/parse/search),不是编码 agent 底座;
  `@z_ai/coding-helper` / `chelper` 是"管别人家编码工具"的助手,也不是底座;
- npm/GitHub(zai-org / THUDM / MetaGLM)里没有 kimi-code 那种一等公民 CLI;
- 而且这把 key 是 **OpenCode Go 的**,不是 z.ai 的 —— 就算有官方 CLI,它认的是
  z.ai 账号,吃不下这把 key。

## Approach

只动供应商表(差异只准活在那里):

| | 旧(bigmodel) | 新(OpenCode Go) |
|---|---|---|
| 底座腿端点 | `open.bigmodel.cn/api/anthropic` | `https://opencode.ai/zen/go` **(不带 `/v1`)** |
| 聊天腿端点 | `open.bigmodel.cn/api/paas/v4/chat/completions` | `https://opencode.ai/zen/go/v1/chat/completions` |
| 默认模型 | `glm-4.6v` | `glm-5.2` |
| key 文件 | `~/.config/zhipu/auth.json` | `~/.config/opencode-go/auth.json` |
| 认证 header | `ANTHROPIC_AUTH_TOKEN`(Bearer) | **`ANTHROPIC_API_KEY`(x-api-key)** |

`panel-review` 的 GLM 腿默认值 `off` → **`chat`**(08-04 关它的理由是欠费,理由没了)。

## 实测把规格改了两处(08-18,写在这儿免得设计和实现各说各话)

上面那张表是**动手前**写的。真打端点之后有两处被证伪,代码已按实测走:

1. **底座腿 base URL 不带尾部 `/v1`**。claude CLI 自己会补 `/v1/messages`,
   写成 `.../go/v1` 会打到 `/zen/go/v1/v1/messages`(404);更坑的是 CLI 把这个 404
   报成「模型 glm-5.2 不存在」—— **地址 bug 伪装成模型名 bug**,我照着"模型名错"
   查了半天。(聊天腿那一格仍是 `.../zen/go/v1/chat/completions`,那是完整路径,没错。)
2. **panel 的 GLM 腿默认档是 `chat`(聊天腿),不是 `agent`**。OpenCode Go 的
   Anthropic 面**不做工具格式转换**(请求体直接转发给 OpenAI 形状的上游),带
   Anthropic 形状的 tools 一律 400「Missing required input field:
   'tools[0].function.name'」。实测三档:无工具 200 / Anthropic 形状工具 400 /
   OpenAI 形状工具 200。而底座腿的全部意义就是自带工具自己读仓库 ⇒ **在这个后端上
   它起不来**,默认写 agent 只会每轮白撞一次 400。
   `PANEL_GLM_LEG=agent` 强制切回的能力保留:哪天 Go 补上格式转换,一个环境变量就切回去。

**认下来的代价**:聊天腿看不见仓库、只看得见 diff ⇒ 派它时要带 `PANEL_INCLUDE`。
panel-review 里那条 `HINT: chat leg in play and PANEL_INCLUDE is empty` 默认走 chat 之后
会常亮,正好当提醒。(**不写行号** —— 上一版这里写了「第 207 行」,而它当时就已经是 221 行。)
这不是无代价的等价替换,是"能用的腿"换掉"跑不起来的腿"。

3. 还有一处不改规格但值得记:**聊天腿必须带 User-Agent**。urllib 的默认 UA
   被 Cloudflare 前置的端点 403(error code 1010),同一个请求 curl 200 / urllib 403。

## Key trade-offs / risks

- **认证 header 是这单的真 bug**:Go 的 Anthropic 面只认 x-api-key,实测 Bearer 回
  401 `Missing API key`。躯干原本硬写着 `ANTHROPIC_AUTH_TOKEN=` ⇒ 光换端点/key 会得到
  一条"活着但永远不回话"的腿。所以表里新增一格 `AUTH_ENV`,deepseek 保持 Bearer。
- **共用躯干的串味风险**:`subagent`/`subchat` 同时服务 deepseek。判据里专门有一组
  "deepseek 一个字没被改"的断言(本机记过账:合并躯干那次我顺手把 GLM 的轮次上限翻了倍)。
- **key 落盘**:新 key 存 `~/.config/opencode-go/auth.json`(600),仓外;判据查
  "仓里被跟踪的文件不许出现 API key 形状的字符串"。
- 旧 `~/.config/zhipu/auth.json` 原样留着(它是另一家的账,将来充值可切回)。

## Alternatives considered

- **包一条 opencode CLI 的新腿**(我的第一版):被业主否掉三次 —— 会变成第五条腿、
  换掉壳、且和"额度过期的那条腿"这个真问题无关。已回滚(装的 opencode 卸掉)。
- **把 key 塞进 `~/.config/zhipu/auth.json`**:文件名会撒谎(那是智谱的账),
  本机反复吃过"同一件事写在两个地方/名字与内容对不上"的亏。

## Test strategy (oracle)

`tests/test-review-tooling.sh`:V8/V9/V13 的旧断言随规格翻新(端点、header 风格、
panel 默认开关),新增 **V26** 专问三件 V8/V9 问不出来的事:①header 风格表驱动、
②deepseek 没被顺手改、③key 落位且不进仓。判据全用 stub(**判据不许有外网出口**),
真端点的连通性由 verify 里的 runlog 冒烟收据承担。

**这个 oracle 能被什么骗过?**

- stub 只能证明"我们注了什么环境变量",证明不了**真端点会不会认**。头一版判据
  就是这么绿着而 Bearer 是死的 ⇒ 必须配一次**真跑**(subglm-agent 打真端点、
  拿到真裁决行)才算数;这是 verify 里那条 runlog 收据存在的唯一理由。
- 判据自己会瞎:V26 第一版忘了 `REVIEW_NO_MY_REVIEW=1`,反锚定闸把每次派发都拦掉,
  16 条红全是空的、还混着两条假绿。**红检要看"基线那几条是不是绿的"**(deepseek
  那组),不是看总数红没红。
