---
name: summary
description: 一轮评审跑完以后，汇总各家结论、核实、定级，决定下一步。
---

# summary — 一轮评审的汇总

评审与修复规则见 [REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md)，项目已接受风险见项目 main 的
`.aiwork/accepted-risks.md`，放行条件见项目关卡策略。这里只说汇总这一步怎么做。

汇总是流程里固定的一步，不是谁的习惯：现在由业主派的一个独立会话做，以后由 OpenClaw 叫醒一个能读代码、跑测试的强模型来做，做法都按这份。

## 什么时候做

什么时候汇总，见 REVIEW-RULES 开头「一轮」的定义。腿怎么审，见 REVIEW-RULES 第四节「多条评审腿审同一个 PR」第 1 条；跨轮次、跨各家的判断都在汇总这一步做。

## 读什么

- 当前 head 上各家的评审；
- PR 说明，内容要求见 REVIEW-RULES 第一节「PR 说明」；
- 这个 PR 前几次汇总（发在 PR 上）；
- 业主写下的有效决定，查阅和记录方式见 REVIEW-RULES 第二节第 1 条「待办与业主决定」。结论取决于业主没写下来的意图时，见 REVIEW-RULES 第三节第 1 条。

## 怎么做

1. 去重：同一处问题合成一条，注明哪几家提的。
2. 核实：复现各家报的 P1、跑和这次改动相关的测试、补 CI 覆盖不到的检查（比如要在 PR 分支上真跑的、要先红的）。CI 在当前 head 上绿时，只做这三件事，不重跑全套；CI 没绿或者拿不到结果时，还要在断网的隔离副本里跑全套测试。算不算 P1，见 REVIEW-RULES 第二节第 1 条；复现不了还说不清时，见第四节「多条评审腿审同一个 PR」第 3 条。新测试先红怎么算，见 REVIEW-RULES 第一节第 3 条第 1 步；要真机才能确认的，标成待业主确认。上述核实按本 skill「汇总核对清单」逐条对照。
3. 定级：见 REVIEW-RULES 第二节第 1 条。
4. 决定下一步：按 REVIEW-RULES 第三节第 5 条的优先顺序。选「合并」之前，先看关卡在当前 head 上的结论：除了业主批准还缺别的（比如额度不够、凑不齐几家不同家族的 PASS），就选交业主，写明缺什么。派修改单的规则和格式见 `delegate` skill。P2 放不放进这张单，见 REVIEW-RULES 第三节第 4 条。
5. 发到 PR 上：使用项目策略 `modification_rounds.summary_account` 登记的账号，向这次核实的完整 head 提交一条 COMMENT 评审，正文按本 skill「汇总的格式」。发出后不编辑；纠错先交业主，不用改写或再发一条相互冲突的记录覆盖。关卡复用评审和改写记录读取它；汇总不批准、不贴合并标签、不推代码。未启用该策略的项目保持原来的非 `reviewer_bot` 账号 COMMENT 做法，关卡不显示轮数。
6. 下一步写「合并」或「交业主」的那次汇总，当场把这个 PR 历次汇总里还没记的 P2 都按 REVIEW-RULES 第二节第 1 条「待办与业主决定」记入项目待办。

## 汇总核对清单

汇总把已知的坑记成核对清单，留在 PR 的汇总记录里，交活后逐条对照实际改动和运行结果，供后续会话接着核对。任务单怎么写，见 `delegate` skill。

## 汇总的格式

- 标题：独立审核 · head <短提交号> · 第 N 次汇总
- 这一次做对了什么；核实了什么（跑了什么、结果如何）；各家结果（谁 PASS、谁 BLOCK、谁 NEEDS_MORE_INFO 及缺什么、谁失败及原因）；
- 汇总核对清单及核对结果，见本 skill「汇总核对清单」；
- 每条 P1：要写的项见 REVIEW-RULES 第二节第 2 条，再补哪家提的；派修改单的规则和格式见 `delegate` skill；
- P2、P3；
- 刹车：引用关卡算出的轮数与停信号，上限见项目 `.aiwork/policy.json` 的 `modification_rounds.limit`；未知或读不清时交业主核实，不自行填零或猜数；
- 「评审的处理」表：来源 | 处理；
- 结论行在前：写法见 REVIEW-RULES 第二节第 2 条。
- 下一步行在后：填 REVIEW-RULES 第三节第 5 条里的一档。

启用 `modification_rounds` 的项目在同一条评审正文中放恰好一个围栏代码块，语言名取下列定义的 `title`，块内写符合定义的 JSON；这是机器记录格式的唯一定义。评审的 `commit_id` 必须与 `head_sha` 一致，正文的下一步和 P1 清单必须与块内一致。`modification_task` 放完整修改单正文（含换行时按 JSON 转义），不再只在聊天里转发；没有修改单时写空字符串。其他核实证据和表格仍写在块外。

```aiwork-summary-schema
{
  "title": "aiwork-summary",
  "type": "object",
  "additionalProperties": false,
  "required": ["head_sha", "next_step", "has_p1", "modification_task"],
  "properties": {
    "head_sha": {"type": "string", "pattern": "^[0-9a-f]{40}$"},
    "next_step": {"type": "string", "enum": ["交业主", "照单修", "合并"]},
    "has_p1": {"type": "boolean"},
    "modification_task": {"type": "string"}
  },
  "allOf": [
    {
      "if": {"properties": {"next_step": {"const": "照单修"}}},
      "then": {"properties": {"has_p1": {"const": true}, "modification_task": {"pattern": "\\S"}}}
    },
    {
      "if": {"properties": {"next_step": {"const": "合并"}}},
      "then": {"properties": {"has_p1": {"const": false}}}
    }
  ]
}
```

关卡只认登记账号发出且未改写的记录，按不同 `head_sha` 的「照单修」计数；同一 head 的重复记录只计一次，字段不同则读不清。合入 main、失败腿重派和小改本身不加轮。最新汇总按提交时间、再按评审编号确定；到上限且最新汇总仍有 P1 时显示停信号。没新记录的旧 PR 显示未知；改写、格式错误、head 不一致或记录冲突显示读不清。此显示不改变 G1–G8 或合并结果。
