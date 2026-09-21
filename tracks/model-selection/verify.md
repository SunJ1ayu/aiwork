# Verify: model-selection

实现完成，独立评审进行中；最终裁决见 decision.json。

## 接手时核实的事实

- 原实现提交 4847497；判据先行提交 42e33fc。断线文档尚写待实施，按代码和原始收据重建状态。
- 接手补查：缺失调用事实会覆盖额度/认证/窗口限额原因。三种离线复现均先红；f34cfb5 保留真实失败原因，同家族跑错具体模型仍不计覆盖。
- 15 项候选选择、20 项结果契约、37 项流程与部署夹具检查通过；最终收据源码前后稳定。
- 原有双 Cursor 真实发散均 rc=0；精确 reported model 为 null，只证明请求/调用和家族一致。真实日志早于 no_verdict 归类修复，最终正常发散健康状态由离线端到端覆盖。
- 先前全量 runner 未全绿：基线已遗留 test-low-uncertainty-reason.sh 孤儿套件，且未引入无出口守卫。基线内容哈希及注册缺失见 evidence/orphan-baseline.txt。部署差异在候选隔离环境用规范部署夹具验证；本单不恢复已撤回旧闸。

## 运行记录与失败说明

- candidates-red / resume-candidates-red：未实现新入口，预期红。
- candidates-green rc=78：沙箱禁止无网络命名空间；宿主保留无出口隔离后通过。
- full-regression 第一遍：私有命名空间未启用 loopback，HTTP 夹具失败；修正后只余既有孤儿/no-egress 和未部署规范差异。
- focused-regression：选择、结果、observation、roster、slice 通过；文档断言尚未匹配修订，后续 final-check 已修正通过。
- final-check rc=65：命令 rc=0，但同时有回归进程写仓，source-stable=no，明确作废。
- resume-health-red：三类错误全部被错误写成 identity_mismatch。
- resume-candidates-green 第一遍仍红：测试自造 authentication failed 不属既有识别词；改用真实协议形状 401 Unauthorized，未扩张生产错误分类规则。
- resume-final-check：串行检查，rc=0、dirty=no、source-stable=yes。

```text
runlog: result-baseline rc=0 commit=e9fafc8 dirty=yes at=2026-09-20T15:10:06Z file=tracks/model-selection/evidence/20260920T151006Z-01-result-baseline.txt
runlog: candidates-red rc=1 commit=2d625b4 dirty=yes at=2026-09-20T15:14:48Z file=tracks/model-selection/evidence/20260920T151448Z-01-candidates-red.txt
runlog: resume-candidates-red rc=1 commit=2d625b4 dirty=yes at=2026-09-21T01:54:08Z file=tracks/model-selection/evidence/20260921T015408Z-01-resume-candidates-red.txt
runlog: candidates-green rc=78 commit=42e33fc dirty=yes at=2026-09-21T02:00:10Z file=tracks/model-selection/evidence/20260921T020010Z-01-candidates-green.txt
runlog: candidates-green rc=0 commit=42e33fc dirty=yes at=2026-09-21T02:08:09Z file=tracks/model-selection/evidence/20260921T020809Z-01-candidates-green.txt
runlog: full-regression rc=1 commit=42e33fc dirty=yes at=2026-09-21T02:28:19Z file=tracks/model-selection/evidence/20260921T022819Z-01-full-regression.txt
runlog: full-regression rc=1 commit=42e33fc dirty=yes at=2026-09-21T02:46:05Z file=tracks/model-selection/evidence/20260921T024605Z-01-full-regression.txt
runlog: focused-regression rc=1 commit=42e33fc dirty=yes at=2026-09-21T02:47:09Z file=tracks/model-selection/evidence/20260921T024709Z-01-focused-regression.txt
runlog: final-check rc=65 commit=4847497 dirty=yes final=yes at=2026-09-21T02:51:25Z file=tracks/model-selection/evidence/20260921T025125Z-01-final-check.txt
runlog: resume-health-red rc=1 commit=4847497 dirty=yes at=2026-09-21T06:58:04Z file=tracks/model-selection/evidence/20260921T065804Z-01-resume-health-red.txt
runlog: resume-candidates-green rc=1 commit=72b82f6 dirty=yes at=2026-09-21T06:58:27Z file=tracks/model-selection/evidence/20260921T065827Z-01-resume-candidates-green.txt
runlog: resume-candidates-green rc=0 commit=72b82f6 dirty=yes at=2026-09-21T06:58:56Z file=tracks/model-selection/evidence/20260921T065856Z-01-resume-candidates-green.txt
runlog: resume-final-check rc=0 commit=f34cfb5 dirty=no final=yes at=2026-09-21T06:59:28Z file=tracks/model-selection/evidence/20260921T065928Z-01-resume-final-check.txt
```

## 独立评审

- 第 1 轮：主仓旧调度器，MiMo(xiaomi)、DeepSeek(deepseek)、Cursor/Grok(xai)。原生 GLM/Grok/Gemini 已有鉴权或连续失败，Kimi 窗口限额，本轮显式关闭；无新增探活请求。
- 评审前自审保存在仓外；verify 在初审派发时仍为占位文本。任务禁止读 verify/self-review/其他报告。
- 日志前缀：/root/aiwork/logs/panel-model-selection-resume-r1-20260921。
- 预算最多 2 轮实质评审；基础设施重试另记。

## 处置

| 来源 | 发现 / 处置 | 依据 |
|---|---|---|
| Cursor #1 | 延期：GLM legacy chat 仍有 inline default。当前默认相等，显式成员禁止 chat fallback；本单新入口不受影响。未来调整 GLM 默认仍须同步 legacy chat 或显式 ZHIPU_MODEL；不声称全通道模型默认已唯一化。 | subchat:102；panel-review 显式 roster 的 chat 为空。 |
| Cursor #2 | 已知边界：保留，不伪造精确服务端身份。 | subcursor 的 invoked 记录 CLI 参数，reported=null；workflow 明确同样限制。 |
| Cursor #3a | 驳回缺少覆盖：测试分层位置不影响实际覆盖；不重复写同一断言。 | candidate E2E 直接 assert contract 3 PASS 不合格及 wrong-model 不合格。 |
| Cursor #3b | 已核实当前 CLI 输出：216 个已知家族精确 ID，GPT/Claude/GLM/Grok/Composer 等均被现行 first-token 解析识别。未来格式漂移是边界。 | logs/model-selection-resume-live-models.txt；只调用 models，不调用生成。 |
| Cursor #3c | 驳回必须断言诊断措辞：额度故障后同模型拒绝派发、另一模型可派已有行为断言。 | test_health_is_separate_for_cursor_models。 |
| Cursor #4 | 接受现有契约：env budget 也是显式预算，与 --members 冲突时拒绝；调用方 unset PANEL_REVIEW_BUDGET。暂无必须改写其优先级的需求。 | panel-review:104,153。 |
| Cursor #5 | 延期：全目录发现遇坏配置会整体拒绝。当前配置/发现可用；可用 --adapter 缩到需要的池。保留清晰错误，不推测不存在的候选。 | _panel_candidates.py main 的异常处理。 |
| MiMo #1/#2 | 延期：每项重读很小的 health 文件、错误文案细化。没有可复现的性能/正确性阻断。 | health_rows/describe。 |
| MiMo #3 | 驳回：explore usage 已有 [--members ID[,ID...]]，不是隐藏支持。 | panel-explore:25。 |
| MiMo 总结 | 文字 PASS，但最后为 Markdown 标题，现有严格解析得 UNKNOWN，不计归档覆盖。报告对 legacy 的“全部改动受 members 守卫”说法过宽；config 与结果 producer 的共享变化已由主 agent 独立验收。 | typed result + 原始 log；不手改裁决或 sidecar。 |
| DeepSeek | agent 超时，chat 回退无完整裁决；保留部分输入/排查为线索，不计覆盖。其 legacy 测试受继承 AIWORK_REVIEW_TRACK 污染后开始清环境复跑，未完成；主 agent 的无该变量回归已有记录。无最终具体存活 finding。 | agent.log、agent.log.err、log、log.err。 |

## 第 1 轮机器记录与重试决定

- 初审派发约 19 分 32 秒；Cursor 合格 PASS；MiMo rc=0 但 verdict=UNKNOWN；DeepSeek agent rc=124，chat rc=1。主控制器 rc=0 不代表 high 覆盖已满足，机械检查只认 1 家族。
- 源码零新增改动。基础设施重试一次：MiMo + Cursor/Composer，两家族同轮完整审查；禁止重复跑测试，末行明确要求裸裁决。用现有旧调度器，显式关闭 DeepSeek 等失败通道。最多这一次取证重试；若还不足，保持未完成，不放宽判卷规则。

```text
# panel-review 花名册(2026-09-21 15:22:05)task=model-selection-review
# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
# impact-risk=high requested-budget=7 selected-count=3
# selected=submimo(xiaomi/submimo),subdeepseek(deepseek/subdeepseek-agent),subcursor(xai/subcursor)
# escalation=none
# snapshot=head:a95cee4
# 日志:/root/aiwork/logs/panel-model-selection-resume-r1-20260921.*.log
submimo=PASS(verdict=UNKNOWN) subdeepseek=FAIL(rc=1,降级:回落聊天腿也没成) subglm=off subkimi=off subgemini=off subgrok=off subcursor=PASS(verdict=PASS)
```
