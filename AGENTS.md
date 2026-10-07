评审、修改 PR 前先读 [REVIEW-RULES.md](REVIEW-RULES.md) 和项目的 `.aiwork/accepted-risks.md`。

完整工作流见 [workflow/CLAUDE.md](workflow/CLAUDE.md)。

本仓库公开：不许提交任何私人内容（密钥、项目名/客户名、配置、日志）；本机工作资料放在 `.gitignore` 挡住的目录里。

开发分支从最新 main 拉，开 PR 前先同步 main。

推送和开 PR 只用机器人身份，令牌只从 `bin/gh-app-token` 换，不用任何个人账号。
