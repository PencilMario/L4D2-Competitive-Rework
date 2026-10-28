/**
 * L4D2 RatingPro ELO 提示
 *
 * 1) 进服提示：玩家完成 Steam 认证后，等后端 ELO 缓存就绪（RatingPro_OnClientDataLoaded），
 *    延迟若干秒单独提示该玩家：
 *      - 当前 ELO / 全服排名 / 已结算场数
 *      - 最近一次结算的变化量（elo_before → elo_after）与历史最高 ELO
 *      - 最近 5 场平均 RatingPro 与定位赛进度
 * 2) 手动查询：!elo 查看自己，!elo <玩家名> 查看他人；比进服提示多一行
 *    「最近 N 场各自的 Rating」（新 → 旧）。
 *
 * 所有数值都读 l4d2_round_ratingpro 的本地缓存（Get 类 native 不发网络请求）。
 * 只有主插件未开启自动缓存（sm_ratingpro_auto_refresh=0）时，本插件才会借
 * RatingPro_RefreshClientData() 让它补一次请求。
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colors>
#include <l4d2_round_ratingpro>

#define PLUGIN_VERSION "1.0.0"

#define ELO_LINE_COUNT 4
#define ELO_LINE_LENGTH 200
#define SEGMENT_LENGTH 96
#define SEGMENT_SEPARATOR " | "

// 数据没就绪时补请求的间隔
#define RETRY_DELAY 8.0

ConVar g_hNotify;
ConVar g_hNotifyDelay;
ConVar g_hShowRank;
ConVar g_hShowDelta;
ConVar g_hShowRecent;
ConVar g_hUpdateMode;
ConVar g_hRetry;

bool g_bApiAvailable;
bool g_bNotified[MAXPLAYERS + 1];
int g_iRetryCount[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "L4D2 RatingPro ELO",
	author = "Codex",
	description = "玩家进服提示其 ELO 与最近变化，并提供 !elo 手动查询。",
	version = PLUGIN_VERSION,
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
	// 未安装 / 版本不匹配的 l4d2_round_ratingpro 不会让本插件加载失败，只是不再提示。
	MarkNativeAsOptional("RatingPro_GetClientCacheStatus");
	MarkNativeAsOptional("RatingPro_GetClientElo");
	MarkNativeAsOptional("RatingPro_GetClientEloRounds");
	MarkNativeAsOptional("RatingPro_GetClientPlacementPlayed");
	MarkNativeAsOptional("RatingPro_GetClientPlacementRequired");
	MarkNativeAsOptional("RatingPro_GetClientLastEloDelta");
	MarkNativeAsOptional("RatingPro_GetClientRecentRating");
	MarkNativeAsOptional("RatingPro_GetClientRecentRatingCount");
	MarkNativeAsOptional("RatingPro_GetClientRecentRatingAt");
	MarkNativeAsOptional("RatingPro_RefreshClientData");

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_hNotify = CreateConVar("sm_ratingpro_elo_notify", "1",
		"玩家进服后提示其 ELO、排名、最近一次结算变化与最近 5 场平均 Rating。",
		FCVAR_NONE, true, 0.0, true, 1.0);
	g_hNotifyDelay = CreateConVar("sm_ratingpro_elo_delay", "3.0",
		"进服提示的延迟秒数（等连接期的其他提示刷完再发）。",
		FCVAR_NONE, true, 0.0, true, 30.0);
	g_hShowRank = CreateConVar("sm_ratingpro_elo_show_rank", "1",
		"进服提示里附带全服 ELO 排名。",
		FCVAR_NONE, true, 0.0, true, 1.0);
	g_hShowDelta = CreateConVar("sm_ratingpro_elo_show_delta", "1",
		"进服提示里附带最近一次结算的 ELO 变化。",
		FCVAR_NONE, true, 0.0, true, 1.0);
	g_hShowRecent = CreateConVar("sm_ratingpro_elo_show_recent", "1",
		"进服提示里附带最近 5 场平均 Rating。",
		FCVAR_NONE, true, 0.0, true, 1.0);
	g_hUpdateMode = CreateConVar("sm_ratingpro_elo_update", "1",
		"对局结算上传后提示 ELO 变化：0 = 关闭，1 = 只提示本人，2 = 提示全员。",
		FCVAR_NONE, true, 0.0, true, 2.0);
	g_hRetry = CreateConVar("sm_ratingpro_elo_retry", "2",
		"进服时 ELO 数据请求失败的重试次数。",
		FCVAR_NONE, true, 0.0, true, 5.0);

	RegConsoleCmd("sm_elo", Command_Elo, "查看自己或指定玩家的 ELO、变化与最近 Rating。");

	AutoExecConfig(true, "l4d2_ratingpro_elo");
}

public void OnAllPluginsLoaded()
{
	g_bApiAvailable = LibraryExists("l4d2_round_ratingpro")
		&& GetFeatureStatus(FeatureType_Native, "RatingPro_GetClientElo") == FeatureStatus_Available;

	if (!g_bApiAvailable)
	{
		LogMessage("未检测到可用的 l4d2_round_ratingpro，进服 ELO 提示与 !elo 查询已停用。");
	}
}

// ==========================================================================================
// 进服提示
// ==========================================================================================

public void OnClientPutInServer(int client)
{
	ResetClientState(client);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
}

void ResetClientState(int client)
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	g_bNotified[client] = false;
	g_iRetryCount[client] = 0;
}

public void OnClientPostAdminCheck(int client)
{
	ResetClientState(client);

	if (!g_bApiAvailable || !g_hNotify.BoolValue || !IsHumanClient(client))
	{
		return;
	}

	switch (RatingPro_GetClientCacheStatus(client))
	{
		case RatingProCache_Ready, RatingProCache_NoRecord:
		{
			ScheduleJoinNotice(client, g_hNotifyDelay.FloatValue);
		}
		case RatingProCache_None:
		{
			// 主插件关掉了自动缓存（sm_ratingpro_auto_refresh=0）时自行补一次请求，
			// 结果仍由 RatingPro_OnClientDataLoaded 回调回来。
			RatingPro_RefreshClientData(client);
		}
		// Loading / Error 交给回调与重试流程处理。
	}
}

public void RatingPro_OnClientDataLoaded(int client, RatingProCacheStatus status)
{
	if (!g_bApiAvailable || !g_hNotify.BoolValue || !IsHumanClient(client))
	{
		return;
	}

	if (status == RatingProCache_Ready || status == RatingProCache_NoRecord)
	{
		ScheduleJoinNotice(client, g_hNotifyDelay.FloatValue);
		return;
	}

	// 只处理「首次请求就失败」的重试；已有结果的玩家不再补发提示。
	if (status != RatingProCache_Error || g_bNotified[client])
	{
		return;
	}

	if (g_iRetryCount[client] < g_hRetry.IntValue)
	{
		g_iRetryCount[client]++;
		CreateTimer(RETRY_DELAY, Timer_Retry, GetClientUserId(client));
		return;
	}

	g_bNotified[client] = true;
	CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} ELO 数据获取失败，输入 {olive}!elo{default} 可稍后再试。");
}

public Action Timer_Retry(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (client <= 0 || g_bNotified[client] || !IsHumanClient(client))
	{
		return Plugin_Stop;
	}

	RatingPro_RefreshClientData(client);
	return Plugin_Stop;
}

void ScheduleJoinNotice(int client, float delay)
{
	if (!IsHumanClient(client) || g_bNotified[client])
	{
		return;
	}

	if (delay < 0.0)
	{
		delay = 0.0;
	}

	CreateTimer(delay, Timer_JoinNotice, GetClientUserId(client));
}

public Action Timer_JoinNotice(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0)
	{
		PrintJoinNotice(client);
	}

	return Plugin_Stop;
}

void PrintJoinNotice(int client)
{
	if (!g_bApiAvailable || !g_hNotify.BoolValue || g_bNotified[client] || !IsHumanClient(client))
	{
		return;
	}

	RatingProCacheStatus status = RatingPro_GetClientCacheStatus(client);
	if (status == RatingProCache_NoRecord)
	{
		g_bNotified[client] = true;
		CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 欢迎 {olive}%N{default}，你还没有 ELO 记录。", client);
		CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 完成一次对局结算（后端默认累计 4 张图上传一次）后即可获得评分。");
		CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 输入 {olive}!rating{default} 查看本章节评分，{olive}!elo{default} 查 ELO。");
		return;
	}

	if (status != RatingProCache_Ready)
	{
		// 还在请求或已失败：交给回调 / 重试流程，这里不打印，避免半截信息。
		return;
	}

	char lines[ELO_LINE_COUNT][ELO_LINE_LENGTH];
	if (!BuildEloReport(client, false, lines))
	{
		return;
	}

	g_bNotified[client] = true;

	CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 欢迎 {olive}%N{default}，%s", client, lines[0]);

	for (int line = 1; line < ELO_LINE_COUNT; line++)
	{
		if (lines[line][0] != '\0')
		{
			CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} %s", lines[line]);
		}
	}

	CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 输入 {olive}!elo{default} 查看 ELO，{olive}!rating{default} 查看详细评分。");
}

// ==========================================================================================
// 结算后的变化提示
// ==========================================================================================

public void RatingPro_OnClientEloUpdated(int client, float eloBefore, float eloAfter, float eloDelta)
{
	if (!g_bApiAvailable || !IsHumanClient(client))
	{
		return;
	}

	int mode = g_hUpdateMode.IntValue;
	if (mode <= 0)
	{
		return;
	}

	char deltaText[32];
	FormatDelta(deltaText, sizeof(deltaText), eloDelta);

	char color[8];
	GetDeltaColor(eloDelta, color, sizeof(color));

	if (mode == 2)
	{
		CPrintToChatAll("{blue}[{green}RatingPro{blue}]{default} {olive}%N{default} 的 ELO 已结算：%.0f → %s%.0f{default}（%s%s{default}）",
			client, eloBefore, color, eloAfter, color, deltaText);
	}
	else
	{
		CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 你的 ELO 已结算：%.0f → %s%.0f{default}（%s%s{default}）",
			eloBefore, color, eloAfter, color, deltaText);
	}
}

// ==========================================================================================
// !elo 手动查询
// ==========================================================================================

public Action Command_Elo(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[RatingPro] 该命令只能在游戏内使用。");
		return Plugin_Handled;
	}

	if (!g_bApiAvailable)
	{
		CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 服务器未启用 ELO 统计。");
		return Plugin_Handled;
	}

	int target = client;
	if (args >= 1)
	{
		char pattern[MAX_NAME_LENGTH];
		GetCmdArg(1, pattern, sizeof(pattern));

		// FindTarget 自己会提示「找不到玩家 / 匹配到多名玩家」，这里只需静默返回。
		target = FindTarget(client, pattern, true);
		if (target <= 0 || !IsHumanClient(target))
		{
			return Plugin_Handled;
		}
	}

	switch (RatingPro_GetClientCacheStatus(target))
	{
		case RatingProCache_NoRecord:
		{
			if (target == client)
			{
				CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 你还没有 ELO 记录，完成一次对局结算后即可获得评分。");
			}
			else
			{
				CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} {olive}%N{default} 还没有 ELO 记录。", target);
			}
			return Plugin_Handled;
		}
		case RatingProCache_None:
		{
			// 没有缓存（自动刷新关掉 / 刚进服）时补一次请求，数据回来后再查。
			RatingPro_RefreshClientData(target);
			CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 正在获取 {olive}%N{default} 的 ELO 数据，请稍后再试。", target);
			return Plugin_Handled;
		}
		case RatingProCache_Loading:
		{
			CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} ELO 数据仍在加载，请稍后再试。");
			return Plugin_Handled;
		}
		case RatingProCache_Error:
		{
			RatingPro_RefreshClientData(target);
			CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} ELO 数据获取失败，正在重试，请稍后再查询。");
			return Plugin_Handled;
		}
	}

	char lines[ELO_LINE_COUNT][ELO_LINE_LENGTH];
	if (!BuildEloReport(target, true, lines))
	{
		CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} ELO 数据暂不可用，请稍后再试。");
		return Plugin_Handled;
	}

	char prefix[MAX_NAME_LENGTH + 16] = "";
	if (target != client)
	{
		Format(prefix, sizeof(prefix), "{olive}%N{default} ", target);
	}

	CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} %s%s", prefix, lines[0]);

	for (int line = 1; line < ELO_LINE_COUNT; line++)
	{
		if (lines[line][0] != '\0')
		{
			CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} %s", lines[line]);
		}
	}

	return Plugin_Handled;
}

// ==========================================================================================
// 汇报文本
// ==========================================================================================

/**
 * 组装 ELO 播报内容（不含前缀标签）。
 *
 * @param client    客户端索引
 * @param full      true = 输出全部字段（!elo）；false = 进服提示，按 cvar 裁剪
 * @param lines     输出：0 = ELO 与排名，1 = 最近变化与历史最高，
 *                  2 = 最近平均与定位赛，3 = 最近每场 Rating（仅 full）
 * @return          true = 缓存就绪，lines 已填充
 */
bool BuildEloReport(int client, bool full, char lines[ELO_LINE_COUNT][ELO_LINE_LENGTH])
{
	for (int line = 0; line < ELO_LINE_COUNT; line++)
	{
		lines[line][0] = '\0';
	}

	float elo;
	float peakElo;
	int rank;
	int totalPlayers;
	if (!RatingPro_GetClientElo(client, elo, peakElo, rank, totalPlayers))
	{
		return false;
	}

	char segment[SEGMENT_LENGTH];
	char suffix[128] = "";

	// 第 0 行：当前 ELO + 排名 + 已结算场数
	if (full || g_hShowRank.BoolValue)
	{
		if (rank > 0 && totalPlayers > 0)
		{
			Format(segment, sizeof(segment), "，全服排名 {olive}%d{default}/{olive}%d{default}", rank, totalPlayers);
			StrCat(suffix, sizeof(suffix), segment);
		}
	}

	int rounds = RatingPro_GetClientEloRounds(client);
	if (rounds > 0)
	{
		Format(segment, sizeof(segment), "，已结算 {olive}%d{default} 场", rounds);
		StrCat(suffix, sizeof(suffix), segment);
	}

	Format(lines[0], ELO_LINE_LENGTH, "当前 ELO {green}%.0f{default}%s", elo, suffix);

	// 第 1 行：最近一次结算的变化 + 历史最高
	float delta;
	if ((full || g_hShowDelta.BoolValue) && RatingPro_GetClientLastEloDelta(client, delta))
	{
		char deltaText[32];
		FormatDelta(deltaText, sizeof(deltaText), delta);

		char deltaColor[8];
		GetDeltaColor(delta, deltaColor, sizeof(deltaColor));

		Format(segment, sizeof(segment), "上次结算 %s%s{default}（%.0f → %.0f）",
			deltaColor, deltaText, elo - delta, elo);
		AppendSegment(lines[1], ELO_LINE_LENGTH, segment);
	}

	if (peakElo > elo + 0.5)
	{
		Format(segment, sizeof(segment), "历史最高 {olive}%.0f{default}", peakElo);
		AppendSegment(lines[1], ELO_LINE_LENGTH, segment);
	}

	// 第 2 行：最近 N 场平均 Rating + 定位赛进度
	float average;
	float averageRaw;
	int count;
	if ((full || g_hShowRecent.BoolValue)
		&& RatingPro_GetClientRecentRating(client, average, averageRaw, count) && count > 0)
	{
		Format(segment, sizeof(segment), "近 %d 场平均 {green}%.2f{default}", count, average);
		AppendSegment(lines[2], ELO_LINE_LENGTH, segment);
	}

	int placementPlayed = RatingPro_GetClientPlacementPlayed(client);
	int placementRequired = RatingPro_GetClientPlacementRequired(client);
	if (placementRequired > 0 && placementPlayed < placementRequired)
	{
		Format(segment, sizeof(segment), "定位赛 {olive}%d{default}/{olive}%d{default}", placementPlayed, placementRequired);
		AppendSegment(lines[2], ELO_LINE_LENGTH, segment);
	}

	// 第 3 行：最近每场各自的 Rating（新 → 旧，只在 !elo 展开，避免进服刷屏）
	if (full)
	{
		int recentCount = RatingPro_GetClientRecentRatingCount(client);
		char list[160] = "";

		for (int index = 0; index < recentCount; index++)
		{
			float rating;
			if (!RatingPro_GetClientRecentRatingAt(client, index, rating))
			{
				continue;
			}

			if (list[0] != '\0')
			{
				StrCat(list, sizeof(list), " / ");
			}

			Format(segment, sizeof(segment), "%.2f", rating);
			StrCat(list, sizeof(list), segment);
		}

		if (list[0] != '\0')
		{
			Format(lines[3], ELO_LINE_LENGTH, "最近 %d 场（新→旧）{green}%s{default}", recentCount, list);
		}
	}

	return true;
}

// 把一段内容拼到行尾，第一段不加分隔符。
void AppendSegment(char[] buffer, int maxlen, const char[] segment)
{
	if (buffer[0] == '\0')
	{
		strcopy(buffer, maxlen, segment);
		return;
	}

	StrCat(buffer, maxlen, SEGMENT_SEPARATOR);
	StrCat(buffer, maxlen, segment);
}

void FormatDelta(char[] buffer, int maxlen, float delta)
{
	if (delta > 0.0)
	{
		Format(buffer, maxlen, "+%.1f", delta);
		return;
	}

	Format(buffer, maxlen, "%.1f", delta);
}

/**
 * 变化量的颜色标签。
 *
 * 只能用非队伍色（{green} / {olive}）：colors.inc 在 L4D2 下把 {red} 当队伍色，
 * 而前缀里已经有 {blue}，同一条消息出现两个队伍色会直接 ThrowError。
 */
void GetDeltaColor(float delta, char[] buffer, int maxlen)
{
	if (delta >= 0.0)
	{
		strcopy(buffer, maxlen, "{green}");
		return;
	}

	buffer[0] = '\0';
}

bool IsHumanClient(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}
