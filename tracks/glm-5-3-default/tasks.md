# Tasks: glm-5-3-default

- base-ref: 072067d2d4b16a7c2bb72ec6a288973093daa130

> 委托 submimo fix 时:主 agent 先写失败测试(oracle)并 commit,再把窄范围实现
> 交给它;oracle/测试文件对它 off-limits;~2 次红了收回主 agent。

- [x] 把 agent/chat 默认模型断言改为 5.3，保存修复前红收据并单独 commit
- [ ] 切换 `subagent` 与 `subchat` 默认值，保留 override
- [ ] 跑全量工具回归与真实 `subglm-agent` 5.3 冒烟
- [ ] fast review、主裁、归档
