# 验证状态

当前接手状态：实现与最终验收已完成，默认 Grok；39 项专项回归和真实双模式通过，最终 MiMo + Cursor Grok 两家族复核合格。以下保留历史过程；当前裁决以 decision.json 为准。

初次验证时：实现已接入；真实调用待登录。主自审存于仓外 /root/panel-my-reviews/cursor-review-explore-my-review.md。
Cursor CLI 2026.09.15-d2fe57e 的 status 返回 Not logged in，不能把离线桩通过说成供应商已可用。

## 机器证据

runlog: cursor-adapter rc=0 commit=dc6f735 dirty=yes at=2026-09-18T02:23:44Z file=tracks/cursor-review-explore/evidence/20260918T022344Z-01-cursor-adapter.txt

Cursor 专项：16 项通过（认证副本/清理、脏仓与原仓只读、差异可读、双模式、换模型、家族预算去重、异常与超时拒绝）。
完整 rust-check-review-tooling 已运行：仅 review-tooling 的 V46⑧d 红（新开关漏入测试环境探针），其余套件通过。
已补清单并单独重跑该套件，561 项通过、0 失败。断线发生在进程成功退出之后，接手从原会话和现存收据交叉确认，无需重复全量回归。

runlog: review-tooling rc=0 commit=dc6f735 dirty=yes at=2026-09-18T02:34:48Z file=tracks/cursor-review-explore/evidence/20260918T023448Z-01-review-tooling.txt

## 接手复核（2026-09-18）

核查原始 diff、适配器、流解析、共享身份判据和两个调度入口。补齐 panel 技能正文中的默认发散通道说明；原先仅 references/legs.md 写了 Cursor。
当前 `cursor-agent status` 仍返回 `Not logged in`。真实验收仍待认证。
接手亲跑 `python3 tests/test_subcursor.py`：16 项通过，19.872 秒，退出码 0；`git diff --check` 通过。
使用说明已通过 `bin/sync-workflow-docs --force` 同步，随后 `--check` 返回 0。
另直接核对本机 CLI 源码：7021.index.js 的 init/assistant/result 事件与解析器字段一致；index.js 存在所用工具与配置隔离参数。该静态核对不代替认证后的供应商冒烟。
独立复核不依赖 Cursor 自身登录，使用已有健康评审腿，预算沿用设计中的一轮初审加一次必要修复复审。
本 track 的 verify.md 已在首次派发前存在，其中包含原会话自审摘要：如实记录这个反锚定限制，不能声称本轮完全盲审；仓外详细主自审仍不发给评审腿。

## 发现与处置

| 发现 | 处置 | 证据/理由 |
| --- | --- | --- |
| 只读工具不能执行 git diff | 本单已修 | subcursor 启动前生成 snapshot tree diff，测试确认 dirty/untracked 内容可见 |
| Cursor 切换到现有家族会重复占预算 | 本单已修 | 选腿/追加腿按家族去重，--all 保持全派发，专项测试覆盖 |
| 花名册固定基线缺新增腿 | 本单已修 | 更新 golden，完整回归中 panel-roster 通过 |
| 新开关漏入 V46 的探针清单 | 本单已修 | 清理入口已有开关，补环境检查清单后复跑 |
| 未登录，真实模型/输出展示名未确认 | 等用户认证 | 先执行 cursor-agent login；然后 review/explore 各做一次真实小任务 |

## 收口

不归档、不宣称真实接通。变更未提交；保留原有无关任务文件不动。
模型配置在 bin/cursor-model；两个模式共用，CURSOR_MODEL 可单次覆盖。

## 外部复核轮次

- 第 1 次派发：`logs/panel-cursor-review-explore-r1-20260918`，MiMo + DeepSeek，high 两家族。两条底座均在 360 秒超时（rc=124），无最终裁决；DeepSeek 按现有流程回落 chat。底座残留目前只有调查过程，不能作为合格覆盖。该派发按基础设施失败记账，不伪装成已通过的实质复核。

最终：MiMo rc=124；DeepSeek chat rc=0 / NEEDS_MORE_INFO / degraded，合格覆盖为 0。控制器 rc=0 仅代表至少一腿产出，不代表验收通过。
花名册：`logs/panel-cursor-review-explore-r1-20260918.roster`。

### 发现处置

| 发现 | 处置 | 核查依据 |
| --- | --- | --- |
| 默认认证文件路径、accessToken 是猜测 | 驳回静态未知；真实认证仍待验证 | 已安装 index.js 的 getAuthFilePath 明确按 XDG_CONFIG_HOME 或 ~/.config 拼 cursor/auth.json；认证读取 accessToken。无需增加猜测性搜索路径 |
| CLI 参数与 init/assistant/result 协议只经假 CLI 验证 | 驳回“仅假 CLI”的前提；保留真实冒烟 | 接手直接读取已安装 index.js 与 7021.index.js 核对字段；未声称账号或服务端可用 |
| 发散标题使用 Markdown 时误拒绝 | 本单已修 | 实测 **Direction:** 原本就能过，此子项驳回；**Direction**:、列表和单星标题会失败属实。新增端到端测试先红，放宽标题装饰匹配后 17 项全绿，仍拒绝缺失章节 |
| 非法模型作为 unknown 进入调度候选 | 延期 | 配错模型会浪费一个失败候选，但适配器在调用前明确拒绝，typed coverage 不会误计成功。不是受支持模型换档的阻断；不为此改共享花名册错误策略 |
| export CURSOR_MODEL 会永久污染使用者终端 | 驳回正常使用路径下的结论 | panel-review 在独立进程内 source，子进程 export 不能改调用者终端；当次冻结是避免身份漂移的设计。显式环境变量优先于配置文件已说明 |
| 多个测试夹具固定 composer-2.5 | 延期 | 夹具刻意固定生产默认值之外的独立输入，换生产模型不影响既有基线；当前没有行为失败，不借接入统一测试框架 |

本轮降级报告提出的低风险格式误拒绝已修，其他确认项无新增产品阻断。未追加外审，避免在认证仍缺失时反复花额度；合格外审保持待办，后续在真实冒烟完成后对最终版本复核，预算仍最多一轮复核。
本次格式修复发生在外审之后，旧 observation 不能作为当前交付的合格覆盖；不复用旧绑定、不伪造 PASS。

## 接手回归收据

新增 `CursorTest.test_explore_accepts_markdown_section_labels` 单独运行先红：rc=1，missing explore section: Direction。修复后全套 17 项通过。
runlog 首次在沙箱内无法创建禁网 namespace，rc=78；随后获准在宿主权限下建立禁网环境运行成功。失败收据保留。

runlog: cursor-resume rc=0 commit=dc6f735 dirty=yes at=2026-09-18T07:16:42Z file=tracks/cursor-review-explore/evidence/20260918T071642Z-01-cursor-resume.txt

最终 `git diff --check`、`bin/sync-workflow-docs --check` 均通过。变更继续未提交、未归档；outcome 保持 NEEDS_MORE_INFO。


## 再次接手（2026-09-18 晚间）

断线后的 `panel-cursor-final-20260918` 已于 16:06（北京时间）完成：MiMo 与 Cursor Composer 均为 rc=0 / PASS / complete / 非降级，属于第一次取得合格双家族覆盖的实质复核。此前 MiMo/DeepSeek 超时派发为基础设施失败，保留原记录。
真实日志与 summary/facts 交叉核对：Composer review/explore 均成功；Grok `cursor-grok-4.6-high` review 成功，准确识别加法被替换为减法，返回 BLOCK 是测试预期。离线最终收据为 Cursor 18 项、共享结果 20 项全部通过，source-stable=yes。

### 第一轮实质复核处置

- Cursor 指出认证注释误导：驳回。注释说的是文件登录要求 refresh token，因此采用显式 token 注入；与实现一致，无需改代码。
- Cursor 指出关闭腿的 rc=1 进入全失败合取：驳回。该项是合取中的中性真值，其他任一派出腿 rc=0 即返回成功，不会把成功变失败。
- MiMo 指出新模型家族需加前缀：接受为当前支持边界；同家族换型号仅改配置，未知家族拒跑，不补自动猜测。
- MiMo 指出 malformed 流读至末尾后拒绝：接受现状，失败被如实记录，无误计覆盖。

### 第二轮目的与有限预算

原始用户要求为“还是用 grok”，后续未撤销；此前默认 Composer 是遗漏。修复清单只有 `bin/cursor-model` 改为已实测的 `cursor-grok-4.6-high`、同步默认值说明和收尾任务文案，不改适配器或判卷机制。
该配置变更会使旧交付绑定失效，明确不复用旧覆盖。按原先最多两轮实质复核预算，最后一轮只核验默认配置、家族去重与双模式，并允许报告相关真实缺陷；不追加第三轮追逐措辞。若存在真实阻断，保持未完成。
Grok 与现有 subgrok 都属 xai，因此预算评审只能计一个家族；本轮以 MiMo(xiaomi) + Cursor(xai) 复核。

### 补齐断线遗漏的机器收据

以下 rc=78 是沙箱不能建立禁网 namespace 的环境失败，不是测试通过；其后同项成功收据已在上文记录。

runlog: cursor-resume rc=78 commit=dc6f735 dirty=yes at=2026-09-18T07:16:12Z file=tracks/cursor-review-explore/evidence/20260918T071612Z-01-cursor-resume.txt

runlog: cursor-live-fixes rc=0 commit=dc6f735 dirty=yes final=yes at=2026-09-18T07:42:18Z file=tracks/cursor-review-explore/evidence/20260918T074218Z-01-cursor-live-fixes.txt

runlog: cursor-final rc=0 commit=dc6f735 dirty=yes final=yes at=2026-09-18T07:48:41Z file=tracks/cursor-review-explore/evidence/20260918T074841Z-01-cursor-final.txt

恢复 Grok 默认后的离线回归：Cursor 18 项、共享结果 20 项全部通过；source-stable=yes。

runlog: cursor-grok-default rc=0 commit=dc6f735 dirty=yes final=yes at=2026-09-18T12:59:08Z file=tracks/cursor-review-explore/evidence/20260918T125908Z-01-cursor-grok-default.txt


### 最后复核前发现的真实阻断：后台 worker 生命周期

无环境覆盖的默认 Grok review/explore 均真实成功，但 review 清理出现 Directory not empty。宿主进程检查确认两次调用各遗留一个 Cursor worker-server 和 typescript-language-server，主进程退出后仍活着；这不是输出格式问题。已安装 CLI 源码确认 worker spawn 不负责父进程退出后的清理。
在 adapter 调用边界构造 detached 后代延迟写 marker 的确定性复现：正常退出、超时两种路径均红。修复仅为在已有只读挂载内给 Cursor 加独立 PID namespace（unshare --pid --fork --kill-child --mount-proc），正常退出和超时都由内核结束后代，再清理 HOME。无按进程名全局 kill、无 provider 别名或新框架。
最后一轮实质复核尚未派发；修复并验证此真实阻断后与 Grok 默认值一并送审，仍保持总共两轮实质预算。

runlog: cursor-worker-red rc=1 commit=dc6f735 dirty=yes at=2026-09-18T13:07:23Z file=tracks/cursor-review-explore/evidence/20260918T130723Z-01-cursor-worker-red.txt

runlog: cursor-worker-final rc=1 commit=dc6f735 dirty=yes final=yes at=2026-09-18T13:08:15Z file=tracks/cursor-review-explore/evidence/20260918T130815Z-01-cursor-worker-final.txt

runlog: cursor-worker-final2 rc=0 commit=dc6f735 dirty=yes final=yes at=2026-09-18T13:14:31Z file=tracks/cursor-review-explore/evidence/20260918T131431Z-01-cursor-worker-final2.txt


PID namespace 修复后第一次回归的正常退出子项已绿，但 timeout 子项仍红：原测试按固定延时写 marker，把 timeout 的 10 秒退出宽限期内存活算成了“返回后遗留”。校准为由主测试在适配器返回后触发 gate，子进程只有读到 gate 后才写 marker。这是修正判据时点，保留原红收据，不修改生产宽限期。最终 Cursor 19 项 + 共享结果 20 项全部通过，source-stable=yes。
真机最终探针 `logs/cursor-default-{review,explore}-20260918-worker-fixed`：两个模式均 success=true / family_ok=true，模型为 Cursor Grok 4.6 High、requested/invoked 为 cursor-grok-4.6-high；正常结束后逐一验证临时 workspace 不存在、无相同 HOME 的后台活进程。评审准确 BLOCK 故意的减法错误；发散有完整七段与正确修复方向，其中把 7-2 写成 -5 是模型的算术笔误，主裁明确驳回，不能当代码事实。

最终主自审无已确认阻断；第二轮复核同时覆盖默认配置和后台生命周期修复，派发前预检执行。


## 最终收尾（2026-09-18 晚间）

第二轮实质复核（第三次派发，第一次为基础设施失败）：`logs/panel-cursor-grok-final-20260918`，MiMo(xiaomi) + Cursor Grok(xai) 均 rc=0、完整、非降级、coverage-eligible，且 subject/delivery 相同。两个报告均无待修缺陷；主裁独立核对后接受结论。评审报告全文留在 logs，机器结果随 observations 保存。没有追加第三轮实质复核。

# panel-review 花名册(2026-09-18 21:25:48)task=cursor-grok-default-review
# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
# impact-risk=high requested-budget=2 selected-count=2
# selected=submimo(xiaomi/submimo),subcursor(xai/subcursor)
# escalation=none
# snapshot=head:dc6f735
# 日志:/root/aiwork/logs/panel-cursor-grok-final-20260918.*.log
submimo=PASS(verdict=PASS) subdeepseek=off subglm=off subkimi=off subgemini=off subgrok=off subcursor=PASS(verdict=PASS)


本轮证据：离线 Cursor 19 + 共享结果 20 全绿；此前完整工具链回归与 review-tooling 561/0 已保存，不重复跑。最终真机 review/explore 不设置 CURSOR_MODEL，确认实际默认值为 cursor-grok-4.6-high，两个模式均成功且没有残留 worker/临时目录。修复前失败探针的残留目录也已清理。git diff --check 与工作流文档同步检查通过。

使用：两个调度器已默认接入；以后改 bin/cursor-model 一行同时影响两种模式，CURSOR_MODEL 可临时覆盖。Cursor 与原生 Grok 均为 xai，常规评审预算只计一个家族；发散保留显式启用的通道，PANEL_CURSOR_LEG=off 可关闭。

提交范围仅本次 Cursor 实现、集成、判据和 track。仓库中另有未跟踪的 opendesign 在途任务文件，保持原样，不把它们夹进本次提交。当前整仓交付绑定包含这些工作区文件，因此它们未自行提交前，working/staged 的归档视图不一致；保留本 track 为 active，产品验收完成不伪装成已经归档，也不为这个行政差异再跑模型评审。
