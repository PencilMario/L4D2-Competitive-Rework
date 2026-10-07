#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <colors>
#define L4D2UTIL_STOCKS_ONLY
#include <l4d2util>


#define MAX_PINNED_DISPLAY 12
#define TANK_CHECK_INTERVAL 0.3
#define PINNED_ANNOUNCE_COOLDOWN 0.2
#define HIGHLIGHT_MERGE_DELAY 1.7
#define SMOKER_PIN_VERIFY_DELAY 0.4

enum struct InfectedState {
    int victimCount;
    bool victims[MAXPLAYERS+1];
    bool isActive;
    Handle timer;
}

InfectedState g_Charger[MAXPLAYERS+1];
InfectedState g_Boomer[MAXPLAYERS+1];
InfectedState g_Tank[MAXPLAYERS+1];

Handle g_hSmokerVerify[MAXPLAYERS+1];
bool g_bSmokerPinned[MAXPLAYERS+1];

static int g_iPlayerLastHealth[MAXPLAYERS+1];

static float g_fLastPinnedAnnounce;
static int g_iMaxPinnedCount;
static int g_iCurrentPinnedCount;
static int g_iPinnedRefCount[MAXPLAYERS + 1];

Handle g_hChargerMessageTimer[MAXPLAYERS + 1];
int g_iChargerQueuedCount[MAXPLAYERS + 1];
char g_szChargerQueuedText[MAXPLAYERS + 1][256];


public Plugin myinfo = 
{
    name = "L4D2 Special Infected Highlights",
    author = "Hana",
    description = "Announce special infected highlights",
    version = "2.3",
    url = "https://steamcommunity.com/profiles/76561197983870853/"
};

public void OnPluginStart()
{
    HookEvent("round_start", Event_RoundStart);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_hurt", Event_PlayerHurt);
    
    HookEvent("charger_charge_start", Event_ChargeStart);
    HookEvent("charger_impact", Event_ChargerImpact);
    HookEvent("charger_carry_start", Event_ChargeCarryStart);
    HookEvent("charger_carry_end", Event_ChargeCarryEnd);
    
    HookEvent("player_now_it", Event_BoomerVomit);
    
    HookEvent("tongue_grab", Event_SpecialInfectedGrab);
    HookEvent("choke_start", Event_SpecialInfectedGrab);
    HookEvent("lunge_pounce", Event_SpecialInfectedGrab);
    HookEvent("jockey_ride", Event_SpecialInfectedGrab);
    HookEvent("charger_carry_start", Event_ChargerGrab);
    HookEvent("charger_pummel_start", Event_ChargerGrab);
    HookEvent("player_incapacitated", Event_PlayerIncapacitated);
    
    HookEvent("tongue_release", Event_PinnedEnd);
    HookEvent("pounce_end", Event_PinnedEnd);
    HookEvent("jockey_ride_end", Event_PinnedEnd);
    HookEvent("charger_carry_end", Event_PinnedEnd);
    HookEvent("charger_pummel_end", Event_PinnedEnd);
    
    InitializeVariables();
}

public void OnMapStart()
{
    ResetAllClients();
    InitializeVariables();
}

public void OnPluginEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        ClearSmokerPinTimer(i);
        if (g_hChargerMessageTimer[i] != null)
        {
            KillTimer(g_hChargerMessageTimer[i]);
            g_hChargerMessageTimer[i] = null;
        }
    }
    
}
public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    ClearPinnedState(client);
}

Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!IsValidEntity(victim) || !IsValidEntity(attacker)) return Plugin_Continue;
    if (!attacker || attacker > MaxClients) return Plugin_Continue;
    if (!IsSurvivor(victim) || !IsTank(attacker)) return Plugin_Continue;
    
    int playerHealth = GetSurvivorPermanentHealth(victim) + GetSurvivorTemporaryHealth(victim);
    
    if (RoundToFloor(damage) >= playerHealth)
    {
        g_iPlayerLastHealth[victim] = playerHealth;
        
        char classname[64];
        GetEdictClassname(inflictor, classname, sizeof(classname));
        
        if (StrEqual(classname, "weapon_tank_claw") && !g_Tank[attacker].victims[victim])
        {
            if (!IsIncapacitated(victim))
            {
                ProcessTankPunch(attacker, victim);
            }
        }
    }
    
    return Plugin_Continue;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ResetAllClients();
    InitializeVariables();
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        ResetClientStats(client);
    }
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        ResetClientStats(client);
    }
}

void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));
    
    if (!attacker || !victim || !IsClientInGame(attacker) || !IsClientInGame(victim))
        return;
    
    if (IsTank(attacker) && IsSurvivor(victim))
    {
        if (strcmp(weapon, "tank_rock") == 0)
        {
            if (!IsIncapacitated(victim))
            {
                CPrintToChatAll("{olive}%N{default}({red}Tank{default}) {red}投掷石头命中 {olive}%N", attacker, victim);
            }
            return;
        }
        
        if (strcmp(weapon, "tank_claw") == 0)
        {
            if (!g_Tank[attacker].isActive)
            {
                InitializeTankState(attacker);
            }
            
            if (!IsIncapacitated(victim) && !g_Tank[attacker].victims[victim])
            {
                ProcessTankPunch(attacker, victim);
            }
        }
    }
}

void Event_ChargeStart(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if (!IsCharger(client))
        return;
        
    ResetClientStats(client);
    g_Charger[client].isActive = true;
}

void Event_ChargerImpact(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("victim"));
    
    if (!IsCharger(client) || !IsSurvivor(victim) || !IsPlayerAlive(victim))
        return;
        
    if (g_Charger[client].isActive && !g_Charger[client].victims[victim])
    {
        g_Charger[client].victims[victim] = true;
        g_Charger[client].victimCount++;

        if (g_Charger[client].victimCount >= 2)
        {
            ShowMessage(client, g_Charger[client].victimCount, "Charger", "一撞");
        }
    }
}

void Event_ChargeCarryStart(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("victim"));
    
    if (!IsCharger(client) || !IsSurvivor(victim) || !IsPlayerAlive(victim))
        return;
    
    if (!g_Charger[client].isActive)
    {
        g_Charger[client].isActive = true;
    }
    
    if (!g_Charger[client].victims[victim])
    {
        g_Charger[client].victims[victim] = true;
        g_Charger[client].victimCount++;
    }
}

void Event_ChargeCarryEnd(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsCharger(client))
    {
        g_Charger[client].isActive = false;
    }
}

void Event_BoomerVomit(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    
    if (!IsBoomer(attacker) || !IsSurvivor(victim))
        return;
        
    if (!g_Boomer[attacker].victims[victim])
    {
        g_Boomer[attacker].victims[victim] = true;
        g_Boomer[attacker].victimCount++;
        
        if (g_Boomer[attacker].victimCount >= 2)
        {
            ShowMessage(attacker, g_Boomer[attacker].victimCount, "Boomer", "一喷");
        }
    }
}

void Event_SpecialInfectedGrab(Event event, const char[] name, bool dontBroadcast)
{
    if (StrEqual(name, "tongue_grab"))
    {
        HandleSmokerGrab(event);
        return;
    }
    if (StrEqual(name, "choke_start"))
    {
        HandleSmokerChoke(event);
        return;
    }
    HandlePinEvent(event, true);
}

void Event_ChargerGrab(Event event, const char[] name, bool dontBroadcast)
{
    HandlePinEvent(event, true);
}

void Event_PinnedEnd(Event event, const char[] name, bool dontBroadcast)
{
    HandlePinEvent(event, false);
}

void Event_PlayerIncapacitated(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    if (victim > 0)
    {
        ClearPinnedState(victim);
    }
    
    if (!attacker || !IsClientInGame(attacker))
        return;
        
    if (!IsTank(attacker) || !IsSurvivor(victim))
        return;
        
    if (strcmp(weapon, "prop_physics") == 0)
    {
        CPrintToChatAll("{olive}%N{default}({red}Tank{default}) {red}打铁命中 {olive}%N", attacker, victim);
        return;
    }
    
    if (strcmp(weapon, "tank_claw") == 0)
    {
        if (!g_Tank[attacker].isActive)
        {
            InitializeTankState(attacker);
        }
        
        if (!g_Tank[attacker].victims[victim])
        {
            ProcessTankPunch(attacker, victim);
        }
    }
    else if (strcmp(weapon, "tank_rock") == 0)
    {
        CPrintToChatAll("{olive}%N{default}({red}Tank{default}) {red}投掷石头命中 {olive}%N", attacker, victim);
    }
}

public Action Timer_CheckTankMultiPunch(Handle timer, any attacker)
{
    if (!IsTank(attacker) || !IsPlayerAlive(attacker))
    {
        g_Tank[attacker].timer = null;
        return Plugin_Stop;
    }
    
    if (g_Tank[attacker].victimCount >= 2)
    {
        ShowMessage(attacker, g_Tank[attacker].victimCount, "Tank", "一拍");
    }
    
    ResetTankState(attacker);
    return Plugin_Stop;
}

void InitializeVariables()
{
    g_fLastPinnedAnnounce = 0.0;
    g_iMaxPinnedCount = 0;
    g_iCurrentPinnedCount = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iPinnedRefCount[i] = 0;
        ClearSmokerPinTimer(i);
        g_bSmokerPinned[i] = false;
        g_iChargerQueuedCount[i] = 0;
        g_szChargerQueuedText[i][0] = '\0';
        if (g_hChargerMessageTimer[i] != null)
        {
            KillTimer(g_hChargerMessageTimer[i]);
            g_hChargerMessageTimer[i] = null;
        }
    }
    
}

void ResetAllClients()
{
    g_iCurrentPinnedCount = 0;
    g_iMaxPinnedCount = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iPinnedRefCount[i] = 0;
        g_bSmokerPinned[i] = false;
        if (g_Charger[i].timer != null)
        {
            KillTimer(g_Charger[i].timer);
            g_Charger[i].timer = null;
        }
        ResetClientStats(i);
    }
}

void ResetClientStats(int client)
{
    g_Charger[client].victimCount = 0;
    g_Boomer[client].victimCount = 0;
    g_Tank[client].victimCount = 0;
    
    g_Charger[client].isActive = false;
    g_Boomer[client].isActive = false;
    g_Tank[client].isActive = false;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        g_Charger[client].victims[i] = false;
        g_Boomer[client].victims[i] = false;
        g_Tank[client].victims[i] = false;
    }
    
    if (g_Tank[client].timer != null)
    {
        KillTimer(g_Tank[client].timer);
        g_Tank[client].timer = null;
    }
    
    g_iPlayerLastHealth[client] = 0;
    g_bSmokerPinned[client] = false;
    ClearPinnedState(client);

    g_iChargerQueuedCount[client] = 0;
    g_szChargerQueuedText[client][0] = '\0';
    if (g_hChargerMessageTimer[client] != null)
    {
        KillTimer(g_hChargerMessageTimer[client]);
        g_hChargerMessageTimer[client] = null;
    }
}

void InitializeTankState(int attacker)
{
    g_Tank[attacker].isActive = true;
    g_Tank[attacker].victimCount = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        g_Tank[attacker].victims[i] = false;
    }
}

void ResetTankState(int attacker)
{
    g_Tank[attacker].victimCount = 0;
    g_Tank[attacker].isActive = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        g_Tank[attacker].victims[i] = false;
    }
    g_Tank[attacker].timer = null;
}

void ProcessTankPunch(int attacker, int victim)
{
    g_Tank[attacker].victims[victim] = true;
    g_Tank[attacker].victimCount++;
    
    if (g_Tank[attacker].timer != null)
    {
        KillTimer(g_Tank[attacker].timer);
    }
    g_Tank[attacker].timer = CreateTimer(TANK_CHECK_INTERVAL, Timer_CheckTankMultiPunch, attacker);
}

void FormatStars(char[] buffer, int maxlen, int count)
{
    if (count < 0)
    {
        count = 0;
    }
    else if (count > MAX_PINNED_DISPLAY)
    {
        count = MAX_PINNED_DISPLAY;
    }

    buffer[0] = '\0';
    for (int i = 0; i < count; i++)
    {
        StrCat(buffer, maxlen, "★");
    }
}

void ScheduleChargerMessage(int client, const char[] text, int victims)
{
    if (victims <= g_iChargerQueuedCount[client])
    {
        return;
    }

    g_iChargerQueuedCount[client] = victims;
    strcopy(g_szChargerQueuedText[client], sizeof(g_szChargerQueuedText[]), text);

    if (g_hChargerMessageTimer[client] == null)
    {
        g_hChargerMessageTimer[client] = CreateTimer(HIGHLIGHT_MERGE_DELAY, Timer_FlushChargerMessage, client);
    }
}

public Action Timer_FlushChargerMessage(Handle timer, any client)
{
    if (client <= 0 || client > MaxClients)
    {
        return Plugin_Stop;
    }

    if (g_hChargerMessageTimer[client] == timer)
    {
        g_hChargerMessageTimer[client] = null;
    }

    if (g_iChargerQueuedCount[client] >= 2 && g_szChargerQueuedText[client][0] != '\0')
    {
        CPrintToChatAll("%s", g_szChargerQueuedText[client]);
    }

    g_iChargerQueuedCount[client] = 0;
    g_szChargerQueuedText[client][0] = '\0';
    return Plugin_Stop;
}

void ShowMessage(int attacker, int victims, const char[] type, const char[] action)
{
    if (victims < 2 || victims > MAX_PINNED_DISPLAY)
        return;

    char stars[32];
    FormatStars(stars, sizeof(stars), victims);
    char buffer[256];
    
    if (IsFakeClient(attacker))
    {
        Format(buffer, sizeof(buffer), "{red}%s {olive}AI{default}({red}%s{default}) {red}%s {olive}%d", 
            stars, type, action, victims);
    }
    else
    {
        Format(buffer, sizeof(buffer), "{red}%s {olive}%N{default}({red}%s{default}) {red}%s {olive}%d", 
            stars, attacker, type, action, victims);
    }
    
    if (StrEqual(type, "Charger"))
    {
        ScheduleChargerMessage(attacker, buffer, victims);
    }
    else
    {
        CPrintToChatAll("%s", buffer);
    }
}

void HandlePinEvent(Event event, bool isPinned)
{
    int victim = GetEventClientSafe(event, "victim");
    if (victim <= 0)
    {
        victim = GetEventClientSafe(event, "userid");
    }

    if (victim <= 0)
    {
        return;
    }

    if (isPinned)
    {
        MarkSurvivorPinned(victim);
    }
    else
    {
        ReleaseSurvivorPinned(victim);
    }
}

void HandleSmokerGrab(Event event)
{
    int victim = GetEventClientSafe(event, "victim");
    if (victim <= 0)
    {
        victim = GetEventClientSafe(event, "userid");
    }
    
    if (victim <= 0)
    {
        return;
    }
    
    ClearSmokerPinTimer(victim);
    g_bSmokerPinned[victim] = false;
    
    Handle timer = CreateTimer(SMOKER_PIN_VERIFY_DELAY, Timer_VerifySmokerPin, victim);
    g_hSmokerVerify[victim] = timer;
}

void HandleSmokerChoke(Event event)
{
    int victim = GetEventClientSafe(event, "victim");
    if (victim <= 0)
    {
        victim = GetEventClientSafe(event, "userid");
    }
    
    if (victim <= 0 || g_bSmokerPinned[victim])
    {
        return;
    }

    MarkSurvivorPinned(victim);
    g_bSmokerPinned[victim] = true;
}

int GetEventClientSafe(Event event, const char[] key)
{
    int value = event.GetInt(key);
    if (value <= 0)
    {
        return 0;
    }

    int client = GetClientOfUserId(value);
    if (client > 0)
    {
        return client;
    }

    if (value <= MaxClients)
    {
        return value;
    }

    return 0;
}

void MarkSurvivorPinned(int victim)
{
    if (!IsSurvivor(victim) || !IsPlayerAlive(victim))
    {
        return;
    }

    ClearSmokerPinTimer(victim);

    g_iPinnedRefCount[victim]++;
    if (g_iPinnedRefCount[victim] == 1)
    {
        g_iCurrentPinnedCount++;
        EvaluatePinnedState();
    }
}

void ReleaseSurvivorPinned(int victim)
{
    if (victim <= 0 || victim > MaxClients)
    {
        return;
    }

    ClearSmokerPinTimer(victim);

    if (g_iPinnedRefCount[victim] <= 0)
    {
        g_iPinnedRefCount[victim] = 0;
        g_bSmokerPinned[victim] = false;
        return;
    }

    g_iPinnedRefCount[victim]--;
    if (g_iPinnedRefCount[victim] == 0)
    {
        if (g_iCurrentPinnedCount > 0)
        {
            g_iCurrentPinnedCount--;
        }
        g_bSmokerPinned[victim] = false;

        if (g_iCurrentPinnedCount < 2)
        {
            g_iMaxPinnedCount = 0;
        }
        EvaluatePinnedState();
    }
}

void ClearPinnedState(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    ClearSmokerPinTimer(client);
    g_bSmokerPinned[client] = false;

    if (g_iPinnedRefCount[client] > 0)
    {
        g_iCurrentPinnedCount -= g_iPinnedRefCount[client];
        if (g_iCurrentPinnedCount < 0)
        {
            g_iCurrentPinnedCount = 0;
        }
        g_iPinnedRefCount[client] = 0;
        if (g_iCurrentPinnedCount < 2)
        {
            g_iMaxPinnedCount = 0;
        }
        EvaluatePinnedState();
    }
    else
    {
        g_iPinnedRefCount[client] = 0;
    }
}

void EvaluatePinnedState()
{
    int pinnedCount = g_iCurrentPinnedCount;
    if (pinnedCount < 2)
    {
        if (pinnedCount <= 0)
        {
            g_iMaxPinnedCount = 0;
        }
        return;
    }

    if (pinnedCount > MAX_PINNED_DISPLAY)
    {
        return;
    }

    int alive = GetAliveSurvivorCount();
    if (alive <= 0)
    {
        return;
    }

    if (pinnedCount > alive)
    {
        pinnedCount = alive;
    }

    if (pinnedCount > g_iMaxPinnedCount)
    {
        float currentTime = GetGameTime();
        if (currentTime - g_fLastPinnedAnnounce < PINNED_ANNOUNCE_COOLDOWN)
        {
            return;
        }

        g_iMaxPinnedCount = pinnedCount;

        char stars[32];
        FormatStars(stars, sizeof(stars), pinnedCount);
        char buffer[256];
        Format(buffer, sizeof(buffer), "{red}%s {red}特感阵营达成 {olive}%d {red}控", stars, pinnedCount);
        CPrintToChatAll("%s", buffer);
        g_fLastPinnedAnnounce = currentTime;
    }
}

int GetAliveSurvivorCount()
{
    int alive = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) != 2)
        {
            continue;
        }

        if (IsPlayerAlive(i))
        {
            alive++;
        }
    }
    return alive;
}

void ClearSmokerPinTimer(int victim)
{
    if (victim <= 0 || victim > MaxClients)
    {
        return;
    }
    
    if (g_hSmokerVerify[victim] != null)
    {
        KillTimer(g_hSmokerVerify[victim]);
        g_hSmokerVerify[victim] = null;
    }
}

public Action Timer_VerifySmokerPin(Handle timer, any victim)
{
    if (victim <= 0 || victim > MaxClients)
    {
        return Plugin_Stop;
    }
    
    if (g_hSmokerVerify[victim] == timer)
    {
        g_hSmokerVerify[victim] = null;
    }
    
    if (!IsSurvivor(victim) || !IsPlayerAlive(victim))
    {
        return Plugin_Stop;
    }
    
    if (g_bSmokerPinned[victim])
    {
        return Plugin_Stop;
    }

    if (GetEntPropEnt(victim, Prop_Send, "m_tongueOwner") > 0)
    {
        MarkSurvivorPinned(victim);
        g_bSmokerPinned[victim] = true;
    }
    
    return Plugin_Stop;
}

bool IsCharger(int client)
{
    return IsValidClient(client) && GetEntProp(client, Prop_Send, "m_zombieClass") == 6;
}

bool IsBoomer(int client)
{
    return IsValidClient(client) && GetEntProp(client, Prop_Send, "m_zombieClass") == 2;
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}
