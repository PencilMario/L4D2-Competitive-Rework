#include <sourcemod>
#include <sdktools>
#include <colors>
#include <l4d2util_constants>
#define CHECK_INTERVAL 1.0
#define KICK_DELAY 20.0


public void OnPluginStart()
{
    CreateTimer(CHECK_INTERVAL, Timer_CheckTeams, _, TIMER_REPEAT);
}

public Action Timer_CheckTeams(Handle timer)
{
    int players[L4D2Team_Size]
    // 统计玩家数量
    for (int i = 1; i <= MaxClients; i++){
        if (!IsClientInGame(i)) continue;
        switch (GetClientTeam(i)){
            case L4D2Team_None:
                {}
            case L4D2Team_Spectator: 
                players[L4D2Team_Spectator]++;
            case L4D2Team_Survivor:{
                if (!IsPlayerAlive(i) || !IsFakeClient(i)) players[L4D2Team_Survivor]++;
            }
            case L4D2Team_Infected:
                players[L4D2Team_Infected]++;
        }
    }
    for (int i = 1; i <= MaxClients; i++){
        
    }
}

public Action Timer_KickSpectator(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client)) return Plugin_Stop;
    if (client != 0 && GetClientTeam(client) == 1)
    {
        KickClient(client, "你因为旁观占位被踢出");
    }

    return Plugin_Continue;
}
