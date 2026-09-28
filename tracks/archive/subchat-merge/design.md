# Design: subchat-merge

- Change: subchat-merge
- Status: chosen(非开放分叉——方案 07-04 已拍板,不花 panel-explore)

## Approach

`bin/subchat <provider> <mode> TASK_FILE LOG_FILE [REPO_DIR]`,通用逻辑一份,
provider 差异收进一个 `case` 小表:

| 维度 | sensenova | zhipu |
|---|---|---|
| env 前缀 | `SENSENOVA_` | `ZHIPU_` |
| 默认模型 | `deepseek-v4-flash` | `glm-4.6` |
| 端点形态 | base URL → `MIMO_BASE_URL`(默认 `https://token.sensenova.cn/v1`,env `SENSENOVA_API_BASE`) | 精确 chat URL → `MIMO_CHAT_COMPLETIONS_URL`(默认 `https://open.bigmodel.cn/api/paas/v4/chat/completions`,env `ZHIPU_CHAT_COMPLETIONS_URL`) |
| auth 文件默认 | `~/.config/sensenova/auth.json` | `~/.config/zhipu/auth.json` |
| REVIEW_LABEL | `subsense-review` | `subglm-review` |

- 前缀化 env(`*_MODEL` / `*_TIMEOUT` / `*_API_KEY` / `*_AUTH_FILE` / `*_INCLUDE`)用 bash
  间接展开 `${!var:-default}` 读取,变量名对外一个不改。
- key 逻辑与现状逐字对齐:env key 优先,否则从 auth 文件 `{"key":"..."}` 读,空 key 硬错。
- `set -f` 包住 INCLUDE 展开(V2 的教训),只写一遍。
- fix 模式:统一拒绝并指向 `submimo fix`(zhipu 的 Anthropic-endpoint 备注保留在注释/提示里)。
- `subsense` / `subglm` 变成 `exec "$(dirname "$0")/subchat" sensenova|zhipu "$@"` 垫片
  (含 shebang 共 3 行左右),CLAUDE.md 与 panel-* 零改动。

## Key trade-offs / risks

- 间接展开比两份平铺稍隐晦,但换来单点修复;provider 表是纯数据,读起来仍然直白。
- 动 key 读取路径 → verify 走 full lane(panel-review),按用户 07-04 拍板。
- V2 oracle 把垫片单独拷进 stub 目录跑,重构后垫片依赖同目录的 subchat——测试需连带拷贝,
  这是部署不变量("bin/ 整体成套")的显式化,先红后绿。

## Alternatives considered

- 两份文件继续平铺 + 靠纪律双写:已经失败过一次(`set -f`),不选。
- 直接删掉 subsense/subglm 让调用方改用 subchat:要动 CLAUDE.md、panel-review、
  panel-explore、记忆若干处,收益为零,不选。

## Test strategy (oracle)

主 agent 拥有,员工禁改。全部在 `tests/test-review-tooling.sh`:

1. 既有 43 用例全绿(特征化:对外行为不变)。V2 需改为连带拷贝 subchat(改前先跑,确认
   重构会让旧 V2 红,即测试确实咬人)。
2. 新增 V8(subchat 自身,stub 引擎捕获 env/argv):
   - 未知 provider → 非零退出 + 报错提及支持列表;
   - sensenova 腿:`MIMO_BASE_URL`、`MIMO_MODEL=deepseek-v4-flash`、`REVIEW_LABEL=subsense-review` 正确注入;
   - zhipu 腿:`MIMO_CHAT_COMPLETIONS_URL`、`MIMO_MODEL=glm-4.6`、`REVIEW_LABEL=subglm-review` 正确注入;
   - auth 文件回退:`*_API_KEY` 未设时从 `*_AUTH_FILE` 的 JSON 读 key 注入 `MIMO_API_KEY`;
   - fix 模式两个 provider 都拒绝(非零);
   - `subglm` 垫片端到端(镜像 V2 的字面 glob 断言,证明垫片链路完整)。
3. `python3 tests/test_submimo_retry.py` 保持绿(引擎未动,防误伤)。
4. 真实冒烟:panel-review 收口本身就会真跑 subsense/subglm 两腿,即活体验证。
