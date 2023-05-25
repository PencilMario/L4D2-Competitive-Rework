#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>
#include <mix_team>
#include <steamworks>


public Plugin myinfo = { 
    name = "noob only sv",
    author = "SirP, TouchMe",
    description = "",
    version = "0.1"
};

#define TRANSLATIONS            "mt_experience.phrases"

#define MIN_PLAYERS             6

// Other
#define APP_L4D2                550

// Macros
#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_REAL_CLIENT(%1)      (IsClientInGame(%1) && !IsFakeClient(%1))

#define L4D2_TEAM_SPECTATOR 1
#define L4D2_TEAM_SURVIVOR 2
#define L4D2_TEAM_INFECTED 3

float PlayRt[MAXPLAYERS + 1];
enum struct PlayerInfo {
    int id;
    float rating;
}

enum struct PlayerStats {
    int playedTime;
    int tankRocks;
    int gamesWon;
    int gamesLost;
    int killBySilenced;
    int killBySmg;
    int killByChrome;
    int killByPump;
}


/**
 * Loads dictionary files. On failure, stops the plugin execution.
 */
void InitTranslations()
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "translations/" ... TRANSLATIONS ... ".txt");

    if (FileExists(sPath)) {
        LoadTranslations(TRANSLATIONS);
    } else {
        SetFailState("Path %s not found", sPath);
    }
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 */
public void OnPluginStart() {
    InitTranslations();
    HookEvent("player_team", PlayerTeam_Event, EventHookMode_Post);
}



public void GetVoteDisplayMessage(int iClient, char[] sDisplayMsg) {
    Format(sDisplayMsg, DISPLAY_MSG_SIZE, "%T", "VOTE_DISPLAY_MSG", iClient);
}

public void OnClientConnected(int client){
    if(IsFakeClient(client)) return;
    PlayerInfo tPlayer;
    tPlayer.rating = CalculatePlayerRating(GetPlayerStats(client));
    PlayRt[client] = tPlayer.rating;
}

public void PlayerTeam_Event(Event event, const char[] name, bool dontBroadcast)
{

    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (!IsClientInGame(client) || IsFakeClient(client))
        return;

    int team = GetEventInt(event, "team");
    if (team == L4D2_TEAM_SPECTATOR)
        return;

    if (PlayRt[client] > 800){
        CPrintToChat(client, "[{green}!{default}] 你已经超出萌新水平了，你可以观战下饭或者找更合适你的服务器({olive}%.2f{default} > 800)", PlayRt[client]);
    }/*else{
        CPrintToChat(client, "[{green}!{default}] 本服为萌新ONLY服，享受互啄~(%.2f)", PlayRt[client])
    }*/
}

public void SteamWorks_OnValidateClient(int iOwnerAuthId, int iAuthId)
{
    int iClient = GetClientFromSteamID(iAuthId);

    if(IS_VALID_CLIENT(iClient)) {
        SteamWorks_RequestStats(iClient, APP_L4D2);
    }
}

any[] GetPlayerStats(int iClient)
{
    PlayerStats tPlayerStats;

    SteamWorks_GetStatCell(iClient, "Stat.TotalPlayTime.Total", tPlayerStats.playedTime);
    SteamWorks_GetStatCell(iClient, "Stat.SpecAttack.Tank", tPlayerStats.tankRocks);
    SteamWorks_GetStatCell(iClient, "Stat.GamesWon.Versus", tPlayerStats.gamesWon);
    SteamWorks_GetStatCell(iClient, "Stat.GamesLost.Versus", tPlayerStats.gamesLost);
    SteamWorks_GetStatCell(iClient, "Stat.smg_silenced.Kills.Total", tPlayerStats.killBySilenced);
    SteamWorks_GetStatCell(iClient, "Stat.smg.Kills.Total", tPlayerStats.killBySmg);
    SteamWorks_GetStatCell(iClient, "Stat.shotgun_chrome.Kills.Total", tPlayerStats.killByChrome);
    SteamWorks_GetStatCell(iClient, "Stat.pumpshotgun.Kills.Total", tPlayerStats.killByPump);

    return tPlayerStats;
}


public void MovePlayerToTeam(int client, int team)
{
    // No need to check multiple times if we're trying to move a player to a possibly full team.
    switch (team)
    {
        case L4D2_TEAM_SPECTATOR:
            ChangeClientTeam(client, L4D2_TEAM_SPECTATOR); 

        case L4D2_TEAM_SURVIVOR:
            FakeClientCommand(client, "jointeam 2");

        case L4D2_TEAM_INFECTED:
            ChangeClientTeam(client, L4D2_TEAM_INFECTED);
    }
}


float CalculatePlayerRating(PlayerStats tPlayerStats)
{
    float fPlayedHours = SecToHours(tPlayerStats.playedTime);

    if (fPlayedHours <= 0.0) {
        return 0.0;
    }

    int iKillTotal = tPlayerStats.killByChrome + tPlayerStats.killByPump + tPlayerStats.killBySilenced + tPlayerStats.killBySmg;
    float fRockPerHours = float(tPlayerStats.tankRocks) / fPlayedHours;
    int iVersusGame = tPlayerStats.gamesWon + tPlayerStats.gamesLost;
    float fWinRounds = 0.5;

    if(iVersusGame >= 700) {
        fWinRounds = float(tPlayerStats.gamesWon) / float(iVersusGame);
    }

    return fWinRounds * (0.55 * fPlayedHours + fRockPerHours + float(iKillTotal) * 0.005);
}



float SecToHours(int iSeconds) {
    return float(iSeconds) / 3600.0;
}

int GetClientFromSteamID(int authid)
{
    for(int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if(!IsClientConnected(iClient) || GetSteamAccountID(iClient) != authid) {
            continue;
        }

        return iClient;
    }

    return -1;
}