# Tasks: repo-write-audit

- base-ref: **`281dcbf`**(= 上一单 `deepseek-leg-bash-hole` 的归档 commit)

> ⚠️ 原本写的是 `a617a3dc54031ce28756c3a64341808a439d0699` —— 那是 11:47 **建 track 时**
> 的 HEAD,而上一单 14:02 才归档。按它取 diff 会把上一单**已经过审的改动**一起卷进来。
> 四审就是按 `281dcbf..HEAD` 派的(`PANEL_DIFF_BASE=281dcbf`)。
> (四审 subglm F6 / subdeepseek 也各自独立指出了这一条。)

> 派活:**主 agent 直接干**(理由见 verify.md 的「派给」栏)。

## 第一轮 —— 只读挂载本体

- [x] 探针先行:只读挂载到底可不可行(三条未知一条都不许凭推理)
      → `probe-readonly.sh` + 三份探针收据;C.2「git 会不会挂」被**证伪**(七条读命令全通)
- [x] `bin/ro-repo-exec`:把命令放进"仓是只读的" mount namespace,fail-closed
- [x] 判据 V35(工具层 15 条)+ V36(三条 wrapper 端到端)
- [x] 三条 wrapper 接进只读仓;`submimo fix` **刻意豁免**(执行腿,V36 ④ 对照组盯着)
- [x] `--rw` 指到仓根 ⇒ 响亮警告
- [x] 变异红检:拿掉 `remount,ro` ⇒ 8 条当场红,对照组 20/20 全绿

## 第二轮 —— 自审 + 四审逼出来的

- [x] **自审抓到**:opencode 底座那条腿(GLM)整个在防线外面 —— 判据先行红过(假模型真写进去了),
      修法是把只读段提到两个底座分支**之外**共用,不是抄第二份
- [x] **真 panel 抓到**:kimi 腿被这道防线弄死(运行期 home 在仓内 ⇒ EROFS),
      判据 V38;home 挪出仓 + 仓内则拒跑并说清原因
- [x] **四审抓到**:那个 `--rw <日志目录>` 写口**根本不必要**(腿日志的 fd 在父 namespace
      打开),而且带来两条真 bug(相对路径整仓开闸 / 新日志目录拒跑)⇒ 判据 V37,写口去掉
- [x] **四审抓到**:linked worktree 的真 git 目录在挂载外 ⇒ 腿照样 commit/tag ⇒ 判据 V39 ①
- [x] **四审抓到**:挂载"成功"但没生效没人发现 ⇒ 挂完实测一次,判据 V39 ②
- [x] 判据夹具:观测文件搬出被评审的仓(34 处)—— 它们此前一直在"防线关闭"下跑
- [x] 变异重跑,覆盖新断言(18 红)+ 单独变异 worktree 那一步(精确 2 红)
- [x] 工件债:proposal 与实现方向的矛盾、base-ref、subagent 的注释措辞

## 不在这一单里

- **strace 写审计(方案 A)**:C 挡不住"腿把东西写到仓外再由别的进程搬进来"这类,
  真需要按进程树归因时 A 仍是唯一答案。没作废,记在 `WORKFLOW-DEBT.md`。
- **有动机的对手**:namespace 里的 root 能自己 remount。威胁模型写在 proposal,没变。
