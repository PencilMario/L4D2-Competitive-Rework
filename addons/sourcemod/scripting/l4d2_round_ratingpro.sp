#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>
#include <l4d2_skill_detect>
#include <logger>
#include <SteamWorks>
#include <l4d2_round_ratingpro>

#define PLUGIN_VERSION "1.1.0"

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

// left4dhooks 原生函数：读取战役累计比分，仅用于「双方分数不减」的章节连续性判定。
// 未安装 left4dhooks 时自动降级为只按地图名 / 章节号判定。
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
	author = "Codex",
	description = "基于比赛生还者与特感表现评估回合 RatingPro 评分。",
	version = PLUGIN_VERSION,
	url = ""
};

Logger g_RatingLogger;

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

// 参与者记录按 SteamID（Steam2）归档：退服后数据仍保留，直到本图结算生成新快照为止。
char g_sParticipantAuth[MAX_PARTICIPANTS][64];
char g_sParticipantName[MAX_PARTICIPANTS][MAX_NAME_LENGTH];
int g_iParticipantTeam[MAX_PARTICIPANTS];
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
ConVar g_hAutoRefresh;
ConVar g_hScoreGuard;

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

// HTTP 回调是主线程序列执行的，响应体共用一块静态缓冲即可，避免频繁堆分配。
char g_sHttpResponse[HTTP_RESPONSE_SIZE];

// ============================ 后端接入：战役（同一章节序列）跟踪 ============================
// 一次战役 = 同一 campaign 前缀、章节号连续递增、双方比分不减的一组地图。
// 中途换图导致序列中断时，只重置上传计数（本段不完整对局不上传），评分窗口保持原始跨图口径。
char g_sCampaignKey[MAP_NAME_LENGTH];
char g_sCampaignStartMap[MAP_NAME_LENGTH];
char g_sRawHistoryCampaign[RAW_HISTORY_SLOTS][MAP_NAME_LENGTH];
int g_iCampaignMaps;
int g_iCampaignLastChapter;
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
	return participant;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnded = false;
	for (int client = 1; client <= MaxClients; client++)
	{
		g_bBiled[client] = false;
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

	for (int participant = 0; participant < MAX_PARTICIPANTS; participant++)
	{
		g_sParticipantAuth[participant][0] = '\0';
		g_sParticipantName[participant][0] = '\0';
		g_iParticipantTeam[participant] = 0;

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
	strcopy(g_sRawHistoryCampaign[slot], sizeof(g_sRawHistoryCampaign[]), g_sCampaignKey);
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
		entry.team = g_iParticipantTeam[participant];

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
// 上传口径：同一战役里每攒满 N 张图（默认 4）上传一次，上传后计数器归零重新累计。
// 战役由「campaign 前缀相同 + 章节号连续递增 + 双方比分不减」三点共同界定；任一条件被破坏
// （中途换图、选图跳过章节、比分被重置）都视为这一段没能打成完整对局：只重置上传计数，
// 不产生任何上传；评分窗口（RAW_HISTORY_SLOTS）保持原始跨图滚动口径，不跟着清空。
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
	g_hAutoRefresh = CreateConVar("sm_ratingpro_auto_refresh", "1",
		"玩家认证完成时自动请求并缓存 ELO 与最近 5 场平均 RatingPro。", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hScoreGuard = CreateConVar("sm_ratingpro_score_guard", "1",
		"用「双方战役比分不减」辅助判定章节连续性（依赖 left4dhooks）；关掉后只按地图名与章节号判定。",
		FCVAR_NONE, true, 0.0, true, 1.0);
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
	g_iCampaignLastChapter = 0;
	g_iCampaignLastScoreA = 0;
	g_iCampaignLastScoreB = 0;
	g_sCampaignKey[0] = '\0';
	g_sCampaignStartMap[0] = '\0';
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

	Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);
	if (request == null)
	{
		return;
	}

	g_bEloRequestInFlight[client] = true;
	g_ClientInfo[client].status = view_as<int>(RatingProCache_Loading);

	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, 10);
	SteamWorks_SetHTTPRequestContextValue(request, client, g_iClientToken[client]);
	SteamWorks_SetHTTPCallbacks(request, OnClientEloResponse);

	if (!SteamWorks_SendHTTPRequest(request))
	{
		g_bEloRequestInFlight[client] = false;
		g_ClientInfo[client].status = view_as<int>(RatingProCache_Error);
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

	Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);
	if (request == null)
	{
		return;
	}

	g_bRatingRequestInFlight[client] = true;

	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, 10);
	SteamWorks_SetHTTPRequestContextValue(request, client, g_iClientToken[client]);
	SteamWorks_SetHTTPCallbacks(request, OnClientRatingResponse);

	if (!SteamWorks_SendHTTPRequest(request))
	{
		g_bRatingRequestInFlight[client] = false;
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
		return;
	}

	g_bEloRequestInFlight[client] = false;

	if (!transportOk)
	{
		g_ClientInfo[client].status = view_as<int>(RatingProCache_Error);
		FireClientDataLoaded(client, RatingProCache_Error);
		return;
	}

	if (status == 404)
	{
		g_ClientInfo[client].loaded = false;
		g_ClientInfo[client].status = view_as<int>(RatingProCache_NoRecord);
		FireClientDataLoaded(client, RatingProCache_NoRecord);
		return;
	}

	if (status != 200 || !hasBody)
	{
		g_ClientInfo[client].status = view_as<int>(RatingProCache_Error);
		FireClientDataLoaded(client, RatingProCache_Error);
		return;
	}

	if (!ParseEloResponse(client, g_sHttpResponse))
	{
		g_ClientInfo[client].status = view_as<int>(RatingProCache_Error);
		FireClientDataLoaded(client, RatingProCache_Error);
		return;
	}

	g_ClientInfo[client].loaded = true;
	g_ClientInfo[client].status = view_as<int>(RatingProCache_Ready);
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
		return;
	}

	g_bRatingRequestInFlight[client] = false;

	if (!transportOk || status != 200 || !hasBody)
	{
		g_ClientInfo[client].hasRecent = false;
		return;
	}

	ParseRatingAverageResponse(client, g_sHttpResponse);
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

// 解析地图名中的战役前缀与章节号：c1m3_mall → key="c1", chapter=3。
// 非标准命名（工坊自定义图）返回 false，由调用方退化为「整张图名即战役键」。
bool ParseCampaignProgress(const char[] map, char[] key, int keySize, int &chapter)
{
	chapter = 0;
	if (keySize <= 0)
	{
		return false;
	}

	key[0] = '\0';

	int length = strlen(map);
	for (int index = 1; index < length - 1; index++)
	{
		if (map[index] != 'm' && map[index] != 'M')
		{
			continue;
		}

		int nextCode = map[index + 1];
		if (nextCode < 48 || nextCode > 57)
		{
			continue;
		}

		int prevCode = map[index - 1];
		bool prevOk = (prevCode >= 48 && prevCode <= 57)
			|| prevCode == '_'
			|| (prevCode >= 97 && prevCode <= 122)
			|| (prevCode >= 65 && prevCode <= 90);
		if (!prevOk)
		{
			continue;
		}

		int value = 0;
		int cursor = index + 1;
		while (cursor < length)
		{
			int digitCode = map[cursor];
			if (digitCode < 48 || digitCode > 57)
			{
				break;
			}
			value = value * 10 + (digitCode - 48);
			cursor++;
		}

		if (value <= 0)
		{
			continue;
		}

		int prefixLength = index;
		if (prefixLength >= keySize)
		{
			prefixLength = keySize - 1;
		}

		for (int copyIndex = 0; copyIndex < prefixLength; copyIndex++)
		{
			key[copyIndex] = map[copyIndex];
		}
		key[prefixLength] = '\0';

		chapter = value;
		return true;
	}

	return false;
}

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

bool IsCampaignBroken(const char[] key, int chapter, bool hasScores, int scoreA, int scoreB)
{
	// 换了战役前缀：一定是新的章节序列。
	if (!StrEqual(key, g_sCampaignKey, false))
	{
		return true;
	}

	// 章节号必须严格 +1；跳章、回退或原地重开都说明这段序列断了。
	if (chapter > 0 && g_iCampaignLastChapter > 0 && chapter != g_iCampaignLastChapter + 1)
	{
		return true;
	}

	// 双方比分必须单调不减：任意一方回退说明战役被重新开始过。
	// 这一条依赖引擎的战役累计分，个别环境不准时可用 sm_ratingpro_score_guard 0 关掉。
	if (hasScores && g_bCampaignHasScoreBaseline && g_hScoreGuard.BoolValue)
	{
		if (scoreA < g_iCampaignLastScoreA || scoreB < g_iCampaignLastScoreB)
		{
			return true;
		}
	}

	return false;
}

// 章节中断只重置「上传计数」，评分窗口（RAW_HISTORY_SLOTS）保持原始跨图滚动口径，不跟着清空。
void ResetCampaignProgress()
{
	g_iCampaignMaps = 0;
	g_bCampaignHasScoreBaseline = false;
	g_iCampaignLastChapter = 0;
	g_iCampaignLastScoreA = 0;
	g_iCampaignLastScoreB = 0;
	g_sCampaignKey[0] = '\0';
	g_sCampaignStartMap[0] = '\0';
}

// 每次正式结算前调用：判定本图是否延续同一战役；断了就重置上传计数，评分窗口原样保留。
void UpdateCampaignProgress()
{
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));

	char key[MAP_NAME_LENGTH];
	int chapter;
	if (!ParseCampaignProgress(map, key, sizeof(key), chapter))
	{
		strcopy(key, sizeof(key), map);
		chapter = 0;
	}

	int scoreA;
	int scoreB;
	bool hasScores = TryGetCampaignScores(scoreA, scoreB);

	if (g_iCampaignMaps > 0 && IsCampaignBroken(key, chapter, hasScores, scoreA, scoreB))
	{
		LogMessage("[RatingPro] 章节中断：%s → %s（上一段 campaign=%s 第 %d 章，已结算 %d 张图），本段不完整对局不上传，仅重置上传计数。",
			g_sCampaignStartMap, map, g_sCampaignKey, g_iCampaignLastChapter, g_iCampaignMaps);

		ResetCampaignProgress();
	}

	if (g_iCampaignMaps == 0)
	{
		strcopy(g_sCampaignKey, sizeof(g_sCampaignKey), key);
		strcopy(g_sCampaignStartMap, sizeof(g_sCampaignStartMap), map);
	}

	g_iCampaignLastChapter = chapter;
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

	if (g_iParticipantCount <= 0)
	{
		return;
	}

	// 上一次上传还没结清（在途 / 等重试）：这一段继续攒着，等下个结算点再传，
	// 免得把仍在重试的载荷覆盖掉。
	if (g_bUploadInFlight || g_bUploadPending)
	{
		return;
	}

	int settledMaps = g_iCampaignMaps;

	// 评分窗口沿用原始插件的跨图滚动口径，因此可能仍含上一段（未完成、已不参与上传）的图。
	// 这里只记录一次覆盖情况，不阻断上传：上传与否只看本段战役累计了多少张图。
	int foreignSlots = 0;
	for (int slot = 0; slot < g_iRawHistoryCount; slot++)
	{
		if (g_sRawHistoryCampaign[slot][0] != '\0'
			&& !StrEqual(g_sRawHistoryCampaign[slot], g_sCampaignKey, false))
		{
			foreignSlots++;
		}
	}

	if (foreignSlots > 0)
	{
		LogMessage("[RatingPro] 评分窗口含 %d 个上一段战役的槽位（%d/%d 张图属于当前战役 %s），按原始跨图口径保留。",
			foreignSlots, g_iRawHistoryCount - foreignSlots, g_iRawHistoryCount, g_sCampaignKey);
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
		ScheduleUploadRetry();
		return;
	}

	char header[320];
	Format(header, sizeof(header), "Bearer %s", apiKey);

	g_iUploadToken++;
	g_bUploadInFlight = true;

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

	ReplyToCommand(client, "[RatingPro] 战役: key=%s 起始图=%s 已累计=%d/%d 张（攒满即上传并归零）",
		g_sCampaignKey, g_sCampaignStartMap, g_iCampaignMaps, g_hUploadMaps.IntValue);

	ReplyToCommand(client, "[RatingPro] 快照窗口: %d 槽 待上传=%d 在途=%d 重试次数=%d 载荷长度=%d",
		g_iRawHistoryCount, g_bUploadPending ? 1 : 0, g_bUploadInFlight ? 1 : 0,
		g_iUploadAttempts, strlen(g_sUploadPayload));

	for (int target = 1; target <= MaxClients; target++)
	{
		if (!IsHumanClient(target))
		{
			continue;
		}

		char stateName[32];
		GetCacheStatusName(g_ClientInfo[target].status, stateName, sizeof(stateName));
		ReplyToCommand(client, "[RatingPro] #%d %N: 状态=%s ELO=%.2f 排名=%d/%d 对局数=%d 最近平均=%.2f(%d 场)",
			target, target, stateName, g_ClientInfo[target].elo, g_ClientInfo[target].rank,
			g_ClientInfo[target].totalPlayers, g_ClientInfo[target].rounds,
			g_ClientInfo[target].recentAverage, g_ClientInfo[target].recentCount);
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

bool ReadResponseBody(Handle request, char[] buffer, int size)
{
	if (size <= 0)
	{
		return false;
	}

	buffer[0] = '\0';

	int length = 0;
	if (request == null || !SteamWorks_GetHTTPResponseBodySize(request, length) || length <= 0)
	{
		return false;
	}

	if (length >= size)
	{
		length = size - 1;
	}

	if (!SteamWorks_GetHTTPResponseBodyData(request, buffer, length + 1))
	{
		buffer[0] = '\0';
		return false;
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

