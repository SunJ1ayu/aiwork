# Design: legs-quick-fixes

- Change: legs-quick-fixes
- Status: draft

- 规划双出: 不适用:五处点状修复,方向由出处直接决定,不开新写口语义。

## Approach

- A1 `bin/subagent` REVIEW_PROMPT 在任务书之后再写一遍契约;`bin/submimo` review MESSAGE 补上契约(原来一个字没有)。
- A2 `bin/_review_result.py`:「usage limit / quota will reset」这类**会自己恢复的窗口限额**归 `rate_limit`,并排在 auth 之前判;
  `bin/subkimi` 在 kimi 非零退出时把日志里 CLI 自己的 `error: failed to run prompt:` 行抄到 stderr(诊断),不扫模型正文。
- A3 `bin/panel-review` record_health:`rate_limit` 失败照样冷却,但不增加连败计数;余额类 `quota`、`auth`、runtime 照旧计数(要人管)。
- A4 `bin/subagent` 渲染 opencode 配置加 `experimental.continue_loop_on_deny = true`。
- A5 `bin/subchat` 只对 zhipu(OpenCode Go)让引擎带会话头;`bin/submimo-review` 每次运行生成一个 id,重试沿用同一个。

- A6(第二轮外审后加入)`bin/_review_result.py` 裁决值认独占一行的中文词,括号英文须一致 —— proposal 里「不先放宽解析器」的前提被 09-14 GLM 真评审证伪(A1 重申契约后仍写 `结论：通过`)。

## Key trade-offs / risks

- A3 把「额度窗口」和「余额耗尽」分开:余额耗尽要人充值,仍应停轮换;窗口限额 5 小时自愈,不该停。
  风险:某供应商把余额耗尽也写成 "usage limit" ⇒ 腿永远不停轮换、每次冷却后再失败一次(回到 08-25 前的行为,有备用腿兜底)。
- A4 被拒后继续 = 模型可能反复撞同一个被拒工具直到步数上限(steps=40)—— 有上限,且比「整轮作废」好。

## Test strategy (oracle)

`tests/test_leg_quick_fixes.py`(主 agent 亲写),十条:七条目标 + 三条对照(余额=quota、坏 key=auth、runtime 仍计数、DeepSeek 聊天腿不带头)。
红检:判据先提交,在旧实现上跑必须红在七条目标上、对照组全绿。

**这个 oracle 能被什么骗过?**

- A1 只查「契约字符串在任务书之后出现」,不查模型真的照做 —— 真跑 GLM/Kimi 冒烟接得住一部分,漂移是概率事件。
- A4 只查配置里有开关,不查 opencode 真的继续 —— 需要一次真跑让它碰仓外路径。
- A5 只对本地假端点验头,不证明 OpenCode Go 接受 —— 回落腿真跑一次接得住。
