# Agent Instructions

本文件是 aiwork 源码 `workflow/CLAUDE.md` 的部署副本。工具位于源码的 `bin/`，可加入 PATH。
工作流 skill 的源码位于 `workflow/skills/`；`bin/sync-workflow-docs --check` 检查部署漂移。

## 规则入口

评审与修复规则：[aiwork main 的 REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md)。
项目已接受风险见项目 main 的 `.aiwork/accepted-risks.md`；正式评审与合并条件见项目关卡策略。
需要判断时读取这些来源，说明文件只提供入口。
记录待办或业主决定前，必读 REVIEW-RULES 第二节第 1 条「待办与业主决定」。

## 一个任务的走法

所有项目都不得放任何密钥和私人信息。密钥只保存在项目外的本机设置目录（aiwork 使用 `~/.config/aiwork/`），项目通过统一入口读取。推送前由 `privacy-check` 兜底，不许用 `--no-verify` 绕过；误报就改本机私人词表或测试夹具。

1. 从最新 main 拉分支。开工先在本机数据目录建自己的工作树，在里面拉分支干活，不在共享检出（如 /root/aiwork）里直接改。路径用 `aiwork-config data-path worktrees` 取。PR 合并后删掉这个工作树。
   标签派活的任务，开工后先用构建机器人推一次分支（可以为空提交或说明草稿）；宿主接线和占位规则见 [Mac 运行手册](https://github.com/SunJ1ayu/aiwork/blob/main/docs/mac-host.md)。
2. 改代码时，先写先红的测试，再实现（怎么算见 REVIEW-RULES 第一节第 3 条第 1 步）。
3. 全跑项目 `tests/`，核对结果及已明确允许的例外。
4. 提交后按下文「机器人推送与开 PR」操作，然后停下。
5. PR 开好、CI 绿了以后，用 `review-pr` 派评审腿。
   `review-pr` 必须在沙箱外运行；使用目标仓库当前 PR head 和 main 的规则来源。
   `review-pr` 从共享检出跑，跑之前先把共享检出更新到最新 main。
   派评审使用 `review-pr --auto --builder-family 本次执行方家族`；分档、顺序和目标见项目 main 的 `.aiwork/policy.json`，工具用法见 README「Review commands」。
   各腿出结果后，由汇总处理（见 `summary` skill）。
6. 修改方怎么修，见 REVIEW-RULES 开头的「一轮」。
   合并由项目关卡或业主完成。合并后用 `sync-workflow-docs` 同步部署出去的工作流文档。

## 评审发布失败后重发

发布失败（包括发布前换令牌失败）时，使用 `review-pr` 失败提示给出的完整命令：

```bash
review-pr PR --repo owner/name --leg LEG --retry-publish RUN_ID
```

`RUN_ID` 是本机数据目录 `review-failures/` 下该次失败的目录名。重发仍从最新 main 的共享检出运行，
只发布保存的正文，不重新调用模型。它会核对发布记录绑定的正文摘要、腿、head 和目标，
照常检查隐私和 PR 当前 head；不满足就拒绝并说明原因。去重只认项目 main 策略登记的评审机器人
已经发出的同一份正文，只用于恢复保存正文的发布。新一次模型评审照常发布，即使同腿、同 head
的新结论文本恰好相同。重发查到保存正文已发布时直接返回原链接、退出 0，拒绝再次 POST。
缺少发布记录的旧档案不能重发。执行方不许拿评审机器人的令牌或私钥手工补发，取令牌由 `review-pr` 自己完成。
这些记录防止发错文件、发错 head 和正文意外损坏；同账号故意篡改的隔离边界见 #127。

## 机器人推送与开 PR

执行方推送和开 PR 只用构建机器人身份，令牌只从仓库的 `bin/gh-app-token` 换，不用个人账号。
防的是 PR #44 首次推送把令牌放进命令行参数，进程列表能看到；来历见 [#43](https://github.com/SunJ1ayu/aiwork/issues/43)。

新机器先按 README「本机设置」安装 App 配置和程序，确认 `gh-app-token` 在 PATH 中。在目标仓库的共享检出执行下面的配置（工作树继承它），示例目标是 aiwork；其他仓库须替换远端及助手内的 `--repo`，并核对角色配置允许该仓库。只配置本仓库，不修改全局凭证设置。

```bash
git remote get-url origin
git config --local --replace-all credential.https://github.com.helper ''
git config --local --add credential.https://github.com.helper \
  '!f() { test "$1" = get || exit 0; token=$(gh-app-token build --repo SunJ1ayu/aiwork) || exit; test -n "$token" || exit 1; printf "username=x-access-token\npassword=%s\n" "$token"; }; f'
git config --show-origin --get-all credential.https://github.com.helper
gh-app-token build --repo SunJ1ayu/aiwork --grant
```

远端须为目标仓库的 `https://github.com/owner/repo.git`。此助手仅在本仓库通过 HTTPS 访问 `github.com` 时生效，不用于 SSH 或其他主机；空项清除继承的助手列表，后面的助手只处理 Git 的 `get` 请求，不存储令牌。换取失败或空值会拒绝返回凭证。令牌经助手标准输出交给 Git，不经过参数。不要直接运行并打印 `git credential fill`；上面的 `--grant` 只显示实际授权范围，不证明推送身份。助手缺失、身份或目标仓库不对时，停下报告，不临时拼认证参数或改用个人登录。

下面在自己的工作树里运行，以 aiwork 为例；替换标题，并在提示时把本次 PR 说明输入到文件（输入结束按 Ctrl-D）。`mktemp` 为每次运行分配独立文件，避免并行覆盖。

```bash
(
  set +x
  umask 077
  pr_body=$(mktemp "${TMPDIR:-/tmp}/aiwork-pr-body.XXXXXX") || exit
  trap 'rm -f "$pr_body"' EXIT
  cat > "$pr_body" || exit
  export GIT_TERMINAL_PROMPT=0
  git push --set-upstream origin HEAD || exit
  GH_TOKEN="$(gh-app-token build --repo SunJ1ayu/aiwork)" || exit
  test -n "$GH_TOKEN" || exit 1
  export GH_TOKEN
  gh pr create --repo SunJ1ayu/aiwork --base main \
    --title '本次改动的标题' --body-file "$pr_body"
)
```

开 PR 的令牌只在这个子 shell 的环境中交给 `gh`；换取失败或返回空值就退出，不能回退到 `gh` 已登录的个人账号。令牌不放进 URL、认证头选项或助手配置的字符串，也不打印环境、开启认证调试或把令牌写进日志、提交和 PR 说明；示例先关闭 shell 跟踪，避免展开的值进入日志。

验证推送时，用 `git ls-remote origin refs/heads/分支名` 的结果对照本地 `git rev-parse HEAD`；开 PR 后核对远端 PR 的 head 和作者是本次提交、构建机器人。记录分支、提交号、PR 链接和验证结果，不记录令牌。同时核对该提交的 GitHub 推送事件中 `actor.login` 是项目构建机器人（不是提交作者）；PR 作者也必须是同一个机器人。身份与助手的实际行为需要真推送核实，文档扫描不能证明它们。

## 做事的方法

- 判据红了，先用具体输入复现，确认是实现问题还是测试题面的问题；不改考卷让自己及格。
- 自己写的判据也可能错；检查它能否区分正确和错误行为，必要时对旧实现或基线做对照。
- 收货不信执行腿的自述：看真实 diff 和未跟踪文件，自己跑检查，再读实际改动。
- 派 PR 任务的规则和格式见 `delegate` skill。
- 一轮评审出完结果后，用 `summary` skill 汇总。
- 部署验证看运行中的目标是否加载了预期版本；源码更新、部署副本和运行状态分别核对。
- 「全仓搜一遍」这类一次性的检查，用命令做完，不写成手抄清单的永久测试；PR 说明要求见 REVIEW-RULES 第一节「PR 说明」；要长期钉住的，见 REVIEW-RULES 第一节「同类一起扫」。
- 外部工具的输出格式（比如各家 CLI 的 stream-json），测试样本从真实输出里截一段，不凭文档手写。
- 注释只写现在为什么这样，也就是这段代码防的是哪种真出过的问题；日期、第几轮评审、谁实测过，写进提交说明；PR 说明要求见 REVIEW-RULES 第一节「PR 说明」。

## 本机设置与数据

本机设置位于 `~/.config/aiwork/`，包含 `models.env`、GitHub App 角色配置及私钥。
本机数据目录入口见 README「本机设置」，里面有哪些东西见 aiwork 仓库 bin/_aiwork_config.py 的登记表。
统一入口是 `bin/aiwork-config`；评审运行目录见 README「评审运行目录」。

可用通道包括 Codex、Cursor、DeepSeek、Kimi、MiMo。每个通道都能写代码也能评审；同一个 PR 的评审要换一家，由关卡判断。默认模型读取本机设置。
`review-pr` 的运行前提包括 node（CI 选择器使用），以及所选腿的程序路径和 Python 版本；配置与预检方法见 README「本机设置」。
正式评审入口和用法见 README「Review commands」中的 `review-pr`。
