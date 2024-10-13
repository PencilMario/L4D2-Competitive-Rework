#pragma semicolon               1
#pragma newdecls                required
#include <sourcemod>
#include <colors>
#include <l4d2util_constants>
#include <exp_interface>
#include <readyup>

public void OnPluginStart()
{
    RegConsoleCmd("sm_exp", CMD_Exp);
}

public void OnRoundIsLive(){
    int surs, infs;
    int surc, infc;
    for (int i = 1; i <= MaxClients; i++){
        if (!IsClientInGame(i)) continue;
        CPrintToChatAll("{blue}%N{default} %i[{green}%s{default}]", i, L4D2_GetClientExp(i), EXPRankNames[L4D2_GetClientExpRankLevel(i)]);
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
    CPrintToChatAll("[{green}EXP{default}] {blue}生还者: %i{default} (平均 %i) | {red}感染者: %i{default} (平均 %i)", surs, surs/surc, infs, infs/infc);
    CPrintToChatAll("{default}[{blue}{default}] 使用{green} !exp{default} 查看每个人的经验分");
    
}
public Action CMD_Exp(int client, int args){
    int surs, infs;
    int surc, infc;
    for (int i = 1; i <= MaxClients; i++){
        if (!IsClientInGame(i)) continue;
        CPrintToChatAll("{blue}%N{default} %i[{green}%s{default}]", i, L4D2_GetClientExp(i), EXPRankNames[L4D2_GetClientExpRankLevel(i)]);
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
    CPrintToChatAll("[{green}EXP{default}] {blue}生还者: %i{default} (平均 %i) | {red}感染者: %i{default} (平均 %i)", surs, surs/surc, infs, infs/infc);
    return Plugin_Handled;
}
