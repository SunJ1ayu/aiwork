# Tasks: grok-leg-kimi-model

- base-ref: e49f69586ad6edd73021b30c0ad205ba34c65827

> 委托 submimo fix 时:主 agent 先写失败测试(oracle)并 commit,再把窄范围实现
> 交给它;oracle/测试文件对它 off-limits;~2 次红了收回主 agent。

- [x] T1 判据单独提交:GPT 的测试改动 + `test_subgrok.py` + 套件注册 + 花名册金样
- [x] T2 实现提交:GPT 的 subgrok/解码器/模型文件/subkimi/模板/花名册/explore/文档,内容不改
- [x] T3 redcheck 两次:Grok 实现退回、Kimi 实现退回,各自红在该红的地方
- [x] T4 手工变异:模型身份校验、子代理与工具文本不算裁决、超时映射
- [x] T5 文档如实写明两处局限(K2 能力声明写死、G1 凭证副本不回写)
- [x] T6 全量回归 `rust-check-review-tooling`,`runlog --final` 留收据
- [x] T7 派外审前预跑 `track archive`,把能提前暴露的归档闸先撞掉
- [ ] T8 high 外审(Grok 未登录 ⇒ `PANEL_GROK_LEG=off`)+ 主裁
- [x] V1 Kimi 运行时核实:真跑 subkimi 后读服务端 `/models`,默认模型的名字与上下文对得上
