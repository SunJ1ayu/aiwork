# Tasks: opencode-agent-base

- base-ref: 114ff448c35e7640638f2470ef2e12dec9ed5cc9

> 委托 submimo fix 时:主 agent 先写失败测试(oracle)并 commit,再把窄范围实现
> 交给它;oracle/测试文件对它 off-limits;~2 次红了收回主 agent。

- [ ] <task 1>
- [ ] <task 2>

## 做完了什么(2026-08-18)

- [x] 探针四件全过(无界面跑 / 只读锁 / 裁决行 / 配置隔离)
- [x] 判据先行 V28,红检 7 红
- [x] 实现:供应商表加 `AGENT_BASE` 一维,GLM 走 opencode CLI
- [x] 判据搬家:V9 → deepseek;V17/V21/V26 里问 GLM 的部分改去 opencode 配置里问
- [x] 兜底桩:判据绝不许碰真 opencode(修的是形状,不是那 9 个调用点)
- [x] 删掉判据顶部那行全局 export(三次瞎断言的根因)
- [x] 真跑:它自己 Read/Glob/git 抓到埋的雷,拿到裁决行
- [x] full 四审 → subdeepseek BLOCK(只读锁不成立)→ 修复 → 主裁 PASS
- [x] **bash 整个关掉**(命令行白名单挡不住 git 自己的参数,两条攻击路径我都复现过)
- [x] 文档:panel skill `references/legs.md` 第三条腿重写
- [x] 最终 339/0(最后一次编辑之后)+ 真跑 rc=0

## 欠的账(下一单)

- [ ] **DeepSeek 腿很可能有同一个洞**(`Bash(git diff:*)` 白名单)—— 没验没修,应立刻起单
