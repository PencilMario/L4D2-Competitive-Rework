#if defined _l4d2_round_ratingpro_included
 #endinput
#endif
#define _l4d2_round_ratingpro_included

/** 最近 N 场平均 RatingPro 的取样场数 */
#define RATINGPRO_MAX_RECENT_RATINGS 5

/**
 * L4D2 Round RatingPro 对外接口
 *
 * 数据来源为 RatingPro Hub 后端（https://l4d2rating.0721play.icu）：
 *   - 玩家通过 Steam 认证（OnClientPostAdminCheck）后，插件自动请求并缓存
 *     「当前 ELO」与「最近 5 场平均 RatingPro」，本文件所有 Get 类 native
 *     都只读本地缓存，不会发起网络请求，可安全地在命令 / 定时器里循环调用。
 *   - 同一战役里每攒满 N 张图（默认 4）上传一次对局数据，上传后触发
 *     RatingPro_OnEloUploaded / RatingPro_OnClientEloUpdated 回调。
 *
 * 约定：所有 native 都以 client index 为键（而不是 SteamID 字符串），
 *       并统一使用 1..MaxClients 的服务器槽位号。client 非法、玩家未认证或
 *       缓存尚未就绪时，native 返回 false / 0.0，可用 RatingPro_GetClientCacheStatus()
 *       区分「没请求」与「查无记录」。
 */

/** 单个玩家的后端数据缓存状态 */
enum RatingProCacheStatus
{
	RatingProCache_None = 0,   // 尚未发起请求（未认证 / 刚进服）
	RatingProCache_Loading,    // 请求进行中
	RatingProCache_Ready,      // 缓存已就绪，Get* 可用
	RatingProCache_NoRecord,   // 后端查无此人（404），通常是从未上传过对局
	RatingProCache_Error,      // 网络或服务端错误，可稍后调用 RatingPro_RefreshClientData() 重试
};

/**
 * 玩家的 ELO 数据缓存完成（请求成功、查无记录或失败都会触发）。
 * 只在 ELO 请求（/elo/current）结束时回调一次；最近 5 场平均值不单独回调。
 *
 * @param client        客户端索引
 * @param status        本次请求的结果状态
 */
forward void RatingPro_OnClientDataLoaded(int client, RatingProCacheStatus status);

/**
 * 本次上传改变了某个在线玩家的 ELO（后端已结算并回传 elo_before / elo_after）。
 *
 * @param client        客户端索引（仍在服务器中的玩家）
 * @param eloBefore     本场结算前 ELO
 * @param eloAfter      本场结算后 ELO
 * @param eloDelta      变化量（eloAfter - eloBefore，可正可负）
 */
forward void RatingPro_OnClientEloUpdated(int client, float eloBefore, float eloAfter, float eloDelta);

/**
 * 一次战役（默认累计 4 张图）的对局数据上传结束。
 *
 * @param snapshotId    插件内部的结算快照编号
 * @param httpStatus    HTTP 状态码；网络层失败（超时 / 无法连接）时为 0
 * @param success       true = 后端已入库（或判定为重复上传且未重复计分）
 * @param playerCount   本次载荷携带的玩家人数
 */
forward void RatingPro_OnEloUploaded(int snapshotId, int httpStatus, bool success, int playerCount);

/**
 * 获取玩家缓存状态。
 *
 * @param client        客户端索引
 * @return              RatingProCacheStatus
 */
native RatingProCacheStatus RatingPro_GetClientCacheStatus(int client);

/**
 * 玩家的后端数据（目前以 ELO 请求为准）是否已就绪。
 *
 * @param client        客户端索引
 * @return              true = 可以安全读取 ELO / 排名 / 平均值等缓存
 */
native bool RatingPro_IsClientDataReady(int client);

/**
 * 一次性读取常用 ELO 字段。
 *
 * @param client        客户端索引
 * @param elo           输出：当前 ELO（初始 1500）
 * @param peakElo       输出：历史最高 ELO
 * @param rank          输出：全服 ELO 排名（1 起，0 = 无排名）
 * @param totalPlayers  输出：参与排名的总人数
 * @return              true = 缓存就绪并已填充所有输出参数
 */
native bool RatingPro_GetClientElo(int client, float &elo, float &peakElo, int &rank, int &totalPlayers);

/**
 * 当前 ELO。
 *
 * @param client        客户端索引
 * @return              ELO；缓存未就绪时返回 0.0（用 RatingPro_IsClientDataReady 区分）
 */
native float RatingPro_GetClientEloValue(int client);

/**
 * 历史最高 ELO。
 *
 * @param client        客户端索引
 * @return              峰值 ELO；缓存未就绪时返回 0.0
 */
native float RatingPro_GetClientPeakElo(int client);

/**
 * 全服 ELO 排名。
 *
 * @param client        客户端索引
 * @return              排名（1 起）；无排名或未就绪时返回 0
 */
native int RatingPro_GetClientEloRank(int client);

/**
 * 参与排名的总人数。
 *
 * @param client        客户端索引
 * @return              总人数；未就绪时返回 0
 */
native int RatingPro_GetClientEloTotalPlayers(int client);

/**
 * 该玩家已结算的有效对局数。
 *
 * @param client        客户端索引
 * @return              对局数
 */
native int RatingPro_GetClientEloRounds(int client);

/**
 * 当前生效的 ELO K 值（定位赛 48，之后 24）。
 *
 * @param client        客户端索引
 * @return              K 值；未就绪时返回 0.0
 */
native float RatingPro_GetClientEloKFactor(int client);

/**
 * 定位赛已完成场数。
 *
 * @param client        客户端索引
 * @return              已完成场数
 */
native int RatingPro_GetClientPlacementPlayed(int client);

/**
 * 定位赛所需场数。
 *
 * @param client        客户端索引
 * @return              所需场数；未就绪时返回 0
 */
native int RatingPro_GetClientPlacementRequired(int client);

/**
 * 最近一次结算的 ELO 变化量（后端 last_round.elo_delta）。
 *
 * @param client        客户端索引
 * @param delta         输出：变化量
 * @return              true = 存在最近一次结算记录
 */
native bool RatingPro_GetClientLastEloDelta(int client, float &delta);

/**
 * 最近 N 场（默认 5 场）RatingPro 平均值。
 *
 * @param client        客户端索引
 * @param average       输出：平均 RatingPro（0-10）
 * @param averageRaw    输出：平均加权原始分
 * @param count         输出：实际取到的场数（少于 5 说明有效结算不足）
 * @return              true = 平均值缓存就绪
 */
native bool RatingPro_GetClientRecentRating(int client, float &average, float &averageRaw, int &count);

/**
 * 最近 N 场 RatingPro 平均值（仅数值）。
 *
 * @param client        客户端索引
 * @return              平均值；未就绪时返回 0.0
 */
native float RatingPro_GetClientRecentRatingAverage(int client);

/**
 * 最近 N 场实际取到的场数。
 *
 * @param client        客户端索引
 * @return              场数；未就绪时返回 0
 */
native int RatingPro_GetClientRecentRatingCount(int client);

/**
 * 按索引读取最近 N 场中的单场 RatingPro。
 *
 * @param client        客户端索引
 * @param index         0 = 最近一把，依次向前
 * @param rating        输出：该场 RatingPro
 * @return              true = 该索引存在
 */
native bool RatingPro_GetClientRecentRatingAt(int client, int index, float &rating);

/**
 * 强制刷新某个玩家的后端缓存（立即发起两次请求，旧缓存保留到新数据返回）。
 *
 * @param client        客户端索引
 * @noreturn
 */
native void RatingPro_RefreshClientData(int client);

/**
 * 最近一次结算快照编号（插件内部自增，可用于关联日志）。
 *
 * @return              快照编号
 */
native int RatingPro_GetSnapshotId();

/**
 * 当前战役（同一章节序列）内已累计结算的地图数。
 *
 * 每攒满 sm_ratingpro_upload_maps（默认 4）张就上传一次，上传后立刻归零重新累计；
 * 序列中断（双方战役比分回退 = 有人重开过战役）同样归零，但这段不完整的对局不上传，
 * 且玩家评分窗口仍按原始跨图口径滚动，不受影响。
 *
 * 判定只看「连续对局」：双方比分单调不减即视为同一段，地图名（战役前缀、章节号）
 * 完全不参与 —— 仓库里有插件能把随机地图拼成章节序列，前缀变化与跳章都可能是
 * 同一段连续对局。
 *
 * @return              已累计地图数
 */
native int RatingPro_GetCampaignMapCount();

/**
 * 是否有已生成但尚未成功上传的对局数据。
 *
 * @return              true = 存在待上传 / 重试中的载荷
 */
native bool RatingPro_HasPendingUpload();
