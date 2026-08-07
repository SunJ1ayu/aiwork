# Verify: redcheck-pycache

- Date: 2026-08-08
- Verdict: PASS(四审修复轮之后)

## Mechanical checks

- [x] build passes —— 不适用(纯 bash 工具,无 build 步)
- [x] tests pass —— **以下是粘的机器输出,不是我的转述**:

```
# ── 第一轮(修复 + 首批判据)────────────────────────────────────────────
$ bash tests/test-delegate-entry.sh                                  → 71 passed, 0 failed
$ git show HEAD:bin/redcheck > bin/redcheck && bash tests/…          → 69 passed, 2 failed   ← 红检

# ── 第二轮(四审三条发现各配一幕 `21ff9ab`,再修 `fb8dc6d`)──────────
$ bash tests/test-delegate-entry.sh          # 判据落盘、修复之前        → 76 passed, 3 failed
$ bash tests/test-delegate-entry.sh          # 修复之后                  → 79 passed, 0 failed
$ git show HEAD:bin/{redcheck,delegate-codex} 换回旧版再跑              → 76 passed, 3 failed   ← 红检
$ 把 restore() 里的 purge_pycache 单独摘掉再跑   # ⑭ 的独立红检          → 71 passed, 6 failed

# ── 全量回归(第二轮修复之后)──────────────────────────────────────────
$ bash tests/test-review-tooling.sh      → === total: 272 passed, 0 failed ===
$ bash tests/test-hooks-installed.sh     → === total: 4 passed, 0 failed ===
$ bash tests/test-track-guard.sh         → === total: 27 passed, 0 failed ===
$ bash tests/test-submimo-fix-oracle.sh  → === total: 17 passed, 0 failed ===
$ python3 tests/test_submimo_retry.py    → ALL RETRY ORACLE CHECKS PASSED
```

- [x] no secrets / unsafe ops —— `rm -rf` 是本单唯一的危险面,四审专门攻过(见 findings)。

## Review

- lane: full
  > 触发的是"**写口语义扩张**":`redcheck` 本来只删 `--impl` 指到的那几个路径
  > (窄、且是用户自己列的),这一单把 `rm -rf` 的范围扩到**全仓扫出来的目录**。
  > 范围从"清单"变成"搜出来的",针孔再薄也不打折。
- 派给: 主 agent 直接干 —— 改的是**判卷防线本身**(红检 + 派活闸),外包等于让考生改考场规则;
  判卷不起服务、无外部依赖,起一条腿的开销大于收益。
- 规格自查(读任何 panel 输出之前先答):
  规格 = "换完代码就把 Python 字节码缓存清干净"。可能错在两处:
  ① **范围过窄** —— 只清 Python;装完之后我会**以为红检干净了**,那比现在更危险。
  ② **范围过宽** —— `rm -rf` 扫全仓;真删错了 panel 也未必看得出。
  事后看:①仍成立(见 Accepted deviations);②被 F1 打中了一半(不是删错,是代价)。
- 腿的花名册:
  `submimo=PASS subdeepseek=PASS subglm=off subkimi=FAIL(rc=1)`
  > subkimi 是**额度上限**(`403 usage limit`)中途死的,不是没话说 ——
  > 它半截日志里已经独立走到了 F5 那一处,并且自己写出了修法正则。
  > **失败腿的日志也要读**,这一次它是三方独立命中里的一方。
- **反锚定的一个洞(这次实测到的,记在这儿别忘)**:panel-review 派发时打印了
  `WARNING: anchor leak` —— 引擎会把仓里的**未跟踪文件**内联进腿的提示词,
  而 `tracks/redcheck-pycache/verify.md` 当时就是未跟踪的,里面有我的"规格自查"两条。
  我的 findings 文件在仓外(闸挡住了那一份),但**这一格没挡住**。
  ⇒ 腿说出"范围过宽/过窄"这两个方向时,不算独立命中;F1/F3/F5 那种带实测的具体形状才算。
- findings:
  - **F5 / M6(高,已修)子串匹配 vs 路径成分** —— `delegate-codex` 放行 `__pycache__`
    写成 `grep -v '__pycache__'`,`tests/__pycache__-evil/conftest.py`、
    `tests/x__pycache__conftest.py` 都能穿过闸①第三臂。而放行的安全性论证
    (PEP 3147:没有源码的 .pyc import 不进来)对这种文件根本不成立 —— 它不是字节码。
    **三方独立命中**(我 / subdeepseek F5 / subkimi 半截日志)。
    修:`grep -vE '(^|[ /])__pycache__/'` 两处;判据 ②c 两幕,修前红。
  - **F3(中,已修)pathspec 默认按 glob 解释** —— `git ls-files -- "$rel"`。
    腿举的例子(跟踪 `a1/__pycache__/*.pyc`)**我核对下来不成立**:带通配符的
    pathspec 不做目录前缀展开。但换成**已跟踪的同名普通文件**(`a1/__pycache__` 是 file)
    就确定复现:误判"被跟踪" ⇒ 跳过不清 ⇒ 残留旧字节码 ⇒ **假绿**。
    修:`:(literal)`;判据 ⑮,按我核对过的形状写,修前红。
  - **F1(中,已修)全仓 find 的代价** —— 仓内 `.venv` 的 `site-packages` 里
    `__pycache__` 数以千计,全被删且**每个目录起一个 git 进程**;`.git`/`node_modules`
    原来只是过滤结果、没有 `-prune`,照样全走一遍。不是正确性问题,是**慢到没人愿意跑**,
    而"没人跑"是这道防线最终失效的方式。
    修:`-prune` 剪掉 `.git`/`node_modules`/`site-packages`/`.tox`/`.nox`
    (剪 `site-packages` 而不是猜 venv 目录叫什么);跟踪判断改成**一次** `git ls-files`。
  - **F2(低,已修)注释过时** —— "本脚本唯一的破坏性动作"这句话,在本单之后是错的,
    而它正是后来的审者判断危险面的锚点。已改成"两处之一"并写清第二处的边界。
    **这条我自己漏了**,是腿抓的。
  - **F4(中,已修)判据缺了事故的另一半** —— "还原之后在干净树上假红"此前零判据;
    一个"只清一次 + `PYTHONDONTWRITEBYTECODE=1`"的实现也能让原来三条全绿。
    修:判据 ⑭,让判据自己每跑一次就把当前源码钉成 unchecked-hash 字节码,
    跑完再**只 import 不编译**地验一次。它对现在的代码本来就是绿的 ⇒
    **单独红检过**(摘掉 `restore()` 里的 `purge_pycache` ⇒ 当场红)。
  - **F6(info,不改)** —— 仓不 ignore `__pycache__` 且 `--build` 会编译 Python 时,
    restore 的 build 会重新写出缓存 ⇒ 收尾自证 rc=9。**改动前就存在**,非本单回归。
  - **submimo**:PASS,六个区域逐条走完,结论与代码相符,但**没有一条孤发现**;
    它在 F5 那一处明确写了"PEP 3147 保证安全、可接受" —— 与另外三方相反,**判错了**。
    (它读的是同一份 diff。全票 PASS 不降低标准,这一条是现成的例子。)
- arbitrated verdict (主裁): **PASS**。
  四审提出的可执行发现共 5 条(F1–F5),**全部成立、全部已修**,每条要么配了新判据、
  要么本来就有判据钉住;F6 属既有行为,记录不改。修复轮之后 79/0,红检 76/3。
  两轮里**没有一条发现是"腿说了但我没验"**就采纳的 —— F3 的具体形状我核对下来与腿说的不同,
  按我验证过的形状重写了判据。

## Accepted deviations

- **只清 Python**。Node/Rust 的字节码/增量缓存能讲一模一样的谎(jest cache、tsbuildinfo),
  本单不扩范围。**风险不是"没装",是"以为装全了"**:红检结论反常时,第一问该是
  "这语言有缓存吗",不是"是不是抖"。目前这句只住在注释和这份 verify 里,
  **没有机械钩子** —— subdeepseek 建议在 `--help` 或输出里留一句,记在下面的欠账里。
- **`purge_pycache` 是全仓,而判据只钉得住"换完代码就清"**(subdeepseek F4 后半)。
  一个只清 impl 所在目录的实现也能让全部判据绿。保持全仓是**保守选择**:
  剪枝之后代价可忽略,而"哪些目录的缓存不可能撒谎"是需要推理的判断 ——
  这一单挨咬的正是这类推理。理由写在函数注释里。
- **开工前就躺在盘上的未跟踪缓存会被删掉**(用户的东西,不是本次红检造的)。
  可接受:`__pycache__` 是 Python 保留的缓存目录名,重生成自动且无损。
  已核对**不会造成假警报**:收尾自证 `comm -13` 只报"新增"的行,删除让行消失。
- **欠账(不在本单做)**:① 红检输出里留一句"非 Python 判据的缓存没人管";
  ② `delegate-codex` 的 `__pycache__` 例外现在有三处独立实现(收货一臂、派发一臂、
  mtime find 一处),形状已经不一致过一次 —— 该收成一个函数。
