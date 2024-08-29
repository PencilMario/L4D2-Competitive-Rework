#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <l4d2util>
#include <left4dhooks>
#include <colors>
#include <sdkhooks>

#include <prophunt_single>

#define TIMER_INTERVAL 1.0
#define LEFT4FRAMEWORK_GAMEDATA "left4dhooks.l4d2"
#define SECTION_NAME "CTerrorGameRules::SetCampaignScores"
Handle hSetCampaignScores;
enum struct PlayerData{
    int roundscore;
	int alivetime;
	int close_tank_time;

	// 如果为0, 则意味着生还者未锁定
	int real_model_index;
	float real_model_pos[3];

	void AliveAddscore(int scores){
		this.roundscore += scores;
		this.alivetime += RoundToNearest(TIMER_INTERVAL);
	}
	void CloseTankAddscore(int scores){
		this.roundscore += scores;
		this.close_tank_time += RoundToNearest(TIMER_INTERVAL);
	}
}

PlayerData PlayersData[MAXPLAYERS];
public Plugin myinfo =
{
	name		= "L4D2 Prop Hunt",
	author		= "Sir.P",
	description = "躲猫猫玩法 - 队伍积分",
	version		= "0.0.0",
	url			= "null"
};
public void OnPluginStart(){
	LoadSDK();
}
void ClearPlayersData(int client){
	PlayersData[client].roundscore = 0;
	PlayersData[client].alivetime = 0;
	PlayersData[client].close_tank_time = 0;
	PlayersData[client].real_model_index = 0;
	PlayersData[client].real_model_pos = NULL_VECTOR;
}
public void OnSeekingStage_Post(){
	for (int i = 1; i <= MaxClients; i++){
		ClearPlayersData(i);
	}
	CreateTimer(TIMER_INTERVAL, Timer_HuntScoreMain, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}
public Action Timer_HuntScorePrint(Handle timer){
		int mvp, hidemvp, runmvp, minmvp = 0;
		int mvpmax, hidemvpmax, runmvpmax = 0;
		int min = 99999;
		for (int i = 1; i <= MaxClients; i++){
			if (!IsClientInGame(i)) continue;
			if (PlayersData[i].roundscore > mvpmax){
				mvp = i;
				mvpmax = PlayersData[i].roundscore;
			}
			if (PlayersData[i].alivetime > hidemvpmax){
				hidemvp = i;
				hidemvpmax = PlayersData[i].alivetime;
			}
			if(PlayersData[i].alivetime < min && PlayersData[i].alivetime > 0)
			{
				minmvp = i;
				min = PlayersData[i].alivetime;
			}
			if (PlayersData[i].close_tank_time > runmvpmax){
				runmvp = i;
				runmvpmax = PlayersData[i].close_tank_time;
			}
		}
		CPrintToChatAll("[{blue}Hide and Seek{default}] 生还者得分:");
		CPrintToChatAll("[{blue}MVP{default}] {green}%N {blue}(%i分)", mvp, mvpmax);
		CPrintToChatAll("[{blue}躲藏MVP{default}] {green}%N {blue}(%i秒)", hidemvp, hidemvpmax);
		CPrintToChatAll("[{blue}溜克MVP{default}] {green}%N {blue}(%i分)", runmvp, runmvpmax);
		CPrintToChatAll("[{blue}躲猫猫速通{default}] {green}%N {blue}(%i秒)", minmvp, min);
		for (int i = 1; i <= MaxClients; i++){
			if (IsClientInGame(i) && GetClientTeam(i)==L4D2Team_Survivor){
				CPrintToChat(i, "[{blue}你的表现{default}] {blue}%i{default}分 (生存{green}%i{default}s / 溜克{green}%i{default}分)", PlayersData[i].roundscore, PlayersData[i].alivetime, PlayersData[i].close_tank_time);
			}
		}
		
	return Plugin_Stop;
}

public Action Timer_HuntScoreMain(Handle timer){
	// 确认模式
	if (GetPHRoundState() == 3){
		// 输出stat
		CreateTimer(3.5, Timer_HuntScorePrint);
		return Plugin_Stop;
	}
	else if(GetPHRoundState() != 2) return Plugin_Stop;

	// 计算生还者队伍分数
	int loop_total_score = 0;
	int alive_score = 1;
	int tank_close_score = 1;
	int SurvivorTeamIndex = GameRules_GetProp("m_bAreTeamsFlipped");
	int InfectedTeamIndex = SurvivorTeamIndex ? 0 : 1;
	for(int i = 1; i <= MaxClients; i++){
		if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i)==L4D2Team_Survivor){
			PlayersData[i].AliveAddscore(alive_score);
			loop_total_score += alive_score;
			int tank_count = 0;
			float tankpos[3], survpos[3];
			// 生还者的坐标
			if (PlayersData[i].real_model_index != 0){
				CopyVectors(PlayersData[i].real_model_pos, survpos);
			}else{
				GetClientEyePosition(i, survpos);
			}
			// tank坐标及对比
			for (int j = 1; j <= MaxClients; j++){
				if (IsClientInGame(j) && IsPlayerAlive(j) && GetClientTeam(j) == L4D2Team_Infected && L4D2_GetPlayerZombieClass(j) == L4D2Infected_Tank){
					GetClientEyePosition(j, tankpos);
					if (GetVectorDistance(survpos, tankpos) <= 1500.0) {
						tank_count++;
						PlayersData[i].CloseTankAddscore(tank_count * tank_close_score);
					}
				}
			}
			loop_total_score += tank_count * tank_close_score;
		}
	}

	SetScores(L4D2Direct_GetVSCampaignScore(SurvivorTeamIndex) + loop_total_score, L4D2Direct_GetVSCampaignScore(InfectedTeamIndex));
	return Plugin_Continue;
}

void LoadSDK()
{
	Handle conf = LoadGameConfigFile(LEFT4FRAMEWORK_GAMEDATA);
	if (conf == INVALID_HANDLE) {
		SetFailState("Could not load gamedata/%s.txt", LEFT4FRAMEWORK_GAMEDATA);
	}

	StartPrepSDKCall(SDKCall_GameRules);
	if (!PrepSDKCall_SetFromConf(conf, SDKConf_Signature, SECTION_NAME)) {
		SetFailState("Function '" ... SECTION_NAME ... "' not found.");
	}
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	hSetCampaignScores = EndPrepSDKCall();
	if (hSetCampaignScores == INVALID_HANDLE) {
		SetFailState("Function '" ... SECTION_NAME ... "' found, but something went wrong.");
	}
	
	delete conf;
}

void SetScores(const int survScore, const int infectScore)
{
	//Determine which teams are which
	bool bFlipped = !!GameRules_GetProp("m_bAreTeamsFlipped");
	int SurvivorTeamIndex = bFlipped ? 1 : 0;
	int InfectedTeamIndex = bFlipped ? 0 : 1;
	
	//Set the scores
	SDKCall(hSetCampaignScores,
				(bFlipped) ? infectScore : survScore,
				(bFlipped) ? survScore : infectScore); //visible scores
	L4D2Direct_SetVSCampaignScore(SurvivorTeamIndex, survScore); //real scores
	L4D2Direct_SetVSCampaignScore(InfectedTeamIndex, infectScore);
}
public void OnCreateRealProp_Post(int client, int entity){
	PlayersData[client].real_model_index = entity;
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", PlayersData[client].real_model_pos);
}

public void OnEntityDestroyed(int entity){
	for(int i = 1; i <= MaxClients; i++){
		if (PlayersData[i].real_model_index == entity){
			PlayersData[i].real_model_index = 0;
		}
	}
}

stock void CopyVectors(float origin[3], float result[3])
{
	result[0] = origin[0];
	result[1] = origin[1];
	result[2] = origin[2];
}