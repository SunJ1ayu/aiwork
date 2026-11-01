# aiwork-gate(放行关卡)

关卡代码取自 SunJ1ayu/OpenDesign `05fe41b97ba94b86bb31f032adb763b1b1576a5e` 的 `.github/aiwork-gate/`。判定行为不变。策略不跟代码走：workflow 把调用方检出里的 `.aiwork/policy.json` 放进 `AIWORK_POLICY_PATH`。

规则来历在 git 历史里。

G3 的合格 PASS 条件见 `decide.mjs`。结论块的必填字段由 `parseReviewBlock` 定义；
`files_read` 不再要求或检查，旧评审带着它也照常判定。这个字段原来是 PR 的改动文件清单，不能证明评审实际读过文件。

| 文件 | 做什么 |
|---|---|
| `collect.mjs` | 只读 GitHub API 收集事实;出错、分页没取完、条数对不上一律抛错(G8) |
| `decide.mjs` | 纯判定,不碰网络(G1–G7) |
| `run.mjs` | 流程:每次运行把所有开着的 PR 全重算一遍(事件只是门铃)。列出开着的 PR、按 head 分组 → 先在每个 head 上占位 → 每个 head 把以它为 head 的 PR 全判一遍、合成一个结论写一次;读不全就不放行;写上的是放行,就合并有合并请求的 PR(见下「合并」) |
| `main.mjs` | 接线:真实 API、`aiwork-gate` App 令牌、发 / 改检查、合并。策略路径只认 `AIWORK_POLICY_PATH` |
| 调用方的 `.aiwork/policy.json` | 策略:判卷面、high 路径、`high_min_families`、Builder、评审 App、检查名、App ID、合并标签和谁贴的算数 |

测试:`tests/test_aiwork_gate.mjs`(判定与收集)、`tests/test_aiwork_gate_run.mjs`(流程与失败处理)、
`tests/test_aiwork_gate_main.mjs`(假 GitHub API 上真跑 `main.mjs`)、`tests/test_aiwork_gate_workflow.mjs`(workflow 形状和本仓库策略)。
从 OpenDesign 仓库内容推导 policy 清单的测试留在 OpenDesign。

## 修改轮数显示

项目可在策略中配置 `modification_rounds`，其中可选的 `limit` 是正整数覆盖值（省略时的上限来源见下段），`summary_account` 是汇总账号，不能兼任评审机器人或合并申请人（含业主）。汇总账号与 Builder 的互斥检查按 [业主决定](https://github.com/SunJ1ayu/aiwork/issues/107#issuecomment-6536969415) 推迟；SunJ1ayuBoT 暂时保留原 Builder 登记。未配置时，关卡输出和行为保持原样。aiwork 启用此项；其他项目要用时修改自己的策略。

上限与停的定义见 `REVIEW-RULES.md` 第三节第 1 条。记录格式和计数约定见 `workflow/skills/summary/SKILL.md`「汇总的格式」，由 `tests/test_aiwork_gate_rounds.mjs` 从定义读取并对照。关卡复用已经取全的 PR 评审与 GraphQL 改写时间，不增加请求；`decide.mjs` 只追加显示，`run.mjs` 在共享 head 的结论中保留每个 PR 的轮数和停信号，G1–G8 和合并条件不变。新汇总通过已有评审门铃重算。

启用后的已有 PR 没有新格式记录时显示「未知」。汇总从合并后的下一次起使用新格式，不回填历史修改单。

## 新项目接入

只有一种接法。

1. 把 `templates/aiwork-gate.yml` 和 `templates/aiwork-review-ping.yml` 复制到项目的 `.github/workflows/`，文件名不变。
2. 写该项目自己的 `.aiwork/policy.json`，要有 `high_min_families`（high 路径要几家不同家族的合格 PASS，G6 读这个字段）。`check_name` 在只报不拦阶段用 `aiwork-gate-shadow`。
3. 把 `aiwork-gate` App 装到该仓库。发检查要 Checks 读写；合并还要 Contents、Pull requests、Workflows 读写。改了 App 权限后，要在仓库的安装处接受新权限。
4. 建 environment `aiwork-gate`，部署分支只许 `main`，不设审批人，放入 secret `AIWORK_GATE_PRIVATE_KEY`。
5. 只报不拦阶段不要把检查设为必过。转真拦截见文末。

`aiwork-gate.yml` 先检出本仓库默认分支（拿 `.aiwork/policy.json`），再检出 `SunJ1ayu/aiwork` 的 `main`（拿 `gate/`），然后在后者的目录里运行 `node gate/main.mjs`。策略路径由 `AIWORK_POLICY_PATH` 传入。触发方式、并发组 `aiwork-gate`、environment、权限和 `persist-credentials: false` 都在模板里，不要另写一套。

关卡 workflow 的 `GITHUB_TOKEN` 只读权限见 `templates/aiwork-gate.yml` 的 `permissions`。

## 一次性设置

- `aiwork-gate` App(App ID 写在 `policy.json` 的 `gate_app_id`):只装在本仓库。权限 Checks 读写(发检查),
  Contents、Pull requests、Workflows 读写(合并:合并接口要前两个;PR 改了 `.github/workflows/` 的,GitHub 还要
  Workflows 才让 App 合)。改了 App 的权限,要在仓库的安装处接受新权限才生效。
  私钥能合并 PR 之后,它和 main 本身一样要紧。
- 标签 `aiwork:merge`(`policy.json` 的 `merge_label`)。
- main 的分支规则见下方「已接入仓库迁移」。
- environment `aiwork-gate`:部署分支只许 `main`,**不设审批人**;私钥放在它的 secret `AIWORK_GATE_PRIVATE_KEY`。
  设了审批人,关卡每次都要等人点,等的时候检查停在旧值。

## 已接入仓库迁移

按旧说明接入、仍要求保险丝或允许管理员绕过的仓库，必须先改规则，再让不写保险丝的新关卡代码生效：

1. 业主在 main 的必需检查中摘掉 `aiwork-gate/fuse-check`，只留 `aiwork-gate`（来源限定 `aiwork-gate` App）。
   保留「合并前分支必须和 main 同步」（Require branches to be up to date），原因见下方「合并」。
2. 业主创建或收紧独立的 `main-gate-merge-only` 规则集：目标 main，只勾 Restrict updates；绕过名单只留
   `aiwork-gate` App（For pull requests only），移出 Repository admin 和其他绕过者。
   这条规则必须独立于必需检查：绕过名单绕过的是整个规则集，放在一起会让 App 连必需检查也绕过。
3. 确认两项规则均已保存，再让新的关卡代码进入 aiwork main。
   调用仓库每次运行都从 aiwork main 取代码，不能等代码生效后再补前两步。
4. 代码生效后，各调用仓库按「新项目接入」同步两份 workflow；同步前的一致性 CI 会红。按 S15 验收管理员网页合并被拒。

依据见 [业主决定](https://github.com/SunJ1ayu/aiwork/issues/111#issuecomment-6552793090)。aiwork 和 OpenDesign
已完成前两步，见[规则补记](https://github.com/SunJ1ayu/aiwork/issues/111#issuecomment-6552923695)；管理员网页被拒的实测记录见 `ACCEPTANCE.md` 的 S15。
新接入仓库转真拦截时也按第 1–2 步配置规则；已有规则就更新，不另建一套。

## 事件只是门铃;同一时间只有一次运行

- **每次运行把所有开着的 PR 全重算一遍**,结论只取决于 GitHub 上的现状,与是哪个事件叫醒的无关。
  以前从事件推"该算哪个 PR、写到哪个提交",漏过好几次(没带 PR 的 workflow_run、旧提交、合并提交、指向默认分支的)。
- **同一时间只有一次运行**:workflow 的并发组是固定名字 `aiwork-gate`,不取消正在跑的;排队的只留最新一个
  (GitHub 自己会把更早排队的取消),它开始时读到的一定不比被它顶掉的旧,而它又会重算全部 PR,所以顶掉的不会漏算。
  于是同一提交上后写的结论一定出自后读的数据 —— 不会有慢一步的旧运行盖掉新结论。
  同名检查后发的一定后写完,GitHub 按创建还是按完成时间取"最新",取到的都是
  最后一次运行的;运行半路死掉时,已创建且未完成的占位检查停在 in_progress,照样挡着,下一次运行全部重算。
- job 上**不许**按事件过滤(比如只认某个标签):排队时被顶掉的运行,要靠顶掉它的那次来算。
- 代价:稳定列表、各接口只需一页、不合并时，设开着的 PR 数为 P、不同 head 数为 H：
  每次 `GITHUB_TOKEN` 要两次读 PR 列表、每 PR 六次 REST 读取和一次 GraphQL 查询，
  即约 `2 + 6P` 次 REST 请求和 P 次 GraphQL 查询；分页或列表不稳定会更多。
  App 另有每 head 两次检查写入，以及每次运行一次安装查询和一次换检查令牌请求；没有 head 时不换 App 令牌。
  合并时还会另查安装、换合并令牌并逐 PR 发合并请求，这些不算进上述 `GITHUB_TOKEN` REST 数。
  设 T 为模板 cron 每小时的分钟刻度数，D=24T；定时的 REST 用量为 `T × (2 + 6P)`/小时，
  每个 head 每天的 App 检查写入为 2D 次、新检查为 D 条；事件触发另加，Actions 和 runner 占用也增加。
  `GITHUB_TOKEN` 的 REST 限额 L 为每仓库每小时 1000 次（[GitHub 官方配额](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api#primary-rate-limit-for-github_token-in-github-actions)），
  GraphQL 另按查询成本计额，不把 App 请求混进这一额度。
  下表按实际 cron 推导，由 workflow 测试比对；示例假设每 PR 不同 head（P=H），单轮 REST 为 `R=2+6P`：

| 依据 | 每小时轮数 T | 每天轮数 D | P=H=30 时 REST/小时 | 每 head 每天 App 写入 | 每 head 每天新检查 | 加 1 轮事件即超额的最小 P=H | 光定时即用满/超额的最小 P=H |
|---|---|---|---|---|---|---|---|
| 当前 cron | 4 | 96 | 728 | 192 | 96 | 34 | 42 |

  将示例的 REST/小时列与 L 比较即可判断余量；达到倒数第二列的规模后，定时加一轮完整事件重算就会超过 L，事件重算已无足够预算；
  达到最后一列时，光定时就用满或超过 L。一般情况下，R 取实际单轮 REST 用量，额外完整事件轮数的预算是 `max(0, floor(L/R) - T)`。
  这些边界只按计划的定时轮数计算，未留分页、合并、列表不稳定或其他 workflow 的余量，实际应更早降频或减少用量；
  队列合并/取消不作为节省配额的保证。限额打满会让后续事件读取或写回失败，不代表事件有优先保留的额度。
  限流、分页读不全会按失败处理；请求失败到检查写回之间仍有下文说明的最终一致窗口。
- 同一提交反复写入：不再追加 commit status（同一 SHA/context 到 1000 条会拒绝继续写）；
  App 检查在单次运行内创建再改写，同一 check suite 内同名检查超过 1000 条时 GitHub 自动删除旧检查，不会因历史次数写满。
  旧检查历史可能被淘汰，不能把 GitHub 检查列表当永久审计存档。平台上限见
  [status 文档](https://docs.github.com/en/rest/commits/statuses#create-a-commit-status)和
  [check run 文档](https://docs.github.com/en/rest/checks/runs#create-a-check-run)。
- 一次运行里先给所有 head 发 App 的 in_progress 占位,之后才读 PR 的数据;单个请求的
  超时配置见 `main.mjs` 的 `AIWORK_GATE_TIMEOUT_MS`，卡住的请求拖不垮整次运行。开着的 PR 的列表连读两遍一致才算数(翻页期间有 PR 关掉,
  后面的会往前挪、漏掉一个)。

## 每样输入的门铃

关卡的结论是它读到的输入的函数;哪样输入变了没有门铃,旧结论就一直挂着。

| 关卡读的输入 | 变了靠什么叫醒 |
|---|---|
| PR 的 head、改动文件、推送记录 | `pull_request_target`:`opened` / `synchronize` / `reopened` |
| 目标分支(G1 要 CI 晚于最后一次改目标分支) | `pull_request_target`:`edited` |
| 开着的 PR 有哪些(同一提交上几个 PR 合在一起判) | `pull_request_target`:`opened` / `reopened` / `closed` |
| CI(以最后开始的那次执行为准) | `workflow_run`(ci):`requested` / `in_progress` / `completed`(重跑不一定发 `requested`,开始跑时会发 `in_progress`) |
| 评审(读当前正文;机器人评审发出后被改写过一律按 BLOCK、时刻按改写那一刻;人的评审被撤销按撤销那一刻) | `aiwork-review-ping`:`submitted` / `edited` / `dismissed` → `workflow_run` |
| 策略 `.aiwork/policy.json`(只认 main 上的) | 改 main 之后 CI 跑完的 `workflow_run` |
| 关卡代码（aiwork main 的 `gate/`） | `schedule`：计划间隔 15 分钟，具体 cron 见模板；[2026-10-30 实测](https://github.com/SunJ1ayu/aiwork/issues/98#issuecomment-6526765438)约每 4–7 小时一次。GitHub 可能延迟、丢弃或停用定时任务，不能保证准时；用途与限制见下方「定时重算」 |
| 合并请求(PR 上有没有 `aiwork:merge`、最后是谁贴的) | `pull_request_target`:`labeled`(撤掉标签不用叫醒:只会少合并,下一次运行自然读到) |
| 手动重算 | 给 PR 加任何标签(如 `aiwork:recheck`) |

### 定时重算：门铃漏响时的补救

按[业主决定](https://github.com/SunJ1ayu/aiwork/issues/98#issuecomment-6554312340)，保留定时重算，不追求准时，也不另加跨仓库叫醒机制。
它在其他门铃漏响时自动补算：重新检出最新的 aiwork main，按现状重算全部开放 PR、补写结论，
并为已有有效合并请求、且本次判为放行的 PR 补上合并。正常合并路径见下方「合并」；在该路径的分支规则前提下，
PR 上挂着的旧结论只影响显示。旧放行残留的场景及已接受风险见 `.aiwork/accepted-risks.md` 第 7 条。

计划与实测频率见上表。计划间隔不是实际等待或写回的时限；成功运行还要经过并发队列、runner 分配、检出和重算，
job 的执行超时见模板。定时任务只使用默认分支上的 workflow；公开仓库
**60 天**没有活动会自动停用定时任务，恢复活动后也要确认 workflow 已重新启用。相关平台行为见
[GitHub 的 schedule 说明](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)。
Actions 被关、environment 等审批、检出/API 失败时，定时任务也无法完成补算；恢复运行后可用上表的手动门铃重算。
定时器不能消除下方「已知限制」所述的最终一致窗口。

## 已知限制:状态检查只能"最终一致"

关卡靠"输入变了 → 叫醒 → 重算 → 写回",写在提交上的结论总是某一刻的。这种做法本身有补不死的上限,
写在上面这几句里。项目若接受它,记在项目的 `.aiwork/accepted-risks.md`。经合并标签合并的 PR 不靠提交上的旧结论,见下「合并」。

## 合并:贴 `aiwork:merge`

- **谁贴的算数**:业主(`policy.json` 的 `owner`)和 `merge_requesters` 里的账号(以后放 OpenClaw 的身份)。
  Builder 贴的不算,也写不进名单(策略校验会拒)—— 不然 Builder 能把自己的 PR 合进去。
  认的是 PR 事件里最后一次贴这个标签的人:撤掉再贴,按最后一次算。
- **不另起一套判定**:关卡每次运行照常把所有开着的 PR 判一遍;某个 head 的 App 结论写上了、
  而且是放行,就当场合并这个 head 上有合并请求的 PR。合并用的就是这次刚读到的数据,调合并接口时带上判过的
  head(`sha`):判完之后又推了新提交,接口会拒,不会把没判过的提交合进去。
- **没放行的请求留着**:之后哪次运行判为放行,就在那次合。不想合了就撤掉标签(关卡正在合的那几秒里撤可能来不及,
  见项目的 `.aiwork/accepted-risks.md`)。
- **"在最新的 main 上测过"不归关卡判**:关卡读的输入(head、改动、评审、head 上的 CI、推送、标签)没有一样随 main
  前进而变,main 动了重判一遍结论也一样。这一点靠 main 规则集的「合并前分支必须和 main 同步」,它对 App 的合并同样生效:
  同一次运行里合了一个 PR,指向 main 的其他 PR 就落后了,GitHub 拒绝合并,请求留着;更新分支 → CI、评审重来 → 放行时再合。
  关了这条规则,关卡会把没和最新 main 一起测过的 PR 合进去。
- **合并没成**(分支落后于 main、有冲突、评审讨论没解决完、刚推了新提交):原因写在那次运行的摘要里,请求留着。
  处理完之后,推送、评审都会叫醒下一次运行再合;没有门铃的(比如把讨论标为已解决),加个 `aiwork:recheck`。
- 合并用 App 另换的一张令牌(Contents / Pull requests / Workflows 写权限),只在真要合并时才换;发检查的那张始终只有 Checks。
- main 的规则与迁移顺序见上方「已接入仓库迁移」；本轮写不了新结论时的显示结果与已接受风险见 `.aiwork/accepted-risks.md` 第 7 条。
  取消不撤销已经完成的合并；未合并的 PR 由下次运行重新判定后合并。

## 同一提交上有几个 PR

检查都挂在**提交**上,不是 PR 上。同一提交可以同时是几个开着的 PR 的 head(目标分支不同,改动和要求就不同)。
所以写 success 之前,关卡把这个提交上其他开着的 PR 也判一遍:**全都放行才放行**,有一个不放行就不放行,
查不到就按 G8 失败。

## 模型按任务切换角色

作者识别继续用 `collect.mjs` 的实际推送活动和 `decide.mjs` 的 `authorOf`，策略来源仍是 main。
已知作者时，登记过的其他 Builder 家族可以审这次 PR；审核排除只针对本次作者家族。
作者 UNKNOWN 时保留原有保守处理，不从共享 build 账号猜测实际模型。
本改动不新增可信执行来源，也不改变 App 权限、模型账号配置或云平台接入。

## 首次部署验收(shadow:检查名 `aiwork-gate-shadow`,只报不拦)

合并后,用一个无害的测试 PR(云端 Claude 以机器账号开)逐条看。每条写下 PR 号、提交号和检查的链接。

| # | 做什么 | 预期 | 证明了什么 |
|---|---|---|---|
| S0 | 合并本 PR 后看 main 上 CI 跑完触发的那次 aiwork-gate | 运行成功,只重算开着的 PR;main 的提交上**没有** `aiwork-gate-shadow` | 事件只是门铃,不往非 head 的提交上写 |
| S1 | 开测试 PR | 立刻出现 `aiwork-gate-shadow`(重算中 / 等 CI);检查的 app 是 `aiwork-gate`(id 5121026),不是 GitHub Actions | 占位先行;结果由 App 发出 |
| S2 | 等 CI 跑完 | failure「不放行:缺合格评审」;作者是 `builders` 里的账号,不在名单里就是 UNKNOWN | CI 按本 PR 认;活动记录接口在 `GITHUB_TOKEN` 下读得到 |
| S3 | 本机 `review-pr` 在当前 head 发 PASS(openai) | 一两分钟内自动重算为 success「放行」 | 评审 → `aiwork-review-ping` → 关卡重算这条链通 |
| S4 | 同一 head 再发一条 BLOCK | failure(G5);业主**在 BLOCK 之后**批准 → success | BLOCK 与批准的先后被认 |
| S5 | 业主在网页上改测试 PR 的一个文件(非机器账号推送) | failure,作者 UNKNOWN(G4);业主在新 head 批准 + 有 PASS → success | 混合作者要业主批准 |
| S6 | 测试 PR 改 `judging_surface` 里的一个文件 / 改 `high` 里的一个文件 | 分别要业主批准(G2)/ `high_min_families` 家不同家族 PASS + 业主批准(G6) | 判卷面与 high 路径 |
| S7 | 给 PR 加标签 `aiwork:recheck` | 重算一次;算的时候合并框里这条检查显示"重算中" | 手动重算可用;占位压得住上一次的结论 |
| S8 | 编辑测试 PR 的标题;再改一次目标分支 | 各重算一次;改目标分支后 G1 ❌「目标分支在这次 CI 之后改过」,推一个新提交(或关掉再重开 PR)让 CI 重跑后恢复 | edited 事件会触发重判;旧目标上的 CI 不算数 |
| S9 | 连着触发两次重算（比如先后加两个标签），看 Actions 里 aiwork-gate 的运行 | 两次运行一个跑完另一个才开始 | 同一时间只有一次运行 |

合并(本节在「合并」上线后补做,同样用无害的测试 PR):

| # | 做什么 | 预期 | 证明了什么 |
|---|---|---|---|
| S10 | 业主给一个会放行的测试 PR 贴 `aiwork:merge` | 那次运行放行后当场合并:合并者是 `aiwork-gate` App,合进去的是判过的 head | 合并用的是刚判过的数据和 head |
| S11 | 机器账号(Builder)给另一个会放行的测试 PR 贴 `aiwork:merge` | 不合并;运行摘要里写"是 SunJ1ayuBoT 提的,不算数" | Builder 合不了自己的 PR |
| S12 | 业主给一个还缺评审的测试 PR 贴 `aiwork:merge`,之后补上 PASS | 贴的时候不合;PASS 之后那次运行合并 | 请求留着,放行时才合 |
| S13 | 两个都会放行、都指向 main 的测试 PR,业主都贴上 `aiwork:merge` | 合进去一个;另一个被 GitHub 拒(分支落后于 main),摘要里写明,请求留着 | 连着合并时,后一个必须先和新的 main 一起测过 |
| S15 | 用已满足其他合并条件、未贴 `aiwork:merge` 的测试 PR，以仓库管理员身份在网页上尝试合并 | 被 `main-gate-merge-only` 拒绝更新 main，PR 未合并 | 管理员不能借提交上的放行绕过关卡合并 |

S14 是历史上的批准迁移样本，见 `ACCEPTANCE.md`「发现」；保留编号，不复用。

失败注入(API 出错、限流、App 私钥坏了、PR 中途推进、合并接口拒绝)在线上没法安全制造,由 `test_aiwork_gate_run.mjs`(R4–R5e、R14c、R20、R25–R26、M1–M10)与 `test_aiwork_gate_main.mjs`(含请求卡住)覆盖;几次运行不会交错由 workflow 的并发组保证(`test_aiwork_gate_workflow.mjs`)。

## 从 shadow 转为真拦截

S0–S13 验收全部符合预期,且之后至少 5 个真实 PR 上 shadow 的结论都和业主的判断一致、没见过过时的 success,再:

1. 发一个 PR 把 `policy.json` 的 `check_name` 改为 `aiwork-gate`(连同钉住它的那条测试;判卷面,要业主批准);
2. 业主按「已接入仓库迁移」第 1–2 步配置 main 规则。
3. 确认:故意缺评审的 PR 合并按钮被挡住;机器账号在网页上合并被拒;按 S15 验收;贴了标签、放行的 PR 由 App 合进去。
