# Verify: subgemini-review-leg

- Date: 2026-08-25

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再跑 panel-review 的全部评审腿,主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] Bash 语法检查通过：本次涉及的 6 份脚本全部 `bash -n`
- [x] 最终三套判据通过：review-tooling **523/0**、panel observation **62/0**、
      panel roster **41/0**；收据确认 `source-stable: yes`
- [x] V46 在外部 owner token 明确不存在时仍 **36/0**，证明判据只用夹具 token；
      V45 同时确认业主凭证目录 / Kimi home / MiMo home / agy 登录原封不动
- [x] 真链冒烟：`evidence/subgemini-smoke7.log` 由活 Gemini 完整交卷；原仓只读、隔离 home、
      评审后凭证擦除均走的是部署中的 `bin/subgemini`

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t subgemini-review-leg -- <判据命令>
```

```
runlog: oracle-red-v46 rc=1 commit=abfb49a dirty=yes at=2026-08-25T15:45:37Z file=tracks/subgemini-review-leg/evidence/20260825T154537Z-01-oracle-red-v46.txt
runlog: oracle-red-dispatch rc=1 commit=ba0b889 dirty=yes at=2026-08-26T00:48:18Z file=tracks/subgemini-review-leg/evidence/20260826T004818Z-01-oracle-red-dispatch.txt
runlog: oracle-red-v46-round2 rc=1 commit=68df60f dirty=yes at=2026-08-26T00:57:01Z file=tracks/subgemini-review-leg/evidence/20260826T005701Z-01-oracle-red-v46-round2.txt
runlog: oracle-red-verdict-parse rc=1 commit=699e1ff dirty=yes at=2026-08-26T03:28:45Z file=tracks/subgemini-review-leg/evidence/20260826T032845Z-01-oracle-red-verdict-parse.txt
runlog: final-oracle-all rc=143 commit=94fc0a1 dirty=no final=yes at=2026-08-26T03:33:13Z file=tracks/subgemini-review-leg/evidence/20260826T033313Z-01-final-oracle-all.txt
runlog: resume-tooling rc=1 commit=94fc0a1 dirty=yes at=2026-08-26T03:38:41Z file=tracks/subgemini-review-leg/evidence/20260826T033841Z-01-resume-tooling.txt
runlog: oracle-red-v41-subctx rc=1 commit=94fc0a1 dirty=yes at=2026-08-26T03:47:13Z file=tracks/subgemini-review-leg/evidence/20260826T034713Z-01-oracle-red-v41-subctx.txt
runlog: oracle-red-final-findings rc=1 commit=e6e8122 dirty=yes at=2026-08-26T04:31:53Z file=tracks/subgemini-review-leg/evidence/20260826T043153Z-01-oracle-red-final-findings.txt
runlog: final-oracle-all rc=0 commit=e1ba97f dirty=no final=yes at=2026-08-26T04:52:53Z file=tracks/subgemini-review-leg/evidence/20260826T045253Z-01-final-oracle-all.txt
```

## Review

- 规格自查：最危险的错规格有两个。第一，把“第五条候选腿”误解为 `--all` 同轮必须派五条；
  Claude 留下的 V22 草稿正好这样错，我用 `.plan` 证实预算契约仍是四审，改成两个轮换窗口
  联合覆盖五腿。第二，把 Bash EXIT/signal 语义靠理论下结论；最终以 TERM/HUP 整组探针和
  V47 的临时靶文件结果为准，不采纳无法复现的说法。
- 腿的花名册（第三轮日志经修好的裁决解析器从盘上重建）：
  `submimo=PASS(verdict=PASS) subdeepseek=PASS(verdict=PASS) subglm=PASS(verdict=UNKNOWN) subkimi=SKIP(health:cooldown:INCOMPLETE) subgemini=off`
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > **控制器没活到收尾时它压根不存在** —— 那时跑 `panel-roster <日志前缀>` 从盘上重建,
  > 与控制器自己写的**归一化后一致**(判据 R5b 守着;抬头有渲染时间戳,不是字面逐字节)。**一轮零记录的评审也粘得出这一行**,
  > 所以"那轮被砍了所以没有花名册"不再是理由(2026-08-23,track panel-roster-from-disk)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - 第一轮 subdeepseek / subglm 双 BLOCK 的 11 条发现全部复现并落地：真实派发、表驱动唯一源、
    `ro-repo-exec`、锁 fd、凭证擦除、报告捞取、判据 mutation/inflight 均有行为级断言。
  - 第二轮虽降级且没有完整收口裁决，失败日志仍给出三个有效发现：环境污染可改题、`cp` 到
    trap 之间的凭证窗口、固定报告名可预植入/符号链接；均已修。
  - 第三轮 subdeepseek 指出交叉接错二进制与 V22 漏测 Gemini；subglm 指出第三套 env scrub、
    另外两份 mutation runner 缺信号生命周期、V46 依赖实时 token；全部先红后绿。
  - submimo 指出的“只有裁决行的半截报告”已拒收；装饰过的真裁决行现在能解析，含竖线的格式
    示例仍保持 UNKNOWN。
  - `LOG_FILE` 是可信调用方参数、模型不可控，不增加额外路径锁；异常中断的 `.mutation-state`
    故意不 gitignore，脏状态正是防止下一轮在被变异实现上继续判卷的第二道可见证据。
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): PASS。核心不变量均有闭环证据：只运行 `gemini-*`、真实派发进轮换池、
  原仓只读且副本可写、owner 凭证不被修改、临时凭证按退出路径擦除、rc=0 无裁决不收、半截/预植入
  报告不收、五条腿家族记账与实际二进制一致。最终干净 HEAD 上 626 条断言全绿且源码稳定。
  > 这里写理由；最终枚举写进 `decision.json.outcome.verdict`。归档时仍为空会被
  > `track-record validate --phase archive` 挡住，`track list` 也会打 ⚠️。

## Accepted deviations

- 按用户明确要求不再重复第四轮外部评审；已有第三轮覆盖最终主干，之后的改动仅是逐条消费其
  findings 与机械判据收口，并由主 agent 亲读 diff、亲跑三套 oracle、亲读结果。
- `agy` 闭源自更新、`--mode plan` 是否机械锁、agent 腿仓外读取、在 Gemini 腿内安全运行任意
  测试仍是跨 track 敞账；本实现不依赖这些能力，也不宣称已解决。
- SIGKILL 无法运行 shell trap，可能留下隔离 home 的 token 副本；这是不可捕获信号的物理边界。
  正常 timeout / TERM / HUP 路径已实测擦除，下一轮启动也会重新覆盖并在退出时清理。
