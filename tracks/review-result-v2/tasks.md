# Tasks: review-result-v2

- base-ref: 23fed8cd2c7980e92bc7a83d84285594aa41bfa5

> 委托 submimo fix 时:主 agent 先写失败测试(oracle)并 commit,再把窄范围实现
> 交给它;oracle/测试文件对它 off-limits;~2 次红了收回主 agent。

- [x] C1–C3：v2 kernel、v1/v2 reader、唯一 normalizer。
- [x] C4–C5：subject/evidence、shadow terminal result。
- [x] C6–C9：迁移 MiMo、DeepSeek/GLM、Kimi、Gemini。
- [x] C10：原子迁移 timeout 与 health。
- [x] C11–C12：v2 writer 与所有 coverage consumers cutover。
- [ ] C13：删除重复旧语义，完整回归并归档。
