# Design: grok-leg-kimi-model

- Change: grok-leg-kimi-model
- Status: draft

- 规划双出: 不适用:收货单,方向已由 GPT 实现落地,这里不重选方向;不开新写口语义。

## Approach

沿用 GPT 的实现,不重做:

- **Grok**:`bin/subgrok` 走官方 Grok Build CLI headless(`streaming-messages-json`),
  复用 `_review-workspace.sh`(可丢弃快照)+ `ro-repo-exec`(原仓只读);工具限 read/list/grep/shell,
  关子代理、联网搜索、Plan 模式;`_grok-stream.py` 只把顶层 assistant 文本当报告,
  要求正常完成事件 + 模型身份一致。模型只读 `bin/grok-model`。
  花名册加 `subgrok|xai`,`_review_result.py` 加身份前缀,panel-explore 默认派 Grok。
- **Kimi**:`bin/kimi-model` 一行 `kimi-code/<id>`;`subkimi` 每次从种子模板渲染运行期
  config(把占位符换成 alias 与 API model ID),渲染失败即拒跑(旧版 `|| true`)。

主 agent 这一单只做:分两次提交(判据先、实现后)⇒ redcheck;几处针对性变异;
把查实的局限写进文档;high 外审;归档。

## Key trade-offs / risks

- **K2 能力声明写死**:模板对任何模型都声明 1M + effort=max。今天对 K2.8 成立(服务端已回显);
  换成本账号的 `k3`(262144)或 highspeed(无 effort)就会声明错。不在本单修,文档写明,进修腿单。
- **G1 凭证副本不回写**:subgrok 复制 `~/.grok/auth.json` 进临时 home、跑完删掉,刷新后的新凭证丢弃。
  若 xAI 轮换刷新令牌,登录会被自己消耗。业主暂不登录 ⇒ 本单测不了,文档写明,登录后再判。
- **G2 未登录的腿进了轮换池**:被轮到时 1 秒内失败 → 冷却 + 追加备用腿;连败 3 次自动停轮换。
  代价是几秒和一条失败记录,不挡归档(mimo/deepseek 仍健康)。
- **shell + always-approve**:与 submimo/subkimi 现行姿态一致(快照可写、原仓只读、工具层不断网),
  不是 Grok 新开的口子;这份共同姿态本身不在本单范围。

## Alternatives considered

- 拆开只提交 Kimi、Grok 继续留在工作区:同批文件交错(README/legs.md/测试),留下未提交活
  会让后续每一单归档都要先挪开它 —— 正是业主选「先审完提交」要避免的。
- 默认关掉 Grok 直到登录:要给单条腿加「停放」机制 = 新设计;现有冷却/连败机制已能自限。

## Test strategy (oracle)

判据是 GPT 写的(违反「oracle 主 agent 亲写」,属于事后收货)⇒ 补偿控制:
1. 判据与实现分两次提交,`redcheck` 把实现真退回判据提交,要求判据红、且红在该红的地方;
2. 针对 GPT 测试可能漏看的地方做手工变异(身份校验、子代理/工具文本当裁决、超时映射);
3. 亲读现有测试的改动:无删断言/skip,唯一改写的断言(V36 写死 `kimi-code/k3` → 读模型文件)是等价泛化;
4. 全量回归 `rust-check-review-tooling` 用 `runlog --final` 留收据;
5. Kimi 运行时:真跑 subkimi 后用新鲜 access token 读服务端 `/models`。

**这个 oracle 能被什么骗过?**

- 离线桩全绿,但真 Grok CLI 协议/登录行为不同 —— 只有真跑接得住;本单 Grok 未真跑(业主跳过登录)。
- 测试只断言「凭证副本 600 权限、跑完删除」,不问「刷新后的凭证去了哪」⇒ G1 那种「登录几天后自己死」
  全绿照样发生;只有登录后比对刷新令牌哈希接得住。
- 模板里的 1M 被断言成常量(V40⑦),断言本身就把 K2 焊死了:换一个 262K 的模型,测试照绿、配置照错。
