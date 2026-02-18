#include <sourcemod>

#define PLUGIN_NAME				"[L4D2] Remove Lobby Reservation"
#define PLUGIN_AUTHOR			"Downtown1, Anime4000, sorallll, lakwsh"
#define PLUGIN_DESCRIPTION		"Removes lobby reservation when server is full"
#define PLUGIN_VERSION			"2.1.2"
#define PLUGIN_URL				"http://forums.alliedmods.net/showthread.php?t=87759"

ConVar g_cvUnreserve, g_cvGameMode, g_cvCookie, g_cvLobbyOnly, g_cvMaxPlayers, g_cvForceUnreserse, g_cvAutoRemoveLimit;
bool g_bUnreserve;

int g_iLobbySlot;
public Plugin myinfo = {
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};
//StringToInt64
// 设置cookies的方式：
//
//
/*
	
	ValidateAddress(g_pServer, "g_pServer");
	ValidateNatives(g_hSDK_CBaseServer_SetReservationCookie, "CBaseServer::SetReservationCookie");
 */

/**
 * #define GAMEDATA_1							"left4dhooks.l4d1"
	#define GAMEDATA_2							"left4dhooks.l4d2"

 * 
 * 	BuildPath(Path_SM, sPath, sizeof(sPath), "gamedata/%s.txt", g_bLeft4Dead2 ? GAMEDATA_2 : GAMEDATA_1);
	if( FileExists(sPath) == false ) SetFailState("\n==========\nMissing required file: \"%s\".\nRead installation instructions again.\n==========", sPath);
	SDKCall(g_hSDK_CBaseServer_SetReservationCookie, g_pServer, 0, 0, "Unreserved by Left 4 DHooks");
*/
/*

	GameData hGameData = g_hGameData;

 * 	StartPrepSDKCall(SDKCall_Static); // Since SM 1.11 can use "SDKCall_Server" (but that crashes the server)
	if( PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "CBaseServer::SetReservationCookie") == false )
	{
		LogError("Failed to find signature: \"CBaseServer::SetReservationCookie\" (%s)", g_sSystem);
	} else {
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		g_hSDK_CBaseServer_SetReservationCookie = EndPrepSDKCall();
		if( g_hSDK_CBaseServer_SetReservationCookie == null )
			LogError("Failed to create SDKCall: \"CBaseServer::SetReservationCookie\" (%s)", g_sSystem);
	}
 */
public void OnPluginStart() {
	CreateConVar("l4d_unreserve_version", PLUGIN_VERSION, "Version of the Lobby Unreserve plugin.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_cvUnreserve = CreateConVar("l4d_unreserve_full", "1", "Automatically unreserve server after a full lobby joins", FCVAR_SPONLY|FCVAR_NOTIFY);
	g_cvAutoRemoveLimit = CreateConVar("l4d_unreserve_autoremove_whenplayer", "-1", "Automatically unreserve server after a full lobby joins");
	g_cvUnreserve.AddChangeHook(CvarChanged);
	g_cvGameMode = FindConVar("mp_gamemode");
	g_cvCookie = FindConVar("sv_lobby_cookie");
	g_cvLobbyOnly = FindConVar("sv_allow_lobby_connect_only");
	g_cvMaxPlayers = FindConVar("sv_maxplayers");
	g_cvForceUnreserse = FindConVar("sv_force_unreserved");
	HookConVarChange(g_cvAutoRemoveLimit, Convar_OnLimitSet);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

	RegAdminCmd("sm_unreserve", cmdUnreserve, ADMFLAG_BAN, "sm_unreserve - manually force removes the lobby reservation");
}

Action cmdUnreserve(int client, int args) {
	ServerCommand("sv_cookie 0");
	g_cvForceUnreserse.IntValue = 1;
	ReplyToCommand(client, "[UL] Lobby reservation has been removed.");
	return Plugin_Handled;
}

public void OnConfigsExecuted() {
	GetCvars();
}

void CvarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	GetCvars();
}
void Convar_OnLimitSet(Handle cvar, const char[] oldValue, const char[] newValue){
	for (int i = 0; i <= MaxClients; i++){
		if (IsClientInGame(i))
		{
			OnClientAuthorized(i, "1");
			break;
		}
	}
	
}

void GetCvars() {
	g_bUnreserve = g_cvUnreserve.BoolValue;
}

public void OnClientAuthorized(int client, const char[] auth) {
	if (!g_bUnreserve || g_cvMaxPlayers.IntValue == -1)
		return;

	if (IsFakeClient(client))
		return;

	if (!IsServerLobbyFull(-1))
		return;
	ServerCommand("sv_cookie 0");
}

//OnClientDisconnect will fired when changing map, issued by gH0sTy at http://docs.sourcemod.net/api/index.php?fastload=show&id=390&
void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	if (g_cvForceUnreserse.BoolValue) {
		ServerCommand("sv_cookie 0")
		return;
	}
	if (g_cvMaxPlayers.IntValue == -1)
		return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client)
		return;

	if (IsFakeClient(client))
		return;

	if (!GetConnectedPlayer(client))
	{
		g_cvCookie.SetString("0");
		g_cvLobbyOnly.SetInt(1);
		return;
	}

	if (IsServerLobbyFull(client))
		return;

	char sCookie[20];
	g_cvCookie.GetString(sCookie, sizeof(sCookie));
	if (StrEqual(sCookie, "0"))
		return;
	ServerCommand("sv_cookie %s", sCookie);
}

void SetDefaultLobbySlot(){
	char sGameMode[32];
	g_cvGameMode.GetString(sGameMode, sizeof(sGameMode));
	if (StrEqual(sGameMode, "versus") || StrEqual(sGameMode, "scavenge"))
	{
		g_iLobbySlot = 8;
	}
	g_iLobbySlot = 4;
}

bool IsServerLobbyFull(int client)
{
	
	int humans = GetConnectedPlayer(client);
	SetDefaultLobbySlot();
	/*
	char sGameMode[32];
	g_cvGameMode.GetString(sGameMode, sizeof(sGameMode));
	if (StrEqual(sGameMode, "versus") || StrEqual(sGameMode, "scavenge"))
	{
		return humans >= 8;
	}
	return humans >= 4;
	*/
	return humans >= (g_cvAutoRemoveLimit.IntValue == -1 ? g_iLobbySlot : g_cvAutoRemoveLimit.IntValue);
}

int GetConnectedPlayer(int client) {
	int count;
	for (int i = 1; i <= MaxClients; i++) {
		if (i != client && IsClientAuthorized(i) && !IsFakeClient(i))
			count++;
	}
	return count;
}
