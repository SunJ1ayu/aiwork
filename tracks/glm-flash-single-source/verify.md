# Verify: glm-flash-single-source

- Date: 2026-08-27

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再按 impact-risk 预算跑 panel-review；只有特殊控制面
> 才显式 `--all` 做全池评审。最后仍由主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [ ] build passes
- [ ] tests pass
- [ ] no secrets / unsafe ops

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t glm-flash-single-source -- <判据命令>
```

```
runlog: oracle-red rc=1 commit=591d58f dirty=yes at=2026-08-26T23:13:53Z file=tracks/glm-flash-single-source/evidence/20260826T231353Z-01-oracle-red.txt
runlog: oracle-red-r2 rc=1 commit=591d58f dirty=yes at=2026-08-26T23:20:17Z file=tracks/glm-flash-single-source/evidence/20260826T232017Z-01-oracle-red-r2.txt
runlog: green-implementation rc=0 commit=93dac40 dirty=yes at=2026-08-26T23:29:44Z file=tracks/glm-flash-single-source/evidence/20260826T232944Z-01-green-implementation.txt
```

- `oracle-red`:容器内无法创建判据要求的无外网 namespace，19 套均 `rc=78`；这是环境失败，
  不冒充功能红，但按收据规则完整保留。
- `oracle-red-r2`:沙箱外运行同一无外网判据；review-tooling `520/9`，九个红项精确覆盖
  Flash 默认五处与 agent override 的 argv/log/config/provider-map 四处；workflow-docs
  `31/1`，其余套件通过。
- `green-implementation`:同一总入口全绿；review-tooling `529/0`、workflow-docs
  `32/0`，其余 17 套也全部通过。

## Review

- 规格自查(读任何 panel 输出之前先答):<如果规格本身就是错的,会错成什么样、我怎么发现?
  panel 只验"实现合不合规格",验不了"规格对不对" —— 全池一致 PASS 也不等于题是对的。>
- 腿的花名册: <把 `<日志前缀>.roster` 里那一行**原样粘过来**,别手写>
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > **控制器没活到收尾时它压根不存在** —— 那时跑 `panel-roster <日志前缀>` 从盘上重建,
  > 与控制器自己写的**归一化后一致**(判据 R5b 守着;抬头有渲染时间戳,不是字面逐字节)。**一轮零记录的评审也粘得出这一行**,
  > 所以"那轮被砍了所以没有花名册"不再是理由(2026-08-23,track panel-roster-from-disk)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - <...>
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): <...>
  > 这里写理由；最终枚举写进 `decision.json.outcome.verdict`。归档时仍为空会被
  > `track-record validate --phase archive` 挡住，`track list` 也会打 ⚠️。

## Accepted deviations

- <接受的非关键偏差 + 原因 + 影响范围,或 None>
