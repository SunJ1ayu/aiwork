# Verify: glm-flash-single-source

- Date: 2026-08-27

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再按 impact-risk 预算跑 panel-review；只有特殊控制面
> 才显式 `--all` 做全池评审。最后仍由主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes
- [x] tests pass
- [x] no secrets / unsafe ops

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t glm-flash-single-source -- <判据命令>
```

```
runlog: oracle-red rc=1 commit=591d58f dirty=yes at=2026-08-26T23:13:53Z file=tracks/glm-flash-single-source/evidence/20260826T231353Z-01-oracle-red.txt
runlog: oracle-red-r2 rc=1 commit=591d58f dirty=yes at=2026-08-26T23:20:17Z file=tracks/glm-flash-single-source/evidence/20260826T232017Z-01-oracle-red-r2.txt
runlog: green-implementation rc=0 commit=93dac40 dirty=yes at=2026-08-26T23:29:44Z file=tracks/glm-flash-single-source/evidence/20260826T232944Z-01-green-implementation.txt
runlog: smoke-real-wrapper rc=0 commit=2b6bc08 dirty=no at=2026-08-26T23:35:24Z file=tracks/glm-flash-single-source/evidence/20260826T233524Z-01-smoke-real-wrapper.txt
runlog: final-green rc=0 commit=522c6df dirty=no at=2026-08-27T02:06:35Z file=tracks/glm-flash-single-source/evidence/20260827T020635Z-01-final-green.txt
```

- `oracle-red`:容器内无法创建判据要求的无外网 namespace，19 套均 `rc=78`；这是环境失败，
  不冒充功能红，但按收据规则完整保留。
- `oracle-red-r2`:沙箱外运行同一无外网判据；review-tooling `520/9`，九个红项精确覆盖
  Flash 默认五处与 agent override 的 argv/log/config/provider-map 四处；workflow-docs
  `31/1`，其余套件通过。
- `green-implementation`:同一总入口全绿；review-tooling `529/0`、workflow-docs
  `32/0`，其余 17 套也全部通过。
- `smoke-real-wrapper`:真实 `subglm-agent` 经 OpenCode Go 调用
  `go/glm-5.3-flash`，模型完成 Read/Bash 工具调用并输出 `Conclusion: PASS`；
  生成配置的 agent model 与 provider model map 一致。
- `final-green`:主裁提交后的干净提交态全量回归；19 套工具链判据全部通过，
  review-tooling `529/0`、workflow-docs `32/0`。

## Review

- 规格自查(读任何 panel 输出之前先答):
  规格可能错在“服务列出 Flash，但当前订阅 key 或工具调用路径不接受它”，
  或只用字符串 stub 造成假绿。主 agent 在 panel 前用同一 key 做了直接
  tool-call 探针（HTTP 200，`finish_reason=tool_calls`），又用真实 wrapper 完成了
  带 Read/Bash 的仓库评审，因此不只验证了“实现合规格”，也验证了该规格
  在当前服务与账号上成立。
- 腿的花名册:

  `submimo=SKIP(rotation) subdeepseek=SKIP(rotation) subglm=PASS(verdict=PASS) subkimi=PASS(verdict=PASS) subgemini=SKIP(rotation)`

  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > **控制器没活到收尾时它压根不存在** —— 那时跑 `panel-roster <日志前缀>` 从盘上重建,
  > 与控制器自己写的**归一化后一致**(判据 R5b 守着;抬头有渲染时间戳,不是字面逐字节)。**一轮零记录的评审也粘得出这一行**,
  > 所以"那轮被砍了所以没有花名册"不再是理由(2026-08-23,track panel-roster-from-disk)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - 主 agent 独立审无 blocking finding：原缺陷是 `MODEL` 已解析 `ZHIPU_MODEL`，
    opencode 活路径却绕过它读硬编码 `OC_MODEL_ID`。实现删除后者，日志、
    provider model map、agent config 和 CLI `-m` 全部只消费 `MODEL`。
  - 主 agent 逐行比对确认 endpoint、key/auth 处理、provider package、只读工具/
    权限、默认 40 turns、900s timeout 与 DeepSeek 分支均未改动。
  - high 风险预算派出两个不同家族：GLM Flash 与 Kimi 均独立重放了实现
    diff、旧实现红检和新实现绿检，均为 `Conclusion: PASS`，无降级、无阻断项。
  - Kimi 重放旧 commit 时 workflow-docs 为 `30/2`，原始红收据为 `31/1`；
    主 agent 核实差异是 W1 会比较当下已同步的部署副本，而原始红检时副本尚未同步。
    固定 commit 下九个核心行为红项一致，这是环境时点差异，不是产品缺陷。
  - GLM 评审员为验证旧路径误触了一次带无效 key 的 chat wrapper，获得 401；
    它未更改仓库、凭据或评审结果，与实现的真实 wrapper 成功证据不冲突。
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): PASS。用户要的底层契约已实现：换模型时运维上只需
  改 `ZHIPU_MODEL`（或修改两个独立入口各自的 standalone 默认名）；同一入口内不再有
  配置、argv 与日志分裂的第二模型源。真实探针、真 wrapper、全量回归与
  两家外部评审相互交叉，未发现需要联动更改的其他协议或安全参数。
  > 这里写理由；最终枚举写进 `decision.json.outcome.verdict`。归档时仍为空会被
  > `track-record validate --phase archive` 挡住，`track list` 也会打 ⚠️。

## Accepted deviations

- panel 前已提交的 `verify.md` 占位符对评审腿可见，触发 anchor-leak 告警。
  接受该偏差，因为两腿都被明确要求不信任 track 自述，并实际重放了 diff 和红绿检；
  主裁仅采纳可由代码/测试复现的发现，不把投票一致当独立证据。
- 真 wrapper 冒烟为控制成本临时设 `ZHIPU_MAX_TURNS=20`；默认 40 turns 未修改且
  已由行为判据覆盖，所以冒烟只验证模型身份、工具调用与端到端兼容性。
