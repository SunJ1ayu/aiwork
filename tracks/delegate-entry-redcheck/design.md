# Design: delegate-entry-redcheck

- Change: delegate-entry-redcheck
- Status: draft

> 不是开放架构分叉(方向由 08-05 的实测账直接指定:入口 + 脚本,不加字段),
> 所以不花 `panel-explore`。但**是新写面**,所以下面那道题照做。

- 规划双出: `/root/aiwork/logs/delegate-entry-dualplan.md`(gpt-5.6-sol 独立出一版,
  明令不许读本 track 工件;我先落盘本文件再派)
  > 这一单正是为"这道题被我自己绕过"而开的,自己再绕一次就没得谈了。

## Approach

### D. `bin/delegate-codex` —— 派活入口

一条命令做四件事,**缺一样就拒发**(exit 2,codex 一次都不启动):

```
delegate-codex --task TASK.md --repo DIR --attack-log PATH \
               --protect PATH [--protect PATH ...] \
               [--model gpt-5.5] [--log PATH] [-- 直通 codex 的其余参数]
delegate-codex --receive RECEIPT.json      # 收货闸①(机械版)
```

1. **`--attack-log PATH` 必给且非空、且必须在仓外**。内容是派活前请第三方
   攻一遍 design + oracle 的记录。仓外的理由和 `panel-review` 的 my-review 闸同源:
   引擎会把未跟踪文件内联进腿的提示词,漏洞清单进了仓就等于**把考卷的洞递给考生**。
2. **`--protect PATH...` 必给**:判卷文件清单。派活时**当场存进回执**,收货时用**同一份**
   跑闸①——不再"人眼把自己那几笔无关改动减掉"(08-05 就是这么退化的)。
3. **自动注入派活三件套**(执行腿看不到本机说明书,规矩不写进任务书就等于不存在):
   ① 判卷文件逐字节 off-limits(把 `--protect` 的路径逐条列进去);
   ② 自检清单:oracle + 回归 + build 全绿才交;
   ③ 不 push / 不 merge / 不归档 / 不装依赖 / 不碰生产系统。
   另外每次都带 `-c project_doc_max_bytes=0`(否则 codex 自动吞 `AGENTS.md` 并向上递归)。
4. **回执** `<log>.receipt.json`(默认落 `/root/aiwork/logs/`,仓外):
   记 repo、**派活那一刻的 HEAD**、protect 清单、attack-log 路径与其 sha256、
   codex 命令行、时间。收货 `--receive` 读它,机械跑闸①:
   - `git diff <派活时 HEAD> -- <protect...>` 必须为空;
   - `git status --porcelain -uall -- <protect...>` 也必须为空
     ——**这半句才是重点**:`git diff` 看不见新增的未跟踪文件,往 `tests/` 里塞一个
     `conftest.py`(autouse fixture)就能让"亲跑全绿"变假绿,而亲读 diff 也照不到它。
   基线用**派活时的 HEAD**(不是 oracle commit):我自己在派活前落的无关欠账已经在基线里,
   不会再把这道闸糊掉。

### E. `bin/redcheck` —— 退回红检

```
redcheck --base REF --impl PATH... --oracle 'CMD' [--build 'CMD'] [--repo DIR]
```

把 `--impl` 那几个文件退回 `--base`(**只退实现,判卷留在 HEAD**),`--build`,跑 `--oracle`,
**要求非零**;然后无条件恢复。绿了(=旧实现也过)就是失败,并把仍然绿的断言名落盘。

- **为什么必须是"真退回"**:08-05 用手写桩红检 ⇒ 恒真前置是绿的,洞没露出来;
  真退回 build 之后才发现那条断言在旧实现上也绿。**桩红不算数。**
- **恢复是本单最危险的动作**(本仓 `dist/` 入库,恢复不干净 = 留下一棵"基线构建的树"):
  - 开工前要求 `--impl` 路径工作树干净,否则拒跑(不替用户猜哪些改动该留);
  - `trap EXIT/INT/TERM` 恢复 + **重新 build**;
  - 收尾**自证**:`git status --porcelain -- <impl 与 build 产物>` 必须为空,不为空就
    大声报错并给出手工恢复命令(部署目标那条规矩的同款:盘上和运行时对不上 = BLOCK)。

## Key trade-offs / risks

- **`--protect` 的强度只等于这份清单**(和 `submimo fix` 同病)。这一单不试图消灭它:
  清单该由主 agent 写。它换来的是"清单在派活时就定死、收货时机械比对",
  而不是收货时凭记忆重建。
- **拒发会不会变成"绕过"**:会,`codex exec` 永远还在。防的是"忘了",不是"故意"。
  这条如实写进抽屉。
- **redcheck 会动工作树**。风险以"开工前干净 + trap 恢复 + 收尾自证"三条兜;
  不用 `git worktree` 是因为本仓 build 依赖 `node_modules`,而 worktree 里补链接
  正是 07 月那次"符号链接被 merge 带回主仓覆盖真目录"的起点。

## Alternatives considered

- **pre-commit hook**:见 proposal 的 Non-goals(两个合法时刻各误报一次)。
- **在 track 模板里再加一格"攻题日志:"**:正是这一单要退场的东西 ——
  自述字段挡不住惯性,08-05 我就是在同一格里把触发条件绕过去的。
- **redcheck 用临时 worktree**:更安全但要解决 `node_modules`,而链接方案有事故史。
  等哪天真被工作树咬到再换。

## Test strategy (oracle)

`tests/test-delegate-entry.sh`(主 agent 亲写,执行腿 off-limits),用假 codex / 临时 git 仓:

1. **拒发**:缺 `--attack-log` / 文件不存在 / 文件为空 / 文件在仓内 → 非零,且
   **假 codex 一次都没被调用**(用调用计数文件证,不看它的自述)。
2. **拒发**:缺 `--protect` → 非零、同样零调用。
3. **注入**:派活成功时,任务书里逐字出现三件套 + 每条 protect 路径 +
   `-c project_doc_max_bytes=0` 在命令行里。
4. **回执**:字段齐全,HEAD 记的是派活那一刻的。
5. **闸①**:protect 文件被改 → 非零;**protect 目录下新增未跟踪文件 → 也必须非零**;
   非 protect 文件改了 → 零(不误报)。
6. **redcheck**:旧实现上 oracle 红 → 通过;旧实现上 oracle 仍绿 → **报失败**并落盘;
   跑完工作树必须回到原状(含 build 产物);oracle 中途异常退出也要恢复。

**这个 oracle 能被什么骗过?**

- 它证明**脚本会拒发**,不证明**我会用这个脚本**。真正的失败形态是我某天直接敲
  `codex exec` —— 判据结构上问不出这件事。接得住它的只有:抽屉把 `codex exec` 那段
  改成指向入口(这一单要做),以及日后 verify.md 里出现的回执路径。**这条写进 verify 的规格自查。**
- 闸① 的用例都在临时仓里跑,证明的是"逻辑对";**真实那次是路径拼错/清单写漏**这类,
  只有下一次真派活才接得住。
- redcheck 的"恢复"用例用的是假 build。真 build(前端 tsc + vite)的失败方式更脏
  (dist 半成品),那一条要在 design-studio 上真跑一次才算数 —— 列进 tasks。
