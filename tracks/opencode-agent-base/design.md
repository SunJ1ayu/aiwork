# Design: opencode-agent-base

- Change: opencode-agent-base
- Status: draft

> Panel hook — 仅当这是真·开放架构分叉(多个站得住的方向、风险=隧道视野)时,
> 先跑 `panel-explore`,把方向谱折叠进这里。否则直接写方向就行。
> 主 agent 在读任何 panel 输出之前,先落自己的方向(反锚定)。

- 规划双出: <日志路径 | 不适用:____>
  > **只剩一个触发条件:新写面 / 开放方向且这单我自己干**(动档案格式、写口语义扩张、
  > 新增参数……即 verify 那边会填 `lane: full` 的同一批面)。
  > **"要外包给执行腿"那半句 08-06 退场** —— 它升级成了 `delegate-codex --attack-log`:
  > 派活时给不出攻题记录就发不出去,不再靠我在这一格里自评(08-05 我就是在这格里
  > 用一句括号把它绕过去的)。
  > 做法:主 agent **先落盘**,再让 `gpt-5.6-sol` 对**同一份需求**独立出一版
  > (明令不许读本 track 的工件),然后对差异。抓的是**"我以为理所当然"的地方** ——
  > 那正是"我出方案、它来审"照不到的死角(审查只会在我的框子里挑毛病)。
  > 史料:08-02 due-writer 单它点破了我判卷题的一个洞(`fef253c`);
  > 08-06 delegate-entry 单它点破三处(攻题记录会过期 / 闸①没给闸③底账 /
  > 红检没区分"红在 build 上")—— 两次都是**结构性的洞,不是措辞**。

## Approach

<选定的技术方向>

## Key trade-offs / risks

- <关键取舍与风险>

## Alternatives considered

- <考虑过但没选的方向 + 为什么没选>

## Test strategy (oracle)

<怎么证明它对 —— 这是后面 verify 的判据,主 agent 拥有>

**这个 oracle 能被什么骗过?**

<不问"断言写没写",问"用户眼里的成功长什么样,我的断言离它差了什么"。
写下:断言全绿但结果仍然错,会错成什么样;以及那种错要靠什么才接得住
(真截图/真机/真返回)。史料:07-24 `columnCount==="3"` 全绿,实际正文被压成竖排。>

## 探针实录(2026-08-18,命令可重跑)

隔离 HOME:`OCH=<某个空目录>`;key 从 `~/.config/opencode-go/auth.json` 读。

```
# 配置(自定义 provider 指到订阅端点 + 自配只读 agent)
$OCH/.config/opencode/opencode.json:
{
  "provider": { "go": { "npm": "@ai-sdk/openai-compatible",
      "options": { "baseURL": "https://opencode.ai/zen/go/v1", "apiKey": "<key>" },
      "models": { "glm-5.2": {} } } },
  "agent": { "reviewonly": { "mode": "primary", "model": "go/glm-5.2",
      "tools": { "write": false, "edit": false, "patch": false, "bash": false,
                 "task": false, "todowrite": false, "webfetch": false,
                 "websearch": false, "read": true, "glob": true, "grep": true } } }
}

# 跑
HOME=$OCH opencode run --dir REPO --agent reviewonly "<任务>"
```

**关掉之后解析出来的工具表**(`opencode debug agent reviewonly`):
- 关:`question bash edit write task webfetch todowrite`
- 开:`invalid read glob grep skill`

**行为实测**(埋雷仓:`add()` 里写成 `a - b`):
- 只读 agent:自己 `Read` 了仓库,**抓到雷**,收尾 `Conclusion: BLOCK`;
  被要求写文件时如实回答"我没有写文件的工具",**仓库里没有多出任何文件**。
- 对照:内置 `plan` 档同样没写出文件,**但它给的理由是"我处于 plan mode 不该做"** ——
  两次(含一次话术攻击)都是模型自觉。解析配置显示 `write/edit/bash: true` +
  权限 `* allow` ⇒ **机械层是敞的,不许拿它当只读保证**。

## 还没定的两件

1. `skill` 工具要不要一起关(现在还开着)。
2. 关掉 `bash` 之后腿看不了 `git diff/log`。Claude 壳那条腿是允许只读 git 的。
   两条路:(a) 保持关掉,diff 由我们喂;(b) 查 opencode 的 bash 权限能不能按命令模式放行
   (permission 项里有 `pattern` 字段,像是支持)。倾向 (b) 再验一次,验不通走 (a)。
