# Verify: subglm-agent

- Date: 2026-07-05
- Verdict: PASS

## Mechanical checks

- [x] build passes — `bash -n` subglm-agent + panel-review OK,可执行位就位
- [x] tests pass — tests/test-review-tooling.sh **97/97**(70 存量 + V9 27,先红后绿)
      + test_submimo_retry.py 全绿
- [x] no secrets / unsafe ops — key 只进子进程 env(argv 无 key、log 无 key);
      `env -u ANTHROPIC_API_KEY` 防主 harness 真 key 流向智谱端点;绝不写
      ~/.claude/settings.json;读写硬隔离(allowlist=Read/Glob/Grep+只读 git,
      disallow 带 Write/Edit/Task/Agent)

## Live smoke(agent 类 wrapper 的 verify 必做项)

真 key + 种 bug 小仓:GLM 自主 Read 仓库(逐行引用 pricing.py 原文)、抓到双重计税
bug 且失败场景算对、回显任务蜜罐词 PINEAPPLE-42、`Conclusion: BLOCK` 格式正确,
50s / rc=0。**冒烟还抓到 oracle stub 抓不到的真 bug**:变长 `--disallowedTools`
把位置参数 prompt 吞成 tool 名 → prompt 改走 stdin,V9 补 stdin/argv 双断言。
教训入档:argv-录制型 stub 测不出 CLI 参数解析层的集成 bug,活体冒烟不可省。

## Review

- lane: fast(主审 + submimo;新增文件为主、subchat 的 key 老路径未动,不够 full 门槛)
- 主 agent 先审:`/root/aiwork/logs/my-review-subglm-agent-0705.md`(repo 外,读
  submimo 输出前落盘)。自审产出:disallow belt 补 `Agent`(新版 CLI 子代理工具名,
  原只写了旧名 Task);`--setting-sources project` 的项目配置面残余风险以
  "只在自有仓跑 panel"为据接受并记录。
- submimo 报告:`/root/aiwork/logs/submimo-subglm-agent-0705.log` — PASS + 1 LOW + 6 test-gap。
- findings 对账(逐条给依据):
  - LOW「verdict grep 扫全 log 可被任务文件自污染」:观察与我审同源,但已验证
    header 只写任务路径不写内容(bin/subglm-agent header 块),自污染路径不存在;
    其修法(只 grep 模型输出段)对它自己描述的"模型复读协议行"绕过无效 → 修法拒绝,
    局限已在两份 review 记录(与 chat 引擎同级,主裁反正要通读 log)。
  - test-gap 6 条:采纳 4(`Bash(git diff:*)` 模式 / `--model sonnet` /
    `--setting-sources project` / `--max-turns` 上 argv 断言,oracle 93→97);
    拒 2(timeout 124 路径=2 行代码目检 + 需 sleep stub 不值;verdict 绕过场景
    =上一条已裁定的接受性局限)。
- arbitrated verdict(主裁):**PASS**。submimo 无 BLOCK 级发现;活体冒烟是决定性
  证据(端到端真通,盲评之痛根治)。

## Accepted deviations

- verdict gate 的"复读协议行"理论绕过:接受(与 chat 引擎同级;gate 职责=拦空转/
  脱轨 run,真伪由主裁通读把关)。
- `--setting-sources project`:reviewer 会读被审仓的项目配置/CLAUDE.md——收益
  (拿到项目约定)大于风险(panel 只跑自有仓;MCP/hooks 在 -p 默认拒绝语义下无权限)。
- agent 腿耗时 ~1-15min(vs chat 腿 ~1-2min),panel 总时长不变(等最慢腿 submimo)。
- subsense 腿维持 chat + 手动 INCLUDE(无 Anthropic 端点;复发再议)。
