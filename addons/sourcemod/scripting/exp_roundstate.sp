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
    for(int i = 1; i <= MaxClients; i++){
        if (IsClientInGame(i)){
            PrintExp(i, false);
        }
    }
    CPrintToChatAll("{default}使用{green} !exp{default} 查看每个人的经验分");
    
    return Plugin_Handled;

}

public Action CMD_Exp(int client, int args){
    PrintExp(client, true);
    return Plugin_Handled;
}



void PrintExp(int client, bool show_everyone){
    int surs, infs;
    int surc, infc;
    int suravg2, infavg2;
    int surl[MAXPLAYERS], infl[MAXPLAYERS];
    for (int i = 1; i <= MaxClients; i++){
        if (!IsClientInGame(i)) continue;
        switch (GetClientTeam(i)){
            case L4D2Team_Survivor:{
                if (show_everyone)
                    CPrintToChat(client, "{blue}%N{default} %i[{green}%s{default}]", i, L4D2_GetClientExp(i), EXPRankNames[L4D2_GetClientExpRankLevel(i)]);
                surs += L4D2_GetClientExp(i);
                surc++;
                surl[i] = L4D2_GetClientExp(i);
            }
            case L4D2Team_Infected:{
                if (show_everyone)
                    CPrintToChat(client,"{red}%N{default} %i[{green}%s{default}]", i, L4D2_GetClientExp(i), EXPRankNames[L4D2_GetClientExpRankLevel(i)]);
                infs += L4D2_GetClientExp(i);
                infc++;
                infl[i] = L4D2_GetClientExp(i);
            }
            case L4D2Team_Spectator:{
                if (show_everyone)
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
    CPrintToChat(client,"[{green}EXP{default}] {blue}生还者: %i{default} (平均 %i / 标准差 %i / 变异系数 %.2f%)", surs, surs/surc, suravg2, CalculateCoefficientOfVariation(surl, MAXPLAYERS));
    CPrintToChat(client,"[{green}EXP{default}] {red}感染者: %i{default} (平均 %i / 标准差 %i / 变异系数 %.2f%)", infs, infs/infc, infavg2, CalculateCoefficientOfVariation(infl, MAXPLAYERS));
}

int abs(int v){
    return v < 0 ? -v : v;
}

float CalculateCoefficientOfVariation(int[] array, int length)
{
    int sum = 0;
    int validLength = 0;
    
    // 第一遍遍历：计算有效数据的总和和数量
    for (int i = 0; i < length; i++) {
        if (array[i] >= 0) {
            sum += array[i];
            validLength++;
        }
    }
    
    // 有效性检查（至少需要两个有效数据点）
    if (validLength <= 1) {
        return 0.0;
    }
    
    // 计算平均值
    float mean = float(sum) / float(validLength);
    
    // 处理平均值为零的特殊情况
    if (mean == 0.0) {
        return 0.0;
    }
    
    // 第二遍遍历：计算方差
    float variance = 0.0;
    for (int i = 0; i < length; i++) {
        if (array[i] >= 0) {
            float diff = float(array[i]) - mean;
            variance += (diff * diff);
        }
    }
    variance /= float(validLength - 1); // 样本方差
    
    // 计算标准差和变异系数
    float std_dev = SquareRoot(variance);
    return (std_dev / mean) * 100.0;
}