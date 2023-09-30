/*
 ----------------------------------------------------------------
 Plugin      : SaveChat 
 Author      : citkabuto
 Game        : Any Source game
 Description : Will record all player messages to a file
 ================================================================
 Date       Version  Description
 ================================================================
 23/Feb/10  1.2.1    - Fixed bug with player team id
 15/Feb/10  1.2.0    - Now records team name when using cvar
                            sm_record_detail 
 01/Feb/10  1.1.1    - Fixed bug to prevent errors when using 
                       HLSW (client index 0 is invalid)
 31/Jan/10  1.1.0    - Fixed date format on filename
                       Added ability to record player info
                       when connecting using cvar:
                            sm_record_detail (0=none,1=all:def:1)
 28/Jan/10  1.0.0    - Initial Version 
 ----------------------------------------------------------------
*/

#include <sourcemod>
#include <sdktools>
#include <geoip.inc>
#include <string.inc>
#include <logger>
#include <left4dhooks>
#include <exp_interface>

#define PLUGIN_VERSION "SaveChat_1.2.1"

static String:chatFile[128]
new Handle:sc_record_detail = INVALID_HANDLE
Logger log, exp;
public Plugin:myinfo = 
{
	name = "SaveChat",
	author = "citkabuto",
	description = "Records player chat messages to a file",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=117116"
}

public OnPluginStart()
{
	new String:date[21]

	/* Register CVars */
	CreateConVar("sm_savechat_version", PLUGIN_VERSION, "Save Player Chat Messages Plugin", 
		FCVAR_DONTRECORD|FCVAR_REPLICATED)

	sc_record_detail = CreateConVar("sc_record_detail", "1", 
		"Record player Steam ID and IP address")

	/* Say commands */
	RegConsoleCmd("say", Command_Say)
	RegConsoleCmd("say_team", Command_SayTeam)
	/* Format date for log filename */
	FormatTime(date, sizeof(date), "%y%m%d", -1)


	Format(chatFile, 48, "Chat%s", date)
	log = new Logger(chatFile, LoggerType_NewLogFile);
	exp = new Logger(chatFile, LoggerType_NewLogFile);
	exp.SetLogPrefix("exp_interface");
}

/*
 * Capture player chat and record to file
 */
public Action:Command_Say(client, args)
{
	LogChat(client, args, false)
	return Plugin_Continue
}

/*
 * Capture player team chat and record to file
 */
public Action:Command_SayTeam(client, args)
{
	LogChat(client, args, true)
	return Plugin_Continue
}

public OnClientPostAdminCheck(client)
{
	/* Only record player detail if CVAR set */
	if(GetConVarInt(sc_record_detail) != 1)
		return

	if(IsFakeClient(client)) 
		return

	new String:msg[2048]
	new String:country[3]
	new String:steamID[128]
	new String:playerIP[50]
	
	GetClientAuthString(client, steamID, sizeof(steamID))

	/* Get 2 digit country code for current player */
	if(GetClientIP(client, playerIP, sizeof(playerIP), true) == false) {
		country   = "  "
	} else {
		if(GeoipCode2(playerIP, country) == false) {
			country = "  "
		}
	}
	bool isADM;
	AdminId id = GetUserAdmin(client);
	isADM = GetAdminFlag(id, Admin_Generic);


	Format(msg, sizeof(msg), "[%s] %N 进入游戏 ('%s' | '%s'%s)",
		country,
		client,
		steamID,
		playerIP,
		isADM ? " | 管理员" : ""
		)

	log.info(msg)
}
public void OnClientDisconnect(int client){
		/* Only record player detail if CVAR set */
	if(GetConVarInt(sc_record_detail) != 1)
		return

	if(IsFakeClient(client)) 
		return

	new String:msg[2048]
	new String:country[3]
	new String:steamID[128]
	new String:playerIP[50]
	
	GetClientAuthString(client, steamID, sizeof(steamID))

	/* Get 2 digit country code for current player */
	if(GetClientIP(client, playerIP, sizeof(playerIP), true) == false) {
		country   = "  "
	} else {
		if(GeoipCode2(playerIP, country) == false) {
			country = "  "
		}
	}
	bool isADM;
	AdminId id = GetUserAdmin(client);
	isADM = GetAdminFlag(id, Admin_Generic);


	Format(msg, sizeof(msg), "[%s] %N 离开游戏 ('%s' | '%s'%s)",
		country,
		client,
		steamID,
		playerIP,
		isADM ? " | 管理员" : ""
		)

	log.info(msg)

}
/*
 * Extract all relevant information and format 
 */
public LogChat(client, args, bool:teamchat)
{
	new String:msg[2048]
	new String:text[1024]
	new String:country[3]
	new String:playerIP[50]
	new String:teamName[20]

	GetCmdArgString(text, sizeof(text))
	StripQuotes(text)

	if(client == 0) {
		/* Don't try and obtain client country/team if this is a console message */
		Format(country, sizeof(country), "  ")
		Format(teamName, sizeof(teamName), "")
	} else {
		/* Get 2 digit country code for current player */
		if(GetClientIP(client, playerIP, sizeof(playerIP), true) == false) {
			country   = "  "
		} else {
			if(GeoipCode2(playerIP, country) == false) {
				country = "  "
			}
		}
		GetTeamName(GetClientTeam(client), teamName, sizeof(teamName))
	}

	if(GetConVarInt(sc_record_detail) == 1) {
		Format(msg, sizeof(msg), "[%s] [%s] %N :%s %s",
			country,
			teamName,
			client,
			teamchat == true ? " (TEAM)" : "",
			text)
	} else {
		Format(msg, sizeof(msg), "[%s] %N :%s '%s'",
			country,
			client,
			teamchat == true ? " (TEAM)" : "",
			text)
	}


	log.info(msg)
}
/*
 * Log a map transition
 */
public OnMapStart(){
	new String:map[128]
	char cfg[64];
	ConVar config = FindConVar("l4d_ready_cfg_name")
	GetConVarString(config != INVALID_HANDLE ? config : FindConVar("mp_gamemode"), cfg, sizeof(cfg))
	GetCurrentMap(map, sizeof(map))

	log.lograw("--=================================================================--")
	log.info(  "* 地图 >>> '%s'   ", 		map);
	log.info(  "* 配置文件: '%s'", 			cfg);
	log.info(  "* 比分 %i : %i", 			L4D2Direct_GetVSCampaignScore(GameRules_GetProp("m_bAreTeamsFlipped")), L4D2Direct_GetVSCampaignScore(!GameRules_GetProp("m_bAreTeamsFlipped")));
	log.lograw("----------------------------------")
}

public void L4D2_OnGetExp(int client, int e){
	exp.info("'%N' 的经验分为 %i", client, e);
}