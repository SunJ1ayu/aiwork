# Tasks: subchat-merge

- base-ref: n/a(/root/aiwork 非 git 仓;diff 供 panel 用时以文件快照/手动 INCLUDE 代替)

> 实现由主 agent 直接做(shell + key 路径,量小且安全敏感,不值得 submimo fix 一轮往返)。
> oracle 文件 tests/test-review-tooling.sh 对员工 off-limits。

- [x] 1. oracle 先行:改 V2(连带拷贝 subchat)+ 新增 V8(20 用例);确认先红(14 FAIL,
     subchat 尚不存在;老 subglm 端到端为绿=特征化基线)
- [x] 2. 写 `bin/subchat`(provider case 表 + 间接展开读前缀 env;`-h` 兼容垫片透传落 $2)
- [x] 3. `bin/subsense`、`bin/subglm` 改为 3 行 exec 垫片
- [x] 4. 全量 oracle 绿:test-review-tooling.sh 63/63(43 旧特征化 + 20 新)+ retry oracle 绿
- [x] 5. verify:主 agent 先审(logs/my-review-subchat-merge-0705.md,自审揪出 unset 加固)
     → panel-review full lane(MiMo PASS;SenseNova/GLM 双 BLOCK 均系 bash 语义误判,
     当场证伪否决;三家 test-gap 采纳,oracle 63→70)→ 主裁 PASS → 归档
