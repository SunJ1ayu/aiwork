# aiwork

Multi-model implementation and PR review tooling.

评审与修复规则见 [REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md)，项目已接受风险见项目 main 的
`.aiwork/accepted-risks.md`，正式评审与合并条件见项目关卡策略。
任务的操作步骤见 [workflow/CLAUDE.md](workflow/CLAUDE.md)；工具用法在 `workflow/skills/`。
`~/CLAUDE.md` 和 `~/.claude/skills/delegate` 是由 `bin/sync-workflow-docs` 管理的部署副本。

GitHub `main` 是 aiwork 的源码准本。改动使用机器人分支和 PR；原始日志、配置、会话及本机资料
留在机器的数据目录。

## History

旧记录在 git 历史里。

## What lives elsewhere

- quicklook lives at `/root/quicklook`; its systemd unit and run-output path
  point there.
- The current wiki-ingest skill lives in the OpenClaw workspace at
  `/root/.openclaw/workspace/skills/wiki-ingest`; the older aiwork copy was
  removed.
- Local working files — task briefs, my-review files, reference notes, logs,
  tool homes — stay in the machine data directory outside this checkout. This repository is
  public: never commit private content.

## Layout

- `bin/` review commands and delegation tools (below)
- Machine data directory `tasks/` holds local task/brief files sent to reviewers (main-agent-authored)
- Machine data directory `logs/` holds reviewer output, `.err` sidecars and arbitration records
- `gate/` shared merge gate. A project connects by the steps in [gate/README.md](gate/README.md)
- `templates/` starter task files (`review-task.md`, `fix-task.md`) and the two gate workflow templates
- `tests/` regression oracles for this tooling itself
- `workflow/` canonical Claude instructions and workflow skills (deployed copies live outside Git)
- Machine data directory `worktrees/` holds per-job isolated checkouts created by `delegate-codex`
- `kimi-review-home/config.toml` and `hooks/guard.mjs` are versioned seeds; reviewer runtime homes use the data directory
- `out/`, `refs/`, `.mimocode/`, `etc/` and other local data live outside the checkout

## Review commands

每个通道都能写代码也能评审。写代码在自己的工作树里打开那家的命令行。
仓库里的这些命令服务 `review-pr`。同一个 PR 要换一家评审，由关卡判断。

- `bin/subdeepseek-agent` — DeepSeek，经 Claude Code headless 读仓库。模型来自 `~/.config/aiwork/models.env` 的 deepseek 行。
- `bin/subkimi` — Kimi，kimi-code CLI。模型来自 kimi 行。
- `bin/submimo` — MiMo，官方 `mimo` CLI。`review` 在可丢弃副本里读和跑检查；`fix` 做有界的小改动。模型来自 mimo 行。
- `bin/subcursor <review|explore>` — Cursor CLI。模型来自 cursor 行，或用 `CURSOR_MODEL` 覆盖一次。家族跟着模型走，不跟着 Cursor 这个传输。用 `cursor-agent login` 登录。
- `bin/subcodex <review|explore>` — Codex CLI。模型来自 codex 行（`SUBCODEX_MODEL` 覆盖一次）。源仓经 `ro-repo-exec` 只读，副本可丢弃，`--ignore-user-config --ephemeral`，提示词走 stdin。派发前用 `codex debug prompt-input` 离线确认子 agent 工具已去掉；联网搜索关闭。
- `bin/submimo-iso` — 两路同时用 submimo 时的隔离入口。
- `bin/review-pr PR [--repo owner/name] --leg LEG` — 评审一个 PR 的 head 并发布一条 aiwork-review COMMENT。`--repo` 默认是这个检出的 origin；origin 不是 GitHub `owner/name` 时显式传入。需要联网、需要读取本机模型凭证；被 agent 派去跑时必须在沙箱外运行。
  失败时打印脱敏后的 stderr 末 40 行，诊断留在数据目录 `logs/review-pr-failures/<run-id>/`，不含仓库检出和凭证助手。只保留最新 20 份失败档案。
  任务在 diff 之后再次要求结论。完整 diff（含删除）放得下就内联。超过 `READER_INLINE_DIFF_BYTES`（200KB）时，任务只列每个文件的状态和行数，完整 diff 在快照文件 `aiwork-review.diff`。
  这条命令默认给评审命令 2400 秒；已有的超时环境变量可以覆盖。只有缺结论或输出被截断时重试一次，并在终端和发布的评审里写明。每次失败的尝试都留下，包括重试成功的那次；其他失败不重新启动评审命令。

所有评审命令：`<tool> review TASK LOG REPO`。输出是主 agent 要核对的证据。

## Delegation entry + judging guards

- `bin/delegate-codex` — the ONE entry for handing implementation work to the
  codex (GPT) leg, and the mechanical half of receiving gate ①. It refuses to
  dispatch (codex never starts) unless: an attack-log exists outside the repo,
  a `--protect` judging list is given, and the attack-log carries the CURRENT
  `oracle-sha256:` of that judging surface (`--print-oracle-hash` emits the line).
  **Each job runs in its own git worktree by default** (`--no-isolate` opts out):
  data path `worktrees/<task>-<ts>` on branch `delegate/<same>`, created from the HEAD at
  dispatch. `--receive <receipt>` runs gate ① against that tree (plus a check for
  uncommitted judging changes in the MAIN tree, which the leg can still reach),
  records the machine-computed write set into the receipt, and PRINTS the
  integrate / symlink-check / `worktree remove` commands — it never merges or
  deletes anything itself.
  Isolation buys attribution, not confinement: `-s workspace-write` resolves its
  writable root upward to the main repo (a worktree's `.git` is a file), so case
  files (attack log, log, receipt) must stay outside `repo ∪ worktrees-root`.
- `bin/redcheck` — revert-the-implementation red check: puts the impl back to a
  baseline, rebuilds, reruns the oracle, and REQUIRES red (`--must-fail` pins
  where the red must land). Restores unconditionally and proves the tree is clean.
  The rule entry is [REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md).

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
still run standalone (`bash tests/test-delegate-isolate.sh`); each one execs
itself into a network namespace first, because **a judging process must have no
egress** (2026-08-10: an oracle called a paid model and burned the quota).

The oracle is owned by the main agent; employees must never edit it.

## MiMo agent CLI setup

```bash
npm install -g @mimo-ai/cli
mimo                      # or: mimo providers login / list
```

## 本机设置

仓库只保存工作流；本机设置统一放在 `~/.config/aiwork/`（目录权限 700）：

- `models.env`：Codex、Cursor、DeepSeek、Kimi、MiMo 和 triage 的模型选择，每条一行。可参考 `templates/models.env.example`。
- `typesafe.env`：triage 使用的 `TYPESAFE_API_KEY`，保留文件权限 600。
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

`tasks/`、`logs/`（包括失败日志）、`worktrees/`、`mimo-home/` 以及各评审命令的运行期 home
都使用该数据入口；已有的专用路径覆盖参数仍优先。源码、模板和共享组件相对实际工具位置查找，
`bin/` 应作为完整工具集部署；缺失共享组件时拒绝派发，不回落到其他机器的 checkout。

`kimi-review-home/config.toml` 和 `hooks/guard.mjs` 是版本控制中的种子；`subkimi` 在运行期 home 渲染模型和 guard 命令占位符。
运行期配置和 hooks 只从种子同步这两类文件；凭证、缓存、会话、日志、索引和遥测留在数据目录，
不会从种子目录整份复制。运行目录缺少凭证会明确拒绝运行。

`out/`、`refs/`、`.mimocode/`、`etc/` 的备份属于仓外本机数据。
归档发现旧位置仍有本轮注册的树时拒绝继续，
明确给出旧树和新根；`--keep-trees` 或既有专用路径覆盖仍可显式保留旧树。
普通缓存 `__pycache__`、`.pytest_cache`、`.mutation-state` 保持现状。
