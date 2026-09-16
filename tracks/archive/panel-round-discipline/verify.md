# Verify: panel-round-discipline

- Date: 2026-09-16

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再按 impact-risk 预算跑 panel-review；只有特殊控制面
> 才显式 `--all` 做全池评审。最后仍由主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes(bash -n:panel-review / 判据均通过)
- [x] tests pass
- [x] no secrets / unsafe ops(改动只有打印与判据;不新增写口、不联网)

**机器打印的**(不是我的转述):

```
runlog: redcheck-cquote-and-blindspots rc=0 commit=d71f310 dirty=yes at=2026-09-16T07:20:14Z file=tracks/panel-round-discipline/evidence/20260916T072014Z-01-redcheck-cquote-and-blindspots.txt
runlog: aiwork-full-suite-r2 rc=0 commit=d71f310 dirty=yes at=2026-09-16T07:20:35Z file=tracks/panel-round-discipline/evidence/20260916T072035Z-01-aiwork-full-suite-r2.txt
runlog: redcheck-round-readout rc=0 commit=598a3c4 dirty=yes at=2026-09-16T06:45:14Z file=tracks/panel-round-discipline/evidence/20260916T064514Z-01-redcheck-round-readout.txt
runlog: aiwork-full-suite rc=0 commit=598a3c4 dirty=yes at=2026-09-16T06:46:30Z file=tracks/panel-round-discipline/evidence/20260916T064630Z-01-aiwork-full-suite.txt
runlog: redcheck-untracked-column rc=0 commit=b8b36fc dirty=yes at=2026-09-16T06:58:33Z file=tracks/panel-round-discipline/evidence/20260916T065833Z-01-redcheck-untracked-column.txt
runlog: aiwork-full-suite-final rc=0 commit=b8b36fc dirty=yes at=2026-09-16T06:58:49Z file=tracks/panel-round-discipline/evidence/20260916T065849Z-01-aiwork-full-suite-final.txt
```

- **红检两遍,都是"真退回实现再跑",不是桩红**:
  第一遍退回 `186eed0`(完全没有实现)⇒ 26 条里 16 红;
  第二遍退回 `598a3c4`(**带 bug 的第一版实现**)⇒ 精准红 5 条,正是新加的 R3b(3)+R3c(2),
  其余全绿 —— 这一遍证明的是**新断言真咬得住那个 bug**,不只是"判据没空转"。
- 总跑两遍 rc=0,26 套判据全 0 failed(含新套件 26/0、workflow-docs 37/0)。
- 新判据已登记进 `bin/rust-check-review-tooling` 清单 —— 不登记就是孤儿脚本,这仓踩过。
- `sync-workflow-docs --check` rc=0;`cmp` 逐字节确认源与部署副本一致。
  force 同步之前先 diff 过:部署副本 == 我改之前的源,漂移**全部**来自本次改动。

## Review

- 规格自查(读任何 panel 输出之前先答):**这份规格最可能错在"位置"上,不是"内容"上。**
  读数打印在**派活那一刻**,而"要不要再来一轮"是我在**读完腿的报告之后**决定的 ——
  中间隔着我最想再确认一次的那段时间。若规格错了,它会错成:读数每轮都打印、我每轮都看见、
  然后照样开第 5 轮,而所有断言全绿。**断言接不住这件事**;能接住它的只有下一次多轮单的账
  (下一单若又超过三轮,回来看这条规矩是不是放错了位置)。这条已具名记账,不假装解决了。
- 腿的花名册: <见 .roster,粘>
- 腿的花名册(第 1 轮,原样粘自 .roster):
```
# impact-risk=high requested-budget=2 selected-count=2
# selected=submimo(xiaomi/submimo),subdeepseek(deepseek/subdeepseek-agent)
# escalation=conflict(no-healthy-spare)
# snapshot=head:b8b36fc
submimo=PASS(verdict=PASS) subdeepseek=PASS(verdict=BLOCK) subglm=SKIP(health:cooldown:rate_limit) subkimi=SKIP(health:cooldown:rate_limit) subgemini=SKIP(health:dead:FAIL:6) subgrok=SKIP(health:cooldown:rate_limit)
```
> 🔴 **两腿冲突且无健康替补**(GLM/Kimi/Grok 限流、Gemini 死)⇒ 第 1 轮这一次 panel
> **不能满足 high 的归档覆盖**(冲突的 eligible PASS/BLOCK 不补预算)。这不是可以绕的,
> 归档资格要靠第 2 轮重新取。

- findings(第 1 轮,**每条我都自己复现过才认**):
  - **F1 读数内容在中文名下是错的**(成立,已修)。不带 `-z` 的 `git diff --name-only` /
    `ls-files --others` 把非 ASCII 路径 C-quote 成 `"\344\270\255..."`;我在临时仓实测复现。
    而这份文件名清单的**唯一用途就是给我看**。本仓 `track-guard` 早就用 `-z` 躲过这件事 ——
    新读数是唯一没跟上的地方。判据 R-cn 4 条钉住,红检退回旧实现精准红这 4 条。
  - **F2 轮数 glob 没判据**(成立,已补 R2b)。我亲手复现:把 `*panel-review*.json` 放宽成
    `*.json`,原 26 条**照样全绿**。决定"第几轮"的那个数字原来完全没被问过。
  - **F3 "比工作区还是 HEAD"没判据**(成立,已补 R3d)。同样亲手复现:改成 `$base HEAD`
    原 26 条照样全绿 —— 夹具每处改动都先提交了,"脏工作区"这个最常见状态没被问过。
  - **F4/F5 我把保证说大了**(成立,已修)。交付投影**豁免**本 track 的 `verify.md` /
    `observations/*.json` / `evidence/` runlog 收据 / `decision.json` 裁决位 / `tasks.md` 勾选位
    (`_review_delivery.py:66-89`,我自己读过)。原文"动仓里任何一个文件指纹就变"是错的。
    🔴 **这是本机「我给的保证比实际大」的第三次复发**,三次都是被造反例/读代码抓到的。
    抽屉与 design 现在逐项列出豁免清单,并据此给出窄第三条路。
    🔴 **两腿在这条上正面冲突**:submimo 判"没有第三条路"(它把第三条路理解成"按目录排除
    指纹射程"并正确否掉,但**漏看了豁免清单已经存在**),subdeepseek 判"有"。
    **我不是投票收场,是去读那 20 行代码**,采信 subdeepseek。
  - **F6 规矩②的自检没落点**(成立,已修):答案写进本文件 findings —— verify.md 正好在
    豁免清单里,写它不作废绑定,所以这个落点是免费的。
  - **F7 本单没自我适用规矩③**(成立,已修):proposal 写明上限 2 轮。立规矩的单自己不守是坏样板。
  - **F8 design 与实现漂移**(成立,已修):"只数成功轮"与实现相反(死腿轮照样计数);
    R6 承诺过没交付,现已补成真断言(submimo 也独立提了同一条)。
  - **具名记账、本单不修**(规矩②自检:说出它在业主那边长什么样):
    - **F9 第三态(默认开、要显式 opt-out 的闸)**:业主那边长什么样 = **无**(这是我这边的
      工作流,业主看不见)。但它会影响他的交付速度:多一道口子=每轮多一次打字。
      规矩本身还没被任何真实多轮单检验过 ⇒ 先用打印跑一单再决定。进下一单待办。
    - **读数时序**(打印在派活那一刻,决定在读完报告之后):业主那边长什么样 = 我仍然多烧一轮
      额度、他多等一轮。接不住,只能靠下一次多轮单的账。已在 design 具名。
    - **产品文件搬进 tests/ 会消失在 tests/ 桶**:业主那边 = 我可能据此误停、漏审一次真改动。
      靠"其它桶列文件名"兜一半,另一半靠我看清单。
    - **12/8 截断硬编码、python3 缺失时静默走"读不出来"**:业主那边 = 无可见影响。低危记账。

- 腿的花名册(第 2 轮,原样粘自 .roster):
```
# escalation=none
# snapshot=head:d71f310
submimo=PASS(verdict=PASS) subdeepseek=PASS(verdict=PASS) subglm=SKIP(health:cooldown:rate_limit) subkimi=SKIP(health:cooldown:rate_limit) subgemini=SKIP(health:dead:FAIL:6) subgrok=SKIP(health:cooldown:rate_limit)
```

- findings(第 2 轮):两腿均 PASS,确认第 1 轮三条机械发现**都真修好了**、四条新断言
  变异可咬无恒真、`-z` 改法没引入功能缺陷。subdeepseek 另提 8 条,**全是文档精度与判据
  健壮性,无阻断**。逐条处置如下(🔴 其中多条**只能就地记在这里**:改 design.md / 判据 /
  实现都会动交付指纹、作废刚拿到的第 2 轮绑定,而本单上限 2 轮已用尽 —— 这正是规矩①
  说的"先别改,记进下一单",本单自己第一个撞上它):

  - **r2F1 成立(中)`design.md:35` 仍写 `git diff --name-only <head_oid>..HEAD`**,而实现自
    `598a3c4` 起比的是**工作区**(R3d 正为钉这件事而加)。我 F8 自称"design 与实现对齐",
    实际只改了 Key trade-offs 那节,Approach 那节漏了。**更正在此备案**:以实现为准 ——
    读数比的是 `<base>` 到**工作区**,不是到 HEAD。design.md 的那句话是错的,下一单改。
  - **r2F2 成立(中)`design.md:80-82` 的"兜一半"理由不成立**(腿实测):文件名**只列"其它"桶**,
    所以"产品逻辑搬进 tests/"这个形状下文件名一次都不出现,兜的是 0 不是一半。
    **更正在此备案**:这条泄漏目前**一点都没兜住**。下一单要么给 tests/ 桶也列名,
    要么把这条记账的措辞改准。
  - **r2F3 成立(低-中)「任何未跟踪文件」仍然说大了** —— 同一类病第 4 次。腿实测:被
    `.gitignore` 命中的未跟踪文件**不进指纹**(投影走 `git add -A`,不带 `-f`)。
    **更正在此备案**:准确说法是「任何**未被 .gitignore 排除的**未跟踪文件」。下一单改抽屉与 design。
  - **r2F4 成立(低)含换行的文件名会被打成两行**(`-z` 之后原样打印)。本仓 `track-guard:24`
    的 `shq()` 是现成解法。极低频,下一单。
  - **r2F5 成立(低)豁免清单把"散文记录"和"绑定的机器事实"并列**:`observations/*.json` 本身
    不进指纹,却是归档闸读 `delivery.digest` 的输入端 ⇒ 清单读起来像授权手改它。
    **"措辞类修正"这个限定词挡住了它,但下一单要加一句「机器事实(observations)不许手改」。**
  - **r2F6 成立(低)且最该认**:F9 的"已记进下一单待办"当时只住在一份**未跟踪的评审简报**里 ——
    和我刚立的规矩②"自检留在脑子里等于没有"是同一个毛病,只是换了个口袋。
    ⇒ **现在把待办落在本文件下方"下一单待办"一节**(verify.md 进 git、随 track 归档、grep 得到)。
  - **r2F7 成立(低)`tests/...sh:239-241` 前置没断言**:那两句 `cp` 的源若取空,R2b 会静默空转
    (当前实现下取得到,所以变异 B 咬得住)。下一单加一条"目录里确有 3 份 observation"的断言。
  - **r2F8 不成立(已做)**:它说 verify.md 的收据块比当前状态旧一轮 —— 那两份新收据在派活**之前**
    就已写进本文件的工作区版本(腿读到的是 HEAD 快照)。现已随本轮一起提交。

## 下一单待办(r2 溢出,规矩③:本单上限 2 轮已用尽)

- [ ] design.md Approach 节:`<head_oid>..HEAD` → 比工作区(r2F1)
- [ ] "搬进 tests/" 那条记账改准,或给 tests/ 桶也列文件名(r2F2)
- [ ] 抽屉与 design:「任何未跟踪文件」→「任何未被 .gitignore 排除的未跟踪文件」(r2F3)
- [ ] 文件名打印走 `shq()` 式引号化,盖住换行(r2F4)
- [ ] 豁免清单加一句「机器事实(observations)不许手改」(r2F5)
- [ ] R2b 补前置断言:那两份额外 observation 真的造出来了(r2F7)
- [ ] F9:把"默认开、要显式 opt-out 的闸"作为读数的第三态重新评估(先用打印跑一单看账)

- arbitrated verdict (主裁): **PASS**。
  依据:判据 36 条全绿且**三次红检都是"真退回实现"**(186eed0→16 红 / 598a3c4→精准 5 红 /
  b8b36fc→精准 4 红),每一次都红在目标断言上;aiwork 总跑三遍 rc=0(26 套全 0 failed);
  源与部署副本逐字节一致、`sync-workflow-docs --check` 零漂移;第 2 轮两个不同家族一致 PASS
  且无冲突(`escalation=none`,绑定 `d71f310`)。
  第 1 轮三条机械发现我**全部亲手复现**后才认并修完;两腿冲突那条我**读代码定案**,不投票。
  第 2 轮 8 条全是文档精度/判据健壮性,已逐条备案并落成下一单待办。
  🔴 **仍然最弱的两处,不假装解决**:规矩②靠我的诚实(机器只能要求我把答案写进 verify.md,
  不能验证答案真不真);读数的时序接不住"读完报告之后我照样再开一轮"——
  **真正的检验是下一次多轮单的账**,不是本单的绿。

## Accepted deviations

- <接受的非关键偏差 + 原因 + 影响范围,或 None>
