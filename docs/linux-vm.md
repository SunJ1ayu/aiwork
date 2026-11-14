# Linux 虚拟机安装（给执行安装的 Agent）

这是新机器的安装步骤，不是切换指令。依据是 [路线决定](https://github.com/SunJ1ayu/aiwork/issues/43#issuecomment-6686152849)、[缩小范围的决定](https://github.com/SunJ1ayu/aiwork/issues/43#issuecomment-6708987865)。本单合并后，还须由 Mac 上的执行方在**新建**虚拟机里完整验证，再交汇总安排正式切换；此前正式发布仍在服务器。现有试验虚拟机不动。

Mac 的中台、标签来源、运行诊断和替换步骤见 [Mac 宿主运行手册](mac-host.md)。

## 安装布局与版本

Mac 运行 Lima、OpenClaw、autoloop 中台。按[钥匙隔离决定](https://github.com/SunJ1ayu/aiwork/issues/127#issuecomment-6768388449)，写代码和评审各用一台 guest，各自从下面同一份模板独立安装；guest 内统一用 root，普通登录账号只用于进入和 `sudo -i`。两台不共享目录、不互相登录，汇总的钥匙留在云端。`check-vm-isolation` 检查可见的宿主共享，不能证明两台之间的网络和凭证部署。

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

执行方只部署 `build` 角色配置及对应私钥；评审方只部署 `review` 角色配置及对应私钥、各家评审登录。不要克隆已经放过凭证的执行方磁盘来建立评审机；使用干净模板、分别 clone 公开代码。私钥经本人已有的非公开入口逐项部署，不整包复制配置，不在命令行或日志中展示。旧副本是否删除、旧钥匙是否轮换由本人决定，本 PR 不移动或销毁任何凭证。

两台各领不同的 worker 身份；Mac 的派活方固定将写代码任务交给执行方、评审任务交给评审方。实例名和 worker 路由只放 Mac 本机设置，执行方不能指定评审目的地。两台不保存对方登录钥匙，不开放互相登录的通道；从两边实测对方登录失败，检查磁盘、挂载、SSH 授权和中台路由，不把程序的角色检查当成虚拟机隔离证明。

执行方开 PR、CI 绿后运行 `review-pr PR --repo owner/name --request --builder-family FAMILY`，把输出交回派活方后停下。这个入口只用构建机器人读取 PR，输出公开的仓库、PR、head 和参数，不连接评审机、不调用模型、不发布评审。派活方核实 PR、CI、实际执行家族和当前 head，再将 `argv` 的各参数交给已配置的评审 worker；不可把 JSON 当 shell 脚本执行。评审机从自己的最新 main 运行其中的 `review-pr --auto`，head 改变会拒派。发布失败仍在评审机按工作流恢复。选远程评审服务时也使用同样的公开交接事实，由派活方自己的适配器发送。

**评审机内部的边界仍未解决**：`ro-repo-exec` 仅把仓挂只读，同账号进程仍能读仓外文件；清除 GitHub 令牌环境变量不隐藏 App 配置和私钥。这不影响两台之间的执行方钥匙隔离，但不能声称评审腿已经与发布钥匙隔离；在后续减少业主批准前须由汇总处理此未验收项。本 PR 不把它写成已接受风险、不改变关卡。

Mac 本机部署验收另交本人完成，PR 中的 Linux 测试不能代替：

1. 记录两台独立实例与代码版本；各自运行 `check-vm-isolation`，核对没有共享、互相登录通道或多余角色配置。执行方 `aiwork-config check-app-role build`、评审方 `aiwork-config check-app-role review` 均应通过；交换角色检查均应拒绝。
2. 执行方不放评审私钥，直接运行正式评审及重发入口应在联网前拒绝；只生成交接资料。评审方不放构建和汇总钥匙，构建取令牌入口应在换令牌前拒绝。检查真实文件部署，不能只信角色设置。
3. 从派活方发送一单本人授权的评审，核实实际 worker、PR head、作者与发布结果；旧 head 交接应拒绝，失败保存和重发仅留在评审机。两台重启后重新检查隔离与路由。
4. 单列评审腿可读同机钥匙的未解决项；上述验收不代表可以取消业主批准。任何一步缺证据，都不能写已通过。

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
