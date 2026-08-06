# Verify: delegate-entry-redcheck

- Date: 2026-08-06
- Verdict: PASS(修复轮之后)

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再跑 panel-review 的全部评审腿,主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes(纯 bash 工具,无构建;`bash -n` 三个脚本全过)
- [x] tests pass(`bin/rust-check-review-tooling` 五套件全绿;本单判据 66/0)
- [x] no secrets / unsafe ops(唯一破坏性动作 rm -rf 已加仓内校验,四审孤发现)

## Review

- lane: full
  > **碰了新写口 / 权限 / auth / 钱 / 数据一致性 → full,针孔再薄也不打折**(硬规矩,别在这降档)。
  > fast = 主+1,中等风险;self = 主自审(闸③ + 截图 + 全量回归),
  > 限纯前端/纯观感、后端一字未动、只新增已过审针孔的调用方。
- 派给: 主 agent 直接干 —— 这一单造的就是**判卷防线**本身(派活闸 + 红检),
  把它外包等于让考生造考场;而且判卷要起临时 git 仓 + 假 codex,窄范围也说不清。
- 规格自查(读任何 panel 输出之前先答):**这套东西证明"脚本会拒发",证明不了"我会用它"。**
  真正的失败形态是我某天直接敲 `codex exec` —— 判据结构上问不出这件事。
  接得住它的只有:抽屉里 `codex exec` 那段已改成指向入口(本单做了),以及**日后 verify.md
  里有没有回执路径**。第二个失败形态:`--protect` 的强度只等于我写的清单,漏列一个就是那个洞;
  这一单没消灭它,只是把清单从"收货时凭记忆重建"挪到"派活时定死"。两条都如实记着,不假装覆盖。
- 腿的花名册: `submimo=FAIL(rc=124) subdeepseek=PASS subglm=off subkimi=PASS`
  (原样粘自 `/root/aiwork/logs/panel-delegate-entry.roster` —— 这一格今天刚上线,
  第一次用就派上用场:submimo 是**超时**,不是通过;subglm 欠费关着。)
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings(主审先落盘在仓外 `scratchpad/delegate-entry-review-my-review.md`,再读腿):
  - **我自己抓的 3 条**(都在读腿之前修完):新文件退回=删掉它、`--impl` 变长写法、
    恢复只 checkout 不够(真 build 才暴露,桩 build 一辈子照不到)。
  - **subkimi【高】孤发现**:`--impl ../x` ⇒ `rm -rf` 删到仓外,而前置检查的 git 报错
    走 stderr、stdout 为空 ⇒ 静默放行,收尾自证同样为空 ⇒ 还打印"已恢复,工作树干净"。
    **不需要攻击者,敲错一个路径就够。**
    ⚠️ 同一处 subdeepseek 判成"低危、预检已挡" —— 我核对代码(`redcheck:59` 没有 `2>&1`),
    **subkimi 对**。两腿判断打架时以代码为准,这次孤腿又是对的那个。
  - **subdeepseek 5 条中危**:恢复 build 失败只告警照常 exit 0;自证只查 `--impl`
    (design 写了"impl 与 build 产物",实现漏了后半句);判卷被 `.gitignore` 藏起来 /
    被挂 `skip-worktree` ⇒ 闸①两臂同时失明;**我的判据 e11 自带 `rm` 通配,把"删掉
    restore 里 git clean"这条回归遮住了**(改完实测:去掉 clean 那步,e11 两条断言变红)。
  - **subkimi 另 2 条**:判据没锁 `-s workspace-write` / `-C`(丢了等于把腿升成全权限);
    D1 全家只断言"非零退出",一个 `exit 2` 的空壳就能全绿 ⇒ 每一幕改成点名"缺的是什么"。
  - 全部中高危已修,判据同步补强(修复前红 7 处),`6b14dd8`。
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): **PASS**。两腿都给 BLOCK,理由成立,我照单修了全部中高危,
  并且**改完之后拿真仓复验**:在 design-studio 上用真 build 跑同一条 redcheck,
  红检通过且 `git status` 为空。判据 66/0,`rust-check` 五套件全绿。
  低危项作为已接受偏差留在下面 —— 都写清了为什么现在不做。
  > **归档时这一条和顶部的 `Verdict:` 都不许还是占位符**,`track-guard` 规矩3 会挡;
  > 没归档但已经合并上线的,`track list` 会打 ⚠️(stage-timer 就这么漏了两个月)。

## Accepted deviations

- **`git clean` 不加 `-x`**(两腿都提:被 ignore 的基线产物清不掉,自证也看不见)。
  **故意不加**:`-x` 会连 `node_modules/` 这类合法的 ignored 目录一起删,
  误删的代价远大于残留。本机 `dist` 入库,这条不发作;换到"构建产物被 ignore"的仓要重新判。
- **TERM 陷阱要等前台命令结束**(subkimi F8):`--oracle 'sleep 30'` 被 TERM 时,
  恢复要等它自然结束;oracle 若彻底挂死,恢复也跟着挂。修法要动进程组,这一单不做,记着。
- **目录级 `--impl` 的"退回"不完整**(subkimi F9):`git checkout BASE -- <目录>` 不删
  HEAD 独有、BASE 没有的文件 ⇒ 红检阶段是混合树。恢复段收拾得干净(E1⑩ 锁的就是这个)。
- **mtime 闸能被 `touch` 绕过**:它防"忘了重攻",不防伪造。双出方案给的内容寻址凭证更强。
- **总跑没有"最低通过数下限"**(subdeepseek F13):某套件被改成只跑 5/40 条仍 exit 0 的话,
  汇总照印绿。加下限等于再存一份数字(和退掉的"第 N 单"同病),暂不加;
  真出过一次再说。
