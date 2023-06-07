#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <sdktools>

#include "include/nativevotes_rework"


public Plugin myinfo = {
	name = "FixVotePoll",
	author = "raziEiL [disawar1]",
	description = "Changes number of players eligible to vote",
	version = "build_0001",
	url = "https://github.com/TouchMe-Inc/l4d2_nativevotes_rework"
}


#define TRANSLATION_LENGTH      192
#define L4D_VOTE_CUSTOM         "#L4D_TargetID_Player"


int g_iVoteController = INVALID_ENT_REFERENCE;

bool g_bVotePoolFixTriggered = false;


/**
 * Called before OnPluginStart.
 * 
 * @param myself      Handle to the plugin
 * @param late        Whether or not the plugin was loaded "late" (after map load)
 * @param error       Error message buffer in case load failed
 * @param err_max     Maximum number of characters for error message buffer
 * @return            APLRes_Success | APLRes_SilentFailure 
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();

	if (engine != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	HookUserMessage(GetUserMessageId("VoteStart"), Message_VoteStart);
	HookUserMessage(GetUserMessageId("VotePass"), Message_VotePass);
	HookUserMessage(GetUserMessageId("VoteFail"), Message_VoteFail);

	AddCommandListener(Listener_Vote, "vote");
}

public void OnMapStart()
{
	if ((g_iVoteController = FindVoteController()) == INVALID_ENT_REFERENCE) {
		SetFailState("VoteController not found!");
	}
}

public Action Listener_Vote(int iClient, const char[] command, int argc)
{
	if (!g_bVotePoolFixTriggered) {
		return Plugin_Continue;
	}

	if (IsClientInGame(iClient) && GetClientTeam(iClient) == NATIVEVOTES_TEAM_SPECTATOR) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

/*
VoteStart Structure
	- Byte      Team index or -1 for all
	- Byte      Initiator client index (or 99 for Server?)
	- String    Vote issue phrase
	- String    Vote issue phrase argument
	- String    Initiator name

*/
public Action Message_VoteStart(UserMsg msg_id, BfRead bfMessage, const int[] players, int playersNum, bool reliable, bool init)
{
	if (!HasSpectator()) {
		return Plugin_Continue;
	}

	int iTeam = bfMessage.ReadByte();

	if (iTeam != NATIVEVOTES_ALL_TEAMS) {
		return Plugin_Continue;
	}

	char sTranslate[TRANSLATION_LENGTH];
	bfMessage.ReadByte();
	bfMessage.ReadString(sTranslate, TRANSLATION_LENGTH);

	if (StrEqual(sTranslate, L4D_VOTE_CUSTOM))
	{
		g_bVotePoolFixTriggered = false;
		return Plugin_Continue;
	}

	g_bVotePoolFixTriggered = true;

	SetEntProp(g_iVoteController, Prop_Send, "m_potentialVotes", GetTotalPlayers());

	return Plugin_Continue;
}

/*
VotePass Structure
	- Byte      Team index or -1 for all
	- String    Vote issue pass phrase
	- String    Vote issue pass phrase argument

*/
public Action Message_VotePass(UserMsg msg_id, BfRead bfMessage, const int[] players, int playersNum, bool reliable, bool init)
{
	g_bVotePoolFixTriggered = false;
	return Plugin_Continue;
}

/*
VoteFail Structure
	- Byte      Team index or -1 for all

*/  
public Action Message_VoteFail(UserMsg msg_id, BfRead bfMessage, const int[] players, int playersNum, bool reliable, bool init)
{
	g_bVotePoolFixTriggered = false;
	return Plugin_Continue;
}

int GetTotalPlayers()
{
	int iPlayerCount = 0;

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IsClientInGame(iClient)
		&& !IsFakeClient(iClient)
		&& GetClientTeam(iClient) != NATIVEVOTES_TEAM_SPECTATOR) {
			iPlayerCount++;
		}
	}

	return iPlayerCount;
}

bool HasSpectator()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IsClientInGame(iClient)
		&& !IsFakeClient(iClient)
		&& GetClientTeam(iClient) == NATIVEVOTES_TEAM_SPECTATOR) {
			return true;
		}
	}

	return false;
}

int FindVoteController()
{
	int entity = FindEntityByClassname(-1, "vote_controller");

	if (entity != -1) {
		return EntIndexToEntRef(entity);
	}

	return INVALID_ENT_REFERENCE;
}
