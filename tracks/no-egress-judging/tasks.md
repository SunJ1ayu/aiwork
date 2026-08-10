# Tasks: no-egress-judging

- base-ref: d5ee9a1cfdb09e6e51f9eb5751eca8b1b031d260

> 委托 submimo fix 时:主 agent 先写失败测试(oracle)并 commit,再把窄范围实现
> 交给它;oracle/测试文件对它 off-limits;~2 次红了收回主 agent。

- [x] T0 事故定性:真凶 = OpenClaw cron `537198fb`「评审工具链-每周防锈」(每周一 08:00,
      payload 是 **command 型**、不经 OpenClaw 的模型路由),超时 300s → **自动重试 3 次**
      → 4 轮 × 3 次真实 kimi。证据在 proposal.md 的表里。
- [x] T1 判据 `tests/test-no-egress.sh`(C0 反空转 + N1..N7),并进 `SUITES`。
- [x] T2 红检:实现落地前必须红,且**红在断言上不是炸在报错上** —— 10 红 / 7 绿,
      收据 `evidence/20260810T073032Z-01-oracle-red.txt`。
      顺带当场抓到我自己一条假绿(N4 的匹配词 `egress` 命中的是**守卫的文件路径**,
      不是解释)—— 已改掉,注释留在判据里。
- [ ] T3 实现 `tests/_no-egress.sh` + `tests/_no_egress.py`:
      自举进 `unshare -n`(拉起 `lo`)、按 `/proc/1/ns/net` 判是否已隔离(**不认环境变量**)、
      隔离不了就拒跑(fail-closed)、每次实测一次出口。
- [ ] T4 把守卫引入现有 7 个套件的头部(bash 6 个 + python 1 个)。
- [ ] T5 判据转绿(`bash tests/test-no-egress.sh`,runlog 落收据)。
- [ ] T6 **回归**:总跑 `bin/rust-check-review-tooling` 全绿,且
      **kimi 日志今日调用数在总跑前后不增**(这才是用户眼里的成功,判据本身接不住)。
      对账命令:`grep -c "kimi-code starting" /root/aiwork/kimi-review-home/logs/kimi-code.log`
      跑前跑后各取一次。
- [ ] T7 verify:lane full(碰**钱**),四审 + 主裁。
- [ ] T8 归档。

## 出了本单范围、单独记账(不在这里做)

- cron 超时重试把一次事故放大成 4 倍:`537198fb` 的 `timeoutSeconds=300` + 自动重试 3 次。
  出口堵死后套件会重新变快(25s 挂起 → 秒级失败),这条不再触发,但**放大器还在**。
  → 记进 `/root/aiwork/tasks/`,下次碰 cron 时一起处理。
