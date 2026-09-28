# Design: codex-exec-leg-gpt6-sol

- 做法:参数解析后,`MODEL` 为空 ⇒ 读 `$BIN_DIR/codex-model`,校验恰好一个 `gpt-<id>`(与 subcodex 同一写法);读不到 / 形状不对就 die,不静默回落。
- 前提:gpt-6-sol 在 codex CLI 实时目录里(`codex debug models` 本次重查仍在);09-23 subcodex 冒烟已真调用成功。
  09-23 发现它声明 multi_agent_version=v2(会自己派子助手),subcodex 为评审剥掉;干活腿不剥 —— 收货三道闸查的是最终改动,子助手在同一沙箱、同样断网。
- 判据:三套老测试 test-delegate-entry / isolate / observation 全过;冒烟空跑 `smoke.sh`(不给 --model ⇒ model=gpt-6-sol;给 --model ⇒ 覆盖)。
