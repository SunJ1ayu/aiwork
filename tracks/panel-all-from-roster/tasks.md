# Tasks: panel-all-from-roster

- base-ref: d5f40583d99d7e4e005b0cda74386c1a20899ed2

> 委托 submimo fix 时:主 agent 先写失败测试(oracle)并 commit,再把窄范围实现
> 交给它;oracle/测试文件对它 off-limits;~2 次红了收回主 agent。

- [x] 写出由花名册派生的全池派发、帮助与 observation 红判据，并单独提交。
- [x] 实现动态 `--all` 和动态帮助，移除 observation 数字上限。
- [x] 更新现行说明，保留历史叙事中的实际数字。
- [ ] 跑相关套件与完整 tooling runner，记录主裁。
