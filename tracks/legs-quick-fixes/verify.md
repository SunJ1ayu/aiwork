# Verify: legs-quick-fixes

- Date: 2026-09-14

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

## 主 agent 亲跑/亲读发现(读任何 panel 之前)

- **判据**:`tests/test_leg_quick_fixes.py` 十条(七目标 + 三对照)。首跑时 9 红,其中 2 条是我夹具的错
  (DeepSeek 对照没拷 `deepseek-model`;emit 复用同一结果文件 ⇒ 第二次读回第一次的 quota)⇒ 修夹具后
  **旧实现上恰好 7 红、3 对照绿**,提交 `9661023` 后留红收据;修复 `592a335` 后 10 绿。
- **在使用现场验证(16:09,主 agent 亲跑,非判据收据;tiny 仓 `add.py`)**,新旧各跑一次同一道题:
  - A4 GLM 底座腿,题面要求先读 `/etc/hostname`:
    - 旧 `subagent`(`9661023`):`! permission requested: external_directory (/etc/*); auto-rejecting` → `✗ Read /etc/hostname failed`
      → `Glob "add.py"` 后整轮结束 → `subglm-agent: model returned no verdict`,rc=1。
    - 新:同样被拒,之后 `Read add.py` → `Step 1: the /etc/hostname read was denied by the harness …` → `Conclusion: PASS`,rc=0。
  - A5 GLM 聊天回落腿(`subglm`):
    - 旧引擎:`HTTP 400 … "type":"MissingSessionID","message":"Error from provider (Console Go): Request is missing x-opencode-session …"`,rc=1(今天仍复现)。
    - 新:rc=0,正常返回(结论 NEEDS_MORE_INFO 是聊天腿在干净仓上「看不见代码」的已知限制,不是本单的事)。
  - A1 MiMo(`submimo`):真跑本地断言后 `Conclusion: PASS`,rc=0。
  - A2 subkimi 的抄错误行只走失败路径,真跑触发不了额度窗口 ⇒ 只有离线判据,如实记。
- **我自己的风险判断**:
  - A3 若某家把「余额耗尽」也写成 usage limit ⇒ 那条腿永不停轮换(每次冷却后再失败一次、有备用腿兜底)= 回到 08-25 前的行为,可接受。
  - A2b 只认 kimi-code 0.36.1 的 `^error: failed to run prompt:` 措辞;CLI 改措辞就退回「runtime」(只是归类变粗,不会假绿)。
  - A4 被拒后继续 ⇒ 模型可能反复撞被拒工具直到 `steps=40`,有上限。
  - A1 只改了 GLM/DeepSeek(subagent)和 MiMo;Kimi/Grok 的契约仍在任务书前但另有「先写裁决」指令,第三轮两家都按格式交卷,不动。
  - 这次评审的腿用的就是改过的提示词(自指),不影响判断:它们审的是代码,不是自己的输出。
  - **A2 回落扫正文的老路径**:`failure_text` 在我们的诊断为空时回落到模型正文。若某腿 rc≠0、stderr 为空、而正文恰好写到
    "usage limit"(例如正在审本单)⇒ 被归成 rate_limit、不计连败。与 08-28「正文 auth 误判」同类;窗口词比 auth 罕见,
    且各腿失败时 stderr 几乎总有我们自己的一行 ⇒ 接受,列为外审要攻的点。

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
runlog -t legs-quick-fixes -- <判据命令>
```

```
runlog: oracle-red-on-old-code rc=1 commit=9661023 dirty=no at=2026-09-14T07:58:05Z file=tracks/legs-quick-fixes/evidence/20260914T075805Z-01-oracle-red-on-old-code.txt
runlog: oracle-green rc=0 commit=592a335 dirty=no at=2026-09-14T07:59:51Z file=tracks/legs-quick-fixes/evidence/20260914T075951Z-01-oracle-green.txt
runlog: full-regression rc=0 commit=592a335 dirty=yes final=yes at=2026-09-14T07:59:58Z file=tracks/legs-quick-fixes/evidence/20260914T075958Z-01-full-regression.txt
```

- 红收据:旧实现上恰好 7 条目标红、3 条对照绿。
- 全量回归 27 组全绿(含新套件 `leg-quick-fixes`);`dirty=yes` 只是上一份未提交的 `oracle-green` 收据与 observation,实现与判据跑前已提交。

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
