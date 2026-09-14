# Verify: grok-leg-kimi-model

- Date: 2026-09-14

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

## 主 agent 亲跑/亲读发现(09-14 断线接手,读任何 panel 之前)

- **K1 Kimi 型号:GPT 的说法核实成立。** 官方 Kimi Code 文档(models 页 + What's New 09-11):
  `kimi-for-coding` = K2.8 Preview、context `1048576`、effort low/high/max 默认 max、「所有会员档」。
  模板里 1M + max 与之一致。13:12 真跑 subkimi PASS,会话日志 `model=kimi-for-coding thinkingEffort=max`。
  - **V1 运行时回显(14:10,主 agent 亲跑,非判据收据)**:真跑 subkimi(tiny 仓)rc=0、`Conclusion: PASS`;
    随即用它刷新出的 access token(剩 865s,不手动刷新)GET `https://api.kimi.com/coding/v1/models`,HTTP 200,逐字:
    ```
    {"id": "kimi-for-coding", "display_name": "K2.8 Preview", "context_length": 1048576, "supports_reasoning": true}
    {"id": "kimi-for-coding-highspeed", "display_name": "K2.7 Code Highspeed", "context_length": 262144, "supports_reasoning": true}
    {"id": "k3-256k", "display_name": "K3-256k", "context_length": 262144, "supports_reasoning": true}
    {"id": "k3", "display_name": "K3", "context_length": 262144, "supports_reasoning": true}
    ```
    ⇒ 本账号默认模型名字与 1M 上下文都对得上。
  - 顺带坐实:本账号 `k3` 只有 262144 ⇒ **旧默认「k3 = 1M」是写多了**(官方写 K3 的 1M 要 Allegretto+)。
- **K2 「只改一个模型名」只做到一半(不阻断,文档如实写 + 进修腿单)。** 模板对**任何**模型都声明
  `max_context_size = 1048576`、`support_efforts = ["max"]`;名字单源了,能力声明没有。
  换成本账号的 `k3` 或 highspeed,只改 `bin/kimi-model` ⇒ 配置照样声明 1M/max,与服务端不符。
  V40⑦ 还把 1M 断言成常量 ⇒ 这种错**测试全绿**。`kimi-for-coding` 是会被官方原地换指向的别名(09-11 就换过一次)。
  根治方向(修腿单):能力声明取自服务端 `/models`,而不是模板常量。
- **G1 Grok 登录已死,且 subgrok 的凭证处理可疑。** 13:13 debug:`token refresh HTTP error http_status=400
  oauth2_error=invalid_grant` → `auth.refresh.permanent_failure reason=RefreshTokenRejected`。
  subgrok 每次把 `~/.grok/auth.json` 复制进临时 home、跑完连同刷新后的凭证一起删,**从不回写**;
  原件 mtime 仍是 09-09 16:42(=登录时刻)。
  - 已证伪:「刷新令牌一复用就吊销」—— 09-13 13:12~14:06 同一份原件起跑 6 次、5 次 success。
  - 未分辨:绝对寿命到期(约 4 天,落在 09-13 06:06Z 后、09-14 05:13Z 前)vs 轮换+延迟吊销。
  - 判法(要业主先重登):跑一次后比较临时 home 里 refresh_token 的哈希是否变了;变了 ⇒ 丢弃新凭证是 bug。
  - 09-14 业主「算了先不登录grok了 先跳过」⇒ 本单 **Grok 未真跑**;本会话发起的 device-code 登录已停,
    `~/.grok/auth.json` mtime 与刷新令牌哈希前后一致(没被动过)。
- **G2 未登录的腿在轮换池里(不阻断)。** `panel-review` 只看可执行文件在不在就算可用;被轮到时
  1 秒内失败 → 冷却 21600s + 追加备用腿;连败 3 次停轮换。当前健康池只剩 submimo/subdeepseek(glm/kimi/gemini 已停轮换),
  备用腿够用。本单自己的外审显式 `PANEL_GROK_LEG=off`,花名册里会如实印 off。
- **S1 shell + always-approve 不是 Grok 新开的口子。** 快照可写、原仓只读、工具层不断网、临时 home 里的凭证副本
  shell 读得到 —— 与 submimo(review 模式 `bash_perm = "allow"`)、subkimi(Bash 跑本地测试)同一姿态。
  这份共同姿态的风险(提示注入 → 读凭证 → 外发)不在本单范围,记在这里免得被当成 Grok 独有。
- **T 亲读判据改动(闸① 的补偿,因为判据是 GPT 自己写的)**:现有测试**无删断言、无 skip**;
  唯一改写的断言是 V36 `== 'kimi-code/k3'` → `== <bin/kimi-model 的内容>`,默认值从字面量变成配置,等价泛化。
  其余是给新腿补 env 清洗、桩模型名、金样多一格 `subgrok=SKIP(rotation)`。
- **M 变异(补偿「判据不是我写的」)**:7 个手工变异里 GPT 的测试**漏 3 个** —— 删 `--disable-web-search`、
  删 `stop_reason == end_turn`、删 `is_error is False`(后两者在现有场景里被 `subtype` 顺带挡住,
  删联网搜索开关则完全无人问)。我补判据(`cdd1cc4`:假 CLI 断言联网开关;新增 `cancelled`/`is_error`
  两个「subtype 说 success 但没正常结束」的场景),`mutation-grok.sh` 回放 7 个变异并指名该红的测试:
  补强前 rc=1(3 漏),补强后 rc=0(7 咬)。收据见下。
- **R1 redcheck 自己的 bug(本单顺手修,判卷工具)**:Kimi 那次红检报 rc=5「没红在该红的地方」,
  而目标断言就在输出第 179 行。`printf "$OUT" | grep -qE` 在 `pipefail` 下:grep 命中即退,printf 吃 SIGPIPE,
  管道 rc=141 ⇒ 命中读成没命中。**我第一次单跑复现没复现出来就判「猜测推翻」—— 错的**:竞态单次赢了不证明没有;
  连跑 40 次:管道写法错 11~19 次(`PIPESTATUS=141 0`),here-string 0 次。判据 E1⑦b 先提交(`cdd1cc4`,
  命中后再塞 ~1MB 让竞态变确定)并红,再修(`9e1bed1`)。方向:只误报不假绿;但误报会让人不信红检。
  - 同型排查(不在本单修,记账):`bin/` 下 `| grep -q` 共 18 处。开 pipefail 且方向是**假绿**的只有
    `track-commit-msg` 查版本号 bump 的 4 处(`git diff -U0 -- <版本文件> | grep -qE`,输出通常很小,概率低);
    `_evidence.sh` 3 处只会误报且调用方未开 pipefail;其余是误匹配或输出很小。
- **G4 被审仓里的 Grok 项目配置(文档级确认,未真跑)**:Grok CLI 内嵌文档(`grok-native` strings):项目级
  `.grok/config.toml` 只贡献 `[mcp_servers]`/`[plugins]`/`[permission]`/`[mcp] max_output_bytes`;项目 hooks 与仓内
  MCP/LSP 要过 folder-trust(`trusted_folders.toml`),未信任即静默跳过;`--always-approve` 下「deny 规则、hooks、
  admin lock 仍生效」。subgrok 每次用全新 `GROK_HOME` ⇒ 信任清单为空 ⇒ 被审仓带进来的 hooks/MCP 不启用。
  没找到「always-approve 绕过 folder-trust」的说法,但这是读文档不是实测。项目 `AGENTS.md` 会进上下文(提示注入面),与其他腿同。
- **K3 subkimi 并发渲染竞争(low)**:运行期 home 是共享的,每次按本次模型整份重写 `config.toml`(原子替换)。
  两个**不同** `KIMI_MODEL` 的 subkimi 并发时,后写者会把先跑者要的 `[models."<alias>"]` 覆盖掉 ⇒ 先跑者报
  「model not configured」而失败。旧版种子同时列两种模型,没有这个竞争。默认模型相同的并发(panel-slice)渲染结果逐字节一致,不受影响。
- **G3 凭证副本在强杀后残留(info)**:subgrok 的清理靠 EXIT trap,SIGKILL(`timeout -k`)时不跑 ⇒ 临时 home 里的
  auth.json 副本(600)留在 workspace 根。workspace 根本身就没有过期清扫(现存 392 个残留快照,约 83M,各腿都有)。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再按 impact-risk 预算跑 panel-review；只有特殊控制面
> 才显式 `--all` 做全池评审。最后仍由主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [ ] build passes
- [ ] tests pass
- [ ] no secrets / unsafe ops

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t grok-leg-kimi-model -- <判据命令>
```

红检(实现真退回判据提交 `6734a29`):

```
runlog: redcheck-grok-roster rc=0 commit=2e4ed24 dirty=no at=2026-09-14T06:15:49Z file=tracks/grok-leg-kimi-model/evidence/20260914T061549Z-01-redcheck-grok-roster.txt
runlog: redcheck-kimi-model rc=5 commit=2e4ed24 dirty=yes at=2026-09-14T06:16:15Z file=tracks/grok-leg-kimi-model/evidence/20260914T061615Z-01-redcheck-kimi-model.txt
runlog: redcheck-kimi-model-rerun rc=0 commit=9e1bed1 dirty=yes at=2026-09-14T06:29:22Z file=tracks/grok-leg-kimi-model/evidence/20260914T062922Z-01-redcheck-kimi-model-rerun.txt
```

- `redcheck-kimi-model rc=5` 是 R1 那个 bug 的误报(目标断言在输出里),不是判据红错地方;修好后重跑 `rerun rc=0`。
- `dirty=yes` 均为同目录未提交的前一份收据/observations,实现与判据文件在跑前已提交。

变异(before 跑在 `2e4ed24` 的独立 worktree 上,脚本同一份;after 跑在主树):

```
runlog: mutation-grok-before-oracle rc=1 commit=cdd1cc4 dirty=yes at=2026-09-14T06:25:51Z file=tracks/grok-leg-kimi-model/evidence/20260914T062551Z-01-mutation-grok-before-oracle.txt
runlog: mutation-grok-after-oracle rc=0 commit=cdd1cc4 dirty=yes at=2026-09-14T06:26:43Z file=tracks/grok-leg-kimi-model/evidence/20260914T062643Z-01-mutation-grok-after-oracle.txt
```

全量回归(第一轮外审前,跑前树干净,26 组;收据里 `skip` 出现 0 次)—— **P1 修复之后已过期,见下方第二遍**:

```
runlog: full-regression rc=0 commit=78de17d dirty=no final=yes at=2026-09-14T06:36:05Z file=tracks/grok-leg-kimi-model/evidence/20260914T063605Z-01-full-regression.txt
```

P1(调用方 `GROK_*` 环境变量漏进 CLI)判据先红后绿,变异在修复后重放:

```
runlog: subgrok-env-sweep-red rc=1 commit=17263f4 dirty=yes at=2026-09-14T07:00:24Z file=tracks/grok-leg-kimi-model/evidence/20260914T070024Z-01-subgrok-env-sweep-red.txt
runlog: subgrok-env-sweep-green rc=0 commit=b7ff89f dirty=no at=2026-09-14T07:01:26Z file=tracks/grok-leg-kimi-model/evidence/20260914T070126Z-01-subgrok-env-sweep-green.txt
runlog: mutation-grok-after-env-sweep rc=0 commit=b7ff89f dirty=yes at=2026-09-14T07:01:35Z file=tracks/grok-leg-kimi-model/evidence/20260914T070135Z-01-mutation-grok-after-env-sweep.txt
```

第一版 P1 判据只注入 3 个固定名字 ⇒ 我加变异 M8(只 unset 这 3 个)证明它骗得过,再给判据加随机名 `GROK_PROBE_<hex>`(`120528e`);
M9 = 不关规则文件扫描。修复后第一遍回归(`3444f05`)因判据又改而过期:

```
runlog: full-regression-after-p1 rc=0 commit=3444f05 dirty=no final=yes at=2026-09-14T07:03:52Z file=tracks/grok-leg-kimi-model/evidence/20260914T070352Z-01-full-regression-after-p1.txt
runlog: mutation-grok-m8-before-oracle rc=1 commit=4207d21 dirty=no at=2026-09-14T07:13:26Z file=tracks/grok-leg-kimi-model/evidence/20260914T071326Z-01-mutation-grok-m8-before-oracle.txt
runlog: mutation-grok-m8-after-oracle rc=0 commit=120528e dirty=yes at=2026-09-14T07:15:09Z file=tracks/grok-leg-kimi-model/evidence/20260914T071509Z-01-mutation-grok-m8-after-oracle.txt
```

**最终全量回归**(第二轮外审前,跑前树干净,26 组全 0 失败,收据里 `skip` 出现 0 次):

```
runlog: full-regression-final rc=0 commit=06a814d dirty=no final=yes at=2026-09-14T07:16:59Z file=tracks/grok-leg-kimi-model/evidence/20260914T071659Z-01-full-regression-final.txt
```

R1 判据先红后绿:

```
runlog: delegate-entry-redcheck-longout-red rc=1 commit=cdd1cc4 dirty=yes at=2026-09-14T06:27:41Z file=tracks/grok-leg-kimi-model/evidence/20260914T062741Z-01-delegate-entry-redcheck-longout-red.txt
runlog: delegate-entry-redcheck-longout-green rc=0 commit=9e1bed1 dirty=no at=2026-09-14T06:28:36Z file=tracks/grok-leg-kimi-model/evidence/20260914T062836Z-01-delegate-entry-redcheck-longout-green.txt
```

## Review

- 规格自查(读任何 panel 输出之前先答):规格=「业主要的:Grok 能当评审/规划腿、换模型只改一处」。若规格本身错,
  最可能错在「只改一处」被理解成只管名字 —— 已查实就是这样(K2),Kimi 的能力声明没跟上;
  panel 验不出这种错(V40⑦ 把 1M 断言成常量,测试照绿),只有对照服务端 `/models` 才发现。另一个规格盲区:
  「Grok 能用」的定义里没有登录寿命(G1),离线全绿照样几天后自己死 —— 业主暂不登录,测不了,如实记。
- 腿的花名册(第一轮,subject `6fe7d0d`):
  submimo=PASS(verdict=PASS) subdeepseek=PASS(verdict=PASS) subglm=SKIP(health:dead:FAIL:3) subkimi=SKIP(health:dead:FAIL:3) subgemini=SKIP(health:dead:FAIL:6) subgrok=off
- findings(第一轮,逐条对代码/二进制核实):
  - **P1 成立但原话不成立 ⇒ 顺藤摸出真洞,已修。** 两腿都指 `bin/subgrok` 的 `env -u` 只清 3 个变量。
    DeepSeek 点名 `GROK_AUTH_FILE`/`GROK_LEADER_SOCKET`/`GROK_SESSION`,MiMo 点名 `GROK_API_KEY`/`GROK_LOG_DIR`
    —— **这五个名字在 `grok-native` 二进制里出现 0 次**,CLI 根本不读,原话的后果不会发生。
    但二进制自带文档里有真的:`GROK_FOLDER_TRUST=0`「ungates project hooks along with MCP/LSP」
    (叠加 `--always-approve` = 被审仓代码执行)、`GROK_CODE_XAI_API_KEY`/`GROK_AUTH_PROVIDER_*`(绕过登录副本)、
    `compat.claude.agents/rules`、`compat.cursor.agents/rules`(扫 CLAUDE.md 与规则文件;GPT 只关了 hooks/mcps/skills)。
    另据同一份文档 `compat.claude.agents` 管 `~/.claude/` 具名文件 ⇒ **修复前 Grok 会把业主的 `/root/.claude/CLAUDE.md`
    读进上下文**(`compat.codex.*` 文档写明 inert,不扫 `~/.codex`)。
    本机 `env` 与 profile 里 `GROK_*` 为 0 个 ⇒ **当下不可利用**;沙箱边界 + 高代价 + 改动小 ⇒ 本单修:
    判据 `17263f4` 注入调用方变量、要求到不了 CLI 且四项扫描为 0,红(收据)→ 修 `b7ff89f` 清掉所有继承的 `GROK_*` → 绿。
  - **P2 AGENTS.md 会进 Grok 上下文(DeepSeek 应修)⇒ 部分采纳。** 二进制文档确认读 `<repo-root>/AGENTS.md`、`<cwd>/AGENTS.md`,
    没找到关断开关;CLAUDE.md/规则扫描已随 P1 关掉。DeepSeek 说「codex 不同」属实(`project_doc_max_bytes=0`),
    但 subdeepseek 自己的底座腿 `bin/subagent:450` 用 `--setting-sources project`、MiMo/GLM 的 opencode 系也读 AGENTS.md
    ⇒ 除 codex 外是共有姿态,归 S1,不在本单。
  - **P3 `num_turns` 收了不用(DeepSeek info)⇒ 接受,记 Grok 上线清单。** CLI 撞轮次时报什么 subtype 离线无法证实;
    假 CLI 用的 `error_max_turns` 是 Claude 兼容 schema 的写法。真登录后跑一次 `GROK_MAX_TURNS=1` 就知道。
  - **P4 here-string 对空行敏感模式(DeepSeek info)⇒ 接受。** `$OUT` 为空时 `^$` 由不中变中;`--must-fail` 空匹配本身无意义,仓内无此用法。
  - **P5 `set -- "${GATE_ARGS[@]}"` 未守护(DeepSeek info)⇒ 接受。** bash 5.2 无碍;仅 bash<4.4 且空参数时崩。
  - **P6 KIMI_MODEL 正则对显式 home 也生效(DeepSeek info)⇒ 有意收紧,接受。**
  - 两腿对 Q1(假 complete)、Q2(c)(只读覆盖整棵进程树)、Q3(渲染旧路径)均无发现,与我自审一致。
    MiMo 表格里「cancelled 用例 is_error=True」写错了(实为 is_error=False、stop_reason=cancelled),不影响结论。
- arbitrated verdict (主裁): 第一轮后改了交付(P1),第一轮覆盖不再对应归档的树 ⇒ 需第二轮 high 复核同一 subject 后再裁。

## Accepted deviations

- <接受的非关键偏差 + 原因 + 影响范围,或 None>
