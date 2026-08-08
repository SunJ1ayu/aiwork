# Verify: machine-evidence-gate

- Date: 2026-08-08
- Verdict: <PASS | BLOCK | NEEDS_MORE_INFO>

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再跑 panel-review 的全部评审腿,主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [ ] build passes
- [ ] tests pass
- [ ] no secrets / unsafe ops

## Review

- lane: full
  > 改的是**判卷防线本身**(pre-commit 守卫 + 归档命令),而且新增一个会**往仓里写文件**
  > 的工具(`runlog` 造 `evidence/`)。写口 + 防线,针孔再薄也不打折。
  > 前例同款:`redcheck-pycache`(08-08)也是动防线走的 full。
- 派给: 主 agent 直接干 —— 这一单造的就是**判卷基础设施**,而「oracle 永远由主 agent
  亲自写,绝不外包」;把守卫外包等于让考生改考场规则。判卷不起服务、无外部依赖,
  起一条执行腿的开销大于收益。
- 规格自查(读任何 panel 输出之前先答):
  规格 = 「verify.md 里粘的数,必须是机器写下的那个数」。它可能这样错:
  ① **高估强度** —— 这四条挡不住蓄意伪造(手改收据文件即可)。装完之后我若以为
     "有闸了,数字可信",反而比没闸更危险 ⇒ 说明书里必须写死"只堵四舍五入"。
  ② **误报** —— 老工件被挡、或中途提交被挡,则一定会被 `--no-verify` 绕过,
     那比没有守卫更糟(规矩3 的注释里已经栽过一次这个道理)⇒ 反误报用例要占一半。
  ③ **只管形式不管内容** —— 收据行齐全,但跑的是一份问不出东西的判据。
     这道闸**结构上照不到**,别指望它;那是 lane / oracle 的活。
  ④ **无人使用** —— 不强制用 runlog ⇒ 干脆不用它就绕过了整条闸。
     5c(归档时零收据必须显式认账)是唯一的兜底,而它给的是认账口不是硬堵。
- 腿的花名册: <把 `<日志前缀>.roster` 里那一行**原样粘过来**,别手写>
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - <...>
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): <...>
  > **归档时这一条和顶部的 `Verdict:` 都不许还是占位符**,`track-guard` 规矩3 会挡;
  > 没归档但已经合并上线的,`track list` 会打 ⚠️(stage-timer 就这么漏了两个月)。

## Accepted deviations

- <接受的非关键偏差 + 原因 + 影响范围,或 None>
