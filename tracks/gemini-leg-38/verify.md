# 验收

## 派发前

- 自审在读任何评审报告之前落盘在**被审仓库之外**
  (`/root/panel-my-reviews/gemini-leg-38-my-review.md`),裁决 PASS,
  但写明了我自己最大的怀疑:**「业主嫌流程麻烦,而我的方案是把闸放松」= 弱模型最经典的
  失败形态,只是理由体面**,并要求评审腿把这当首要嫌疑去攻。
- oracle 先跑:`bash tests/test-workflow-docs.sh` rc=0(panel-review 也记了一遍 `ORACLE: … rc=0`)。

**第一次派发根本没派出去,而我发完就走了。** `decision.json` 里我把风险因子写成
`judging_defense`,枚举里是 `judging_control` ⇒ 闸 fail-closed 拒发、一条腿都没起,
白等 15 分钟才回头看。⇒ **派发之后第一件事是确认它真的派出去了,不是隔很久才想起来看。**

**反锚定泄漏,如实记账**:`/root/aiwork/tasks/` 里躺着四份**别的 track** 的
`*-my-review.md`(另一个项目 各批),它们是仓内未跟踪文件、会被引擎内联进评审 prompt。
与本单无关,但确实不是"零泄漏",记在这里而不是声称"已反锚定"。

## 花名册(机器写的)

```
impact-risk=high requested-budget=2 selected=2
subdeepseek(deepseek/subdeepseek-agent)=PASS(verdict=BLOCK)
subglm(zhipu/subglm-agent→降级 chat)=rc=1(报告写完了,裁决行没独立成行 ⇒ no verdict)
submimo=skipped(rotation/budget)  subkimi=skipped(rotation/budget)  subgemini=skipped(cooldown:FAIL)
```

subgemini 在冷却里没被派 —— 正好,**它不该审自己这一单**。

## 逐条对账

| 来源 | 发现 | 判定 |
|---|---|---|
| **DeepSeek F1** | 第三处拷贝:`workflow/skills/panel/references/legs.md:127-130` 仍写 3.7 并引 3.7 的选型实测;`test-workflow-docs.sh` 的 W3 给 glm/mimo 钉了文档=代码而 **gemini 没钉** ⇒ 文档错着 36/36 全绿 | **成立,已核到行,已修**(仓里+部署副本+补 W3 那一行,红检过)。**这是本单在治的病本身,而我搜索时停在了前一个文件。** |
| **GLM MEDIUM** | 新 V46② 的 grep **没锚定**:stub_log 存的是含 `-p "$PROMPT"` 的整条命令行 ⇒ 提示词正文含 `--model gemini-` 就算通过;放松后误通过面比钉版本号更宽 | **成立,已修**:假 agy 单独写 `MODEL_ARG=<值>` 行,断言认那一行。红检对照见下。 |
| **DeepSeek F2** | 被拆掉的版本钉子还兼着「面板跑的是不是业主验过的模型」这个没写明的职;3.7 过了埋雷考卷,3.8 只做了"存在+冒烟";**这个取舍不能由放松的受益者自认** | **成立** ⇒ 我停下来问了业主。**2026-09-04 业主拍板:① 就用 3.8,不重考;② 以后 gemini 家族内换档改一行即可,不必走 track。** 已写进 legs.md 与 design.md,记成业主签的字。 |
| **DeepSeek F3** | 假 agy 的 models 输出仍只列 3.7,容易被下个人误读成断言 | **成立,已顺手补上 3.8**。 |
| GLM MEDIUM 2 | tasks.md 里 T7「完整判据全绿」还没跑,而唯一那份收据自述"rc 不作数" | **成立** ⇒ 已跑,见最终收据。 |
| GLM LOW | ok/bad 分支回显用 `grep -o … \| tail -1`,可能与命中的不是同一处 | **成立**,随锚定一起修(现在取的是 `^MODEL_ARG=` 那一行)。 |
| DeepSeek(第 2 问) | 放松后不再能区分「真读了 DEFAULT_MODEL 常量」与「调用里写死了一个 gemini 字面量」 | **成立但接受**:那是"实现有没有绕过常量",不是家族覆盖;M2 变异仍咬得住,风险窄。**记在此处,不装作没有。** |
| GLM(正面回答第 1 点) | **降档通道本来就敞着**(`AGY_MODEL` + V46① 只要 `gemini-` 前缀)⇒ 放松 V46② 没有新增降档通道 | **成立,而且这是我自己没想到的论据 —— 它加强了本单的正当性。** |

## 收据(机器写的,逐字节)

runlog: redcheck-v46-anchor rc=0 commit=ca17209 dirty=yes at=2026-09-04T07:28:11Z file=tracks/gemini-leg-38/evidence/20260904T072811Z-01-redcheck-v46-anchor.txt

runlog: T7-FINAL rc=0 commit=0e56cd4 dirty=yes final=yes at=2026-09-04T07:38:09Z file=tracks/gemini-leg-38/evidence/20260904T073809Z-01-T7-FINAL.txt

最终收据内容:`tests/test-review-tooling.sh` **549 passed / 0 failed**、
`tests/test-workflow-docs.sh` **37 passed / 0 failed**、文档同步一致。

**红检(旧闸对新默认档)**:`evidence/20260904T0613Z-01-redcheck-old-gate-pins-version.txt` ——
旧 V46② 对着 3.8 打红,证明它真的在钉版本号、不是摆设。
🔴 **该收据自述两条不作数**:① 我接了 `| grep`,rc 取的是 grep 的 0 而不是判据的
(**管道吃 rc,本仓第八次**);② 那一跑期间我在编辑同一个 tests/ 文件。
红的证据取自输出内容那一行 FAIL,不取 rc;**最终收据另跑,见上**。

**锚定红检的对照**(`20260904T072811Z-01`):同一份"`--model` 一个都没传、
但提示词正文含 `--model gemini-3.8-flash-high`"的日志 ——
旧断言 **PASS(误通过)**、新断言 **FAIL(正确地红)**。

**变异红检**:`20260904T0730Z-03`(锚定修好之后重跑)**咬住 23 / 漏网 1**,
`[咬住] M2 ⇒ 「V46②」`。

## 敞账

🔴 **V46㉒ 是一条死断言**(与本单无关,已用探针量到真因,不是推的):
它的场景用 `STUB_SILENT=1` 让假 agy 零输出,而**预检 `agy models` 也被静默** ⇒
腿在**预检**就 die,执行**根本走不到** SALVAGE_FILE 那段(在变异行后面插的探针
**一行都没打出来**)。所以它声称测「仓里预埋的同名报告不会被当成模型的结论」,
实际测的是「预检失败会 die」。变异 M24 因此恒漏网。**单独开单修。**

## 主裁

**PASS。** DeepSeek 判 BLOCK 的两条我都认了并修掉/交业主拍板;GLM 那条锚定我认了并修掉。
核心嫌疑(放松=放水)被两条腿各自独立否掉:家族防线(V46① + `bin/subgemini` 运行期闸)
原样健在,新断言经变异证明有牙,且降档通道本来就敞着、本单没有新增。

**本单我自己犯的**:① 派发失败了没回头看,白等 15 分钟;② 管道吃 rc(第八次);
③ **我对 M24 给了一个错误解释,并照着那个解释改了测试数据 —— 改完照样漏网、解释被证伪,
那个改动已撤回**。一个改动做的事和它注释写的理由对不上,就是屎山,哪怕看着无害。
