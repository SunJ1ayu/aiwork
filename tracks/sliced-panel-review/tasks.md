# Tasks: sliced-panel-review

- base-ref: eaaea756960dd48835af39eb87cec4779d2c9d39

> 主 agent 自己实现(adapter=main)。判据先写、先红检、单独 commit,再写实现。
> 工作区里 GPT 另两件未提交的活(Grok/Kimi)已 stash 到 `stash@{0}` 与分支
> `backup/gpt-grok-kimi-20260913`,归档后放回并重跑总闸 —— 这是本单收口的最后一步,不许漏。

## 判据(先行)

- [x] O1 `tests/test-panel-slice.sh`:S1 N+1 次调用/家族互异/plan+reserved 先落盘/任务书隔离/契约 2/零 observation/游标不动
- [x] O2 同上:S3/S4/S5/S13/S14/S16 各类派发前拒绝且零调用
- [x] O3 同上:S6/S7 retry 占 extra、超额整批拒绝、旧 BLOCK 不被新 PASS 抹掉
- [x] O4 同上:S8/S9/S10 verify 家族排除、all-or-nothing、源码变了拒绝、decide 追加式、未登记 BLOCK
- [x] O5 同上:S11 控制器被砍 ⇒ unknown 不是 failed,腿跑完后重建;S12 scoped 不回落聊天腿
- [x] O6 同上:S15 panel-review scoped 开关的拒绝规则与角色腿不进普通池/花名册
- [x] O7 `tests/test-subcodex.sh`:argv/单源模型/只读源仓/无裁决/额度/fix 拒绝/超时
- [x] O8 `tests/test_review_result.py`:emit 契约 2 ⇒ ineligible(review_contract_unsupported),默认仍是 1
- [x] O9 判据对 base 红检(红在断言上),收据落 evidence,判据单独 commit(`74f39d5`)
- [x] O10 V2 真跑证伪 `--disable multi_agent` 后补 subcodex C5(目录覆盖/离线核验/联网关闭),对第一版实现红 5 条,单独 commit(`60480ee`)

## 实现

- [x] I1 `_review_result.py`:`emit --review-contract-version`,`SCOPED_REVIEW_CONTRACT_VERSION`,subcodex 身份
- [x] I2 `_panel-roster-lib.sh`:`PANEL_ROLE_LEG_SPECS` + `PANEL_ROLE_LEGS_ORDER`,取值函数查两张表,花名册印 plan 里出现的角色腿
- [x] I3 `panel-review`:`--scoped-review` / `--pin-leg`,契约版本透传进 session_run,scoped 不推游标、不回落、拒 --track
- [x] I4 `bin/_panel_slice.py`:清单校验/冻结/分配/预算占用/findings 账/status
- [x] I5 `bin/panel-slice`:run/verify/retry/decide/status,探针、并发上限、setsid、controller.exit
- [x] I6 `bin/subcodex` + `bin/codex-model`
- [x] I7 注册:`rust-check-review-tooling` SUITES;文档 panel SKILL.md / legs.md / README;`sync-workflow-docs`
- [ ] I8 `tests/mutation-panel-slice.sh` 变异红检

## 验证与收口

- [ ] V1 新判据 + 全量总闸 `rust-check-review-tooling` 用 runlog 留收据
- [x] V2 真跑:codex 额度恢复后 subcodex 最小 review 一次(读 --json 事件核实工具面/子 agent 关闭)
  —— 09-13 23:19 第一版**不合格**(子 agent 工具 + web__run 都在);修后两次真跑归因各开关,见 verify.md
- [x] V3 真跑:小切片评审(≥2 片 + overall)一次,核对调用数、终态、预算、status
  —— 09-14 00:15 xiaomi/deepseek/openai 各 1 次 + 换家族复核 1 次 = 4 会话,全部对账;见 verify.md
- [ ] V4 主 agent 自审落盘(仓外 my-review)→ panel-review high 预算评审 → 主裁
- [ ] V5 归档
- [ ] V6 `git stash pop` 放回 GPT 的 Grok/Kimi 改动,解冲突(只合并,不改它的内容),`sync-workflow-docs --force`,重跑总闸
