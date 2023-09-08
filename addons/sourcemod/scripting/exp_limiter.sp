#pragma semicolon               1
#pragma newdecls                required
#include <sourcemod>
#include <colors>
#include <l4d2util_constants>
#include <exp_interface>
#define WARMBOT_STEAMID "STEAM_1:1:695917591"
ConVar enable, max, min;

public void OnPluginStart(){
    CreateTimer(2.0, Timer_CheckAllPlayer, _, TIMER_REPEAT);
    enable = CreateConVar("exp_limit_enabled", "0");
    min = CreateConVar("exp_limit_min", "0");
    max = CreateConVar("exp_limit_max", "0");
}

public Action Timer_CheckAllPlayer(Handle timer){
    if (enable.IntValue == 0) return Plugin_Continue;
    for (int client = 1; client <= MaxClients; client++){
        if (!IsClientInGame(client)) continue;
        int team = GetClientTeam(client);
        if (team == L4D2Team_Infected || team == L4D2Team_Survivor){
            if (!isInRange(L4D2_GetClientExp(client), min.IntValue, max.IntValue)){
                if (L4D2_GetClientExp(client) == -2){
                    CPrintToChat(client, "[{red}!{default}] 你不能进入游戏, 因为暂时未获取到你的经验分, 请稍后重试");
                }
                else CPrintToChat(client, "[{red}!{default}] 你不能进入游戏, 因为你的经验分(%i)不在规定范围内 {olive}(%i~%i){default}, 你仍可以旁观",L4D2_GetClientExp(client) ,min.IntValue, max.IntValue);
                CreateTimer(3.0, Timer_SafeToSpec, client);
            }
        }
    }
    return Plugin_Continue;
}

public bool isInRange(int i, int mi, int ma){
    return i >= mi && i <= ma;
}

public Action Timer_SafeToSpec(Handle timer, int client){
    if (IsWarmBot(client)) return Plugin_Stop;
    if (IsClientInGame(client) && GetClientTeam(client) != L4D2Team_Spectator) FakeClientCommand(client, "sm_s");
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