#include <sourcemod>
#include <left4dhooks>
#include <colors>

float g_fSpawnTime[MAXPLAYERS + 1];

ConVar g_cvAntiRockProtectTime;

public Plugin myinfo = 
{
	name = "[L4D2] Tank Spawn Anti-Rock Protect",
	author = "B[R]UTUS",
	description = "Protects a Tank player from randomly rock attack at his spawn",
	version = "1.0.1",
	url = "https://github.com/SirPlease/L4D2-Competitive-Rework"
}

public void OnPluginStart()
{
	HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_Post);
	g_cvAntiRockProtectTime = CreateConVar("l4d2_antirock_protect_time", "1.5", "Protection time to avoid Tank throwing a rock by accident");
}

void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int tank = GetClientOfUserId(event.GetInt("userid"));
	g_fSpawnTime[tank] = GetGameTime();
}

// 使用l4d_tank_pass
public void TP_OnTankPass(int old_tank, int new_tank){
	g_fSpawnTime[old_tank] = 0.0;
	g_fSpawnTime[new_tank] = GetGameTime();
}

public Action L4D_OnCThrowActivate(int ability)
{
	int abilityOwner = GetEntPropEnt(ability, Prop_Send, "m_owner");

	if (abilityOwner != -1 && GetGameTime() - g_fSpawnTime[abilityOwner] < g_cvAntiRockProtectTime.FloatValue)
		return Plugin_Handled;

	return Plugin_Continue;
}