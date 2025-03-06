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
    int surl[MAXPLAYERS], infl[MAXPLAYERS] = {0};
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

float CalculateCoefficientOfVariation(int[] array, int length) {
    float sum = 0.0;
    int validLength = 0;
    
    // 调试输出原始数据
    PrintToServer("[DEBUG] 原始数据:");
    for (int i = 0; i < length; i++) {
        PrintToServer("array[%d] = %d", i, array[i]);
    }
    
    // 第一遍遍历：计算有效数据
    for (int i = 0; i < length; i++) {
        if (array[i] > 0) {
            sum += float(array[i]);
            validLength++;
            PrintToServer("[处理] 接受 array[%d] = %d (当前sum=%.2f, valid=%d)", 
                i, array[i], sum, validLength);
        } else {
            PrintToServer("[跳过] 排除 array[%d] = %d (非正数)", i, array[i]);
        }
    }
    
    PrintToServer("[SUM] 总和=%.2f 有效数据=%d", sum, validLength);
    
    if (validLength <= 1) {
        PrintToServer("[错误] 有效数据不足: %d <=1", validLength);
        return 0.0;
    }
    
    // 计算平均值
    float mean = sum / float(validLength);
    PrintToServer("[MEAN] 平均值=%.2f", mean);
    
    if (mean == 0.0) {
        PrintToServer("[警告] 平均值为零!");
        return 0.0;
    }
    
    // 第二遍遍历：计算方差
    float variance = 0.0;
    for (int i = 0; i < length; i++) {
        if (array[i] > 0) {
            float diff = float(array[i]) - mean;
            variance += (diff * diff);
            PrintToServer("[方差] array[%d]贡献: (%.2f - %.2f)^2 = %.2f (累计=%.2f)",
                i, float(array[i]), mean, diff*diff, variance);
        }
    }
    variance /= float(validLength - 1); // 样本方差
    PrintToServer("[VAR] 方差=%.2f (分母=%d-1)", variance, validLength);
    
    // 计算标准差
    float std_dev = SquareRoot(variance);
    PrintToServer("[STD] 标准差=%.2f (sqrt(%.2f))", std_dev, variance);
    
    // 最终结果
    float cv = (std_dev / mean) * 100.0;
    PrintToServer("[CV] 变异系数= (%.2f / %.2f) *100 = %.2f%%", 
        std_dev, mean, cv);
    
    return cv;
}