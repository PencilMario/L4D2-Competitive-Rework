#include <sourcemod>
#include <sdktools>
#include <colors>
#define CHECK_INTERVAL 5.0
#define KICK_DELAY 20.0


public void OnPluginStart()
{
    CreateTimer(CHECK_INTERVAL, Timer_CheckTeams, _, TIMER_REPEAT);
}

public Action Timer_CheckTeams(Handle timer)
{
    int numSurvivors = 0;
    int numInfected = 0;
    int numSpectators = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i)) continue;
        
        int team = GetClientTeam(i);
        if (IsFakeClient(i)){
            // 死亡的生还bot应该被计算 去除存活的生还bot
            if (IsPlayerAlive(i) && GetClientTeam(i) == 2) continue;
        }
        switch (team)
        {
            case 2:
                numSurvivors++;
            case 3:
                numInfected++;
            case 1:
                numSpectators++;
        }
    }

    if (numSurvivors < 4 || numInfected < 4)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i)) continue;
            int team = GetClientTeam(i);
            if (team == 1 && !IsFakeClient(i))
            {
                CPrintToChat(i, "[{green}!{default}] 请及时进行补位，不然将会踢出");
                CreateTimer(KICK_DELAY, Timer_KickSpectator, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
            }
            break;
        }
    }

    return Plugin_Continue;
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