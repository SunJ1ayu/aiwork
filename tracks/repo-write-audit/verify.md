# Verify: repo-write-audit

- Date: 2026-08-19
- Verdict: <第二轮四审跑完回填 —— 不许留占位符>

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再跑 panel-review 的全部评审腿,主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes —— 本单全是 bash 工具,**没有 build 步骤**;等价检查是
      `bash -n` 语法 + 判据里 15 条工具层断言真起进程跑 `ro-repo-exec`。
- [x] tests pass —— `bash tests/test-review-tooling.sh` **426 passed, 0 failed**(rc=0),
      且这一遍跑在**最后一次编辑之后**(见下面最末那行收据 `final-green-round4`)。
      ⚠️ 08-19 断线后更正:这一栏原先写的 `405 passed` 是 **16:57 写下的,之后又有 7 个
      commit** —— 典型的「我给的绿是过期的」。作数的只有 `final-green-round4` 那一行。
      收据里唯一一处 `skip` 字样是断言正文 `PASS: panel: PANEL_KIMI_LEG=off skips kimi`,
      **不是**被跳过的闸(老账:「全绿」那句话里不含整块 SKIP)。
- [x] no secrets / unsafe ops —— 新增的写口是 `mount --bind`(在 namespace 内,
      `--make-rprivate` 不外泄);`--rw` 写口最终**为零**(V37 断言);
      没有 push / 没有删文件 / 没有装依赖。

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,收据行原样粘在下面。
⚠️ **slug 是我起的名字,rc 才是机器写的**:下面 `red-v36-integration rc=0`、
`green-v36-wired rc=1` 这种名不副实的行**照原样留着**,不修饰 —— 08-19 上一单的教训
(5 份叫 green- 的其实 rc=1)。判红检有没有真红,看 rc,不看名字。

```
runlog: probe-readonly-mount rc=0 commit=281dcbf dirty=yes at=2026-08-19T06:29:19Z file=tracks/repo-write-audit/evidence/20260819T062919Z-01-probe-readonly-mount.txt
runlog: probe-readonly-mount-v2 rc=0 commit=281dcbf dirty=yes at=2026-08-19T06:30:16Z file=tracks/repo-write-audit/evidence/20260819T063016Z-01-probe-readonly-mount-v2.txt
runlog: probe-logs-writable rc=0 commit=281dcbf dirty=yes at=2026-08-19T06:32:31Z file=tracks/repo-write-audit/evidence/20260819T063231Z-01-probe-logs-writable.txt
runlog: red-v35-readonly rc=1 commit=308934a dirty=yes at=2026-08-19T06:34:44Z file=tracks/repo-write-audit/evidence/20260819T063444Z-01-red-v35-readonly.txt
runlog: red-v35-readonly-v2 rc=1 commit=308934a dirty=yes at=2026-08-19T06:39:14Z file=tracks/repo-write-audit/evidence/20260819T063914Z-01-red-v35-readonly-v2.txt
runlog: green-v35-tool rc=0 commit=303f01b dirty=yes at=2026-08-19T06:44:43Z file=tracks/repo-write-audit/evidence/20260819T064443Z-01-green-v35-tool.txt
runlog: probe-real-leg-readonly rc=2 commit=2efb0d6 dirty=no at=2026-08-19T06:51:03Z file=tracks/repo-write-audit/evidence/20260819T065103Z-01-probe-real-leg-readonly.txt
runlog: probe-real-leg-readonly-v2 rc=0 commit=2efb0d6 dirty=yes at=2026-08-19T06:51:51Z file=tracks/repo-write-audit/evidence/20260819T065151Z-01-probe-real-leg-readonly-v2.txt
runlog: red-v36-integration rc=0 commit=2efb0d6 dirty=yes at=2026-08-19T06:53:51Z file=tracks/repo-write-audit/evidence/20260819T065351Z-01-red-v36-integration.txt
runlog: red-v36-integration-v2 rc=1 commit=2efb0d6 dirty=yes at=2026-08-19T06:58:43Z file=tracks/repo-write-audit/evidence/20260819T065843Z-01-red-v36-integration-v2.txt
runlog: red-v36-integration-v3 rc=1 commit=2efb0d6 dirty=yes at=2026-08-19T07:03:06Z file=tracks/repo-write-audit/evidence/20260819T070306Z-01-red-v36-integration-v3.txt
runlog: green-v36-wired rc=1 commit=18acaec dirty=yes at=2026-08-19T07:08:32Z file=tracks/repo-write-audit/evidence/20260819T070832Z-01-green-v36-wired.txt
runlog: green-v36-wired-v2 rc=1 commit=18acaec dirty=yes at=2026-08-19T07:12:26Z file=tracks/repo-write-audit/evidence/20260819T071226Z-01-green-v36-wired-v2.txt
runlog: green-v36-wired-v3 rc=1 commit=18acaec dirty=yes at=2026-08-19T07:16:42Z file=tracks/repo-write-audit/evidence/20260819T071642Z-01-green-v36-wired-v3.txt
runlog: green-v36-wired-final rc=0 commit=18acaec dirty=yes at=2026-08-19T07:20:25Z file=tracks/repo-write-audit/evidence/20260819T072025Z-01-green-v36-wired-final.txt
runlog: red-rootrw-warning rc=1 commit=e2798be dirty=yes at=2026-08-19T07:24:41Z file=tracks/repo-write-audit/evidence/20260819T072441Z-01-red-rootrw-warning.txt
runlog: green-rootrw-warning rc=0 commit=a8edf65 dirty=yes at=2026-08-19T07:27:46Z file=tracks/repo-write-audit/evidence/20260819T072746Z-01-green-rootrw-warning.txt
runlog: mutation-control-unmutated rc=0 commit=f664d75 dirty=no at=2026-08-19T07:36:12Z file=tracks/repo-write-audit/evidence/20260819T073612Z-01-mutation-control-unmutated.txt
runlog: mutation-ro-removed rc=1 commit=f664d75 dirty=yes at=2026-08-19T07:36:27Z file=tracks/repo-write-audit/evidence/20260819T073627Z-01-mutation-ro-removed.txt
runlog: red-v36-opencode-leg rc=1 commit=082cc60 dirty=yes at=2026-08-19T07:42:25Z file=tracks/repo-write-audit/evidence/20260819T074225Z-01-red-v36-opencode-leg.txt
runlog: green-v36-opencode-leg rc=0 commit=f7f4b93 dirty=yes at=2026-08-19T07:43:46Z file=tracks/repo-write-audit/evidence/20260819T074346Z-01-green-v36-opencode-leg.txt
runlog: green-after-opencode-fix rc=0 commit=f7f4b93 dirty=yes at=2026-08-19T07:43:58Z file=tracks/repo-write-audit/evidence/20260819T074358Z-01-green-after-opencode-fix.txt
runlog: panel-full-rwaudit rc=0 commit=eb7b77b dirty=no at=2026-08-19T07:50:04Z file=tracks/repo-write-audit/evidence/20260819T075004Z-01-panel-full-rwaudit.txt
runlog: red-v37-v38-writehole-home rc=1 commit=eb7b77b dirty=yes at=2026-08-19T08:05:17Z file=tracks/repo-write-audit/evidence/20260819T080517Z-01-red-v37-v38-writehole-home.txt
runlog: red-v37-v38-fixed-oracle rc=1 commit=eb7b77b dirty=yes at=2026-08-19T08:06:26Z file=tracks/repo-write-audit/evidence/20260819T080626Z-01-red-v37-v38-fixed-oracle.txt
runlog: red-v37-v38-final rc=1 commit=eb7b77b dirty=yes at=2026-08-19T08:07:39Z file=tracks/repo-write-audit/evidence/20260819T080739Z-01-red-v37-v38-final.txt
runlog: red-v37-v38-oracle-v4 rc=1 commit=eb7b77b dirty=yes at=2026-08-19T08:09:03Z file=tracks/repo-write-audit/evidence/20260819T080903Z-01-red-v37-v38-oracle-v4.txt
runlog: green-v37-v38 rc=0 commit=b127eec dirty=yes at=2026-08-19T08:11:36Z file=tracks/repo-write-audit/evidence/20260819T081136Z-01-green-v37-v38.txt
runlog: green-full-after-v37-v38 rc=1 commit=b127eec dirty=yes at=2026-08-19T08:11:48Z file=tracks/repo-write-audit/evidence/20260819T081148Z-01-green-full-after-v37-v38.txt
runlog: full-after-obs-outside rc=1 commit=b127eec dirty=yes at=2026-08-19T08:17:00Z file=tracks/repo-write-audit/evidence/20260819T081700Z-01-full-after-obs-outside.txt
runlog: full-obs-outside-v2 rc=1 commit=b127eec dirty=yes at=2026-08-19T08:20:24Z file=tracks/repo-write-audit/evidence/20260819T082024Z-01-full-obs-outside-v2.txt
runlog: full-repo-subdir rc=1 commit=b127eec dirty=yes at=2026-08-19T08:24:23Z file=tracks/repo-write-audit/evidence/20260819T082423Z-01-full-repo-subdir.txt
runlog: full-green-writehole-removed rc=0 commit=b127eec dirty=yes at=2026-08-19T08:27:38Z file=tracks/repo-write-audit/evidence/20260819T082738Z-01-full-green-writehole-removed.txt
runlog: red-v39-blindspots rc=1 commit=fedb834 dirty=yes at=2026-08-19T08:32:08Z file=tracks/repo-write-audit/evidence/20260819T083208Z-01-red-v39-blindspots.txt
runlog: green-v39-blindspots rc=0 commit=81e3bb8 dirty=yes at=2026-08-19T08:33:16Z file=tracks/repo-write-audit/evidence/20260819T083316Z-01-green-v39-blindspots.txt
runlog: full-after-v39 rc=0 commit=81e3bb8 dirty=yes at=2026-08-19T08:33:25Z file=tracks/repo-write-audit/evidence/20260819T083325Z-01-full-after-v39.txt
runlog: mutation2-control rc=0 commit=b789f2c dirty=no at=2026-08-19T08:36:38Z file=tracks/repo-write-audit/evidence/20260819T083638Z-01-mutation2-control.txt
runlog: mutation2-ro-removed rc=1 commit=b789f2c dirty=yes at=2026-08-19T08:36:48Z file=tracks/repo-write-audit/evidence/20260819T083648Z-01-mutation2-ro-removed.txt
runlog: mutation3-gitdir-removed rc=1 commit=b789f2c dirty=yes at=2026-08-19T08:37:29Z file=tracks/repo-write-audit/evidence/20260819T083729Z-01-mutation3-gitdir-removed.txt
runlog: final-green-after-mutations rc=0 commit=495251a dirty=yes at=2026-08-19T08:49:49Z file=tracks/repo-write-audit/evidence/20260819T084949Z-01-final-green-after-mutations.txt

# —— 08-19 断线后补:verify.md 停在 08:49:49Z,后面这些收据当时没粘进来 ——
runlog: panel-r2-four-legs rc=0 commit=495251a dirty=yes at=2026-08-19T08:55:25Z file=tracks/repo-write-audit/evidence/20260819T085525Z-01-panel-r2-four-legs.txt
runlog: red-v40-panel2-findings rc=1 commit=495251a dirty=yes at=2026-08-19T09:24:06Z file=tracks/repo-write-audit/evidence/20260819T092406Z-01-red-v40-panel2-findings.txt
runlog: green-v40-impl rc=1 commit=01c4797 dirty=yes at=2026-08-19T09:35:14Z file=tracks/repo-write-audit/evidence/20260819T093514Z-01-green-v40-impl.txt
runlog: red-v40-7-8-mutation rc=1 commit=01c4797 dirty=yes at=2026-08-19T09:40:52Z file=tracks/repo-write-audit/evidence/20260819T094052Z-01-red-v40-7-8-mutation.txt
runlog: green-v40-all rc=0 commit=d6797e4 dirty=yes at=2026-08-19T09:44:05Z file=tracks/repo-write-audit/evidence/20260819T094405Z-01-green-v40-all.txt
runlog: mut-m1-guard-call-removed rc=1 commit=b9d68f6 dirty=yes at=2026-08-19T09:48:01Z file=tracks/repo-write-audit/evidence/20260819T094801Z-01-mut-m1-guard-call-removed.txt
runlog: mut-m2-gitdir-probe-removed rc=1 commit=b9d68f6 dirty=yes at=2026-08-19T09:50:52Z file=tracks/repo-write-audit/evidence/20260819T095052Z-01-mut-m2-gitdir-probe-removed.txt
runlog: mut-m3-erofs-noise-back rc=1 commit=b9d68f6 dirty=yes at=2026-08-19T09:53:29Z file=tracks/repo-write-audit/evidence/20260819T095329Z-01-mut-m3-erofs-noise-back.txt
runlog: mut-m4-rootrw-warn-only rc=0 commit=b9d68f6 dirty=yes at=2026-08-19T09:56:18Z file=tracks/repo-write-audit/evidence/20260819T095618Z-01-mut-m4-rootrw-warn-only.txt
runlog: red-v40-3c-mutation rc=1 commit=b9d68f6 dirty=yes at=2026-08-19T10:00:15Z file=tracks/repo-write-audit/evidence/20260819T100015Z-01-red-v40-3c-mutation.txt
(无收据行)20260819T100329Z-01-VOID-断线砍半-final-green-round3.txt —— **断线砍出来的半截**,已改名标 VOID 作废:222 行 vs 完整的 478 行,无 total / 无收尾 / 无 rc。不许当绿用。
runlog: red-v41-oracle-selfexec rc=1 commit=e05ba20 dirty=yes at=2026-08-19T10:17:09Z file=tracks/repo-write-audit/evidence/20260819T101709Z-01-red-v41-oracle-selfexec.txt
runlog: red-v41-oracle-selfexec-v2 rc=1 commit=e05ba20 dirty=yes at=2026-08-19T10:21:50Z file=tracks/repo-write-audit/evidence/20260819T102150Z-01-red-v41-oracle-selfexec-v2.txt
runlog: final-green-round4 rc=0 commit=1311f4d dirty=yes at=2026-08-19T10:25:45Z file=tracks/repo-write-audit/evidence/20260819T102545Z-01-final-green-round4.txt
```

## Review

- lane: **full** —— 这一单造的是**判卷防线本身**(评审腿动没动被评审的仓),
  而且碰权限面(mount namespace、只读重挂、受保护根解析)。硬规矩:碰权限/新写口 → full,
  针孔再薄也不打折。**实际走了两轮 full**(轮 1 在 `eb7b77b`,轮 2 在 `495251a`)。
- 派给: **主 agent 直接干**(开工前判断,收口时回填返工数)——
  ① 判卷面要真起 mount namespace 做系统调用,要现场设计探针、看实际行为,不是照单执行的活;
  ② 核心判断是"防线自己失效时会不会安静降级",属于安全语义,不外包;
  ③ 事后看这个判断是对的:全单最贵的四件事(opencode 腿在防线外、写口多余且带两条真 bug、
     worktree 的真 git 目录在挂载外、挂载没生效没人发现)全是**现场看行为**才冒出来的,
     照单执行的腿一件也碰不到。
  **返工 0 轮 / 自身错误 9 处**(按证据链数,不按印象):
  1. `bin/subagent` 的只读段第一版焊在 claude 那一支里 ⇒ opencode 底座整条腿在防线外
     (**自审抓到**,判据 V36①b 先行红过 —— 假模型真的写进去了,`f7f4b93`→`4fef188`);
  2. kimi 腿的运行期 home 在仓内 ⇒ 这道防线**把一条评审腿弄死了**(EROFS)
     (**真 panel 撞出来的**,轮 1 花名册 `subkimi=FAIL(rc=1)`,`b127eec`→`fedb834`);
  3. `--rw <日志目录>` 那个写口**根本不必要**(腿日志的 fd 在父 namespace 就打开了)
     (四审 subdeepseek F1/F2、subglm F1~F3);
  4. 同一处的真 bug 之一:`dirname` 相对调用方 cwd 解析 ⇒ 从仓根裸文件名调用时**整仓开闸**;
  5. 同一处的真 bug 之二:写口在 mkdir 日志目录**之前**构建 ⇒ 新日志目录直接拒跑(行为回归);
  6. linked worktree 的真 git 目录在挂载外 ⇒ 腿照样 `git commit` / `git tag` 改主仓
     (四审 subdeepseek F3;被推翻的 strace 方案当初**明确计划**保护 `--git-common-dir`,
     只读方案漏了 —— 老账:换方案时把旧方案的保护清单丢了);
  7. "挂载成功"没有实证 ⇒ 最贵的失败形态(安静失效)没人发现(判据 V39②);
  8. 判据夹具的观测文件住在**被评审的仓内**(34 处)⇒ 它们此前一直在"防线关闭"下跑;
  9. 工件债:`proposal.md` 的结论「⇒ 检测,不预防」与实际做的(预防)**互相矛盾**、
     `tasks.md` 的 base-ref 指到建 track 时的 HEAD(会把上一单已过审的改动卷进 diff)。
- 规格自查(读任何 panel 输出之前先答):**规格错的话会错成这样** —— 这道防线保护的是
  "被评审的那个仓",而**判据自己住在另一个仓里**跑;如果真实威胁是"腿写自己能碰到的任何地方",
  那这道防线只挡住了其中一个目录,规格就是**问错了问题**(08-19 上一单正是这个形状:
  实现完全合规格,错在规格问错了问题,而 panel 验不出来)。我怎么发现:轮 1 我把这条
  写进自审 F2 明确请腿挑战;**结论是不改规格** —— 威胁模型写死在 proposal:对面是
  **误伤和提示注入**,不是有动机的对手。有动机的对手在 namespace 里本来就能自己 remount,
  挡不住也不打算挡;而误伤的实际形态就是"腿在被评审的仓里留下东西",那正是这道防线的靶心。
  ⚠️ **这个结论本身仍可能是错的**,它依赖"评审腿没有改判据让自己及格的动机"这个前提;
  前提失效(比如将来把执行腿也塞进 panel)⇒ 规格要重开。
