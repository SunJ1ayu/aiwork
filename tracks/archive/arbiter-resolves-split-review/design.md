# Design: arbiter-resolves-split-review

- Change: arbiter-resolves-split-review
- Status: decided(4c 挑战后改方案;原方向保留在下方「挑战前的方向」供对照)

## Goal-to-design check

- 当前行为 → 拟改变的行为:
  - 事实:`_review_result.summarize_results` 把同 run 同 subject 合格腿里同时有 PASS 与 BLOCK 记 `conflict=True`;
    `track-record` 的 `qualifying_review_groups` 丢掉所有 conflict 组 ⇒ 归档 `observation.review_budget` BLOCK,ledger 记 `review_budget:N` 缺口。
    两家都 BLOCK 不算 conflict ⇒ 主裁能裁。
  - 拟改:conflict 组若在 decision.json 里有**完整**的主裁裁决记录,则视为合格组;否则照旧。
  - 用户(业主)要的是:分裂由主裁判断,判能过就写清理由和证据。我推导的:「每条意见」「证据要能在仓里查到」「写记录不作废绑定」。
- 检查深度与触发事实:改的是归档闸(判卷控制面)的放行条件,且改变「主裁能否推翻腿」这条信任契约 ⇒ 4c 第三行命中,
  做一次不同家族的独立方案挑战(能读仓库的腿)。
- 关键前提:
  - P1:裁决记录放在 decision.json `outcome` 下、交付投影把它去掉,不会让没有这个字段的旧记录指纹变化
    (⇒ 正在跑的别的单的绑定不受影响)。可证伪:对现有 decision 跑新旧投影比字节。
  - P2:「证据存在」可以只靠路径检查做到,不需要机器读懂理由;路径限定仓内相对路径(不许绝对路径、`..`、/tmp)。
  - P3:只有 PASS 裁决需要这份记录;BLOCK/NEEDS_MORE_INFO 归档本来就不查覆盖。
  - P4(最危险):这条放行口会不会变成「一句话推翻 BLOCK」的新形态 —— 机器挡得住的只有「没写 / 漏腿 / 证据指向空气」,
    挡不住写得敷衍。补偿:ledger 公开标出裁过的分裂 + 业主能读 verify.md。
- 完全实现仍可能失败:
  - 主裁每次分裂都照模板敷衍几句 + 随便指一个存在的文件 ⇒ 结构全绿、实质就是一句话推翻。
  - 腿其实抓到真缺陷,主裁误判驳回 ⇒ 缺陷发出去(现行闸下会逼出一轮重派,也许就被抓回)。
  - 主裁先写好裁决、再重派到分裂为止(重抽)—— 记录绑定 run_id + subject,重派出新 run 旧记录就不作数。
- 独立意见与核实(原文 evidence/20260924-design-challenge-grok.md,Grok 4.7 High / xai,读取核查过没碰我的方案):
  - G1「每条意见」机器查不了:腿的结果只有 verdict 一个结论字段(`bin/_review_result.py:80` TOP_KEYS),意见只在仓外日志里 ⇒
    我原方案的 findings 清单是**查主裁自己写的清单**,列一条稻草人 + 非空理由 + 任意现存路径就过 = 一句话推翻。**核实属实,改方案**。
  - G2 证据「存在且在仓内」会被豁免文件满足:verify.md 整份跳过、runlog 收据跳过,评审后新写的都能当证据。**属实**(`bin/_review_delivery.py:66-90`)。
  - G3 日志有指纹锁:`evidence.ref` + `evidence.digest`,归档时 `eligibility_reasons` 重读文件比 digest(`_review_result.py:675-687`)⇒
    「摘录必须是那家日志的字面子串」可机检。**属实,采纳**。
  - G4 重抽:之后另派一轮全 PASS 仍可单独成组归档,先前 BLOCK 留在影子里 —— **今天就如此,非本单引入**,本单不改(见未解决项)。
  - G5 CLAUDE.md「冲突时追加第三腿」破不了冲突(同组多一腿仍同时有 PASS/BLOCK)。**属实**,本单顺带改文档说法。
- 未解决项:G4(重抽到全 PASS)今天就开着,本单不扩大也不收;记延期,业主要收再开单。
  机器仍判断不了摘录是否就是那条阻断、理由对不对(G1 的剩余面)——靠 ledger 公开 + 业主读 verify.md。

## Approach(定稿,挑战后)

`outcome.split_resolutions`(可选;缺省 = 没有)。每项绑定一个分裂组,逐条 BLOCK 腿写驳回:

```json
{"run_id": "<panel run>", "subject_digest": "sha256:…",
 "legs": [{"name": "submimo", "log_digest": "sha256:<该腿 evidence.digest>",
           "rebuttals": [{"quote": "<该腿日志里的原话,字面子串>", "disposition": "rejected|deferred",
                          "reason": "…", "evidence": ["bin/x.py:773", "tracks/<t>/evidence/<runlog 收据>.txt"]}]}]}
```

归档(verdict=PASS)逐项查,任何一项不成立都 BLOCK 并打印 rule/path/actual/expected:
- 目标:(run_id, subject_digest) 恰是一个合格分裂组(有冲突);指向不存在的组或不冲突的组 ⇒ `split.target`。
- 腿:`legs[].name` 集合 == 该组合格 BLOCK 腿集合(不漏、不多)⇒ `split.legs`;`log_digest` == 该腿 `evidence.digest` ⇒ `split.log_digest`。
- 驳回:每腿 ≥1 条;`quote` 去首尾空白后非空、且是该腿日志(按 ref 读,digest 已由资格检查核过)的字面子串 ⇒ `split.quote`;
  `disposition` ∈ {rejected, deferred};`reason` 非空 ⇒ `split.rebuttal`。
- 证据:每条 ≥1 项;仓内相对路径(不许绝对、`..`、符号链接),可带 `:行` 或 `:起-止`(不越出文件行数);
  必须是**被审交付里的已跟踪文件**,即排除本单的 verify.md / decision.json / tasks.md / observations/;
  runlog 收据例外:`tracks/<t>/evidence/<run_id>.txt` 且 observations 里有同 run_id 的 runlog execution_finished ⇒ `split.evidence`。
- 通过的分裂组与不冲突组一样算合格组(家族数门槛照旧)。两家都 BLOCK、超时/无结论/降级/跨 run/同家族 —— 谓词不动。
交付投影:`outcome` 置空 verdict 之外**删掉** `split_resolutions` 键(老记录没有这个键 ⇒ 字节不变)。
ledger:`resolved_split_groups` 计数;`review_budget` 缺口用同一谓词。文档:抽屉与 CLAUDE.md 的冲突句改成「分裂由主裁按记录裁」。

## 挑战前的方向(已被 G1/G2 推翻,留作对照)

decision.json schema v2 `outcome` 允许一个可选字段 `split_resolutions`(缺省 = 没有):

```json
"outcome": {
  "verdict": "PASS",
  "split_resolutions": [
    {"run_id": "<panel run>", "subject_digest": "sha256:…",
     "legs": [
       {"name": "submimo",
        "findings": [
          {"summary": "…", "disposition": "rejected|deferred", "reason": "…",
           "evidence": ["bin/ds_credential.py:773", "tracks/<t>/verify.md", "tracks/<t>/evidence/<runlog>.txt"]}
        ]}
     ]}
  ]
}
```

归档(verdict=PASS)时:每个 conflict 组若有 run_id+subject 精确匹配的记录,且 `legs[].name` 集合 == 该组合格 BLOCK 腿集合、
每腿 ≥1 条意见、每条有非空 summary/reason、disposition 在枚举内、evidence 非空且每项是存在的仓内相对路径(可带 `:行号`)
⇒ 该组算合格组。多余/过期记录(指向不存在的 run、非 conflict 组)⇒ BLOCK(防止拿旧记录混)。
交付投影:`outcome.verdict` 置空之外,再**删掉** `outcome.split_resolutions`(不加键,老记录字节不变)。
ledger:新增 `resolved_split_groups`,`review_budget` 缺口判定用同一个谓词。

## Key trade-offs / risks

- 放行口只查结构,理由质量靠人;换来的是分裂不再逼出重派。风险见 P4。
- 裁决记录在 decision.json(机器字段唯一落点)而不是 verify.md 散文:散文机器查不了(自述型字段挡不住惯性)。

## Alternatives considered

- 分裂时追加第三家、看多数:抽屉明写「不靠多数票」;且第三家同样可能分裂,还是重派。
- 分裂一律算覆盖、只要主裁 verdict=PASS:= 一句话推翻,回到 09-22 之前。
- 裁决记录放 verify.md 的约定格式行:能免指纹,但解析散文脆,且与「机器字段只写 decision.json」冲突。

## Test strategy (oracle)

`tests/test-track-record.sh`,紧挨现有 R10 `conflict` 用例(它不写记录 ⇒ 仍须 BLOCK,原样保留):
- S1 完整记录(摘录是 BLOCK 腿日志里的原话、证据指向已跟踪文件带行号 + 一份有 observation 的 runlog 收据)⇒ 归档过;ledger `resolved_split_groups=1`、无 review_budget 缺口。
- 各种缺 ⇒ 各自 BLOCK 且 rule 对得上:S2 摘录不在日志里 / 空摘录;S3 漏腿、多写一条腿;S4 log_digest 对不上;S5 run_id 或 subject 对不上、指向不冲突组;
  S6 缺 reason、disposition 越界、rebuttals 为空;S7 证据为空、不存在、绝对路径、`..`、行号越界、指向本单 verify.md / decision.json、
  收据没有对应 observation;S8 verdict=PASS 但日志被改(digest 变)⇒ 该腿不合格(现有资格检查兜住)。
- S9 两家都 BLOCK 不写记录 ⇒ 仍按现状由 verdict 决定(不回归);S10 schema:dispatch 阶段带 split_resolutions 形状错 ⇒ 报 field.*。
- 交付投影(`tests/test-review-tooling.sh` 或 python 单测):无该键的 decision 新旧投影字节相同;评审后加该键不改 digest;改 decision 其它字段改 digest。
- 红检:判据先单独 commit,在未改实现上 S1/S* 相关用例红(新 schema 字段被 exact_object 拒)。

**这个 oracle 能被什么骗过?** 结构全对而理由敷衍、摘录挑一句无关原话 —— 机器接不住(G1 剩余面),只能靠 ledger 公开 + 业主读 verify.md。
