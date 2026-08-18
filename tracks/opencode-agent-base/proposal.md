# Proposal: opencode-agent-base

## 问题

GLM 腿换到 OpenCode Go 之后**失去了"自己读仓库"的能力**(track `opencode-go-leg`)。
根因:我们的底座腿是**借 Claude Code 当壳**,工具是 Anthropic 形状的;而 Go 的
Anthropic 面不做工具格式转换,带 tools 的请求一律 400。当时我把这个降级当成既成事实
写进了三份文档,**没有回头重新评估"换个底座"这条路** —— 业主一句
「mimo 底座不是 mimo code 吗,glm 可以走 opencode 这个底座吧」把它掰回来。

**业主是对的,而且这不是新腿,是同一条腿换底座** —— 四条腿里已经有两条是这个形状:

| 腿 | 底座 |
|---|---|
| MiMo | 官方 MiMoCode CLI(`mimo run`) |
| Kimi | 原生 kimi-code CLI(`kimi -p`) |
| DeepSeek | 借 Claude Code 当壳 |
| GLM | 借 Claude Code 当壳 ← 就是 400 的原因 |

我早先提过"包 opencode CLI",业主否了三次(会变成第五条腿/换掉壳/和欠费无关)——
**当时那个否决是对的**,但 400 这个发现出来之后前提变了,而我没把它端回去。
"会变成第五条腿"这个说法本身也是错的,我还把它抄进了设计文档。

## 提议

把 `subglm-agent` 的底座从「Claude Code 壳 + Anthropic 端点」换成
**opencode CLI 自己**(`opencode run`),让 GLM 腿恢复自己读仓库。

## 可行性探针(2026-08-18 已跑完,四件全过)

命令都在 `design.md` 里,可重跑。

| 要验的 | 结果 |
|---|---|
| ① 无界面跑 | ✅ `opencode run --dir REPO --agent X -m go/glm-5.2 "..."` |
| ② 只读锁**机械成立** | ✅ 见下,**但内置 plan 档不算数** |
| ③ 裁决行拿得到 | ✅ stdout 干净收尾 `Conclusion: BLOCK` |
| ④ 配置隔离 | ✅ 换 `HOME` 即整体重定向(和 subkimi 的 `KIMI_CODE_HOME` 同形) |
| 附:自己读仓库 | ✅ **它自己跑了 `ls`/`git log`/`Read calc.py`,找到了埋的雷** |

## 探针挖出来的四个坑(都得写进实现)

1. **默认 provider 用不了**:CLI 默认走 OpenCode 按量付费网关 ⇒ `Insufficient balance`。
   必须在配置里自定义 provider 指到订阅端点 `https://opencode.ai/zen/go/v1`
   (`@ai-sdk/openai-compatible`),模型名变成 `go/glm-5.2`。
2. **`rc=0` 不可信**:余额不足那次它把错误打在 stdout 上、**退出码仍然是 0**。
   ⇒ 判活必须靠裁决行,不能靠 rc(我们本来就有裁决 gate,但这条要写死在判据里)。
3. **内置 `plan` agent 不是机械锁**:它自称"禁掉所有编辑工具",但解析出来的配置是
   `write/edit/bash: true` + 权限 `* allow`。两次实测它**拒绝**写文件(还识破了话术),
   但那是**模型自觉**,不是闸。评审腿的只读必须机械成立 ⇒ **不许用 plan 档**,
   要自配 agent 把工具关掉(实测关掉后模型自己报告"我没有写文件的工具",且文件确实没出现)。
4. **`skill` 工具默认还开着**(关掉 write/edit/bash 之后仍在)。要不要一起关,实现时定。

## 影响面

只动 `subglm-agent` 这条腿。deepseek 腿仍走 Claude Code 壳(它的端点做转换,没问题)。
`panel-review` / `panel-explore` 的默认档要从 chat 改回 agent —— 但**这次要有判据钉住
"默认档必须是真的能跑起来的那一档"**,不能再出现"默认写着 agent 其实每次 400"。
