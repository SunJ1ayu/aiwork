# Tasks: mimo-key-single-source

- base-ref: b5de25fcfc4af2d922aa129f017bb60d2d74aa5e

> 全程主 agent 自己做(execution_plan.adapter=main),没有外部执行腿 ——
> 这单碰的是全机凭证与仓外配置,不是能派出去的窄范围实现。

## 第一轮(09-01 上午)
- [x] 查清 key 到底抄在几处(9 处;手工换漏 3 处,其中 canonical home 会重播回隔离树)
- [x] 顺带查出第 10 处:GitHub-Watch cron 提示词内嵌 `LLM_API_KEY=***` ⇒ 静默 401
- [x] 判据先行(`7b69dc1`,此刻 1 红)→ 实现(`be0683c`)
- [x] 能删的删掉(`~/.bashrc` 那行、cron 提示词整段 env 前缀)
- [x] 不能删的收到一个源头 + 一个工具 + 一份共享清单
- [x] 变异 11 条(9 咬 + 2 对照)

## 第二轮(09-01 中午,断线之后接上)
- [x] 读断线现场:panel 被砍,零 coverage-eligible 腿(subglm 失败、subkimi 被 Terminated)
- [x] **补做主 agent 自审**(上一轮是 `--panel-dispatch` 裸派的,自审文件当时不存在)
- [x] 捞 subkimi 那 94KB 半截日志当证据(不当预算)
- [x] 自审抓到的四处 → 判据先行(`9887599`,3 红)→ 实现(`49d6827`)
- [x] 重派 panel:subkimi(moonshot)+ subgemini(google),**两条腿都 PASS、complete、不降级**

## 第三轮(09-01 下午,消化 panel 发现)
- [x] ②b 占位符绿 + `switch-model.sh` 非原子写(判据 `e8ef431` → 实现 `51354f1`)
- [x] ④c 端点字段无人守(key 对了但被送错地方 = 同一种 silent-401)
- [x] 目录 fsync / 网关等不到就死 / 隔离树刷新不吞失败 / 冒烟任务先问在不在
- [x] **GitHub-Watch 的 AI 摘要端到端跑通**(`env -i` 模拟 cron 环境,拿到真中文摘要)

## 第四轮(09-01 下午,断线接手复核)
- [x] 接手第一动作:查最终收据的**时间戳**而不是看绿不绿 —— 三份完整、都在最后一次代码提交之后
- [x] 逐条重核断线前打的勾(两条腿 typed 结果 / `watch.py:37-51` / 对照组 9 绿 4 红 / 工件无字面 key)
- [x] 改掉一处**我写得比事实好看**的数字(过程收据 9/0 被写成 13/0)
- [x] 🔴 发现 H:本单交付的那道闸是孤儿脚本,归档后没人叫得动 ⇒ 搬进 `tests/` + 登记 SUITES
- [x] 🔴 发现 H2:真跑整套周跑才抓到它**一直带着网在判卷** ⇒ 补 no-egress 守卫
- [x] 四份最终收据重跑(29/19/13 + 整套周跑 22 个套件全绿),全 `source-stable: yes`
- [x] 记一笔不属于本单的账:评审腿 `failure_kind` 误判(根因已量到正则那一行,见 verify.md 末条)

## 明确不做(理由在 verify.md 的 Accepted deviations)
- 不扫历史备份/会话记录里的旧 key(死 key,是历史证据)
- 不在判卷面验 key 有效性(判卷面不许有外网出口)
- 不把 `bin/rotate-mimo-key` 塞进 `_tooling-paths.sh`(它是运维脚本,那份名单刻意不收运维脚本)
