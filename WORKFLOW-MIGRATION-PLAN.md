# aiwork 工作流改造 · 第 4 版(最小实施方案)

> 状态:待 GPT 复核。日期:2026-09-28。第 4.1 版:写入业主对第 7 节两项的决定,补 high 的第二家族评审入口。
> 由第 3 版按 GPT"第一性原理收敛"的意见缩减而来;第 3 版全文见本文件的上一个 commit(`087cabf`)。
> ⚠️ 本文件目前只在 GitHub 镜像仓库里,本机 `/root/aiwork` 还没有。同步镜像前先把它拉回本机。

---

## 0. 只证明三件事

| | 要证明的事 | 现状(反例) |
|---|---|---|
| **P1** | CI 确实测了最终要合入的代码 | OpenDesign 的 PR 上没有 CI;PR #6 check runs = 0,测试结果靠 Builder 在评论里自述 |
| **P2** | 独立评审确实审了这份代码 | PR #6 的 `563eef7`、`8dd3efe` 是提意见的本地 Codex 自己修的,没有经过任何独立评审就进了 main |
| **P3** | Builder 不能给自己放行 | 所有 agent 共用 SunJ1ayu 身份;发版提交直接推 main;reviewer 能改 Builder 的分支并合并 |

**纪律**:每条规则、每个模块都要写明"防的是哪个具体的误放行"和"删掉会发生什么"(第 2 节)。说不出来的不做。每完成一个阶段,就删掉被它取代的旧逻辑(第 4 节)。复杂的推断一律不做:**无法可靠确认时,标为 UNKNOWN,停止自动放行,交业主批准。**

---

## 1. 最小形态

| 环节 | 由谁做 |
|---|---|
| 写代码(可自动放行) | **只有**云端 Claude,用机器账号推送。本机 agent 暂不当 Builder |
| 评审 | 本机评审腿通过 `aiwork-review` App 发结构化评审(这个 App **没有推代码权限**)。standard 只用 `subcodex`;high 另加一条非 OpenAI、非 Anthropic 家族的第二评审腿(见 G6) |
| 判定 | `aiwork-gate`:代码随 OpenDesign 的 main 固定,只读 GitHub API,不执行 PR 代码 |
| 合并 | gate 为 success 时 GitHub 自动合并;UNKNOWN、判卷面、high、有争议的 PR 需业主在当前 commit 上点 Approve |
| 发版 | 业主触发的 release workflow,只在 main 上跑,需业主在 GitHub 上批准后才执行 |

---

## 2. 规则与模块(每条都说明防什么、删掉会怎样)

| 编号 | 规则 / 模块 | 证明 | 防的具体误放行 | 删掉会怎样 |
|---|---|---|---|---|
| R1 | **分支规则**:main 禁止直推和强推、必须走 PR、合并前必须与 main 同步;必过检查只有 `aiwork-gate`,并限定只认 `aiwork-gate` App 发出的结果 | P1 P3 | 发版提交直推 main(`ad8ce62` 等);PR #6 修复后未审即合并 | 任何有写权限的身份都能绕过全部检查 |
| R2 | **CI workflow**:`pull_request` 触发,不给 secrets,不做路径过滤,跑 `tests/run-all.sh` 与 `tests/e2e/run-all.sh` | P1 | 未经测试的代码合入;Builder 自述"全过" | 回到 PR #6 的状态 |
| G1 | gate 核对 CI:结果针对当前 head、来自 `.github/workflows/ci.yml`、结论为 success | P1 | CI 被跳过或结论为 neutral 却被当成通过(GitHub 默认如此);PR 新增一个同名的假 job 冒充 CI | skipped 被当成通过;假 job 能冒充 |
| G2 | **判卷面**:PR 改动 `.github/**`、`.aiwork/**`、`tests/run-all.sh`、`tests/e2e/run-all.sh` 及测试配置 → 需业主批准 | P1 P3 | Builder 改 CI 或测试入口,让自己变绿 | 改一行 workflow 就能放行 |
| G3 | **评审**:需要一条评审,由 `aiwork-review` 发出、针对当前 head、结论 PASS、完整、上下文非空、家族与作者家族不同 | P2 | 未审就合、审的是旧代码(D13)、自己审自己、没看代码就给 PASS | 独立评审变成可有可无 |
| G4 | **作者**:PR 分支上的每次推送都来自机器账号 → 作者是 Claude;否则判为 UNKNOWN → 需业主批准,且当前 head 上仍须有至少一条 PASS | P3 | reviewer、本机 agent 或泄露的凭证追加未审 commit,并沿用之前的评审(PR #6 原样) | 混合作者的 PR 可以绕过评审 |
| G5 | 当前 head 上**任何**一条 `aiwork-review` 给出 BLOCK → failure,除非业主批准 | P2 | 一条 BLOCK 被另一条 PASS 盖过 | 挑一个 PASS 就能过 |
| G6 | **high 路径**(策略文件列出)→ 两个不同的非 Builder 家族 PASS(都针对当前 head)+ 业主批准。**业主批准是风险决策,不能代替第二次技术审查**:没有第二家合格结论就不放行 | P2 | 高风险改动只有一家审过 | 高风险和普通改动同等放行(沿用现行 high = 2) |
| G7 | **人工例外** = SunJ1ayu 在**当前 head** 上的 Approve;可豁免 G2 / G4 / G5,**不能豁免 G1(CI)** | P3 | 旧的批准被沿用到新代码上 | UNKNOWN、判卷面、争议将永远卡住(这是唯一的出口) |
| G8 | **失败即拒**:API 报错、分页不全、限流、活动记录读不到 → failure | 全部 | 缺数据被当成通过 | 数据缺失时误放行 |
| M1 | **gate 运行方式**:由 `pull_request_target`(opened / synchronize / reopened / labeled)与 `workflow_run`(CI 完成)触发;只用 main 上的 gate 代码(放在 OpenDesign 的 `.github/aiwork-gate/`),不 checkout PR 代码;同一 PR 取消旧的运行,只保留最新一次;gate 私钥放在只允许 main 使用的 Environment secret | P3 | Builder 在 PR 里改 gate,或借 PR 的 workflow 伪造 gate 检查 | gate 可以被 PR 自己改写 |
| I1 | **身份分离**:SunJ1ayu 只给人用(撤销 agent 用过的 PAT 与授权);云端 Claude 用机器账号;`aiwork-review` 无推代码权限 | P3 | agent 以业主身份批准或合并;reviewer 直接改 Builder 的分支(PR #6) | G4、G7 全部失效 |
| D1 | **发版 workflow**:业主手动触发,只在 main 上跑,release environment 需业主批准;产物来自 main 上的具体 commit | P3 | 用未合入的代码打包发布(PR #6 之后的打包) | 撤掉本机的业主凭证后就发不了版,会逼着把凭证放回去,I1 随之失效 |

补充说明:
- **评审发出后怎么触发重算**:评审适配器发完评审,给 PR 加一个 `aiwork:recheck` 标签,触发 `labeled` 事件。加标签只需 PR 写权限,不需要推代码权限;用 `repository_dispatch` 则需要推代码权限,所以不用。漏算时,人或 agent 手动加这个标签即可重算。
- **结论格式**:评审正文里放一个 JSON 块,字段为 verdict、head_sha、model、family、completeness、files_read。只因为它由 `aiwork-review` 发出才被采信;家族映射从 aiwork 现有的 `_review_result.py` 生成,不手写第二份。
- **推送者**:用 GitHub 的仓库活动记录(每次推送的执行者)判断,commit 里填写的作者名不作数。阶段 C 先验证这个接口可用;读不到就按 UNKNOWN 处理。
- **gate 代码放在 OpenDesign**:原因是 aiwork 的 GitHub 仓库只是无历史的镜像,每次重新生成,固定不了 commit。

---

## 3. 阶段(每个阶段:交付什么 / 怎么验收 / 删掉什么)

### 阶段 A:CI + 分支规则

- 交付:R2;R1 先把必过检查设为 `ci`(暂时可能被同名假 job 冒充,阶段 C 由 G1 接管)。
- 先验证禁止联网的守卫(`_no_egress`)在 GitHub runner 上能否生效;不行就换一种可用的方式,不直接关掉。
- 约定:PR 不改 VERSION,版本号改动走发版 PR。
- **验收**:普通 PR 上 CI 自动出现;直推 main 被拒;测试失败时不能合并;发版 PR 能走通。
- **废止**:PR 评论里自述测试结果的做法;OpenDesign 的新任务不再用 `runlog` 贴收据(CI 本身就是收据)。
- **状态:已完成(2026-09-28),"发版 PR 能走通"一项待下次发版时补验。**
  - CI:OpenDesign PR #7 引入 `.github/workflows/ci.yml`,在 PR 上逐轮修到全绿(`7aa496e`)。合并后 main 上的 push 运行(`3af3083`)也全绿。
  - 分支规则:ruleset 24121895 已生效,内容为禁止删除和强推、必须走 PR、评审讨论须解决、`ci` 必过(限定 GitHub Actions 发出)、合并前须与 main 同步。
  - 直推 main 被拒:用业主的管理员账号推一个空提交,返回 `GH013: Changes must be made through a pull request`,说明绕过名单为空。
  - 红 CI 挡合并:探针 PR #8 只加一条故意失败的测试,CI 仅红在这一条,`mergeable_state` = `blocked`;验完已关闭、删除分支。
  - 无出口守卫:在 GitHub runner 上以 root 运行可生效,e2e 在独立网络命名空间里跑。
  - 发版 PR 能走通:**未验**。本轮没有待发的版本,下次发版时走发版 PR 补验。
  - 过程中发现、已在 PR #7 里处理的环境差异:
    - `web/package-lock.json` 的下载地址是腾讯云内网镜像,CI 里临时改从 npm 官方源装,integrity 逐包校验;
    - 需要完整历史才能读到 `win-installer-0.98.8` 这个 tag;
    - CI 上固定有 4 条测试不跑:python 里 Windows 专属 1 条、要活 gateway 的 ws 冒烟 1 条,e2e 里要活 gateway 的 2 条;
    - 两条 e2e 的时序竞争(`settings_fvis`、`composer_zcode` ②),只加等待,断言不变。
  - 未查清:`stage_history.e2e.mjs` 在 CI 上红过一次,之后都绿。现在红了会自动保留日志,再红时查。

### 阶段 B:身份分离 + 发版 workflow

- 交付:I1、D1。业主注册机器账号并切换 claude.ai 的 GitHub 连接;建 `aiwork-review`、`aiwork-gate` 两个 App;在 GitHub 上撤销 agent 用过的 SunJ1ayu PAT 与已授权应用;建 release workflow 与 release environment(审批人:SunJ1ayu)。
- 过渡:本机 agent 只评审、不推代码。
- **验收**:本机 `gh auth status` 已不是 SunJ1ayu;用 `aiwork-review` 推代码被拒;机器账号能开 PR;发版 workflow 要等业主批准才执行,产物对应 main 上的 commit。
- **删除**:本机的 SunJ1ayu 凭证;"reviewer 直接修 Builder 分支"和"本机手工打包发布"的做法。
- **进度(2026-09-29)**:
  - 机器账号 `SunJ1ayuBoT`:已注册,OpenDesign 与 aiwork 均为 write 协作者;claude.ai 的 GitHub 连接已从 SunJ1ayu 换到它(`get_me` = SunJ1ayuBoT;OpenDesign PR #7 上的测试评论署名为它)。
  - `aiwork-review` App:已建并只装在 OpenDesign。App ID `5116249`,installation ID `165993669`(都不是机密;私钥只在业主电脑上)。权限按业主口述是 Contents 只读、Pull requests 读写,第 4 步用它换令牌时以 GitHub 返回的权限为准核一次。
  - `aiwork-gate` App:挪到阶段 C 与 gate 一起建 —— 现在建了也没有东西用它。
  - 发版 workflow:OpenDesign PR #9 已合并(main `7fc71bf`;`release.yml`,tag 打在构建提交上,构建前核 environment 保护)。environment `release` 由业主建。真跑一次要等下一个改版本号的发版 PR,顺带补验阶段 A 的"发版 PR 能走通"。
  - environment `release`:业主已建(审批人 SunJ1ayu、不勾 Prevent self-review、部署分支只有 main)。第一次建成了 `aiwork`,名字不对时 GitHub 会在发布那一刻自动建一个没有保护的同名 environment,所以 `release.yml` 的 check 在构建前先核它的保护是齐的。
  - 第 4 步(**已通过**,2026-09-29):执行单 `workflow-migration/phase-b-step4.md`,适配器 `workflow-migration/gh-app-token`。验收:A1 令牌权限恰为 contents:read / pull_requests:write / metadata:read、仓库只有 OpenDesign(首次 422:App 权限未生效,业主改好后通过——适配器按配置要权限,因此当场暴露);A2 PR #8 评论署名 `aiwork-review[bot]`(issuecomment-5883842602);A3 推送 403、rc=128,OpenDesign 上没有探针分支;A4 私钥权限、位置、副本检查符合预期。A5 盘点:本机 `gh` 登录与 `/root/.git-credentials` 两条都属 SunJ1ayu;OpenClaw 备份脚本从 `gh` 登录取令牌;SSH 身份未核成(主机公钥未登记)。私钥放 `/etc/aiwork/apps/`(root、600,不在任何仓库里)。**不另建系统用户**:本机 agent 都以 root 运行,另建用户挡不住 root;真正隔离见 §6"agent 降为普通用户"。同时只读盘点本机的 SunJ1ayu 凭证,供第 5 步用。
  - 第 5 步(进行中):执行单 `workflow-migration/phase-b-step5.md`。甲已完成:`gh` 登录令牌已失效,03:00 备份与 09:00 GitHub-Watch 因此跑不通;本机 SSH 钥匙未登记在 GitHub。乙已完成:`aiwork-sync`(App ID `5118560`,installation `166057171`,Contents 读写,装在 aiwork、lt-workspace)、`aiwork-orchestrator`(App ID `5118664`,installation `166058398`,六项只读,装在 OpenDesign)。丙已通过:aiwork 镜像探针推送与删除成功;OpenClaw 备份带 sync 令牌推到 lt-workspace,远端 main 与本地 HEAD 一致;GitHub-Watch 用 orchestrator 令牌跑通;orchestrator 发评论被拒 403;sync 推 OpenDesign 被拒 403。(首次核 lt-workspace 报 Repository not found:核对命令没带令牌,私有仓库不带身份时 GitHub 就这样回。)顺序:盘点写入流程与 SSH 身份 → 按用途建 `aiwork-sync`(必要时 `aiwork-orchestrator`)→ 流程换上并真跑验证 → 业主在 GitHub 上吊销 → 本机先证明旧凭证已失效再删。

### 阶段 C:最小 gate(先只报不拦,再拦截)

- 交付:G1–G8、M1;`.aiwork/policy.yml`(判卷面清单、high 路径);`bin/review-pr <PR> [--leg <腿>]`:取当前 head 快照 → 运行一条现有评审腿 → 以 `aiwork-review` 发出 → 加 recheck 标签。默认 `subcodex`;**high 用的第二家族入口**就是同一命令指定一条非 OpenAI、非 Anthropic 家族的现有腿(先固定一条,如 `subdeepseek`),不做多腿调度、轮换或健康管理。第二腿失败或结论不合格时 gate 保持 failure,由人决定重跑或换腿。
- 先以 `aiwork-gate-shadow` 这个检查名只报不拦,再把必过检查从 `ci` 换成 `aiwork-gate`。用不同的名字,是为了避免切换时 neutral 被当作通过。
- **验收**:第 5 节的对抗用例全部通过 + 第 4 节的 PR #6 端到端回放全部符合预期。
- **停用**(拦截生效后):OpenDesign 停止新建 track,新任务一律走 PR + gate。
- **不删除 aiwork 的 track 代码**:业主决定 aiwork 暂不迁 GitHub PR 流程,本机仍是准本,`bin/track`、`track-guard`、`track-record`、`runlog`、`panel-*` 等继续供 aiwork 自己使用。aiwork 的迁移与旧代码删除,等 OpenDesign 的 CI、身份和 gate 稳定后**单独规划**,不绑在这一轮。

### 阶段 D:QA(核心闭环稳定后)

- Pre-QA 验收契约 + 黑盒 QA,只用于用户可见的改动;此时再建 `aiwork-qa`。进入前先写明每条新规则防什么。

### 阶段 E:OpenClaw(最后)

- 按 gate 的缺项清单派活,从 GitHub 重建状态,负责额度与健康管理。进入前同样逐条写明防什么。

---

## 4. PR #6 端到端回放(阶段 C 验收)

在 OpenDesign 上用一个无害的改动,按 PR #6 的真实过程走一遍:

| 步骤 | 预期 |
|---|---|
| 1. 云端 Claude(机器账号)开 PR | CI 自动运行 |
| 2. CI 绿,但还没有评审 | gate failure(G3) |
| 3. Codex 经 `review-pr` 在当前 head 给 PASS | gate success(standard) |
| 4. Codex 在新 head 上给 BLOCK(对应 PR #6 的第二条意见) | gate failure(G5) |
| 5. **回放失效**:Codex 试图自己推修复 | 用 `aiwork-review` 推送被拒(I1) |
| 6. **回放失效**:以非机器账号的身份往 PR 分支推 commit | gate 判 UNKNOWN → failure(G4) |
| 7. **回放失效**:试图直推 main,或从 PR 分支打包发布 | 直推被拒(R1);发版 workflow 只在 main 上跑且需业主批准(D1) |
| 8. 正确路径:Claude 推修复 → 旧评审失效 → Codex 在新 head 上复审 PASS | gate success → 自动合并 |
| 9. 附加:PR 改 `ci.yml`;CI 红;评审针对旧 SHA | 分别 failure(G2 / G1 / G3) |

---

## 5. 对抗用例(gate 的单元测试)

**应拦下:**
1. CI 红、被跳过或为 neutral(G1)
2. PR 新增一个同名的假 `ci` job(G1 核对来源路径)
3. PR 改 `ci.yml`、`run-all.sh` 或 `.aiwork/`,且业主未批准(G2)
4. 没有评审;评审针对旧 head(G3)
5. PASS 不是由 `aiwork-review` 发出,比如机器账号或 SunJ1ayu 在评论里贴一段 PASS 的 JSON(G3)
6. 评审超时、降级或零上下文(G3)
7. 评审家族等于作者家族(Claude 审 Claude)(G3)
8. PR 分支上有非机器账号的推送,也就是 PR #6 的情形(G4)
9. 仓库活动记录读不到(G4 / G8)
10. 当前 head 上既有 PASS 又有 BLOCK(G5)
11. high 路径只有一家 PASS,或缺业主批准(G6)
12. 业主批准针对旧 head;业主批准试图豁免红 CI(G7)
13. API 限流或分页不全(G8)
14. PR 修改 `.github/aiwork-gate/`:仍按 main 上的代码判,并算作判卷面(M1 / G2)

**应放行(对照组):**
- A. 机器账号推送 + CI 绿 + 当前 head 上有一条非 Claude 家族的 PASS
- B. UNKNOWN + 至少一条 PASS + 业主在当前 head 上批准 + CI 绿
- C. high 路径 + 两个不同非作者家族 PASS + 业主批准 + CI 绿

---

## 6. 暂缓清单(为什么暂缓 / 什么时候再做)

| 暂缓项 | 现在怎么处理 | 何时再做 |
|---|---|---|
| 按实现会话逐段溯源作者 | 只有机器账号推送才算已知作者,其余一律 UNKNOWN 交业主 | 本机 agent 需要当 Builder 时 |
| `aiwork-build` App、本机 Builder | 本机 agent 只评审 | 同上 |
| agent 降为普通用户(root 隔离) | 本机 agent 不当 Builder,伪造评审对它没有动机;云端 Builder 碰不到本机私钥 | 本机 agent 当 Builder 之前 |
| 结论沿用(文件内容不变就不重审) | 一律按 head SHA 精确匹配,同步 main 后重审 | 同步 main 导致的重审次数明显时(先记录次数) |
| 完整事件调度(在途规则、定时对账、dispatch) | PR 事件 + CI 完成 + recheck 标签 + 同一 PR 只保留最新一次运行 | 出现漏算或卡住时 |
| 仲裁协议(同家族反证、第三家族) | 争议交业主批准 | 业主每周处理的争议超过约 3 条时 |
| 腿名册合并、三张配置表、通用 `project.yml`、多项目 | 只有 OpenDesign 一份 `policy.yml`;家族映射从 `_review_result.py` 生成 | 接入第二个项目时 |
| 交付类型 none / deploy;回显"版本 + 构建 commit" | 只保留 OpenDesign 的 release workflow(产物天然来自 main 上的 commit) | 接入需要部署的项目时 |
| 结论格式 v3 完整外壳 | 最小 JSON 块 | 接入第二种评审腿或 QA 时 |
| 更多评审腿、多腿调度 | standard 只接 `subcodex`;high 固定加一条第二家族腿 | 核心闭环稳定后,按需逐条接入 |
| Pre-QA / 黑盒 QA | —— | 阶段 D |
| OpenClaw 调度、健康与额度迁移、并行 | 现行 `panel-review` 照旧 | 阶段 E |
| 迁到组织名下、谱系规则 | 业主已决定暂不做 | 阶段 E 复议 |

业主已拍板、继续有效:实质评审 2 轮、返工最多 3 轮(超出交业主);暂不迁组织;不设谱系规则;交付是可选插槽。

---

## 7. 业主决定(2026-09-28)

1. **aiwork 暂不迁 GitHub PR 流程**。本机 `/root/aiwork` 继续作为准本,旧 track 代码保留供 aiwork 使用;OpenDesign 启用新流程后停止为它新建 track。aiwork 的迁移与旧代码删除,等 OpenDesign 的 CI、身份和 gate 稳定后单独规划。
2. **high 保留"两个不同的非 Builder 家族评审 + 业主批准"**。业主批准是风险决策,不能替代第二次技术审查;阶段 C 补一个仅供 high 使用的最简第二家族评审入口(见阶段 C),没有第二家合格结论就不放行。
3. **阶段 A 现在开始**:先完成 PR 自动 CI 和 main 分支规则,用真实 PR 验收,不等上面两项的后续工作。
4. **(2026-09-29)云端 Claude 用机器账号 `SunJ1ayuBoT`;本机各角色用 GitHub App**;发版保留业主批准(不分测试版 / 正式版)。
5. **(2026-09-29)OpenClaw 以后当主控,日常管理交给它**。它用自己的 App 身份 `aiwork-orchestrator`,不拿业主账号(业主账号能删仓库、改或关掉规则与检查,且记录分不出人和程序)。
   业主不需要读技术细节:需要业主确认的事,由 OpenClaw 先写成一句大白话(改了什么、测试和评审结果、建议),业主只决定"发 / 不发"。
   发版与 high 的最后确认暂时仍是业主点一下;几次发版顺利后,业主可以改成交给 OpenClaw(去掉 `release` 环境的审批人、给 orchestrator 触发权限),代价是出错或被 PR 里的文字诱导时,坏更新会直接推到所有用户电脑上,中间没有人拦。

---

## 8. 请 GPT 复核

1. G1–G8、M1、I1、D1 是否足以证明 P1–P3,有没有哪条可以再删。
2. 第 4 节的回放是否覆盖了 PR #6 的全部失效点。
3. 暂缓清单里有没有其实不能暂缓的项。
