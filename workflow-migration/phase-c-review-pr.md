# 阶段 C:`review-pr`(给本机 agent 的实现单)

计划见同分支 `WORKFLOW-MIGRATION-PLAN.md` 阶段 C。放行关卡(OpenDesign PR #10,`.github/aiwork-gate/`)已经写好,
它**只认**按本文件第 3 节格式、由 `aiwork-review[bot]` 发出的 PR 评审。`review-pr` 就是产出这种评审的唯一入口。

## 1. 接口

```
review-pr <PR号> [--repo owner/name] [--leg <腿名>] [--dry-run]
```

- 默认 `--leg subcodex`(OpenAI 家族)。high 路径的第二家族入口 = 同一命令指定另一条腿,先固定 `--leg subdeepseek`(DeepSeek 家族)。
- 只接受认得出家族的腿(`bin/_review_result.py` 的 `leg_identity`):固定模型的腿查 `ADAPTER_IDENTITIES`;`subcursor` 是通道,家族跟着这次用的模型走 —— 开跑时冻结一次模型(`CURSOR_MODEL`,没设就读 `bin/cursor-model`,和评审组同一个来源),传给腿、事后按它核对;认不出家族的模型(`auto` 之类)直接拒绝。**不按家族拒绝**:哪一家的评审对哪个 PR 算数,由 OpenDesign 的关卡判(`.github/aiwork-gate/decide.mjs`),`review-pr` 只负责把家族如实写进结论块。
- `--dry-run`:照常跑评审,但只把要发的评审正文打印出来,不发到 GitHub。
- `--repo` 是本次任务的目标仓库，默认仍为 `SunJ1ayu/OpenDesign`；API、快照、任务标题和发布都用它。令牌用 `gh-app-token review --repo owner/name`，只在角色既有配置范围内收窄，不改变 App 权限或安装范围。
- 评审口径统一从 GitHub 上 aiwork 的 main 读取 `REVIEW-RULES.md`，任务书附来源提交号；读不到时拒绝评审、不发任何内容。目标项目无需保存规则副本，已接受风险仍从目标项目 main 的 `.aiwork/accepted-risks.md` 读取。
- 放在 aiwork 的 `bin/review-pr`,按 aiwork 本机的正常流程提交;`gh-app-token` 也在这次一起收进 aiwork 的 `bin/`(阶段 B 时先放在 `/usr/local/bin`)。

## 2. 步骤

1. **取 PR**:`GET /repos/<owner/name>/pulls/<PR号>`，核对响应的 base 仓库，记下 `head.sha`(下称 HEAD)、`head.ref`、`base.ref`。PR 不是 open 或仓库不符就退出。
2. **快照**:在一个临时目录里拿到**正好是 HEAD** 的代码(`git fetch` 这个提交后检出,核对 `git rev-parse HEAD` 等于 HEAD),并算出相对 base 的改动(merge-base 起的 diff 和改动文件清单)。快照目录只读给评审腿用,用完删掉。
3. **任务书**:写明这是目标仓库的 PR #N 在 HEAD 上的**完整评审**,附改动文件清单和 diff,要求评审腿读改动涉及的文件、按现行评审口径给出独占一行的 `Conclusion: PASS|BLOCK|NEEDS_MORE_INFO`。沿用 aiwork 现有评审任务书的写法,不另起一套口径。**任务书里原样附上 aiwork main 的 `REVIEW-RULES.md`（评审口径，标明完整提交号）和 PR 所在项目 main 的 `.aiwork/accepted-risks.md`（没有这个文件就写"无"）**。规则按先解析出的 aiwork main 提交读取，风险从项目 main 读取；不从本地工作区或 PR 里读（PR 不能改评它自己的口径）。`REVIEW-RULES.md` 读不到就报错退出、不评审、不发任何内容（没有口径的评审不算数）。
4. **跑腿**:`bin/<腿名> review <任务书> <日志> <快照目录>`,然后用 `bin/_review_result.py` 规整出 ReviewLegResult(不在 `review-pr` 里自己解析结论行)。腿的日志 = 以 `# <腿名> <模式> log` 开头的表头 + 一个空行 + 模型原文;评审正文只取空行之后的原文。日志不是这个格式就报错、不发(不去猜哪一段是表头)。
5. **组结论块**(第 3 节),字段全部由 `review-pr` 从 ReviewLegResult 和快照填,**不让模型自己写**:
   - `verdict`:ReviewLegResult 的 verdict;
   - `head_sha`:HEAD;
   - `model`:这次实际用的模型名;`family`:`leg_identity` 给出的家族(`subcursor` 按冻结的模型);
   - `completeness`:只有"进程正常退出、结论解析成功、没降级、证据完整"才是 `complete`;其余按实际写 `partial` 或 `none`;
   - `files_read`:评审腿实际读过的文件;适配器报不出来时,用"完整快照视图下交给它的改动文件清单"。不能是空数组。
6. **发之前再核一次 HEAD**:重新 `GET` 这个 PR,`head.sha` 已经不是 HEAD(评审期间有新推送)⇒ **不发**,退出码非 0,提示重跑。
7. **发评审**:`POST /repos/<owner/name>/pulls/<PR号>/reviews`(与第 1 步同一目标仓库),`commit_id` = HEAD,`event` = `COMMENT`(不管 PASS 还是 BLOCK 都用 COMMENT;**不用 APPROVE / REQUEST_CHANGES**),`body` = 第 3 节格式。打印评审链接。
8. 评审腿没跑成(超时、额度、鉴权、没有结论)⇒ **什么都不发**,退出码非 0,原样报原因。不重试、不换腿(换腿由人或以后的 OpenClaw 决定)。

## 3. 评审正文格式(关卡按这个认)

```
**aiwork-review · <腿名> · <model>**

<模型的评审意见原文(见下面的净化)>

```json
{"verdict":"PASS","head_sha":"<40 位小写提交号>","model":"<模型名>","family":"<家族>","completeness":"complete","files_read":["路径1","路径2"]}
```
```

关卡的核对规则(`.github/aiwork-gate/decide.mjs` 的 `parseReviewBlock`):

| 字段 | 要求 |
|---|---|
| 结论块 | 正文里**恰好一个** ` ```json ` 块,是一个 JSON 对象 |
| `verdict` | `PASS` / `BLOCK` / `NEEDS_MORE_INFO` / `UNKNOWN` |
| `head_sha` | 40 位小写十六进制,且等于评审挂的提交(`commit_id`)和 PR 当前 head |
| `model` | 非空字符串 |
| `family` | 小写字母开头,只含小写字母、数字、`-`(如 `openai`、`deepseek`) |
| `completeness` | `complete` / `partial` / `none`;只有 `complete` 的 PASS 才算 |
| `files_read` | 字符串数组,每项非空;PASS 要求至少一项 |

**看不懂就按 BLOCK**:格式不对的评审(结论块缺字段、不止一个、不是 JSON、没有,或正文 `Conclusion:` 行和结论块的 verdict 不一样)、以及**发出后正文被改写过**的评审,关卡一律按 BLOCK 算,要业主在其后批准才能豁免。所以 `aiwork-review` 只用来发结论评审,不要用它回复评论(回复也会生成一条空正文的评审),**也不要改写已发出的评审** —— 要改结论就发一条新的。

**净化**:模型原文里如果出现 ` ```json `,改成 ` ```text ` 再放进正文,否则正文里就不止一个结论块,关卡会按 BLOCK 算。

## 4. 验收(本机先测,再做计划第 4 节的 PR #6 端到端回放)

1. `--dry-run` 在一个真实 PR 上跑:打印出的正文只有一个 ` ```json ` 块,字段齐全,`head_sha` 等于 PR 当前 head,`family` 是 `openai`。
2. 同一 PR 用 `--leg subdeepseek --dry-run`:`family` 是 `deepseek`。
3. `--leg` 给一个认不出家族的腿,或 `--leg subcursor` 配一个认不出家族的模型(如 `auto`):直接拒绝,不跑。`--leg subcursor` 配任何认得出的模型(包括 Claude):照常评审,`family` 是那个模型的家族。
4. 净化:构造一段含 ` ```json ` 的"模型原文",组出的正文仍只有一个 ` ```json ` 块。
5. HEAD 变了:评审期间往 PR 推一个新提交(或用假数据模拟第 6 步读到不同的 head),不发、退出码非 0。
6. 真发一次:评审出现在 PR 上,署名 `aiwork-review[bot]`,挂在当前 head;几十秒内 PR 上的 `aiwork-gate-shadow` 检查重算。
7. 评审腿失败(例如给一个不存在的模型):什么都不发,退出码非 0。

做完停下,报告每条的结果和发出去的评审链接。**不要自己去合并或批准任何 PR。**
