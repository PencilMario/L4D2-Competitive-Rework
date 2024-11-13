#pragma semicolon               1
#pragma newdecls                required
#include <sourcemod>
#include <colors>
#include <l4d2util_constants>
#include <exp_interface>

#undef REQUIRE_PLUGIN
#include <readyup>
#define REQUIRE_PLUGIN

bool g_bReadyUpAvailable = false;

public void OnPluginStart()
{
    RegConsoleCmd("sm_exp", CMD_Exp);
}

public void OnAllPluginsLoaded()
{
    g_bReadyUpAvailable = LibraryExists("readyup");
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "readyup"))
    {
        g_bReadyUpAvailable = true;
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "readyup"))
    {
        g_bReadyUpAvailable = false;
    }
}

#if !defined REQUIRE_PLUGIN
public void __pl_readyup_SetNTVOptional()
{
    MarkNativeAsOptional("OnRoundIsLive");
}
#endif

public void OnRoundIsLive()
{
    if (g_bReadyUpAvailable)
    {
        CreateTimer(3.0, Timer_DelayedRoundIsLive);
    }
}

public Action Timer_DelayedRoundIsLive(Handle timer){
    int surs, infs;
    int surc, infc;
    int suravg2, infavg2;
    for (int i = 1; i <= MaxClients; i++){
        if (!IsClientInGame(i)) continue;
        switch (GetClientTeam(i)){
            case L4D2Team_Survivor:{
                surs += L4D2_GetClientExp(i);
                surc++;
            }
            case L4D2Team_Infected:{
                infs += L4D2_GetClientExp(i);
                infc++;
            }
        }
        
    }        
    int suravg = surs/surc;
    int infavg = infs/infc;
    for (int i = 1; i <= MaxClients; i++){
        if (!IsClientInGame(i)) continue;
        switch (GetClientTeam(i)){
            case L4D2Team_Survivor:{
                suravg2 += abs(suravg - L4D2_GetClientExp(i));
            }
            case L4D2Team_Infected:{
                infavg2 += abs(infavg - L4D2_GetClientExp(i));
            }
        }
    }
    CPrintToChatAll("[{green}EXP{default}] {blue}生还者: %i{default} (平均 %i / 标准差 %i)", surs, surs/surc, suravg2);
    CPrintToChatAll("[{green}EXP{default}] {red}感染者: %i{default} (平均 %i / 标准差 %i)", infs, infs/infc, infavg2);
    CPrintToChatAll("{default}使用{green} !exp{default} 查看每个人的经验分");
    
    return Plugin_Handled;

}

public Action CMD_Exp(int client, int args){
    int surs, infs;
    int surc, infc;
    int suravg2, infavg2;
    for (int i = 1; i <= MaxClients; i++){
        if (!IsClientInGame(i)) continue;
        switch (GetClientTeam(i)){
            case L4D2Team_Survivor:{
                CPrintToChat(client, "{blue}%N{default} %i[{green}%s{default}]", i, L4D2_GetClientExp(i), EXPRankNames[L4D2_GetClientExpRankLevel(i)]);
                surs += L4D2_GetClientExp(i);
                surc++;
            }
            case L4D2Team_Infected:{
                CPrintToChat(client,"{red}%N{default} %i[{green}%s{default}]", i, L4D2_GetClientExp(i), EXPRankNames[L4D2_GetClientExpRankLevel(i)]);
                infs += L4D2_GetClientExp(i);
                infc++;
            }
            case L4D2Team_Spectator:{
                CPrintToChat(client,"{default}%N{default} %i[{green}%s{default}]", i, L4D2_GetClientExp(i), EXPRankNames[L4D2_GetClientExpRankLevel(i)]);
            }
        }
    }
    int suravg = surs/surc;
    int infavg = infs/infc;
    for (int i = 1; i <= MaxClients; i++){
        if (!IsClientInGame(i)) continue;
        switch (GetClientTeam(i)){
            case L4D2Team_Survivor:{
                suravg2 += abs(suravg - L4D2_GetClientExp(i));
            }
            case L4D2Team_Infected:{
                infavg2 += abs(infavg - L4D2_GetClientExp(i));
            }
        }
    }
    CPrintToChat(client,"============================");
    CPrintToChat(client,"[{green}EXP{default}] {blue}生还者: %i{default} (平均 %i / 标准差 %i)", surs, surs/surc, suravg2);
    CPrintToChat(client,"[{green}EXP{default}] {red}感染者: %i{default} (平均 %i / 标准差 %i)", infs, infs/infc, infavg2);
    return Plugin_Handled;
}

int abs(int v){
    return v < 0 ? -v : v;
}