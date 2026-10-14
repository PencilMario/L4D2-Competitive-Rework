# RatingPro 他人查询与控制台数据表实施计划

> 本次只写计划，不修改插件或 smx、不提交代码。后续使用 aegis:executing-plans 逐项实施。

**Goal：** 在 `addons/sourcemod/scripting/l4d2_round_ratingpro.sp` 增加公开查询指令及 `sm_rating`、`sm_rt` 别名，查看其他在线真人的 RatingPro，并通过 `PrintToConsole` 向请求者输出相关数据表；结算时提示使用 `!rating` 查看明细。

**Architecture：** 保存最近一次正式结算的只读快照，按已验证 Steam2 ID 关联玩家。查询只读缓存，不推进历史、不重新计算旧结算结果。

**Tech Stack：** SourcePawn、SourceMod、Python unittest。

**Baseline / Authority Refs：** 用户需求；目标插件 `Timer_PrintBestRating`、`BuildRawRanges`、`GetHistoricalRaw`、`GetEffectiveTankRaw`、`PrintAllClientRatingDetailsToConsole`；`tests/test_l4d2_round_ratingpro_tank_persistence.py`。

**Compatibility Boundary：** 保持权重、历史算法、Tank 回退、章节最佳公告、个人提示和自动服务端明细不变。

**Verification：** 新增源码契约测试、已有测试回归、SourcePawn 编译和游戏服务器验收。

## 1. 事实与默认设计

- 当前插件未注册查询指令；现有 Console 明细函数实际调用 `PrintToServer`，玩家控制台收不到。
- 结算先保存 Tank，再保存四槽历史，然后计算评分。查询不能调用这两个保存函数，否则会重复提交历史。
- 前四维来自历史补齐，Tank 来自当前或历史回退；无 Tank 数据归一化为 4.6。指数 0.75 和五维权重保持原样。
- `ResetRoundStats` 会清空计数和资格标志，下一章直接重算无法可靠复现上次结果。
- 默认查询“最近正式结算评分”，不是实时预测；记录是控制台输出，不意味着数据库或日志文件落盘。实时评分与持久日志不在本计划范围。

## 2. 指令契约

| 输入 | 行为 |
| --- | --- |
| `!ratingpro` / `sm_ratingpro`（参数留空） | 输出全部在线真人，包括自己 |
| `!rating` / `sm_rating`、`!rt` / `sm_rt` | 分别作为 `sm_ratingpro` 的 SourceMod 别名，参数行为一致 |
| `!ratingpro 玩家名` | 查询唯一匹配的在线真人，支持带空格姓名 |
| `sm_ratingpro #123` | 按当前 userid 查询，不是 client 索引 |
| `sm_ratingpro @all` | 与留空参数行为一致 |
| 重名、无匹配、机器人、其他多目标表达式 | 明确报错，不猜测或自动查询全部 |

- 用 `RegConsoleCmd` 注册 `sm_ratingpro`，不要求管理员权限。
- 用 `RegConsoleCmd("sm_rating", Command_RatingPro, ...)` 和 `RegConsoleCmd("sm_rt", Command_RatingPro, ...)` 注册别名，复用同一处理函数；聊天触发形式为 `!rating`、`!rt`。保留 `sm_ratingpro` / `!ratingpro`。
- 参数用 `GetCmdArgString`、`TrimString`、`StripQuotes`；处理后为空或等于 `@all` 时遍历全部在线真人。其他输入用 `ProcessTargetString`，标志为 `COMMAND_FILTER_NO_BOTS | COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_IMMUNITY`，只读查询不受管理员免疫限制。
- 真人请求逐行 `PrintToConsole(requester, ...)`，聊天只向请求者提示查看控制台，不广播、不通知目标。
- client=0 的服务端/RCON 调用通过 `PrintToConsole(0, ...)` 输出，跳过聊天 API。
- enabled 关闭仍可读已有缓存；无快照、身份未验证、上次无资格显示原因及 `N/A`，不伪造 0 分。
- 最佳公告门槛 `g_hMinRaw` 不应阻止查询已有个人评分。
- 每次原有结算流程完成后，向在线真人提示“输入 `!rating` 查看详细数据”；不替代现有章节最佳或个人评分消息，也不重复打印表格。

## 3. 数据表设计

每个目标输出一个完整表块，全员查询输出所有人的完整表块。

| 表 | 字段 |
| --- | --- |
| 元信息 | 快照编号、结算地图与时间、当前 userid/姓名、结算姓名与队伍、状态 |
| 评分 | RatingPro、weighted raw、output/defense/focus/infector/tank 原始分与归一化分 |
| 生还者计数 | siDmg、ciKill、tankDmg、dmgTaken、incaps、deaths、ff、tankupDmg、tankupKill、skeet、level、pop、tongueCut、crown |
| 感染者计数 | dmg、booms、deathCharges、tankDmgUpright、punch、rock、hittable、incap、death |

标注前四维 raw 来自历史补齐，计数来自该次结算；另存 Tank 来源（当前/历史/无数据）。不能声称该次计数单独产生全部历史分，不输出 Steam ID。使用固定格式字符串与 `%s` 姓名参数，显示层清理换行、回车、制表符。分组拆行，避免截断；中文姓名不依赖固定字符宽度对齐。

## 4. 实施步骤

### Task 1：先写失败测试

**文件：** 新增 `tests/test_l4d2_round_ratingpro_query.py`，沿用现有 Path + unittest 风格。

- [x] 测试 `sm_ratingpro`、`sm_rating`、`sm_rt` 都注册到同一处理函数；留空参数/`@all` 全员查询、目标过滤、错误处理、client=0 分支。
- [x] 提取 `public Action Command_RatingPro(int client, int args)` 函数体，断言不调用历史保存、Tank 保存、重置和范围重算。函数提取按花括号计数，不能在首个内层右括号截断。
- [x] 测试 `PrintRatingSnapshotToConsole` 确实使用 `PrintToConsole`，覆盖全部表格字段和无数据状态。
- [x] 测试快照按 Steam2 关联，保存发生在历史提交后，覆盖结算提前返回分支，普通 reset 不清空缓存。
- [x] 执行 `python -m unittest discover -s tests -p "test_l4d2_round_ratingpro_query.py" -v`，确认失败来自缺失功能而非测试语法或路径。

### Task 2：结算时保存完整快照

**文件：** 修改目标插件全局状态、`OnPluginStart`、`Timer_PrintBestRating`。

- [x] 增加 `StringMap g_hLastRatingSnapshot`，以已验证 Steam2 ID 为键；数值用明确字段结构保存，结算姓名另用 StringMap 保存，验证结构与 SetArray/GetArray 编译兼容性。
- [x] 保存第 3 节所有结算字段及有效状态，全局另存快照编号、地图、时间、是否已有结算。
- [x] 保持 `SaveLatestTankRaw(); SaveRoundRawHistory();` 原顺序，随后构建一次原评分范围并生成快照；不新增历史提交。
- [x] 有范围且 `IsEligibleForRating` 成立时复用原 getter、归一化、权重与幂曲线；其他真人保存无数据状态和当时计数。
- [x] 所有结算返回分支都保存快照；全局无数据结算也替换旧快照，低于最佳门槛仍保留个人有效评分。
- [x] 每次结算整体替换，缓存大小不随章节数增长。reset、换图、离线不清空，插件重载自然清空。
- [x] 不用 client 槽或姓名兜底身份；重连可读取，新玩家复用旧槽不能串人。
- [x] 运行已有 Tank/history 与新快照测试，确认原公式和自动输出保持不变。

### Task 3：查询与控制台输出

**文件：** 修改目标插件 `OnPluginStart`，新增 `Command_RatingPro` 与 `PrintRatingSnapshotToConsole`。

- [x] 注册指令，留空参数/`@all` 遍历在线真人，其他参数单目标解析；错误用 `ReplyToTargetError`，返回 `Plugin_Handled`。
- [x] 输出前重新确认在线真人与身份，只读取缓存，不读取当前计数拼接历史评分。
- [x] 单人/全员复用相同表格打印函数，加入开始/结束标记及无数据说明。
- [x] 真人只收到一条查看控制台的聊天提示；服务端调用跳过聊天。任何结果不广播。
- [x] 结算完成后向在线真人提示输入 `!rating`；保留现有公告和个人评分消息，提示不替代明细表。
- [x] 建议请求者冷却 2 秒，client=0 不限流；离线清理冷却，不清理评分快照。
- [x] 新测试通过，重复查询同一快照数值一致，历史槽索引和计数不变。

### Task 4：编译、回归与运行验收

- [x] 执行 `python -m unittest discover -s tests -v`，无关失败单独记录，不顺带修复。
- [x] 从仓库根目录编译到临时目录，不覆盖发布产物：

```powershell
$output = Join-Path $env:TEMP 'l4d2_round_ratingpro-query.smx'
& '.\addons\sourcemod\scripting\sourcemod\spcomp.exe' -i 'addons/sourcemod/scripting/sourcemod/include' -i 'addons/sourcemod/scripting/include' '.\addons\sourcemod\scripting\l4d2_round_ratingpro.sp' -o $output
```

- [x] 预期退出码 0，无新增警告。
- [ ] 在测试服务器加载临时产物，确认无加载错误，不未经确认部署生产或更新 optional smx。（由于本地环境无运行中的专用 srcds 服务器，已完成单元测试与 spcomp 编译验证，真实游戏服务器验收留待实际部署环境执行）
- [ ] 验证三个命令名及聊天触发：留空参数全员、姓名/空格姓名、userid、重名、无匹配、机器人、`@all`、身份未验证、服务端调用。
- [ ] 完成两半场结算，核对查询与原个人提示/服务端评分在相同精度下一致；低于最佳门槛也可查询个人结果。
- [ ] 结算后确认在线真人收到 `!rating` 提示，原最佳公告和评分消息仍然存在。
- [ ] 验证延迟期间读取上次快照，首次结算前无数据，跨图仍可读取，下次无数据结算替换旧结果。
- [ ] 验证离线重连、槽复用、无 Tank、历史 Tank 回退、enabled 关闭及冷却。其他玩家不应收到查询输出。
- [x] 记录测试、编译、服务器验收证据；没有服务器时明确运行验收未执行，不用静态测试替代真实交互。

## 5. 风险、回滚与完成标准

- 非目标：实时预测、离线检索、菜单、数据库、跨插件重载持久化、新广播。
- 缓存完整评分，避免人员变化导致旧评分归一化范围变化；当前延迟结算和章节计数生命周期不顺带修改。
- PrintToConsole 不等于日志落盘，需要持久记录时由玩家复制或启用客户端日志功能。
- 保留现有服务端输出责任，不将其直接改为只对某个玩家打印；不存在要退役的旧查询路径。
- 回滚移除新增指令、缓存及打印函数或恢复旧 smx，不删除原 Tank/history 状态与日志路径。
- [x] 指令、表格、无数据状态符合契约；查询只读且身份不串人。
- [x] 原公告和服务端明细保持不变，新旧测试与编译通过。
- [x] 运行验收边界已明确说明（静态与编译验证全部通过，实机测试待部署环境验证）。
