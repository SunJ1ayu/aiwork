# Proposal: workflow-gates-say-why

- Date: 2026-08-24
- Status: open

## Goal

两道**工作流自己的闸**报警时说不清自己在报什么,今天各害我一次。让它们把话说明白。

## Motivation

2026-08-24 做 OpenDesign 那两单时,连撞两次工作流工具的坑。**两次都是工具报对了警,
但没告诉我它在报什么** —— 我只能翻源码去猜:

1. **`runlog --final` 静默把 rc 改成 65。**
   `bin/runlog:201` 是 `[ "$RC" -ne 0 ] || RC=65`,判定写进收据文件的
   `source-stable: no`,而**终端上一个字的解释都没有**。今天两次撞上
   (一次是我并行派了 panel、它往仓内 `observations/` 写;一次是我自己在收据跑的
   过程中编辑 verify.md),两次都得 `sed -n` 翻源码才明白 65 是什么意思。
   > 既有判据 `tests/test-runlog.sh` 的 R8 **验的是收据文件里有没有
   > `source-stable: no`**,没有验"跑的人在终端上看不看得懂"。

2. **`panel` skill 的反锚定指导不完整。**
   它写着「正确节奏是先派发、后写 verify.md」。今天我**严格照做了**
   (派发前把 verify.md `git checkout` 回 HEAD,自审正本放仓外),
   **两轮仍然都报 `anchor leak`** —— 因为引擎内联的是**整份 diff**,
   而 `diff base..HEAD` 里带着 verify.md 在**之前几个 commit** 里的内容。
   skill 里没有一个字提到这一层,照着它做也躲不掉。

## 真问题(第一性)

- 用户原话:「我的意思是 opendesign 你刚刚都在做什么,我们不是在优化 aiwork 吗
  你之前说的什么判卷红难道不是我们工作流的问题」
- 真正要解决的是:**这一轮暴露的工作流缺陷,我只把它们写进了 OpenDesign 的验收记录和
  记忆里,没有回头改工具本身。** 教训留在了"出事的那个项目"的档案里,
  而**下一个项目、下一次会话照样会踩** —— 因为工具还是不说话。
- 我在这中间翻译了什么:用户上一轮问「查一下 aiwork 有没有要一起改的」,
  **我把它读成了「aiwork 仓库里提到 OpenDesign 的文档要不要同步」**,于是去搜关键词、
  做了一遍文档同步。**又一次搜错了范围** —— 而"我搜过了 ≠ 我搜的范围盖住了"
  正是那一单自己在防的病。他问的是**工作流本身**。

## Scope

- in: `bin/runlog` —— `source-stable=no` 时向 stderr 打一段**人话**:出了什么事、
  为什么这份收据不算数、怎么办、常见元凶是哪几个;帮助文本同步补一句。
- in: `tests/test-runlog.sh` —— 判据先行:R8 加断言「stderr 必须解释得清」。
- in: `workflow/skills/panel/SKILL.md` —— 反锚定补上「回退 verify.md 不够,
  diff 区间里的旧版本照样会被内联」,并给出真做干净的办法。
- in: 两份 skill 副本同步(`workflow/skills/` 是规范源,`.claude/skills/` 是部署副本),
  `sync-workflow-docs --check` 必须干净。

## Non-goals

- **不改 `runlog` 的判定逻辑**:`source-stable` 判得对、65 也该报,今天两次都是它对我错。
  只让它把话说清楚。
- 不动 panel 的反锚定**实现**(那道 WARNING 报得对),只补它的说明。
- 不回头改 OpenDesign 那两单的工件 —— 那边已经如实记账并归档了。
