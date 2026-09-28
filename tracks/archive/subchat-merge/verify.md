# Verify: subchat-merge

- Date: 2026-07-05
- Verdict: PASS

## Mechanical checks

- [x] build passes — `bash -n` on subchat + both shims OK; scripts executable
- [x] tests pass — tests/test-review-tooling.sh **70/70**(43 旧特征化 + V8 27 新,
      先红 14 FAIL 后绿)+ test_submimo_retry.py 全绿
- [x] no secrets / unsafe ops — key 只走 env(argv 仅 auth 文件路径),stray 端点
      变量在 exec 引擎前 unset;无网络/删除/迁移类操作

## Review

- lane: full(动 API-key 读取路径,按用户 07-04 拍板)
- 主 agent 先审:`/root/aiwork/logs/my-review-subchat-merge-0705.md`(repo 外,
  panel 启动后、读取任何员工输出前落盘)。自审产出两项行动:未选中端点变量 unset
  加固 + stray-scrub 断言(oracle 65)。
- panel 日志:`/root/aiwork/logs/panel-subchat-merge-0705.{submimo,subsense,subglm}.log`
- findings 对账(逐条给依据):
  - **MiMo=PASS**。F1 die 前缀变 `subchat:`:真,cosmetic,与我审 known-delta #1 一致,
    查证无任何调用方 grep 该前缀(panel-review/tests)→ 接受不改。F2 跨 provider 端点
    变量未 unset:真(它审的是加固前版本);我在自审中独立标记并已修
    (bin/subchat unset 两行)→ 已修。F3 test gaps:采纳 malformed-auth/-h/timeout,
    多 pattern INCLUDE 与单 pattern 同一循环路径 → 不加。
  - **SenseNova=BLOCK,整份否决**。MEDIUM「`${!v:-default}` 对空串不回默认=行为回退」:
    **假**——实测 `x=""; v=x; ${!v:-default}` → `default`(`:-` 语义=unset 或 null,
    与间接展开正常组合);且已加 oracle 用例 `SENSENOVA_MODEL=` → 仍得
    deepseek-v4-flash,永久钉死。LOW test gaps:有效,已采纳(空串默认/坏 JSON/-h)。
  - **GLM=BLOCK,整份否决**。CRITICAL「set -u 下间接展开未设变量必崩」:**假**——
    实测 `bash -uc 'v=UNSET; ${!v:-default}'` rc=0 输出 default;且 V8 的 `env -u`
    未设用例一直全绿。其建议的 `set +u` 修复反而是倒退。MEDIUM「MIMO_TIMEOUT 未断言」:
    真,已加(默认 900 + ZHIPU_TIMEOUT=123 覆写)。LOW 坏 JSON:采纳已加;LOW 空串
    API_KEY 应报错:误读——空 env key 回落 auth 文件是原脚本既有语义,平价保持;
    LOW die 前缀:同 MiMo F1,接受。
- arbitrated verdict(主裁):**PASS**。两份 BLOCK 均建立在可当场证伪的 bash 语义
  断言上(同族错误:低估 `${!v:-}` 组合语义);三家的 test-gap 类发现是本轮 panel 的
  真实价值,已折进 oracle(63→70)。活体冒烟:panel 本身即通过新垫片链
  subsense/subglm→subchat→engine 真跑成功(subsense/subglm 两腿产出正常报告)。

## Accepted deviations

- die/usage 前缀统一为 `subchat:`(原 `subsense:`/`subglm:`)——无调用方解析该前缀,
  单一错误命名空间更利于排障。
- fix 拒绝文案统一(zhipu 的 Anthropic-endpoint 提示移至头注释)。
- 未测:多 pattern INCLUDE(与单 pattern 同一代码路径)、`*_TIMEOUT`/endpoint 覆写的
  sensenova 侧镜像(zhipu 侧已钉,代码同一行)。
