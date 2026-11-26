# aiwork-gate(放行关卡)

关卡代码取自 SunJ1ayu/OpenDesign `05fe41b97ba94b86bb31f032adb763b1b1576a5e` 的 `.github/aiwork-gate/`。判定行为不变。策略不跟代码走：workflow 把调用方检出里的 `.aiwork/policy.json` 放进 `AIWORK_POLICY_PATH`。

规则来历在 git 历史里。

G3 的合格 PASS 条件见 `decide.mjs`。结论块的必填字段由 `parseReviewBlock` 定义；
`files_read` 不再要求或检查，旧评审带着它也照常判定。这个字段原来是 PR 的改动文件清单，不能证明评审实际读过文件。

| 文件 | 做什么 |
|---|---|
| `github.mjs` | GitHub 请求、Link 分页与 GraphQL 的共享客户端；各入口传入本角色令牌 |
| `synchronize.mjs` | 自动同步意向、实际推送和提交树差的核实；只有可证明的干净同步能沿用授权 |
| `branch-history.mjs` | 分支活动分类、排序和生命周期边界的共用事实 |
| `merge-request.mjs` | 合并标签事件的冻结提交与绑定记录格式 |
| `collect.mjs` | 只读 GitHub API 收集事实;出错、分页没取完、条数对不上一律抛错(G8) |
| `decide.mjs` | 纯判定,不碰网络(G1–G7) |
| `run.mjs` | 流程:每次运行把所有开着的 PR 全重算一遍(事件只是门铃)。列出开着的 PR、按 head 分组 → 先在每个 head 上占位 → 每个 head 把以它为 head 的 PR 全判一遍、合成一个结论写一次;读不全就不放行;写上的是放行,就合并该合的 PR(有可信合并请求的,或普通 PR 当前 head 干净、只有够数合格 PASS 时直接合并;见下「合并」) |
| `main.mjs` | 接线:真实 API、`aiwork-gate` App 令牌、发 / 改检查、合并。策略路径只认 `AIWORK_POLICY_PATH` |
| 调用方的 `.aiwork/policy.json` | 策略:判卷面、high 路径、`high_min_families`、Builder、评审 App、检查名、App ID、合并标签和谁贴的算数、直接合并的目标家数、事后抽查设置 |

测试:`tests/test_aiwork_gate.mjs`(判定与收集)、`tests/test_aiwork_gate_run.mjs`(流程与失败处理)、
`tests/test_aiwork_gate_main.mjs`(假 GitHub API 上真跑 `main.mjs`)、`tests/test_aiwork_gate_workflow.mjs`(workflow 形状和本仓库策略)、`tests/test_aiwork_gate_sync.mjs`(同步来源、文件交集和沿用范围)。
从 OpenDesign 仓库内容推导 policy 清单的测试留在 OpenDesign。

## 评审分档与派发

项目 main 的 `.aiwork/policy.json` 中 `review_dispatch` 定义派发策略；`gate/review-plan.mjs` 同时供关卡和 `review-pr --auto` 使用。字段：`minimum_families` 是 G3 底线；`targets` 按 `documentation`、`code`、`high` 给出目标家族数；`documentation_paths` 是普通说明文档 glob，判卷面匹配优先按代码算；`candidates` 是所有档位共用的候选腿，`selection: "random"` 要求排除作者及执行方家族、已交卷家族，再按家族等概率洗牌，前面的补足目标，余下的是有序备用。high 优先于其他档位，底线仍由 `high_min_families` 定义。`review-pr --auto` 同时启动所缺目标家数；每家结束后重新读关卡，只有未确认完整交卷留下的空位才补派，补派与尚在跑的腿并行，目标凑够后不再启动。BLOCK 也是完整交卷，不因未达 PASS 底线无限补腿。每轮启动前在 PR 普通评论公开 head、策略版本、抽选结果和备用顺序，结束后更新该评论，仅包含实际启动的腿及关卡确认结果；中途停止时公开停止状态和派发停止原因，不推断单腿结果，不写单腿失败原因、类别或日志原文；这份记录不作为评审结论。PR 在派发器收尾前被关卡按这个 head 合并时（直接合并或按合并标签），这一轮按成功收尾；只有读不到关卡状态、head 或策略变化、或者因别的原因关闭时才停止。公开内容只从已知事实的固定字段生成，再过隐私检查；完整诊断留在本机。公开记录检查或发布失败仅记本机日志，不影响评审和补派。未配置 `review_dispatch` 的项目保留原有关卡行为，自动派发拒绝猜测候选或目标。旧的 `order`、`high_only` 字段不再接受，接入项目需在自己的策略 PR 中迁移。

工具用法见 README「Review commands」；汇总读取 PR 上的公开派发记录，本地诊断不作为公开记录的一部分。关卡摘要显示目标与底线：底线参与 G3 / G6，目标家数和当前 head 的记录白名单只决定普通 PR 能否由关卡直接合并（见「合并」），不改变放行底线；其他规则不变。隔离保障链的推导和漏项检查见 `tests/test_aiwork_gate_workflow.mjs`。

`decide.mjs` 的 `review_state` 是派发器消费的机器状态：底线是否满足、已排除家族、完整已交卷家族及目标缺口均在那里定义。派发桥只读取默认分支策略、收集事实并转交该状态；Python 只按状态选择下一条腿，不计算评审资格或底线。派发桥仅在选择腿的排除集合中加入实际执行方；关卡返回的作者、评审资格、底线及原文保持原样。读取桥与关卡入口共用 `github.mjs`，配置仍由入口环境提供。

## 修改轮数显示

项目可在策略中配置 `modification_rounds`，其中可选的 `limit` 是正整数覆盖值（省略时的上限来源见下段），`summary_account` 是汇总账号，不能兼任评审机器人或合并申请人（含业主）。汇总账号也不能兼任 Builder，依据见 [业主决定](https://github.com/SunJ1ayu/aiwork/issues/43#issuecomment-6888714838)。接入项目升级共享关卡前，先将汇总账号移出执行方名单。未配置时，关卡输出和行为保持原样。aiwork 启用此项；其他项目要用时修改自己的策略。

上限与停的定义见 `REVIEW-RULES.md` 第三节第 1 条。记录格式和计数约定见 `workflow/skills/summary/SKILL.md`「汇总的格式」，由 `tests/test_aiwork_gate_rounds.mjs` 从定义读取并对照。关卡复用已经取全的 PR 评审与 GraphQL 改写时间，不增加请求；`decide.mjs` 用同一份解析显示轮数，并让普通 PR 的直接合并按白名单检查当前 head 的所有记录（见「普通 PR 直接合并」）；`run.mjs` 在共享 head 的结论中保留每个 PR 的轮数和停信号，G1–G8 不变。新汇总通过已有评审门铃重算。

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
4. 代码生效后，各调用仓库按「新项目接入」同步两份 workflow；已配置模板一致性检查的仓库在同步前会红。按 S15 验收管理员网页合并被拒。

依据见 [业主决定](https://github.com/SunJ1ayu/aiwork/issues/111#issuecomment-6552793090)。aiwork 和 OpenDesign
已完成前两步，见[规则补记](https://github.com/SunJ1ayu/aiwork/issues/111#issuecomment-6552923695)；管理员网页合并的验收状态见 `ACCEPTANCE.md` 的 S15。
新接入仓库转真拦截时也按第 1–2 步配置规则；已有规则就更新，不另建一套。

## 事件只是门铃;同一时间只有一次运行

- **每次运行把所有开着的 PR 全重算一遍**,结论只取决于 GitHub 上的现状,与是哪个事件叫醒的无关。
  以前从事件推"该算哪个 PR、写到哪个提交",漏过好几次(没带 PR 的 workflow_run、旧提交、合并提交、指向默认分支的)。
- **同一时间只有一次重算**:workflow 的 gate 任务并发组是固定名字 `aiwork-gate`,不取消正在跑的;排队的只留最新一个
  (GitHub 自己会把更早排队的取消),它开始时读到的一定不比被它顶掉的旧,而它又会重算全部 PR,所以顶掉的不会漏算。
  于是同一提交上后写的结论一定出自后读的数据 —— 不会有慢一步的旧运行盖掉新结论。
  同名检查后发的一定后写完,GitHub 按创建还是按完成时间取"最新",取到的都是
  最后一次运行的;运行半路死掉时,已创建且未完成的占位检查停在 in_progress,照样挡着,下一次运行全部重算。
- job 上**不许**按事件过滤(比如只认某个标签):排队时被顶掉的运行,要靠顶掉它的那次来算。
- 代价:稳定列表、各接口只需一页、无瞬时状态重读、没有待核实的关卡同步且不合并时，设开着的 PR 数为 P、不同 head 数为 H：
  每次 `GITHUB_TOKEN` 要两次读 PR 列表、每 PR 六次 REST 读取（PR、改动文件、评审、CI 运行、PR 事件、分支活动）和一次 GraphQL 查询，
  即约 `2 + 6P` 次 REST 请求和 P 次 GraphQL 查询；分页或列表不稳定会更多。
  App 另有每 head 两次检查写入，以及每次运行一次安装查询和一次换检查令牌请求；没有 head 且没有待保存的标签事件时不换 App 令牌。
  最新贴标签者可信时，每个带标签 PR 还要用检查令牌读取绑定记录（分页会增加请求）；
  可信的贴标签载荷另创建一条绑定检查，包括重跑。上述绑定读写不计入 GITHUB_TOKEN 的 REST 公式或下表每 head 的常规检查写入数。
  满足放行并带有效合并请求时，每个 PR 另做同步准备：固定 6 次 `GITHUB_TOKEN` REST 读取（PR、仓库、目标分支 ref、compare 两次、再读 ref），
  main 每有一个新提交再加 1 次文件读取；有提交可同步时还要重读 PR 和 ref 各一次，即 k 个新提交共 `8 + k` 次（k=1 时 9 次）。
  其中某个提交的文件列表达到 300 个时按「可能被接口截断」处理，不能确认文件交集。
  合并前另读目标分支 ref 和 PR 各 1 次（共 2 次）；合并接口拒绝后再读 PR 和 ref 各 1 次（本路径共 4 次）；
  若重读时 PR 仍落后、且要判断关卡会不会自动同步，再读仓库默认分支 1 次（本路径共 5 次）。
  关卡实际发出同步时，另读 PR 和 ref 各 1 次（2 次），update-branch 写请求用 App 令牌。
  核实历史关卡同步时，另读原 head 上的 App 同步意向、实际合并提交，以及两个树差的完整 Git trees（4 次 tree 读取，每次先读 1 次提交，共 8 次提交/tree 读取；这个 8 不含意向、合并提交和下面的 compare）；
  main 在意向之后前进时再加 2 次 compare 核实新基准（一次取提交总数和共同祖先，分页再读一次首页），并逐个读取这段新提交的文件列表（每个约 1 次，分页另计）补算文件交集；每次都核实，不把缓存当事实。
  上述额外事实读取使用 `GITHUB_TOKEN`，绑定及意向检查仍用 Checks 令牌，均不在基础公式内；有合并请求、同步或待核实同步历史时应按上面的数字另计。
  合并或同步时还会另查安装、换合并令牌并逐 PR 发写请求，这些 App 请求不算进上述 `GITHUB_TOKEN` REST 数。
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
| PR 是草稿还是正式（草稿不直接合并） | `pull_request_target`:`ready_for_review`（草稿转正式）、`converted_to_draft`（正式转回草稿）；`opened` / `edited` 也会读当前状态 |
| 目标分支(G1 要 CI 晚于最后一次改目标分支) | `pull_request_target`:`edited` |
| 开着的 PR 有哪些(同一提交上几个 PR 合在一起判) | `pull_request_target`:`opened` / `reopened` / `closed` |
| CI(以最后开始的那次执行为准) | `workflow_run`(ci):`requested` / `in_progress` / `completed`(重跑不一定发 `requested`,开始跑时会发 `in_progress`) |
| 评审(读当前正文;机器人评审发出后被改写过一律按 BLOCK、时刻按改写那一刻;人的评审被撤销按撤销那一刻) | `aiwork-review-ping`:`submitted` / `edited` / `dismissed` → `workflow_run` |
| 策略 `.aiwork/policy.json`(只认 main 上的) | 改 main 之后 CI 跑完的 `workflow_run` |
| 关卡代码（aiwork main 的 `gate/`） | `schedule`：计划间隔 15 分钟，具体 cron 见模板；[2026-10-30 实测](https://github.com/SunJ1ayu/aiwork/issues/98#issuecomment-6526765438)约每 4–7 小时一次。GitHub 可能延迟、丢弃或停用定时任务，不能保证准时；用途与限制见下方「定时重算」 |
| 合并请求(PR 上有没有 `aiwork:merge`、最后是谁贴的及其提交绑定) | `pull_request_target`:`labeled`(撤掉标签不用叫醒:只会少合并,下一次运行自然读到)；直接合并靠评审、CI、PR 事件和定时重算叫醒 |
| 手动重算 | 给 PR 加任何标签(如 `aiwork:recheck`) |

### 定时重算：门铃漏响时的补救

按[业主决定](https://github.com/SunJ1ayu/aiwork/issues/98#issuecomment-6554312340)，保留定时重算，不追求准时，也不另加跨仓库叫醒机制。
它在其他门铃漏响时自动补算：重新检出最新的 aiwork main，按现状重算全部开放 PR、补写结论，
并为本次判为放行、且该合的 PR（有有效合并请求，或普通 PR 直接合并白名单条件成立）补上合并。正常合并路径见下方「合并」；在该路径的分支规则前提下，
PR 上挂着的旧结论只影响显示。旧放行残留的场景及已接受风险见 `.aiwork/accepted-risks.md` 第 7 条。

计划与实测频率见上表。计划间隔不是实际等待或写回的时限；成功运行还要经过并发队列、runner 分配、检出和重算，
job 的执行超时见模板。定时任务只使用默认分支上的 workflow；公开仓库
**60 天**没有活动会自动停用定时任务，恢复活动后也要确认 workflow 已重新启用。相关平台行为见
[GitHub 的 schedule 说明](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)。
Actions 被关、environment 等审批、检出/API 失败时，定时任务也无法完成补算；恢复运行后可用上表的手动门铃重算。
定时器不能消除下方「已知限制」所述的最终一致窗口。

## 已知限制:状态检查只能"最终一致"

关卡靠"输入变了 → 叫醒 → 重算 → 写回",写在提交上的结论总是某一刻的。这种做法本身有补不死的上限,
写在上面这几句里。项目若接受它,记在项目的 `.aiwork/accepted-risks.md`。关卡直接合并用的是当前 head 的结论；经合并标签合并的 PR 不靠提交上的旧结论,见下「合并」。

## 合并:普通 PR 直接合并与贴 `aiwork:merge`

当前目标分支提交统一从 Git ref 读取（`synchronize.mjs` 的 `baseTip`），不把 PR 的 `base.sha` 当作当前 main。同步比较、文件交集和意向使用同一固定提交；读取或写入期间 main 前进会重读，合并被拒的原因写回检查摘要。

合并有两条路，判定都来自同一次 `decide()`：普通 PR 在当前 head 干净、只有白名单允许的记录且凑够目标家数时由关卡直接合并；被白名单挡下（当前 head 或已核实的干净同步沿用来源上有不允许的记录）的普通 PR 要业主在当前 head 上批准并贴合并标签；只到底线、没有不允许记录的普通 PR 仍按合并标签合并，不额外要求业主批准。判卷面、high、汇总降级的批准要求见下；实际走哪条路写在检查摘要的「实际合并路径」一行。

### 普通 PR 直接合并

前提是项目策略配置了 `review_dispatch`（没有配置的项目保持原来的合并标签行为）。直接合并是白名单：满足以下全部条件时，关卡不等合并标签直接合并：

- 这次改动不碰 `judging_surface`，也不碰 `high`（判卷面 / high 仍要业主批准 + 合并标签，凑够家数也不能跳过）；
- 当前 head（含已核实的沿用来源）上只有白名单允许的记录（见下）；不同家族的合格 PASS 家数达到这一档的 `review_dispatch.targets` 目标家数；
- 不是草稿 PR（草稿即使凑够家数也不直接合并）；
- CI 绿、其余放行条件满足（作者已知、G3 底线满足等）。

「允许的记录」只有三种：计过目标家数的合格 PASS（评审机器人，含同步沿用来源上的）；业主在当前 head 上的批准（同一 head 多次批准都算；更晚的要求修改或撤销照旧挡）；登记汇总账号在当前 head 上唯一一条格式合法、发出后未改写、写「合并」且 `has_p1: false` 的汇总记录。其余可信账号记录照旧挡住：汇总的其他结论（交业主 / 照单修）、同一 head 多条汇总记录、读不清或改写过的记录、业主的要求修改或撤销、降级记录、任何账号的 BLOCK / `NEEDS_MORE_INFO`、看不懂或不认识的评审，以及评审机器人和执行方不计入目标家数的评审。非可信账号的普通评审意见（`COMMENT`）不挡直接合并；其「要求修改」仍按 G5 拦。关卡只读评审记录，汇总在 PR 上的普通评论（答复执行方、修改单等）不作为直接合并的依据。当前 head 上有一条不允许的记录就不直接合并，摘要的「直接合并」一行写明是哪条记录挡住的；以后出现新的记录种类也默认不放行。只查当前 head 和关卡核实过、干净同步沿用的来源；旧 head 且没有沿用的记录不参与。

差一个条件就不直接合并。只有底线家数、没到目标家数时仍然判「放行」，只是不直接合并，由汇总按 `workflow/skills/summary/SKILL.md` 第 4 步补派评审凑目标；补派凑够后，若汇总在当前 head 写的是唯一合法「合并」且无 P1 的记录，仍可直接合并；写其他结论、同一 head 多条或读不清时，这一单改由业主批准并贴合并标签。被白名单挡下的普通 PR（有不允许的记录）要业主在当前 head 上批准；没有批准时结论不放行，贴了合并标签也不合并。凑不够交业主。

`review_dispatch` 的 `high` 档只用于派发目标；直接合并完全不覆盖判卷面和 high。

`post_merge_check` 只控制直接合并后的巡检抽查比例（`all`、`sample` 配 `sample_every`、`off`；未配置按 `all`）；查什么、记在哪见 `workflow/skills/patrol/SKILL.md`「合并后抽查」。

### 汇总降级

评审腿判 BLOCK、汇总核实后降为 P2 时，汇总账号在当前 head 上的一条 COMMENT 评审里放一个 `aiwork-downgrade` 记录围栏（格式见 `workflow/skills/summary/SKILL.md`「汇总降级」），写明核实过程（跑过什么、为什么不算 P1）和被降级的评审编号。

关卡只认同时满足这些的记录：登记账号（`modification_rounds.summary_account`）发出、`commit_id` 和记录里的 `head_sha` 都是当前 head、发出后未被改写、正文恰好一个格式符合 `workflow/skills/summary/SKILL.md`「汇总降级」中 `aiwork-downgrade-schema` 的 `aiwork-downgrade` 记录围栏、列出的编号都是当前 head 上评审机器人的 BLOCK。别人写的、旧 head 上（包括同步沿用的来源提交）的、格式不合的、降的不是当前 head BLOCK 的，都不认。

被降级的 BLOCK 不再算 G5 的 BLOCK。只有结论可信且范围合格的当前 head 评审，才按家族计入 G3 / G6 的评审家数：结论块完整可读、正文发出后没被改写、正文结论行与结论块一致（结论块是 BLOCK 也照样检查）、范围合格（当前 head、完整、不是本次作者家族）；降级条目还须结论是 BLOCK。同一家族只算一家。这样本 issue 起因的情形——评审都 BLOCK、汇总核实后全部降级、业主在当前 head 上批准——可以放行；结论块不完整、正文被改写、正文结论行与结论块不一致、范围不合格或结论不是 BLOCK 的降级条目只移走 G5，不能补家数，摘要会写「已降级但不计家数」及原因。正常评审家数（G3 的 PASS 与派发用的已评审家族）和降级计数使用同一个「能不能计家数」判断。

仍要业主在当前 head 上批准，且批准要晚于最后一条 BLOCK（含被降级的）才放行（G7 的「汇总降级」）；汇总降级不能让「直接合并」成立 —— 这一单仍要合并标签。降级记录只加不减；要撤回只能由业主决定。

### 合并标签的授权

- **谁贴的算数**:业主(`policy.json` 的 `owner`)和 `merge_requesters` 里的账号(以后放 OpenClaw 的身份)。
  Builder 贴的不算,也写不进名单(策略校验会拒)—— 不然 Builder 能把自己的 PR 合进去。
  认的是 PR 事件里最后一次贴这个标签的人:撤掉再贴,按最后一次算。
- **只授权通知里的提交**：`main.mjs` 从可信 `pull_request_target/labeled` 原始通知取 `pull_request.head.sha`，
  由关卡 App 保存 `merge-request.mjs` 定义的版本化授权。叉库 PR 不支持自动合并，摘要明确提示人工处理。每次重算从 GitHub 读，只认策略指定的关卡 App 和授权账号。
  采用[业主 D 方案决定](https://github.com/SunJ1ayu/aiwork/issues/153#issuecomment-7107164506)：同一 PR、标签、提交上的可信授权可复用，
  不再用通知的 `updated_at` 对历史事件的 `created_at`。标签仍挂着、最后一次贴合并标签的人可信时，
  即使同一提交上摘掉重贴的新通知未保存，也可沿用此前授权；最新贴标签的人无权限时先提示该原因，不能借授权合并。
  旧时间键格式不当成新授权，上线时没有新格式记录的提交需可信账号摘掉重贴。
- **授权提交必须连续保留**：活动历史分页取全，须覆盖本次分支创建、推送链相接，当前 head 和授权源提交都只出现一次。
  记录读不全或分支换走又回到旧 SHA 时不合并，摘要说明连续性无法证明；重贴不能绕过连续性检查，仍无法证明时需人工处理。
  普通推送到新提交没有旧提交的授权；只有下段经核实的关卡干净同步可以延续源授权。
  无新格式记录、记录被淘汰或保存失败且没有可复用授权时，摘要提示没有可信授权记录、要摘掉重贴。
  字段来源见 [Checks API](https://docs.github.com/en/rest/checks/runs)、[Webhook 文档](https://docs.github.com/en/webhooks/webhook-events-and-payloads#pull_request)
  和[仓库活动 API](https://docs.github.com/en/rest/repos/repos#list-repository-activities)。不增加角色权限。
- **保存独立于重算队列**：workflow 的 `binding` 任务只保存原始通知授权，没有并发组；保存结束后 `gate` 任务才进入固定并发组重算。
  后一次重算顶掉排队任务不会取消已完成或正在执行的保存任务；保存失败、跳过时仍以 `always()` 重算所有开放 PR。
  保存本身不读当前 head、不重算、不合并；迟到或重跑的通知只能保存通知中的提交。
  保存仍可能因运行被人工取消、平台失败或超时而缺失，缺授权不合并；重算被顶掉后由其他门铃消费已保存的授权。
- **不另起一套判定**:关卡每次运行照常把所有开着的 PR 判一遍;某个 head 的 App 结论写上了、
  而且是放行,就当场合并这个 head 上该合的 PR（有可信合并请求的，或普通 PR 直接合并白名单条件成立的）。
  合并用的就是这次刚读到的数据,调合并接口时带上判过的 head(`sha`):判完之后又推了新提交,接口会拒,不会把没判过的提交合进去。
- **没放行的请求留着**:只有授权提交连续保留、标签仍挂着且最后贴标签者可信（或满足下段关卡自动干净同步的例外），之后哪次运行判为放行，才在那次合。不想合了就撤掉标签(关卡正在合的那几秒里撤可能来不及,
  见项目的 `.aiwork/accepted-risks.md`)。
- **自动同步最新 main**：按[业主决定](https://github.com/SunJ1ayu/aiwork/issues/205#issuecomment-7088746460)，仅当 G1–G8 与合并条件都已满足时（有可信合并请求，或普通 PR 直接合并白名单条件成立），关卡才检查默认分支是否落后。
  有冲突就停止同步并在检查摘要说明，关卡不解冲突。无冲突时先用 Checks 令牌保存 `synchronize.mjs` 定义的同步意向，再用现有合并令牌调用 [update-branch](https://docs.github.com/en/rest/pulls/pulls#update-a-pull-request-branch)，带 `expected_head_sha`，拒绝同步已经推进的分支。
  GitHub 尚在后台计算（`mergeable: null`）或 PR/目标分支在核实、写入期间推进时，不判为数据出错。关卡在同一次运行内等待并重读开放列表、事实、授权及全部放行条件；重读预算见 `run.mjs` 的 `MAX_STATE_READS`，默认间隔按指数退避（1 秒起、单次最多 30 秒），耗尽后保留进行中。同一 head 在本轮重读时复用已创建的占位检查，不再重复新建；同一次运行里曾经写出 `completed` 结论的检查，即使后来因合并瞬时状态改回进行中，消失时也不能收尾成失败；若它仍在开放列表且当前结论是进行中，重读轮照常重新算出结论。重读后消失、但本次运行从未写出最终结论的 head 当场收尾，不留 `in_progress`。已接受的同步请求在该次运行内不重复发送，等实际 head 改变后再核实。真正的读取失败及不合法数据仍按 G8 拒绝；不修改门铃、定时或权限。背景计算与轮询方式见 [GitHub 文档](https://docs.github.com/en/rest/guides/using-the-rest-api-to-interact-with-your-git-database#checking-mergeability-of-pull-requests)。
  同步意向整段写进检查结果，长度超过接口上限时保留核心字段、把 overlap 截到能放下并标记截断；下一轮据此拒绝沿用，不把半截意向当成干净同步。列表接口没带完整正文或正文解析失败时，按检查 id 用有 Checks 权限的令牌重取一次；仍读不出按 G8 拒绝，不当成「没有意向」。比较范围是固定提交，提交条数与首页总数对不上属于读取不完整，同样按 G8 拒绝，不按瞬时状态反复重读。
  接口是异步的；请求获准不代表完成。下一轮从实际推送者、意向绑定的 PR/分支/双亲及完整 Git tree 差核实同步。
  写意向与调用 update-branch 之间 main 可能前进：只要实际第二双亲仍是意向 base 的后代，就以实际第二双亲为合并基准核实，并在摘要写出 main 中途前进；不再因为双亲不等于意向 base 就永远证明不了。这段新提交同样要逐个补算文件交集：意向里的 overlap 只算到写意向时的 main，漏掉这段就会把后来碰了本单文件的提交当成干净同步。
  只有同步前后 PR 自身的路径、对象类型、模式与 blob/gitlink 改动都相同、且 main 新提交未碰本单文件，才延续源提交的评审和合并标签；任意普通推送（包括推回曾同步的 SHA）都会截断沿用。
  main 有提交的文件列表达到 GitHub 单提交 300 个上限时，无法确认是否碰了本单文件，按「未知」处理：同步后须重新评审，再按当时的合并路径继续。
  Git tree 被接口截断时，仍按意向和双亲认出这是关卡的同步推送（作者不会变成 UNKNOWN），但不能证明 PR 自身改动未变，因此不沿用评审或标签，要求在当前 head 重新评审。
  main 新提交未触及本单任何文件时，关卡沿用意向中原 head 的评审（包括反对及其改写、撤销），并在摘要列出来源；同路径有交集则须重新评审。main 改判卷面不单独触发重评，所有判定仍读取 main 的最新规则。
  无论是否沿用，CI 只认新 head；业主的批准仍按 GitHub 实际返回的当前 head 表态认定，不自行搬移。
  同步写入失败是逐 PR 的执行结果：非瞬时失败只记在对应 PR 的摘要并跳过它的合并，不改共享 head 的放行结论；同 head 其他 PR 的同步仍继续，但共享结论在同步完成前保持进行中，这一轮不合并该 head 上任何一单；瞬时失败则重读全部事实。意向丢失、实际双亲不符或树差变化时不沿用；数据读不全按 G8 拒绝。
  main 规则集的「合并前分支必须和 main 同步」继续保留：同轮先合入另一单后，后续单在合并前重新读 main，先同步、等新 head 的 CI，再重算合并。
- **合并没成**(分支落后于 main、有冲突、评审讨论没解决完、刚推了新提交):原因按 PR 写在那次运行的摘要里；贴了标签的请求留着，直接合并的下一轮按现状重算。
  非瞬时的合并拒绝不改变 G1–G8 的放行判定：同一 head 的已授权 PR 各自尝试，全部尝试完再补写拒绝摘要。
  瞬时状态（PR/目标分支在写入期间推进、GitHub 还在计算、分支被规则要求先跟上 main **且关卡下一轮确实会自动同步**）则停止这一轮剩余的合并，重读全部事实后再试，
  不会把瞬时竞争写成最终拒绝。目标分支不是默认分支或 head 来自叉库时，关卡不会自动同步；这种落后以及同步写入被非瞬时拒绝的情况保留原始拒绝原因，这一轮不合并该 PR，不把它报成「重读后自动同步」。
  快照变化同样停止使用该共享快照并重读。
  处理时若普通推送了新提交，要摘掉重贴合并标签；关卡自动干净同步见上段。未改提交的，评审等门铃会叫醒下一次运行再合;没有门铃的(比如把讨论标为已解决),加个 `aiwork:recheck`。
- 合并用 App 另换的一张令牌(Contents / Pull requests / Workflows 写权限),只在真要合并或同步时才换;发检查的那张始终只有 Checks。
- main 的规则与迁移顺序见上方「已接入仓库迁移」；本轮写不了新结论时的显示结果与已接受风险见 `.aiwork/accepted-risks.md` 第 7 条。
  取消不撤销已经完成的合并；未合并的 PR 由下次运行重新判定后合并。

## 同一提交上有几个 PR

检查都挂在**提交**上,不是 PR 上。同一提交可以同时是几个开着的 PR 的 head(目标分支不同,改动和要求就不同)。
所以写 success 之前,关卡把这个提交上其他开着的 PR 也判一遍:**全都放行才放行**,有一个不放行就不放行,
查不到就按 G8 失败。

## 执行方登记

aiwork 的执行方登记只在 [`.aiwork/policy.json` 的 `builders`](../.aiwork/policy.json)：键是构建机器人登录名，值含 `family`（家族）和 `role`（本机 `apps/<role>.env` 的角色名）。结构化登记的格式约束唯一定义在 [共享格式定义](../.aiwork/builder-schema.json)。[Python 配置读取器](../bin/_aiwork_config.py) 和 [关卡读取器](builders.mjs) 解释这份定义；[直接比对测试](../tests/test_aiwork_gate_workflow.mjs) 对同一批边界输入实际执行两种语言，不靠两个独立的样例测试声称一致。

[汇总答复](https://github.com/SunJ1ayu/aiwork/pull/229#issuecomment-7122366442)确认新增家族只改这份策略，仍走 PR、由业主批准。这里登记的是可信身份，不是 CLI 的调用方式；供应商 CLI 的接入不属于本项。机器上的角色文件、钥匙、模型和路由继续用各自的本机设置。

标签来源与 `check-app-role` 读取运行中 aiwork 程序所在检出的这份策略，不跟随调用目录，也不提供环境变量替换登记的入口。因此部署必须包含同版完整检出（含策略及共享格式定义），不能只复制 `bin/`。关卡和评审交接仍读取目标项目默认分支策略；Mac 上为其他项目配置派活前，其策略须登记对应身份，与已部署 aiwork 的可派家族相符。

缺失、读不了或格式不合法时，身份选择和派活拒绝运行，不恢复内置名单、不回退其他钥匙；本机路由只能选择已登记的家族。关卡及交接为未迁移的其他项目保留旧的「登录名 → 家族字符串」格式；关卡对旧的字符串映射仅保留原来的非空对象检查，不新增登录名或家族的格式及唯一性限制，不能借此收紧其他已接入项目的关卡。交接工具仍保留它在 main 上原有的旧格式家族检查。旧格式不含角色，不能作为 aiwork 的派活及本机角色登记。结构化格式只由上述共享定义校验。

合并后的部署与验收由本人操作，目前未验收：

1. 合并前备好已批准版本的部署安排，但本 PR 不操作机器。合并使 GitHub 关卡代码和 aiwork 的新策略立即生效；旧评审交接程序读取新策略会报登记非法、拒绝派评审，直到评审机更新。这段过渡期不能标作可用，也不能把拒绝当成已经评审。
2. 合并后先更新评审机的完整 aiwork 检出，记录提交；让此前轮次按原流程收尾，下一次交接使用新版入口。已导入旧代码的进程不会因更新文件自动换版，由本人按既有进程管理方式确认加载新版；保留请求、失败记录和去重状态，不重新发送已完成业务。核实目标策略能被新版读取后，再恢复积压交接。
3. 然后更新各写代码机的完整检出，最后更新 Mac 检出和标签查询入口，全部到同一已批准版本（含策略及共享格式定义），逐台记录提交；保留各自的设置、凭证和派活状态。全部更新前不登记新家族。Mac 查询每次新起进程，持久进程如仍在使用则须确认已重新加载登记，不能只更新磁盘文件。
4. 从登记逐项核对家族标签、Mac 路由及写代码机角色文件。用 `aiwork-config check-app-role build --resolve` 核对本家选择，再用 `gh-app-token build --repo SunJ1ayu/aiwork --grant` 验证原有授权，没有其他钥匙被读取。隔离和真实身份的验法见 [虚拟机手册](../docs/linux-vm.md#角色部署与评审交接)。
5. 按 [Mac 手册](../docs/mac-host.md#安装与本机设置)预演，确认现有家族各走原规则；对已有授权任务核对实际推送者、PR 作者和关卡认作者结果，不为验收制造正式派活。
6. 未来加家族时只在登记增加一项，经业主批准后部署；另由本人完成新 App 和本机配置。先预演、再验真实身份与关卡结果。未实际执行的场景继续标未验收。

## 模型按任务切换角色

作者识别继续用 `collect.mjs` 的实际推送活动和 `decide.mjs` 的 `authorOf`，策略来源仍是 main。
已知作者时，登记过的其他 Builder 家族可以审这次 PR；审核排除只针对本次作者家族。
作者 UNKNOWN 时，排除 `builders` 登记的家族以及项目策略可选的 `unknown_author_extra_families`。后者用于可能通过共用账号写代码的其他家族。
本改动不新增可信执行来源，也不改变 App 权限、模型账号配置或云平台接入。

## 首次部署验收(shadow:检查名 `aiwork-gate-shadow`,只报不拦)

合并后,用一个无害的测试 PR 逐条看。测试 PR 用 `builders` 登记的执行方本家构建机器人开;作者判定与评审排除集的定义见「模型按任务切换角色」。每条写下 PR 号、提交号和检查的链接。

| # | 做什么 | 预期 | 证明了什么 |
|---|---|---|---|
| S0 | 合并本 PR 后看 main 上 CI 跑完触发的那次 aiwork-gate | 运行成功,只重算开着的 PR;main 的提交上**没有** `aiwork-gate-shadow` | 事件只是门铃,不往非 head 的提交上写 |
| S1 | 开测试 PR | 立刻出现 `aiwork-gate-shadow`(重算中 / 等 CI);检查的 app 是 `aiwork-gate`(id 5121026),不是 GitHub Actions | 占位先行;结果由 App 发出 |
| S2 | 等 CI 跑完 | failure「不放行:缺合格评审」;G4 显示作者是开 PR 的本家构建机器人 | CI 按本 PR 认;活动记录接口在 `GITHUB_TOKEN` 下读得到 |
| S3 | 本机 `review-pr` 在当前 head 发 PASS(家族在排除集之外) | 一两分钟内自动重算为 success「放行」 | 评审 → `aiwork-review-ping` → 关卡重算这条链通 |
| S4 | 同一 head 再发一条 BLOCK | failure(G5);业主**在 BLOCK 之后**批准 → success | BLOCK 与批准的先后被认 |
| S5 | 业主在网页上改测试 PR 的一个文件(非构建机器人推送) | failure,作者 UNKNOWN(G4);业主在新 head 批准 + 排除集之外家族的合格 PASS → success | 混合作者要业主批准 |
| S6 | 测试 PR 改 `judging_surface` 里的一个文件 / 改 `high` 里的一个文件 | 分别要业主批准(G2)/ `high_min_families` 家不同家族 PASS(家族都在排除集之外)+ 业主批准(G6) | 判卷面与 high 路径 |
| S7 | 给 PR 加标签 `aiwork:recheck` | 重算一次;算的时候合并框里这条检查显示"重算中" | 手动重算可用;占位压得住上一次的结论 |
| S8 | 编辑测试 PR 的标题;再改一次目标分支 | 各重算一次;改目标分支后 G1 ❌「目标分支在这次 CI 之后改过」,推一个新提交(或关掉再重开 PR)让 CI 重跑后恢复 | edited 事件会触发重判;旧目标上的 CI 不算数 |
| S9 | 连着触发两次重算（比如先后加两个标签），看 Actions 的 gate 任务 | gate 串行，排队的重算可被更新的顶掉；binding 不受该并发组影响 | 重算串行与授权保存相互独立 |

合并(本节在「合并」上线后补做,同样用无害的测试 PR):

| # | 做什么 | 预期 | 证明了什么 |
|---|---|---|---|
| S10 | 业主给一个会放行的测试 PR 贴 `aiwork:merge` | 那次运行放行后当场合并:合并者是 `aiwork-gate` App,合进去的是判过的 head | 合并用的是刚判过的数据和 head |
| S11 | 先核实登记执行方的本家构建机器人是否有贴标签权限；无权限不加权限、记未验收。有权限时给会放行的测试 PR 贴 `aiwork:merge`,自己开的、别家执行方开的各贴一次 | 两次都不合并；摘要和日志先说明申请人不算数，不误报为缺授权 | 登记的执行方合不了自己的 PR,也合不了别家的 PR |
| S12 | 业主给一个还缺评审的测试 PR 贴 `aiwork:merge`,不推新提交，之后补上 PASS | 贴的时候不合;PASS 之后那次运行合并 | 同一提交的请求留着,放行时才合 |
| S12a | 在旧提交贴合并标签后、关卡运行前推新提交，再补齐新提交的放行条件 | 不合新提交；摘要说明缺可信授权。新提交连续性可证明时重贴并保存后可合 | 授权只来自原始通知提交 |
| S12b | A 上业主贴标签并保存，摘掉 → 推 B → 重贴 → 强推回 A，补齐其他条件；测试期间不让 PR 达到合并条件 | 不合 A；摘要说明换走后回到旧提交或连续性无法证明 | 换走再回来不能复活旧授权 |
| S12c | 同一提交保存一次可信授权，保持 head 不变，摘掉重贴；对照通知 updated_at 与历史 created_at（如出现一秒差也记录），再补齐其他条件 | 重贴可沿用原授权，合并不依赖两时间相等；记录授权检查和合并 head | D 方案复用语义及时间差不影响授权 |
| S12d | 在无害测试 PR 上连续触发标签和其他门铃，观察有重算排队被顶掉的运行；先保持其他条件不齐 | 每次 labeled 的 binding 均完成保存，不被 gate 队列取消；后续重算读到原授权 | 保存不受重算队列顶替影响；平台执行证据需合并后补 |
| S13 | 两个指向 main、改不同文件且其他条件齐全的测试 PR，业主都贴 `aiwork:merge`；等第一单合入 | 第二单由关卡同步 main，摘要列出沿用的原提交；作者仍是原 Builder；新 head CI 绿后自行合并，不重评、不重贴标签 | 干净同步、评审和标签沿用、新 head CI |
| S13a | 两单改同一文件中不同位置，能自动合并，第一单先合入 | 第二单同步后摘要要求重评并重新满足合并条件；旧 PASS 不满足 G3，旧标签也不再授权，补当前 head 的评审并重贴标签后才能继续 | 文件有交集不能沿用评审，也不能沿用原合并标签 |
| S13b | 两单改同一处制造冲突；落后单其他条件补齐 | 检查摘要说明冲突；分支 head 不变，关卡不解冲突、不发同步写请求 | 冲突留给人 |
| S13c | 在 S13 的同步后、CI 完成前，由 Builder 再推一个普通提交，补齐新 head 放行条件 | 旧合并标签失效，不自动合并；按当时的合并路径补齐条件后才可继续 | 同步例外不放松后续推送拦截 |
| S13d | 制造一次「写意向之后、update-branch 之前 main 前进」：在另一单合入的同一时段触发同步，核对同步合并提交的第二双亲 | 下一轮仍能证明这是关卡的同步；摘要写出 main 中途前进；干净时沿用、有交集时要求重评，作者不变成 UNKNOWN | 实际合并基准核实与摘要可读 |
| S13e | 用单个提交改动 300 个文件的 main 更新与截断的 Git tree 样本核对同步摘要 | 摘要说明无法确认文件交集或无法比对树，要求重新评审并重新满足合并条件；不误放行 | 平台截断下的保守处理 |
| S15 | 用判卷面或 high 路径、已满足其他合并条件但未贴 `aiwork:merge` 的测试 PR（这种单不会直接合并），以仓库管理员身份在网页上尝试合并 | 被 `main-gate-merge-only` 拒绝更新 main，PR 未合并 | 管理员不能借提交上的放行绕过关卡合并 |
| S16 | 普通 PR 当前 head 只有白名单允许的记录（达标目标家数的合格 PASS、至多一条汇总「合并」记录、业主批准）、CI 绿，未贴 `aiwork:merge` | 关卡直接合并；摘要的「实际合并路径」写明按目标家数直接合并，合并者是 `aiwork-gate` App，合的是判过的 head | 普通 PR 直接合并 |
| S17 | 普通 PR 只到 G3 底线、没到目标家数；汇总补派评审并在当前 head 写下记录 | 补派前关卡判放行但不合并；补派凑够目标且 CI 绿后，汇总写唯一合法「合并」记录时直接合并，写其他结论/多条/读不清时改由业主批准并贴合并标签 | 底线与目标的区别；汇总记录决定补派后能否直接合并 |
| S18 | 判卷面或 high 的 PR，或当前 head 有汇总降级；凑够目标家数但不贴合并标签 | 不直接合并；仍然要业主在当前 head 批准并贴合并标签 | 家族数不能跳过判卷面、high 与降级 |
| S19 | 汇总在当前 head 对 BLOCK 写下合法的降级记录，业主随后在当前 head 批准并贴合并标签 | 放行并合并；摘要显示汇总降级；没有直接合并 | 降级解除 G5 并可按家族计入 G3/G6，不等于批准，也不能直接合并 |
| S20 | 全部评审 BLOCK，汇总在当前 head 降级全部 BLOCK，业主随后在当前 head 批准并贴合并标签 | 放行并合并；G3/G6 按被降级的独立家族计数；没有直接合并 | 本 issue 起因的 PR #172 情形 |
| S20a | 当前 head 的 BLOCK 发出后被改写，汇总仍把它写进合法的降级记录，业主随后批准并贴合并标签 | G5 解除，但该条不计家数；摘要写「已降级但不计家数」和改写原因；家数不够时不放行 | 降级只处理严重程度，不把被改写的正文变成可信评审 |
| S20b | 当前 head 的 BLOCK 正文另有不同结论行（例如先写 `Conclusion: PASS`、最后写 `Conclusion: BLOCK`，结论块仍是 BLOCK），汇总降级、业主随后批准并贴合并标签 | 该条仍算 G5 的 BLOCK，直到降级把它移走；降级后也不计家数，摘要写「已降级但不计家数」和正文结论行原因；家数不够时不放行。对照：正文结论行与结论块一致（或没有结论行）的 BLOCK 降级后照旧计家数 | 正文自己都没说清结论，降级只处理严重程度，不把它变成可信评审 |

S14 是历史上的批准迁移样本，见 `ACCEPTANCE.md`「发现」；保留编号，不复用。

失败注入(API 出错、限流、App 私钥坏了、PR 中途推进、合并接口拒绝)在线上没法安全制造,由 `test_aiwork_gate_run.mjs`(R4–R5e、R14c、R20、R25–R26、M1–M10)与 `test_aiwork_gate_main.mjs`(含请求卡住)覆盖;几次重算不会交错、保存独立由 workflow 的任务与并发组保证(`test_aiwork_gate_workflow.mjs`)。

## 从 shadow 转为真拦截

S0–S13e（含 S12a–S12d）验收全部符合预期,且之后至少 5 个真实 PR 上 shadow 的结论都和业主的判断一致、没见过过时的 success,再:

1. 发一个 PR 把 `policy.json` 的 `check_name` 改为 `aiwork-gate`(连同钉住它的那条测试;判卷面,要业主批准);
2. 业主按「已接入仓库迁移」第 1–2 步配置 main 规则。
3. 确认:故意缺评审的 PR 合并按钮被挡住;执行方的构建机器人在网页上合并被拒;按 S15 验收;贴了标签、放行的 PR 由 App 合进去。
