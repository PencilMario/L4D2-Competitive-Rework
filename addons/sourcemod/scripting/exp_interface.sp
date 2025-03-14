#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>
#include <SteamWorks>
#include <logger>

#define PTYPE_SMG 0
#define PTYPE_SHOTGUN 1
#define MAX_RETRY 12
#define RETRY_INTERVAL 1.0

#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)

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
    
    // 理论最高分
    int get_player_maxrankpoint(){
        return this.gametime + this.versustotal;
    }
    
    // 场均击杀
    float kill_per_round(){
        int kills = this.smgkills + this.shotgunkills;
        return float(kills) / float(this.versustotal);
    }
    
    float rock_per_round(){
        return float(this.tankrocks) / float(this.versustotal);
    }

    float hour_per_round(){
        return float(this.gametime) / float(this.versustotal);
    }
    
    // 击杀数修正
    void reset_max_kills(){
        if (this.kill_per_round() < 600.0) return;
        float per = 600.0 / this.kill_per_round();
        this.smgkills = RoundToNearest(float(this.smgkills) * per);
        this.shotgunkills = RoundToNearest(float(this.shotgunkills) * per);
    }
}

PlayerInfo PlayerInfoData[MAXPLAYERS];
int GetTimeOut[MAXPLAYERS] = {5};
Logger log;
Handle g_hForward_OnGetExp;
public void OnPluginStart(){
    log = new Logger("exp_interface", LoggerType_NewLogFile);
    log.IgnoreLevel = LogType_Info;
    if (log.FileSize > 1024*1024*5) log.DelLogFile();
    log.logfirst("exp interface log记录");

    for (int i = 1; i <= MaxClients; i++){
        if (IsClientInGame(i) && !IsFakeClient(i)){
            GetTimeOut[i] = MAX_RETRY;
            CreateTimer(0.1, Timer_GetClientExp, i);
        }
    }

}

public void OnClientPutInServer(int iClient)
{
	if(IS_VALID_CLIENT(iClient)) {
		GetTimeOut[iClient] = MAX_RETRY;
        CreateTimer(0.5, Timer_GetClientExp, iClient);
	}
}

public void OnClientAuthorized(int iClient)
{
    if (PlayerInfoData[iClient].rankpoint <= 0){
        OnClientPutInServer(iClient);
    }
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    g_hForward_OnGetExp = CreateGlobalForward("L4D2_OnGetExp", ET_Ignore, Param_Cell, Param_Cell);
    CreateNative("L4D2_GetClientExp", _Native_GetClientExp);
    CreateNative("L4D2_CheckAndGetAllClientExp", _Native_CheckAndGetAllClient);
    RegPluginLibrary("exp_interface");
    return APLRes_Success;
}
public int _Native_CheckAndGetAllClient(Handle plugin, int numParams)
{
    if (log.IgnoreLevel == LogType_Debug){
        char name[64];
        GetPluginFilename(plugin, name, sizeof(name));
        log.debug("\"%s\" 调用了 _Native_CheckAndGetAllClient()", name);
    }
    for (int i = 1; i <= MaxClients; i++){
        if (IsClientInGame(i) && !IsFakeClient(i)){
            if (PlayerInfoData[i].rankpoint <= 0){
                GetTimeOut[i] = MAX_RETRY;
                CreateTimer(0.1, Timer_GetClientExp, i);            }
        }
    }
    return 0;
}

public int _Native_GetClientExp(Handle plugin, int numParams){
    int client = GetNativeCell(1);
    if (log.IgnoreLevel == LogType_Debug){
        char name[64];
        GetPluginFilename(plugin, name, sizeof(name));
        log.debug("\"%s\" 调用了 _Native_GetClientExp(%i), return %i", 
            name, client, PlayerInfoData[client].rankpoint
        );
    }

    return PlayerInfoData[client].rankpoint;
}

public void ClearClientExpData(int client){
    PlayerInfoData[client].gametime = 0;
    PlayerInfoData[client].rankpoint = -2;
    PlayerInfoData[client].shotgunkills = 0;
    PlayerInfoData[client].smgkills = 0;
    PlayerInfoData[client].tankrocks = 0;
    PlayerInfoData[client].versuslose = 0;
    PlayerInfoData[client].versuswin = 0;
    PlayerInfoData[client].versustotal = 0;
    PlayerInfoData[client].winrounds = 0.0;
}
public Action Timer_GetClientExp(Handle timer, int iClient){
    GetTimeOut[iClient]--;
    ClearClientExpData(iClient);
    if (GetTimeOut[iClient] < 0) {
        log.warning("获取 %N 的信息时重试超时", iClient);
        return Plugin_Stop;
    }
    if (!IsClientInGame(iClient)){
        if (!IsClientConnected(iClient)){
            log.debug("%i 未连接, 不再尝试查询", iClient);
            return Plugin_Stop;
        } 
        log.debug("%i 不在游戏内, 重试%i", iClient, GetTimeOut[iClient]);
        CreateTimer(RETRY_INTERVAL, Timer_GetClientExp, iClient);
        return Plugin_Stop;
    }
    if (IsFakeClient(iClient)) return Plugin_Stop;
    int res = GetClientRP(iClient);
    if (res == -2) {
        CreateTimer(RETRY_INTERVAL, Timer_GetClientExp, iClient);
        return Plugin_Stop;
    }
    Call_StartForward(g_hForward_OnGetExp);
    Call_PushCell(iClient);
    Call_PushCell(res);
    Call_Finish();
    // global forward
    log.info("[%N] Total: %i, gametime: %i, rankpoint: %i, shotgunkills: %i, smgkills:%i, tankrocks: %i, versuswin: %i, versustotal：%i, maxrankpoint: %i, kill_per_round: %.0f, rock_per_round: %.0f, hour_per_round: %.0f", 
        iClient, res, 
        PlayerInfoData[iClient].gametime,
        PlayerInfoData[iClient].rankpoint,
        PlayerInfoData[iClient].shotgunkills,
        PlayerInfoData[iClient].smgkills,
        PlayerInfoData[iClient].tankrocks,
        PlayerInfoData[iClient].versuswin,
        PlayerInfoData[iClient].versustotal,
        PlayerInfoData[iClient].get_player_maxrankpoint(),
        PlayerInfoData[iClient].kill_per_round(),
        PlayerInfoData[iClient].rock_per_round(),
        PlayerInfoData[iClient].hour_per_round()
    );
    return Plugin_Stop;
}

public int GetClientRP(int iClient){
    PlayerInfoData[iClient].rankpoint = -2;
    SteamWorks_RequestStats(iClient, 550);
    bool status = SteamWorks_GetStatCell(iClient, "Stat.TotalPlayTime.Total", PlayerInfoData[iClient].gametime);
    if (!status) {
        log.debug("获取 %N 的数据信息时失败了, 但这也许是正常的...", iClient);
        return -2;
    }

    PlayerInfoData[iClient].gametime = PlayerInfoData[iClient].gametime/3600;
    status = SteamWorks_GetStatCell(iClient, "Stat.SpecAttack.Tank", PlayerInfoData[iClient].tankrocks) && 
    SteamWorks_GetStatCell(iClient, "Stat.GamesLost.Versus", PlayerInfoData[iClient].versuslose) &&
    SteamWorks_GetStatCell(iClient, "Stat.GamesWon.Versus", PlayerInfoData[iClient].versuswin);
    if (!status) {
        log.warning("获取 %N 的数据信息时失败了", iClient);
        return -2;
    }
    
    
    PlayerInfoData[iClient].versustotal = PlayerInfoData[iClient].versuslose + PlayerInfoData[iClient].versuswin;
    PlayerInfoData[iClient].smgkills = 0;
    PlayerInfoData[iClient].shotgunkills = 0;
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

int Calculate_RP(PlayerInfo tPlayer)
{
    int killtotal = tPlayer.shotgunkills + tPlayer.smgkills;
    float shotgunperc = float(tPlayer.shotgunkills) / float(killtotal);  
    float maxrp = float(tPlayer.get_player_maxrankpoint()) * 1.135; 
    float rp = 
        0.55 * float(tPlayer.gametime) * (tPlayer.hour_per_round() > 5.73 ? 5.73 / tPlayer.hour_per_round() : 1.0) + 
        float(tPlayer.tankrocks) * 0.65 * (tPlayer.rock_per_round() > 1.88 ? 1.88 / tPlayer.rock_per_round() : 1.0) + 
        (float(killtotal) * 0.005 * (tPlayer.kill_per_round() > 570.0 ? 570.0 / tPlayer.kill_per_round() : 1.0) * (shotgunperc));
    if (rp > maxrp) rp = maxrp;
    return RoundToNearest(rp);
}
