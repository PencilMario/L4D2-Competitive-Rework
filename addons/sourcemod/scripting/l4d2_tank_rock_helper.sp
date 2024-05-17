#pragma semicolon 1
#pragma newdecls required


#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

int g_iTankRockOwner[MAXPLAYERS];

enum struct TankRock {
    float pos[3];
    float ang[3];
}
ArrayList g_iRockThrowQueue;
TankRock g_iTankTrace[MAXPLAYERS][50];
float g_fClientViewang[MaxClients][3];
public Plugin myinfo = 
{
	name = "[L4D2] tank 计算石头轨迹",
	author = "Sir.P",
	description = "在tank丢饼时，计算石头的轨迹和落点",
	version = "1.0.1",
	url = "https://github.com/SirPlease/L4D2-Competitive-Rework"
}
public void OnPluginStart(){
    g_iRockThrowQueue = new ArrayList();
}
public void OnPluginEnd(){
    CloseHandle(g_iRockThrowQueue);
}
public void L4D2_OnSelectTankAttack(int client, int &sequence){
    if (sequence>=48)
    g_iRockThrowQueue.Push(client);
}

public void OnEntityCreated(int Entity, char[] Classname)
{
    if (!strcmp(Classname, "tank_rock")) return;
    int owner = g_iRockThrowQueue.Get(0);
    if (owner) {
        g_iRockThrowQueue.Erase(0);
    }
    g_iTankRockOwner[owner] = Entity;
    // Hook石头 OnThrowing
}

int GetWhoOwnedRock(int ientity){
    for (int i = 1; i <= MaxClients; i++){
        if (IsClientInGame(i)){
            if (g_iTankRockOwner[i] == ientity) return i;
        }
    }
    return 0;
}

public MRESReturn OnThrowing(int pThis, DHookReturn hReturn){
    int client = GetWhoOwnedRock(pThis);
    if (!IsClientInGame(client)) return MRES_Ignored;
    //获取当前玩家视线方向矢量
    GetClientEyeAngles(client, g_fClientViewang[client]);
    GetAngleVectors(g_fClientViewang[client], g_fClientViewang[client], NULL_VECTOR, NULL_VECTOR);
    //计算tank出手力度
    ResetVectorLength(g_fClientViewang[client], 800.0);
    return MRES_Ignored;
}
TankRock GetRockPos(float startpos[3], float rockvel[3], float time){
    TankRock result;
    result.pos[0] = startpos[0] + rockvel[0] * time;
    result.pos[1] = startpos[1] + rockvel[1] * time;
    result.pos[2] = startpos[2] + rockvel[2] * time;

    result.ang = rockvel;
    result.ang[3] -= 800.0 * time;
    return result;
}
void ResetVectorLength(float vector[3], float targetlength){
    float currentLength = GetVectorLength(vector);
    float factor = targetlength / currentLength;
    vector[0] = vector[0] * factor;
    vector[1] = vector[1] * factor;
    vector[2] = vector[2] * factor;
}