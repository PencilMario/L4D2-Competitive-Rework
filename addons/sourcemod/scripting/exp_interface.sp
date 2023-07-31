#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>
#include <mix_team>
#include <SteamWorks>
#include <logger>

#define SW_GetStatFail -2;
#define PTYPE_SMG 0
#define PTYPE_SHOTGUN 1

enum struct PlayerInfo{
    int rankpoint;
    int gametime;	
    int tankrocks;	
    float winrounds;
    int versustotal;
    int versuswin;
    int versuslose;
    int smgkills;
    int shotgunkills;
    int type;
}

PlayerInfo PlayerInfoData[MAXPLAYERS];
int GetTimeOut[MAXPLAYERS] = {5};
Logger log;
Handle g_hForward_OnGetExp;
public void OnPluginStart(){
    log = new Logger("exp_interface");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_hForward_OnGetExp = CreateGlobalForward("L4D2_OnGetExp", ET_Ignore, Param_String, Param_Cell, Param_Cell);
	CreateNative("L4D2_GetClientExp", _Native_GetTotalPlaytime);
	return APLRes_Success;
}

public void OnClientAuthorized(int client, const char[] auth){
    CreateTimer()
}

public void Timer_GetClientExp(Handle timer, int iClient){
    int res = GetClientRP(iClient);
    if (res == SW_GetStatFail) return Plugin_Continue;

    // global forward
    return Plugin_Stop;
}

public int GetClientRP(int iClient){
    PlayerInfoData[iClient].rankpoint = SW_GetStatFail;
    SteamWorks_RequestStats(iClient, 550);
    bool status = SteamWorks_GetStatCell(iClient, "Stat.TotalPlayTime.Total", PlayerInfoData[iClient].gametime);
    if (!status) return SW_GetStatFail;
    PlayerInfoData[iClient].gametime = PlayerInfoData[iClient].gametime/3600;
    SteamWorks_GetStatCell(iClient, "Stat.SpecAttack.Tank", PlayerInfoData[iClient].tankrocks);
    SteamWorks_GetStatCell(iClient, "Stat.GamesLost.Versus", PlayerInfoData[iClient].versuslose);
    SteamWorks_GetStatCell(iClient, "Stat.GamesWon.Versus", PlayerInfoData[iClient].versuswin);
    PlayerInfoData[iClient].versustotal = PlayerInfoData[iClient].versuslose + PlayerInfoData[iClient].versuswin;
    PlayerInfoData[iClient].smgkills = 0;
    int t_kills;
    SteamWorks_GetStatCell(iClient, "Stat.smg_silenced.Kills.Total", t_kills);
    PlayerInfoData[iClient].smgkills += t_kills;
    SteamWorks_GetStatCell(iClient, "Stat.smg.Kills.Total", t_kills);
    PlayerInfoData[iClient].smgkills += t_kills;
    SteamWorks_GetStatCell(iClient, "Stat.shotgun_chrome.Kills.Total", t_kills);
    PlayerInfoData[iClient].shotgunkills += t_kills;
    SteamWorks_GetStatCell(iClient, "Stat.pumpshotgun.Kills.Total", t_kills);
    PlayerInfoData[iClient].shotgunkills += t_kills;
    PlayerInfoData[iClient].winrounds = float(PlayerInfoData[iClient].versuswin) / float(PlayerInfoData[iClient].versustotal);
    if(PlayerInfoData[iClient].versustotal < 700) PlayerInfoData[iClient].winrounds = 0.5;
    PlayerInfoData[iClient].rankpoint = Calculate_RP(PlayerInfoData[iClient]);
    if (PlayerInfoData[iClient].shotgunkills > PlayerInfoData[iClient].smgkills){
        PlayerInfoData[iClient].type = PTYPE_SHOTGUN;
    }else{
        PlayerInfoData[iClient].type = PTYPE_SMG;
    }
    return PlayerInfoData[iClient].rankpoint;
}

int Calculate_RP(Player tPlayer)
{
    int killtotal = tPlayer.shotgunkills + tPlayer.smgkills;
    float shotgunperc = float(tPlayer.shotgunkills) / float(killtotal);   
    float rpm = float(tPlayer.tankrocks) / float(tPlayer.gametime);
    rpm = 1.0 + rpm;
    float rp = tPlayer.winrounds * (0.55 * float(tPlayer.gametime) + float(tPlayer.tankrocks) * rpm * 0.65 + 
        float(killtotal) * 0.005 * (1.0 + shotgunperc));
    return RoundToNearest(rp);
}
