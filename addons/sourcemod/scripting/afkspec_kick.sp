#include <sourcemod>
#include <sdktools>
#include <colors>
#include <l4d2util_constants>
#define CHECK_INTERVAL 1.0

int kicktime[MAXPLAYERS] = {20};
public void OnPluginStart()
{
    CreateTimer(CHECK_INTERVAL, Timer_CheckTeams, _, TIMER_REPEAT);
}
public void OnMapStart(){
    for (int i = 1; i <= MaxClients; i++){
        kicktime[i] = 20;
    }
}
public Action Timer_CheckTeams(Handle timer)
{
    int players[L4D2Team_Size]
    // 统计玩家数量
    for (int i = 1; i <= MaxClients; i++){
        if (!IsClientInGame(i)) continue;
        switch (GetClientTeam(i)){
            case L4D2Team_Spectator: 
                players[L4D2Team_Spectator]++;
            case L4D2Team_Survivor:{
                if (!IsPlayerAlive(i) || !IsFakeClient(i)) players[L4D2Team_Survivor]++;
            }
            case L4D2Team_Infected:
                players[L4D2Team_Infected]++;
        }
    }
    if (players[L4D2Team_Survivor] < 4 || players[L4D2Team_Infected] < 4){
        if (players[L4D2Team_Spectator] > 0){
            for (int i = 1; i <= MaxClients; i++){
                if (!IsClientInGame(i)) continue;
                if (GetClientTeam(i) == L4D2Team_Spectator){
                    CPrintToChat(i, "[{olive}!{default}] 请在 {green}%is{default} 内进入队伍, 不然将会踢出", kicktime[i]);
                    if (kicktime[i]-- < 0){
                        KickClient(i, "你因为旁观占位被踢出");
                    }
                    break;
                }
            }
        }
    }
    return Plugin_Continue;
}

public void OnClientConnected(int client){
    kicktime[client] = 20;
}

public void OnClientDisconnect(int client){
    OnClientConnected(client);
}