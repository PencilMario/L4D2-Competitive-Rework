# RatingPro 参与者按 SteamID 记账

**Goal：** `l4d2_round_ratingpro.sp` 的整局累计数据从「客户端槽位」改为「SteamID 参与者记录」，玩家退服后数据保留并计入结算快照；数据随下次结算生成的快照覆盖而释放，不新增手动清除指令。

**触发问题：**

- 中途退服的玩家在 `SaveRatingSnapshot` 的 `IsHumanClient` 过滤下被丢弃，其本局表现不进入快照与日志。
- 累计器 `g_iXxx[client]` 以客户端槽位为键，客户端槽位被新玩家复用时新玩家会继承旧玩家的计数。
- `!rating <名字>` 走 `ProcessTargetString`，只能匹配在线玩家，查不到仍在快照里的退服玩家。

**新模型：**

| 层 | 键 | 生命周期 |
| --- | --- | --- |
| 参与者记录 `g_iXxx[participant]` + `g_sParticipantAuth[]` | SteamID（Steam2） | 自首次行为记录起，到本图 `OnMapStart` 清空 |
| 历史槽位 `g_hRawHistory[]` / `g_hRawActionHistory[]` | SteamID | 四槽环形缓冲，跨图保留 |
| 快照 `g_hLastRatingSnapshot` / `g_hLastRatingSnapshotNames` | SteamID | 下次结算覆盖时清除 |

- `g_bBiled` 保持按客户端槽位：它是「当前实体正在被胆汁覆盖」的即时状态，不是玩家累计数据，且 `player_bot_replace` / `bot_player_replace` 需按槽位转移。
- 参与者注册表上限 `MAX_PARTICIPANTS`（64），满员时丢弃新参与者并记录一次错误，不再静默串数据。
- 结算、范围构建、最佳评选、控制台明细均遍历参与者，不再遍历在线客户端；聊天明细仍只发给在线真人。

**验证：** `spcomp` 编译通过；`python -m unittest discover -s tests -p 'test_l4d2_round_ratingpro*.py'` 全绿（含新增退服保留用例）。

## 结果（已落地）

- 新增 `GetClientAuthKey` / `FindParticipantByAuth` / `AcquireParticipant` / `FindClientByAuth` / `FindSnapshotPlayer`，`OnClientPutInServer` 与 `OnClientDisconnect` 只清 `g_sClientAuth`、`g_bBiled`、`g_fLastQueryTime`，不再触碰累计数据。
- 全部整局累计器与 `GetTankRaw` / `GetEffectiveTankRaw` / `GetHistoricalRaw` / `AggregateHistoricalActions` / `BuildRawRanges` / 最佳评选 / 快照 / 结算遍历改为参与者键；`SaveLatestTankRaw`、`SaveRoundRawHistory` 以 `g_sParticipantAuth[participant]` 写入历史。
- `PrintRatingSnapshotToConsole(requester, auth, displayName, userId, logToFile)` 统一打印入口：`userId = 0` 显示 `已退服 (offline)`；`!rating <名字|STEAM_x:x:xxxx>` 在在线匹配失败后回落到快照查询（精确名优先，其次唯一子串，多命中要求更精确输入）。
- 参与者池满时只记录一次错误（`g_bParticipantOverflowLogged`，`ResetRoundStats` 复位），避免刷日志。
- 证据：`spcomp` 无警告，Code 72968 / Data 44572 / Stack-heap 18516；`python -m unittest discover -s tests -p 'test_*.py'` → 55 tests OK。
