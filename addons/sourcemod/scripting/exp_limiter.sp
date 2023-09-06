#pragma semicolon               1
#pragma newdecls                required
#include <sourcemod>
#include <colors>
#include <l4d2util_constants>
#include <exp_interface>
#define WARMBOT_STEAMID "STEAM_1:1:695917591"
ConVar enable, max, min;

public void OnPluginStart(){
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
    enable = CreateConVar("exp_limit_enabled", "0");
    min = CreateConVar("exp_limit_min", "0");
    max = CreateConVar("exp_limit_max", "0");
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast){
    if (enable.IntValue == 0) return Plugin_Continue;
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (IsFakeClient(client)) return Plugin_Continue;
    int team = event.GetInt("team");
    if (team == L4D2Team_Infected || team == L4D2Team_Survivor){
        if (!isInRange(L4D2_GetClientExp(client), min.IntValue, max.IntValue)){
            if (L4D2_GetClientExp(client) == -2){
                CPrintToChat(client, "[{red}!{default}] 你不能进入游戏, 因为暂时未获取到你的经验分, 请稍后重试");
            }
            else CPrintToChat(client, "[{red}!{default}] 你不能进入游戏, 因为你的经验分(%i)不在规定范围内 {olive}(%i~%i){default}, 你仍可以旁观",L4D2_GetClientExp(client) ,min.IntValue, max.IntValue);
            CreateTimer(3.0, Timer_SafeToSpec, client);
            return Plugin_Continue;
        }
    }
    return Plugin_Continue;
}

public bool isInRange(int i, int mi, int ma){
    return i >= mi && i <= ma;
}

public Action Timer_SafeToSpec(Handle timer, int client){
    if (IsClientInGame(client) && !IsWarmBot(client)) FakeClientCommand(client, "sm_s");
    else if (IsClientConnected(client)) CreateTimer(3.0, Timer_SafeToSpec, client);
    else return Plugin_Stop;
    return Plugin_Continue;
}

bool IsWarmBot(int client)
{
    char steamid[64];
    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
    return StrEqual(steamid, WARMBOT_STEAMID);
}