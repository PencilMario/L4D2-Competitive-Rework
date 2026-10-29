#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>
#include <l4d2_skill_detect>
#include <logger>
#include <SteamWorks>
#include <l4d2_round_ratingpro>

#define PLUGIN_VERSION "1.3.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_TANK 8

#define RATING_EXPONENT 0.75
#define TANK_NO_DATA_SCORE 4.6
#define RAW_HISTORY_SLOTS 4
#define MAX_PARTICIPANTS 64
#define MAP_NAME_LENGTH 64
#define SNAPSHOT_MAP_LIST_CELLS 256
#define SNAPSHOT_MAP_SEPARATOR " → "

// RatingPro Hub 后端路径（base URL 由 sm_ratingpro_api_base 提供）
#define API_UPLOAD_PATH "/api/v1/rounds"
#define API_ELO_PATH "/api/v1/players/%s/elo/current"
#define API_RATING_AVERAGE_PATH "/api/v1/players/%s/rating/average?limit=%d"

#define HTTP_RESPONSE_SIZE 32768
#define UPLOAD_PAYLOAD_SIZE 65536
#define UPLOAD_MAX_ATTEMPTS 3
#define UPLOAD_RETRY_DELAY 10.0
#define RATING_REFRESH_DELAY 5.0

// 结算时地图分常常落后于 round_end：一次读不到就按秒重试，别让时序失误丢掉整局胜负与比分。
#define MAP_RESULT_RETRY_DELAY 1.0
#define MAP_RESULT_MAX_ATTEMPTS 6

// 后端接入专用日志：单独一个文件 logs/l4d2_ratingpro_api.log，
// 不跟结算明细（ratingpro.log / ratingpro_<地图>_<时间>.log）混在一起。
#define API_LOG_NAME "l4d2_ratingpro_api"
#define API_LOG_BODY_CHUNK 400
#define CLIENT_API_ERROR_LENGTH 192

// left4dhooks 原生函数：读取战役累计比分，是「对局是否连续」的唯一判据。
// 未安装 left4dhooks（或 sm_ratingpro_score_guard 0）时无法检测中断，只能按攒满即传。
native int L4D_GetTeamScore(int logical_team, bool campaign_score = false);

enum struct RatingSnapshotEntry
{
	bool valid;
	bool eligible;
	int team;
	int tankSource;
	float rating;
	float raw;
	float output;
	float defense;
	float focus;
	float infector;
	float tank;
	float outputRaw;
	float defenseRaw;
	float focusRaw;
	float infectorRaw;
	float tankRaw;
	int siDmg;
	int ciKill;
	int tankDmg;
	int dmgTaken;
	int incaps;
	int deaths;
	int ff;
	int tankupDmg;
	int tankupKill;
	int skeet;
	int level;
	int pop;
	int tongueCut;
	int crown;
	int dmg;
	int booms;
	int deathCharges;
	int tankDmgUpright;
	int punch;
	int rock;
	int hittable;
	int incap;
	int death;
	bool becameTank;
	int recordedSlots;
	int mapCount;
	char maps[SNAPSHOT_MAP_LIST_CELLS];
}

enum struct RawHistoryActionEntry
{
	float raw[4];
	int siDmg;
	int ciKill;
	int tankDmg;
	int dmgTaken;
	int incaps;
	int deaths;
	int ff;
	int tankupDmg;
	int tankupKill;
	int skeet;
	int level;
	int pop;
	int tongueCut;
	int crown;
	int dmg;
	int booms;
	int deathCharges;
}

enum struct TankHistoryEntry
{
	float raw;
	bool becameTank;
	int tankDmgUpright;
	int punch;
	int rock;
	int hittable;
	int incap;
	int death;
}

// 单个玩家的后端缓存。status 使用 RatingProCacheStatus 的整型值。
enum struct RatingProClientInfo
{
	bool loaded;
	int status;
	float elo;
	float peakElo;
	float kFactor;
	int rank;
	int totalPlayers;
	int rounds;
	int placementPlayed;
	int placementRequired;
	bool hasLastRound;
	float lastDelta;
	float lastRating;
	bool hasRecent;
	float recentAverage;
	float recentAverageRaw;
	int recentCount;
	int recentTotalEligible;
	float recentBest;
	float recentWorst;
	float recentValues[RATINGPRO_MAX_RECENT_RATINGS];
	int recentValueCount;
}

public Plugin myinfo =
{
	name = "L4D2 Round RatingPro",
	author = "Sir.P",
	description = "基于比赛生还者与特感表现评估回合 RatingPro 评分。",
	version = PLUGIN_VERSION,
	url = "https://github.com/PencilMario/L4D2-Competitive-Rework"
};

Logger g_RatingLogger;
// 后端 HTTP 专用 logger：固定写 logs/l4d2_ratingpro_api.log。
// 与 g_RatingLogger 分开，因为后者会被 RecordRatingSettlement 改成每局一个文件名。
Logger g_ApiLogger;

ConVar g_hEnabled;
ConVar g_hDelay;
ConVar g_hMinRaw;
StringMap g_hLastTankRaw;
int g_iRawHistoryNextSlot;
int g_iRawHistoryCount;
StringMap g_hRawHistory[RAW_HISTORY_SLOTS];
StringMap g_hRawActionHistory[RAW_HISTORY_SLOTS];
char g_sRawHistoryMap[RAW_HISTORY_SLOTS][MAP_NAME_LENGTH];

StringMap g_hLastRatingSnapshot;
StringMap g_hLastRatingSnapshotNames;
int g_iSnapshotRoundId;
bool g_bHasSnapshot;
char g_sSnapshotMap[MAP_NAME_LENGTH];
char g_sSnapshotMaps[SNAPSHOT_MAP_LIST_CELLS];
int g_iSnapshotMapCount;
char g_sSnapshotTime[64];
float g_fLastQueryTime[MAXPLAYERS + 1];

bool g_bRoundEnded;

// 本图结果：由双方地图分判定，按「第二半场所在方」的编号（2=生还方 / 3=特感方）记录，
// 与 players[].team 同口径。后端拿它走「表现 + 胜负」混合 ELO，`team_scores` 用来展示比分。
// 0 / -1 = 未判定或读不到（打平、只有一队打过分、left4dhooks 缺失）。
//
// 判定分两段：
//   1. 第一半场结束时记下「哪支逻辑队当生还者」（RememberFirstHalfSurvivorTeam），
//      第二半场开场再补读一次 —— round_end 那一刻地图分常常还没落账。
//   2. 第二半场结算时读双方地图分（ResolveMapWinner），没读全就按秒重试。
// 把逻辑队 A/B 换算成 2/3 队伍编号需要第一段的结果，所以映射未知时比分与胜负一起不发。
int g_iFirstHalfLogicalTeam;
int g_iFirstHalfScoreA = -1;
int g_iFirstHalfScoreB = -1;
int g_iMapScoreA = -1;
int g_iMapScoreB = -1;
int g_iMapWinnerTeam;
int g_iMapResultAttempts;

// 参与者记录按 SteamID（Steam2）归档：退服后数据仍保留，直到本图结算生成新快照为止。
char g_sParticipantAuth[MAX_PARTICIPANTS][64];
char g_sParticipantName[MAX_PARTICIPANTS][MAX_NAME_LENGTH];
int g_iParticipantTeam[MAX_PARTICIPANTS];
// 是否在第二半场露过面：没露面的人最后所在边是第一半场的边，结算队伍要取反。
bool g_bParticipantSecondHalf[MAX_PARTICIPANTS];
int g_iParticipantCount;
bool g_bParticipantOverflowLogged;

// 客户端槽位到 SteamID 的缓存，槽位复用时立即失效，避免把两个玩家算成同一人。
char g_sClientAuth[MAXPLAYERS + 1][64];

int g_iSiDamage[MAX_PARTICIPANTS];
int g_iCiKilled[MAX_PARTICIPANTS];
int g_iTankDamage[MAX_PARTICIPANTS];
int g_iDmgTaken[MAX_PARTICIPANTS];
int g_iIncaps[MAX_PARTICIPANTS];
int g_iDied[MAX_PARTICIPANTS];
int g_iFfGiven[MAX_PARTICIPANTS];

int g_iSiDamageTankup[MAX_PARTICIPANTS];
int g_iSiKilledTankup[MAX_PARTICIPANTS];
int g_iSkeets[MAX_PARTICIPANTS];
int g_iLevels[MAX_PARTICIPANTS];
int g_iPops[MAX_PARTICIPANTS];
int g_iTongueCuts[MAX_PARTICIPANTS];
int g_iCrowns[MAX_PARTICIPANTS];

int g_iInfDmgTotal[MAX_PARTICIPANTS];
int g_iInfBooms[MAX_PARTICIPANTS];
// 胆汁覆盖是实体的即时状态而非玩家累计数据，仍按客户端槽位记录。
bool g_bBiled[MAXPLAYERS + 1];
int g_iInfDeathCharges[MAX_PARTICIPANTS];

int g_iTankDmgUpright[MAX_PARTICIPANTS];
int g_iTankPunch[MAX_PARTICIPANTS];
int g_iTankRock[MAX_PARTICIPANTS];
int g_iTankHittable[MAX_PARTICIPANTS];
int g_iTankIncap[MAX_PARTICIPANTS];
int g_iTankDeath[MAX_PARTICIPANTS];
bool g_bBecameTank[MAX_PARTICIPANTS];

// ============================ 后端接入：配置与回调 ============================

ConVar g_hApiEnabled;
ConVar g_hApiBase;
ConVar g_hApiKey;
ConVar g_hServerKey;
ConVar g_hUploadMaps;
ConVar g_hMinPlayers;
ConVar g_hAutoRefresh;
ConVar g_hScoreGuard;
ConVar g_hApiLog;

Handle g_hFwdClientDataLoaded;
Handle g_hFwdClientEloUpdated;
Handle g_hFwdEloUploaded;

// ============================ 后端接入：玩家缓存 ============================
// 缓存按客户端槽位存放，槽位复用时令牌立即失效，避免旧请求把数据写到新玩家身上。
RatingProClientInfo g_ClientInfo[MAXPLAYERS + 1];
int g_iClientToken[MAXPLAYERS + 1];
bool g_bEloRequestInFlight[MAXPLAYERS + 1];
bool g_bRatingRequestInFlight[MAXPLAYERS + 1];
bool g_bApiKeyWarned;

// 每个玩家最近一次 ELO 请求的失败原因（成功/404 时清空）。
// !apidebug 直接把它打出来，不用先开日志再复现。
char g_sClientApiError[MAXPLAYERS + 1][CLIENT_API_ERROR_LENGTH];

// HTTP 回调是主线程序列执行的，响应体共用一块静态缓冲即可，避免频繁堆分配。
char g_sHttpResponse[HTTP_RESPONSE_SIZE];

// ============================ 后端接入：战役（同一章节序列）跟踪 ============================
// 一段序列 = 连续结算、双方战役累计比分单调不减的一组地图。
// 判据只有比分这一条，也不解析地图名 —— 仓库里有插件能把随机地图拼成章节序列，
// 前缀和章节号在那种服务器上说明不了连续性，所以「按图名判断」这条路径整条都不存在。
// 序列中断时只重置上传计数（本段不完整对局不上传），评分窗口保持原始跨图口径。
char g_sCampaignStartMap[MAP_NAME_LENGTH];  // 本段第一张图的图名（仅日志定位）
int g_iCampaignSeqId;                       // 段序号，每断一次 +1；评分窗口用它在槽位里标记归属
int g_iRawHistorySeq[RAW_HISTORY_SLOTS];    // 槽位写入时所处的段序号（0 = 尚未记录）
int g_iCampaignMaps;
int g_iCampaignLastScoreA;
int g_iCampaignLastScoreB;
bool g_bCampaignHasScoreBaseline;

// ============================ 后端接入：上传 ============================
char g_sUploadPayload[UPLOAD_PAYLOAD_SIZE];
char g_sUploadExternalId[256];
int g_iUploadAttempts;
bool g_bUploadInFlight;
bool g_bUploadPending;
int g_iPendingUploadSnapshotId;
int g_iPendingUploadPlayerCount;
int g_iUploadToken;


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("RatingPro_GetClientCacheStatus", Native_GetClientCacheStatus);
	CreateNative("RatingPro_IsClientDataReady", Native_IsClientDataReady);
	CreateNative("RatingPro_GetClientElo", Native_GetClientElo);
	CreateNative("RatingPro_GetClientEloValue", Native_GetClientEloValue);
	CreateNative("RatingPro_GetClientPeakElo", Native_GetClientPeakElo);
	CreateNative("RatingPro_GetClientEloRank", Native_GetClientEloRank);
	CreateNative("RatingPro_GetClientEloTotalPlayers", Native_GetClientEloTotalPlayers);
	CreateNative("RatingPro_GetClientEloRounds", Native_GetClientEloRounds);
	CreateNative("RatingPro_GetClientEloKFactor", Native_GetClientEloKFactor);
	CreateNative("RatingPro_GetClientPlacementPlayed", Native_GetClientPlacementPlayed);
	CreateNative("RatingPro_GetClientPlacementRequired", Native_GetClientPlacementRequired);
	CreateNative("RatingPro_GetClientLastEloDelta", Native_GetClientLastEloDelta);
	CreateNative("RatingPro_GetClientRecentRating", Native_GetClientRecentRating);
	CreateNative("RatingPro_GetClientRecentRatingAverage", Native_GetClientRecentRatingAverage);
	CreateNative("RatingPro_GetClientRecentRatingCount", Native_GetClientRecentRatingCount);
	CreateNative("RatingPro_GetClientRecentRatingAt", Native_GetClientRecentRatingAt);
	CreateNative("RatingPro_RefreshClientData", Native_RefreshClientData);
	CreateNative("RatingPro_GetSnapshotId", Native_GetSnapshotId);
	CreateNative("RatingPro_GetCampaignMapCount", Native_GetCampaignMapCount);
	CreateNative("RatingPro_HasPendingUpload", Native_HasPendingUpload);

	// left4dhooks 缺失时后端仍可上传，只是少一层「比分不减」的连续性校验。
	MarkNativeAsOptional("L4D_GetTeamScore");

	RegPluginLibrary("l4d2_round_ratingpro");

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_RatingLogger = new Logger("ratingpro", LoggerType_NewLogFile);
	// 级别过滤交给 sm_ratingpro_api_log：logger 自身不过滤，WritetoLogFile 才拿得到原始级别。
	g_ApiLogger = new Logger(API_LOG_NAME, LoggerType_NewLogFile);
	g_ApiLogger.IgnoreLevel = LogType_Debug;
	g_hLastTankRaw = new StringMap();
	g_iRawHistoryNextSlot = 0;
	g_iRawHistoryCount = 0;
	for (int slot = 0; slot < RAW_HISTORY_SLOTS; slot++)
	{
		g_hRawHistory[slot] = new StringMap();
		g_hRawActionHistory[slot] = new StringMap();
		g_sRawHistoryMap[slot][0] = '\0';
	}

	g_hLastRatingSnapshot = new StringMap();
	g_hLastRatingSnapshotNames = new StringMap();
	g_iSnapshotRoundId = 0;
	g_bHasSnapshot = false;
	g_sSnapshotMap[0] = '\0';
	g_sSnapshotMaps[0] = '\0';
	g_sSnapshotTime[0] = '\0';

	g_hEnabled = CreateConVar("sm_round_ratingpro_enabled", "1", "启用回合结束时 RatingPro 最佳表现播报与查询功能。", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hDelay = CreateConVar("sm_round_ratingpro_delay", "3.0", "回合结束后延迟公布最佳 RatingPro 玩家的秒数。", FCVAR_NONE, true, 0.0, true, 15.0);
	g_hMinRaw = CreateConVar("sm_round_ratingpro_min_raw", "1.0", "公布最佳表现所需的最低加权原始分阈值。", FCVAR_NONE, true, 0.0, true, 10.0);
	CreateConVar("sm_round_ratingpro_version", PLUGIN_VERSION, "L4D2 回合 RatingPro 插件版本。", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	CreateApiConVars();
	InitializeApi();

	// 让 cfg/sourcemod/l4d2_round_ratingpro.cfg 真正被执行：sourcemod 只会自动执行
	// 调用了 AutoExecConfig 的插件配置，缺这一句时那个文件形同废纸（API Key 也读不到）。
	AutoExecConfig(true, "l4d2_round_ratingpro");

	RegConsoleCmd("sm_ratingpro", Command_RatingPro, "查询玩家 RatingPro 评分数据快照。");
	RegConsoleCmd("sm_rating", Command_RatingPro, "查询玩家 RatingPro 评分数据快照（别名）。");
	RegConsoleCmd("sm_rt", Command_RatingPro, "查询玩家 RatingPro 评分数据快照（别名）。");
	RegAdminCmd("sm_ratingpro_apidebug", Command_ApiDebug, ADMFLAG_ROOT,
		"查看后端接入状态、战役累计与在线玩家 ELO 缓存；附加任意参数可打印待上传载荷。");

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("scavenge_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("map_transition", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("finale_vehicle_leaving", Event_RoundEnd, EventHookMode_PostNoCopy);

	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("infected_death", Event_InfectedDeath, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_incapacitated", Event_PlayerIncapacitated, EventHookMode_Post);
	HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_Post);
	HookEvent("bot_player_replace", Event_BotPlayerReplace, EventHookMode_Post);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_now_it", Event_PlayerBiled, EventHookMode_Post);
	HookEvent("player_no_longer_it", Event_PlayerUnbiled, EventHookMode_Post);
	HookEvent("player_bot_replace", Event_PlayerBotReplace, EventHookMode_Post);

	ResetRoundStats();
}

public void OnMapStart()
{
	ResetRoundStats();
}

// cfg 里的 cvar 在 OnPluginStart 之后才被 AutoExecConfig 执行，会话头必须放在这里，
// 否则日志里记的是默认值（尤其是 api_base / server_key）。
public void OnConfigsExecuted()
{
	char base[256];
	g_hApiBase.GetString(base, sizeof(base));

	char serverKey[PLATFORM_MAX_PATH];
	GetServerKey(serverKey, sizeof(serverKey));

	char apiKey[256];
	g_hApiKey.GetString(apiKey, sizeof(apiKey));

	ApiLog(LogType_Info, "======== 会话开始：插件 %s · 日志级别 %d · base=%s · server_key=%s · api_key=%s ========",
		PLUGIN_VERSION, g_hApiLog.IntValue, base, serverKey,
		apiKey[0] == '\0' ? "未配置（只读不上传）" : "已配置");
}

public void OnClientDisconnect(int client)
{
	if (IsValidClientIndex(client))
	{
		// 参与者记录不随退服删除：数据保留到本图结算生成快照。
		g_bBiled[client] = false;
		g_fLastQueryTime[client] = 0.0;
		g_sClientAuth[client][0] = '\0';

		// 令牌自增让仍在途中的 HTTP 响应作废，不会写回复用该槽位的新玩家。
		g_iClientToken[client]++;
		ResetClientApiCache(client);
	}
}

public void OnClientPutInServer(int client)
{
	if (IsValidClientIndex(client))
	{
		// 客户端槽位可能被新玩家复用，丢弃旧 Auth 缓存，下一次事件再按需解析。
		g_sClientAuth[client][0] = '\0';
		g_bBiled[client] = false;
		g_fLastQueryTime[client] = 0.0;

		g_iClientToken[client]++;
		ResetClientApiCache(client);
	}
}

// Steam 认证完成后才能拿到稳定 SteamID，此时才请求 ELO 与最近 5 场平均值。
public void OnClientPostAdminCheck(int client)
{
	if (!IsHumanClient(client) || !g_hAutoRefresh.BoolValue)
	{
		return;
	}

	RequestClientApiData(client);
}

// 解析并缓存客户端所属 SteamID；未完成认证或实体无效时返回 false。
bool GetClientAuthKey(int client, char[] key, int size)
{
	if (!IsHumanClient(client))
	{
		return false;
	}

	if (g_sClientAuth[client][0] == '\0')
	{
		if (!GetClientAuthId(client, AuthId_Steam2, g_sClientAuth[client], sizeof(g_sClientAuth[]), true))
		{
			return false;
		}
	}

	if (size > 0)
	{
		strcopy(key, size, g_sClientAuth[client]);
	}
	return true;
}

int FindParticipantByAuth(const char[] auth)
{
	for (int participant = 0; participant < g_iParticipantCount; participant++)
	{
		if (StrEqual(g_sParticipantAuth[participant], auth, false))
		{
			return participant;
		}
	}
	return -1;
}

// 事件发生时取得参与者记录：不存在则按 SteamID 新建，并刷新姓名与队伍。
int AcquireParticipant(int client)
{
	char auth[64];
	if (!GetClientAuthKey(client, auth, sizeof(auth)))
	{
		return -1;
	}

	int participant = FindParticipantByAuth(auth);
	if (participant < 0)
	{
		if (g_iParticipantCount >= MAX_PARTICIPANTS)
		{
			if (!g_bParticipantOverflowLogged)
			{
				g_bParticipantOverflowLogged = true;
				LogError("[RatingPro] 参与者记录已满 (%d)，本图后续新玩家的数据将被忽略。", MAX_PARTICIPANTS);
			}
			return -1;
		}

		participant = g_iParticipantCount;
		g_iParticipantCount++;
		strcopy(g_sParticipantAuth[participant], sizeof(g_sParticipantAuth[]), auth);
	}

	GetClientName(client, g_sParticipantName[participant], sizeof(g_sParticipantName[]));
	g_iParticipantTeam[participant] = GetClientTeam(client);

	// 对抗每图换边，队伍编号统一按「第二半场所在方」定义：这里只记这个人有没有在第二半场露面，
	// 生成快照时再决定是否需要取反（见 ResolveSnapshotTeam）。
	if (InSecondHalfOfRound())
	{
		g_bParticipantSecondHalf[participant] = true;
	}

	return participant;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnded = false;
	for (int client = 1; client <= MaxClients; client++)
	{
		g_bBiled[client] = false;
	}

	// 第二半场开局再确认一次「第一半场谁当生还者」：round_end 那一刻地图分可能还没落账
	// （L4D_GetTeamScore 会返回 -1），到半场真正开始时读到的才是稳定值。
	if (g_iFirstHalfLogicalTeam == 0 && InSecondHalfOfRound())
	{
		RememberFirstHalfSurvivorTeam();

		// 个别环境半场刚开时仍返回 -1：隔两秒再补一次（只补，不覆盖已经定下来的值）。
		if (g_iFirstHalfLogicalTeam == 0)
		{
			CreateTimer(2.0, Timer_RememberFirstHalfTeam, _, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_hEnabled.BoolValue || g_bRoundEnded)
	{
		return;
	}

	g_bRoundEnded = true;

	if (!InSecondHalfOfRound())
	{
		// 第一半场结束：记下这半场当生还者的是哪支逻辑队，第二半场结算时用它换算胜方编号。
		RememberFirstHalfSurvivorTeam();
		return;
	}

	CreateTimer(g_hDelay.FloatValue, Timer_PrintBestRating, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_hEnabled.BoolValue || g_bRoundEnded)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int damage = event.GetInt("dmg_health");
	if (damage <= 0)
	{
		return;
	}

	if (IsHumanClient(victim))
	{
		int victimParticipant = AcquireParticipant(victim);
		if (victimParticipant >= 0 && g_iParticipantTeam[victimParticipant] == TEAM_SURVIVOR)
		{
			if (!IsSurvivorIncapacitated(victim))
			{
				g_iDmgTaken[victimParticipant] += damage;
			}
		}
	}

	if (!IsHumanClient(attacker))
	{
		return;
	}

	int attackerParticipant = AcquireParticipant(attacker);
	if (attackerParticipant < 0)
	{
		return;
	}

	int attackerTeam = g_iParticipantTeam[attackerParticipant];
	int victimTeam = IsHumanClient(victim) ? GetClientTeam(victim) : 0;

	if (attackerTeam == TEAM_SURVIVOR)
	{
		if (victimTeam == TEAM_INFECTED)
		{
			int zombieClass = GetZombieClass(victim);
			if (zombieClass == ZC_TANK)
			{
				g_iTankDamage[attackerParticipant] += damage;
			}
			else
			{
				g_iSiDamage[attackerParticipant] += damage;
				if (IsTankInPlay())
				{
					g_iSiDamageTankup[attackerParticipant] += damage;
				}
			}
		}
		else if (victimTeam == TEAM_SURVIVOR && attacker != victim)
		{
			g_iFfGiven[attackerParticipant] += damage;
		}
	}
	else if (attackerTeam == TEAM_INFECTED && victimTeam == TEAM_SURVIVOR)
	{
		int zombieClass = GetZombieClass(attacker);
		if (zombieClass == ZC_TANK)
		{
			TrackTankHit(attackerParticipant, victim, damage, event);
		}
		else if (!IsSurvivorIncapacitated(victim))
		{
			g_iInfDmgTotal[attackerParticipant] += damage;
		}
	}
}

public void Event_InfectedDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_hEnabled.BoolValue || g_bRoundEnded)
	{
		return;
	}

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!IsHumanClient(attacker))
	{
		return;
	}

	int participant = AcquireParticipant(attacker);
	if (participant < 0 || g_iParticipantTeam[participant] != TEAM_SURVIVOR)
	{
		return;
	}

	g_iCiKilled[participant]++;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (IsValidClientIndex(victim))
	{
		g_bBiled[victim] = false;
	}

	if (!g_hEnabled.BoolValue || g_bRoundEnded)
	{
		return;
	}

	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if (IsHumanClient(victim))
	{
		int victimParticipant = AcquireParticipant(victim);
		if (victimParticipant >= 0 && g_iParticipantTeam[victimParticipant] == TEAM_SURVIVOR)
		{
			g_iDied[victimParticipant]++;
		}
	}

	if (!IsHumanClient(attacker))
	{
		return;
	}

	int attackerParticipant = AcquireParticipant(attacker);
	if (attackerParticipant < 0)
	{
		return;
	}

	bool victimIsSurvivor = IsHumanClient(victim) && GetClientTeam(victim) == TEAM_SURVIVOR;
	bool victimIsInfected = IsHumanClient(victim) && GetClientTeam(victim) == TEAM_INFECTED;

	if (g_iParticipantTeam[attackerParticipant] == TEAM_SURVIVOR && victimIsInfected && GetZombieClass(victim) != ZC_TANK && IsTankInPlay())
	{
		g_iSiKilledTankup[attackerParticipant]++;
	}
	else if (g_iParticipantTeam[attackerParticipant] == TEAM_INFECTED && GetZombieClass(attacker) == ZC_TANK && victimIsSurvivor)
	{
		MarkClientAsTank(attacker);
		g_iTankDeath[attackerParticipant]++;
	}
}

public void Event_PlayerIncapacitated(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_hEnabled.BoolValue || g_bRoundEnded)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if (IsHumanClient(victim))
	{
		int victimParticipant = AcquireParticipant(victim);
		if (victimParticipant >= 0 && g_iParticipantTeam[victimParticipant] == TEAM_SURVIVOR)
		{
			g_iIncaps[victimParticipant]++;
		}
	}

	if (IsHumanClient(attacker) && GetClientTeam(attacker) == TEAM_INFECTED && GetZombieClass(attacker) == ZC_TANK)
	{
		int attackerParticipant = MarkClientAsTank(attacker);
		if (attackerParticipant >= 0)
		{
			g_iTankIncap[attackerParticipant]++;
		}
	}
}

// 记录该玩家本图出过克，返回其参与者槽位（无 SteamID 时 -1）。
int MarkClientAsTank(int client)
{
	int participant = AcquireParticipant(client);
	if (participant >= 0)
	{
		g_bBecameTank[participant] = true;
	}
	return participant;
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_hEnabled.BoolValue || g_bRoundEnded)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsHumanClient(client) && GetClientTeam(client) == TEAM_INFECTED)
	{
		MarkClientAsTank(client);
	}
}

public void Event_BotPlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
	int bot = GetClientOfUserId(event.GetInt("bot"));
	int player = GetClientOfUserId(event.GetInt("player"));
	if (IsValidClientIndex(bot) && IsValidClientIndex(player))
	{
		g_bBiled[player] = g_bBiled[bot];
		g_bBiled[bot] = false;
	}

	if (!g_hEnabled.BoolValue || g_bRoundEnded)
	{
		return;
	}

	if (IsHumanClient(player) && GetClientTeam(player) == TEAM_INFECTED && GetZombieClass(player) == ZC_TANK)
	{
		MarkClientAsTank(player);
	}
}

public void Event_PlayerBotReplace(Event event, const char[] name, bool dontBroadcast)
{
	int bot = GetClientOfUserId(event.GetInt("bot"));
	int player = GetClientOfUserId(event.GetInt("player"));
	if (IsValidClientIndex(bot) && IsValidClientIndex(player))
	{
		g_bBiled[bot] = g_bBiled[player];
		g_bBiled[player] = false;
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsValidClientIndex(client))
	{
		g_bBiled[client] = false;
	}

	if (!g_hEnabled.BoolValue || g_bRoundEnded)
	{
		return;
	}

	if (IsHumanClient(client) && GetClientTeam(client) == TEAM_INFECTED && GetZombieClass(client) == ZC_TANK)
	{
		MarkClientAsTank(client);
	}
}

public void OnSkeet(int survivor, int hunter)
{
	AddFocusCounter(survivor, g_iSkeets);
}

public void OnSkeetMelee(int survivor, int hunter)
{
	AddFocusCounter(survivor, g_iSkeets);
}

public void OnSkeetGL(int survivor, int hunter)
{
	AddFocusCounter(survivor, g_iSkeets);
}

public void OnSkeetSniper(int survivor, int hunter)
{
	AddFocusCounter(survivor, g_iSkeets);
}

public void OnBoomerPop(int survivor, int boomer, int shoveCount, float timeAlive)
{
	AddFocusCounter(survivor, g_iPops);
}

public void OnChargerLevel(int survivor, int charger)
{
	AddFocusCounter(survivor, g_iLevels);
}

public void OnWitchCrown(int survivor, int damage)
{
	AddFocusCounter(survivor, g_iCrowns);
}

public void OnWitchCrownHurt(int survivor, int damage, int chipdamage)
{
	AddFocusCounter(survivor, g_iCrowns);
}

public void OnTongueCut(int survivor, int smoker)
{
	AddFocusCounter(survivor, g_iTongueCuts);
}

public void Event_PlayerBiled(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClientIndex(victim) || !IsClientInGame(victim) || GetClientTeam(victim) != TEAM_SURVIVOR || g_bBiled[victim])
	{
		return;
	}

	g_bBiled[victim] = true;

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!g_hEnabled.BoolValue || g_bRoundEnded || !IsHumanClient(attacker) || GetClientTeam(attacker) != TEAM_INFECTED)
	{
		return;
	}

	int participant = AcquireParticipant(attacker);
	if (participant >= 0)
	{
		g_iInfBooms[participant]++;
	}
}

public void Event_PlayerUnbiled(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (IsValidClientIndex(victim))
	{
		g_bBiled[victim] = false;
	}
}

public void OnDeathCharge(int charger, int survivor, float height, float distance, bool wasCarried)
{
	int participant = AcquireParticipant(charger);
	if (participant >= 0)
	{
		g_iInfDeathCharges[participant]++;
	}
}

public void OnTankRockEaten(int tank, int survivor)
{
	int participant = AcquireParticipant(tank);
	if (participant >= 0)
	{
		g_iTankRock[participant]++;
	}
}

public Action Timer_PrintBestRating(Handle timer)
{
	// 本图胜负与比分必须在生成快照、上传之前定下来；读不全就按秒重试。
	// 重试放在 UpdateCampaignProgress 之前 —— 那里会累加「本段已结算张数」，
	// 重试路径重复调用会把同一张图算成两张。
	if (!ResolveMapWinner())
	{
		if (g_iMapResultAttempts < MAP_RESULT_MAX_ATTEMPTS)
		{
			g_iMapResultAttempts++;
			LogMessage("[RatingPro] 地图分还没落账，%.1f 秒后重试判定（%d/%d）。",
				MAP_RESULT_RETRY_DELAY, g_iMapResultAttempts, MAP_RESULT_MAX_ATTEMPTS);
			CreateTimer(MAP_RESULT_RETRY_DELAY, Timer_PrintBestRating, _, TIMER_FLAG_NO_MAPCHANGE);
			return Plugin_Stop;
		}

		LogMessage("[RatingPro] 地图分重试 %d 次仍未读到，本图不判定胜负，也不上报比分。",
			g_iMapResultAttempts);
	}

	// 先判定本图是否仍属于同一战役：中途换图会在这里重置上传计数（本段不上传）。
	UpdateCampaignProgress();

	SaveLatestTankRaw();
	SaveRoundRawHistory();

	float outputMin;
	float outputMax;
	float defenseMin;
	float defenseMax;
	float focusMin;
	float focusMax;
	float infectorMin;
	float infectorMax;
	float tankMin;
	float tankMax;

	if (!BuildRawRanges(outputMin, outputMax, defenseMin, defenseMax, focusMin, focusMax, infectorMin, infectorMax, tankMin, tankMax))
	{
		SaveRatingSnapshot(false, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
		RecordRatingSettlement();
		MaybeUploadCampaign();
		CPrintToChatAll("{blue}[{green}RatingPro{blue}]{default} 本章节没有足够数据生成最佳表现。");
		PrintAllClientRatingDetailsNoData();
		PrintAllClientRatingDetailsToConsoleNoData();
		PromptRatingQuery();
		return Plugin_Stop;
	}

	SaveRatingSnapshot(true, outputMin, outputMax, defenseMin, defenseMax, focusMin, focusMax, infectorMin, infectorMax, tankMin, tankMax);
	RecordRatingSettlement();
	MaybeUploadCampaign();

	int bestParticipant = -1;
	float bestRating = 0.0;
	float bestRaw = 0.0;

	for (int participant = 0; participant < g_iParticipantCount; participant++)
	{
		if (!IsEligibleForRating(participant))
		{
			continue;
		}

		float output = NormalizeRaw(GetHistoricalOutputRaw(g_sParticipantAuth[participant]), outputMin, outputMax);
		float defense = NormalizeRaw(GetHistoricalDefenseRaw(g_sParticipantAuth[participant]), defenseMin, defenseMax);
		float focus = NormalizeRaw(GetHistoricalFocusRaw(g_sParticipantAuth[participant]), focusMin, focusMax);
		float infector = NormalizeRaw(GetHistoricalInfectorRaw(g_sParticipantAuth[participant]), infectorMin, infectorMax);
		float tank = NormalizeTankRaw(GetEffectiveTankRaw(participant), tankMin, tankMax);
		float raw = GetWeightedRaw(output, defense, focus, infector, tank);
		float rating = Pow(raw / 10.0, RATING_EXPONENT) * 10.0;

		if (bestParticipant < 0 || rating > bestRating)
		{
			bestParticipant = participant;
			bestRating = rating;
			bestRaw = raw;
		}
	}

	if (bestParticipant < 0 || bestRaw < g_hMinRaw.FloatValue)
	{
		CPrintToChatAll("{blue}[{green}RatingPro{blue}]{default} 本章节没有足够数据生成最佳表现。");
		PrintOnlineClientRatingDetails();
		PrintAllClientRatingDetailsToConsole();
		PromptRatingQuery();
		return Plugin_Stop;
	}

	CPrintToChatAll("{blue}[{green}RatingPro{blue}]{default} 章节最佳: {olive}%s{default} rating {green}%.1f",
		g_sParticipantName[bestParticipant], bestRating);
	PrintOnlineClientRatingDetails();
	PrintAllClientRatingDetailsToConsole();
	// 结算完成后向在线真人提示输入 !rating 查看详细数据
	PromptRatingQuery();

	return Plugin_Stop;
}

void PrintAllClientRatingDetailsNoData()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanClient(client))
		{
			continue;
		}

		CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 本章节没有足够数据生成你的 RatingPro。");
	}
}

// 聊天明细只发给在线真人；数值直接取刚生成的快照，保证与结算日志一致。
void PrintOnlineClientRatingDetails()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanClient(client))
		{
			continue;
		}

		char auth[64];
		RatingSnapshotEntry entry;
		if (!GetClientAuthKey(client, auth, sizeof(auth))
			|| !g_hLastRatingSnapshot.GetArray(auth, entry, sizeof(entry))
			|| !entry.eligible)
		{
			CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 本章节没有足够数据生成你的 RatingPro。");
			continue;
		}

		CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 你的评分 {green}%.1f{default} 综合 {olive}%.1f{default} | 输出 %.1f 防守 %.1f 关键操作 %.1f 特感进攻 %.1f Tank表现 %.1f",
			entry.rating, entry.raw, entry.output, entry.defense, entry.focus, entry.infector, entry.tank);
	}
}

// 控制台明细覆盖全部参与者，包含结算前已退服的玩家。
void PrintAllClientRatingDetailsToConsoleNoData()
{
	PrintToServer("[RatingPro] No enough round data to generate RatingPro details.");

	for (int participant = 0; participant < g_iParticipantCount; participant++)
	{
		PrintToServer("[RatingPro] %s (%s) team=%d: no enough RatingPro data.",
			g_sParticipantName[participant], g_sParticipantAuth[participant], g_iParticipantTeam[participant]);
	}
}

void PrintAllClientRatingDetailsToConsole()
{
	PrintToServer("[RatingPro] Round player details:");

	for (int participant = 0; participant < g_iParticipantCount; participant++)
	{
		RatingSnapshotEntry entry;
		if (!g_hLastRatingSnapshot.GetArray(g_sParticipantAuth[participant], entry, sizeof(entry)) || !entry.eligible)
		{
			PrintToServer("[RatingPro] %s (%s) team=%d: no enough RatingPro data.",
				g_sParticipantName[participant], g_sParticipantAuth[participant], g_iParticipantTeam[participant]);
			continue;
		}

		PrintToServer("[RatingPro] %s (%s) team=%d rating=%.1f raw=%.1f normalized(output=%.1f defense=%.1f focus=%.1f infector=%.1f tank=%.1f)",
			g_sParticipantName[participant], g_sParticipantAuth[participant], g_iParticipantTeam[participant],
			entry.rating, entry.raw, entry.output, entry.defense, entry.focus, entry.infector, entry.tank);
		PrintToServer("[RatingPro] %s raw(output=%.1f defense=%.1f focus=%.1f infector=%.1f tank=%.1f)",
			g_sParticipantName[participant], entry.outputRaw, entry.defenseRaw, entry.focusRaw, entry.infectorRaw, entry.tankRaw);
		PrintToServer("[RatingPro] %s survivor(跨章节累计%d槽 siDmg=%d ciKill=%d tankDmg=%d dmgTaken=%d incaps=%d deaths=%d ff=%d tankupDmg=%d tankupKill=%d skeet=%d level=%d pop=%d tongueCut=%d crown=%d)",
			g_sParticipantName[participant], entry.recordedSlots, entry.siDmg, entry.ciKill, entry.tankDmg, entry.dmgTaken, entry.incaps, entry.deaths, entry.ff,
			entry.tankupDmg, entry.tankupKill, entry.skeet, entry.level, entry.pop, entry.tongueCut, entry.crown);
		PrintToServer("[RatingPro] %s infected(跨章节累计%d槽 dmg=%d booms=%d deathCharges=%d tankDmgUpright=%d punch=%d rock=%d hittable=%d incap=%d death=%d)",
			g_sParticipantName[participant], entry.recordedSlots, entry.dmg, entry.booms, entry.deathCharges, entry.tankDmgUpright, entry.punch, entry.rock, entry.hittable, entry.incap, entry.death);
	}
}

void ResetRoundStats()
{
	g_bRoundEnded = false;
	g_iParticipantCount = 0;
	g_bParticipantOverflowLogged = false;
	g_iFirstHalfLogicalTeam = 0;
	g_iFirstHalfScoreA = -1;
	g_iFirstHalfScoreB = -1;
	g_iMapScoreA = -1;
	g_iMapScoreB = -1;
	g_iMapWinnerTeam = 0;
	g_iMapResultAttempts = 0;

	for (int participant = 0; participant < MAX_PARTICIPANTS; participant++)
	{
		g_sParticipantAuth[participant][0] = '\0';
		g_sParticipantName[participant][0] = '\0';
		g_iParticipantTeam[participant] = 0;
		g_bParticipantSecondHalf[participant] = false;

		g_iSiDamage[participant] = 0;
		g_iCiKilled[participant] = 0;
		g_iTankDamage[participant] = 0;
		g_iDmgTaken[participant] = 0;
		g_iIncaps[participant] = 0;
		g_iDied[participant] = 0;
		g_iFfGiven[participant] = 0;

		g_iSiDamageTankup[participant] = 0;
		g_iSiKilledTankup[participant] = 0;
		g_iSkeets[participant] = 0;
		g_iLevels[participant] = 0;
		g_iPops[participant] = 0;
		g_iTongueCuts[participant] = 0;
		g_iCrowns[participant] = 0;

		g_iInfDmgTotal[participant] = 0;
		g_iInfBooms[participant] = 0;
		g_iInfDeathCharges[participant] = 0;

		g_iTankDmgUpright[participant] = 0;
		g_iTankPunch[participant] = 0;
		g_iTankRock[participant] = 0;
		g_iTankHittable[participant] = 0;
		g_iTankIncap[participant] = 0;
		g_iTankDeath[participant] = 0;
		g_bBecameTank[participant] = false;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		g_bBiled[client] = false;
	}
}

void TrackTankHit(int tankParticipant, int survivor, int damage, Event event)
{
	if (tankParticipant < 0)
	{
		return;
	}

	g_bBecameTank[tankParticipant] = true;

	if (!IsSurvivorIncapacitated(survivor))
	{
		g_iInfDmgTotal[tankParticipant] += damage;
		g_iTankDmgUpright[tankParticipant] += damage;
	}

	char weapon[64];
	event.GetString("weapon", weapon, sizeof(weapon));

	if (StrContains(weapon, "tank_claw", false) != -1 || StrEqual(weapon, "tank", false))
	{
		g_iTankPunch[tankParticipant]++;
	}
	else if (StrContains(weapon, "rock", false) != -1)
	{
		g_iTankRock[tankParticipant]++;
	}
	else if (StrContains(weapon, "prop", false) != -1 || StrContains(weapon, "hittable", false) != -1 || StrContains(weapon, "physics", false) != -1)
	{
		g_iTankHittable[tankParticipant]++;
	}
}

void AddFocusCounter(int client, int counters[MAX_PARTICIPANTS])
{
	int participant = AcquireParticipant(client);
	if (participant >= 0)
	{
		counters[participant]++;
	}
}

bool IsEligibleForRating(int participant)
{
	if (participant < 0 || participant >= g_iParticipantCount)
	{
		return false;
	}

	return HasAnyRawSignal(participant);
}

bool HasAnyRawSignal(int participant)
{
	return g_iSiDamage[participant] > 0
		|| g_iCiKilled[participant] > 0
		|| g_iTankDamage[participant] > 0
		|| g_iDmgTaken[participant] > 0
		|| g_iIncaps[participant] > 0
		|| g_iDied[participant] > 0
		|| g_iFfGiven[participant] > 0
		|| g_iSiDamageTankup[participant] > 0
		|| g_iSiKilledTankup[participant] > 0
		|| g_iSkeets[participant] > 0
		|| g_iLevels[participant] > 0
		|| g_iPops[participant] > 0
		|| g_iTongueCuts[participant] > 0
		|| g_iCrowns[participant] > 0
		|| g_iInfDmgTotal[participant] > 0
		|| g_iInfBooms[participant] > 0
		|| g_iInfDeathCharges[participant] > 0
		|| g_iTankDmgUpright[participant] > 0
		|| g_iTankPunch[participant] > 0
		|| g_iTankRock[participant] > 0
		|| g_iTankHittable[participant] > 0
		|| g_iTankIncap[participant] > 0
		|| g_iTankDeath[participant] > 0
		|| g_bBecameTank[participant];
}

float GetOutputRaw(int participant)
{
	return float(g_iSiDamage[participant] + g_iTankDamage[participant] + g_iCiKilled[participant] * 10);
}

float GetDefenseRaw(int participant)
{
	return -float(g_iDmgTaken[participant] + g_iIncaps[participant] * 350 + g_iDied[participant] * 80 + g_iFfGiven[participant] * 40);
}

float GetFocusRaw(int participant)
{
	return float(g_iSiDamageTankup[participant]) * 0.004
		+ float(g_iSiKilledTankup[participant]) * 0.25
		+ float(g_iSkeets[participant]) * 2.0
		+ float(g_iLevels[participant]) * 2.0
		+ float(g_iPops[participant]) * 1.5
		+ float(g_iTongueCuts[participant]) * 1.0
		+ float(g_iCrowns[participant]) * 2.0;
}

float GetInfectorRaw(int participant)
{
	return float(g_iInfDmgTotal[participant] + g_iInfBooms[participant] * 8 + g_iInfDeathCharges[participant] * 25);
}

void SaveRoundRawHistory()
{
	int slot = g_iRawHistoryNextSlot;
	g_hRawHistory[slot].Clear();
	g_hRawActionHistory[slot].Clear();
	GetCurrentMap(g_sRawHistoryMap[slot], sizeof(g_sRawHistoryMap[]));
	g_iRawHistorySeq[slot] = g_iCampaignSeqId;
	for (int participant = 0; participant < g_iParticipantCount; participant++)
	{
		if (g_sParticipantAuth[participant][0] == '\0')
		{
			continue;
		}

		float values[4];
		values[0] = GetOutputRaw(participant);
		values[1] = GetDefenseRaw(participant);
		values[2] = GetFocusRaw(participant);
		values[3] = GetInfectorRaw(participant);
		g_hRawHistory[slot].SetArray(g_sParticipantAuth[participant], values, sizeof(values));

		RawHistoryActionEntry entry;
		entry.raw[0] = values[0];
		entry.raw[1] = values[1];
		entry.raw[2] = values[2];
		entry.raw[3] = values[3];

		entry.siDmg = g_iSiDamage[participant];
		entry.ciKill = g_iCiKilled[participant];
		entry.tankDmg = g_iTankDamage[participant];
		entry.dmgTaken = g_iDmgTaken[participant];
		entry.incaps = g_iIncaps[participant];
		entry.deaths = g_iDied[participant];
		entry.ff = g_iFfGiven[participant];
		entry.tankupDmg = g_iSiDamageTankup[participant];
		entry.tankupKill = g_iSiKilledTankup[participant];
		entry.skeet = g_iSkeets[participant];
		entry.level = g_iLevels[participant];
		entry.pop = g_iPops[participant];
		entry.tongueCut = g_iTongueCuts[participant];
		entry.crown = g_iCrowns[participant];

		entry.dmg = g_iInfDmgTotal[participant];
		entry.booms = g_iInfBooms[participant];
		entry.deathCharges = g_iInfDeathCharges[participant];

		g_hRawActionHistory[slot].SetArray(g_sParticipantAuth[participant], entry, sizeof(entry));
	}

	g_iRawHistoryNextSlot = (slot + 1) % RAW_HISTORY_SLOTS;
	if (g_iRawHistoryCount < RAW_HISTORY_SLOTS)
	{
		g_iRawHistoryCount++;
	}
}

// 历史槽位是环形缓冲：index 0 为最早一次已结算的章节，index 增长到最新。
int GetRawHistorySlotByIndex(int chronologicalIndex)
{
	if (g_iRawHistoryCount <= 0 || chronologicalIndex < 0 || chronologicalIndex >= g_iRawHistoryCount)
	{
		return -1;
	}

	if (g_iRawHistoryCount < RAW_HISTORY_SLOTS)
	{
		return chronologicalIndex;
	}

	return (g_iRawHistoryNextSlot + chronologicalIndex) % RAW_HISTORY_SLOTS;
}

// 按时间顺序收集快照覆盖的地图（去重）。auth 为空串时统计整个快照窗口，否则只统计该 SteamID 有数据的槽位。
int CollectHistoryMaps(const char[] auth, char[] buffer, int size, const char[] separator)
{
	if (size <= 0)
	{
		return 0;
	}

	buffer[0] = '\0';

	char maps[RAW_HISTORY_SLOTS][MAP_NAME_LENGTH];
	int mapCount = CollectHistoryMapNames(auth, maps);

	for (int index = 0; index < mapCount; index++)
	{
		if (buffer[0] != '\0')
		{
			StrCat(buffer, size, separator);
		}
		StrCat(buffer, size, maps[index]);
	}

	return mapCount;
}

// 与 CollectHistoryMaps 同源，但返回原始地图名数组，供 JSON 载荷拼装使用。
int CollectHistoryMapNames(const char[] auth, char maps[RAW_HISTORY_SLOTS][MAP_NAME_LENGTH])
{
	bool restrictToPlayer = auth[0] != '\0';

	int mapCount = 0;
	RawHistoryActionEntry historyEntry;

	for (int index = 0; index < g_iRawHistoryCount; index++)
	{
		int slot = GetRawHistorySlotByIndex(index);
		if (slot < 0 || g_sRawHistoryMap[slot][0] == '\0')
		{
			continue;
		}

		if (restrictToPlayer && !g_hRawActionHistory[slot].GetArray(auth, historyEntry, sizeof(historyEntry)))
		{
			continue;
		}

		bool duplicate = false;
		for (int seen = 0; seen < mapCount; seen++)
		{
			if (StrEqual(maps[seen], g_sRawHistoryMap[slot], false))
			{
				duplicate = true;
				break;
			}
		}

		if (duplicate)
		{
			continue;
		}

		strcopy(maps[mapCount], MAP_NAME_LENGTH, g_sRawHistoryMap[slot]);
		mapCount++;
	}

	return mapCount;
}

void FormatMapList(const char[] maps, char[] buffer, int size)
{
	strcopy(buffer, size, maps);
	if (buffer[0] == '\0')
	{
		strcopy(buffer, size, "无记录 (none)");
	}
}

float GetHistoricalOutputRaw(const char[] auth)
{
	return GetHistoricalRaw(auth, 0);
}

float GetHistoricalDefenseRaw(const char[] auth)
{
	return GetHistoricalRaw(auth, 1);
}

float GetHistoricalFocusRaw(const char[] auth)
{
	return GetHistoricalRaw(auth, 2);
}

float GetHistoricalInfectorRaw(const char[] auth)
{
	return GetHistoricalRaw(auth, 3);
}

float GetHistoricalRaw(const char[] auth, int field)
{
	if (auth[0] == '\0')
	{
		return 0.0;
	}

	float total = 0.0;
	int recordedSlots = 0;
	float values[4];
	for (int slot = 0; slot < g_iRawHistoryCount; slot++)
	{
		if (g_hRawHistory[slot].GetArray(auth, values, sizeof(values)))
		{
			total += values[field];
			recordedSlots++;
		}
	}
	if (recordedSlots == 0)
	{
		return 0.0;
	}
	return total * float(RAW_HISTORY_SLOTS) / float(recordedSlots);
}

void AggregateHistoricalActions(const char[] auth, RatingSnapshotEntry entry)
{
	entry.recordedSlots = 0;
	entry.siDmg = 0;
	entry.ciKill = 0;
	entry.tankDmg = 0;
	entry.dmgTaken = 0;
	entry.incaps = 0;
	entry.deaths = 0;
	entry.ff = 0;
	entry.tankupDmg = 0;
	entry.tankupKill = 0;
	entry.skeet = 0;
	entry.level = 0;
	entry.pop = 0;
	entry.tongueCut = 0;
	entry.crown = 0;
	entry.dmg = 0;
	entry.booms = 0;
	entry.deathCharges = 0;

	if (auth[0] == '\0')
	{
		return;
	}

	RawHistoryActionEntry historyEntry;
	for (int slot = 0; slot < g_iRawHistoryCount; slot++)
	{
		if (g_hRawActionHistory[slot].GetArray(auth, historyEntry, sizeof(historyEntry)))
		{
			entry.recordedSlots++;
			entry.siDmg += historyEntry.siDmg;
			entry.ciKill += historyEntry.ciKill;
			entry.tankDmg += historyEntry.tankDmg;
			entry.dmgTaken += historyEntry.dmgTaken;
			entry.incaps += historyEntry.incaps;
			entry.deaths += historyEntry.deaths;
			entry.ff += historyEntry.ff;
			entry.tankupDmg += historyEntry.tankupDmg;
			entry.tankupKill += historyEntry.tankupKill;
			entry.skeet += historyEntry.skeet;
			entry.level += historyEntry.level;
			entry.pop += historyEntry.pop;
			entry.tongueCut += historyEntry.tongueCut;
			entry.crown += historyEntry.crown;
			entry.dmg += historyEntry.dmg;
			entry.booms += historyEntry.booms;
			entry.deathCharges += historyEntry.deathCharges;
		}
	}
}

float GetTankRaw(int participant)
{
	if (participant < 0 || participant >= g_iParticipantCount)
	{
		return 0.0;
	}

	float baseRaw = g_bBecameTank[participant] ? 1.0 : 0.0;
	return baseRaw + float(g_iTankDmgUpright[participant] + g_iTankPunch[participant] * 10 + g_iTankRock[participant] * 20 + g_iTankHittable[participant] * 35 + g_iTankIncap[participant] * 45 + g_iTankDeath[participant] * 60);
}

float GetEffectiveTankRaw(int participant)
{
	float currentRaw = GetTankRaw(participant);
	if (currentRaw > 0.0)
	{
		return currentRaw;
	}

	if (participant < 0 || participant >= g_iParticipantCount || g_hLastTankRaw == null)
	{
		return 0.0;
	}

	TankHistoryEntry tankEntry;
	if (!g_hLastTankRaw.GetArray(g_sParticipantAuth[participant], tankEntry, sizeof(tankEntry)))
	{
		return 0.0;
	}

	return tankEntry.raw;
}

void SaveLatestTankRaw()
{
	if (g_hLastTankRaw == null)
	{
		return;
	}

	for (int participant = 0; participant < g_iParticipantCount; participant++)
	{
		float tankRaw = GetTankRaw(participant);
		if (tankRaw <= 0.0 || g_sParticipantAuth[participant][0] == '\0')
		{
			continue;
		}

		TankHistoryEntry tankEntry;
		tankEntry.raw = tankRaw;
		tankEntry.becameTank = g_bBecameTank[participant];
		tankEntry.tankDmgUpright = g_iTankDmgUpright[participant];
		tankEntry.punch = g_iTankPunch[participant];
		tankEntry.rock = g_iTankRock[participant];
		tankEntry.hittable = g_iTankHittable[participant];
		tankEntry.incap = g_iTankIncap[participant];
		tankEntry.death = g_iTankDeath[participant];

		g_hLastTankRaw.SetArray(g_sParticipantAuth[participant], tankEntry, sizeof(tankEntry));
	}
}

float GetWeightedRaw(float output, float defense, float focus, float infector, float tank)
{
	return output * 0.30 + defense * 0.10 + focus * 0.10 + infector * 0.25 + tank * 0.25;
}

float NormalizeRaw(float raw, float minValue, float maxValue)
{
	if (maxValue <= minValue)
	{
		return 5.0;
	}

	return (raw - minValue) / (maxValue - minValue) * 10.0;
}

float NormalizeTankRaw(float raw, float tankMin, float tankMax)
{
	if (raw <= 0.0)
	{
		return TANK_NO_DATA_SCORE;
	}

	return NormalizeRaw(raw, tankMin, tankMax);
}

bool BuildRawRanges(float &outputMin, float &outputMax, float &defenseMin, float &defenseMax, float &focusMin, float &focusMax, float &infectorMin, float &infectorMax, float &tankMin, float &tankMax)
{
	bool found = false;
	bool foundTank = false;

	for (int participant = 0; participant < g_iParticipantCount; participant++)
	{
		if (!IsEligibleForRating(participant))
		{
			continue;
		}

		float output = GetHistoricalOutputRaw(g_sParticipantAuth[participant]);
		float defense = GetHistoricalDefenseRaw(g_sParticipantAuth[participant]);
		float focus = GetHistoricalFocusRaw(g_sParticipantAuth[participant]);
		float infector = GetHistoricalInfectorRaw(g_sParticipantAuth[participant]);
		float tank = GetEffectiveTankRaw(participant);

		if (!found)
		{
			outputMin = output;
			outputMax = output;
			defenseMin = defense;
			defenseMax = defense;
			focusMin = focus;
			focusMax = focus;
			infectorMin = infector;
			infectorMax = infector;
			found = true;
		}
		else
		{
			if (output < outputMin) outputMin = output;
			if (output > outputMax) outputMax = output;
			if (defense < defenseMin) defenseMin = defense;
			if (defense > defenseMax) defenseMax = defense;
			if (focus < focusMin) focusMin = focus;
			if (focus > focusMax) focusMax = focus;
			if (infector < infectorMin) infectorMin = infector;
			if (infector > infectorMax) infectorMax = infector;
		}

		if (tank > 0.0)
		{
			if (!foundTank)
			{
				tankMin = tank;
				tankMax = tank;
				foundTank = true;
			}
			else
			{
				if (tank < tankMin) tankMin = tank;
				if (tank > tankMax) tankMax = tank;
			}
		}
	}

	return found;
}

bool IsHumanClient(int client)
{
	return IsValidClientIndex(client) && IsClientInGame(client) && !IsFakeClient(client);
}

bool IsValidClientIndex(int client)
{
	return client > 0 && client <= MaxClients;
}

int GetZombieClass(int client)
{
	if (!IsValidClientIndex(client) || !IsClientInGame(client))
	{
		return 0;
	}

	return GetEntProp(client, Prop_Send, "m_zombieClass");
}

bool IsSurvivorIncapacitated(int client)
{
	if (!IsValidClientIndex(client) || !IsClientInGame(client))
	{
		return false;
	}

	return GetEntProp(client, Prop_Send, "m_isIncapacitated") != 0;
}

bool IsTankInPlay()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsHumanClient(client) && GetClientTeam(client) == TEAM_INFECTED && GetZombieClass(client) == ZC_TANK)
		{
			MarkClientAsTank(client);
			return true;
		}
	}

	return false;
}

bool InSecondHalfOfRound()
{
	return GameRules_GetProp("m_bInSecondHalfOfRound") != 0;
}

void PromptRatingQuery()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsHumanClient(client))
		{
			CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 输入 {olive}!rating{default} 查看详细数据。");
		}
	}
}

void SaveRatingSnapshot(bool hasRanges, float outputMin, float outputMax, float defenseMin, float defenseMax, float focusMin, float focusMax, float infectorMin, float infectorMax, float tankMin, float tankMax)
{
	if (g_hLastRatingSnapshot == null || g_hLastRatingSnapshotNames == null)
	{
		return;
	}

	g_bHasSnapshot = true;
	g_iSnapshotRoundId++;
	GetCurrentMap(g_sSnapshotMap, sizeof(g_sSnapshotMap));
	g_iSnapshotMapCount = CollectHistoryMaps("", g_sSnapshotMaps, sizeof(g_sSnapshotMaps), SNAPSHOT_MAP_SEPARATOR);
	FormatTime(g_sSnapshotTime, sizeof(g_sSnapshotTime), "%Y-%m-%d %H:%M:%S");

	g_hLastRatingSnapshot.Clear();
	g_hLastRatingSnapshotNames.Clear();

	for (int participant = 0; participant < g_iParticipantCount; participant++)
	{
		if (g_sParticipantAuth[participant][0] == '\0')
		{
			continue;
		}

		g_hLastRatingSnapshotNames.SetString(g_sParticipantAuth[participant], g_sParticipantName[participant]);

		RatingSnapshotEntry entry;
		entry.valid = true;
		entry.team = ResolveSnapshotTeam(participant);

		AggregateHistoricalActions(g_sParticipantAuth[participant], entry);
		entry.mapCount = CollectHistoryMaps(g_sParticipantAuth[participant], entry.maps, sizeof(entry.maps), SNAPSHOT_MAP_SEPARATOR);

		entry.tankDmgUpright = g_iTankDmgUpright[participant];
		entry.punch = g_iTankPunch[participant];
		entry.rock = g_iTankRock[participant];
		entry.hittable = g_iTankHittable[participant];
		entry.incap = g_iTankIncap[participant];
		entry.death = g_iTankDeath[participant];
		entry.becameTank = g_bBecameTank[participant];

		float currentTank = GetTankRaw(participant);
		float effectiveTank = GetEffectiveTankRaw(participant);
		if (currentTank > 0.0)
		{
			entry.tankSource = 1;
		}
		else if (effectiveTank > 0.0)
		{
			entry.tankSource = 2;
			TankHistoryEntry histTank;
			if (g_hLastTankRaw != null && g_hLastTankRaw.GetArray(g_sParticipantAuth[participant], histTank, sizeof(histTank)))
			{
				entry.tankDmgUpright = histTank.tankDmgUpright;
				entry.punch = histTank.punch;
				entry.rock = histTank.rock;
				entry.hittable = histTank.hittable;
				entry.incap = histTank.incap;
				entry.death = histTank.death;
				entry.becameTank = histTank.becameTank;
			}
		}
		else
		{
			entry.tankSource = 0;
		}

		if (hasRanges && IsEligibleForRating(participant))
		{
			entry.eligible = true;
			entry.outputRaw = GetHistoricalOutputRaw(g_sParticipantAuth[participant]);
			entry.defenseRaw = GetHistoricalDefenseRaw(g_sParticipantAuth[participant]);
			entry.focusRaw = GetHistoricalFocusRaw(g_sParticipantAuth[participant]);
			entry.infectorRaw = GetHistoricalInfectorRaw(g_sParticipantAuth[participant]);
			entry.tankRaw = effectiveTank;

			entry.output = NormalizeRaw(entry.outputRaw, outputMin, outputMax);
			entry.defense = NormalizeRaw(entry.defenseRaw, defenseMin, defenseMax);
			entry.focus = NormalizeRaw(entry.focusRaw, focusMin, focusMax);
			entry.infector = NormalizeRaw(entry.infectorRaw, infectorMin, infectorMax);
			entry.tank = NormalizeTankRaw(entry.tankRaw, tankMin, tankMax);

			entry.raw = GetWeightedRaw(entry.output, entry.defense, entry.focus, entry.infector, entry.tank);
			entry.rating = Pow(entry.raw / 10.0, RATING_EXPONENT) * 10.0;
		}
		else
		{
			entry.eligible = false;
			entry.outputRaw = 0.0;
			entry.defenseRaw = 0.0;
			entry.focusRaw = 0.0;
			entry.infectorRaw = 0.0;
			entry.tankRaw = 0.0;
			entry.output = 0.0;
			entry.defense = 0.0;
			entry.focus = 0.0;
			entry.infector = 0.0;
			entry.tank = 0.0;
			entry.raw = 0.0;
			entry.rating = 0.0;
		}

		g_hLastRatingSnapshot.SetArray(g_sParticipantAuth[participant], entry, sizeof(entry));
	}
}

public Action Command_RatingPro(int client, int args)
{
	if (client > 0)
	{
		float engineTime = GetEngineTime();
		if (engineTime - g_fLastQueryTime[client] < 2.0)
		{
			CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 查询过于频繁，请稍候再试。");
			return Plugin_Handled;
		}
		g_fLastQueryTime[client] = engineTime;
	}

	char arg[128];
	GetCmdArgString(arg, sizeof(arg));
	TrimString(arg);
	StripQuotes(arg);

	if (arg[0] == '\0' || StrEqual(arg, "@all", false))
	{
		int count = 0;
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsHumanClient(i))
			{
				PrintClientRatingSnapshot(client, i);
				count++;
			}
		}

		if (client == 0)
		{
			if (count == 0)
			{
				PrintToConsole(0, "[RatingPro] 未找到在线真人玩家。");
			}
			else
			{
				PrintToConsole(0, "[RatingPro] 已将所有在线真人玩家的 RatingPro 详细数据输出到控制台。");
			}
		}
		else
		{
			if (count == 0)
			{
				CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 当前没有在线真人玩家。");
			}
			else
			{
				CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 已将所有在线玩家的 RatingPro 详细数据输出到控制台（按 ~ 键查看）。");
			}
		}

		return Plugin_Handled;
	}

	int target_list[MAXPLAYERS + 1];
	char target_name[MAX_TARGET_LENGTH];
	bool tn_is_ml;
	int target_count = ProcessTargetString(
		arg,
		client,
		target_list,
		sizeof(target_list),
		COMMAND_FILTER_NO_BOTS | COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_IMMUNITY,
		target_name,
		sizeof(target_name),
		tn_is_ml
	);

	if (target_count <= 0)
	{
		// 在线没匹配到：退服玩家只要仍在当前快照里就按名字或 SteamID 查询。
		char offlineAuth[64];
		char offlineName[MAX_NAME_LENGTH];
		int offlineMatches = FindSnapshotPlayer(arg, offlineAuth, sizeof(offlineAuth), offlineName, sizeof(offlineName));
		if (offlineMatches == 1)
		{
			PrintRatingSnapshotToConsole(client, offlineAuth, offlineName, 0);
			if (client == 0)
			{
				PrintToConsole(0, "[RatingPro] 已将已退服玩家 %s 的 RatingPro 详细数据输出到控制台。", offlineName);
			}
			else
			{
				CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 已将已退服玩家 {olive}%s{default} 的 RatingPro 详细数据输出到控制台（按 ~ 键查看）。", offlineName);
			}
			return Plugin_Handled;
		}

		if (offlineMatches > 1)
		{
			if (client == 0)
			{
				PrintToConsole(0, "[RatingPro] 匹配到多名已退服玩家，请输入更精确的名称或 SteamID。");
			}
			else
			{
				CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 匹配到多名已退服玩家，请输入更精确的名称或 SteamID。");
			}
			return Plugin_Handled;
		}

		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	int target = target_list[0];
	if (!IsHumanClient(target))
	{
		if (client == 0)
		{
			PrintToConsole(0, "[RatingPro] 目标必须是在线真人玩家。");
		}
		else
		{
			CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 目标必须是在线真人玩家。");
		}
		return Plugin_Handled;
	}

	PrintClientRatingSnapshot(client, target);

	if (client > 0)
	{
		char targetDisplayName[MAX_NAME_LENGTH];
		GetClientName(target, targetDisplayName, sizeof(targetDisplayName));
		CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 已将玩家 {olive}%s{default} 的 RatingPro 详细数据输出到控制台（按 ~ 键查看）。", targetDisplayName);
	}

	return Plugin_Handled;
}

// 在线玩家入口：解析 SteamID 后交给快照打印；未认证时 auth 传空串走“身份未验证”分支。
void PrintClientRatingSnapshot(int requester, int targetClient, bool logToFile = false)
{
	if (!IsHumanClient(targetClient))
	{
		return;
	}

	char targetName[MAX_NAME_LENGTH];
	GetClientName(targetClient, targetName, sizeof(targetName));

	char auth[64];
	if (!GetClientAuthKey(targetClient, auth, sizeof(auth)))
	{
		auth[0] = '\0';
	}

	PrintRatingSnapshotToConsole(requester, auth, targetName, GetClientUserId(targetClient), logToFile);
}

int FindClientByAuth(const char[] auth)
{
	if (auth[0] == '\0')
	{
		return 0;
	}

	char clientAuth[64];
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanClient(client) || !GetClientAuthKey(client, clientAuth, sizeof(clientAuth)))
		{
			continue;
		}

		if (StrEqual(clientAuth, auth, false))
		{
			return client;
		}
	}

	return 0;
}

// 在快照里查找已退服玩家：先按 SteamID，再按名字（精确优先，其次唯一子串）。返回匹配数量。
int FindSnapshotPlayer(const char[] query, char[] authOut, int authSize, char[] nameOut, int nameSize)
{
	authOut[0] = '\0';
	nameOut[0] = '\0';

	if (!g_bHasSnapshot || g_hLastRatingSnapshotNames == null || query[0] == '\0')
	{
		return 0;
	}

	if (StrContains(query, "STEAM_", false) == 0)
	{
		char snapshotName[MAX_NAME_LENGTH];
		if (!g_hLastRatingSnapshotNames.GetString(query, snapshotName, sizeof(snapshotName)))
		{
			return 0;
		}

		strcopy(authOut, authSize, query);
		strcopy(nameOut, nameSize, snapshotName);
		return 1;
	}

	StringMapSnapshot snapshot = g_hLastRatingSnapshotNames.Snapshot();
	int exactMatches = 0;
	int partialMatches = 0;
	char exactAuth[64];
	char exactName[MAX_NAME_LENGTH];
	char partialAuth[64];
	char partialName[MAX_NAME_LENGTH];

	for (int index = 0; index < snapshot.Length; index++)
	{
		char key[64];
		snapshot.GetKey(index, key, sizeof(key));

		char storedName[MAX_NAME_LENGTH];
		if (!g_hLastRatingSnapshotNames.GetString(key, storedName, sizeof(storedName)))
		{
			continue;
		}

		if (StrEqual(storedName, query, false))
		{
			exactMatches++;
			if (exactMatches == 1)
			{
				strcopy(exactAuth, sizeof(exactAuth), key);
				strcopy(exactName, sizeof(exactName), storedName);
			}
		}
		else if (StrContains(storedName, query, false) != -1)
		{
			partialMatches++;
			if (partialMatches == 1)
			{
				strcopy(partialAuth, sizeof(partialAuth), key);
				strcopy(partialName, sizeof(partialName), storedName);
			}
		}
	}

	delete snapshot;

	if (exactMatches == 1)
	{
		strcopy(authOut, authSize, exactAuth);
		strcopy(nameOut, nameSize, exactName);
		return 1;
	}

	if (exactMatches > 1)
	{
		return exactMatches;
	}

	if (partialMatches == 1)
	{
		strcopy(authOut, authSize, partialAuth);
		strcopy(nameOut, nameSize, partialName);
		return 1;
	}

	return partialMatches;
}

void CleanName(const char[] input, char[] output, int maxlen)
{
	strcopy(output, maxlen, input);
	for (int i = 0; output[i] != '\0'; i++)
	{
		if (output[i] == '\r' || output[i] == '\n' || output[i] == '\t')
		{
			output[i] = ' ';
		}
	}
}

void GetTeamNameString(int team, char[] buffer, int maxlen)
{
	if (team == TEAM_SURVIVOR)
	{
		strcopy(buffer, maxlen, "生还者 (Survivor)");
	}
	else if (team == TEAM_INFECTED)
	{
		strcopy(buffer, maxlen, "特感 (Infected)");
	}
	else
	{
		strcopy(buffer, maxlen, "旁观/其他");
	}
}

// 结算日志里的一行胜负说明。uploader 会从 "winner_team=N" 取胜负、从
// "team2=X team3=Y" 取比分，所以这行同时是给人看的结论和给 agent 用的字段（格式别随意改）。
void PrintMapWinnerLine(int requester, bool logToFile)
{
	char scoreNote[96];
	FormatScoreNote(scoreNote, sizeof(scoreNote));

	if (g_iMapWinnerTeam == TEAM_SURVIVOR)
	{
		PrintToConsoleOrLog(requester, logToFile,
			"本图胜负: 队伍 1（winner_team=2）%s | 第二半场生还方所在队获胜", scoreNote);
	}
	else if (g_iMapWinnerTeam == TEAM_INFECTED)
	{
		PrintToConsoleOrLog(requester, logToFile,
			"本图胜负: 队伍 2（winner_team=3）%s | 第二半场特感方所在队获胜", scoreNote);
	}
	else
	{
		PrintToConsoleOrLog(requester, logToFile,
			"本图胜负: 未判定（地图分缺失、未打满两半场或打平）%s | 本局 ELO 只按表现结算", scoreNote);
	}
}

// 比分片段：`team2=312 team3=245` 是无歧义的机器可读 token（不依赖先后顺序）。
// 只读到逻辑队分数、却换算不出 2/3 归属时，退化成诊断信息且不带上报字段。
void FormatScoreNote(char[] buffer, int size)
{
	int team2Score;
	int team3Score;

	if (TryGetTeamScores(team2Score, team3Score))
	{
		Format(buffer, size, " | 比分 team2=%d team3=%d", team2Score, team3Score);
	}
	else if (g_iMapScoreA >= 0 && g_iMapScoreB >= 0)
	{
		Format(buffer, size, " | 地图分 A=%d B=%d（队伍归属未知，未上报）", g_iMapScoreA, g_iMapScoreB);
	}
	else
	{
		buffer[0] = '\0';
	}
}

void RecordRatingSettlement()
{
	char timestamp[32];
	FormatTime(timestamp, sizeof(timestamp), "%Y%m%d_%H%M%S");
	char logName[MAX_LOGGERNAME_LENGTH];
	char logPath[PLATFORM_MAX_PATH];
	int sequence = 0;
	do
	{
		sequence++;
		Format(logName, sizeof(logName), "ratingpro_%s_%03d", timestamp, sequence);
		BuildPath(Path_SM, logPath, sizeof(logPath), "logs/%s.log", logName);
	}
	while (FileExists(logPath));

	File logFile = OpenFile(logPath, "wt");
	if (logFile == null)
	{
		LogError("[RatingPro] Cannot create settlement log: %s", logPath);
		return;
	}
	delete logFile;
	g_RatingLogger.SetLogName(logName);

	PrintToConsoleOrLog(0, true, "==================== RatingPro 结算 ====================");
	PrintToConsoleOrLog(0, true, "结算地图: %s | 结算时间: %s | 快照编号: #%d", g_sSnapshotMap, g_sSnapshotTime, g_iSnapshotRoundId);
	PrintMapWinnerLine(0, true);
	PrintSnapshotCoverage(0, true);
	for (int participant = 0; participant < g_iParticipantCount; participant++)
	{
		int onlineClient = FindClientByAuth(g_sParticipantAuth[participant]);
		int userId = onlineClient > 0 ? GetClientUserId(onlineClient) : 0;
		PrintRatingSnapshotToConsole(0, g_sParticipantAuth[participant], g_sParticipantName[participant], userId, true);
	}
	PrintToServer("[RatingPro] Saved settlement log: %s", logPath);
}

void PrintToConsoleOrLog(int requester, bool logToFile, const char[] format, any ...)
{
	char buffer[2048];
	VFormat(buffer, sizeof(buffer), format, 4);
	if (logToFile)
	{
		g_RatingLogger.WritetoLogFileRaw(buffer);
	}
	else
	{
		PrintToConsole(requester, "%s", buffer);
	}
}

void PrintSnapshotCoverage(int requester, bool logToFile)
{
	char mapList[SNAPSHOT_MAP_LIST_CELLS];
	FormatMapList(g_sSnapshotMaps, mapList, sizeof(mapList));
	PrintToConsoleOrLog(requester, logToFile, "覆盖地图 (%d 座): %s", g_iSnapshotMapCount, mapList);
}

void PrintEntryCoverage(int requester, bool logToFile, int mapCount, const char[] maps)
{
	char mapList[SNAPSHOT_MAP_LIST_CELLS];
	FormatMapList(maps, mapList, sizeof(mapList));
	PrintToConsoleOrLog(requester, logToFile, "[统计范围] 覆盖地图 (%d 座): %s", mapCount, mapList);
}

// 快照打印统一入口：auth 为 SteamID 键。userId 为 0 表示玩家已退服，只要快照还在就仍可查询。
void PrintRatingSnapshotToConsole(int requester, const char[] auth, const char[] displayName, int targetUserId, bool logToFile = false)
{
	char cleanCurrentName[MAX_NAME_LENGTH];
	CleanName(displayName, cleanCurrentName, sizeof(cleanCurrentName));

	char identity[64];
	if (targetUserId > 0)
	{
		Format(identity, sizeof(identity), "userid: #%d", targetUserId);
	}
	else
	{
		strcopy(identity, sizeof(identity), "已退服 (offline)");
	}

	if (auth[0] == '\0')
	{
		PrintToConsoleOrLog(requester, logToFile, "==================== RatingPro 数据表 ====================");
		PrintToConsoleOrLog(requester, logToFile, "[元信息] 当前玩家: %s (%s) | 状态: 身份未验证 (N/A)", cleanCurrentName, identity);
		PrintToConsoleOrLog(requester, logToFile, "[说明] 目标玩家尚未完成 Steam 认证，无法关联评分快照。");
		PrintToConsoleOrLog(requester, logToFile, "==========================================================");
		return;
	}

	if (!g_bHasSnapshot)
	{
		PrintToConsoleOrLog(requester, logToFile, "==================== RatingPro 数据表 ====================");
		PrintToConsoleOrLog(requester, logToFile, "[元信息] 当前玩家: %s (%s) | 状态: 暂无快照数据 (N/A)", cleanCurrentName, identity);
		PrintToConsoleOrLog(requester, logToFile, "[说明] 服务器尚未完成任何章节正式结算，暂无 RatingPro 快照。");
		PrintToConsoleOrLog(requester, logToFile, "==========================================================");
		return;
	}

	RatingSnapshotEntry entry;
	if (!g_hLastRatingSnapshot.GetArray(auth, entry, sizeof(entry)))
	{
		PrintToConsoleOrLog(requester, logToFile, "==================== RatingPro 数据表 ====================");
		PrintToConsoleOrLog(requester, logToFile, "快照编号: #%d | 结算地图: %s | 结算时间: %s", g_iSnapshotRoundId, g_sSnapshotMap, g_sSnapshotTime);
		PrintSnapshotCoverage(requester, logToFile);
		PrintToConsoleOrLog(requester, logToFile, "[元信息] 当前玩家: %s (%s) | 状态: 未参与上次结算 (N/A)", cleanCurrentName, identity);
		PrintToConsoleOrLog(requester, logToFile, "[说明] 该玩家未参与上次正式结算或结算时未完成身份认证。");
		PrintToConsoleOrLog(requester, logToFile, "==========================================================");
		return;
	}

	char snapshotName[MAX_NAME_LENGTH];
	char cleanSnapshotName[MAX_NAME_LENGTH];
	if (!g_hLastRatingSnapshotNames.GetString(auth, snapshotName, sizeof(snapshotName)))
	{
		strcopy(snapshotName, sizeof(snapshotName), cleanCurrentName);
	}
	CleanName(snapshotName, cleanSnapshotName, sizeof(cleanSnapshotName));

	char teamName[32];
	GetTeamNameString(entry.team, teamName, sizeof(teamName));

	if (!entry.eligible)
	{
		PrintToConsoleOrLog(requester, logToFile, "==================== RatingPro 数据表 ====================");
		PrintToConsoleOrLog(requester, logToFile, "快照编号: #%d | 结算地图: %s | 结算时间: %s", g_iSnapshotRoundId, g_sSnapshotMap, g_sSnapshotTime);
		PrintSnapshotCoverage(requester, logToFile);
		PrintToConsoleOrLog(requester, logToFile, "[元信息] 当前玩家: %s (%s) | 结算姓名: %s | 结算队伍: %s | 状态: 上次结算数据不足/无资格 (N/A)",
			cleanCurrentName, identity, cleanSnapshotName, teamName);
		PrintToConsoleOrLog(requester, logToFile, "[综合评分] RatingPro: N/A | 加权原始分 (weighted raw): N/A");
		PrintToConsoleOrLog(requester, logToFile, "[原始分与归一化] 输出(output): N/A | 防守(defense): N/A | 关键操作(focus): N/A | 特感进攻(infector): N/A | Tank表现(tank): N/A");
		PrintEntryCoverage(requester, logToFile, entry.mapCount, entry.maps);
		PrintToConsoleOrLog(requester, logToFile, "[生还者数据] 特感伤害(siDmg)=%d 丧尸击杀(ciKill)=%d 克伤害(tankDmg)=%d 承受伤害(dmgTaken)=%d 倒地(incaps)=%d 死亡(deaths)=%d 友伤(ff)=%d 克局特伤(tankupDmg)=%d 克局特杀(tankupKill)=%d 空爆(skeet)=%d 截停(level)=%d 秒爆(pop)=%d 断舌(tongueCut)=%d 秒妹(crown)=%d",
			entry.siDmg, entry.ciKill, entry.tankDmg, entry.dmgTaken, entry.incaps, entry.deaths, entry.ff,
			entry.tankupDmg, entry.tankupKill, entry.skeet, entry.level, entry.pop, entry.tongueCut, entry.crown);
		PrintToConsoleOrLog(requester, logToFile, "[特感数据] 造成的伤害(dmg)=%d 胆汁命中生还者(booms)=%d 致命牛撞(deathCharges)=%d 克直立伤害(tankDmgUpright)=%d 拳击(punch)=%d 砸石(rock)=%d 铁(hittable)=%d 击倒(incap)=%d 击杀(death)=%d",
			entry.dmg, entry.booms, entry.deathCharges, entry.tankDmgUpright, entry.punch, entry.rock, entry.hittable, entry.incap, entry.death);
		PrintToConsoleOrLog(requester, logToFile, "[说明] 该玩家在上次结算时无有效行为计数，未生成 RatingPro 评分。");
		PrintToConsoleOrLog(requester, logToFile, "==========================================================");
		return;
	}

	char tankSourceStr[32];
	if (entry.tankSource == 1)
	{
		strcopy(tankSourceStr, sizeof(tankSourceStr), "本局当前 (current)");
	}
	else if (entry.tankSource == 2)
	{
		strcopy(tankSourceStr, sizeof(tankSourceStr), "历史回退 (historical)");
	}
	else
	{
		strcopy(tankSourceStr, sizeof(tankSourceStr), "无数据 (no data: 4.6)");
	}

	PrintToConsoleOrLog(requester, logToFile, "==================== RatingPro 数据表 ====================");
	PrintToConsoleOrLog(requester, logToFile, "快照编号: #%d | 结算地图: %s | 结算时间: %s", g_iSnapshotRoundId, g_sSnapshotMap, g_sSnapshotTime);
	PrintSnapshotCoverage(requester, logToFile);
	PrintToConsoleOrLog(requester, logToFile, "[元信息] 当前玩家: %s (%s) | 结算姓名: %s | 结算队伍: %s | 状态: 正常有效",
		cleanCurrentName, identity, cleanSnapshotName, teamName);
	PrintToConsoleOrLog(requester, logToFile, "[综合评分] RatingPro: %.1f | 加权原始分 (weighted raw): %.1f", entry.rating, entry.raw);
	PrintToConsoleOrLog(requester, logToFile, "[加权分贡献 (对raw)] 输出(30%%): %.2f | 防守(10%%): %.2f | 关键操作(10%%): %.2f | 特感进攻(25%%): %.2f | Tank表现(25%%): %.2f",
		entry.output * 0.30, entry.defense * 0.10, entry.focus * 0.10, entry.infector * 0.25, entry.tank * 0.25);
	PrintToConsoleOrLog(requester, logToFile, "[归一化分] 输出(output): %.1f | 防守(defense): %.1f | 关键操作(focus): %.1f | 特感进攻(infector): %.1f | Tank表现(tank): %.1f",
		entry.output, entry.defense, entry.focus, entry.infector, entry.tank);
	PrintToConsoleOrLog(requester, logToFile, "[原始评分] 输出(output): %.1f | 防守(defense): %.1f | 关键操作(focus): %.1f | 特感进攻(infector): %.1f | Tank表现(tank): %.1f (Tank来源: %s)",
		entry.outputRaw, entry.defenseRaw, entry.focusRaw, entry.infectorRaw, entry.tankRaw, tankSourceStr);

	float curOutput = float(entry.siDmg + entry.tankDmg + entry.ciKill * 10);
	float curDefense = -float(entry.dmgTaken + entry.incaps * 350 + entry.deaths * 80 + entry.ff * 40);
	float curFocus = float(entry.tankupDmg) * 0.004 + float(entry.tankupKill) * 0.25 + float(entry.skeet) * 2.0 + float(entry.level) * 2.0 + float(entry.pop) * 1.5 + float(entry.tongueCut) * 1.0 + float(entry.crown) * 2.0;
	float curInfector = float(entry.dmg + entry.booms * 8 + entry.deathCharges * 25);

	PrintEntryCoverage(requester, logToFile, entry.mapCount, entry.maps);
	PrintToConsoleOrLog(requester, logToFile, "[原始评分构成与动作贡献 (跨章节累计 %d 槽)]", entry.recordedSlots);
	PrintToConsoleOrLog(requester, logToFile, "  ├─ 输出原始分贡献 (累计%.1f / 均值补齐生效值%.1f): 特感伤害+%d, 克伤害+%d, 丧尸击杀+%d (x10)",
		curOutput, entry.outputRaw, entry.siDmg, entry.tankDmg, entry.ciKill * 10);
	PrintToConsoleOrLog(requester, logToFile, "  ├─ 防守原始分扣除 (累计%.1f / 均值补齐生效值%.1f): 承伤-%d, 倒地-%d (x350), 死亡-%d (x80), 友伤-%d (x40)",
		curDefense, entry.defenseRaw, entry.dmgTaken, entry.incaps * 350, entry.deaths * 80, entry.ff * 40);
	PrintToConsoleOrLog(requester, logToFile, "  ├─ 关键操作原始分 (累计%.1f / 均值补齐生效值%.1f): 克局特伤+%.1f, 克局特杀+%.1f, 空爆+%.1f, 截停+%.1f, 秒爆+%.1f, 断舌+%.1f, 秒妹+%.1f",
		curFocus, entry.focusRaw, float(entry.tankupDmg) * 0.004, float(entry.tankupKill) * 0.25, float(entry.skeet) * 2.0, float(entry.level) * 2.0, float(entry.pop) * 1.5, float(entry.tongueCut) * 1.0, float(entry.crown) * 2.0);
	PrintToConsoleOrLog(requester, logToFile, "  ├─ 特感进攻原始分 (累计%.1f / 均值补齐生效值%.1f): 特感伤害+%d, 炸人+%d (x8), 致命牛撞+%d (x25)",
		curInfector, entry.infectorRaw, entry.dmg, entry.booms * 8, entry.deathCharges * 25);
	PrintToConsoleOrLog(requester, logToFile, "  └─ Tank表现原始分 (当前生效值%.1f): 出克基础分+%d, 直立伤害+%d, 拳击+%d (x10), 砸石+%d (x20), 铁+%d (x35), 击倒+%d (x45), 击杀+%d (x60)",
		entry.tankRaw, entry.becameTank ? 1 : 0, entry.tankDmgUpright, entry.punch * 10, entry.rock * 20, entry.hittable * 35, entry.incap * 45, entry.death * 60);

	PrintToConsoleOrLog(requester, logToFile, "[生还者数据 (跨章节累计 %d 槽)] 特感伤害(siDmg)=%d 丧尸击杀(ciKill)=%d 克伤害(tankDmg)=%d 承受伤害(dmgTaken)=%d 倒地(incaps)=%d 死亡(deaths)=%d 友伤(ff)=%d 克局特伤(tankupDmg)=%d 克局特杀(tankupKill)=%d 空爆(skeet)=%d 截停(level)=%d 秒爆(pop)=%d 断舌(tongueCut)=%d 秒妹(crown)=%d",
		entry.recordedSlots, entry.siDmg, entry.ciKill, entry.tankDmg, entry.dmgTaken, entry.incaps, entry.deaths, entry.ff,
		entry.tankupDmg, entry.tankupKill, entry.skeet, entry.level, entry.pop, entry.tongueCut, entry.crown);
	PrintToConsoleOrLog(requester, logToFile, "[特感数据 (跨章节累计 %d 槽)] 造成的伤害(dmg)=%d 胆汁命中生还者(booms)=%d 致命牛撞(deathCharges)=%d 克直立伤害(tankDmgUpright)=%d 拳击(punch)=%d 砸石(rock)=%d 铁(hittable)=%d 击倒(incap)=%d 击杀(death)=%d",
		entry.recordedSlots, entry.dmg, entry.booms, entry.deathCharges, entry.tankDmgUpright, entry.punch, entry.rock, entry.hittable, entry.incap, entry.death);
	PrintToConsoleOrLog(requester, logToFile, "[说明] 生还者与特感数据为已有历史槽位(%d槽)跨章节累计统计，RatingPro评分采用平均值补齐至四槽计算。", entry.recordedSlots);
	PrintToConsoleOrLog(requester, logToFile, "==========================================================");
}

// ==========================================================================================
// RatingPro Hub 后端接入
//
// 上传口径：一组连续对局里每攒满 N 张图（默认 4）上传一次，上传后计数器归零重新累计。
// 「连续」只有一个判据：双方战役累计比分单调不减。比分回退（= 战役被重开）就视为这一段
// 没能打成完整对局：只重置上传计数，不产生任何上传；评分窗口（RAW_HISTORY_SLOTS）保持
// 原始跨图滚动口径，不跟着清空。地图名（战役前缀、章节号）完全不参与判定。
// 另外触发上传的那张图参与人数必须 >= sm_ratingpro_min_players（默认 8），否则这段数据直接丢弃。
//
// 读接口：玩家认证完成后异步请求 /elo/current 与 /rating/average?limit=5 并缓存在本地，
// 所有 Get 类 native 只读本地缓存，不发请求。
// ==========================================================================================

void CreateApiConVars()
{
	g_hApiEnabled = CreateConVar("sm_ratingpro_api_enabled", "1",
		"启用 RatingPro Hub 后端接入（ELO 缓存 + 对局上传）。", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hApiBase = CreateConVar("sm_ratingpro_api_base", "https://l4d2rating.0721play.icu",
		"RatingPro Hub 后端地址，末尾不要带斜杠。");
	g_hApiKey = CreateConVar("sm_ratingpro_api_key", "",
		"上传对局数据的 API Key；留空时只读不写（仍可缓存 ELO 与平均分）。");
	g_hServerKey = CreateConVar("sm_ratingpro_server_key", "",
		"服务器标识，后端用它区分多台服务器并做幂等去重；留空时取 hostname。");
	g_hUploadMaps = CreateConVar("sm_ratingpro_upload_maps", "4",
		"同一章节累计结算多少张图后上传一次对局数据。", FCVAR_NONE, true, 1.0, true, 4.0);
	g_hMinPlayers = CreateConVar("sm_ratingpro_min_players", "8",
		"参与人数达到该值（含）才上传对局数据；人数不足的对局直接丢弃，计数器归零。0 表示不限制。",
		FCVAR_NONE, true, 0.0, true, float(MAX_PARTICIPANTS));
	g_hAutoRefresh = CreateConVar("sm_ratingpro_auto_refresh", "1",
		"玩家认证完成时自动请求并缓存 ELO 与最近 5 场平均 RatingPro。", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hScoreGuard = CreateConVar("sm_ratingpro_score_guard", "1",
		"用「双方战役比分不减」判定对局是否连续（依赖 left4dhooks）。这是唯一的断章信号：关掉后不再检测中断，上传计数只在攒满上传时归零。",
		FCVAR_NONE, true, 0.0, true, 1.0);
	// 后端排查日志：独立文件。默认 2（全量），先把证据记全；确认稳定后再降到 1 省磁盘。
	g_hApiLog = CreateConVar("sm_ratingpro_api_log", "2",
		"后端日志级别（logs/l4d2_ratingpro_api.log）：0=关闭，1=只记请求失败与上传结果，2=另外记录每次请求的 URL、响应体与上传载荷。",
		FCVAR_NONE, true, 0.0, true, 2.0);
}

void InitializeApi()
{
	g_hFwdClientDataLoaded = CreateGlobalForward("RatingPro_OnClientDataLoaded", ET_Ignore, Param_Cell, Param_Cell);
	g_hFwdClientEloUpdated = CreateGlobalForward("RatingPro_OnClientEloUpdated", ET_Ignore, Param_Cell, Param_Float, Param_Float, Param_Float);
	g_hFwdEloUploaded = CreateGlobalForward("RatingPro_OnEloUploaded", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

	g_iUploadToken = 0;
	g_iUploadAttempts = 0;
	g_bUploadInFlight = false;
	g_bUploadPending = false;
	g_bApiKeyWarned = false;

	g_bCampaignHasScoreBaseline = false;
	g_iCampaignMaps = 0;
	g_iCampaignSeqId = 0;
	g_iCampaignLastScoreA = 0;
	g_iCampaignLastScoreB = 0;
	g_sCampaignStartMap[0] = '\0';

	for (int index = 0; index < RAW_HISTORY_SLOTS; index++)
	{
		g_iRawHistorySeq[index] = 0;
	}
	g_sUploadPayload[0] = '\0';
	g_sUploadExternalId[0] = '\0';
	g_sHttpResponse[0] = '\0';
	g_iPendingUploadSnapshotId = 0;
	g_iPendingUploadPlayerCount = 0;

	for (int client = 0; client <= MaxClients; client++)
	{
		ResetClientApiCache(client);
	}
}

// ------------------------------ 玩家缓存 ------------------------------

void ResetClientApiCache(int client)
{
	if (!IsValidClientIndex(client))
	{
		return;
	}

	g_ClientInfo[client].loaded = false;
	g_ClientInfo[client].status = view_as<int>(RatingProCache_None);
	g_ClientInfo[client].elo = 0.0;
	g_ClientInfo[client].peakElo = 0.0;
	g_ClientInfo[client].kFactor = 0.0;
	g_ClientInfo[client].rank = 0;
	g_ClientInfo[client].totalPlayers = 0;
	g_ClientInfo[client].rounds = 0;
	g_ClientInfo[client].placementPlayed = 0;
	g_ClientInfo[client].placementRequired = 0;
	g_ClientInfo[client].hasLastRound = false;
	g_ClientInfo[client].lastDelta = 0.0;
	g_ClientInfo[client].lastRating = 0.0;
	g_ClientInfo[client].hasRecent = false;
	g_ClientInfo[client].recentAverage = 0.0;
	g_ClientInfo[client].recentAverageRaw = 0.0;
	g_ClientInfo[client].recentCount = 0;
	g_ClientInfo[client].recentTotalEligible = 0;
	g_ClientInfo[client].recentBest = 0.0;
	g_ClientInfo[client].recentWorst = 0.0;
	g_ClientInfo[client].recentValueCount = 0;

	for (int index = 0; index < RATINGPRO_MAX_RECENT_RATINGS; index++)
	{
		g_ClientInfo[client].recentValues[index] = 0.0;
	}

	g_bEloRequestInFlight[client] = false;
	g_bRatingRequestInFlight[client] = false;
	ClearClientApiError(client);
}

// ------------------------------ 后端日志 ------------------------------
// 全部写 logs/l4d2_ratingpro_api.log，级别由 sm_ratingpro_api_log 控制（默认 2）：
//   0 = 不写；1 = 只写失败 / 上传结果 / 会话头；2 = 再写每次请求的 URL 与成功响应体。
// 这里直接调 WritetoLogFile 而不是 logger 的 error()/warning()：后者会同时刷服务器控制台，
// 后端长期不可达时每个玩家两条，控制台会被淹掉。
void ApiLog(LogType level, const char[] fmt, any ...)
{
	if (g_hApiLog == null || g_hApiLog.IntValue <= 0)
	{
		return;
	}

	if (level == LogType_Debug && g_hApiLog.IntValue < 2)
	{
		return;
	}

	char buffer[MAX_LOG_LINE];
	VFormat(buffer, sizeof(buffer), fmt, 3);
	g_ApiLogger.WritetoLogFile(level, buffer);
}

// 响应体分块写：logger 单行上限 512，整段丢进去只剩开头几十个字，
// 而排查 401/500 恰恰要看后端返回的错误 JSON。
void ApiLogBody(LogType level, const char[] label, const char[] body)
{
	if (g_hApiLog == null || g_hApiLog.IntValue <= 0)
	{
		return;
	}

	if (level == LogType_Debug && g_hApiLog.IntValue < 2)
	{
		return;
	}

	int length = strlen(body);
	ApiLog(level, "%s：%d 字节", label, length);

	char chunk[API_LOG_BODY_CHUNK];
	for (int offset = 0; offset < length; offset += sizeof(chunk) - 1)
	{
		strcopy(chunk, sizeof(chunk), body[offset]);
		ApiLog(level, "  [%d] %s", offset, chunk);
	}
}

void SetClientApiError(int client, const char[] fmt, any ...)
{
	if (client < 0 || client > MaxClients)
	{
		return;
	}

	VFormat(g_sClientApiError[client], sizeof(g_sClientApiError[]), fmt, 3);
}

void ClearClientApiError(int client)
{
	if (client >= 0 && client <= MaxClients)
	{
		g_sClientApiError[client][0] = '\0';
	}
}

// 日志里用的 SteamID：未认证/已离场时退化成 unknown，不阻断请求本身。
void GetClientApiAuthForLog(int client, char[] buffer, int size)
{
	buffer[0] = '\0';
	if (!GetClientAuthKey(client, buffer, size))
	{
		strcopy(buffer, size, "unknown");
	}
}

void RequestClientApiData(int client)
{
	if (!g_hApiEnabled.BoolValue || !IsHumanClient(client))
	{
		return;
	}

	char auth[64];
	if (!GetClientAuthKey(client, auth, sizeof(auth)))
	{
		return;
	}

	char encoded[256];
	UrlEncode(auth, encoded, sizeof(encoded));

	RequestClientElo(client, encoded);
	RequestClientRecentRating(client, encoded);
}

void RequestClientElo(int client, const char[] encodedAuth)
{
	if (g_bEloRequestInFlight[client])
	{
		return;
	}

	char path[256];
	Format(path, sizeof(path), API_ELO_PATH, encodedAuth);

	char url[512];
	FormatApiUrl(url, sizeof(url), path);

	ApiLog(LogType_Debug, "[GET elo] client=%d token=%d url=%s", client, g_iClientToken[client], url);

	Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);
	if (request == null)
	{
		SetClientApiError(client, "创建 ELO 请求失败（SteamWorks_CreateHTTPRequest 返回 null）");
		ApiLog(LogType_Error, "[GET elo] client=%d 创建请求失败：%s", client, url);
		return;
	}

	g_bEloRequestInFlight[client] = true;
	g_ClientInfo[client].status = view_as<int>(RatingProCache_Loading);
	ClearClientApiError(client);

	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, 10);
	SteamWorks_SetHTTPRequestContextValue(request, client, g_iClientToken[client]);
	SteamWorks_SetHTTPCallbacks(request, OnClientEloResponse);

	if (!SteamWorks_SendHTTPRequest(request))
	{
		g_bEloRequestInFlight[client] = false;
		g_ClientInfo[client].status = view_as<int>(RatingProCache_Error);
		SetClientApiError(client, "发送 ELO 请求失败（Steam 网络栈拒绝）");
		ApiLog(LogType_Error, "[GET elo] client=%d 发送请求失败（SteamWorks_SendHTTPRequest 返回 false）：%s", client, url);
		delete request;
	}
}

void RequestClientRecentRating(int client, const char[] encodedAuth)
{
	if (g_bRatingRequestInFlight[client])
	{
		return;
	}

	char path[256];
	Format(path, sizeof(path), API_RATING_AVERAGE_PATH, encodedAuth, RATINGPRO_MAX_RECENT_RATINGS);

	char url[512];
	FormatApiUrl(url, sizeof(url), path);

	ApiLog(LogType_Debug, "[GET rating] client=%d token=%d url=%s", client, g_iClientToken[client], url);

	Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);
	if (request == null)
	{
		ApiLog(LogType_Error, "[GET rating] client=%d 创建请求失败：%s", client, url);
		return;
	}

	g_bRatingRequestInFlight[client] = true;

	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, 10);
	SteamWorks_SetHTTPRequestContextValue(request, client, g_iClientToken[client]);
	SteamWorks_SetHTTPCallbacks(request, OnClientRatingResponse);

	if (!SteamWorks_SendHTTPRequest(request))
	{
		g_bRatingRequestInFlight[client] = false;
		ApiLog(LogType_Error, "[GET rating] client=%d 发送请求失败（SteamWorks_SendHTTPRequest 返回 false）：%s", client, url);
		delete request;
	}
}

public void OnClientEloResponse(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode, any data1, any data2)
{
	int client = data1;
	int token = data2;
	int status = view_as<int>(statusCode);

	bool transportOk = !failure && requestSuccessful;
	bool hasBody = ReadResponseBody(request, g_sHttpResponse, sizeof(g_sHttpResponse));
	delete request;

	// 槽位已被复用（玩家退服 / 换人）时丢弃这次结果。
	if (!IsValidClientIndex(client) || token != g_iClientToken[client])
	{
		ApiLog(LogType_Debug, "[GET elo] 丢弃过期响应：client=%d token=%d 当前 token=%d status=%d",
			client, token, g_iClientToken[client], status);
		return;
	}

	g_bEloRequestInFlight[client] = false;

	char auth[64];
	GetClientApiAuthForLog(client, auth, sizeof(auth));

	if (!transportOk)
	{
		SetClientApiError(client, "ELO 传输失败 failure=%d ok=%d status=%d body=%d 字节",
			failure ? 1 : 0, requestSuccessful ? 1 : 0, status, strlen(g_sHttpResponse));
		ApiLog(LogType_Error,
			"[GET elo] %N(%s) 传输失败：failure=%d requestSuccessful=%d status=%d body=%d 字节。常见原因：服务器出站 DNS/防火墙拦截、后端域名解析失败、TLS 握手失败。",
			client, auth, failure ? 1 : 0, requestSuccessful ? 1 : 0, status, strlen(g_sHttpResponse));
		if (hasBody)
		{
			ApiLogBody(LogType_Error, "[GET elo] 失败响应体", g_sHttpResponse);
		}

		g_ClientInfo[client].status = view_as<int>(RatingProCache_Error);
		FireClientDataLoaded(client, RatingProCache_Error);
		return;
	}

	if (status == 404)
	{
		ApiLog(LogType_Debug, "[GET elo] %N(%s) 后端无此玩家记录（HTTP 404）", client, auth);
		ClearClientApiError(client);

		g_ClientInfo[client].loaded = false;
		g_ClientInfo[client].status = view_as<int>(RatingProCache_NoRecord);
		FireClientDataLoaded(client, RatingProCache_NoRecord);
		return;
	}

	if (status != 200 || !hasBody)
	{
		SetClientApiError(client, "ELO HTTP %d body=%d 字节", status, strlen(g_sHttpResponse));
		ApiLog(LogType_Error, "[GET elo] %N(%s) 返回 HTTP %d（期望 200），body=%d 字节%s",
			client, auth, status, strlen(g_sHttpResponse), hasBody ? "" : "（未读到 body，原因见下一行）");
		if (hasBody)
		{
			ApiLogBody(LogType_Error, "[GET elo] 错误响应体", g_sHttpResponse);
		}

		g_ClientInfo[client].status = view_as<int>(RatingProCache_Error);
		FireClientDataLoaded(client, RatingProCache_Error);
		return;
	}

	if (!ParseEloResponse(client, g_sHttpResponse))
	{
		SetClientApiError(client, "ELO 响应解析失败（缺少 elo 字段）");
		ApiLog(LogType_Error, "[GET elo] %N(%s) 响应解析失败：HTTP 200 但不是预期的 JSON（缺少 elo 字段），检查后端返回结构是否变了。",
			client, auth);
		ApiLogBody(LogType_Error, "[GET elo] 解析失败响应体", g_sHttpResponse);

		g_ClientInfo[client].status = view_as<int>(RatingProCache_Error);
		FireClientDataLoaded(client, RatingProCache_Error);
		return;
	}

	ClearClientApiError(client);
	g_ClientInfo[client].loaded = true;
	g_ClientInfo[client].status = view_as<int>(RatingProCache_Ready);
	ApiLog(LogType_Debug, "[GET elo] %N(%s) 成功：elo=%.2f rank=%d/%d rounds=%d",
		client, auth, g_ClientInfo[client].elo, g_ClientInfo[client].rank,
		g_ClientInfo[client].totalPlayers, g_ClientInfo[client].rounds);
	ApiLogBody(LogType_Debug, "[GET elo] 响应体", g_sHttpResponse);
	FireClientDataLoaded(client, RatingProCache_Ready);
}

bool ParseEloResponse(int client, const char[] body)
{
	float elo;
	if (!JsonGetFloat(body, "elo", elo))
	{
		return false;
	}

	float peak;
	float kFactor;
	int rank;
	int totalPlayers;
	int rounds;
	int placementPlayed;
	int placementRequired;

	g_ClientInfo[client].elo = elo;
	g_ClientInfo[client].peakElo = JsonGetFloat(body, "peak_elo", peak) ? peak : elo;
	g_ClientInfo[client].kFactor = JsonGetFloat(body, "k_factor", kFactor) ? kFactor : 0.0;
	g_ClientInfo[client].rank = JsonGetInt(body, "rank", rank) ? rank : 0;
	g_ClientInfo[client].totalPlayers = JsonGetInt(body, "total_players", totalPlayers) ? totalPlayers : 0;
	g_ClientInfo[client].rounds = JsonGetInt(body, "rounds", rounds) ? rounds : 0;
	g_ClientInfo[client].placementPlayed = JsonGetInt(body, "placement.played", placementPlayed) ? placementPlayed : 0;
	g_ClientInfo[client].placementRequired = JsonGetInt(body, "placement.required", placementRequired) ? placementRequired : 0;

	float delta;
	g_ClientInfo[client].hasLastRound = JsonGetFloat(body, "last_round.elo_delta", delta);
	g_ClientInfo[client].lastDelta = g_ClientInfo[client].hasLastRound ? delta : 0.0;

	float lastRating;
	g_ClientInfo[client].lastRating = JsonGetFloat(body, "last_round.rating", lastRating) ? lastRating : 0.0;

	return true;
}

public void OnClientRatingResponse(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode, any data1, any data2)
{
	int client = data1;
	int token = data2;
	int status = view_as<int>(statusCode);

	bool transportOk = !failure && requestSuccessful;
	bool hasBody = ReadResponseBody(request, g_sHttpResponse, sizeof(g_sHttpResponse));
	delete request;

	if (!IsValidClientIndex(client) || token != g_iClientToken[client])
	{
		ApiLog(LogType_Debug, "[GET rating] 丢弃过期响应：client=%d token=%d 当前 token=%d status=%d",
			client, token, g_iClientToken[client], status);
		return;
	}

	g_bRatingRequestInFlight[client] = false;

	char auth[64];
	GetClientApiAuthForLog(client, auth, sizeof(auth));

	if (!transportOk)
	{
		ApiLog(LogType_Error, "[GET rating] %N(%s) 传输失败：failure=%d requestSuccessful=%d status=%d body=%d 字节。",
			client, auth, failure ? 1 : 0, requestSuccessful ? 1 : 0, status, strlen(g_sHttpResponse));
		if (hasBody)
		{
			ApiLogBody(LogType_Error, "[GET rating] 失败响应体", g_sHttpResponse);
		}

		g_ClientInfo[client].hasRecent = false;
		return;
	}

	if (status == 404)
	{
		ApiLog(LogType_Debug, "[GET rating] %N(%s) 无历史评分（HTTP 404）", client, auth);
		g_ClientInfo[client].hasRecent = false;
		return;
	}

	if (status != 200 || !hasBody)
	{
		ApiLog(LogType_Error, "[GET rating] %N(%s) 返回 HTTP %d（期望 200），body=%d 字节%s",
			client, auth, status, strlen(g_sHttpResponse), hasBody ? "" : "（未读到 body，原因见下一行）");
		if (hasBody)
		{
			ApiLogBody(LogType_Error, "[GET rating] 错误响应体", g_sHttpResponse);
		}

		g_ClientInfo[client].hasRecent = false;
		return;
	}

	ParseRatingAverageResponse(client, g_sHttpResponse);

	if (g_ClientInfo[client].hasRecent)
	{
		ApiLog(LogType_Debug, "[GET rating] %N(%s) 成功：最近平均=%.2f（%d 场）",
			client, auth, g_ClientInfo[client].recentAverage, g_ClientInfo[client].recentCount);
	}
	else
	{
		ApiLog(LogType_Error, "[GET rating] %N(%s) 响应解析失败：HTTP 200 但缺少 average 字段。", client, auth);
		ApiLogBody(LogType_Error, "[GET rating] 解析失败响应体", g_sHttpResponse);
	}
}

void ParseRatingAverageResponse(int client, const char[] body)
{
	float average;
	if (!JsonGetFloat(body, "average", average))
	{
		g_ClientInfo[client].hasRecent = false;
		return;
	}

	float averageRaw;
	float best;
	float worst;
	int count;
	int totalEligible;

	g_ClientInfo[client].recentAverage = average;
	g_ClientInfo[client].recentAverageRaw = JsonGetFloat(body, "average_raw", averageRaw) ? averageRaw : 0.0;
	g_ClientInfo[client].recentBest = JsonGetFloat(body, "best", best) ? best : average;
	g_ClientInfo[client].recentWorst = JsonGetFloat(body, "worst", worst) ? worst : average;
	g_ClientInfo[client].recentCount = JsonGetInt(body, "count", count) ? count : 0;
	g_ClientInfo[client].recentTotalEligible = JsonGetInt(body, "total_eligible_rounds", totalEligible) ? totalEligible : 0;
	g_ClientInfo[client].hasRecent = true;

	int valueCount = JsonGetArrayLength(body, "values");
	if (valueCount > RATINGPRO_MAX_RECENT_RATINGS)
	{
		valueCount = RATINGPRO_MAX_RECENT_RATINGS;
	}

	g_ClientInfo[client].recentValueCount = 0;
	for (int index = 0; index < valueCount; index++)
	{
		char element[1024];
		if (!JsonGetArrayElement(body, "values", index, element, sizeof(element)))
		{
			continue;
		}

		float rating;
		if (!JsonGetFloat(element, "rating", rating))
		{
			continue;
		}

		g_ClientInfo[client].recentValues[g_ClientInfo[client].recentValueCount] = rating;
		g_ClientInfo[client].recentValueCount++;
	}
}

// ------------------------------ 战役跟踪 ------------------------------

// 读取双方战役累计比分；left4dhooks 不存在或尚未就绪时返回 false，判定自动降级。
bool TryGetCampaignScores(int &scoreA, int &scoreB)
{
	scoreA = 0;
	scoreB = 0;

	if (GetFeatureStatus(FeatureType_Native, "L4D_GetTeamScore") != FeatureStatus_Available)
	{
		return false;
	}

	scoreA = L4D_GetTeamScore(1, true);
	scoreB = L4D_GetTeamScore(2, true);

	return scoreA >= 0 && scoreB >= 0;
}

// ------------------------------ 胜负判定 ------------------------------

bool HasTeamScoreNative()
{
	return GetFeatureStatus(FeatureType_Native, "L4D_GetTeamScore") == FeatureStatus_Available;
}

// 第一半场结束时只有一支逻辑队已经打过分（另一支返回 -1），打过的那支就是这半场的生还方。
// 记下来是为了在第二半场结算时把「逻辑队」换算成「第二半场所在方」的编号。
// 只在拿到确定答案时写入，绝不把已经记下来的值清成 0（后面还有补读的机会）。
void RememberFirstHalfSurvivorTeam()
{
	if (!HasTeamScoreNative())
	{
		return;
	}

	int scoreA = L4D_GetTeamScore(1, false);
	int scoreB = L4D_GetTeamScore(2, false);

	int logicalTeam = 0;
	if (scoreA >= 0 && scoreB < 0)
	{
		logicalTeam = 1;
	}
	else if (scoreB >= 0 && scoreA < 0)
	{
		logicalTeam = 2;
	}

	if (logicalTeam == 0)
	{
		return;
	}

	g_iFirstHalfLogicalTeam = logicalTeam;
	g_iFirstHalfScoreA = scoreA;
	g_iFirstHalfScoreB = scoreB;

	LogMessage("[RatingPro] 第一半场生还方 = 逻辑队 %d（地图分 A=%d / B=%d）。", logicalTeam, scoreA, scoreB);
}

// 第二半场开场后延迟补读一次第一半场的生还方（半场刚开时个别环境仍读到 -1）。
public Action Timer_RememberFirstHalfTeam(Handle timer)
{
	if (g_iFirstHalfLogicalTeam == 0)
	{
		RememberFirstHalfSurvivorTeam();
	}

	return Plugin_Stop;
}

// 本图胜负 = 双方地图分高的一方（一张图两个半场，各当一次生还者，比分可直接比较）。
// 结果换算成「第二半场所在方」的编号，和 players[].team 同口径，后端据此结算「表现 + 胜负」。
// 返回 false = 地图分还没落账、值得稍后重试；true = 已有终局答案（含打平 / 无 native / 映射未知）。
bool ResolveMapWinner()
{
	g_iMapWinnerTeam = 0;
	g_iMapScoreA = -1;
	g_iMapScoreB = -1;

	if (!HasTeamScoreNative())
	{
		return true;
	}

	int scoreA = L4D_GetTeamScore(1, false);
	int scoreB = L4D_GetTeamScore(2, false);

	if (scoreA < 0 || scoreB < 0)
	{
		return false;
	}

	g_iMapScoreA = scoreA;
	g_iMapScoreB = scoreB;

	if (g_iFirstHalfLogicalTeam != 1 && g_iFirstHalfLogicalTeam != 2)
	{
		LogMessage("[RatingPro] 读到地图分 A=%d / B=%d，但第一半场生还方未知，本图不判定胜负（比分也换算不出 2/3 队伍编号）。",
			scoreA, scoreB);
		return true;
	}

	if (scoreA == scoreB)
	{
		LogMessage("[RatingPro] 本图双方地图分相同（%d:%d），不判定胜负，按表现 ELO 结算。", scoreA, scoreB);
		return true;
	}

	int winnerLogical = (scoreA > scoreB) ? 1 : 2;
	int secondHalfLogical = (g_iFirstHalfLogicalTeam == 1) ? 2 : 1;

	g_iMapWinnerTeam = (winnerLogical == secondHalfLogical) ? TEAM_SURVIVOR : TEAM_INFECTED;

	LogMessage("[RatingPro] 本图胜负：地图分 A=%d / B=%d，第一半场生还方为逻辑队 %d，第二半场生还方为逻辑队 %d → winner_team=%d。",
		scoreA, scoreB, g_iFirstHalfLogicalTeam, secondHalfLogical, g_iMapWinnerTeam);

	return true;
}

// 把逻辑队 A/B 的地图分换算成 players[].team 的 2/3 编号（= 第二半场所在方）。
// 换算依赖「第一半场谁是生还者」，映射未知时返回 false —— 宁可不上报，也不上报错位的比分。
bool TryGetTeamScores(int &team2Score, int &team3Score)
{
	team2Score = -1;
	team3Score = -1;

	if (g_iMapScoreA < 0 || g_iMapScoreB < 0)
	{
		return false;
	}

	if (g_iFirstHalfLogicalTeam != 1 && g_iFirstHalfLogicalTeam != 2)
	{
		return false;
	}

	int secondHalfLogical = (g_iFirstHalfLogicalTeam == 1) ? 2 : 1;
	team2Score = (secondHalfLogical == 1) ? g_iMapScoreA : g_iMapScoreB;
	team3Score = (secondHalfLogical == 1) ? g_iMapScoreB : g_iMapScoreA;

	return true;
}

// 快照里的队伍编号：统一按「第二半场所在方」。
// 只在第一半场露过面的人（中途退服等），最后所在边是第一半场的边，取反后才是结算时所属的那一队。
int ResolveSnapshotTeam(int participant)
{
	int lastTeam = g_iParticipantTeam[participant];

	if (lastTeam != TEAM_SURVIVOR && lastTeam != TEAM_INFECTED)
	{
		return lastTeam;
	}

	if (g_bParticipantSecondHalf[participant])
	{
		return lastTeam;
	}

	return (lastTeam == TEAM_SURVIVOR) ? TEAM_INFECTED : TEAM_SURVIVOR;
}

// 唯一判据：双方战役累计比分单调不减。回退了就说明有人重开过战役，这段序列作废。
// 地图名一概不参与判定（连解析都不做）—— 仓库里有插件能把随机地图拼成章节序列，
// 前缀和章节号在那种服务器上说明不了连续性，日志里只记原始图名。
// 这一条依赖引擎的战役累计分；个别环境读不准时可用 sm_ratingpro_score_guard 0 关掉，
// 关掉后就没有任何断章信号了，上传计数只会在攒满上传时归零。
bool IsCampaignBroken(bool hasScores, int scoreA, int scoreB)
{
	if (!hasScores || !g_bCampaignHasScoreBaseline || !g_hScoreGuard.BoolValue)
	{
		return false;
	}

	return scoreA < g_iCampaignLastScoreA || scoreB < g_iCampaignLastScoreB;
}

// 章节中断只重置「上传计数」，评分窗口（RAW_HISTORY_SLOTS）保持原始跨图滚动口径，不跟着清空。
void ResetCampaignProgress()
{
	g_iCampaignMaps = 0;
	g_bCampaignHasScoreBaseline = false;
	g_iCampaignLastScoreA = 0;
	g_iCampaignLastScoreB = 0;
	g_sCampaignStartMap[0] = '\0';
}

// 每次正式结算前调用：判定这张图是否接着上一段连续对局（只看双方比分有没有回退）；
// 断了就重置上传计数，评分窗口原样保留。
void UpdateCampaignProgress()
{
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));

	int scoreA;
	int scoreB;
	bool hasScores = TryGetCampaignScores(scoreA, scoreB);

	if (g_iCampaignMaps > 0 && IsCampaignBroken(hasScores, scoreA, scoreB))
	{
		char scoreNote[64];
		if (hasScores)
		{
			Format(scoreNote, sizeof(scoreNote), "，比分 %d:%d → %d:%d",
				g_iCampaignLastScoreA, g_iCampaignLastScoreB, scoreA, scoreB);
		}
		else
		{
			scoreNote[0] = '\0';
		}

		LogMessage("[RatingPro] 序列中断：上一段起点 %s，已结算 %d 张图%s；从当前图 %s 重新开始，本段不完整对局不上传，仅重置上传计数。",
			g_sCampaignStartMap, g_iCampaignMaps, scoreNote, map);

		ResetCampaignProgress();
		g_iCampaignSeqId++;
	}

	if (g_iCampaignMaps == 0)
	{
		if (g_iCampaignSeqId == 0)
		{
			g_iCampaignSeqId = 1;
		}

		strcopy(g_sCampaignStartMap, sizeof(g_sCampaignStartMap), map);
	}

	g_iCampaignLastScoreA = scoreA;
	g_iCampaignLastScoreB = scoreB;
	g_bCampaignHasScoreBaseline = hasScores;
	g_iCampaignMaps++;
}

// ------------------------------ 上传 ------------------------------

void MaybeUploadCampaign()
{
	if (!IsApiWritable())
	{
		return;
	}

	int requiredMaps = g_hUploadMaps.IntValue;
	if (requiredMaps < 1 || g_iCampaignMaps < requiredMaps)
	{
		return;
	}

	// 上一次上传还没结清（在途 / 等重试）：这一段继续攒着，等下个结算点再传，
	// 免得把仍在重试的载荷覆盖掉。
	if (g_bUploadInFlight || g_bUploadPending)
	{
		return;
	}

	if (g_iParticipantCount <= 0)
	{
		return;
	}

	// 人数不够不算一次有效对局：这段数据不入库，计数器归零重新攒。
	// 之所以不「跳过等下一局」，是因为 players[] 只取自触发的这一张图：
	// 攒着不消费会让下一局的上传把这段稀薄战绩连同错配的人数一起带出去。
	int minPlayers = g_hMinPlayers.IntValue;
	if (minPlayers > 0 && g_iParticipantCount < minPlayers)
	{
		LogMessage("[RatingPro] 本局参与人数 %d 未达到 sm_ratingpro_min_players=%d，这 %d 张图的数据不上传，计数器归零。",
			g_iParticipantCount, minPlayers, g_iCampaignMaps);

		g_iCampaignMaps = 0;
		return;
	}

	int settledMaps = g_iCampaignMaps;

	// 评分窗口沿用原始插件的跨图滚动口径，因此可能仍含上一段（已中断、不参与上传）的图。
	// 这里只记录一次覆盖情况，不阻断上传：上传与否只看本段累计了多少张图。
	// 归属按段序号判断：同一段里跨过的图前缀可能变、章节可能跳，都算本段。
	int foreignSlots = 0;
	for (int slot = 0; slot < g_iRawHistoryCount; slot++)
	{
		if (g_iRawHistorySeq[slot] > 0 && g_iRawHistorySeq[slot] != g_iCampaignSeqId)
		{
			foreignSlots++;
		}
	}

	if (foreignSlots > 0)
	{
		LogMessage("[RatingPro] 评分窗口含 %d 个上一段序列的槽位（%d/%d 张图属于当前序列，本段起点 %s），按原始跨图口径保留。",
			foreignSlots, g_iRawHistoryCount - foreignSlots, g_iRawHistoryCount, g_sCampaignStartMap);
	}

	g_iPendingUploadSnapshotId = g_iSnapshotRoundId;
	g_iUploadAttempts = 0;
	g_bUploadPending = true;

	BuildUploadPayload();

	// 攒满即视为这一段已交付：计数器归零，从下一张图重新开始攒。
	// 成功、后端判重、以及重试彻底失败都不回补，避免同一段被反复上传。
	g_iCampaignMaps = 0;

	if (g_iPendingUploadPlayerCount <= 0)
	{
		LogMessage("[RatingPro] 本轮已累计 %d 张图但没有可上传的玩家记录，跳过本次上传并重置计数器。", settledMaps);
		ClearPendingUpload();
		return;
	}

	SendUploadRequest();
}

bool IsApiWritable()
{
	if (!g_hApiEnabled.BoolValue)
	{
		return false;
	}

	char apiKey[256];
	g_hApiKey.GetString(apiKey, sizeof(apiKey));
	if (apiKey[0] == '\0')
	{
		if (!g_bApiKeyWarned)
		{
			g_bApiKeyWarned = true;
			LogError("[RatingPro] sm_ratingpro_api_key 未配置，对局数据不会上传。");
		}
		return false;
	}

	return true;
}

void GetServerKey(char[] buffer, int size)
{
	buffer[0] = '\0';
	g_hServerKey.GetString(buffer, size);
	if (buffer[0] == '\0')
	{
		GetServerHostname(buffer, size);
	}
	if (buffer[0] == '\0')
	{
		strcopy(buffer, size, "default");
	}
}

void GetServerHostname(char[] buffer, int size)
{
	buffer[0] = '\0';

	ConVar hostname = FindConVar("hostname");
	if (hostname != null)
	{
		hostname.GetString(buffer, size);
	}
}

void GetServerDisplayName(char[] buffer, int size)
{
	GetServerHostname(buffer, size);
	if (buffer[0] == '\0')
	{
		strcopy(buffer, size, "L4D2 Server");
	}
}

void FormatApiUrl(char[] buffer, int size, const char[] path)
{
	char base[256];
	g_hApiBase.GetString(base, sizeof(base));

	int length = strlen(base);
	while (length > 0 && base[length - 1] == '/')
	{
		base[length - 1] = '\0';
		length--;
	}

	Format(buffer, size, "%s%s", base, path);
}

void BuildUploadPayload()
{
	g_sUploadPayload[0] = '\0';

	char temp[1024];
	char escaped[640];
	char serverKey[PLATFORM_MAX_PATH];
	char serverName[MAX_NAME_LENGTH * 2];

	GetServerKey(serverKey, sizeof(serverKey));
	GetServerDisplayName(serverName, sizeof(serverName));

	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), "{\"schema_version\":2,\"stats_scope\":\"cumulative\"");

	JsonEscape(serverKey, escaped, sizeof(escaped));
	Format(temp, sizeof(temp), ",\"server\":{\"key\":\"%s\"", escaped);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	JsonEscape(serverName, escaped, sizeof(escaped));
	Format(temp, sizeof(temp), ",\"name\":\"%s\"}", escaped);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	// 幂等键固定为「服务器 | 地图 | 快照号 | 结算时间」：同一份载荷重试时完全一致，后端据此去重。
	Format(g_sUploadExternalId, sizeof(g_sUploadExternalId), "%s|%s|%d|%s",
		serverKey, g_sSnapshotMap, g_iSnapshotRoundId, g_sSnapshotTime);

	JsonEscape(g_sUploadExternalId, escaped, sizeof(escaped));
	Format(temp, sizeof(temp), ",\"snapshot\":{\"external_id\":\"%s\"", escaped);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	Format(temp, sizeof(temp), ",\"snapshot_id\":%d", g_iSnapshotRoundId);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	JsonEscape(g_sSnapshotMap, escaped, sizeof(escaped));
	Format(temp, sizeof(temp), ",\"map\":\"%s\"", escaped);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	char maps[RAW_HISTORY_SLOTS][MAP_NAME_LENGTH];
	int mapCount = CollectHistoryMapNames("", maps);

	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), ",\"maps\":[");
	for (int index = 0; index < mapCount; index++)
	{
		if (index > 0)
		{
			StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), ",");
		}

		JsonEscape(maps[index], escaped, sizeof(escaped));
		Format(temp, sizeof(temp), "\"%s\"", escaped);
		StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);
	}
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), "]");

	Format(temp, sizeof(temp), ",\"map_count\":%d", mapCount);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	if (g_sSnapshotTime[0] != '\0')
	{
		JsonEscape(g_sSnapshotTime, escaped, sizeof(escaped));
		Format(temp, sizeof(temp), ",\"settled_at\":\"%s\"", escaped);
		StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);
	}

	// 有明确胜负才带 winner_team：后端拿它当「表现 + 胜负」混合 ELO 的胜负分量，
	// 2/3 与 players[].team 同口径（= 第二半场所在方）。
	if (g_iMapWinnerTeam == TEAM_SURVIVOR || g_iMapWinnerTeam == TEAM_INFECTED)
	{
		Format(temp, sizeof(temp), ",\"winner_team\":%d", g_iMapWinnerTeam);
		StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);
	}

	// 双方地图分：前端展示比分，也是 winner_team 缺失时后端自行判胜负的依据。
	// 换算不出 2/3 归属就不带 —— 错位的比分比没有比分更糟。
	int team2Score;
	int team3Score;
	if (TryGetTeamScores(team2Score, team3Score))
	{
		Format(temp, sizeof(temp), ",\"team_scores\":{\"2\":%d,\"3\":%d}", team2Score, team3Score);
		StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);
	}

	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), ",\"mode\":\"versus\"}");

	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), ",\"players\":[");

	int added = 0;
	for (int participant = 0; participant < g_iParticipantCount; participant++)
	{
		if (g_sParticipantAuth[participant][0] == '\0')
		{
			continue;
		}

		RatingSnapshotEntry entry;
		if (!g_hLastRatingSnapshot.GetArray(g_sParticipantAuth[participant], entry, sizeof(entry)))
		{
			continue;
		}

		// 留出单个玩家条目 + 结尾 "]} " 的余量，避免载荷超长被截断成非法 JSON。
		if (strlen(g_sUploadPayload) + 1024 >= sizeof(g_sUploadPayload))
		{
			LogError("[RatingPro] 上传载荷达到上限，跳过剩余玩家（已写入 %d 人）。", added);
			break;
		}

		AppendPlayerJson(participant, entry, added);
		added++;
	}

	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), "]}");
	g_iPendingUploadPlayerCount = added;
}

void AppendPlayerJson(int participant, RatingSnapshotEntry entry, int index)
{
	char temp[1024];
	char escaped[640];

	if (index > 0)
	{
		StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), ",");
	}

	JsonEscape(g_sParticipantAuth[participant], escaped, sizeof(escaped));
	Format(temp, sizeof(temp), "{\"steam_id\":\"%s\"", escaped);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	char name[MAX_NAME_LENGTH];
	CleanName(g_sParticipantName[participant], name, sizeof(name));
	JsonEscape(name, escaped, sizeof(escaped));
	Format(temp, sizeof(temp), ",\"name\":\"%s\"", escaped);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	Format(temp, sizeof(temp), ",\"team\":%d,\"eligible\":%s,\"recorded_slots\":%d,\"tank_source\":%d",
		entry.team, entry.eligible ? "true" : "false", entry.recordedSlots, entry.tankSource);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	Format(temp, sizeof(temp), ",\"rating\":%.2f,\"raw\":%.2f", entry.rating, entry.raw);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	Format(temp, sizeof(temp),
		",\"normalized\":{\"output\":%.2f,\"defense\":%.2f,\"focus\":%.2f,\"infector\":%.2f,\"tank\":%.2f}",
		entry.output, entry.defense, entry.focus, entry.infector, entry.tank);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	Format(temp, sizeof(temp),
		",\"raw_scores\":{\"output\":%.2f,\"defense\":%.2f,\"focus\":%.2f,\"infector\":%.2f,\"tank\":%.2f}",
		entry.outputRaw, entry.defenseRaw, entry.focusRaw, entry.infectorRaw, entry.tankRaw);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	Format(temp, sizeof(temp),
		",\"survivor\":{\"si_dmg\":%d,\"ci_kill\":%d,\"tank_dmg\":%d,\"dmg_taken\":%d,\"incaps\":%d,\"deaths\":%d,\"ff\":%d,\"tankup_dmg\":%d,\"tankup_kill\":%d,\"skeet\":%d,\"level\":%d,\"pop\":%d,\"tongue_cut\":%d,\"crown\":%d}",
		entry.siDmg, entry.ciKill, entry.tankDmg, entry.dmgTaken, entry.incaps, entry.deaths,
		entry.ff, entry.tankupDmg, entry.tankupKill, entry.skeet, entry.level, entry.pop,
		entry.tongueCut, entry.crown);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	Format(temp, sizeof(temp), ",\"infected\":{\"dmg\":%d,\"booms\":%d,\"death_charges\":%d}",
		entry.dmg, entry.booms, entry.deathCharges);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);

	Format(temp, sizeof(temp),
		",\"tank\":{\"became_tank\":%s,\"dmg_upright\":%d,\"punch\":%d,\"rock\":%d,\"hittable\":%d,\"incap\":%d,\"death\":%d}}",
		entry.becameTank ? "true" : "false", entry.tankDmgUpright, entry.punch, entry.rock,
		entry.hittable, entry.incap, entry.death);
	StrCat(g_sUploadPayload, sizeof(g_sUploadPayload), temp);
}

void SendUploadRequest()
{
	if (g_bUploadInFlight)
	{
		g_bUploadPending = true;
		return;
	}

	char apiKey[256];
	g_hApiKey.GetString(apiKey, sizeof(apiKey));
	if (apiKey[0] == '\0')
	{
		return;
	}

	char url[512];
	FormatApiUrl(url, sizeof(url), API_UPLOAD_PATH);

	Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, url);
	if (request == null)
	{
		ApiLog(LogType_Error, "[POST upload] 创建上传请求失败（SteamWorks_CreateHTTPRequest 返回 null）：%s", url);
		ScheduleUploadRetry();
		return;
	}

	char header[320];
	Format(header, sizeof(header), "Bearer %s", apiKey);

	g_iUploadToken++;
	g_bUploadInFlight = true;

	ApiLog(LogType_Debug, "[POST upload] snapshot=#%d token=%d 人数=%d 载荷=%d 字节 url=%s",
		g_iPendingUploadSnapshotId, g_iUploadToken, g_iPendingUploadPlayerCount,
		strlen(g_sUploadPayload), url);
	// Authorization 头里有 api_key，绝不写日志；载荷里只有对局数据与 server_key。
	ApiLogBody(LogType_Debug, "[POST upload] 载荷", g_sUploadPayload);

	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, 20);
	SteamWorks_SetHTTPRequestHeaderValue(request, "Content-Type", "application/json; charset=utf-8");
	SteamWorks_SetHTTPRequestHeaderValue(request, "Authorization", header);
	SteamWorks_SetHTTPRequestContextValue(request, g_iPendingUploadSnapshotId, g_iUploadToken);
	SteamWorks_SetHTTPCallbacks(request, OnUploadCompleted);
	SteamWorks_SetHTTPRequestRawPostBody(request, "application/json; charset=utf-8",
		g_sUploadPayload, strlen(g_sUploadPayload));

	if (!SteamWorks_SendHTTPRequest(request))
	{
		g_bUploadInFlight = false;
		delete request;
		ApiLog(LogType_Error, "[POST upload] 发送请求失败（SteamWorks_SendHTTPRequest 返回 false）：snapshot=#%d token=%d url=%s",
			g_iPendingUploadSnapshotId, g_iUploadToken, url);
		ScheduleUploadRetry();
		return;
	}

	g_bUploadPending = false;
}

void ScheduleUploadRetry()
{
	g_iUploadAttempts++;
	if (g_iUploadAttempts >= UPLOAD_MAX_ATTEMPTS)
	{
		LogError("[RatingPro] 对局数据上传连续失败 %d 次，放弃本次上传（快照 #%d）。",
			g_iUploadAttempts, g_iPendingUploadSnapshotId);
		ClearPendingUpload();
		return;
	}

	g_bUploadPending = true;
	CreateTimer(UPLOAD_RETRY_DELAY * float(g_iUploadAttempts), Timer_RetryUpload);
}

public Action Timer_RetryUpload(Handle timer)
{
	if (!g_bUploadPending || g_bUploadInFlight)
	{
		return Plugin_Stop;
	}

	g_bUploadPending = false;
	SendUploadRequest();
	return Plugin_Stop;
}

void ClearPendingUpload()
{
	g_bUploadPending = false;
	g_iUploadAttempts = 0;
	g_iPendingUploadPlayerCount = 0;
	g_sUploadPayload[0] = '\0';
	g_sUploadExternalId[0] = '\0';
	g_iUploadToken++;
}

public void OnUploadCompleted(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode, any data1, any data2)
{
	int snapshotId = data1;
	int token = data2;
	int status = view_as<int>(statusCode);

	bool transportOk = !failure && requestSuccessful;
	bool hasBody = ReadResponseBody(request, g_sHttpResponse, sizeof(g_sHttpResponse));
	delete request;

	if (token != g_iUploadToken)
	{
		ApiLog(LogType_Debug, "[POST upload] 丢弃过期响应：snapshot=#%d token=%d 当前 token=%d status=%d",
			snapshotId, token, g_iUploadToken, status);
		return;
	}

	g_bUploadInFlight = false;

	// ClearPendingUpload() 会清零计数，先抓一份给 forward 用。
	int playerCount = g_iPendingUploadPlayerCount;

	bool success = transportOk && (status == 200 || status == 201);

	if (!success)
	{
		char detail[400];
		detail[0] = '\0';
		if (hasBody)
		{
			strcopy(detail, sizeof(detail), g_sHttpResponse);
		}

		LogError("[RatingPro] 对局数据上传失败（快照 #%d，%d 人，HTTP %d）：%s",
			snapshotId, playerCount, status, detail);

		// 网络层失败、429 限流与 5xx 值得重试；4xx 属于载荷/鉴权问题，重试也不会成功。
		bool retryable = !transportOk || status == 0 || status == 429 || status >= 500;

		ApiLog(LogType_Error, "[POST upload] snapshot=#%d 失败：transportOk=%d status=%d body=%d 字节 → %s",
			snapshotId, transportOk ? 1 : 0, status, strlen(g_sHttpResponse),
			retryable ? "可重试（网络/429/5xx）" : "不可重试（4xx：载荷或 api_key 被拒），丢弃本段载荷");
		if (hasBody)
		{
			ApiLogBody(LogType_Error, "[POST upload] 失败响应体", g_sHttpResponse);
		}

		if (retryable)
		{
			ScheduleUploadRetry();
		}
		else
		{
			ClearPendingUpload();
		}

		FireEloUploaded(snapshotId, status, false, playerCount);
		return;
	}

	bool duplicate = false;
	JsonGetBool(g_sHttpResponse, "duplicate", duplicate);

	ApplyUploadResults(g_sHttpResponse);

	LogMessage("[RatingPro] 对局数据上传成功（快照 #%d，%d 人，HTTP %d%s）。",
		snapshotId, playerCount, status, duplicate ? "，后端判定重复" : "");

	ApiLog(LogType_Debug, "[POST upload] snapshot=#%d 成功：HTTP %d%s",
		snapshotId, status, duplicate ? "（后端判定重复）" : "");
	ApiLogBody(LogType_Debug, "[POST upload] 响应体", g_sHttpResponse);

	FireEloUploaded(snapshotId, status, true, playerCount);
	ClearPendingUpload();

	// 后端已重算 ELO 与平均分，稍后再刷一次在线玩家缓存，让 !rating / 其他插件看到新值。
	CreateTimer(RATING_REFRESH_DELAY, Timer_RefreshOnlineClients);
}

// 把后端回传的 elo_before / elo_after 直接写回缓存，并通知订阅者。
void ApplyUploadResults(const char[] body)
{
	int count = JsonGetArrayLength(body, "results");
	for (int index = 0; index < count; index++)
	{
		char element[1024];
		if (!JsonGetArrayElement(body, "results", index, element, sizeof(element)))
		{
			continue;
		}

		char steamId[64];
		if (!JsonGetValue(element, "steam_id", steamId, sizeof(steamId)))
		{
			continue;
		}

		int client = FindClientByAuth(steamId);
		if (client <= 0)
		{
			continue;
		}

		float after;
		if (!JsonGetFloat(element, "elo_after", after))
		{
			continue;
		}

		float before;
		float delta;
		if (!JsonGetFloat(element, "elo_before", before))
		{
			before = g_ClientInfo[client].elo;
		}
		if (!JsonGetFloat(element, "elo_delta", delta))
		{
			delta = after - before;
		}

		g_ClientInfo[client].elo = after;
		g_ClientInfo[client].hasLastRound = true;
		g_ClientInfo[client].lastDelta = delta;
		g_ClientInfo[client].status = view_as<int>(RatingProCache_Ready);

		FireClientEloUpdated(client, before, after, delta);
	}
}

public Action Timer_RefreshOnlineClients(Handle timer)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsHumanClient(client))
		{
			RequestClientApiData(client);
		}
	}

	return Plugin_Stop;
}

// ------------------------------ 回调派发 ------------------------------

void FireClientDataLoaded(int client, RatingProCacheStatus status)
{
	if (g_hFwdClientDataLoaded == null)
	{
		return;
	}

	Call_StartForward(g_hFwdClientDataLoaded);
	Call_PushCell(client);
	Call_PushCell(view_as<int>(status));
	Call_Finish();
}

void FireClientEloUpdated(int client, float eloBefore, float eloAfter, float delta)
{
	if (g_hFwdClientEloUpdated == null)
	{
		return;
	}

	Call_StartForward(g_hFwdClientEloUpdated);
	Call_PushCell(client);
	Call_PushFloat(eloBefore);
	Call_PushFloat(eloAfter);
	Call_PushFloat(delta);
	Call_Finish();
}

void FireEloUploaded(int snapshotId, int httpStatus, bool success, int playerCount)
{
	if (g_hFwdEloUploaded == null)
	{
		return;
	}

	Call_StartForward(g_hFwdEloUploaded);
	Call_PushCell(snapshotId);
	Call_PushCell(httpStatus);
	Call_PushCell(success);
	Call_PushCell(playerCount);
	Call_Finish();
}

// ------------------------------ Natives ------------------------------

public any Native_GetClientCacheStatus(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client))
	{
		return view_as<any>(view_as<int>(RatingProCache_None));
	}

	return view_as<any>(g_ClientInfo[client].status);
}

public any Native_IsClientDataReady(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return view_as<any>(IsValidClientIndex(client) && g_ClientInfo[client].loaded);
}

public any Native_GetClientElo(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client) || !g_ClientInfo[client].loaded)
	{
		return view_as<any>(false);
	}

	SetNativeCellRef(2, view_as<any>(g_ClientInfo[client].elo));
	SetNativeCellRef(3, view_as<any>(g_ClientInfo[client].peakElo));
	SetNativeCellRef(4, g_ClientInfo[client].rank);
	SetNativeCellRef(5, g_ClientInfo[client].totalPlayers);
	return view_as<any>(true);
}

public any Native_GetClientEloValue(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client) || !g_ClientInfo[client].loaded)
	{
		return view_as<any>(0.0);
	}

	return view_as<any>(g_ClientInfo[client].elo);
}

public any Native_GetClientPeakElo(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client) || !g_ClientInfo[client].loaded)
	{
		return view_as<any>(0.0);
	}

	return view_as<any>(g_ClientInfo[client].peakElo);
}

public any Native_GetClientEloRank(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client) || !g_ClientInfo[client].loaded)
	{
		return 0;
	}

	return g_ClientInfo[client].rank;
}

public any Native_GetClientEloTotalPlayers(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client) || !g_ClientInfo[client].loaded)
	{
		return 0;
	}

	return g_ClientInfo[client].totalPlayers;
}

public any Native_GetClientEloRounds(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client) || !g_ClientInfo[client].loaded)
	{
		return 0;
	}

	return g_ClientInfo[client].rounds;
}

public any Native_GetClientEloKFactor(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client) || !g_ClientInfo[client].loaded)
	{
		return view_as<any>(0.0);
	}

	return view_as<any>(g_ClientInfo[client].kFactor);
}

public any Native_GetClientPlacementPlayed(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client) || !g_ClientInfo[client].loaded)
	{
		return 0;
	}

	return g_ClientInfo[client].placementPlayed;
}

public any Native_GetClientPlacementRequired(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client) || !g_ClientInfo[client].loaded)
	{
		return 0;
	}

	return g_ClientInfo[client].placementRequired;
}

public any Native_GetClientLastEloDelta(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client) || !g_ClientInfo[client].hasLastRound)
	{
		return view_as<any>(false);
	}

	SetNativeCellRef(2, view_as<any>(g_ClientInfo[client].lastDelta));
	return view_as<any>(true);
}

public any Native_GetClientRecentRating(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client) || !g_ClientInfo[client].hasRecent)
	{
		return view_as<any>(false);
	}

	SetNativeCellRef(2, view_as<any>(g_ClientInfo[client].recentAverage));
	SetNativeCellRef(3, view_as<any>(g_ClientInfo[client].recentAverageRaw));
	SetNativeCellRef(4, g_ClientInfo[client].recentCount);
	return view_as<any>(true);
}

public any Native_GetClientRecentRatingAverage(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client) || !g_ClientInfo[client].hasRecent)
	{
		return view_as<any>(0.0);
	}

	return view_as<any>(g_ClientInfo[client].recentAverage);
}

public any Native_GetClientRecentRatingCount(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClientIndex(client) || !g_ClientInfo[client].hasRecent)
	{
		return 0;
	}

	return g_ClientInfo[client].recentCount;
}

public any Native_GetClientRecentRatingAt(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int index = GetNativeCell(2);

	if (!IsValidClientIndex(client) || !g_ClientInfo[client].hasRecent
		|| index < 0 || index >= g_ClientInfo[client].recentValueCount)
	{
		return view_as<any>(false);
	}

	SetNativeCellRef(3, view_as<any>(g_ClientInfo[client].recentValues[index]));
	return view_as<any>(true);
}

public any Native_RefreshClientData(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (IsValidClientIndex(client))
	{
		RequestClientApiData(client);
	}

	return 0;
}

public any Native_GetSnapshotId(Handle plugin, int numParams)
{
	return g_iSnapshotRoundId;
}

public any Native_GetCampaignMapCount(Handle plugin, int numParams)
{
	return g_iCampaignMaps;
}

public any Native_HasPendingUpload(Handle plugin, int numParams)
{
	return view_as<any>(g_bUploadPending || g_bUploadInFlight);
}

// ------------------------------ 运维排查 ------------------------------

// 只读诊断：确认战役累计、上传状态与玩家缓存是否按预期工作，不改变任何状态。
public Action Command_ApiDebug(int client, int args)
{
	char base[256];
	g_hApiBase.GetString(base, sizeof(base));

	char serverKey[PLATFORM_MAX_PATH];
	GetServerKey(serverKey, sizeof(serverKey));

	char apiKey[256];
	g_hApiKey.GetString(apiKey, sizeof(apiKey));

	ReplyToCommand(client, "[RatingPro] 后端: enabled=%d base=%s server_key=%s api_key=%s",
		g_hApiEnabled.BoolValue ? 1 : 0, base, serverKey,
		apiKey[0] == '\0' ? "(未配置，不会上传)" : "(已配置)");

	ReplyToCommand(client, "[RatingPro] 序列: #%d 起点=%s 已累计=%d/%d 张（攒满即上传并归零；断章只看双方比分回退）",
		g_iCampaignSeqId, g_sCampaignStartMap,
		g_iCampaignMaps, g_hUploadMaps.IntValue);

	ReplyToCommand(client, "[RatingPro] 上传门槛: 人数>=%d（本图参与 %d 人）",
		g_hMinPlayers.IntValue, g_iParticipantCount);

	// 胜负/比分的原始读数：判定不出来时，这一行就是唯一能分清「没读到分」还是「映射没捕获」的证据。
	{
		char scoreText[32];
		int team2Score;
		int team3Score;
		if (TryGetTeamScores(team2Score, team3Score))
		{
			Format(scoreText, sizeof(scoreText), "team2=%d team3=%d", team2Score, team3Score);
		}
		else
		{
			strcopy(scoreText, sizeof(scoreText), "未上报");
		}

		ReplyToCommand(client,
			"[RatingPro] 本图结果: 第一半场生还方=%s（当时 A=%d B=%d）地图分 A=%d B=%d 比分=%s winner_team=%d 重试=%d/%d（native %s）",
			g_iFirstHalfLogicalTeam == 0 ? "未知" : (g_iFirstHalfLogicalTeam == 1 ? "逻辑队 1" : "逻辑队 2"),
			g_iFirstHalfScoreA, g_iFirstHalfScoreB,
			g_iMapScoreA, g_iMapScoreB, scoreText, g_iMapWinnerTeam,
			g_iMapResultAttempts, MAP_RESULT_MAX_ATTEMPTS,
			HasTeamScoreNative() ? "可用" : "缺失");
	}

	ReplyToCommand(client, "[RatingPro] 快照窗口: %d 槽 待上传=%d 在途=%d 重试次数=%d 载荷长度=%d",
		g_iRawHistoryCount, g_bUploadPending ? 1 : 0, g_bUploadInFlight ? 1 : 0,
		g_iUploadAttempts, strlen(g_sUploadPayload));

	ReplyToCommand(client, "[RatingPro] 日志: sm_ratingpro_api_log=%d 文件=addons/sourcemod/logs/%s.log（0=关闭 1=失败与上传 2=全部请求；改完即时生效，无需重载）",
		g_hApiLog.IntValue, API_LOG_NAME);

	for (int target = 1; target <= MaxClients; target++)
	{
		if (!IsHumanClient(target))
		{
			continue;
		}

		char stateName[32];
		GetCacheStatusName(g_ClientInfo[target].status, stateName, sizeof(stateName));

		// 失败原因直接带出来：状态=请求失败时最想知道的就是哪一层失败了。
		char errorNote[CLIENT_API_ERROR_LENGTH + 16];
		errorNote[0] = '\0';
		if (g_sClientApiError[target][0] != '\0')
		{
			Format(errorNote, sizeof(errorNote), " 最近错误=%s", g_sClientApiError[target]);
		}

		ReplyToCommand(client, "[RatingPro] #%d %N: 状态=%s ELO=%.2f 排名=%d/%d 对局数=%d 最近平均=%.2f(%d 场)%s",
			target, target, stateName, g_ClientInfo[target].elo, g_ClientInfo[target].rank,
			g_ClientInfo[target].totalPlayers, g_ClientInfo[target].rounds,
			g_ClientInfo[target].recentAverage, g_ClientInfo[target].recentCount, errorNote);
	}

	if (args > 0 && g_sUploadPayload[0] != '\0')
	{
		ReplyToCommand(client, "[RatingPro] 载荷预览:\n%s", g_sUploadPayload);
	}

	return Plugin_Handled;
}

void GetCacheStatusName(int status, char[] buffer, int size)
{
	switch (view_as<RatingProCacheStatus>(status))
	{
		case RatingProCache_Loading:
		{
			strcopy(buffer, size, "请求中");
		}
		case RatingProCache_Ready:
		{
			strcopy(buffer, size, "已就绪");
		}
		case RatingProCache_NoRecord:
		{
			strcopy(buffer, size, "后端无记录");
		}
		case RatingProCache_Error:
		{
			strcopy(buffer, size, "请求失败");
		}
		default:
		{
			strcopy(buffer, size, "未请求");
		}
	}
}

// ------------------------------ JSON / HTTP 工具 ------------------------------

// 读不出 body 时不能只说「空响应体」：size 拿不到和 data 读不出是两种故障，
// 而两者都可能因为响应头丢了 body。这里把两层原生的真实返回值与响应头一起记下来。
void LogResponseBodyReadFailure(Handle request, bool sizeOk, int size)
{
	if (g_hApiLog == null || g_hApiLog.IntValue <= 0)
	{
		return;
	}

	char contentLength[64];
	contentLength[0] = '\0';
	bool hasContentLength = SteamWorks_GetHTTPResponseHeaderValue(request, "Content-Length",
		contentLength, sizeof(contentLength));

	char contentEncoding[64];
	contentEncoding[0] = '\0';
	bool hasContentEncoding = SteamWorks_GetHTTPResponseHeaderValue(request, "Content-Encoding",
		contentEncoding, sizeof(contentEncoding));

	char transferEncoding[64];
	transferEncoding[0] = '\0';
	bool hasTransferEncoding = SteamWorks_GetHTTPResponseHeaderValue(request, "Transfer-Encoding",
		transferEncoding, sizeof(transferEncoding));

	char server[64];
	server[0] = '\0';
	bool hasServer = SteamWorks_GetHTTPResponseHeaderValue(request, "Server", server, sizeof(server));

	char contentType[64];
	contentType[0] = '\0';
	bool hasContentType = SteamWorks_GetHTTPResponseHeaderValue(request, "Content-Type", contentType, sizeof(contentType));

	// 分两行：中文按 UTF-8 计 3 字节，单行 512 的上限很容易把后面的头截掉。
	ApiLog(LogType_Error, "[http] 响应体读取失败：GetHTTPResponseBodySize 返回=%d size=%d",
		sizeOk ? 1 : 0, size);
	ApiLog(LogType_Error, "[http] 响应头 Content-Length=%s | Content-Encoding=%s | Transfer-Encoding=%s | Server=%s | Content-Type=%s",
		hasContentLength ? contentLength : "(无此头)",
		hasContentEncoding ? contentEncoding : "(无此头)",
		hasTransferEncoding ? transferEncoding : "(无此头)",
		hasServer ? server : "(无此头)",
		hasContentType ? contentType : "(无此头)");
}

bool ReadResponseBody(Handle request, char[] buffer, int size)
{
	if (size <= 0)
	{
		return false;
	}

	buffer[0] = '\0';

	if (request == null)
	{
		return false;
	}

	int length = 0;
	bool sizeOk = SteamWorks_GetHTTPResponseBodySize(request, length);
	if (!sizeOk || length <= 0)
	{
		LogResponseBodyReadFailure(request, sizeOk, length);
		return false;
	}

	if (length >= size)
	{
		length = size - 1;
	}

	// Valve 的 GetHTTPResponseBodyData 要的是「缓冲区长度」，而部分 Steam 客户端要求它
	// 与 body 大小**完全一致**：多传 1 字节留 null 结尾会被判成缓冲不匹配，直接返回 false。
	// 以前这里传 length + 1，于是 HTTP 200、size 也读到了 526，body 却永远是空的。
	// 先按精确大小读（仓库里的 sm_translator 一直这么写）；万一某个客户端只认更大的缓冲，
	// 再退回 length + 1，并把实际生效的口径记进日志。
	buffer[0] = '\0';
	if (!SteamWorks_GetHTTPResponseBodyData(request, buffer, length))
	{
		if (!SteamWorks_GetHTTPResponseBodyData(request, buffer, length + 1))
		{
			ApiLog(LogType_Error, "[http] GetHTTPResponseBodyData 两种 bufferLen 都失败：body=%d，目标缓冲=%d",
				length, size);
			buffer[0] = '\0';
			return false;
		}

		// 客户端口径差异，不是错误，别刷 Error。
		ApiLog(LogType_Debug, "[http] GetHTTPResponseBodyData 仅在 bufferLen=%d 时成功（body=%d）",
			length + 1, length);
	}

	buffer[length] = '\0';
	return true;
}

void UrlEncode(const char[] input, char[] output, int size)
{
	if (size <= 0)
	{
		return;
	}

	char hexDigits[] = "0123456789ABCDEF";

	int out = 0;
	int length = strlen(input);
	for (int index = 0; index < length && out < size - 4; index++)
	{
		int code = input[index] & 0xFF;

		bool unreserved = (code >= 65 && code <= 90)
			|| (code >= 97 && code <= 122)
			|| (code >= 48 && code <= 57)
			|| code == 45 || code == 46 || code == 95 || code == 126;

		if (unreserved)
		{
			output[out++] = input[index];
			continue;
		}

		output[out++] = '%';
		output[out++] = hexDigits[(code >> 4) & 0x0F];
		output[out++] = hexDigits[code & 0x0F];
	}

	output[out] = '\0';
}

void JsonEscape(const char[] input, char[] output, int size)
{
	if (size <= 0)
	{
		return;
	}

	int out = 0;
	int length = strlen(input);
	for (int index = 0; index < length && out < size - 2; index++)
	{
		char c = input[index];
		if (c == '"' || c == '\\')
		{
			output[out++] = '\\';
			output[out++] = c;
			continue;
		}

		if (c == '\r' || c == '\n' || c == '\t')
		{
			output[out++] = ' ';
			continue;
		}

		output[out++] = c;
	}

	output[out] = '\0';
}

static int JsonSkipWhitespace(const char[] json, int pos)
{
	int length = strlen(json);
	while (pos < length)
	{
		char c = json[pos];
		if (c != ' ' && c != '\t' && c != '\r' && c != '\n')
		{
			break;
		}
		pos++;
	}
	return pos;
}

// pos 指向起始引号，返回闭合引号之后的下标。
static int JsonSkipString(const char[] json, int pos)
{
	int length = strlen(json);
	if (pos >= length || json[pos] != '"')
	{
		return -1;
	}

	pos++;
	while (pos < length)
	{
		char c = json[pos];
		if (c == '\\')
		{
			pos += 2;
			continue;
		}
		if (c == '"')
		{
			return pos + 1;
		}
		pos++;
	}

	return -1;
}

// 返回一个完整值（标量 / 字符串 / 对象 / 数组）之后的下标。
static int JsonSkipValue(const char[] json, int pos)
{
	int length = strlen(json);
	pos = JsonSkipWhitespace(json, pos);
	if (pos >= length)
	{
		return -1;
	}

	if (json[pos] == '"')
	{
		return JsonSkipString(json, pos);
	}

	if (json[pos] == '{' || json[pos] == '[')
	{
		int depth = 0;
		while (pos < length)
		{
			char c = json[pos];
			if (c == '"')
			{
				pos = JsonSkipString(json, pos);
				if (pos < 0)
				{
					return -1;
				}
				continue;
			}

			if (c == '{' || c == '[')
			{
				depth++;
			}
			else if (c == '}' || c == ']')
			{
				depth--;
				if (depth == 0)
				{
					return pos + 1;
				}
			}

			pos++;
		}

		return -1;
	}

	while (pos < length)
	{
		char c = json[pos];
		if (c == ',' || c == '}' || c == ']' || c == ' ' || c == '\t' || c == '\r' || c == '\n')
		{
			break;
		}
		pos++;
	}

	return pos;
}

// 把 JSON 字符串字面量反转义写入 output（pos 指向起始引号）。
static bool JsonCopyString(const char[] json, int pos, char[] output, int size)
{
	if (size <= 0)
	{
		return false;
	}

	output[0] = '\0';

	int length = strlen(json);
	if (pos >= length || json[pos] != '"')
	{
		return false;
	}

	pos++;
	int out = 0;
	while (pos < length && out < size - 1)
	{
		char c = json[pos];
		if (c == '"')
		{
			output[out] = '\0';
			return true;
		}

		if (c == '\\' && pos + 1 < length)
		{
			pos++;
			char escape = json[pos];
			if (escape == 'n')
			{
				output[out++] = '\n';
			}
			else if (escape == 'r')
			{
				output[out++] = '\r';
			}
			else if (escape == 't')
			{
				output[out++] = '\t';
			}
			else if (escape == 'b')
			{
				output[out++] = '\b';
			}
			else if (escape == 'f')
			{
				output[out++] = '\f';
			}
			else
			{
				output[out++] = escape;
			}

			pos++;
			continue;
		}

		output[out++] = c;
		pos++;
	}

	output[out] = '\0';
	return true;
}

// 在 objectPos 指向的对象里查找 key，valuePos 返回对应值的起始下标。
static bool JsonFindMember(const char[] json, int objectPos, const char[] key, int &valuePos)
{
	valuePos = -1;

	int length = strlen(json);
	int pos = JsonSkipWhitespace(json, objectPos);
	if (pos >= length || json[pos] != '{')
	{
		return false;
	}

	pos = JsonSkipWhitespace(json, pos + 1);

	while (pos < length)
	{
		if (json[pos] != '"')
		{
			return false;
		}

		char name[128];
		int keyEnd = JsonSkipString(json, pos);
		if (keyEnd < 0)
		{
			return false;
		}

		JsonCopyString(json, pos, name, sizeof(name));

		pos = JsonSkipWhitespace(json, keyEnd);
		if (pos >= length || json[pos] != ':')
		{
			return false;
		}

		pos = JsonSkipWhitespace(json, pos + 1);
		int valueEnd = JsonSkipValue(json, pos);
		if (valueEnd < 0)
		{
			return false;
		}

		if (StrEqual(name, key, false))
		{
			valuePos = pos;
			return true;
		}

		pos = JsonSkipWhitespace(json, valueEnd);
		if (pos < length && json[pos] == ',')
		{
			pos = JsonSkipWhitespace(json, pos + 1);
			continue;
		}

		break;
	}

	return false;
}

// 解析 "a.b.c" 形式的路径，valuePos 返回末级值的起始下标。
static bool JsonResolvePath(const char[] json, const char[] path, int &valuePos)
{
	valuePos = -1;

	int pos = JsonSkipWhitespace(json, 0);
	int length = strlen(path);

	char segment[128];
	int segmentLength = 0;

	for (int index = 0; index <= length; index++)
	{
		if (index < length && path[index] != '.')
		{
			if (segmentLength < sizeof(segment) - 1)
			{
				segment[segmentLength] = path[index];
				segmentLength++;
			}
			continue;
		}

		segment[segmentLength] = '\0';
		if (segmentLength == 0)
		{
			return false;
		}

		int childPos = -1;
		if (!JsonFindMember(json, pos, segment, childPos))
		{
			return false;
		}

		pos = childPos;
		segmentLength = 0;
	}

	valuePos = pos;
	return valuePos >= 0;
}

bool JsonGetValue(const char[] json, const char[] path, char[] output, int size)
{
	if (size <= 0)
	{
		return false;
	}

	output[0] = '\0';

	int pos = -1;
	if (json[0] == '\0' || !JsonResolvePath(json, path, pos))
	{
		return false;
	}

	if (json[pos] == '"')
	{
		return JsonCopyString(json, pos, output, size);
	}

	int valueEnd = JsonSkipValue(json, pos);
	if (valueEnd < 0)
	{
		return false;
	}

	int count = valueEnd - pos;
	if (count >= size)
	{
		count = size - 1;
	}

	for (int index = 0; index < count; index++)
	{
		output[index] = json[pos + index];
	}
	output[count] = '\0';

	return true;
}

bool JsonGetFloat(const char[] json, const char[] path, float &output)
{
	char buffer[64];
	if (!JsonGetValue(json, path, buffer, sizeof(buffer)))
	{
		return false;
	}

	if (buffer[0] == '\0' || StrEqual(buffer, "null", false))
	{
		return false;
	}

	output = StringToFloat(buffer);
	return true;
}

bool JsonGetInt(const char[] json, const char[] path, int &output)
{
	char buffer[64];
	if (!JsonGetValue(json, path, buffer, sizeof(buffer)))
	{
		return false;
	}

	if (buffer[0] == '\0' || StrEqual(buffer, "null", false))
	{
		return false;
	}

	output = StringToInt(buffer);
	return true;
}

bool JsonGetBool(const char[] json, const char[] path, bool &output)
{
	char buffer[16];
	if (!JsonGetValue(json, path, buffer, sizeof(buffer)))
	{
		return false;
	}

	if (StrEqual(buffer, "true", false))
	{
		output = true;
		return true;
	}

	if (StrEqual(buffer, "false", false))
	{
		output = false;
		return true;
	}

	return false;
}

int JsonGetArrayLength(const char[] json, const char[] path)
{
	int pos = -1;
	if (json[0] == '\0' || !JsonResolvePath(json, path, pos))
	{
		return 0;
	}

	int length = strlen(json);
	pos = JsonSkipWhitespace(json, pos);
	if (pos >= length || json[pos] != '[')
	{
		return 0;
	}

	pos = JsonSkipWhitespace(json, pos + 1);
	if (pos < length && json[pos] == ']')
	{
		return 0;
	}

	int count = 0;
	while (pos < length)
	{
		int valueEnd = JsonSkipValue(json, pos);
		if (valueEnd < 0)
		{
			break;
		}

		count++;

		pos = JsonSkipWhitespace(json, valueEnd);
		if (pos < length && json[pos] == ',')
		{
			pos = JsonSkipWhitespace(json, pos + 1);
			continue;
		}

		break;
	}

	return count;
}

bool JsonGetArrayElement(const char[] json, const char[] path, int index, char[] output, int size)
{
	if (size <= 0)
	{
		return false;
	}

	output[0] = '\0';

	int pos = -1;
	if (json[0] == '\0' || !JsonResolvePath(json, path, pos))
	{
		return false;
	}

	int length = strlen(json);
	pos = JsonSkipWhitespace(json, pos);
	if (pos >= length || json[pos] != '[')
	{
		return false;
	}

	pos = JsonSkipWhitespace(json, pos + 1);
	if (pos < length && json[pos] == ']')
	{
		return false;
	}

	int current = 0;
	while (pos < length)
	{
		int valueEnd = JsonSkipValue(json, pos);
		if (valueEnd < 0)
		{
			return false;
		}

		if (current == index)
		{
			int count = valueEnd - pos;
			if (count >= size)
			{
				count = size - 1;
			}

			for (int copyIndex = 0; copyIndex < count; copyIndex++)
			{
				output[copyIndex] = json[pos + copyIndex];
			}
			output[count] = '\0';

			return true;
		}

		current++;

		pos = JsonSkipWhitespace(json, valueEnd);
		if (pos < length && json[pos] == ',')
		{
			pos = JsonSkipWhitespace(json, pos + 1);
			continue;
		}

		break;
	}

	return false;
}

