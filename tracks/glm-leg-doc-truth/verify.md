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

## Review

- 规格自查(读任何 panel 输出之前先答):规格最可能错成“为了统一措辞，把仍有价值的历史沿革
  也删掉”，或把 OpenCode 当前路径与休眠的 Claude fallback 配置混为一谈。判断依据必须是
  当前实际消费点，历史事实保留但标清时态；不能用文字整齐代替运行语义。
- 腿的花名册:尚未运行外部 panel；high 风险评审预算未满足，不能归档。
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > **控制器没活到收尾时它压根不存在** —— 那时跑 `panel-roster <日志前缀>` 从盘上重建,
  > 与控制器自己写的**归一化后一致**(判据 R5b 守着;抬头有渲染时间戳,不是字面逐字节)。**一轮零记录的评审也粘得出这一行**,
  > 所以"那轮被砍了所以没有花名册"不再是理由(2026-08-23,track panel-roster-from-disk)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - 主 agent 逐行审 `7a5245d..ec5e028`：可执行脚本只改帮助文本和注释，没有修改
    模型解析、端点、认证、权限、选腿或调用 argv。
  - 规范源把当前 agent 明确为 `subglm-agent → opencode run`，provider base 为
    `/zen/go/v1`，chat 为显式/失败回落；与 `subagent`、花名册和 panel-explore 实现一致。
  - 活引用复扫未发现旧默认腿/Claude 壳/旧 agent endpoint 断言；旧模型值只存在于
    历史沿革或负向测试。部署 CLAUDE 与 panel legs 副本均和规范源逐字一致。
  - 新判据先在旧状态稳定红 4 项，修后 36/0；中间一次物理换行误报已公开保留并纠正，
    没有通过改松产品语义取得绿灯。
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁):待外部评审。主 agent 当前未发现 blocking finding，
  但 `decision.json` 将本单标为 judging_control/high，不能用自审和全绿代替规定的两家覆盖。
  > 这里写理由；最终枚举写进 `decision.json.outcome.verdict`。归档时仍为空会被
  > `track-record validate --phase archive` 挡住，`track list` 也会打 ⚠️。

## Accepted deviations

- None（评审预算未完成属于待办，不作为偏差接受）。
