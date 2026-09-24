# 方案挑战题面(4c):评审分裂时由主裁裁决

仓库:/root/aiwork(本机多 agent 工作流工具)。**不要读** `tracks/arbiter-resolves-split-review/design.md`、`tasks/*my-review*` 与任何 panel 日志(那是主裁自己的方案与自审)。
可读:`bin/track-record`、`bin/_review_result.py`、`bin/_review_delivery.py`、`tests/test-track-record.sh`、`workflow/skills/panel/SKILL.md`、`/root/CLAUDE.md`、`tracks/arbiter-resolves-split-review/proposal.md`。

## 背景事实
- 这台机器上,一个「主 agent」是唯一仲裁者;外部模型(MiMo、DeepSeek、Grok…)当评审腿,输出 PASS/BLOCK,只是证据。
- 改动按风险要 0/1/2 家不同模型家族评审。归档闸(`bin/track-record validate --phase archive`)要求:同一次评审(run)、同一份交付内容(subject digest)里,
  有足够多「合格」的不同家族腿,**且合格腿之间没有 PASS/BLOCK 冲突**(`_review_result.summarize_results` 的 `conflict`)。
- 现状后果:两家都 BLOCK ⇒ 主裁可以逐条驳回后判 PASS 归档;一家 PASS 一家 BLOCK ⇒ 这次评审整组作废,主裁驳回也没用,只能重派。
- 09-22 设这道「冲突闸」是为了防两件事:主裁一句话推翻 BLOCK;主裁重抽评审直到全 PASS。
- 09-24 实例:一个改动第 11 轮修完后产品代码零改动,又派了三次评审;最后一次 DeepSeek PASS、MiMo BLOCK,
  MiMo 的阻断理由属于「测试挡不住某种假想的错误改法」「上个版本就有的老行为」。

## 业主原话(09-24)
- 「你是主裁决，你如果是这种有人拿锤子砸墙墙会不会裂这种情况你应该直接否决啊」
- 「好就按这个规定吧，主要是一家通过一家不通过需要你来判断 你觉得可以过就写清理由和证据没错的」

## 拟改变的行为
- 一家 PASS 一家 BLOCK 时,若主裁在 track 的 decision.json 里写了一份裁决记录(绑定该 run 与 subject digest,覆盖每条 BLOCK 腿,
  每条被驳回/延期的意见写理由 + 仓内可查的证据路径),且最终裁决 PASS,归档闸就把这次评审算进覆盖;记录不全 ⇒ 照旧挡。
- 评审之后才写这份记录,写它不应让这次评审的内容绑定失效(现在 `outcome.verdict` 已是这种豁免)。
- 其余覆盖规则(超时/无结论/降级/跨 run 拼接/同家族凑数、两家都 BLOCK)不变。

## 请回答(不必凑问题,不要只核对上面条款)
1. 完全照这样实现,业主的目标仍会怎样落空?(从「主裁唯一仲裁 + 不一句话推翻 + 不重抽」出发推失败场景)
2. 哪个前提若为假就要重做?请到代码里核实最可疑的那个。
3. 有没有更简单的方向?用什么最小实验能分辨?
