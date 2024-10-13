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
    CPrintToChatAll("[{green}EXP{default}] {blue}生还者: %i{default} (平均 %i)", surs, surs/surc);
    CPrintToChatAll("[{green}EXP{default}] {red}感染者: %i{default} (平均 %i)", infs, infs/infc);
    CPrintToChatAll("{default}使用{green} !exp{default} 查看每个人的经验分和队伍的标准差");
    
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