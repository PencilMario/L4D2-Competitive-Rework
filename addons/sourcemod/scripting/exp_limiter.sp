#pragma semicolon               1
#pragma newdecls                required
#include <sourcemod>
#include <colors>
#include <l4d2util_constants>
#include <exp_interface>

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
            CPrintToChat(client, "[{red}!{default}] 你不能进入游戏, 因为你的经验分超出范围了 (%i~%i)", min.IntValue, max.IntValue);
            return Plugin_Handled;
        }
    }
    return Plugin_Continue;
}

public bool isInRange(int i, int mi, int ma){
    return i >= mi && i <= ma;
}