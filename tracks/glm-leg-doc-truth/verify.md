# Verify: glm-leg-doc-truth

- Date: 2026-08-27

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再按 impact-risk 预算跑 panel-review；只有特殊控制面
> 才显式 `--all` 做全池评审。最后仍由主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes（纯 shell/Markdown；相关脚本 `bash -n` 通过）
- [x] tests pass
- [x] no secrets / unsafe ops

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t glm-leg-doc-truth -- <判据命令>
```

```
runlog: oracle-red rc=1 commit=7a5245d dirty=yes at=2026-08-27T02:59:21Z file=tracks/glm-leg-doc-truth/evidence/20260827T025921Z-01-oracle-red.txt
runlog: green-docs rc=1 commit=1cdfb77 dirty=yes at=2026-08-27T03:01:14Z file=tracks/glm-leg-doc-truth/evidence/20260827T030114Z-01-green-docs.txt
runlog: green-docs-r2 rc=0 commit=1cdfb77 dirty=yes at=2026-08-27T03:02:03Z file=tracks/glm-leg-doc-truth/evidence/20260827T030203Z-01-green-docs-r2.txt
runlog: green-docs-r3 rc=0 commit=1cdfb77 dirty=yes at=2026-08-27T03:03:44Z file=tracks/glm-leg-doc-truth/evidence/20260827T030344Z-01-green-docs-r3.txt
runlog: full-green rc=0 commit=ec5e028 dirty=no at=2026-08-27T03:04:19Z file=tracks/glm-leg-doc-truth/evidence/20260827T030419Z-01-full-green.txt
runlog: review-fixes-green rc=0 commit=016fd0d dirty=yes at=2026-08-27T03:33:19Z file=tracks/glm-leg-doc-truth/evidence/20260827T033319Z-01-review-fixes-green.txt
```

- `oracle-red`:旧状态 32 项通过、4 项失败；失败精确覆盖 OpenCode agent/端点、旧默认腿
  断言、README/help 入口说明和 Gemini 员工枚举，没有既有项目误红。
- `green-docs`:35/1；唯一失败是判据把 endpoint 标签和值限定在同一物理行，属于排版误报，
  改为分别验证后重跑。
- `green-docs-r2`:36/0；其后人工复扫又发现 chat 注释仍把旧 x-api-key 路径写成当前 agent，
  补充修正与禁用词后由 r3 取代。
- `green-docs-r3`:36/0；最终定向文档契约全绿，规范源与部署副本逐字一致。
- `full-green`:实现提交后的干净提交态完整工具链全绿；review-tooling 529/0、
  workflow-docs 36/0，其余 17 套也全部通过。
- `review-fixes-green`:落实 Kimi 的低风险换行建议，并顺手修正它指出的两处既有帮助/注释
  失真后，定向文档契约仍为 36/0；最终干净全量收据在评审修正提交后补录。

## Review

- 规格自查(读任何 panel 输出之前先答):规格最可能错成“为了统一措辞，把仍有价值的历史沿革
  也删掉”，或把 OpenCode 当前路径与休眠的 Claude fallback 配置混为一谈。判断依据必须是
  当前实际消费点，历史事实保留但标清时态；不能用文字整齐代替运行语义。
- 腿的花名册（机器收尾工件原文）：

  ```text
  # panel-review 花名册(2026-08-27 11:32:03)task=glm-leg-doc-truth
  # PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
  # impact-risk=high requested-budget=2 selected-count=3
  # selected=submimo(xiaomi/submimo),subkimi(moonshot/subkimi),subgemini(google/subgemini)
  # escalation=failure
  # snapshot=head:016fd0d
  # 日志:/root/aiwork/logs/panel-glm-leg-doc-truth-20260827-r1.*.log
  submimo=PASS(verdict=PASS) subdeepseek=SKIP(rotation) subglm=SKIP(rotation) subkimi=PASS(verdict=PASS) subgemini=FAIL(rc=1)
  ```

  high 风险所需的两家独立家族覆盖由 Xiaomi/MiMo 与 Moonshot/Kimi 满足；Google/Gemini
  因登录凭据预检失败，没有报告、没有被算作通过。失败后控制器按预算升级至 MiMo，未降级风险档。
- findings:
  - 主 agent 逐行审 `7a5245d..ec5e028`：可执行脚本只改帮助文本和注释，没有修改
    模型解析、端点、认证、权限、选腿或调用 argv。
  - 规范源把当前 agent 明确为 `subglm-agent → opencode run`，provider base 为
    `/zen/go/v1`，chat 为显式/失败回落；与 `subagent`、花名册和 panel-explore 实现一致。
  - 活引用复扫未发现旧默认腿/Claude 壳/旧 agent endpoint 断言；旧模型值只存在于
    历史沿革或负向测试。部署 CLAUDE 与 panel legs 副本均和规范源逐字一致。
  - 新判据先在旧状态稳定红 4 项，修后 36/0；中间一次物理换行误报已公开保留并纠正，
    没有通过改松产品语义取得绿灯。
  - MiMo 独立复核未发现 blocking issue，确认 `bin/` 非注释差异仅帮助文本、运行路径未变，
    并重放了默认模型、端点、选腿、部署副本一致性与测试证据。
  - Kimi 独立复核结论 PASS，提出一项低风险健壮性问题：同一行 grep 会因 Markdown 纯换行
    误红；同时指出 `subchat` 的 Claude fix 假设和 `subagent -h` 的通用 auth 路径两处既有失真。
    三处均已作窄修复，新增判据锁住显式 DeepSeek/OpenCode auth 默认路径和旧注释禁用词。
  - Kimi 在 owner panel 并发期间重跑 review-tooling 得到 528/1；唯一 V45 失败是同一轮 Kimi
    进程刷新 owner credential fingerprint，正是判据注明的并发误报场景。该 snapshot 的 track
    干净全量证据为 529/0，且本次改动没有认证写路径，故不归因于产品差异。
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁):外部 panel 在 `016fd0d` 上取得两家独立 PASS，没有 blocking
  finding；主 agent 接受全部低风险建议并做窄修复。待修复提交后的干净全量回归通过，即裁为 PASS。
  > 这里写理由；最终枚举写进 `decision.json.outcome.verdict`。归档时仍为空会被
  > `track-record validate --phase archive` 挡住，`track list` 也会打 ⚠️。

## Accepted deviations

- Panel 控制器提示 anchor leak：评审 snapshot 已包含主 agent 的独立自审。任务明确要求评审员
  不信任 track 自述、直接重放 diff 和关键判据；MiMo/Kimi 均按此执行并给出独立证据，因此接受。
- Gemini 因本机未登录而失败；它没有产出裁决，也没有计入覆盖。控制器按 high 风险失败升级规则
  补派 MiMo，最终由两个不同家族的有效 PASS 满足预算，因此不额外重跑 Gemini。
