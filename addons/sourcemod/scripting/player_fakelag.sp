#pragma semicolon 1
#pragma newdecls required

#include <custom_fakelag>
#include <console>
#include <colors>
#include <builtinvotes>

#define PLUGIN_VERSION			"1.3"
#define PLUGIN_NAME			    "player_fakelag"
#define ABS(%0) (((%0) < 0) ? -(%0) : (%0))

#define FAKELAG_BOTTOM	0
#define FAKELAG_TOP		400

public Plugin myinfo = 
{
	name = PLUGIN_NAME,
	author = "ProdigySim, Bred",
	description = "Set a custom fake latency per player",
	version = PLUGIN_VERSION,
	url = "https://github.com/ProdigySim/custom_fakelag"
};

ConVar survivor_limit;

ArrayList lowteamplayers;

Handle hVoteEFakelag = null;

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("player_fakelag.phrases");
	
	survivor_limit = FindConVar("survivor_limit");
	
	RegAdminCmd("sm_fakelag", FakeLagCmd, ADMFLAG_CONFIG, "Set fake lag for a player");
	RegAdminCmd("sm_fl", FakeLagCmd, ADMFLAG_CONFIG, "Set fake lag for a player");
	
	RegConsoleCmd("sm_printlag", PrintLagCmd,  "Print Current FakeLag");
	RegConsoleCmd("sm_ping", PrintLagCmd,  "Print Current FakeLag");
	RegConsoleCmd("sm_pings", PrintLagCmd,  "Print Current FakeLag");
	
	RegConsoleCmd("sm_myfakelag", MyFakeLagCmd, "Set fake lag for yourself");
	RegConsoleCmd("sm_myfl", MyFakeLagCmd, "Set fake lag for yourself");
	
	RegConsoleCmd("sm_equalizefakelag", EFakeLagVoteCmd, "Equalize fakelags of all player");
	RegConsoleCmd("sm_efl", EFakeLagVoteCmd, "Equalize fakelags of all player");
	RegConsoleCmd("sm_epings", EFakeLagVoteCmd, "Equalize fakelags of all player");
	RegConsoleCmd("sm_eping", EFakeLagVoteCmd, "Equalize fakelags of all player");
}

public Action FakeLagCmd(int client, int args) 
{
	if(args != 2) 
	{
		CReplyToCommand(client, "%t", "Usage");
		return Plugin_Handled;
	}
	
	char targetStr[256];
	GetCmdArg(1, targetStr, sizeof(targetStr));
	int target = FindTarget(client, targetStr, true);
	if(target < 0) 
	{
		CReplyToCommand(client, "%t", "No_Target");
		return Plugin_Handled;
	}
	if(!IsClientInGame(target)) 
	{
		CReplyToCommand(client, "%t", "Not_Ingame", target);
		return Plugin_Handled;
	}
	if (IsFakeClient(target)) 
	{
		CReplyToCommand(client, "%t", "Fake_Client", target);
		return Plugin_Handled;
	}

	int lagAmount = GetCmdArgInt(2);
	
	if (FAKELAG_BOTTOM <= lagAmount <= FAKELAG_TOP )
	{
		CFakeLag_SetPlayerLatency(target, lagAmount * 1.0);
		CPrintToChatAllEx(target, "%t", "Set_Fakelag", lagAmount, client, target);
		return Plugin_Handled;
	}
	
	CPrintToChat(client, "%t", "InValid_Fakelag", FAKELAG_BOTTOM, FAKELAG_TOP);
	return Plugin_Handled;
}

public Action MyFakeLagCmd(int client, int args) 
{
	if(args != 1) 
	{
		CReplyToCommand(client, "%t", "Usage_Myfl");
		return Plugin_Handled;
	}
	
	int lagAmount = GetCmdArgInt(1);
	
	if (FAKELAG_BOTTOM <= lagAmount <= FAKELAG_TOP )
	{
		CFakeLag_SetPlayerLatency(client, lagAmount * 1.0);
		CPrintToChatAllEx(client, "%t", "Set_MyFakelag", lagAmount, client);
		return Plugin_Handled;
	}
	
	CPrintToChat(client, "%t", "InValid_Fakelag", FAKELAG_BOTTOM, FAKELAG_TOP);
	return Plugin_Handled;
}

//--------------------- equalize pings vote -----------------------------

public Action EFakeLagVoteCmd(int client, int args)
{
	if (StartEFakeLagVote(client))
	{
		CPrintToChatAllEx(client, "%t", "vote_to_start", client);
		FakeClientCommand(client, "Vote Yes");
    } 

	return Plugin_Handled;
}

bool StartEFakeLagVote(int client)
{
	if (!CheckPlayers())
	{
		CPrintToChat(client, "%t", "not_enough_player", survivor_limit.IntValue * 2);
		return false;
	}
	
	if (!IsBuiltinVoteInProgress())
	{
		int iNumPlayers;
		int[] iPlayers = new int[MaxClients];
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsHuman(i) || (GetClientTeam(i) <= 1))
			{
				continue;
			}
			iPlayers[iNumPlayers++] = i;
		}
			
		char cVoteTitle[32];
		Format(cVoteTitle, sizeof(cVoteTitle), "%T", "Vote_Tittle", LANG_SERVER);

		hVoteEFakelag = CreateBuiltinVote(VoteEFakelagActionHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);

		SetBuiltinVoteArgument(hVoteEFakelag, cVoteTitle);
		SetBuiltinVoteInitiator(hVoteEFakelag, client);
		SetBuiltinVoteResultCallback(hVoteEFakelag, VoteEFakelagResultHandler);
		DisplayBuiltinVote(hVoteEFakelag, iPlayers, iNumPlayers, 20);
		
		return true;
	}
	
	CPrintToChat(client, "%t", "already_vote");
	return false;
}

public void VoteEFakelagActionHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
	switch (action) 
	{
		case BuiltinVoteAction_End: 
		{
			delete vote;
			hVoteEFakelag = null;
		}
		case BuiltinVoteAction_Cancel: 
		{
			DisplayBuiltinVoteFail(vote, view_as<BuiltinVoteFailReason>(param1));
		}
	}
}

public void VoteEFakelagResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++) {
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES) 
		{
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2))
			{
				char tVotePass[32];
				Format(tVotePass, sizeof(tVotePass), "%T", "Vote_Pass_Tittle", LANG_SERVER);
				
				DisplayBuiltinVotePass(vote, tVotePass);
				
				EqualizeFakelag();
				return;
			}
		}
	}

	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void EqualizeFakelag()
{
	if (!CheckPlayers())
	{
		CPrintToChatAll("%t", "not_enough_player", survivor_limit.IntValue * 2);
		return;
	}
	
	ClearAllPlayersFakelag();
	
	int surpings = SumPings(2);
	int infpings = SumPings(3);
	int lowteam;
	int avgbuffer;
	ClearArray(lowteamplayers);
	
	if (surpings > infpings)
	{
		lowteam = 3;
		avgbuffer = surpings / survivor_limit.IntValue;
	}
	else
	{
		lowteam = 2;
		avgbuffer = infpings / survivor_limit.IntValue;
	}
	
	int sumdiff = 0;
	int diff;
	
	for(int i = 1; i < MaxClients; i++)
	{
		if (IsHuman(i) && GetClientTeam(i) == lowteam)
		{
			diff = GetClientAvgPing(i) - avgbuffer;
			if ( diff < 0)
			{
				PushArrayCell(lowteamplayers, i);
				sumdiff += diff;
			}
		}
	}
	
	int teamdiff = ABS(surpings - infpings);
	
	for(int i = 0; i < GetArraySize(lowteamplayers); i++)
	{
		int client = GetArrayCell(lowteamplayers, i);
		int lagAmount = (avgbuffer - GetClientAvgPing(client)) / sumdiff * teamdiff;
		CFakeLag_SetPlayerLatency(client, lagAmount * 1.0);
		CPrintToChat(client, "%t", "eping_notice_player", lagAmount);
	}
	
	CPrintToChatAll("%t", "equalize_finish", sumdiff);
}

// DEBUG: See the value of s_FakeLag
public Action PrintLagCmd(int client, int args) 
{
	for(int i = 1; i < MaxClients; i++) 
	{
		if(IsSurvivor(i) || IsInfected(i))
		{
			if (CFakeLag_GetPlayerLatency(i))
				CReplyToCommandEx(client, i, "%t", "show_ping_fl", i, GetClientAvgPing(i) * 1.0, GetClientAvgPing(i) - CFakeLag_GetPlayerLatency(i), CFakeLag_GetPlayerLatency(i));
			else
				CReplyToCommandEx(client, i, "%t", "show_ping", i, GetClientAvgPing(i) * 1.0);
		}
	}
	
	return Plugin_Handled;
}

public void ClearAllPlayersFakelag()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsHuman(i))
			CFakeLag_SetPlayerLatency(i, 0.0);
	}
}

stock int SumPings(int team)
{
	int teampings = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsHuman(i) && GetClientTeam(i) == team)
			teampings += GetClientAvgPing(i);
		continue;
	}
	return teampings;
}

stock int GetClientAvgPing(int client)
{
	return RoundFloat(GetClientAvgLatency(client, NetFlow_Both) * 1000);
}

public bool CheckPlayers() 
{
	int count = 0;

	for (int client = 1; client <= MaxClients; client++) 
	{
		if (IsSurvivor(client) || IsInfected(client)) 
		{
			count ++;
		}
		continue;
	}
	return count == survivor_limit.IntValue * 2;
}

stock bool IsSurvivor(int client)                                                   
{                                                                               
	return IsHuman(client) && GetClientTeam(client) == 2; 
}

stock bool IsInfected(int client)                                                   
{                                                                               
	return IsHuman(client) && GetClientTeam(client) == 3; 
}

stock bool IsHuman(int client)
{
	return IsClientInGame(client) && !IsFakeClient(client);
}