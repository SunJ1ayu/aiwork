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
- 腿的花名册: 待第二轮 panel-review 收尾后粘贴机器生成行。
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > **控制器没活到收尾时它压根不存在** —— 那时跑 `panel-roster <日志前缀>` 从盘上重建。
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
  - 规范源、README、track/panel skill 与 Claude 部署副本已统一改成 coverage-eligible 语义。
- 敞着的账(**不写成结论**):
  - **腿在自己沙箱里跑我们的 shell 判据会看到大批失败,真因未知。** 第一轮 GLM 腿留下
    `410 passed, 117 failed`,而本机同一 commit 是 547/0。我先推断"因为仓库对腿是只读的",
    **量了一遍推翻了自己**:在同一个只读挂载里跑是 545 passed / 1 failed。
    腿的日志只留了汇总和 FAIL 行、没留 wrapper 的 stderr,所以真因**还没量到**。
    可见后果是实的:三条腿的整个预算烧在"这些红是不是真的"上,然后超时被砍。
  - **V43 ① 在总跑里红过一次、再没复现。** 同一 commit 重跑 546/0,单跑+6 并发共 7 遍全绿。
    该失败路径在没有本轮修复时同样存在(腿的 describe 一失败就会补腿),所以它不是这次
    改动引入的;但**原因未定案**。已把那格改成红时打印 rc / 实际派发数 / 升级原因 / 花名册末行,
    下次它自己说得清。
  - **subgemini 腿要业主重登**:`~/.gemini/antigravity-cli/antigravity-oauth-token`
    自 08-26 起只有 10 字节,`agy models` 说 "Please sign in"。腿是**响亮拒跑**的(不静默挂死)。
- arbitrated verdict (主裁): 待第二轮 panel 证据到齐后裁决。

## Accepted deviations

- consumer oracle 是从额度中断留下的 dirty worktree 恢复的；提交图仍保持
  `eb0c01f`（测试矩阵）先于 `1adda64`（实现），因此 checkout 测试提交本身会红，
  但本窗口没有重新制造一遍人工红跑收据。影响仅限开发过程证据，不影响最终行为判据。
