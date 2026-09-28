# 设计

- subcursor 沿用 subgrok 的调用形状、review workspace、ro-repo-exec、自审闸与 facts 输出。
- 模型只读 bin/cursor-model；调度器冻结当次 CURSOR_MODEL，家族由共享结果模块按模型前缀识别。拒绝 auto/无法识别家族的配置。
- Cursor 可切换 Composer、Claude、GPT、Gemini、Grok 等家族；预算轮换与追加腿避开已选家族，--all 仍派所有启用通道。
- 在独立空 workspace 启动，把原样快照作为 add-dir 提供，防止自动执行待审仓库启动配置。只开 read/grep/glob/ls，ask 模式，不提供 shell/MCP/子 agent 工具。
- 每轮独立 PID namespace，CLI 退出或超时即结束其所有后台 worker/语言服务，再清理临时目录；不按进程名全局杀进程。
- 每轮独立 HOME/config/data。Linux 默认 ~/.config/cursor/auth.json，只读取 accessToken，经 CLI 的 CURSOR_AUTH_TOKEN 注入，不复制 refreshToken/API key；明确设置 CURSOR_API_KEY 时使用该认证方式。访问令牌过期须由正常 CLI 登录刷新。
- 只读工具不能执行 git diff，启动前把 snapshot tree 相对 HEAD（或 PANEL_DIFF_BASE 的 merge-base）的 diff 放在运行目录里供读取，包含未跟踪文件，快照本身不变。
- 请求/调用模型 ID 沿用共享结果契约，以实际传入 CLI 的 --model 为证。init 只回显人类可读名称，且与 models 目录显示名也可能不同；按名称检查模型家族并保留原始名称，reported_model 留空，不伪造精确 ID，也不维护别名表。
- stream-json 只抽取顶层 assistant 文本，拒绝缺终止事件、错误、截断、会话串线或模型家族不符。临时工作目录及副本通过 --trust 解除无人值守启动确认；不使用 --force/--yolo，工具白名单保持只读。
- 原始流与 summary 留在日志目录；usage 不伪造，原流有多少记多少。现有 typed usage 槽仍允许 unknown。

## 验证

离线套件使用假 CLI 和真实快照/只读挂载：脏仓读取、原仓不可写、独立 home 并发、凭证副本清理、模型切换、裁决/发散格式、错误/超时/空产出拒绝、两个调度入口、家族预算去重。
既有 review-result / panel-roster / panel-observation / panel-slice / review-tooling 回归。
真实评审和发散需 Cursor 登录后各一次小任务；未登录不能以离线桩声称供应商可用。

## 已知边界

Cursor 隐藏的 allowed-tools/disable-project-configs 参数已在本机 2026.09.15-d2fe57e CLI 真调用验证；工具名使用 snake_case。exclude-workspace-context 被服务端明确拒绝，已移除；不承诺排除所有仓库规则上下文。升级后须实测。
原仓只读挂载不隔绝全机读取（与现有腿同一边界）；账户级 team hooks 仍由 Cursor 服务端策略控制，不能宣称整个 CLI 无任何外部启动行为。
family 是现有供应商/模型系标识，不代表统计独立或没有共享训练底座；Composer 与 Kimi 的共同来源不因两个标签而消失。

## 复核预算

先主自审，至多一轮外部评审加一次必要修复复审；基础设施重试单列，不无限续单。
