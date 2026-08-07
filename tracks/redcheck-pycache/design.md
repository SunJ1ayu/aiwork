# Design: redcheck-pycache

- Change: redcheck-pycache
- Status: done

- 规划双出: 不适用 —— 不是新写面,方向只有一个(换完代码就清缓存),
  开放的只有"清多干净"这一个刻度,不值得起 explore。

## Approach

在 `redcheck` 里加一个 `purge_pycache()`,**每次换完代码就调**,一共两处:

1. 退回到 base 之后、跑判据之前(`git checkout <base> -- <impl>` 那一段末尾);
2. `restore()` 里恢复到 HEAD 之后 —— 否则盘上留的是**基线**的字节码,
   下一个人跑判据跑的是退回后那版代码。这和它下面"恢复之后必须重新 build"
   是同一个道理,只是这一份缓存 build 管不着。

范围:`find "$REPO_REAL" -type d -name __pycache__`,排除 `node_modules/` 和 `.git/`。
只删目录本身(`rm -rf`),不去猜哪个 `.pyc` 对应哪个源文件。

**被 git 跟踪的 `__pycache__` 跳过,并且吼一声**(不是静默跳过):删了会把工作树弄脏,
而收尾自证会因此喊"恢复没干净" —— 一个为了正确性加的动作不该反过来触发假警报。
但跳过的那个目录**就是这道防线的洞**,得让人看见。

## Key trade-offs / risks

- **`rm -rf` 进了一个跑在真仓库上的工具**。三层约束把范围钉死:根是 `REPO_REAL`
  (已有的仓外守卫算出来的那个 realpath)、`-type d -name __pycache__`(`find` 默认
  不跟符号链接,`-type d` 也不匹配指向目录的链接)、跟踪的一律跳过。
  代价是可能删掉别人手工放在 `__pycache__` 目录里的东西 —— 接受:那个目录名在
  Python 世界里是保留的缓存目录,不是数据目录。
- **只清 Python**。Node/其他语言的缓存不管。理由是这一单修的是**已经咬过我一口**的
  那条路;没出过事的不在这一单里加(也是本单明确不做的事)。
- 每次红检多一次全仓 `find`。大仓上是几十毫秒量级,相对于跑判据可以忽略。

## Alternatives considered

- **`PYTHONDONTWRITEBYTECODE=1` / `-B`**:只挡"写",挡不住**已经躺在盘上**的那份 ——
  而事故里骗到我的正是残留的旧缓存。且只能作用于 `redcheck` 自己起的进程,
  判据命令里嵌套起的解释器不一定继承。否决。
- **`--invalidation-mode checked-hash` 之类的全局配置**:要求被测仓库配合,
  跨仓不成立。否决。
- **"下次记得清缓存"(写进说明书)**:这正是这一单要否掉的东西 —— 红检是
  "判据到底证明了什么"的唯一机械答案,它自己撒谎的话,判据先行 / 退回红检 /
  死断言闸整套都落在流沙上。自述挡不住惯性,已有前科。

## Test strategy (oracle)

`tests/test-delegate-entry.sh` 新增一幕(commit `60915a4`,**先于修复单独提交**):
造一个两 commit 的小 Python 仓,旧实现 `VALUE = "old!"` 与新实现 `VALUE = "NEW!"`
**同样长度**(复刻事故形状),然后用 `py_compile` 以 **UNCHECKED_HASH**
(PEP 552 —— Python 从不拿它跟源码比对)把新实现的字节码钉成"永远可信",
再让 `redcheck` 退回到旧实现。三条断言:夹具就位 / 退回后判据必须红(rc=0)/
跑完 `git status` 为空。

**红检**:把 `bin/redcheck` 换回 HEAD 那版跑同一份判据 ⇒ **69 passed, 2 failed**
(正是新加的后两条);装上修复 ⇒ **71 passed, 0 failed**。

**这个 oracle 能被什么骗过?**

它把"缓存被信任"钉成了**确定事件**(unchecked-hash),而真实事故是**概率事件**
(mtime 同秒 + 同长度)。所以它证明的是"缓存留在盘上就会被用",**证明不了**
"我这次红检没撞上概率"。也就是说:它挡住的是这一类的**再次发生**,
挡不住"某次红检因为别的原因跑了旧代码"。

第二个洞:它只看 Python。判据跑的是 Node/Rust/别的语言时,这道防线不存在 ——
盘上留着的 build 产物由 `--build` 管,别的缓存**没人管**。这不是本单的缺口,
是**下一次这种事故会从哪儿来**的记号。
