# aiwork

Multi-model implementation and PR review tooling.

评审与修复规则见 [REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md)，项目已接受风险见项目 main 的
`.aiwork/accepted-risks.md`，正式评审与合并条件见项目关卡策略。
任务的操作步骤见 [workflow/CLAUDE.md](workflow/CLAUDE.md)；工具用法在 `workflow/skills/`。
`~/CLAUDE.md` 和 `~/.claude/skills/delegate` 是由 `bin/sync-workflow-docs` 管理的部署副本。

GitHub `main` 是 aiwork 的源码准本。改动使用机器人分支和 PR；本机资料的存放位置见[「本机设置」](#本机设置)。

## History

旧记录在 git 历史里。

## What lives elsewhere

- quicklook lives at `/root/quicklook`; its systemd unit and run-output path
  point there.
- The current wiki-ingest skill lives in the OpenClaw workspace at
  `/root/.openclaw/workspace/skills/wiki-ingest`; the older aiwork copy was
  removed.
- Local working files stay in the machine data directory outside this checkout.
  里面有哪些东西见 `bin/_aiwork_config.py` 的登记表。This repository is
  public: never commit private content.

## Layout

- `bin/` review commands (below)
- 本机数据目录(不在这个仓库里):里面有哪些东西见 `bin/_aiwork_config.py` 的登记表
- `gate/` shared merge gate. A project connects by the steps in [gate/README.md](gate/README.md)
- `templates/` starter task file (`review-task.md`) and the two gate workflow templates
- `tests/` regression oracles for this tooling itself
- `workflow/` canonical Claude instructions and workflow skills (deployed copies live outside Git)
- `kimi-review-home/config.toml` and `hooks/guard.mjs` are versioned seeds; reviewer runtime homes use disposable review workspaces

## Review commands

每个通道都能写代码也能评审。写代码在自己的工作树里打开那家的命令行。
仓库里的这些命令服务 `review-pr`。同一个 PR 要换一家评审，由关卡判断。

- `bin/subdeepseek-agent` — DeepSeek，经 Claude Code headless 读仓库。模型来自 `~/.config/aiwork/models.env` 的 deepseek 行。
- `bin/subkimi` — Kimi，kimi-code CLI。review、explore 仅有 Read/ReadMediaFile/Glob/Grep，CLI 的 agent profile 关闭命令和写工具，hook 再拒一次；任务复制进快照，由 Read 读取，正文不进命令行参数。模型来自 kimi 行。
- `bin/submimo <review|explore>` — MiMo，官方 `mimo` CLI。review、explore 仅有 read/glob/grep，CLI 配置关闭 bash 并拒绝 bash 权限。模型来自 mimo 行。
- `bin/subcursor <review|explore>` — Cursor CLI。模型来自 cursor 行，或用 `CURSOR_MODEL` 覆盖一次。家族跟着模型走，不跟着 Cursor 这个传输。用 `cursor-agent login` 登录。
- `bin/subcodex <review|explore>` — Codex CLI。模型来自 codex 行（`SUBCODEX_MODEL` 覆盖一次）。源仓经 `ro-repo-exec` 只读，副本可丢弃，`--ignore-user-config --ephemeral`，提示词走 stdin。派发前用 `codex debug prompt-input` 离线确认子 agent 工具已去掉；联网搜索关闭。
- `bin/review-pr PR [--repo owner/name] --leg LEG` — 评审一个 PR 的 head 并发布一条 aiwork-review COMMENT。`--repo` 默认是这个检出的 origin；origin 不是 GitHub `owner/name` 时显式传入。需要联网、需要读取本机模型凭证；被 agent 派去跑时必须在沙箱外运行。跑之前的前提见 `workflow/CLAUDE.md`。
  失败时打印脱敏后的 stderr 末 40 行，诊断留在数据目录 `review-failures/<run-id>/`，不含仓库检出和凭证助手。保留规矩见 `bin/_aiwork_config.py` 的 `DATA_ENTRIES`。旧的 `logs/review-pr-failures/` 不再写入，按 `logs` 的保留规矩清理。
  任务在 diff 之后再次要求结论。完整 diff（含删除）放得下就内联。超过 `READER_INLINE_DIFF_BYTES`（200KB）时，任务只列每个文件的状态和行数，完整 diff 在快照文件 `aiwork-review.diff`。
  这条命令默认给评审命令 2400 秒；已有的超时环境变量可以覆盖。只有缺结论或输出被截断时重试一次，并在终端和发布的评审里写明。每次失败的尝试都留下，包括重试成功的那次；其他失败不重新启动评审命令。

Kimi、MiMo 的快照内有 `aiwork-git-context.txt`，含可用的 Git 历史和状态；它们没有命令工具，不能运行或声称运行测试。

所有评审命令：`<tool> review TASK LOG REPO`。输出是主 agent 要核对的证据。

## Tests (run for tooling changes)

推送前启用仓内隐私钩子（在仓库根目录执行，每台机器设置一次）：

```bash
git config core.hooksPath .githooks
install -d -m 700 ~/.config/aiwork
touch ~/.config/aiwork/private-terms
chmod 600 ~/.config/aiwork/private-terms
# 自己编辑 private-terms，一行一个私人词；不要提交词表。
bin/privacy-check origin/main..HEAD
bin/privacy-check --all
bin/privacy-check --files kimi-review-home/config.toml kimi-review-home/hooks/guard.mjs
bin/privacy-check HEAD  # 当前分支可达的全部历史，含根提交
```

`aiwork-config path private-terms` 定位本机词表；词表缺失时检查失败，空表只检查密钥形状。
范围检查每个提交新增的行、新增文件路径、提交说明、作者和提交者的名字与邮箱；
`--all` 检查当前已跟踪和未忽略的工作树文件（包括路径）。钩子检查实际推送的提交，删除分支不检查。
新分支以本机已获取的远端 refs 排除已有历史；没有远端 refs 时检查全部历史。
命中只报 `文件:行号` 和类型，路径本身命中时隐藏路径；路径用 `:0`，提交元数据用 `commit/<SHA>/<字段>:行号`。
返回码 `0` 为干净，`1` 为命中，`2` 为检查失败。密钥形状只有 `bin/_secret-shapes` 一份定义，供日志脱敏和检查共用。
不许用 `--no-verify` 绕过；误报修改本机词表或在运行时拼接测试夹具。

```bash
bash bin/rust-check-review-tooling   # THE runner: every suite below, one summary line
bash bin/rust-check-review-tooling --coverage-only   # 只查没登记进总跑的孤儿套件
```

The runner is list-driven (`SUITES`) and hard-reds when a `tests/test-*` file is
NOT in that list — a judging suite nobody runs rots silently. Individual suites
still run standalone (`bash tests/test-subcodex.sh`); each one first reruns
itself with no egress — inside a network namespace on Linux, under the system
`sandbox-exec` on macOS — and refuses to run (78) if isolation cannot be verified.
The macOS guarantees and limitations are defined in one place:
[`tests/_no_egress.py`, “Mac 上出网的路”](tests/_no_egress.py).
Linux details: `tests/_no-egress.sh`. This guard prevents accidental paid calls
from tests (the 2026-08-10 incident), within the documented platform limits.

## MiMo agent CLI setup

```bash
npm install -g @mimo-ai/cli
mimo                      # or: mimo providers login / list
```

## 本机设置

仓库只保存工作流；本机设置统一放在 `~/.config/aiwork/`（目录权限 700）：

- `models.env`：Codex、Cursor、DeepSeek、Kimi、MiMo 的模型选择，每条一行。可参考 `templates/models.env.example`。
- `deepseek.env`：DeepSeek 使用的 `DEEPSEEK_API_KEY`，保留文件权限 600。
- `models.env`、`deepseek.env` 按同一规矩逐行读：空行和以 `#` 开头的行跳过，其余每一行必须是可选的 `export` 加 `名字=值`；值要么是一整段不含空白、引号和 `#` 的文字，要么被一对相同的引号整个包住且引号里同样不含空白、引号和 `#`；不符合的行、同一个名字出现两次、空值，或文件不是 UTF-8，都报错并带上文件路径和行号。
- `apps/*.env`：GitHub App 各角色的 App ID、安装 ID、目标仓库和权限配置。
  `KEY` 推荐只写文件名（如 `KEY=aiwork-sync.pem`）；相对路径在所选 `apps/` 下查找，绝对路径照原样使用。
- `apps/*.pem`：GitHub App 私钥，文件权限 600。

换机器时把整个目录复制过去并保持权限。`bin/aiwork-config` 是统一读取入口；
`AIWORK_CONFIG_DIR` 可指定其他设置目录，测试只指向临时目录。
`AIWORK_APPS_DIR` 仍可单独覆盖 App 配置目录。
`models.env` 必须完整，包含每条腿的模型行；原有模型单次覆盖参数只是在完整设置的基础上换一次，不能代替文件或补缺行。
缺少 `models.env` 或所需腿的模型行时明确报错并停止，不调用模型。
本机数据由 `bin/aiwork-config data-path [相对路径]` 统一定位，默认 `~/.local/share/aiwork/`；
`AIWORK_DATA_DIR` 可覆盖该入口（例如离线测试使用临时目录）。供应商隔离运行时会改写
`XDG_*`，因此 aiwork 数据入口不随供应商的 XDG 设置变化。查询路径本身不创建目录。
数据目录要先存在，aiwork 不会自动创建它。数据目录要放在外接盘里面的一个子目录，不要直接用盘的挂载点(盘没挂上时，挂载点往往还是一个空目录，检查会误判通过)。
数据目录的登记项和保留规矩见 `bin/_aiwork_config.py` 的 `DATA_ENTRIES`；产物单位和计龄说明见该文件中 `DATA_ENTRIES` 上方的注释及 `prune_data`。
`review-pr`（除 `--dry-run`）和 `explore` 在通过会让整次运行退出的检查之后、开始干活之前自动清理；清理某项失败时在 stderr 报出路径和原因，跳过后继续。也可手动运行 `bin/aiwork-config prune-data`，加 `--dry-run` 只列出候选路径、逻辑字节数和最后改动时间，不删除。输出的 `last_modified` 是文件系统提供的 Unix 秒数，使用数字而非日期字符串。

这些子目录都通过该数据入口定位，有哪些见登记表；已有的专用路径覆盖参数仍优先。源码、模板和共享组件相对实际工具位置查找，
`bin/` 应作为完整工具集部署；缺失共享组件时拒绝派发，不回落到其他机器的 checkout。

## 评审运行目录

`kimi-review-home/config.toml` 和 `hooks/guard.mjs` 是版本控制中的种子；`subkimi` 在运行期 home 渲染模型和 guard 命令占位符。
每次渲染配置和 guard，另写 CLI 的只读 agent profile；credentials 链接到 Kimi CLI 自己的凭证目录。缺少 `kimi-code.json` 时拒跑并提示先用 kimi 登录。
`submimo` 的临时 `XDG_CONFIG_HOME` 与评审副本一起删除，凭证仍由 MiMo 自己管理。
`KIMI_REVIEW_HOME`、`MIMO_REVIEW_HOME` 指定的目录由调用方管理：不渲染种子、不删除，仍经过 `review_home_guard`；Kimi 仍重写只读 agent profile，MiMo 仍重写隔离评审配置。

### 加新评审腿的规矩

- 运行目录在 `review_workspace_prepare` 之后调用 `_review-workspace.sh` 的 `review_workspace_home <名字>` 创建（权限 700），由现有 workspace 清理一起删除。
- 登录凭证只用各家 CLI 自己的位置，不复制凭证。
- CLI 自己的会话记录能关就关。
- 每家 CLI 都必须在 `tests/test_review_homes.py` 里有明确的运行状态检查，没有就测试失败。
- 数据目录里不放凭证或凭证链接，只留工作产物。

`tests/test_review_homes.py` 从 `bin/sub*` 自动发现评审腿，用 CLI 桩检查正常、失败和超时后的清理；新腿缺桩或跑不通会失败。

普通缓存 `__pycache__`、`.pytest_cache`、`.mutation-state` 保持现状。
