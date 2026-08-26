# Verify: panel-all-from-roster

- Date: 2026-08-26

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再跑 panel-review 的全部评审腿,主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [ ] build passes
- [ ] tests pass
- [ ] no secrets / unsafe ops

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t panel-all-from-roster -- <判据命令>
```

初次 sandbox 内运行被无出口守卫拒绝（rc=78），随后经授权在 network namespace 中重跑；两类记录都保留：

```
runlog: oracle-red-panel-all rc=78 commit=d5f4058 dirty=yes at=2026-08-26T05:11:23Z file=tracks/panel-all-from-roster/evidence/20260826T051123Z-01-oracle-red-panel-all.txt
runlog: oracle-red-observation-capacity rc=78 commit=d5f4058 dirty=yes at=2026-08-26T05:11:23Z file=tracks/panel-all-from-roster/evidence/20260826T051123Z-02-oracle-red-observation-capacity.txt
runlog: oracle-red-doc-contract rc=78 commit=d5f4058 dirty=yes at=2026-08-26T05:11:23Z file=tracks/panel-all-from-roster/evidence/20260826T051123Z-03-oracle-red-doc-contract.txt
runlog: oracle-red-panel-all-real rc=1 commit=d5f4058 dirty=yes at=2026-08-26T05:13:04Z file=tracks/panel-all-from-roster/evidence/20260826T051304Z-01-oracle-red-panel-all-real.txt
runlog: oracle-red-observation-capacity-real rc=1 commit=d5f4058 dirty=yes at=2026-08-26T05:13:25Z file=tracks/panel-all-from-roster/evidence/20260826T051325Z-01-oracle-red-observation-capacity-real.txt
runlog: oracle-red-doc-contract-real rc=1 commit=d5f4058 dirty=yes at=2026-08-26T05:16:13Z file=tracks/panel-all-from-roster/evidence/20260826T051613Z-01-oracle-red-doc-contract-real.txt
runlog: oracle-red-observation-capacity-r2 rc=1 commit=d5f4058 dirty=yes at=2026-08-26T05:24:24Z file=tracks/panel-all-from-roster/evidence/20260826T052424Z-01-oracle-red-observation-capacity-r2.txt
```

红因与需求一一对应：旧 `--all` 只调用花名册的一部分；reader/writer 都拒收完整池 observation；README/panel skill 没有全池语义。

## Review

- 规格自查(读任何 panel 输出之前先答):如果把目标翻译成“把 4 改成 5”，下一次加减腿就会复发；因此判据只比较运行时花名册集合，不比较固定数字。panel 只验实现是否合规格，不能替代这一步建模。
- 腿的花名册: <把 `<日志前缀>.roster` 里那一行**原样粘过来**,别手写>
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > **控制器没活到收尾时它压根不存在** —— 那时跑 `panel-roster <日志前缀>` 从盘上重建,
  > 与控制器自己写的**归一化后一致**(判据 R5b 守着;抬头有渲染时间戳,不是字面逐字节)。**一轮零记录的评审也粘得出这一行**,
  > 所以"那轮被砍了所以没有花名册"不再是理由(2026-08-23,track panel-roster-from-disk)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - `--all` 把预算硬编码为 4，命令名和全池预期不一致。
  - `track-record` 的 4-leg 上限重复了容量规则；64 KiB 才是稳定 compact 边界。
  - 帮助列表、README、panel/track skill 和 verify 模板仍有现行固定数量或漏腿措辞。
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): <...>
  > 这里写理由；最终枚举写进 `decision.json.outcome.verdict`。归档时仍为空会被
  > `track-record validate --phase archive` 挡住，`track list` 也会打 ⚠️。

## Accepted deviations

- 按用户明确要求不启动外部评审；该 high-impact track 会如实保留 coverage 缺口，不用降风险或伪造 PASS 绕过机械归档闸。
