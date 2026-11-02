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
2. 核实：按 [REVIEW-RULES 第二节第 3 条「核实与五级证据」](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md#3-核实与五级证据)执行，逐条对照本 skill「汇总核对清单」。
3. 定级：见 REVIEW-RULES 第二节第 1 条。
4. 决定下一步：按 REVIEW-RULES 第三节第 5 条的优先顺序。选「合并」之前，先看关卡在当前 head 上的结论：除了业主批准还缺别的（比如额度不够、凑不齐几家不同家族的 PASS），就选交业主，写明缺什么。派修改单的规则和格式见 `delegate` skill。P2 放不放进这张单，见 REVIEW-RULES 第三节第 4 条。
5. 发到 PR 上：使用项目策略 `modification_rounds.summary_account` 登记的账号，向这次核实的完整 head 提交一条 COMMENT 评审，正文按本 skill「汇总的格式」。发出后不编辑；纠错先交业主，不用改写或再发一条相互冲突的记录覆盖。关卡复用评审和改写记录读取它；汇总不批准、不贴合并标签、不推代码。未启用该策略的项目保持原来的非 `reviewer_bot` 账号 COMMENT 做法，关卡不显示轮数。
6. 下一步写「合并」或「交业主」的那次汇总，当场把这个 PR 历次汇总里还没记的 P2 都按 REVIEW-RULES 第二节第 1 条「待办与业主决定」记入项目待办。

## 汇总核对清单

每个 PR 各记一份：从本 PR 此前评审、汇总里已核实的坑整理，留在 PR 的汇总记录里；第一次没有历史时可以为空。本轮新核实的坑补入，后续汇总逐条对照实际改动和运行结果。任务单怎么写，见 `delegate` skill。

## 汇总的格式

- 标题：独立审核 · head <短提交号> · 第 N 次汇总
- 这一次做对了什么；核实记录见 REVIEW-RULES 第二节第 3 条；各家结果（谁 PASS、谁 BLOCK、谁 NEEDS_MORE_INFO 及缺什么、谁失败及原因）；
- 汇总核对清单及核对结果，见本 skill「汇总核对清单」；
- 每条 P1：要写的项见 REVIEW-RULES 第二节第 2 条，再补哪家提的；派修改单的规则和格式见 `delegate` skill；
- P2、P3；
- 刹车：按 REVIEW-RULES 第三节第 1 条的读数口径核对并记录轮数与停信号；
- 「评审的处理」表：来源 | 处理；
- 结论行在前：写法见 REVIEW-RULES 第二节第 2 条。
- 下一步行在后：填 REVIEW-RULES 第三节第 5 条里的一档。

启用 `modification_rounds` 的项目在同一条评审正文中放恰好一个下列定义 `title` 命名的记录围栏，块内是符合定义的 JSON 元数据；这是机器记录格式的唯一定义。评审的 `commit_id` 必须与 `head_sha` 一致，正文下一步和是否有 P1 必须与元数据一致。

真正的记录围栏在正文顶层，起止行都顶格写三个反引号，起始行的围栏名紧跟反引号；行尾可有空格或制表符，换行可用 LF 或 CRLF。缩进 1–3 格、围栏名前留空白或用其他围栏写的同名顶层记录都是错格式，显示读不清。证据和修改单里引用、举例的旧记录用 Markdown 块引用（每行加 `> `），或包在另一个代码围栏里（反引号围栏须比内层长，也可用波浪号）；引用内部的同名围栏不算记录，单独出现也不把未知变读不清。四格缩进的代码同样不是顶层记录；两个未被引用的记录仍然读不清。以下是引用示例，测试直接读取这些示例与关卡对照：

`````markdown
> ```aiwork-summary
> {"head_sha":"0000000000000000000000000000000000000000","next_step":"合并","has_p1":false}
> ```
`````

`````markdown
````markdown
```aiwork-summary
{"head_sha":"0000000000000000000000000000000000000000","next_step":"合并","has_p1":false}
```
````
`````

`````markdown
~~~markdown
```aiwork-summary
{"head_sha":"0000000000000000000000000000000000000000","next_step":"合并","has_p1":false}
```
~~~
`````

完整修改单是记录围栏结束后的全部 Markdown，直接写标题、换行、列表和代码块，不放进 JSON 字符串，也不另抄一份；机器读取这段原文。`next_step` 为「照单修」时，这段正文必须非空。没有修改单时围栏后留空；核实证据、结论、表格等都放在记录围栏前。

```aiwork-summary-schema
{
  "title": "aiwork-summary",
  "type": "object",
  "additionalProperties": false,
  "required": ["head_sha", "next_step", "has_p1"],
  "properties": {
    "head_sha": {"type": "string", "pattern": "^[0-9a-f]{40}$"},
    "next_step": {"type": "string", "enum": ["交业主", "照单修", "合并"]},
    "has_p1": {"type": "boolean"}
  },
  "allOf": [
    {
      "if": {"properties": {"next_step": {"const": "照单修"}}},
      "then": {"properties": {"has_p1": {"const": true}}}
    },
    {
      "if": {"properties": {"next_step": {"const": "合并"}}},
      "then": {"properties": {"has_p1": {"const": false}}}
    }
  ]
}
```

关卡只认登记账号发出且未改写的记录，按不同 `head_sha` 的「照单修」计数；同一 head 的重复记录只计一次，字段或修改单原文不同则读不清。合入 main、失败腿重派和小改本身不加轮。同一记录以最早的提交时间、再按最小评审编号确定首次出现，迟到的重复记录不更新它的时刻；去重后最新汇总按提交时间、再按评审编号确定，与接口返回次序无关；停的定义见 REVIEW-RULES 第三节第 1 条。没新记录的旧 PR 显示未知；带记录围栏的评审被改写、格式错误、head 不一致或记录冲突显示读不清；无记录围栏的评审不参与计数。此显示不改变 G1–G8 或合并结果。
