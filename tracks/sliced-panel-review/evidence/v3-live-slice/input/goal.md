# 改动目标
审查本仓最新提交(`git diff HEAD~1..HEAD`):新增 `store.py`(把事件追加写入 JSON lines 日志)
与 `report.py`(读取该日志并给出最近一条事件)。需求:
- `save` 是**追加**写,已有的行必须保留;
- `report.latest` 必须能读 `store.save` 写出来的文件,按时间取最近一条。
