# Proposal: repo-write-audit —— 评审腿动过被评审的仓,必须留下证据

> 来源:track `deepseek-leg-bash-hole` 转向时分出来的。设计主体来自
> **gpt-5.6-sol 的规划双出那一版**(全文 `/root/aiwork-plans/plan-dual-worktree-guard.log`,
> brief 在同目录),主 agent 评估后采纳其诊断。**别当成"以后有空再说"的账 ——
> 它是那一单被推翻之后唯一还站着的防线。**

## 问题(现状,不是推测)

`panel-review` 并行派四条评审腿,每条在被评审的仓里自己读代码。**这些腿有能力写这个仓**:

- `mimo debug agent plan` 实测:自称 "Disallows all edit tools",实际
  `bash/write/edit/task` 全 True + 权限 `{"*": allow "*"}`(收据:
  `tracks/deepseek-leg-bash-hole/evidence/20260819T025552Z-01-probe-mimo-plan-agent.txt`)。
- claude 那层 `--allowedTools` 不是严格白名单;即便禁掉 Bash 工具,
  `git diff --output=<path> HEAD` 也能写文件(08-18 亲手复现)。
- kimi 的守卫是正则前缀白名单,同样挡不住。

**而 panel 跑完没有任何检查会去看仓有没有被动过。** 腿真写了,除非人下次碰巧
`git status` 看见,否则不会有人知道。

## 为什么不是"把腿的能力关掉"

试过,被推翻(见 `deepseek-leg-bash-hole` 的 design 第一节)。关掉 bash ⇒ 腿不能自己
读 git ⇒ 主 agent 要算好 diff 喂进去 ⇒ 那条链上长出 E2BIG、SIGPIPE 静默暴毙、
基线静默变瞎一整串 bug,**最坏的形态是两条腿根本没跑起来而 panel 照常出结论**。
且评审腿**没有**"改判据让自己及格"的动机(那是执行腿的威胁模型)。
⇒ 对面是**误伤和提示注入**,不是有动机的对手 ⇒ **检测,不预防**。

## 方案要点(采纳 gpt-5.6-sol 那版)

**按评审腿进程树归因的写审计**,不是 panel 前后 `git status` 对比。

1. 共享审计器包在**真正的模型 CLI**那一层(`mimo run` / `claude -p` / `opencode run` /
   `kimi`,以及 chat fallback 的引擎进程),用 `strace -ff -yy` 一类跟踪该进程树对
   受保护根的**成功写**(write/truncate/create/unlink/rename/chmod…)。
   - 主 agent 和别的腿不是它的后代 ⇒ **并发改仓不误报**。这是它胜过"前后快照"的关键。
   - 记的是**写事件不是净差异** ⇒ 写完又删、改完又恢复、改 `.git`、写 ignored 文件
     都抓得到。
2. 三态收据,**`UNKNOWN` 不许冒充 `CLEAN`**:观察器没武装好 ⇒ 派发前拒跑;
   中途死掉 ⇒ 写完横幅和 roster 后**非零退出**。
3. 每轮 **nonce**,防上一轮的收据冒充本轮;缺一份阶段收据就是 `UNKNOWN`。
4. `DIRTY` **不改 panel 退出码**(非零会被调用方 `set -e` 截断,反而让人不读日志),
   但横幅进 **stdout + 每份非空腿日志 + roster**(照 HEAD 漂移那条先例)。
5. 受保护根 = 工作树 realpath + `git rev-parse --absolute-git-dir` +
   `--git-common-dir`(否则 linked worktree 改共享 refs/index 会从路径过滤旁边溜掉)。
6. **审计窗口外**放 wrapper 自己的基础设施写:`bin/submimo:140` 会在被评仓里建
   `.submimo-task-$$.md` —— 包整条 wrapper 会每轮固定误报,而固定误报的警告一周内没人看。

## 它照不到什么(写清楚,不假装全覆盖)

仓外的 HOME/`/tmp`/邻接仓;经已有 daemon/MCP/docker socket 代写(实际写进程不是腿的后代);
仓内符号链接指向仓外的目标;审计窗口开始前/结束后 wrapper 自身的写;
共享可写 mmap / io_uring 这类没支持的写路径(遇到 ⇒ 出 `UNKNOWN` 不出 `CLEAN`);
**主动对抗的恶意进程** —— 这版吃的是"腿没有作恶动机"这个前提,不是强敌沙箱。

## 判据(gpt 那版给的场景表,直接当验收标准)

纯读取 ⇒ 精确 `CLEAN` / 已知漏洞复现(`git diff --output=`)⇒ 精确 `DIRTY` 带腿名和路径 /
**写后消失**(创建再删除,`git status` 最终干净)⇒ 仍是 `DIRTY` / **主 agent 并发写** ⇒
腿收据仍是 `CLEAN` / 精确归因(四腿只有一腿写)/ **fallback**(agent 阶段写了、chat 阶段
干净成功 ⇒ 最终仍 `DIRTY(agent)`,不许被后一份 CLEAN 覆盖)/ 传播形状(stdout+每份日志+
roster 同一 nonce)/ **审计器故障 ⇒ UNKNOWN 且 panel 非零** / **旧 nonce 收据必须被拒** /
日志落在被评仓 `logs/` 下不许误报 / 四条真实入口 + fallback 都真的经过审计器。

**要避免的"永远绿"假闸**(它明确点名的):
`grep -q 'REPO MUTATION' bin/panel-review` 只证明写了文案;
只断言输出里有 `WARNING` —— 审计器缺失导致的 `UNKNOWN` 也能让它通过。
正向断言要同时绑定:**本轮 nonce + 精确状态 + 精确肇事腿 + 精确写入路径**,
并确认假模型自身 rc=0(排除"警告其实来自旁路失败")。

## 现在的状态(明账)

`deepseek-leg-bash-hole` 拆掉 diff 注入、恢复 bash 之后,到这一单上线之前,
**腿有 bash、能写被评审的仓、没有任何检查** —— 即 08-18 之前的状态。
那个状态已经跑了很久,不是新增风险,但从现在起它是**写下来的账**。
