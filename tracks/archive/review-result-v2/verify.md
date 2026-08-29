# Verify: review-result-v2

- Date: 2026-08-28

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再按 impact-risk 预算跑 panel-review；只有特殊控制面
> 才显式 `--all` 做全池评审。最后仍由主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes（无独立编译产物；Python/Shell 入口由总闸逐项加载和执行）
- [x] tests pass
- [x] no secrets / unsafe ops

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog: full-regression rc=0 commit=b4ce427 dirty=no final=yes at=2026-08-28T10:39:50Z file=tracks/review-result-v2/evidence/20260828T103950Z-01-full-regression.txt
runlog: red-v43-eligibility rc=1 commit=8f57889 dirty=yes at=2026-08-28T12:29:32Z file=tracks/review-result-v2/evidence/20260828T122932Z-01-red-v43-eligibility.txt
runlog: red-v43-eligibility-r2 rc=1 commit=56cfd2d dirty=yes at=2026-08-28T12:44:33Z file=tracks/review-result-v2/evidence/20260828T124433Z-01-red-v43-eligibility-r2.txt
runlog: green-v43-eligibility rc=1 commit=56cfd2d dirty=yes at=2026-08-28T12:55:26Z file=tracks/review-result-v2/evidence/20260828T125526Z-01-green-v43-eligibility.txt
runlog: green-v43-eligibility-r2 rc=0 commit=56cfd2d dirty=yes at=2026-08-28T13:01:37Z file=tracks/review-result-v2/evidence/20260828T130137Z-01-green-v43-eligibility-r2.txt
runlog: red-failure-kind rc=1 commit=5b7f6d9 dirty=yes at=2026-08-28T13:14:37Z file=tracks/review-result-v2/evidence/20260828T131437Z-01-red-failure-kind.txt
runlog: full-regression-final rc=1 commit=aa6cb98 dirty=no final=yes at=2026-08-28T13:27:03Z file=tracks/review-result-v2/evidence/20260828T132703Z-01-full-regression-final.txt
runlog: red-ineligible-cooldown rc=1 commit=aa6cb98 dirty=yes at=2026-08-28T13:39:56Z file=tracks/review-result-v2/evidence/20260828T133956Z-01-red-ineligible-cooldown.txt
runlog: full-regression-final-r2 rc=0 commit=dd745e4 dirty=no final=yes at=2026-08-28T13:40:59Z file=tracks/review-result-v2/evidence/20260828T134059Z-01-full-regression-final-r2.txt
runlog: full-regression-final-r3 rc=0 commit=72caea4 dirty=no final=yes at=2026-08-28T15:48:38Z file=tracks/review-result-v2/evidence/20260828T154838Z-01-full-regression-final-r3.txt
```

红收据逐份是什么红的(不许四舍五入成散文):

- `red-v43-eligibility` rc=1,3 红。**其中两条红在错的地方** —— ⑨ 把 `subdeepseek-agent`
  换成必败桩后一直没换回来,⑩⑫ 里那条腿必然降级,`escalation=degraded` 盖住了要问的原因。
  是我加的"把实际值打印出来"当场照出来的(打印的是 `# escalation=degraded`)。
  **红在别处 = 等于没红检过**,所以这份不算数,题面改完重跑。
- `red-v43-eligibility-r2` rc=1,3 红,红在被测行为上:没补腿 / `escalation=none` /
  健康状态没标记 `INELIGIBLE`。
- `green-v43-eligibility` **rc=1**:目标三条转绿,但 V43 ① 红了两条
  (`high 默认只派两条腿` / `未选中的健康腿明确记 rotation skip`)。同一 commit 重跑
  (`green-v43-eligibility-r2`)546/0 全绿,V43 单独跑 1 次 + 并发 6 次共 7 遍全绿,
  未再复现。**敞账,见下**。
- `red-failure-kind` rc=1,1 红:`assertNotEqual('auth')` 失败,实际就是 `auth`。
- `full-regression-final` **rc=1**:panel-observation 3 红(P2 两条 + P5)。
  真因是那套判据的"健康桩"只给裁决、不产 typed facts —— 在新契约下那正是
  "决定性但不可计数",于是调度器为它补腿,腿数不再是 P2/P5 想问的东西。
  修的是夹具(让桩像真腿),不是期望值。
- `red-ineligible-cooldown` rc=1,1 红,打印的实际值是
  `submimo=SKIP(health:cooldown:INELIGIBLE)` —— 我自己新加的状态把最靠谱的腿
  按进了 6 小时冷却。

## Review

- 规格自查(读任何 panel 输出之前先答):如果规格错了，最危险的两种错法是把
  “完成了一次有效审查”偷换成“审查结论自动批准收货”，或让 subject identity 混入
  review protocol、导致同一源码对象因协议变化无法比较。当前设计用两个独立事实防止它们：
  `coverage_eligible` 只判腿是否完成可信审查，最终裁决仍只在 `decision.json.outcome`；
  `subject_digest` 只含任务原始字节与实际 Git snapshot，`review_contract_version` 独立记录。
  false-coverage 矩阵再从反面验证 UNKNOWN、NMI、timeout、degraded、v1、不同 subject、
  跨 run 和冲突都不能补归档预算。若这些边界任一在 archive 与 ledger 输出不一致，
  consumer parity 判据会直接暴露，而不是靠 panel 一致 PASS 猜规格正确。
- 腿的花名册（第二轮，机器生成，逐字节）:
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > **控制器没活到收尾时它压根不存在** —— 那时跑 `panel-roster <日志前缀>` 从盘上重建。
  ```
  # impact-risk=high requested-budget=5 selected-count=5
  # selected=submimo(xiaomi/submimo),subdeepseek(deepseek/subdeepseek-agent),subglm(zhipu/subglm-agent),subkimi(moonshot/subkimi),subgemini(google/subgemini)
  # escalation=none
  submimo=PASS(verdict=PASS) subdeepseek=PASS(verdict=PASS) subglm=FAIL(rc=1,降级:回落聊天腿也没成) subkimi=FAIL(rc=124) subgemini=PASS(verdict=PASS)
  ```
  **第二轮有 Xiaomi / DeepSeek / Google 三个 coverage-eligible 家族且裁决均为 PASS；**
  Kimi 的 timeout PASS 只作 partial evidence，GLM 失败不计 coverage。完整 typed 事实已落在
  `observations/20260828T143903Z-panel-review-execution_finished-001.json`。

  第一轮(20260828,head cf4f212)的花名册,逐字节:
  ```
  # impact-risk=high requested-budget=5 selected-count=5
  # escalation=none
  submimo=PASS(verdict=PASS) subdeepseek=FAIL(rc=1,降级:回落聊天腿也没成) subglm=FAIL(rc=1,降级:回落聊天腿也没成) subkimi=FAIL(rc=124) subgemini=FAIL(rc=1)
  ```
  **五条腿只有一条交卷 ⇒ 那一轮只满足 1 个 coverage-eligible 家族,high 要 2。**
- findings（主 agent 自审，写在读第二轮 panel 之前）:
  - `ReviewLegResult v2` 已成为唯一 executable contract、normalizer 与 eligibility predicate；
    adapter 只提供 invocation/process/snapshot/view/evidence 事实。
  - production observation writer 已关闭 v1 `--leg` 写口；v1 仍可读，但不再产生
    authoritative coverage，也不会从 raw log 回填升级。
  - archive 与 ledger 只认可同一次成功 panel、同一 subject digest 的 eligible family；
    同 subject 跨 run 只输出 shadow 指标，未启用 P1 放行。
  - **调度器是最后一个没切过来的 coverage consumer**(本轮修):腿给了 PASS/BLOCK 就当数,
    而共享谓词早判它不可计数 ⇒ 归档闸才发现家族不够,而那一轮剩下的健康 reviewer
    已经白白没派。现在决定性但不合格 ⇒ 补一条腿,理由记 `ineligible`。
  - **我给这条修复带出的副作用是我自己抓的**:`INELIGIBLE` 是非 PASS 状态,而任何
    非 PASS 状态都会进 6 小时冷却 ⇒ 一次不合格就把一条**活着的**腿按下去。
    已排除出冷却,代价(配置真坏时每轮重调)写在实现注释里,且每轮印在花名册上。
  - **`failure_kind` 会撒谎,而且当天就撒了**:它拿正则扫「模型写的评审正文 + 我们的诊断」,
    第一轮 DeepSeek 腿评审的正是认证相关代码,正文里 `auth` 出现 13 次 ⇒ 它的死法被记成
    `auth`(真因:没交裁决行,`.err` 原话)。这台机器为一次假的"凭证坏了"追过六天
    (08-25 kimi)。改成先只读我们自己的 stderr,只有它一个字没说时才回落到正文;
    配反向对照(401 只出现在 stdout 时仍要认出来)。真实数据回放:同一份日志,
    修复前 `auth`,修复后 `runtime`。
  - **第一轮那条 PASS 的腿(submimo)提的第 2 条观察,它自己判成"non-blocking"是错的**:
    它说 failure_kind 的正文匹配"不会影响一次成功的评审" —— 对,但它污染的是**健康**,
    而健康决定下一轮派不派。上面那条就是它。第 3 条观察(`substantive_legs` 用 v1 口径)
    读完判为不成立:ledger 是**故意**分列 process/substantive/eligible 三栏,R10 判据钉着它们必须不同。
  - Kimi/Gemini 的 timeout verdict 和 Gemini salvage 仍保留为 partial evidence，
    但 timeout/degraded 不能计 coverage；provider-specific auth/home/lock/sandbox 与 raw log
    按原计划保留，不做 adapter 大重构。
  - **第二轮 DeepSeek 的中等 finding 已收口**:roster 过去只从 raw log 重算
    `PASS(verdict=PASS)`，会把 typed `INELIGIBLE` 伪装成普通 PASS。现在有 v2 sidecar 时
    roster 从唯一 `describe` 入口读取 verdict/eligibility，并显式打印
    `coverage=INELIGIBLE`；只有 legacy 轮次才回落 raw log。
  - **外层 oracle 递归污染已收口**:`test-panel-observation.sh` 入口现在清理
    `PANEL_ORACLE_CMD`。红检为 68/1（唯一红是入口变量非空），修后定向 69/0。
  - **V43 偶发红已定案并收口**:并发健康桩对同一个 fixture repo 跑 `git write-tree`，
    争用 `.git/index.lock`；失败腿因空 `index_tree_oid` 被 v2 正确判成
    `model_invocation_unverified/subject_unknown/view_incomplete`，调度器于是正确补 spare。
    静态 clean fixture 已改为只读 `HEAD^{tree}`，并加“不许调用 write-tree”守卫。
  - 规范源、README、track/panel skill 与 Claude 部署副本已统一改成 coverage-eligible 语义。
- 敞着的账(**不写成结论**):
  - **腿在自己沙箱里跑我们的 shell 判据会看到大批失败,真因未知。** 第一轮 GLM 腿留下
    `410 passed, 117 failed`,而本机同一 commit 是 547/0。我先推断"因为仓库对腿是只读的",
    **量了一遍推翻了自己**:在同一个只读挂载里跑是 545 passed / 1 failed。
    腿的日志只留了汇总和 FAIL 行、没留 wrapper 的 stderr,所以真因**还没量到**。
    可见后果是实的:三条腿的整个预算烧在"这些红是不是真的"上,然后超时被砍。
  - **provider 错误只出现在 stdout 时仍可能被归成 `runtime`。** 第二轮多腿命中，但当前
    wrapper 把 provider stdout 与模型评审正文混在同一日志；直接回扫会复活“正文谈 auth 就
    判凭证坏”的假阳性。它影响 health 原因标签，不会放宽 coverage 或阻止 fallback；留待
    adapter 能提供独立 provider diagnostic stream 后再修，不在本轮猜信号。
  - **subgemini 登录敞账已由业主重登关闭**:凭证恢复为权限 600 的正常文件，
    `agy models` 成功，`gemini-3.7-flash-high` 真调用返回 `GEMINI_LEG_OK`，第二轮腿随后 PASS。
- arbitrated verdict (主裁): **PASS**。理由不是“多数模型同意”，而是三个不同家族在
  同一 run、同一 subject、同一 review contract 下交出 eligible PASS，第二轮可执行 finding
  已修，最终干净提交上的 `runlog --final` 全绿；timeout/失败腿未被拿来补 coverage。

## Accepted deviations

- consumer oracle 是从额度中断留下的 dirty worktree 恢复的；提交图仍保持
  `eb0c01f`（测试矩阵）先于 `1adda64`（实现），因此 checkout 测试提交本身会红，
  但本窗口没有重新制造一遍人工红跑收据。影响仅限开发过程证据，不影响最终行为判据。

## 复核与署名(2026-08-30,主 agent 补记)

- 上面那句 `arbitrated verdict (主裁): PASS` 是**执行腿(GPT)在我额度用尽期间写的**,
  当时它不是主裁下的话。2026-08-30 我(Claude,主 agent)按业主要求做了独立复核,
  **裁决:ACCEPT** —— 这一单的 PASS 从这一刻起才是主裁下的。
- 复核不看自述,做了四件事:
  1. 在干净树 `7257520` 上亲跑全量回归 rc=0,逐项数字与 `full-regression-final-r3` 一致;
  2. 拿本单真实归档的第二轮 observation 自己跑一遍谓词:3 个 coverage-eligible 家族
     (xiaomi / deepseek / google)全 PASS、无冲突;kimi 的 timeout PASS 与 GLM 的降级
     被正确排除;
  3. 造 18 条对抗探针(NMI / UNKNOWN / timeout / degraded / rc≠0 / 篡改证据摘要 /
     证据文件丢失 / model 不符 / 视野不全 / 换 subject / 跨 run 拼接 / eligible PASS-BLOCK
     冲突 / v1 / 失败的 panel run)全部 BLOCK,而且核的是规则名
     `observation.review_budget`,不是只看 rc —— 防"红在别处";
  4. 变异 10 条打共享谓词,8 条被判据咬住。
- **咬不住的那 2 条已单独开单收口**:track `review-result-oracle-pins`
  (`subject_unknown` / `evidence_incomplete` 在判据里是搭便车的;实现里两条检查都在,
  所以不是活 bug,是钉不住)。
- 仍敞着、留给 P1 判断的结构性缺口:coverage 绑的是 panel 冻结的 `subject_digest`,
  但**没有任何地方拿它和真正被归档的那棵树比一遍**。本单自己就有一个代码提交
  (`8909f07`)落在 panel subject(`ea50e38`)之后 —— 我逐行读过,小且失败时会回落老路径,
  不改变本单裁决;但这条路是敞着的。
- 本 track 已归档,不再往它里面加收据:这次复核的机器证据在 track
  `review-result-oracle-pins` 的 evidence/ 下。
