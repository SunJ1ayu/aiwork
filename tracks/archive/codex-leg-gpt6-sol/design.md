# Design: codex-leg-gpt6-sol

模型单源 `bin/codex-model`,subcodex / 派活都从这里读。前提核验(实跑):
- `codex exec -m gpt-6-sol` 回显 `model: gpt-6-sol`;编造的模型名服务端 400 ⇒ 不是静默回落。
- `codex debug models` 实时目录里 gpt-6-sol 恰好一次、声明 multi_agent_version=v2 ⇒ subcodex 现有的「剥目录去子 agent」机制照样适用(与 astra 同形)。
