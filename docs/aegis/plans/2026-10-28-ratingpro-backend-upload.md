# RatingPro 后端接入：按战役上传 + 对外查询接口

**Goal：** `l4d2_round_ratingpro.sp` 把每局结算快照上传到 RatingPro Hub（`https://l4d2rating.0721play.icu`），但**同一战役里每攒满 N 张图（默认 4）才上传一次**；同时新增 `l4d2_round_ratingpro.inc`，让其它插件能读到缓存的 ELO / 最近 5 场平均分，并在 ELO 更新、上传完成时收到 forward。

**触发问题：**

- 快照号 `g_iSnapshotRoundId` 只在单图内自增，逐图上传会让后端把「同一战役的第 N 图」当成互不相关的对局，且中途换图会造成半局数据入库。
- 其它插件（计分板、排位显示）需要 ELO 与近期平均分，但不应该各自重复实现 HTTP 客户端与 JSON 解析。

**口径（本实现的核心决定）：**

| 概念 | 判定 | 后果 |
| --- | --- | --- |
| 同一战役 | 连续结算 **且** 双方战役累计比分单调不减。**地图名完全不参与判定**：仓库里有插件能把随机地图拼成章节序列，前缀变化与跳章都可能是同一段连续对局 | 继续累加 |
| 战役中断 | 任一方战役累计比分回退（= 有人重开过战役） | 只把**上传计数器**归零：这段不完整对局**不产生任何上传**；评分窗口不动 |
| 上传时机 | `g_iCampaignMaps >= sm_ratingpro_upload_maps`（默认 4），且上一发已结清 | 上传一次快照，随后**计数器归零**重新累计；同一战役连打超过 N 张会分多次上传 |
| 人数门槛 | 触发上传的那张图参与人数 < `sm_ratingpro_min_players`（默认 8） | 这段数据不上传，计数器归零；设 0 关闭限制 |

- 断章**不清空评分窗口**（`RAW_HISTORY_SLOTS` 四槽环仍按原始跨图口径滚动）：断章只决定「这段数据算不算一次可交付的战役段」，不改变 `!rating` 看到的历史口径。因此上传载荷的评分窗口可能含上一段序列留下的槽位——槽位归属按段序号 `g_iCampaignSeqId` 判定（断章 +1、上传归零不 +1），只记一条 `LogMessage` 说明覆盖情况，不阻断上传。
- 攒满即消费：计数器在**载荷构建之后**归零，成功、后端判重、重试彻底失败都不回补，避免同一段被反复上传；上一发还在途 / 等重试时不会重复攒（否则会覆盖仍在重试的载荷）。
- 人数不足**丢弃而非延后**：`players[]` 只取自触发上传的那张图，若只是「等下一局够人再传」，下一局的载荷会把这段稀薄战绩连同错配的人数一起带出去。人数据取的是「本图触发过统计事件的去重 SteamID 数」（`g_iParticipantCount`，按图重置），纯观察位不算。
- 地图名解析（`c1m3_mall` → `c1` + 章节 `3`）只用于日志与 `!apidebug` 定位，**不参与判定**：仓库里有插件能把随机地图拼成章节序列，前缀与章节号在那种服务器上说明不了连续性。
- 比分单调性是**唯一**判据，依赖 left4dhooks `L4D_GetTeamScore(team, campaign_score=true)`，以 `native` + `MarkNativeAsOptional` 声明避免硬依赖；native 不可用或返回负数时不再检测中断（`sm_ratingpro_score_guard 0` 同理），上传计数只在攒满上传时归零。

**载荷：** `schema_version: 2` + `stats_scope: cumulative`，字段与 `docs/API.md` §4.2–4.4 一一对应（`snapshot` / `players[]` / 23 项行为计数 / 五维归一化 / 五维原始分）。不发送 `winner_team`，走文档默认的**表现 ELO**。`external_id` 固定为 `服务器key|地图|快照号|结算时间`，重试时完全一致，后端据此幂等去重。

**网络层：** 统一用 SteamWorks extension（用户指定优先），不引入 RIPExt；GET 超时 10s、上传 20s；上传失败按 `UPLOAD_RETRY_DELAY × 次数` 退避，最多 3 次，仅对网络失败 / 429 / 5xx 重试，4xx 视为载荷或鉴权问题直接放弃。响应体读入全局固定缓冲 `g_sHttpResponse`（32 KiB），不分配堆内存。

**对外接口（`l4d2_round_ratingpro.inc`）：**

- 玩家认证完成（`OnClientPostAdminCheck`）后异步请求 `/players/{id}/elo/current` 与 `/players/{id}/rating/average?limit=5`，结果缓存在 `g_ClientInfo[client]`；所有 Get 类 native 只读缓存，不发请求。
- 20 个 native（`RatingPro_GetClientElo` / `_GetClientRecentRating` / `_GetClientRecentRatingAt` / `_RefreshClientData` / `_GetCampaignMapCount` …）+ 3 个 forward（`RatingPro_OnClientDataLoaded` / `_OnClientEloUpdated` / `_OnEloUploaded`）。
- 入参统一用**在线 client index**（用户允许），避免 native 字符串参数；缓存按 client 槽位存，槽位复用由 `g_iClientToken[client]` 让在途响应失效。
- native 参数里带 SteamID 的只有上传响应回填：按 `steam_id` 反查在线 client 后写回 ELO 并触发 `RatingPro_OnClientEloUpdated`。

**验证：**

- `spcomp -w234 -w217 -O2 -v2` 无 error / 无 warning（Code 123988 / Data 160588 / Stack-heap 19380）。
- `python -m unittest discover -s tests -p 'test_*.py'` → 112 tests OK，其中 `tests/test_l4d2_round_ratingpro_backend.py` 新增 26 条：native 声明与注册双向一致、forward 全覆盖、断章只重置上传计数且不动评分窗口、攒满即归零且在途不重复攒、人数门槛不足即丢弃、载荷字段与 API 文档对齐、external_id 重试稳定、SteamID 先编码再拼 URL、槽位复用丢弃过期响应、只对可重试状态重试。
- 载荷结构用逐字复制源码字面量的 Python 脚本 `json.loads` 复核通过（含 2 人样例，1.6 KB；满 64 人约 52 KB，未超 2 MB 限制，另有 `strlen + 1024` 余量保护）。
- 未对线上后端 POST 测试数据（避免污染生产库）；`GET /api/v1/health` 确认为 `1.1.0` + `ratingpro-1.0.0`，未知 SteamID 返回 404 `not_found`，与实现的 404 → `RatingProCache_NoRecord` 分支一致。

## 结果（已落地）

- 新增 `CreateApiConVars` / `InitializeApi` / `ResetClientApiCache` / `RequestClientApiData` / `RequestClientElo` / `RequestClientRecentRating` / `OnClientEloResponse` / `OnClientRatingResponse` / `ParseEloResponse` / `ParseRatingAverageResponse`。
- 新增 `ParseCampaignProgress` / `TryGetCampaignScores` / `IsCampaignBroken` / `ResetCampaignProgress` / `UpdateCampaignProgress`；`Timer_PrintBestRating` 在写入原始分槽位**之前**调用 `UpdateCampaignProgress()`，两条结算分支之后各调用一次 `MaybeUploadCampaign()`。`ResetCampaignProgress` 只清战役计数与段序号以外的状态，不碰 `g_hRawHistory` / `g_hRawActionHistory` / `g_iRawHistory*`；断章时由 `UpdateCampaignProgress` 自己把 `g_iCampaignSeqId` 加一。
- 新增 `MaybeUploadCampaign` / `IsApiWritable` / `BuildUploadPayload` / `AppendPlayerJson` / `SendUploadRequest` / `ScheduleUploadRetry` / `OnUploadCompleted` / `ApplyUploadResults` / `Timer_RefreshOnlineClients`。`MaybeUploadCampaign` 在 `BuildUploadPayload()` 之后把 `g_iCampaignMaps` 归零；原先的「本战役已上传」标志 `g_bCampaignUploaded` 随归零机制一并删除，同一事实不再有两份真相。
- 新增手写 JSON 读取器（`JsonSkipValue` / `JsonFindMember` / `JsonResolvePath` / `JsonGetValue|Float|Int|Bool` / `JsonGetArrayLength|Element`）与写入器（`JsonEscape` / `UrlEncode`）：仓库没有 `json.inc`，为免给所有服主加装 RIPExt 硬依赖，只实现用得到的最小子集，不分配堆内存。
- `CollectHistoryMaps` 拆出 `CollectHistoryMapNames` 供上传载荷复用；`SaveRoundRawHistory` 额外记录槽位所属段序号 `g_iRawHistorySeq[slot]`。
- 运维命令 `sm_ratingpro_apidebug`（`ADMFLAG_ROOT`）：打印后端配置、战役累计、上传状态与在线玩家 ELO 缓存，加任意参数打印待上传载荷 JSON。
- 新增 `cfg/sourcemod/l4d2_round_ratingpro.cfg`（API Key 与 server_key 默认注释掉，避免自动执行时覆盖本机既有值）。
- 行为影响面：`spcomp` 编译通过的同一份源码在无 `sm_ratingpro_api_key` 时**只读不写**——ELO 与平均分照常缓存，但一次也不会尝试上传，并只在首次记录一条 `LogError` 提示。

## 部署前提

- SteamWorks 是**硬依赖**（`#include <SteamWorks>` 且调用了其 native）：缺扩展时整个插件不会加载，`!rating` 也会一起失效。
  仓库只带了 `addons/sourcemod/extensions/SteamWorks.ext.so`（Linux）；Windows 服需自行补 `SteamWorks.ext.dll`。
  这里刻意不做「缺扩展就静默降级」：上传静默失效比加载失败更难排查。
- `left4dhooks`（`L4D_GetTeamScore`）是**软依赖**：`MarkNativeAsOptional` + `GetFeatureStatus` 检查，缺失时只关掉「比分不减」这一条辅助判定。
