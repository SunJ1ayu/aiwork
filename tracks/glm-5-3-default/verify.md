# Verify: glm-5-3-default

- Date: 2026-08-20
- Verdict: PASS

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再跑 panel-review 的全部评审腿,主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes
- [x] tests pass
- [x] no secrets / unsafe ops

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t glm-5-3-default -- <判据命令>
```

```
runlog: default-red rc=1 commit=072067d dirty=yes at=2026-08-20T05:45:48Z file=tracks/glm-5-3-default/evidence/20260820T054548Z-01-default-red.txt
runlog: default-green rc=0 commit=ae2be6e dirty=yes at=2026-08-20T05:50:43Z file=tracks/glm-5-3-default/evidence/20260820T055043Z-01-default-green.txt
```

- `default-red`: 旧实现仍是 5.2，新的 5.3 合同正好红 5 条（agent/chat default、help、
  OpenCode model argv、日志 model）；其余 422 条保持绿。
- `default-green`: 切换后 12 套总入口全绿，review-tooling `427/0`、review-workspace `24/0`。

## Review

- lane: self — 用户明确要求本轮不再做四审；同一 Go 订阅内仅替换默认 model id，不改端点、
  auth、权限、钱或数据一致性边界，并由全量回归 + 真实 5.3 冒烟承重
  > **碰了新写口 / 权限 / auth / 钱 / 数据一致性 → full,针孔再薄也不打折**(硬规矩,别在这降档)。
  > fast = 主+1,中等风险;self = 主自审(闸③ + 截图 + 全量回归),
  > 限纯前端/纯观感、后端一字未动、只新增已过审针孔的调用方。
- 派给: 主 agent 直接干 —— 仅两处默认值与既有判据，真实服务验证由主 agent 掌握凭证边界
- 规格自查(读任何 panel 输出之前先答):规格可能错在“目录列出 5.3 但当前 key/tool-call 实际不可用”；
  用真实 `subglm-agent` 冒烟而不是 stub 断言发现。
- 腿的花名册: 不适用:用户明确要求本轮不做四审，未运行 panel
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - 主 agent 亲读 diff:agent/chat 两条默认路径与 help 同步到 5.3，override、端点、认证、
    权限和轮次上限未变。
  - 真实 `subglm-agent` 冒烟回显 `model: go/glm-5.3`，可读仓库并给出 `Conclusion: PASS`；
    日志 `logs/glm-5-3-real-smoke.log` `[仓外不承重]`。
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): PASS — 5 条红合同全部转绿，真实默认路径已由运行中的 5.3 回显确认。
  > **归档时这一条和顶部的 `Verdict:` 都不许还是占位符**,`track-guard` 规矩3 会挡;
  > 没归档但已经合并上线的,`track list` 会打 ⚠️(stage-timer 就这么漏了两个月)。

## Accepted deviations

- 按用户明确要求不做四审；风险由现有完整工具回归和一次真实 GLM-5.3 agent 冒烟覆盖。
