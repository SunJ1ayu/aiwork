# Design: subglm-agent

- Change: subglm-agent
- Status: chosen(底座选型已与用户对齐:Claude Code 壳;ZCode 查证为桌面 ADE 不适用)

## Approach

`bin/subglm-agent review TASK_FILE LOG_FILE [REPO_DIR]`,内部:

1. **key**:`ZHIPU_API_KEY` > `~/.config/zhipu/auth.json`(`{"key":...}`),与 subchat
   同规则(小段复读,不值得为 6 行抽库)。
2. **env 只注入子进程,绝不落盘**:`ANTHROPIC_AUTH_TOKEN=$KEY`、
   `ANTHROPIC_BASE_URL=${ZHIPU_ANTHROPIC_URL:-https://open.bigmodel.cn/api/anthropic}`、
   三个 `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL=${ZHIPU_MODEL:-glm-4.6}`;
   显式 `unset ANTHROPIC_API_KEY`(防主 harness 的真 key 干扰,spike 已见告警)。
3. **驱动**:`cd REPO_DIR && timeout ${ZHIPU_TIMEOUT:-900} claude -p --model sonnet
   --setting-sources project --max-turns ${ZHIPU_MAX_TURNS:-40}` + 读写硬隔离:
   `--allowedTools Read Glob Grep "Bash(git diff:*)" "Bash(git log:*)" "Bash(git status:*)"`
   `--disallowedTools Write Edit NotebookEdit WebFetch WebSearch Task`
4. **prompt**:review 协议头(自主读仓库、findings 带 file:line、结尾必须
   `Conclusion: PASS|BLOCK|NEEDS_MORE_INFO`)+ TASK_FILE 全文。
5. **log**:头部(time/model/base-url/mode)+ claude stdout 写 LOG_FILE;
   **verdict 校验**同引擎语义:无 `Conclusion:` → rc 非零 + 原因到 stderr(log 保留)。
6. `fix` 拒绝(review-only);`-h` usage。

**panel-review 换腿**:GLM 腿命令由 `PANEL_GLM_LEG` 决定——`agent`(默认,且
`bin/subglm-agent` 存在时)→ subglm-agent;`chat` 或 agent 缺失 → subglm。
日志名仍是 `<prefix>.subglm.log`(下游 V3 oracle / 归档习惯不变),log 头部标注实际腿。

## Key trade-offs / risks

- agent 腿耗时 2min → 5-15min(与 submimo 同级),panel 总时长不变(等最慢腿)。
- 烧智谱按量 token(不占 Claude 额度);`--max-turns` 兜底防转圈。
- claude 壳会读 REPO 内 CLAUDE.md(`--setting-sources project`)——对 reviewer 是
  加分项(拿到项目约定);用户全局 settings 不加载,主 harness env 不受污染。
- GLM 在 Claude Code harness 里 tool-calling 可靠性未知 → 真实冒烟 + 失败时
  `PANEL_GLM_LEG=chat` 一键回退。

## Alternatives considered

- **ZCode(智谱官方壳)**:实为桌面 ADE(GUI + 移动端 remote),无无头模式;
  npm `zcode-cli` 为 3KB 个人占名包。不可用。若官方日后出无头 CLI,接口不变换壳即可。
- **OpenCode/Crush 等 chat 原生 agent CLI**:能顺带覆盖 SenseNova,但引入全新依赖面;
  免费级 flash 模型 tool-calling 可靠性存疑。等 subsense 痛点复发再议。
- **引擎内自造 tool-call 循环**:自维护 mini agent 框架,屎山风险最高,不做。

## Test strategy (oracle)

主 agent 拥有,员工禁改。`tests/test-review-tooling.sh` 新增 V9(stub `claude`
置于 PATH 前捕获 argv+env),先红后绿:

1. env 注入:AUTH_TOKEN 来自 env key / auth 文件两路;BASE_URL 默认值;三个
   DEFAULT_*_MODEL=ZHIPU_MODEL;`ANTHROPIC_API_KEY` 被清除(stub 断言其不存在)。
2. 读写隔离:argv 含 `--allowedTools`(含 Read、不含 Write/Edit);
   `--disallowedTools` 含 Write+Edit。
3. verdict 校验:stub 输出无 Conclusion → rc 非零且 log 已写;有 → rc 0。
4. `fix` 拒绝非零;`-h` rc 0。
5. panel-review 换腿:stub subglm-agent + subglm,默认走 agent、
   `PANEL_GLM_LEG=chat` 走 chat、agent 文件缺失时回落 chat(检查 log 内容来源)。
6. 真实冒烟(非 oracle,verify 记录):对一个小 git 仓真跑一次 subglm-agent review,
   确认它真的 Read 了仓库文件且给出 verdict。
