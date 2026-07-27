# Tasks: subglm-agent

- base-ref: n/a(/root/aiwork 非 git 仓)

> 实现由主 agent 直接做(碰 key 注入 + 权限隔离,安全敏感)。
> oracle 文件 tests/test-review-tooling.sh 对员工 off-limits。

- [x] 1. oracle 先行:V9 22 用例(stub claude 捕获 argv+env+stdin);先红确认
- [x] 2. 写 `bin/subglm-agent`;活体冒烟抓到真 bug:变长 --disallowedTools 吞位置参数
     prompt → 改走 stdin,oracle 补 stdin/argv 断言(stub 只录 argv 时抓不到这类)
- [x] 3. panel-review GLM 腿按 `PANEL_GLM_LEG` 选路(默认 agent,缺失/显式 chat 回落),
     日志名保持 .subglm.log
- [x] 4. 全量 oracle 绿:93/93(70 旧 + V9 23)+ retry oracle 绿
- [x] 5. 真实冒烟通过:GLM 自主读仓(逐行引用 pricing.py)、抓到种下的双重计税 bug、
     蜜罐词回显、verdict 正确,50s / rc=0
- [x] 6. verify(fast lane)完成:主审先行(加固=disallow 补 Agent)→ submimo PASS+
     1 LOW+6 gap → 对账采 4 拒 3(依据见 verify.md)→ 主裁 PASS,oracle 终值 97/97
