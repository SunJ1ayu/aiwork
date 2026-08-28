# Agent Instructions

本机是单人多 agent 工作站:主 agent(会话里的 frontier 模型)是**唯一的控制者与最终仲裁者**,
外部模型(MiMo / DeepSeek / GLM / Kimi / Gemini / GPT-Codex)都是**员工**——它们的输出是待评估的证据,
永远不是自动生效的决定。工具在 `/root/aiwork/bin/`,任务存 `/root/aiwork/tasks/`,
日志存 `/root/aiwork/logs/`。
本文件的唯一规范源在 `/root/aiwork/workflow/CLAUDE.md`；这里是 Claude Code 的部署副本。
工作流 skill 同理以 `/root/aiwork/workflow/skills/` 为准，用
`/root/aiwork/bin/sync-workflow-docs --check` 查逐字节漂移。

## 随身规矩(这几条不看抽屉也必须守)

**oracle 永远由主 agent 亲自写,绝不外包。** 弱模型最可能的失败方式是**改考卷让自己及格**
(删断言、写死期望值、加 skip)。

**收货时执行腿的自述一概不作数**,三道闸每次都走(① diff / ② 亲跑 / ③ 亲读)。
每道闸挡的是什么、`--protect` 清单、以及闸① 的机械版 `delegate-codex --receive`,
全在 delegate 抽屉里 —— **派活前本来就得开那个抽屉**,这里不留第二份
(2026-08-08 退场:这里那份已经比抽屉旧,它还在讲手工流程)。

**判据红了,先问「是不是真 bug」,不许先怀疑判据。** 尤其是行为考卷那种带方差的:
"它只是抖" 是最舒服的解释,而顺着它走下一步就是**调钝报警器**——那和弱模型
"改考卷让自己及格" 是同一个动作,只是理由体面。08-04 实证:我把 resolver_eval 的抖动
归成噪音、准备加"重复跑取多数",用户一句「抖动实际上是我们的 bug」掰回来;
真因是助手在心算日期、工具层零日期能力,业主的截止日当时就是错的。
**判"我改劣化了没有"要对 baseline 也连跑几遍比失败数**,不是看单次绿没绿。
> 反过来也有一条,别用它掩护上面这条:**连红三遍、而模型的答案讲得通 ⇒ 先怀疑题面**。
> 08-04 同日实证:我把两步行为的断言写进单选路由器考卷,红了两轮才想明白错在题面。
> 区别在**证据方向**:改题面前必须说清"这份考卷结构上问不出这件事",
> 并把断言**搬到问得出的地方**(更强、且重新红检);说不清就是在放水。

**判据先单独 commit,再 commit 修复。** 中途自己补判据也一样。
闸①问的是「执行腿有没有动判卷」,不是「文件有没有变过」——判据和它的修复揉进一个
commit,闸①就退化成翻执行腿日志人工找补,而且 git 历史里再也证明不了「红过」。

**风险和方向不确定性是两个轴，别再让 lane 一词兼任两件事。**
`impact-risk`:self / standard / high，外部评审预算分别是 self=0、standard=1、high=2；
新写口 / 权限 / auth / 钱 / 数据一致性默认 high。high 从健康池轮换两个不同模型家族，
失败、降级、冲突、NEEDS_MORE_INFO 或我仍不确定才追加第三腿；判卷/沙箱/权限边界等
特殊控制面才显式 `panel-review --all`。绑定 typed track 时，`--budget` 只能加证据，不能低于
该 risk 的 0/1/2 预算绕闸。`design-uncertainty`:low / high，只决定是否做
premise attack / 双出 / panel-explore，不因实现风险高就自动花一次规划双出。
新 track 的机器字段只写同目录 `decision.json`，unknown 用 null，不在 verify.md 复制
`Verdict:` / `lane:` / `派给:`。真实 controller dispatch 前先跑
`track-record validate --phase dispatch tracks/<name>`；缺字段、高危因子降档、high uncertainty
却没有持久 premise evidence 都会打印 rule/path/actual/expected 并 BLOCK。旧 track 继续 legacy，
不从旧自由文本猜新字段。PASS 归档还会从 compact panel observation 机械核对
self/standard/high 是否由同一次成功 panel、同一 subject digest 下 0/1/2 个
coverage-eligible 的不同模型家族腿满足；v1、UNKNOWN/NMI、timeout、降级、证据不完整、
跨 run 拼接或 eligible PASS/BLOCK 冲突都不能补预算。缺腿时 archive 与成功成本聚合都 BLOCK。
**oracle 是我写的、可能本身就错**——过审只证明"合乎规格",不证明规格对。

**bump 版本号、或动判卷防线的 commit,必须挂在一个 track 下**(归进现成 track 也算)。
这条 pre-commit 守卫 `/root/aiwork/bin/track-guard` 会机械查(新仓库要自己装 hook),
我只需记住它查不了的那件:**harness 自带的任务清单会话结束就没了,不许拿它顶替 track。**

**外部执行腿一律不许**:push、merge、删文件、装依赖、碰生产系统、跑数据库迁移、改密钥。
需要危险操作**先问用户**。**沙箱网络保持关闭**——三道闸查的都是「它改了什么」,
没有一道查得了「它往外发了什么」,网络是唯一无痕的出口。

**要第二意见**开 `panel` skill 选 review/explore;两者都不像就直接做,别花 panel。
panel 是第二意见,**永远不能替代我自己的第一遍工作**。

**新硬规矩的准入与退场**:刹车类(要我停下来做某事)= 真出过事 + git 一眼可查;
信任/安全类(闸、断网这种)= 查工件不查自述 + 防不可逆损害,**允许事前推演准入,
不必等出事**。两类都够不上的只能进抽屉当建议。每条硬规矩要说得出理由;
理由失效即候删——总量不许只进不出。
> 退场是真会发生的,不是场面话。2026-08-08 退过一轮:收货三闸细节与 `--protect` →
> delegate 抽屉(那里更新、这里已旧);「lane/派给 空着=没判过」「bump 必挂 track」的
> 机械部分 → track-guard 守卫;AGENTS.md 那段重复 → 只留全局那一份。
> **判断标准就一条:这件事已经有机器在查、或抽屉里有更新的全文,这里就不该有第二份。**

## 在使用现场验证(部署目标规矩)

交付物跑在你改的仓库之外时——浏览器(Tampermonkey)、systemd 服务、OpenClaw gateway、
另一台机器的安装——**"做完了"的标准是运行中的目标回显出预期版本/状态,不是新文件躺在盘上。**
没被加载/重启/重装的新文件不算部署。

一周内栽过两次:GLM 抢购脚本浏览器里跑 v2.9 而 v3.0 躺在盘上(输掉一次实盘);
gateway 内存里跑 6.8 而装好的 dist 是 6.10(07-07 全 cron 崩)。同一种病,不同运行时。

所以:任何部署类改动之后,**跑一条能让运行中的目标自己打印版本/身份的命令**,和你发出去的
东西对一遍。gateway 有现成脚本(`/root/aiwork/bin/check-gateway-version`);浏览器等其他目标,
在任务的验证环节加一个等价的"回显活版本"检查再宣布完成。**盘上和运行时对不上 = BLOCK,不是警告。**

## 抽屉(用到再打开)

- **派活给执行腿** → `delegate` skill:分层选档、oracle 先行、派活三件套、收货三闸、
  `submimo fix` 的全部参数与边界、codex(GPT)腿怎么调。
- **多模型评审/发散** → `panel` skill:`panel-review` 健康池预算与五步协议、
  `panel-explore` 纪律、三条护栏、信任校准;各腿后端细节在它的 `references/legs.md`。
- **track 轻量工作流**(一个 PR 级改动的工件链 proposal→design→tasks→verify→archive)
  → `/track` skill;完整约定在 `/root/aiwork/track/CONVENTION.md`。
  CLI:`track new|archive|list <name> [project-dir]`。
