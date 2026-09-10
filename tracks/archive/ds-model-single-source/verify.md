# 验证：DS 默认模型单一来源

已核对：agent 与 chat 都读取 `bin/deepseek-model`；当前值为 `deepseek-flash`。
两条实际入口的 `--help` 均回显该名称，当前会话没有非空 `DEEPSEEK_MODEL` 覆盖。

V8 把夹具配置改成虚构模型名，检查 chat 实际传给引擎的名称与帮助信息跟随，
并检查显式覆盖仍然优先。V36 同样改夹具配置，检查 agent 子进程接到的名称、
运行事实记录及帮助信息一致。V9 继续验证显式覆盖，并增加所有模型槽位的核对。
样例账本保留原有模型名，不把历史事实当成当前默认配置。

全量离线回归通过：review-tooling 553/0，review-workspace 31/0，workflow-docs 37/0，
总跑的其余套件全部通过。`git diff --check`、shell 语法检查及部署文档同步检查通过。
本轮未调用真实供应商；传参由离线桩验证，线上可用性不由这份回归收据证明。

- `runlog: full-regression rc=0 commit=99a3146 dirty=yes final=yes at=2026-09-10T11:44:16Z file=tracks/ds-model-single-source/evidence/20260910T114416Z-01-full-regression.txt`

收据如实标记 dirty=yes：包含本次尚未提交的实现与此前遗留的另一条 track 的工件。
这轮测试期间没有继续编辑工作树；最终运行记录的前后源视图稳定。

此前仅替换名称的版本已完成全量离线回归（review-tooling 549/0），
它不作为本次单一配置重构的最终证据。
