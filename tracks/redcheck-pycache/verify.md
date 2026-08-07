# Verify: redcheck-pycache

- Date: 2026-08-08
- Verdict: <PASS | BLOCK | NEEDS_MORE_INFO>

## Mechanical checks

- [x] build passes —— 不适用(纯 bash 工具,无 build 步)
- [x] tests pass —— **以下是粘的机器输出,不是我的转述**:

```
$ bash tests/test-delegate-entry.sh        # 判卷一(含新加的三条)
  PASS: E1: 夹具就位(缓存里存着新实现的字节码)
  PASS: E1: 退回后判据跑的是**盘上的源码**,不是残留的 .pyc(否则假绿说它是死判据)
  PASS: E1: 跑完盘上没留下 .pyc 缓存(git status 空)
=== total: 71 passed, 0 failed ===

$ git show HEAD:bin/redcheck > bin/redcheck && bash tests/test-delegate-entry.sh   # 红检
  PASS: E1: 夹具就位(缓存里存着新实现的字节码)
  FAIL: E1: 退回后判据跑的是**盘上的源码**,不是残留的 .pyc(否则假绿说它是死判据)
  FAIL: E1: 跑完盘上没留下 .pyc 缓存(git status 空)
=== total: 69 passed, 2 failed ===

$ bash tests/test-review-tooling.sh      → === total: 272 passed, 0 failed ===
$ bash tests/test-hooks-installed.sh     → === total: 4 passed, 0 failed ===
$ bash tests/test-track-guard.sh         → === total: 27 passed, 0 failed ===
$ bash tests/test-submimo-fix-oracle.sh  → === total: 17 passed, 0 failed ===
$ python3 tests/test_submimo_retry.py    → ALL RETRY ORACLE CHECKS PASSED
```

- [x] no secrets / unsafe ops —— 见下,`rm -rf` 是本单唯一的危险面,单独审。

## Review

- lane: full
  > 触发的是"**写口语义扩张**":`redcheck` 本来只删 `--impl` 指到的那几个路径
  > (窄、且是用户自己列的),这一单把 `rm -rf` 的范围扩到**全仓扫出来的目录**。
  > 范围从"清单"变成"搜出来的",针孔再薄也不打折。
- 派给: 主 agent 直接干 —— 改的是**判卷防线本身**(红检),外包等于让考生改考场规则;
  判卷不起服务、28 行、无外部依赖,起一条腿的开销大于收益。
- 规格自查(读任何 panel 输出之前先答):
  规格 = "换完代码就把 Python 字节码缓存清干净"。**它可能错在两处**:
  ① **范围过窄** —— 只清 Python。判据跑 Node/别的语言时同一种谎照样能讲,
  而这一单装完之后我会**以为红检干净了**,那是比现在更危险的状态(已写进 design 的
  "能被什么骗过")。发现方式:下次红检结论反常时先问"这语言有缓存吗"。
  ② **范围过宽** —— `rm -rf` 扫全仓。真删错了 panel 也未必看得出(它只验实现合不合规格),
  接得住它的是判据里那条"跑完 `git status` 为空"和跟踪文件跳过的告警。
- 腿的花名册: <把 `<日志前缀>.roster` 里那一行原样粘过来>
- findings:
  - <...>
- arbitrated verdict (主裁): <...>

## Accepted deviations

- <接受的非关键偏差 + 原因 + 影响范围,或 None>
