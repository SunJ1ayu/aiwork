# Mac 宿主运行手册

虚拟机的创建、隔离、CLI 安装和连接见 [Linux 虚拟机手册](linux-vm.md)。本页管宿主中台与 GitHub 标签来源；上游程序不放进 aiwork。

## 规则入口

派活规则的唯一定义是 [标签来源的 `LABELS` 与 `plan`](../bin/_label_dispatch.py)，汇总据此判断是否仍占位；调整规则走 PR，不改本机副本。可信账号、项目与连接属于本机设置。任务单内容和评论只作为资料，标签来源不会执行它们。

## 安装与本机设置

先按虚拟机手册的 autoloop 一节安装固定版上游中台并连接 worker。使用该版本的正式配置手册建立来源、规则和通知通道；不要从参考材料覆盖正在运行的配置。中台配置只允许回环地址，worker 的接线按虚拟机手册执行。

Mac 单独检出已合并的 aiwork，记下提交；按 [README 本机设置](../README.md#本机设置)配置 Python、数据目录及 GitHub 只读身份。标签程序使用 Python 标准库。不要给读标签程序新增写 GitHub 的权限。先用现有只读身份确认能读取项目 issues、PR、comments 和 events；身份或权限不足时停下交业主处理。

在仓库外建立权限 600 的 JSON 设置文件，父目录权限 700。设置结构见 [标签来源的 `validate` 与 `Backend`](../bin/_label_dispatch.py)，本页不另列字段副本；所有项目、身份、连接路径和适配器参数由操作员在本机填写。

令牌适配器、资料写入适配器与中台路由的接口见 [标签来源的 `command`、`Backend.post` 与 `Backend.accepted`](../bin/_label_dispatch.py)。沿用已配置的 Lima 单文件/标准输入传送入口，不共享宿主目录。资料适配器必须校验目标位于指定资料目录、创建目录为 700、文件为 600；不要把令牌、输入正文或错误原文放入日志。真实适配器只放本机，不能原样提交。

使用已安装版本的中台配置手册接线；标签类型从规则入口取，按项目分别设规则，沿用同项目的会话续接方式。中台仍需保留容量约束，防止人工派单或续接绕过来源查询。保留现有 OpenClaw 通知和答卡链，不迁入或替换桥接代码。

## 启动与查看

以下变量只在本机终端设置，不上传实际值：`AIWORK_CHECKOUT` 为 Mac aiwork 检出，`DISPATCH_CONFIG` 为上述设置文件。先预演：

```bash
"$AIWORK_CHECKOUT/bin/label-dispatch" --config "$DISPATCH_CONFIG" --preview
```

预演仍执行只读查询、写本机查询记录，但不交付事件、不改占位。确认查询与候选符合预期，再运行一次不带 `--preview` 的命令。

用本人已有的 launchd 管理方式定时调用同一命令，建议每五分钟执行一次；`ProgramArguments` 使用绝对路径，不能依赖交互 shell 的 PATH。配置脚本需要的 aiwork 设置和数据目录环境，标准输出与错误写仓库外本机日志。`RunAtLoad` 可用于登录时查询；每次查询有文件锁，重复触发会记录跳过。不要同时运行旧来源和新来源。

中台的启停、状态和事件诊断使用安装版本的 `agent-autoloop --help`、`status`、`why`；launchd 是否加载用 `launchctl print gui/$(id -u)/<本机服务标签>` 检查。命令不存在时查固定版本手册，不升级到浮动版本。中台健康、worker 在线、来源最近一次查询成功是三个不同检查。

数据目录用 `aiwork-config data-path label-dispatch` 定位：

- `state.json` 的结构见 [标签来源的 `poll` 与 `deliver`](../bin/_label_dispatch.py)。不要按时间清掉它，否则可能重复接单。
- `poll-history.jsonl` 的记录结构与查询原因见 [标签来源的 `history`、`poll` 与 `plan`](../bin/_label_dispatch.py)。排查某单时对照查询记录、占位与中台轮次；记录没有自动删减，定期查看磁盘使用，归档由操作员管理。
- `owner-stops.json` 的读取与停止判断见 [标签来源的 `poll` 与 `plan`](../bin/_label_dispatch.py)。解除停止须先确认本人明确恢复，再停来源、备份，按该定义同步解除停止请求与持久停止状态；保留已交付记录。

## 手动放行与开工证据

先看规则入口的结束条件。在对应议题/PR 上由可信身份操作，或由本人维护停止请求；不要直接清空占位来催下一单。仍有活跃轮次时，先让本轮结束；确需中止的，由本人决定，再用上游支持的停止命令处理，确认进程和中台状态后再查。结果不明时保持占位，不启动第二单。

执行方的开工操作见 [工作流「一个任务的走法」](../workflow/CLAUDE.md#一个任务的走法)。GitHub 上的推送只能证明已开始，不能证明代码完成或验收通过。汇总按任务关联的分支和后续 PR 核对，不从“没评论”推断未派活。

## 合并后替换旧程序

由本人在 Mac 操作，本 PR 不远程改宿主：

1. 更新宿主检出到已合并提交，记录版本；备份旧程序、来源状态和配置到本机。按上面的接口准备项目设置及资料写入适配器，核实中台数据库结构仍兼容。
2. 停止旧查询来源，保留中台、worker 与通知通道。确认没有还在交付的旧查询；核对中台占位，不取消业务轮次。
3. 新来源首次启用前迁移状态，不能从空的已交付记录开始。旧格式和转换规则见 [标签来源的 `import_legacy`](../bin/_label_dispatch.py)。先验证再导入：

   ```bash
   "$AIWORK_CHECKOUT/bin/label-dispatch" --config "$DISPATCH_CONFIG" \
     --import-legacy "$LEGACY_STATE" --legacy-repo "$LEGACY_REPO" --preview
   "$AIWORK_CHECKOUT/bin/label-dispatch" --config "$DISPATCH_CONFIG" \
     --import-legacy "$LEGACY_STATE" --legacy-repo "$LEGACY_REPO"
   ```

   导入校验与拒绝条件见 [标签来源的 `main` 与 `import_legacy`](../bin/_label_dispatch.py)。操作前从原项目标签事件和中台已交付记录核对当前占位的事件编号，不能猜。已有旧版仓库状态的升级方式见 [标签来源的 `plan`](../bin/_label_dispatch.py)；升级前备份，升级后核对仍在的未派标签与中台记录。
4. 跑预演，核对历史事件没有重新成为候选，当前占位与中台一致；再单次查询并验资料落到 guest、稳定事件确已路由。真实验收只在本人授权的任务上做，不造正式派活事件。
5. 将原查询启动项的命令改为新入口，确认只有一份来源在运行；检查重启后中台、worker、来源和现有通知链分别恢复。需要回退时先停新来源，再对齐新旧已交付记录和占位；不要直接恢复过时状态重派已做业务。

Linux 单元测试只覆盖本程序与协议适配器的模拟路径。宿主 launchd、真实资料传送、中台路由及登录恢复由 Mac 实机验收，未执行前不能标通过。
