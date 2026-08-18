# Tasks: opencode-go-leg

- base-ref: da5d244

- [x] 探针:OpenCode Go 有没有 Anthropic 兼容口(有:`/zen/go/v1/messages`,只认 x-api-key)
- [x] 调研:GLM 有没有官方底座(没有;官方路子就是 Claude Code 换端点)
- [x] 判据先行:V8/V9/V13 随规格翻新 + 新增 V26,红检(13 红,deepseek 基线绿)
- [ ] 实现:`subagent` 供应商表 zhipu 一格 + `AUTH_ENV` 表驱动
- [ ] 实现:`subchat` 供应商表 zhipu 一格
- [ ] 实现:`panel-review` GLM 腿默认开回来
- [ ] key 落位 `~/.config/opencode-go/auth.json`(600)
- [ ] 文档:panel skill `references/legs.md` 第三条腿改写
- [ ] 判据转绿(全量总跑)
- [ ] **真跑冒烟**:subglm-agent 打真端点评一份真 diff,拿到裁决行(stub 证不了这件事)
- [ ] 收尾:卸掉误装的 opencode CLI、归档
