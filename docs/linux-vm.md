# Linux 虚拟机安装（给执行安装的 Agent）

这是新机器的安装步骤，不是切换指令。依据是 [路线决定](https://github.com/SunJ1ayu/aiwork/issues/43#issuecomment-6686152849)、[缩小范围的决定](https://github.com/SunJ1ayu/aiwork/issues/43#issuecomment-6708987865)。本单合并后，还须由 Mac 上的执行方在**新建**虚拟机里完整验证，再交汇总安排正式切换；此前正式发布仍在服务器。现有试验虚拟机不动。

Mac 的中台、标签来源、运行诊断和替换步骤见 [Mac 宿主运行手册](mac-host.md)。

## 安装布局与版本

Mac 运行 Lima、OpenClaw、autoloop 中台。按[钥匙隔离决定](https://github.com/SunJ1ayu/aiwork/issues/127#issuecomment-6768388449)，写代码和评审各用一台 guest，各自从下面同一份模板独立安装；guest 的管理和发布用 root，评审腿的普通账号见下方部署章节，guest 登录账号仍只用于进入和 `sudo -i`。两台不共享目录、不互相登录，汇总的钥匙留在云端。`check-vm-isolation` 检查可见的宿主共享，不能证明两台之间的网络和凭证部署。

虚拟机参数的唯一定义是 [templates/linux-vm.yaml](../templates/linux-vm.yaml)。文件用 JSON 语法书写（合法 YAML），因此测试能用 Python 标准库检查，无须另装解析器。它不继承 Lima 默认模板，因为默认模板会共享宿主家目录；只读共享也禁止。

| 程序 | 安装基线与来源 |
| --- | --- |
| Lima（Mac） | [正式版 2.3.0](https://github.com/lima-vm/lima/releases/tag/v2.3.0)，VZ，Apple Silicon |
| guest 系统 | 模板里带 SHA256 的 Ubuntu 24.04 ARM64 cloud image；不自动退到浮动镜像 |
| 系统包 | 模板 `provision` 是完整清单；版本来自 Ubuntu 24.04 发行线及安全更新，实际补丁号写本机清单 |
| Node / npm、各家 CLI | 下方安装块中的固定版本；测试 Node 的主版本由测试对照 Linux CI 核实 |
| autoloop | 下方固定正式 tag；Mac 和 guest 各自安装上游程序，不复制进 aiwork |

系统包随发行版提供 Python 3.12、Bash 5.2、Git 2.43 等兼容版本；不手工冻结有安全更新的系统包。CLI 基线采用服务器可核对的版本，不声称已经在新 guest 上跑过。DeepSeek、MiMo 共用 Claude Code，不另装 mimocode。上游发布物消失、安装失败或 ARM CLI 起不来时停下报告，不改为 x86 模拟或关闭防护。

## 1. Mac：准备 Lima，再创建全新的实例

使用 Mac 本人的终端，不能用 root 跑 `limactl`。从 Lima 上述正式发行页下载 `lima-2.3.0-Darwin-arm64.tar.gz` 和 `SHA256SUMS`，在同一临时目录里核对：

```bash
awk '$2 == "lima-2.3.0-Darwin-arm64.tar.gz"' SHA256SUMS > lima-selected.sha256
test -s lima-selected.sha256 && shasum -a 256 -c lima-selected.sha256
```

按 [Lima 手动安装说明](https://lima-vm.io/docs/installation/)把该压缩包的 `bin/`、`share/`、`libexec/` 装入同一安装前缀，将它的 `bin/` 加入 PATH；已有符合版本的安装就复用。安装路径属于本机设置。确认 `limactl --version` 与上表一致，不能只安装一个孤立的 `limactl` 文件。

默认不设 `LIMA_HOME`，实例留在 Lima 自己的默认位置。先检查本机 `~/.lima/_config/default.yaml` 和 `override.yaml`；如果存在共享目录、转发认证、额外磁盘或 socket 的配置，**先停下**核对，不让全局配置覆盖本模板，也不改现有试验实例。禁止 `--mount`、`--block-device`、`--sync`、`--preserve-env`、SSH agent/X11/socket 转发；不要把 Mac 的 HOME、aiwork 设置、OpenClaw、临时目录或项目目录共享进 guest。

从已审过的 aiwork 检出根目录执行；新机器可先匿名 `git clone https://github.com/SunJ1ayu/aiwork.git`。验收 PR 时使用待验的提交，合并后使用合并提交，记下 `git rev-parse HEAD`。实例名由本机选一个未使用的名字，后文都用同一 shell 变量：

```bash
read -r -p '新的实例名：' AIWORK_VM_NAME
test -n "$AIWORK_VM_NAME" || exit 1
limactl validate templates/linux-vm.yaml
limactl create --name="$AIWORK_VM_NAME" --mount-none --tty=false templates/linux-vm.yaml
```

启动前在 Mac 本地检查 Lima 生成的实例 `lima.yaml`：没有任何 `mounts`、`additionalDisks`、`copyToHost` 或 socket 转发；SSH agent、X11 转发关闭。配置可能含本机信息，不上传原文件。确认后：

```bash
limactl start "$AIWORK_VM_NAME"
limactl copy bin/check-vm-isolation "$AIWORK_VM_NAME:/tmp/check-vm-isolation"
limactl shell --workdir=/ "$AIWORK_VM_NAME" sudo /usr/bin/python3 /tmp/check-vm-isolation
limactl shell --workdir=/ "$AIWORK_VM_NAME" sudo -i
```

`limactl copy` 只发送这一个公开程序，不共享目录。检查失败就停下，不继续放凭证。每次重启、改 Lima 配置、插拔或改存储以后，都要从 guest 初始挂载命名空间重新检查。

**可选外接盘**：在创建新实例以前，把 `LIMA_HOME` 指到本人选定的已挂载目录，只在本机 shell 设置中保存它；每次运行 Lima 前先确认盘已挂好，不能让缺盘时自动建同名目录。最好使用加密磁盘。不要把实际盘名、路径写进模板、PR 或日志。Mac 上 autoloop 中台继续在内置盘 HOME 的默认目录，不随 `LIMA_HOME` 搬动。

## 2. guest：安装两份独立 Node 和 CLI

以下均在刚才的 **guest root shell** 执行，不能在 Mac 上执行。后续 shell 复用这里的版本变量；版本升级单独验证。

```bash
set -eu
umask 077
AIWORK_NODE_VERSION=22.23.4
AUTOLOOP_NODE_VERSION=24.22.2
KIMI_PACKAGE=@moonshot-ai/kimi-code@0.36.1
CLAUDE_PACKAGE=@anthropic-ai/claude-code@2.1.301
CODEX_PACKAGE=@openai/codex@0.166.0
CURSOR_VERSION=2026.10.16-e3cb207
read -r -p '从独立可信渠道核实的 Cursor 包 SHA-256：' CURSOR_SHA256
test "${#CURSOR_SHA256}" -eq 64

for entry in "aiwork:$AIWORK_NODE_VERSION" "autoloop:$AUTOLOOP_NODE_VERSION"; do
  purpose=${entry%%:*}
  version=${entry#*:}
  node_stage=$(mktemp -d)
  archive="node-v$version-linux-arm64.tar.xz"
  curl -fSL "https://nodejs.org/dist/v$version/$archive" -o "$node_stage/$archive"
  curl -fSL "https://nodejs.org/dist/v$version/SHASUMS256.txt" -o "$node_stage/SHASUMS256.txt"
  (cd "$node_stage" && sha256sum --check --ignore-missing SHASUMS256.txt)
  test ! -e "/opt/node-$purpose" || exit 1
  mkdir -p "/opt/node-$purpose"
  tar --no-same-owner -xJf "$node_stage/$archive" --strip-components=1 -C "/opt/node-$purpose"
  rm -r "$node_stage"
done

export PATH="/opt/node-aiwork/bin:$PATH"
npm install --global "$KIMI_PACKAGE" "$CLAUDE_PACKAGE" "$CODEX_PACKAGE"
cursor_stage=$(mktemp -d)
curl -fSL "https://downloads.cursor.com/lab/$CURSOR_VERSION/linux/arm64/agent-cli-package.tar.gz" -o "$cursor_stage/package.tar.gz"
printf '%s  %s\n' "$CURSOR_SHA256" "$cursor_stage/package.tar.gz" | sha256sum --check -
mkdir -p /opt/cursor-agent
tar --no-same-owner -xzf "$cursor_stage/package.tar.gz" --strip-components=1 -C /opt/cursor-agent
rm -r "$cursor_stage"
```

Cursor 包的预期 SHA-256 和 autoloop 发布提交须在安装前经独立可信渠道核实，不能从同一次下载结果自算后当作校验值。无法取得可信值时停下，不安装。

Cursor 的固定版本包地址取自[官方安装器](https://cursor.com/install)的发行目录结构，不运行会跟随最新版的安装脚本。启动时禁用自动更新的评审行为见 `bin/subcursor`；安装时也不运行 `cursor-agent update`。

## 3. guest：代码、本机设置与登录

在 guest 内新 clone，与 Mac 没有目录共享：

```bash
git clone https://github.com/SunJ1ayu/aiwork.git /opt/aiwork
cd /opt/aiwork
# PR 验收时，在这里检出与步骤 1 相同的待验提交。
install -d -m 700 "$HOME/.config/aiwork/programs"
ln -s /usr/bin/python3 "$HOME/.config/aiwork/programs/python3"
ln -s /opt/node-aiwork/bin/node "$HOME/.config/aiwork/programs/node"
ln -s /opt/node-aiwork/bin/kimi "$HOME/.config/aiwork/programs/kimi"
ln -s /opt/node-aiwork/bin/claude "$HOME/.config/aiwork/programs/claude"
ln -s /opt/node-aiwork/bin/codex "$HOME/.config/aiwork/programs/codex"
ln -s /opt/cursor-agent/cursor-agent "$HOME/.config/aiwork/programs/cursor-agent"
export PATH="$HOME/.config/aiwork/programs:/opt/aiwork/bin:/usr/local/bin:/usr/bin:/bin"
/usr/bin/python3 /opt/aiwork/bin/check-vm-isolation
```

按 [README「本机设置」](../README.md#本机设置)手动建立 guest 数据根目录并填写本机文件；默认数据路径只从该入口读取，不在这里另定一份。`models.env` 从 `templates/models.env.example` 开始填写。不要整包复制 Mac 的 aiwork 配置、HOME 或登录缓存。`private-terms` 也按 README 建立，缺少它时隐私检查会拒绝运行。

配置、登录缓存、模型选择、API Key、GitHub App 设置均只放 guest 自己的本机目录，权限按 README；数据用 `aiwork-config data-path`，工作树用 `aiwork-config data-path worktrees`。在 guest 单独登录 Kimi、Cursor、Codex；DeepSeek、MiMo 由业主新建能单独撤销的 Key，并在供应商后台设花费上限。不要把任何登录或钥匙写进仓库或验收输出。

机器人角色部署、评审交接与验收见下节；没有完成对应验收前不切换正式发布。

逐项执行 `python3 --version`、`node --version`、`kimi --version`、`claude --version`、`cursor-agent --version`、`codex --version`，再对本次要用的各腿执行 `aiwork-config check-programs 入口名`。任一 ARM 程序失败就停下，不放松防护让它跑。

## 角色部署与评审交接

在每台 guest 的本机设置目录建立权限 600 的 `review.env`，格式与行为见 [README「评审位置」](../README.md#评审位置)。执行方选 `external`，评审方选 `local`；默认模板内存不变，小机器可在新实例的本机配置调到 2GiB，不能低于它，不修改公共模板中的默认值。

执行方部署 [执行方登记](../gate/README.md#执行方登记) 中配置对应的私钥。未切换的任务继续使用 `build`。评审方只部署 `review` 角色配置及对应私钥、各家评审登录。不要克隆已经放过凭证的执行方磁盘来建立评审机；使用干净模板、分别 clone 公开代码。私钥经本人已有的非公开入口逐项部署，不整包复制配置，不在命令行或日志中展示。旧副本是否删除、旧钥匙是否轮换由本人决定，本 PR 不移动或销毁任何凭证。

两台各领不同的 worker 身份；Mac 的派活方固定将写代码任务交给执行方、评审任务交给评审方。实例名和 worker 路由只放 Mac 本机设置，执行方不能指定评审目的地。两台不保存对方登录钥匙，不开放互相登录的通道；从两边实测对方登录失败，检查磁盘、挂载、SSH 授权和中台路由，不把程序的角色检查当成虚拟机隔离证明。

执行方开 PR、CI 绿后运行 `review-pr PR --repo owner/name --request --builder-family FAMILY`，把输出交回派活方后停下。这个入口只用构建机器人读取 PR，输出公开的仓库、PR、head 和参数，不连接评审机、不调用模型、不发布评审。派活方核实 PR、CI、实际执行家族和当前 head，再将 `argv` 的各参数交给已配置的评审 worker；不可把 JSON 当 shell 脚本执行。评审机从自己的最新 main 运行其中的 `review-pr --auto`，head 改变会拒派。发布失败仍在评审机按工作流恢复。选远程评审服务时也使用同样的公开交接事实，由派活方自己的适配器发送。

**评审机内部账号分离（#154，待真机验证）**：`local` 模式的发布程序仍由 root 从最新 main 运行，适配器和模型使用同一个已配置普通账号的真实与有效 uid。发布侧建立进程空间及对应 `/proc`，保留正常系统文件和域名解析；不把系统根目录变只读。每次调用的 home 和运行路径仅在本次挂载空间可见，背后的文件存于发布账号私有数据目录；不同调用使用不重复的运行组，防止同 uid 的其他进程经 `/proc` 进入本次目录。普通账号保留原主组作为附加组来读取已部署设置，不获得创建命名空间或其他能力。

发布账号的 home、设置、角色配置、钥匙、部署程序和记录须以私有权限保护。入口以腿身份只探测可访问性，不读取真实钥匙；登记的钥匙还须由 root 独立持有。公开运行代码从 Git 清单制作，排除发布入口与凭证。源仓、任务和运行代码归 root；程序安装与模型设置同样须归 root 且腿不可改写，设置目录在腿 home 以外，由 `review-user.env` 的 `settings` 指定。

每次使用新的可写 home；需要的固定 CLI 配置可放在上述设置目录的 `home/` 模板内，每次复制后只在本次修改。持久输入仅接入 [登录路径登记表](../bin/_aiwork_config.py) 中的状态：Kimi、Cursor 的登录目录可读写；Codex 只由普通账号复制并回写 `auth.json`，不加载持久目录里的配置、插件或技能。发布侧不读取登录内容。aiwork 工作区和缓存使用本次私有临时目录，升级时不使用旧版 root 留下的共享工作区，无须删除或改权限。

Cursor 的 CLI 由发布侧监管入口创建独立进程空间，再降到普通账号执行；登录环境以不解析的文件描述符传递，只有降权后的进程才加载。CLI 退出立即收掉其 worker，再由适配器收尾。适配器退出后监管进程终止剩余进程，再将独立普通结果文件封存到 root 私有目录；外层只收取已完成的封存，不读取仍可被腿改写的文件。链接、硬链接、管道结果拒收。

这保护发布账号的私有文件，也覆盖其 home 下未登记的其他凭证；各家模型登录属于腿账号，仍可被该账号读取。不能保护故意设成公开可读的秘密、内核漏洞或拥有其他提权通道的账号。不能凭本机模拟测试声称已隔离；真机验证和业主批准仍是合并前提，不改变关卡。

本边界只用于正式评审入口。持有发布钥匙的 root 不直接运行适配器或 `explore` 来处理不可信任务；手工小任务同样通过下方的生产执行函数切换身份。

### 评审账号部署与真机验证

以下由业主在评审机完成，执行方不远程操作，不复制或查看真实钥匙、登录内容：

1. 建立带独立 home 和私有主组的普通账号，例如 `useradd --create-home --user-group --shell /bin/bash aiwork-leg`；home 权限设为 700。不赋予管理权限，不加入发布账号的组。系统须有 `util-linux`，发布程序须能创建进程与挂载命名空间；普通账号不需要挂载权限。
2. 发布程序、设置、数据仍归 root，目录保持 700、私有文件保持 600；核对发布 checkout（例如 `/opt/aiwork`）不可被腿读取或改写。GitHub 钥匙原位置不动，不新建 App。用 `aiwork-config path review-user.env` 定位，写入 `user=aiwork-leg`，该文件由 root 独立持有，其他账号不可改；`review.env` 仍选 `local`。这里只声明新字段，账号规则入口见 [运行实现](../bin/_leg_session.py)。
3. root 在腿 home 外建立独立运行设置目录（例如 `/etc/aiwork-leg`）：目录和配置归 root、腿的私有主组，目录 750、配置 640；在 `review-user.env` 增加 `settings=/etc/aiwork-leg`。按 README「本机设置」在该目录登记程序及模型、reader 参数和供应商配置。程序及完整安装依赖由 root 管理，腿只能读取执行；程序不能安装在腿可改写的 home 下，也不能仍指向发布账号的私有目录。不把 GitHub 角色、钥匙或发布设置放进这个目录。相对设置仍相对该目录解析；需要的固定原生 CLI 配置可放 `home/`，不要把登录内容放模板。
4. 业主以 `sudo -iu aiwork-leg` 亲手完成各家登录，路径可用 `AIWORK_CONFIG_DIR=/etc/aiwork-leg /opt/aiwork/bin/aiwork-config login-path 供应商` 定位（发布 checkout 私有时，使用已部署给普通账号的公开工具副本）。登录目录属于腿账号，不使用目录链接指向发布账号。API 供应商固定设置由业主在 root 持有的运行设置目录填写。旧 home 中的模型设置、程序登记、Git/CLI 配置和插件不会被评审加载；登录如何保留由业主决定，不整包复制发布账号 home。本实现不删除旧登录或共享工作区。
5. 发布数据目录的 `review-account/` 由工具建立并保持 root 私有，里面的运行组计数器须保留，不手工清零或回滚；工具会避开已有系统组和已分配的从属组范围。不要给其他服务分配这里使用的高位运行组。临时目录随本次调用回收；这不改变任何系统账号或组的配置。


合并前，在评审机的独立 PR 检出直接使用该提交的生产 `_leg_session.run_leg_attempt`，不调用或绕过正式 `review-pr` 的最新 main 保护。检查结果贴回 PR，只记录版本、账号身份与成功/失败，登录和钥匙只做元数据/可访问性核对，不输出内容：

- 从这个入口运行每条登记腿，用一次性小仓库实际调用各家已配置模型，产出结论；确认有效 uid 为普通账号，登录文件可正常读写。没有触发续期就明确写未验证续期，不以模拟写入冒充真实续期证据。
- 用假钥匙、假发布程序、假历史记录验证外层可访问、腿不可读写；对真实部署文件只做可访问性检查，不读取真实内容。核实其他发布账号私有文件和外层进程不能被腿访问。
- 验证 root 持有的源仓、运行设置和程序不可改，自己的工作副本及登录可写；在旧 home 放一个无害的不同模型设置，确认下一次仍读取 root 设置。并发的小任务不能读取彼此工作区，也不能经 `/proc` 访问；进程结束后普通账号不能改封存结果。链接、硬链接、管道拒收。
- 保留旧部署的 root 私有共享工作区，五条腿仍应直接运行；确认本次临时目录不同。用真实 Cursor 核实 CLI 退出后 worker 被收掉且评审正常结束；模拟 worker 测试不能替代这一项。
- 缺账号配置、错误账号或发布目录可访问时拒跑；恢复部署后上述小任务能完成。若必须让腿读取发布账号文件才能运行，立即停止交业主，不能逐项放开。

**只能合并后核实**：正式 `review-pr --auto` 必须由发布账号从最新 main 运行。新代码进入 main 后，由派活方发送一单授权评审，核实真实自动发布的账号、目标、head、模型及结论块；再检查失败归档/重发和重启后的账号分工。合并前小任务及离线发布桩不能代替这条证据。每一项未执行或失败均保留为未验收，不能写成已通过。

Mac 本机部署验收另交本人完成，PR 中的 Linux 测试不能代替：

1. 记录两台独立实例与代码版本；各自运行 `check-vm-isolation`，核对没有共享、互相登录通道；角色配置按 [角色检查入口](../bin/_aiwork_config.py) 核对。执行方各带本家派活家族（`AIWORK_BUILDER_FAMILY`）运行 `aiwork-config check-app-role build`，解析到[执行方登记](../gate/README.md#执行方登记)里本家的角色并各自通过，本家角色换令牌（`gh-app-token build --grant`）也各自成功；不带派活家族只解析成通用 `build`，只放 `build.env` 也能通过，验不出各执行方角色是否部署。评审方 `aiwork-config check-app-role review` 应通过；交换角色检查均应拒绝。
2. 执行方不放评审私钥，直接运行正式评审及重发入口应在联网前拒绝；只生成交接资料。评审方不放构建和汇总钥匙，构建取令牌入口应在换令牌前拒绝。检查真实文件部署，不能只信角色设置。
3. 从派活方发送一单本人授权的评审，核实实际 worker、PR head、作者与发布结果；旧 head 交接应拒绝，失败保存和重发仅留在评审机。两台重启后重新检查隔离与路由。
4. 按上方账号部署与真机清单核实评审机内部边界；上述验收不代表可以取消业主批准。任何一步缺证据，都不能写已通过。
5. 写代码机每家各真接一张单：真读到一张派来的任务单、连上 GitHub；其余对照 [#171 决定一](https://github.com/SunJ1ayu/aiwork/issues/171#issuecomment-6998669468)的同一份共同执行规矩逐项核对，共用这一份，不各写一套。
6. 以后每次部署改动，都要用一张真单从头跑一遍才算验收（[业主 2026-11-19 决定](https://github.com/SunJ1ayu/aiwork/issues/43#issuecomment-7000910124)「另定」）。

## 4. autoloop：只安装和连接，不配置派活

固定使用 [agent-autoloop 正式发布版](https://github.com/KKKKhazix/agent-autoloop/releases/tag/v1.6.1)。不要运行上游会选最新 Release 的安装器或 `update`，不要把上游代码、规则副本放进 aiwork。Mac 中台和 guest 接单程序分别匿名 clone 该 tag 到各自默认的 `~/.agent-autoloop/app`，已存在时先核实，不覆盖。

guest root shell：

```bash
set -eu
AUTOLOOP_TAG=v1.6.1
read -r -p '从独立可信渠道核实的发布提交完整哈希：' AUTOLOOP_COMMIT
test "${#AUTOLOOP_COMMIT}" -eq 40
install -d -m 700 "$HOME/.agent-autoloop" "$HOME/.local/bin"
git clone --depth 1 --branch "$AUTOLOOP_TAG" https://github.com/KKKKhazix/agent-autoloop.git "$HOME/.agent-autoloop/app"
test "$(git -C "$HOME/.agent-autoloop/app" rev-parse HEAD)" = "$AUTOLOOP_COMMIT"
cat > "$HOME/.local/bin/agent-autoloop" <<'SH'
#!/bin/sh
exec /opt/node-autoloop/bin/node --disable-warning=ExperimentalWarning "$HOME/.agent-autoloop/app/bin/agent-autoloop.ts" "$@"
SH
chmod 755 "$HOME/.local/bin/agent-autoloop"
/opt/node-autoloop/bin/node --version
```

这是 Node 自带 TypeScript 支持的程序，不需要 `npm install`。上面的启动器用绝对路径选 Node，不改变测试用的 `node`。Mac 上复用已安装的 Node（要求 >=24；试用用过 Node 26），使用同一固定 tag 和默认目录，按上游该 tag 的 [INSTALL.md](https://github.com/KKKKhazix/agent-autoloop/blob/v1.6.1/INSTALL.md)和 [正式配置手册](https://github.com/KKKKhazix/agent-autoloop/blob/v1.6.1/skills/agent-autoloop/SKILL.md)配置中台；`hub.listen` 只用 `127.0.0.1:3350`，Mac 不配 worker。中台的 owner/channel Key 留在 Mac，guest 只领 worker Key。通知只保留 OpenClaw 一个通道，桌面通知关闭；不改现有 OpenClaw 程序。

在 Mac 本机设置中生成一个专用于新 guest 的 worker 身份（不复用试验 worker），通过非公开本机操作交给 guest。guest 的 `~/.agent-autoloop/config.json` 只需 `url`、`worker.name`、`worker.key`，字段见上游 `host/config.ts`；地址为 `http://host.lima.internal:3350`。文件 600、父目录 700，不放 `hub`、`owner` 或 `channels`。不要把 Key 填进公开示例、终端录屏或命令行参数。

确认从 guest 连通中台，Mac 本地核实监听地址仍是回环地址；不改为 `0.0.0.0`，不挂载目录，不开隧道。步骤 1 已禁用 guest 到 Mac 的自动端口转发；guest 主动访问中台不受此限制。网络访问不是目录隔离检查能证明的事实，需要真机复验。

guest 如需重启后自动恢复，可用上游支持的同名系统级服务（不依赖 root 的 user systemd session）：

```bash
cat > /etc/systemd/system/agent-autoloop.service <<'UNIT'
[Unit]
Description=Agent autoloop guest worker
Wants=network-online.target
After=network-online.target

[Service]
User=root
Environment=HOME=/root
Environment=PATH=/root/.config/aiwork/programs:/opt/aiwork/bin:/usr/local/bin:/usr/bin:/bin
ExecStartPre=/usr/bin/python3 /opt/aiwork/bin/check-vm-isolation
ExecStart=/opt/node-autoloop/bin/node --disable-warning=ExperimentalWarning /root/.agent-autoloop/app/bin/agent-autoloop.ts up
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now agent-autoloop
```

没有 `rules.json` 派活规则也不往正式中台发试验事件；本单只验连接和重启恢复。不要执行 `agent-autoloop service install` 再叠一个 user 服务。

## 5. guest：检查和全套测试

在 guest 初始 shell 跑检查，不在腿的挂载沙箱中跑。检查退出码 0 为当前观察通过，1 为发现违反项，2 为观察失败、参数或运行环境不对；任何非零都停下。

`MOUNT` 拒绝宿主共享及未知文件系统，包括改名、任意挂载点、只读共享；`MAC_PATH` 查 Mac 根目录；`MAC_SETTINGS` 查 Mac 设置痕迹和 aiwork 链接；`OPENCLAW` 查已知应用和状态位置及 PATH；`SSH_AGENT` 查转发的认证入口。读取或解析失败不会给 PASS。

检查只覆盖当前可见的挂载、列出的路径与环境，不证明 hypervisor 身份，不追溯任意改名复制进 guest 的文件来源，也不阻止以后新增挂载。Lima 云初始化盘等 guest 本地块设备可用；不要附加 Mac 原始块设备。安装前核对宿主配置与 guest 实查必须都做。

以下在 guest root 的 `/opt/aiwork` 内运行；与 Linux CI 相同，测试自行建断网命名空间，不改守卫，不靠环境变量冒充隔离：

```bash
export PATH="$HOME/.config/aiwork/programs:/opt/aiwork/bin:/usr/local/bin:/usr/bin:/bin"
/usr/bin/python3 /opt/aiwork/bin/check-vm-isolation
node --version
bash bin/rust-check-review-tooling
```

## 6. 真机验收交给汇总

证据等级见 [REVIEW-RULES 第二节第 3 条](../REVIEW-RULES.md)。服务器上的单元测试和模板解析只是「跑过」，新 guest 安装、CLI 运行、连回中台与重启恢复均须「在真程序里复现」。提交以下脱敏结果，不提交原始配置或整份进程环境：

1. 新实例使用的 aiwork 提交、Lima 和 OS 版本、模板参数、CLI 实际版本；系统包版本清单用 `dpkg-query -W` 保存在 guest 本机，传交时只摘本次依赖包。
2. 默认状态隔离检查通过；在**可丢弃的新验收实例**里，只共享一个不含秘密的 Mac 临时目录，确认检查非零并报 `MOUNT`，移除共享后再过。不要为了验收共享真实 HOME 或钥匙。
3. 用无秘密的临时 OpenClaw 状态目录或 aiwork 指向 `/Users` 的链接，确认各自对应规则报错，清理后再过；本机设置原文件不动。
4. guest 全套测试结果；各家直接评审入口真实运行、无发布，结束后检查进程残留。测试 Node 与接单 Node 分别核实，不用提高权限之外的绕过。
5. Mac 回环监听、guest 经 `host.lima.internal` 连回中台、Mac 局域网地址连接应失败、重启 guest 后接单程序自行恢复；只验新 worker，不触发正式工作。没有另一台局域网设备实测时明确标注。

任一步失败停止切换，记录具体版本与结果交汇总；不要把未验证项写成已通过。

评审交接适配器的仓库与本机边界、安装设置见 [评审交接入口](review-handoff.md)。

### 评审交接并行验收

本节是评审交接更新后的操作步骤；以下步骤尚未由本次执行方在评审机真机验证。配置字段、容量与恢复语义只见 [评审交接入口](review-handoff.md)。以下由业主在 Mac 和评审机操作，执行方不登录评审机，不修改任何机器配置。

1. 按 [业主决定](https://github.com/SunJ1ayu/aiwork/issues/43#issuecomment-7101735047)，先在 Mac 将评审机内存加到 6 GiB，核对 guest 实际可用内存；保持写代码机和评审机的隔离。停止旧评审入口接新单，等待旧轮次退出，保留原设置和运行记录，按交接入口说明完成升级。
2. 按业主决定的目标轮数核对三处：评审机原 SETTINGS 的 `concurrency`（定义见交接入口）；Mac 中台评审组的同时上限；评审机接单程序 `~/.agent-autoloop/config.json` 的 `worker.capacity`。第三处是外部 agent-autoloop 的本机设置，读取与传递见固定安装版本的 [host/config.ts](https://github.com/KKKKhazix/agent-autoloop/blob/v1.6.1/host/config.ts)、[host/up.ts](https://github.com/KKKKhazix/agent-autoloop/blob/v1.6.1/host/up.ts)，执行容量判断见 [worker/worker.ts](https://github.com/KKKKhazix/agent-autoloop/blob/v1.6.1/worker/worker.ts)。三处分别控制入口准入、中台派发、接单机器容量，跨两个程序和两台机器，不能仅在本仓库收成一个设置；不复制上游程序或兜底值。以后调整轮数，逐一核对三处，不改代码。接单程序启动时读取设置，修改后由业主按原服务方式重启，并核对服务账号、实际配置位置与运行版本；不要启动第二个接单实例。核对发布账号、普通腿账号和命名空间能力，记录运行的 main 提交；不公开配置内容。
3. 从 Mac 中台提交两个不同 PR 当前 head 的授权评审请求，核对两轮确实重叠、检出路径不同、原源码检出未切换、任务和结果互不覆盖；另发一个已完成 head 的重复请求，核对直接返回已交接，未申请交接容量、未创建新检出、未读取 GitHub、没有再次正式派腿。核对接单程序确实同时持有两轮、中台未限成一轮；不能仅凭三个设置值宣称生效。再提交超过容量的请求，确认排队。核对实际发布身份、目标 PR、head 和关卡认可的 CI，不用模拟测试替代。
4. 重叠运行时用 `free -m`、`vmstat 1` 及进程内存统计记录空闲量、峰值、交换区和内核内存不足记录；观察两轮从开始到结束，不能只看启动瞬间。记录是否有腿被内存不足终止。内存不够或隔离检查失败时停止验收，交业主调整，不擅改容量或隔离。
5. 用授权的小任务验证排队、中断和恢复；在独立验收配置中缩短总时限，让挂住的假评审超时，确认其另建会话的后代也退出、下一轮能接纳。模拟坏记录只操作独立验收数据，不改生产成功记录。旧成功记录必须先核对转存并能阻止重复。用独立验收夹具让预检取令牌和读派发状态各短暂失败一次，核对沿正式入口退避后能派腿；让总时限落在持久完成记录写入之后，核对回执仍报告该次完成结果；落在提交完成记录之前则仍报告未完成。不得改生产记录或制造真实凭证故障。
6. 将版本、环境、实际并发、独立检出、去重、超时清理、各次结果、内存峰值及未验收项回报汇总；不包含配置原文、登录或钥匙。未运行或未通过的项目保持未验收。

### 评审发布验收

发布边界和实现入口见 [评审交接入口](review-handoff.md)。以下尚未由本次执行方在评审机真机运行；合并后由业主在独立验收环境操作，不改生产凭证、发布记录或权限，不在正式 PR 上制造故障。

1. 更新后记录实际运行的 main 提交、GitHub CLI 版本、发布机器人身份和验收 PR 的当前 head。运行离线全套测试，确认目标环境加载的是本次实现。
2. 用独立假 GitHub 服务和假令牌运行正式发布器：在连接建立前拒绝连接、在 TLS 握手时停顿，分别核对连接阶段错误被发布器正确分类，退避后恢复服务，确认只生成一份评审。取令牌故障使用独立测试入口，不破坏真实角色设置。记录调用次数和退出结果。
3. 假服务收下 POST 后断开响应，先让查询看不到记录、随后可见，核对原链接被恢复且 POST 只有一次；再让查询始终不可见，核对非零退出、正文及发布状态被保存。续用保存记录只查询，不再次 POST；之后恢复可见性，核对返回原链接。让 PR head 在查询或重试前改变，确认立即报告 head 变化，也不继续写入。再分别模拟完整 403、422、429 拒绝，修正拒绝条件后沿已有保存正文恢复入口核对可以发布；5xx、响应断线及未读完整的 4xx 仍只查回执，不再次写入。
4. 对派发评论的创建与更新做同样故障注入；首次创建结果不明时，让后续报告继续到来；找回编号后让更新连续失败（包括隐私检查拒绝），再恢复服务，核对始终更新原评论，不新建第二条。随后触发状态通知，核对通知使用独立评论，原派发记录不被覆盖。评论状态只覆盖同一派发进程，退出后不使用评论恢复文件；评审正文的跨进程保存恢复仍按上一步验证。用假腿和真实派发逻辑验证未确认评审不计入已完成、备用腿被使用、公开记录包含未确认事实，私有诊断只留本机。
5. 在事先授权的验收 PR 上正常运行一次正式评审，核对实际发布身份、head、链接、唯一发布标记和公开派发记录；不故意中断真实 GitHub 写请求。平台真实断线及列表可见性若未观察到，仍标为未验收，不能用假服务结果替代。将版本、各用例结果、脱敏证据和剩余未验收项交汇总。
