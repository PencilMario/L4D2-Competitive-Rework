# RatingPro 每次结算日志

## 最终需求
- 每次正式地图结算后创建独立日志，不再等待四图。
- 保留现有下半场结束结算、延迟及重复事件防护逻辑。
- 文件名使用 `ratingpro_YYYYMMDD_HHMMSS_序号.log`，检查同名文件防止覆盖。
- 文件位于 `addons/sourcemod/logs/`，头部包含当前地图、时间和快照编号。
- 当前真人玩家的数据表与 `sm_rt` 共用格式化函数，包含 N/A 分支。
- 原有四槽评分算法保持不变，仅改变落盘频率。

## 实现与边界
- 正常及无评分数据分支均在保存快照后调用日志输出。
- 复用 `logger.inc` 原始写入接口，以 2048 字节缓冲格式化，绕开其默认 512 字节缓冲且不增加时间等级前缀。
- 创建失败记录 SourceMod 错误，不影响原有结算广播和查询。
- 仅修改源码及测试，不覆盖现有 optional 插件产物。

## 验证
- `python -m unittest discover -s tests -p 'test_l4d2_round_ratingpro*.py'`：30 项通过。
- SourcePawn 1.12.0.7230 编译成功；有一条来自现有 `halflife.inc` 的弃用警告。
- 编译输出位于系统临时目录 `l4d2_round_ratingpro_logging.smx`。
- 游戏服务器实测尚未执行：需验证连续两次正式结算产生不同文件，检查地图名、完整数据表及 N/A 玩家输出。
