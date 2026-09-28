# Tasks: glm-flash-single-source

- base-ref: 591d58fd9250aa3efa4d81764fa9e147271ed245

> 委托 submimo fix 时:主 agent 先写失败测试(oracle)并 commit,再把窄范围实现
> 交给它;oracle/测试文件对它 off-limits;~2 次红了收回主 agent。

- [x] 把 Flash 默认与 agent override 行为写成判据，保存旧实现红收据并单独提交
- [x] 删除 agent 的 `OC_MODEL_ID` 第二事实源，让全部 opencode 消费点使用 `MODEL`
- [x] 切换 agent/chat standalone 默认值，更新唯一文档源并同步部署副本
- [x] 跑定向/全量回归与真实 Go/wrapper 冒烟
- [x] 主 agent 独立审、按 high 风险取两家外部评审、主裁并归档
