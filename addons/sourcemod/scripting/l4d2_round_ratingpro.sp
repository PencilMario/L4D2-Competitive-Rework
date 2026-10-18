#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>
#include <l4d2_skill_detect>
#include <logger>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_TANK 8

#define RATING_EXPONENT 0.75
#define TANK_NO_DATA_SCORE 4.6
#define RAW_HISTORY_SLOTS 4

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

StringMap g_hLastRatingSnapshot;
StringMap g_hLastRatingSnapshotNames;
int g_iSnapshotRoundId;
bool g_bHasSnapshot;
char g_sSnapshotMap[64];
char g_sSnapshotTime[64];
float g_fLastQueryTime[MAXPLAYERS + 1];

bool g_bRoundEnded;
bool g_bSeen[MAXPLAYERS + 1];
char g_sName[MAXPLAYERS + 1][MAX_NAME_LENGTH];

int g_iSiDamage[MAXPLAYERS + 1];
int g_iCiKilled[MAXPLAYERS + 1];
int g_iTankDamage[MAXPLAYERS + 1];
int g_iDmgTaken[MAXPLAYERS + 1];
int g_iIncaps[MAXPLAYERS + 1];
int g_iDied[MAXPLAYERS + 1];
int g_iFfGiven[MAXPLAYERS + 1];

int g_iSiDamageTankup[MAXPLAYERS + 1];
int g_iSiKilledTankup[MAXPLAYERS + 1];
int g_iSkeets[MAXPLAYERS + 1];
int g_iLevels[MAXPLAYERS + 1];
int g_iPops[MAXPLAYERS + 1];
int g_iTongueCuts[MAXPLAYERS + 1];
int g_iCrowns[MAXPLAYERS + 1];

int g_iInfDmgTotal[MAXPLAYERS + 1];
int g_iInfBooms[MAXPLAYERS + 1];
int g_iInfDeathCharges[MAXPLAYERS + 1];

int g_iTankDmgUpright[MAXPLAYERS + 1];
int g_iTankPunch[MAXPLAYERS + 1];
int g_iTankRock[MAXPLAYERS + 1];
int g_iTankHittable[MAXPLAYERS + 1];
int g_iTankIncap[MAXPLAYERS + 1];
int g_iTankDeath[MAXPLAYERS + 1];
bool g_bBecameTank[MAXPLAYERS + 1];

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
	}

	g_hLastRatingSnapshot = new StringMap();
	g_hLastRatingSnapshotNames = new StringMap();
	g_iSnapshotRoundId = 0;
	g_bHasSnapshot = false;
	g_sSnapshotMap[0] = '\0';
	g_sSnapshotTime[0] = '\0';

	g_hEnabled = CreateConVar("sm_round_ratingpro_enabled", "1", "启用回合结束时 RatingPro 最佳表现播报与查询功能。", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hDelay = CreateConVar("sm_round_ratingpro_delay", "3.0", "回合结束后延迟公布最佳 RatingPro 玩家的秒数。", FCVAR_NONE, true, 0.0, true, 15.0);
	g_hMinRaw = CreateConVar("sm_round_ratingpro_min_raw", "1.0", "公布最佳表现所需的最低加权原始分阈值。", FCVAR_NONE, true, 0.0, true, 10.0);
	CreateConVar("sm_round_ratingpro_version", PLUGIN_VERSION, "L4D2 回合 RatingPro 插件版本。", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	RegConsoleCmd("sm_ratingpro", Command_RatingPro, "查询玩家 RatingPro 评分数据快照。");
	RegConsoleCmd("sm_rating", Command_RatingPro, "查询玩家 RatingPro 评分数据快照（别名）。");
	RegConsoleCmd("sm_rt", Command_RatingPro, "查询玩家 RatingPro 评分数据快照（别名）。");

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
		g_bSeen[client] = false;
		g_fLastQueryTime[client] = 0.0;
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnded = false;
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
		RememberClient(victim);
		if (GetClientTeam(victim) == TEAM_SURVIVOR)
		{
			if (!IsSurvivorIncapacitated(victim))
			{
				g_iDmgTaken[victim] += damage;
			}
		}
	}

	if (!IsHumanClient(attacker))
	{
		return;
	}

	RememberClient(attacker);

	int attackerTeam = GetClientTeam(attacker);
	int victimTeam = IsHumanClient(victim) ? GetClientTeam(victim) : 0;

	if (attackerTeam == TEAM_SURVIVOR)
	{
		if (victimTeam == TEAM_INFECTED)
		{
			int zombieClass = GetZombieClass(victim);
			if (zombieClass == ZC_TANK)
			{
				g_iTankDamage[attacker] += damage;
			}
			else
			{
				g_iSiDamage[attacker] += damage;
				if (IsTankInPlay())
				{
					g_iSiDamageTankup[attacker] += damage;
				}
			}
		}
		else if (victimTeam == TEAM_SURVIVOR && attacker != victim)
		{
			g_iFfGiven[attacker] += damage;
		}
	}
	else if (attackerTeam == TEAM_INFECTED && victimTeam == TEAM_SURVIVOR)
	{
		int zombieClass = GetZombieClass(attacker);
		if (zombieClass == ZC_TANK)
		{
			TrackTankHit(attacker, victim, damage, event);
		}
		else
		{
			if (!IsSurvivorIncapacitated(victim))
			{
				g_iInfDmgTotal[attacker] += damage;
			}
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
	if (!IsHumanClient(attacker) || GetClientTeam(attacker) != TEAM_SURVIVOR)
	{
		return;
	}

	RememberClient(attacker);
	g_iCiKilled[attacker]++;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_hEnabled.BoolValue || g_bRoundEnded)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if (IsHumanClient(victim))
	{
		RememberClient(victim);
		if (GetClientTeam(victim) == TEAM_SURVIVOR)
		{
			g_iDied[victim]++;
		}
	}

	if (IsHumanClient(attacker))
	{
		RememberClient(attacker);
		if (GetClientTeam(attacker) == TEAM_SURVIVOR && IsHumanClient(victim) && GetClientTeam(victim) == TEAM_INFECTED && GetZombieClass(victim) != ZC_TANK && IsTankInPlay())
		{
			g_iSiKilledTankup[attacker]++;
		}
		else if (GetClientTeam(attacker) == TEAM_INFECTED && GetZombieClass(attacker) == ZC_TANK && IsHumanClient(victim) && GetClientTeam(victim) == TEAM_SURVIVOR)
		{
			MarkClientAsTank(attacker);
			g_iTankDeath[attacker]++;
		}
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

	if (IsHumanClient(victim) && GetClientTeam(victim) == TEAM_SURVIVOR)
	{
		RememberClient(victim);
		g_iIncaps[victim]++;
	}

	if (IsHumanClient(attacker) && GetClientTeam(attacker) == TEAM_INFECTED && GetZombieClass(attacker) == ZC_TANK)
	{
		MarkClientAsTank(attacker);
		g_iTankIncap[attacker]++;
	}
}

void MarkClientAsTank(int client)
{
	if (!IsHumanClient(client))
	{
		return;
	}

	RememberClient(client);
	g_bBecameTank[client] = true;
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
	if (!g_hEnabled.BoolValue || g_bRoundEnded)
	{
		return;
	}

	int player = GetClientOfUserId(event.GetInt("player"));
	if (IsHumanClient(player) && GetClientTeam(player) == TEAM_INFECTED && GetZombieClass(player) == ZC_TANK)
	{
		MarkClientAsTank(player);
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_hEnabled.BoolValue || g_bRoundEnded)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
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

public void OnBoomerVomitLanded(int boomer, int amount)
{
	if (amount <= 0 || !IsHumanClient(boomer))
	{
		return;
	}

	RememberClient(boomer);
	g_iInfBooms[boomer] += amount;
}

public void OnDeathCharge(int charger, int survivor, float height, float distance, bool wasCarried)
{
	if (!IsHumanClient(charger))
	{
		return;
	}

	RememberClient(charger);
	g_iInfDeathCharges[charger]++;
}

public void OnTankRockEaten(int tank, int survivor)
{
	if (!IsHumanClient(tank))
	{
		return;
	}

	RememberClient(tank);
	g_iTankRock[tank]++;
}

public Action Timer_PrintBestRating(Handle timer)
{
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
		CPrintToChatAll("{blue}[{green}RatingPro{blue}]{default} 本章节没有足够数据生成最佳表现。");
		PrintAllClientRatingDetailsNoData();
		PrintAllClientRatingDetailsToConsoleNoData();
		PromptRatingQuery();
		return Plugin_Stop;
	}

	SaveRatingSnapshot(true, outputMin, outputMax, defenseMin, defenseMax, focusMin, focusMax, infectorMin, infectorMax, tankMin, tankMax);
	RecordRatingSettlement();

	int bestClient = 0;
	float bestRating = 0.0;
	float bestRaw = 0.0;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsEligibleForRating(client))
		{
			continue;
		}

		float output = NormalizeRaw(GetHistoricalOutputRaw(client), outputMin, outputMax);
		float defense = NormalizeRaw(GetHistoricalDefenseRaw(client), defenseMin, defenseMax);
		float focus = NormalizeRaw(GetHistoricalFocusRaw(client), focusMin, focusMax);
		float infector = NormalizeRaw(GetHistoricalInfectorRaw(client), infectorMin, infectorMax);
		float tank = NormalizeTankRaw(GetEffectiveTankRaw(client), tankMin, tankMax);
		float raw = GetWeightedRaw(output, defense, focus, infector, tank);
		float rating = Pow(raw / 10.0, RATING_EXPONENT) * 10.0;

		if (bestClient == 0 || rating > bestRating)
		{
			bestClient = client;
			bestRating = rating;
			bestRaw = raw;
		}
	}

	if (bestClient == 0 || bestRaw < g_hMinRaw.FloatValue)
	{
		CPrintToChatAll("{blue}[{green}RatingPro{blue}]{default} 本章节没有足够数据生成最佳表现。");
		PrintAllClientRatingDetails(outputMin, outputMax, defenseMin, defenseMax, focusMin, focusMax, infectorMin, infectorMax, tankMin, tankMax);
		PrintAllClientRatingDetailsToConsole(outputMin, outputMax, defenseMin, defenseMax, focusMin, focusMax, infectorMin, infectorMax, tankMin, tankMax);
		PromptRatingQuery();
		return Plugin_Stop;
	}

	char name[MAX_NAME_LENGTH];
	GetBestClientName(bestClient, name, sizeof(name));
	CPrintToChatAll("{blue}[{green}RatingPro{blue}]{default} 章节最佳: {olive}%s{default} rating {green}%.1f",
		name, bestRating);
	PrintAllClientRatingDetails(outputMin, outputMax, defenseMin, defenseMax, focusMin, focusMax, infectorMin, infectorMax, tankMin, tankMax);
	PrintAllClientRatingDetailsToConsole(outputMin, outputMax, defenseMin, defenseMax, focusMin, focusMax, infectorMin, infectorMax, tankMin, tankMax);
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

void PrintAllClientRatingDetails(float outputMin, float outputMax, float defenseMin, float defenseMax, float focusMin, float focusMax, float infectorMin, float infectorMax, float tankMin, float tankMax)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanClient(client))
		{
			continue;
		}

		if (!IsEligibleForRating(client))
		{
			CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 本章节没有足够数据生成你的 RatingPro。");
			continue;
		}

		float output = NormalizeRaw(GetHistoricalOutputRaw(client), outputMin, outputMax);
		float defense = NormalizeRaw(GetHistoricalDefenseRaw(client), defenseMin, defenseMax);
		float focus = NormalizeRaw(GetHistoricalFocusRaw(client), focusMin, focusMax);
		float infector = NormalizeRaw(GetHistoricalInfectorRaw(client), infectorMin, infectorMax);
		float tank = NormalizeTankRaw(GetEffectiveTankRaw(client), tankMin, tankMax);
		float raw = GetWeightedRaw(output, defense, focus, infector, tank);
		float rating = Pow(raw / 10.0, RATING_EXPONENT) * 10.0;

		CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 你的评分 {green}%.1f{default} 综合 {olive}%.1f{default} | 输出 %.1f 防守 %.1f 关键操作 %.1f 特感进攻 %.1f Tank表现 %.1f",
			rating, raw, output, defense, focus, infector, tank);
	}
}

void PrintAllClientRatingDetailsToConsoleNoData()
{
	PrintToServer("[RatingPro] No enough round data to generate RatingPro details.");

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanClient(client))
		{
			continue;
		}

		char name[MAX_NAME_LENGTH];
		GetBestClientName(client, name, sizeof(name));
		PrintToServer("[RatingPro] #%d %s team=%d: no enough RatingPro data.", client, name, GetClientTeam(client));
	}
}

void PrintAllClientRatingDetailsToConsole(float outputMin, float outputMax, float defenseMin, float defenseMax, float focusMin, float focusMax, float infectorMin, float infectorMax, float tankMin, float tankMax)
{
	PrintToServer("[RatingPro] Round player details:");

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanClient(client))
		{
			continue;
		}

		char name[MAX_NAME_LENGTH];
		GetBestClientName(client, name, sizeof(name));

		if (!IsEligibleForRating(client))
		{
			PrintToServer("[RatingPro] #%d %s team=%d: no enough RatingPro data.", client, name, GetClientTeam(client));
			continue;
		}

		float outputRaw = GetHistoricalOutputRaw(client);
		float defenseRaw = GetHistoricalDefenseRaw(client);
		float focusRaw = GetHistoricalFocusRaw(client);
		float infectorRaw = GetHistoricalInfectorRaw(client);
		float tankRaw = GetEffectiveTankRaw(client);
		float output = NormalizeRaw(outputRaw, outputMin, outputMax);
		float defense = NormalizeRaw(defenseRaw, defenseMin, defenseMax);
		float focus = NormalizeRaw(focusRaw, focusMin, focusMax);
		float infector = NormalizeRaw(infectorRaw, infectorMin, infectorMax);
		float tank = NormalizeTankRaw(tankRaw, tankMin, tankMax);
		float raw = GetWeightedRaw(output, defense, focus, infector, tank);
		float rating = Pow(raw / 10.0, RATING_EXPONENT) * 10.0;

		PrintToServer("[RatingPro] #%d %s team=%d rating=%.1f raw=%.1f normalized(output=%.1f defense=%.1f focus=%.1f infector=%.1f tank=%.1f)",
			client, name, GetClientTeam(client), rating, raw, output, defense, focus, infector, tank);
		PrintToServer("[RatingPro] #%d %s raw(output=%.1f defense=%.1f focus=%.1f infector=%.1f tank=%.1f)",
			client, name, outputRaw, defenseRaw, focusRaw, infectorRaw, tankRaw);
		PrintToServer("[RatingPro] #%d %s survivor(siDmg=%d ciKill=%d tankDmg=%d dmgTaken=%d incaps=%d deaths=%d ff=%d tankupDmg=%d tankupKill=%d skeet=%d level=%d pop=%d tongueCut=%d crown=%d)",
			client, name, g_iSiDamage[client], g_iCiKilled[client], g_iTankDamage[client], g_iDmgTaken[client], g_iIncaps[client], g_iDied[client], g_iFfGiven[client], g_iSiDamageTankup[client], g_iSiKilledTankup[client], g_iSkeets[client], g_iLevels[client], g_iPops[client], g_iTongueCuts[client], g_iCrowns[client]);

		int tankDmgUpright = g_iTankDmgUpright[client];
		int tankPunch = g_iTankPunch[client];
		int tankRock = g_iTankRock[client];
		int tankHittable = g_iTankHittable[client];
		int tankIncap = g_iTankIncap[client];
		int tankDeath = g_iTankDeath[client];
		if (GetTankRaw(client) <= 0.0 && tankRaw > 0.0 && g_hLastTankRaw != null)
		{
			char auth[64];
			if (GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true))
			{
				TankHistoryEntry histTank;
				if (g_hLastTankRaw.GetArray(auth, histTank, sizeof(histTank)))
				{
					tankDmgUpright = histTank.tankDmgUpright;
					tankPunch = histTank.punch;
					tankRock = histTank.rock;
					tankHittable = histTank.hittable;
					tankIncap = histTank.incap;
					tankDeath = histTank.death;
				}
			}
		}
		PrintToServer("[RatingPro] #%d %s infected(dmg=%d booms=%d deathCharges=%d tankDmgUpright=%d punch=%d rock=%d hittable=%d incap=%d death=%d)",
			client, name, g_iInfDmgTotal[client], g_iInfBooms[client], g_iInfDeathCharges[client], tankDmgUpright, tankPunch, tankRock, tankHittable, tankIncap, tankDeath);
	}
}

void ResetRoundStats()
{
	g_bRoundEnded = false;

	for (int client = 1; client <= MaxClients; client++)
	{
		g_bSeen[client] = false;
		g_sName[client][0] = '\0';

		g_iSiDamage[client] = 0;
		g_iCiKilled[client] = 0;
		g_iTankDamage[client] = 0;
		g_iDmgTaken[client] = 0;
		g_iIncaps[client] = 0;
		g_iDied[client] = 0;
		g_iFfGiven[client] = 0;

		g_iSiDamageTankup[client] = 0;
		g_iSiKilledTankup[client] = 0;
		g_iSkeets[client] = 0;
		g_iLevels[client] = 0;
		g_iPops[client] = 0;
		g_iTongueCuts[client] = 0;
		g_iCrowns[client] = 0;

		g_iInfDmgTotal[client] = 0;
		g_iInfBooms[client] = 0;
		g_iInfDeathCharges[client] = 0;

		g_iTankDmgUpright[client] = 0;
		g_iTankPunch[client] = 0;
		g_iTankRock[client] = 0;
		g_iTankHittable[client] = 0;
		g_iTankIncap[client] = 0;
		g_iTankDeath[client] = 0;
		g_bBecameTank[client] = false;
	}
}

void TrackTankHit(int tank, int survivor, int damage, Event event)
{
	RememberClient(tank);
	MarkClientAsTank(tank);

	if (!IsSurvivorIncapacitated(survivor))
	{
		g_iInfDmgTotal[tank] += damage;
		g_iTankDmgUpright[tank] += damage;
	}

	char weapon[64];
	event.GetString("weapon", weapon, sizeof(weapon));

	if (StrContains(weapon, "tank_claw", false) != -1 || StrEqual(weapon, "tank", false))
	{
		g_iTankPunch[tank]++;
	}
	else if (StrContains(weapon, "rock", false) != -1)
	{
		g_iTankRock[tank]++;
	}
	else if (StrContains(weapon, "prop", false) != -1 || StrContains(weapon, "hittable", false) != -1 || StrContains(weapon, "physics", false) != -1)
	{
		g_iTankHittable[tank]++;
	}
}

void AddFocusCounter(int client, int counters[MAXPLAYERS + 1])
{
	if (!IsHumanClient(client))
	{
		return;
	}

	RememberClient(client);
	counters[client]++;
}

void RememberClient(int client)
{
	if (!IsHumanClient(client))
	{
		return;
	}

	g_bSeen[client] = true;
	GetClientName(client, g_sName[client], sizeof(g_sName[]));
}

bool IsEligibleForRating(int client)
{
	if (!g_bSeen[client] || !IsHumanClient(client))
	{
		return false;
	}

	return HasAnyRawSignal(client);
}

bool HasAnyRawSignal(int client)
{
	return g_iSiDamage[client] > 0
		|| g_iCiKilled[client] > 0
		|| g_iTankDamage[client] > 0
		|| g_iDmgTaken[client] > 0
		|| g_iIncaps[client] > 0
		|| g_iDied[client] > 0
		|| g_iFfGiven[client] > 0
		|| g_iSiDamageTankup[client] > 0
		|| g_iSiKilledTankup[client] > 0
		|| g_iSkeets[client] > 0
		|| g_iLevels[client] > 0
		|| g_iPops[client] > 0
		|| g_iTongueCuts[client] > 0
		|| g_iCrowns[client] > 0
		|| g_iInfDmgTotal[client] > 0
		|| g_iInfBooms[client] > 0
		|| g_iInfDeathCharges[client] > 0
		|| g_iTankDmgUpright[client] > 0
		|| g_iTankPunch[client] > 0
		|| g_iTankRock[client] > 0
		|| g_iTankHittable[client] > 0
		|| g_iTankIncap[client] > 0
		|| g_iTankDeath[client] > 0
		|| g_bBecameTank[client];
}

float GetOutputRaw(int client)
{
	return float(g_iSiDamage[client] + g_iTankDamage[client] + g_iCiKilled[client] * 10);
}

float GetDefenseRaw(int client)
{
	return -float(g_iDmgTaken[client] + g_iIncaps[client] * 350 + g_iDied[client] * 80 + g_iFfGiven[client] * 40);
}

float GetFocusRaw(int client)
{
	return float(g_iSiDamageTankup[client]) * 0.004
		+ float(g_iSiKilledTankup[client]) * 0.25
		+ float(g_iSkeets[client]) * 2.0
		+ float(g_iLevels[client]) * 2.0
		+ float(g_iPops[client]) * 1.5
		+ float(g_iTongueCuts[client]) * 1.0
		+ float(g_iCrowns[client]) * 2.0;
}

float GetInfectorRaw(int client)
{
	return float(g_iInfDmgTotal[client] + g_iInfBooms[client] * 8 + g_iInfDeathCharges[client] * 25);
}

void SaveRoundRawHistory()
{
	int slot = g_iRawHistoryNextSlot;
	g_hRawHistory[slot].Clear();
	g_hRawActionHistory[slot].Clear();
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanClient(client))
		{
			continue;
		}

		char auth[64];
		if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true))
		{
			continue;
		}

		float values[4];
		values[0] = GetOutputRaw(client);
		values[1] = GetDefenseRaw(client);
		values[2] = GetFocusRaw(client);
		values[3] = GetInfectorRaw(client);
		g_hRawHistory[slot].SetArray(auth, values, sizeof(values));

		RawHistoryActionEntry entry;
		entry.raw[0] = values[0];
		entry.raw[1] = values[1];
		entry.raw[2] = values[2];
		entry.raw[3] = values[3];

		entry.siDmg = g_iSiDamage[client];
		entry.ciKill = g_iCiKilled[client];
		entry.tankDmg = g_iTankDamage[client];
		entry.dmgTaken = g_iDmgTaken[client];
		entry.incaps = g_iIncaps[client];
		entry.deaths = g_iDied[client];
		entry.ff = g_iFfGiven[client];
		entry.tankupDmg = g_iSiDamageTankup[client];
		entry.tankupKill = g_iSiKilledTankup[client];
		entry.skeet = g_iSkeets[client];
		entry.level = g_iLevels[client];
		entry.pop = g_iPops[client];
		entry.tongueCut = g_iTongueCuts[client];
		entry.crown = g_iCrowns[client];

		entry.dmg = g_iInfDmgTotal[client];
		entry.booms = g_iInfBooms[client];
		entry.deathCharges = g_iInfDeathCharges[client];

		g_hRawActionHistory[slot].SetArray(auth, entry, sizeof(entry));
	}

	g_iRawHistoryNextSlot = (slot + 1) % RAW_HISTORY_SLOTS;
	if (g_iRawHistoryCount < RAW_HISTORY_SLOTS)
	{
		g_iRawHistoryCount++;
	}
}

float GetHistoricalOutputRaw(int client)
{
	return GetHistoricalRaw(client, 0);
}

float GetHistoricalDefenseRaw(int client)
{
	return GetHistoricalRaw(client, 1);
}

float GetHistoricalFocusRaw(int client)
{
	return GetHistoricalRaw(client, 2);
}

float GetHistoricalInfectorRaw(int client)
{
	return GetHistoricalRaw(client, 3);
}

float GetHistoricalRaw(int client, int field)
{
	if (!IsHumanClient(client))
	{
		return 0.0;
	}

	char auth[64];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true))
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

void AggregateHistoricalActions(int client, RatingSnapshotEntry entry)
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

	if (!IsHumanClient(client))
	{
		return;
	}

	char auth[64];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true))
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

float GetTankRaw(int client)
{
	float baseRaw = g_bBecameTank[client] ? 1.0 : 0.0;
	return baseRaw + float(g_iTankDmgUpright[client] + g_iTankPunch[client] * 10 + g_iTankRock[client] * 20 + g_iTankHittable[client] * 35 + g_iTankIncap[client] * 45 + g_iTankDeath[client] * 60);
}

float GetEffectiveTankRaw(int client)
{
	float currentRaw = GetTankRaw(client);
	if (currentRaw > 0.0)
	{
		return currentRaw;
	}

	if (!IsHumanClient(client) || g_hLastTankRaw == null)
	{
		return 0.0;
	}

	char auth[64];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true))
	{
		return 0.0;
	}

	TankHistoryEntry tankEntry;
	if (!g_hLastTankRaw.GetArray(auth, tankEntry, sizeof(tankEntry)))
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

	for (int client = 1; client <= MaxClients; client++)
	{
		float tankRaw = GetTankRaw(client);
		if (tankRaw <= 0.0 || !IsHumanClient(client))
		{
			continue;
		}

		char auth[64];
		if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true))
		{
			continue;
		}

		TankHistoryEntry tankEntry;
		tankEntry.raw = tankRaw;
		tankEntry.becameTank = g_bBecameTank[client];
		tankEntry.tankDmgUpright = g_iTankDmgUpright[client];
		tankEntry.punch = g_iTankPunch[client];
		tankEntry.rock = g_iTankRock[client];
		tankEntry.hittable = g_iTankHittable[client];
		tankEntry.incap = g_iTankIncap[client];
		tankEntry.death = g_iTankDeath[client];

		g_hLastTankRaw.SetArray(auth, tankEntry, sizeof(tankEntry));
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

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsEligibleForRating(client))
		{
			continue;
		}

		float output = GetHistoricalOutputRaw(client);
		float defense = GetHistoricalDefenseRaw(client);
		float focus = GetHistoricalFocusRaw(client);
		float infector = GetHistoricalInfectorRaw(client);
		float tank = GetEffectiveTankRaw(client);

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

void GetBestClientName(int client, char[] buffer, int size)
{
	if (IsClientInGame(client))
	{
		GetClientName(client, buffer, size);
		return;
	}

	strcopy(buffer, size, g_sName[client]);
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
	FormatTime(g_sSnapshotTime, sizeof(g_sSnapshotTime), "%Y-%m-%d %H:%M:%S");

	g_hLastRatingSnapshot.Clear();
	g_hLastRatingSnapshotNames.Clear();

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanClient(client))
		{
			continue;
		}

		char auth[64];
		if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true))
		{
			continue;
		}

		char name[MAX_NAME_LENGTH];
		GetClientName(client, name, sizeof(name));
		g_hLastRatingSnapshotNames.SetString(auth, name);

		RatingSnapshotEntry entry;
		entry.valid = true;
		entry.team = GetClientTeam(client);

		AggregateHistoricalActions(client, entry);

		entry.tankDmgUpright = g_iTankDmgUpright[client];
		entry.punch = g_iTankPunch[client];
		entry.rock = g_iTankRock[client];
		entry.hittable = g_iTankHittable[client];
		entry.incap = g_iTankIncap[client];
		entry.death = g_iTankDeath[client];
		entry.becameTank = g_bBecameTank[client];

		float currentTank = GetTankRaw(client);
		float effectiveTank = GetEffectiveTankRaw(client);
		if (currentTank > 0.0)
		{
			entry.tankSource = 1;
		}
		else if (effectiveTank > 0.0)
		{
			entry.tankSource = 2;
			TankHistoryEntry histTank;
			if (g_hLastTankRaw != null && g_hLastTankRaw.GetArray(auth, histTank, sizeof(histTank)))
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

		if (hasRanges && IsEligibleForRating(client))
		{
			entry.eligible = true;
			entry.outputRaw = GetHistoricalOutputRaw(client);
			entry.defenseRaw = GetHistoricalDefenseRaw(client);
			entry.focusRaw = GetHistoricalFocusRaw(client);
			entry.infectorRaw = GetHistoricalInfectorRaw(client);
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

		g_hLastRatingSnapshot.SetArray(auth, entry, sizeof(entry));
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
				PrintRatingSnapshotToConsole(client, i);
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

	PrintRatingSnapshotToConsole(client, target);

	if (client > 0)
	{
		char targetDisplayName[MAX_NAME_LENGTH];
		GetClientName(target, targetDisplayName, sizeof(targetDisplayName));
		CPrintToChat(client, "{blue}[{green}RatingPro{blue}]{default} 已将玩家 {olive}%s{default} 的 RatingPro 详细数据输出到控制台（按 ~ 键查看）。", targetDisplayName);
	}

	return Plugin_Handled;
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
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsHumanClient(client))
		{
			PrintRatingSnapshotToConsole(0, client, true);
		}
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

void PrintRatingSnapshotToConsole(int requester, int targetClient, bool logToFile = false)
{
	if (!IsHumanClient(targetClient))
	{
		return;
	}

	int targetUserId = GetClientUserId(targetClient);
	char currentName[MAX_NAME_LENGTH];
	char cleanCurrentName[MAX_NAME_LENGTH];
	GetClientName(targetClient, currentName, sizeof(currentName));
	CleanName(currentName, cleanCurrentName, sizeof(cleanCurrentName));

	char auth[64];
	if (!GetClientAuthId(targetClient, AuthId_Steam2, auth, sizeof(auth), true))
	{
		PrintToConsoleOrLog(requester, logToFile, "==================== RatingPro 数据表 ====================");
		PrintToConsoleOrLog(requester, logToFile, "[元信息] 当前玩家: %s (userid: #%d) | 状态: 身份未验证 (N/A)", cleanCurrentName, targetUserId);
		PrintToConsoleOrLog(requester, logToFile, "[说明] 目标玩家尚未完成 Steam 认证，无法关联评分快照。");
		PrintToConsoleOrLog(requester, logToFile, "==========================================================");
		return;
	}

	if (!g_bHasSnapshot)
	{
		PrintToConsoleOrLog(requester, logToFile, "==================== RatingPro 数据表 ====================");
		PrintToConsoleOrLog(requester, logToFile, "[元信息] 当前玩家: %s (userid: #%d) | 状态: 暂无快照数据 (N/A)", cleanCurrentName, targetUserId);
		PrintToConsoleOrLog(requester, logToFile, "[说明] 服务器尚未完成任何章节正式结算，暂无 RatingPro 快照。");
		PrintToConsoleOrLog(requester, logToFile, "==========================================================");
		return;
	}

	RatingSnapshotEntry entry;
	if (!g_hLastRatingSnapshot.GetArray(auth, entry, sizeof(entry)))
	{
		PrintToConsoleOrLog(requester, logToFile, "==================== RatingPro 数据表 ====================");
		PrintToConsoleOrLog(requester, logToFile, "快照编号: #%d | 结算地图: %s | 结算时间: %s", g_iSnapshotRoundId, g_sSnapshotMap, g_sSnapshotTime);
		PrintToConsoleOrLog(requester, logToFile, "[元信息] 当前玩家: %s (userid: #%d) | 状态: 未参与上次结算 (N/A)", cleanCurrentName, targetUserId);
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
		PrintToConsoleOrLog(requester, logToFile, "[元信息] 当前玩家: %s (userid: #%d) | 结算姓名: %s | 结算队伍: %s | 状态: 上次结算数据不足/无资格 (N/A)",
			cleanCurrentName, targetUserId, cleanSnapshotName, teamName);
		PrintToConsoleOrLog(requester, logToFile, "[综合评分] RatingPro: N/A | 加权原始分 (weighted raw): N/A");
		PrintToConsoleOrLog(requester, logToFile, "[原始分与归一化] 输出(output): N/A | 防守(defense): N/A | 关键操作(focus): N/A | 特感进攻(infector): N/A | Tank表现(tank): N/A");
		PrintToConsoleOrLog(requester, logToFile, "[生还者数据] 特感伤害(siDmg)=%d 丧尸击杀(ciKill)=%d 克伤害(tankDmg)=%d 承受伤害(dmgTaken)=%d 倒地(incaps)=%d 死亡(deaths)=%d 友伤(ff)=%d 克局特伤(tankupDmg)=%d 克局特杀(tankupKill)=%d 空爆(skeet)=%d 截停(level)=%d 秒爆(pop)=%d 断舌(tongueCut)=%d 秒妹(crown)=%d",
			entry.siDmg, entry.ciKill, entry.tankDmg, entry.dmgTaken, entry.incaps, entry.deaths, entry.ff,
			entry.tankupDmg, entry.tankupKill, entry.skeet, entry.level, entry.pop, entry.tongueCut, entry.crown);
		PrintToConsoleOrLog(requester, logToFile, "[特感数据] 造成的伤害(dmg)=%d 炸中生还者(booms)=%d 致命牛撞(deathCharges)=%d 克直立伤害(tankDmgUpright)=%d 拳击(punch)=%d 砸石(rock)=%d 铁(hittable)=%d 击倒(incap)=%d 击杀(death)=%d",
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
	PrintToConsoleOrLog(requester, logToFile, "[元信息] 当前玩家: %s (userid: #%d) | 结算姓名: %s | 结算队伍: %s | 状态: 正常有效",
		cleanCurrentName, targetUserId, cleanSnapshotName, teamName);
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
	PrintToConsoleOrLog(requester, logToFile, "[特感数据 (跨章节累计 %d 槽)] 造成的伤害(dmg)=%d 炸中生还者(booms)=%d 致命牛撞(deathCharges)=%d 克直立伤害(tankDmgUpright)=%d 拳击(punch)=%d 砸石(rock)=%d 铁(hittable)=%d 击倒(incap)=%d 击杀(death)=%d",
		entry.recordedSlots, entry.dmg, entry.booms, entry.deathCharges, entry.tankDmgUpright, entry.punch, entry.rock, entry.hittable, entry.incap, entry.death);
	PrintToConsoleOrLog(requester, logToFile, "[说明] 生还者与特感数据为已有历史槽位(%d槽)跨章节累计统计，RatingPro评分采用平均值补齐至四槽计算。", entry.recordedSlots);
	PrintToConsoleOrLog(requester, logToFile, "==========================================================");
}
