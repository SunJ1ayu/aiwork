# 独立方案探索: aiwork 如何在实现之前发现错误方案

用户要求修改 aiwork 工作流,遵循第一性原理。目标是降低「方案错了,整轮实现/测试/外审都在证明错误规格」的代价,同时保持小修改轻量。

事实:
- OpenDesign 启动更新方案写了等待网络、最长35秒中断;用户需求很明确,被判 design-uncertainty=low,实现评审两家通过,用户实际启动被挡才揭示方案问题。
- 曾加「low 也必须有理由文件」机器闸,新6条测试绿却破坏旧契约,补丁已撤回;那种文件存在性也证明不了理由正确。
- Jev 对92个历史proposal做过三轮分类;题目/组合调整导致报警增多或漏掉已知坏方案,没有完整事实标签。不能让其低分降审查强度。
- 切片有局部独有发现,也漏了片外受影响的老测试脚本;独立整体腿有价值但不是万无一失。scoped结果不计现有归档资格。

请从原始目标独立提出一个最小、可落地的方向,指出其关键假设/代价以及怎样在实施前证伪。尤其检查怎样触发独立思考而不依赖「我觉得方向确定」,怎样区分小改动与值得花多模型的任务,现有工具是否足够。无需迎合任何既有方案,不要输出PASS/BLOCK。

可读上下文: workflow/CLAUDE.md、workflow/skills/{track,panel,delegate}/SKILL.md、track/templates/{proposal,design}.md、track/CONVENTION.md、bin/triage、bin/track-record 的 validate_dispatch、bin/panel-explore 的 help、tracks/design-uncertainty-low-needs-reason/verify.md。
不要读取 tracks/design-before-build/、其他评审输出或本轮主 agent 的方向记录。不要派子agent、运行测试、改文件、联网或调用其它模型。输出是建议,不替主 agent 拍板。控制篇幅,最多约1000中文词。
