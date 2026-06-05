#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>
#include <l4d2_skill_detect>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_TANK 8

#define RATING_SLOPE 0.7
#define RATING_INTERCEPT 2.5
#define TANK_NO_DATA_SCORE 4.6

public Plugin myinfo =
{
	name = "L4D2 Round RatingPro",
	author = "Codex",
	description = "Estimates per-round RatingPro from in-game survivor and infected performance.",
	version = PLUGIN_VERSION,
	url = ""
};

ConVar g_hEnabled;
ConVar g_hDelay;
ConVar g_hMinRaw;

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

public void OnPluginStart()
{
	g_hEnabled = CreateConVar("sm_round_ratingpro_enabled", "1", "Enable round-end RatingPro estimate announcement.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hDelay = CreateConVar("sm_round_ratingpro_delay", "3.0", "Delay after round_end before announcing the best round RatingPro client.", FCVAR_NONE, true, 0.0, true, 15.0);
	g_hMinRaw = CreateConVar("sm_round_ratingpro_min_raw", "1.0", "Minimum weighted raw score required before announcing a winner.", FCVAR_NONE, true, 0.0, true, 10.0);
	CreateConVar("sm_round_ratingpro_version", PLUGIN_VERSION, "L4D2 Round RatingPro version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("scavenge_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("map_transition", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("finale_vehicle_leaving", Event_RoundEnd, EventHookMode_PostNoCopy);

	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("infected_death", Event_InfectedDeath, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_incapacitated", Event_PlayerIncapacitated, EventHookMode_Post);

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
			g_iDmgTaken[victim] += damage;
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
			g_iInfDmgTotal[attacker] += damage;
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
		RememberClient(attacker);
		g_iTankIncap[attacker]++;
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
		CPrintToChatAll("{blue}[{green}RatingPro{blue}]{default} 本章节没有足够数据生成最佳表现。");
		PrintAllClientRatingDetailsNoData();
		PrintAllClientRatingDetailsToConsoleNoData();
		return Plugin_Stop;
	}

	int bestClient = 0;
	float bestRating = 0.0;
	float bestRaw = 0.0;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsEligibleForRating(client))
		{
			continue;
		}

		float output = NormalizeRaw(GetOutputRaw(client), outputMin, outputMax);
		float defense = NormalizeRaw(GetDefenseRaw(client), defenseMin, defenseMax);
		float focus = NormalizeRaw(GetFocusRaw(client), focusMin, focusMax);
		float infector = NormalizeRaw(GetInfectorRaw(client), infectorMin, infectorMax);
		float tank = NormalizeTankRaw(GetTankRaw(client), tankMin, tankMax);
		float raw = GetWeightedRaw(output, defense, focus, infector, tank);
		float rating = raw * RATING_SLOPE + RATING_INTERCEPT;

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
		return Plugin_Stop;
	}

	char name[MAX_NAME_LENGTH];
	GetBestClientName(bestClient, name, sizeof(name));
	CPrintToChatAll("{blue}[{green}RatingPro{blue}]{default} 章节最佳: {olive}%s{default} rating {green}%.1f",
		name, bestRating);
	PrintAllClientRatingDetails(outputMin, outputMax, defenseMin, defenseMax, focusMin, focusMax, infectorMin, infectorMax, tankMin, tankMax);
	PrintAllClientRatingDetailsToConsole(outputMin, outputMax, defenseMin, defenseMax, focusMin, focusMax, infectorMin, infectorMax, tankMin, tankMax);

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

		float output = NormalizeRaw(GetOutputRaw(client), outputMin, outputMax);
		float defense = NormalizeRaw(GetDefenseRaw(client), defenseMin, defenseMax);
		float focus = NormalizeRaw(GetFocusRaw(client), focusMin, focusMax);
		float infector = NormalizeRaw(GetInfectorRaw(client), infectorMin, infectorMax);
		float tank = NormalizeTankRaw(GetTankRaw(client), tankMin, tankMax);
		float raw = GetWeightedRaw(output, defense, focus, infector, tank);
		float rating = raw * RATING_SLOPE + RATING_INTERCEPT;

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

		float outputRaw = GetOutputRaw(client);
		float defenseRaw = GetDefenseRaw(client);
		float focusRaw = GetFocusRaw(client);
		float infectorRaw = GetInfectorRaw(client);
		float tankRaw = GetTankRaw(client);
		float output = NormalizeRaw(outputRaw, outputMin, outputMax);
		float defense = NormalizeRaw(defenseRaw, defenseMin, defenseMax);
		float focus = NormalizeRaw(focusRaw, focusMin, focusMax);
		float infector = NormalizeRaw(infectorRaw, infectorMin, infectorMax);
		float tank = NormalizeTankRaw(tankRaw, tankMin, tankMax);
		float raw = GetWeightedRaw(output, defense, focus, infector, tank);
		float rating = raw * RATING_SLOPE + RATING_INTERCEPT;

		PrintToServer("[RatingPro] #%d %s team=%d rating=%.1f raw=%.1f normalized(output=%.1f defense=%.1f focus=%.1f infector=%.1f tank=%.1f)",
			client, name, GetClientTeam(client), rating, raw, output, defense, focus, infector, tank);
		PrintToServer("[RatingPro] #%d %s raw(output=%.1f defense=%.1f focus=%.1f infector=%.1f tank=%.1f)",
			client, name, outputRaw, defenseRaw, focusRaw, infectorRaw, tankRaw);
		PrintToServer("[RatingPro] #%d %s survivor(siDmg=%d ciKill=%d tankDmg=%d dmgTaken=%d incaps=%d deaths=%d ff=%d tankupDmg=%d tankupKill=%d skeet=%d level=%d pop=%d tongueCut=%d crown=%d)",
			client, name, g_iSiDamage[client], g_iCiKilled[client], g_iTankDamage[client], g_iDmgTaken[client], g_iIncaps[client], g_iDied[client], g_iFfGiven[client], g_iSiDamageTankup[client], g_iSiKilledTankup[client], g_iSkeets[client], g_iLevels[client], g_iPops[client], g_iTongueCuts[client], g_iCrowns[client]);
		PrintToServer("[RatingPro] #%d %s infected(dmg=%d booms=%d deathCharges=%d tankDmgUpright=%d punch=%d rock=%d hittable=%d incap=%d death=%d)",
			client, name, g_iInfDmgTotal[client], g_iInfBooms[client], g_iInfDeathCharges[client], g_iTankDmgUpright[client], g_iTankPunch[client], g_iTankRock[client], g_iTankHittable[client], g_iTankIncap[client], g_iTankDeath[client]);
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
	}
}

void TrackTankHit(int tank, int survivor, int damage, Event event)
{
	RememberClient(tank);
	g_iInfDmgTotal[tank] += damage;

	if (!IsSurvivorIncapacitated(survivor))
	{
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
		|| g_iTankDeath[client] > 0;
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

float GetTankRaw(int client)
{
	return float(g_iTankDmgUpright[client] + g_iTankPunch[client] * 10 + g_iTankRock[client] * 20 + g_iTankHittable[client] * 35 + g_iTankIncap[client] * 45 + g_iTankDeath[client] * 60);
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

		float output = GetOutputRaw(client);
		float defense = GetDefenseRaw(client);
		float focus = GetFocusRaw(client);
		float infector = GetInfectorRaw(client);
		float tank = GetTankRaw(client);

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
			return true;
		}
	}

	return false;
}

bool InSecondHalfOfRound()
{
	return GameRules_GetProp("m_bInSecondHalfOfRound") != 0;
}
