#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <l4d2util>
#include <left4dhooks>
#include <colors>
#include <sdkhooks>
#define GAMEDATA_FILE "l4d_predict_tank_glow"

#include <prophunt_single>
#include <tankglow/tankglow_defines>

#define COOLDOWN_TIME_SUR 120.0
#define COOLDOWN_TIME_INF 45.0
CZombieManager ZombieManager;
float f_ClientLastUsed[MAXPLAYERS];
public Plugin myinfo =
{
	name		= "L4D2 Prop Hunt",
	author		= "Sir.P",
	description = "躲猫猫玩法 - 传送至指定进度",
	version		= "0.0.0",
	url			= "null"
};
public void OnPluginStart(){
	RegConsoleCmd("sm_phtp", CMD_PHTeleport, "tp至指定进度");
	LoadSDK();
}

public void OnHidingStage_Post(){
	for(int i = 1; i <= MaxClients; i++){
		f_ClientLastUsed[i] = -1000.0;
	}
	for (int i = 1; i <= MaxClients; i++){
		if (IsClientInGame(i) && GetClientTeam(i) == L4D2Team_Survivor){
			CPrintToChat(i, "{blue} 你可以使用指令 {green}!phtp <进度>{blue} 来传送到指定进度!");
			CPrintToChat(i, "{blue} 示例: {green}!phtp 50{blue}");
			CPrintToChat(i, "{blue} 这将会传送你到大约50%进度的位置, 但该指令只能在躲藏阶段使用, 且CD为%.0f秒", COOLDOWN_TIME_SUR);
		}
	}
}

public void OnSeekingStage_Post(){
	for (int i = 1; i <= MaxClients; i++){
		if (IsClientInGame(i) && GetClientTeam(i) == L4D2Team_Infected){
			CPrintToChat(i, "{blue} 你可以使用指令 {green}!phtp <进度>{blue} 来传送到指定进度!");
			CPrintToChat(i, "{blue} 示例: {green}!phtp 50{blue}");
			CPrintToChat(i, "{blue} 这将会传送你到大约50%进度的位置, CD为%.0f秒, 如果你知道大概位置的话会很有用...", COOLDOWN_TIME_INF);
		}
	}
}

public Action CMD_PHTeleport(int client, int args){
	if(args != 1){
		ReplyToCommand(client, "[SM] Usage: sm_phtp <percent>\npercent: 0-100");
		return Plugin_Handled;
	}
	float targetper = L4D2Util_IntToPercentFloat(GetCmdArgInt(1), 100);
	float cooldowntime = GetGameTime() - f_ClientLastUsed[client];
	if (IsPlayerAlive(client)){
		if (GetClientTeam(client) == L4D2Team_Survivor){
			if (GetPHRoundState() != 1){
				CReplyToCommand(client, "{blue}只有在躲藏阶段才能传送!");
				return Plugin_Handled;
			}
			else if(cooldowntime < COOLDOWN_TIME_SUR)
			{
				CReplyToCommand(client, "{blue}你需要等待 %.0f 秒后才能传送", COOLDOWN_TIME_SUR - cooldowntime);
				return Plugin_Handled;
			}
		}
		else if(GetClientTeam(client) == L4D2Team_Infected)
		{
			if (GetPHRoundState() <= 1){
				CReplyToCommand(client, "{blue}只有在搜寻阶段才能传送!");
				return Plugin_Handled;
			}
			else if(cooldowntime < COOLDOWN_TIME_INF)
			{
				CReplyToCommand(client, "{blue}你需要等待 %.0f 秒后才能传送", COOLDOWN_TIME_INF - cooldowntime);
				return Plugin_Handled;
			}
		}
		float vpos[3], vAng[3];
		ProcessTeleport(client, vpos, vAng, targetper);
		f_ClientLastUsed[client] = GetGameTime();
		CReplyToCommand(client, "{blue}已经传送!");
	}
	return Plugin_Handled;
}


/**
 * 获取TP位置并传送,感谢l4d_predict_tank_glow
 */
void ProcessTeleport(int client, float vPos[3], float vAng[3], float Target)
{
    // 从 -12% 反方向获取位置
    for (float p = Target; p > 0.0; p -= 0.01)
    {
        TerrorNavArea nav = GetBossSpawnAreaForFlow(p);
        if (nav.Valid())
        {
            L4D_FindRandomSpot(view_as<int>(nav), vPos);
            vPos[2] -= 8.0; // less floating off ground
            
            vAng[0] = 0.0;
            vAng[1] = GetRandomFloat(0.0, 360.0);
            vAng[2] = 0.0;
            
            break;
        }
    }
    

    TeleportEntity(client, vPos, vAng, NULL_VECTOR);
}

TerrorNavArea GetBossSpawnAreaForFlow(float flow)
{
    float vPos[3];
    TheEscapeRoute().GetPositionOnPath(flow, vPos);
    
    TerrorNavArea nav = TerrorNavArea(vPos);
    if (!nav.Valid())
        return NULL_NAV_AREA;
    
    ArrayList aList = new ArrayList();
    while( !nav.IsValidForWanderingPopulation()
        || nav.m_isUnderwater
        || (nav.GetCenter(vPos), vPos[2] += 10.0, !ZombieManager.IsSpaceForZombieHere(vPos))
        || nav.m_activeSurvivors )
    {
        if (aList.FindValue(nav) != -1)
        {
            delete aList;
            return NULL_NAV_AREA;
        }
        
        if (nav.Valid())
            aList.Push(nav);
        
        nav = nav.GetNextEscapeStep();
    }
    
    delete aList;
    return nav;
}
