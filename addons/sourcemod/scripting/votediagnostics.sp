#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <sdktools>


#define LOGFILE "vote_diagnostics.txt"
#define MAX_ARG_SIZE 65
#define DELAY 6.0


int g_VoteController = -1;


public Plugin myinfo = 
{
	name = "L4D2 Vote Sniffer",
	author = "Powerlord",
	description = "Sniff voting commands, events, and usermessages",
	version = "build_0001",
	url = "https://github.com/TouchMe-Inc/l4d2_nativevotes_rework"
}


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

bool CheckVoteController()
{
	int entity = -1;
	if (g_VoteController != -1)
	{
		entity = EntRefToEntIndex(g_VoteController);
	}
	
	if (entity == -1)
	{
		entity = FindEntityByClassname(-1, "vote_controller");
		if (entity == -1)
		{
			LogError("Could not find Vote Controller.");
			return false;
		}
		
		g_VoteController = EntIndexToEntRef(entity);
	}
	return true;
}

public void OnPluginStart()
{
	HookEventEx("vote_changed", Event_VoteChanged);

	HookUserMessage(GetUserMessageId("VoteRegistered"), Message_VoteRegistered);
	HookUserMessage(GetUserMessageId("VoteStart"), Message_VoteStart);
	HookUserMessage(GetUserMessageId("VotePass"), Message_VotePass);
	HookUserMessage(GetUserMessageId("VoteFail"), Message_VoteFail);

	AddCommandListener(CommandVote, "vote");
	AddCommandListener(CommandCallVote, "callvote");
}

/*
"vote_changed"
{
		"yesVotes"              "byte"
		"noVotes"               "byte"
		"potentialVotes"        "byte"
}
*/
public void Event_VoteChanged(Event event, const char[] name, bool dontBroadcast)
{
	int yesVotes = event.GetInt("yesVotes");
	int noVotes = event.GetInt("noVotes");
	int potentialVotes = event.GetInt("potentialVotes");

	LogMessage("Vote Changed event: yesVotes: %d, noVotes: %d, potentialVotes: %d",
		yesVotes, noVotes, potentialVotes);
}

/*
VoteRegistered Structure
	- Byte      Choice voted for, 0 = No, 1 = Yes
*/  
public Action Message_VoteRegistered(UserMsg msg_id, BfRead message, const int[] players, int playersNum, bool reliable, bool init)
{
	int choice = BfReadByte(message);
	
	LogToFile(LOGFILE, "VoteRegistered Usermessage: choice: %d", choice);
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
public Action Message_VoteStart(UserMsg msg_id, BfRead message, const int[] players, int playersNum, bool reliable, bool init)
{
	char issue[MAX_ARG_SIZE];
	char param1[MAX_ARG_SIZE];
	char initiatorName[MAX_NAME_LENGTH];

	int iTeam = message.ReadByte();
	int initiator = message.ReadByte();

	message.ReadString(issue, MAX_ARG_SIZE);
	message.ReadString(param1, MAX_ARG_SIZE);
	message.ReadString(initiatorName, MAX_NAME_LENGTH);

	LogToFile(LOGFILE, "VoteStart Usermessage: team: %d, initiator: %d, issue: %s, param1: %s, player count: %d, initiatorName: %s", iTeam, initiator, issue, param1, playersNum, initiatorName);

	if (CheckVoteController()) {
		LogToFile(LOGFILE, "Active Index for issue %s: %d", issue, GetEntProp(g_VoteController, Prop_Send, "m_activeIssueIndex"));
	}

	return Plugin_Continue;
}

/*
VotePass Structure
	- Byte      Team index or -1 for all
	- String    Vote issue pass phrase
	- String    Vote issue pass phrase argument

*/
public Action Message_VotePass(UserMsg msg_id, BfRead message, const int[] players, int playersNum, bool reliable, bool init)
{
	char issue[MAX_ARG_SIZE];
	char param1[MAX_ARG_SIZE];
	int iTeam = message.ReadByte();

	message.ReadString(issue, MAX_ARG_SIZE);
	message.ReadString(param1, MAX_ARG_SIZE);

	LogToFile(LOGFILE, "VotePass Usermessage: team: %d, issue: %s, param1: %s", iTeam, issue, param1);

	CreateTimer(DELAY, Timer_LogControllerValues, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

/*
VoteFail Structure
	- Byte      Team index or -1 for all

*/  
public Action Message_VoteFail(UserMsg msg_id, BfRead message, const int[] players, int playersNum, bool reliable, bool init)
{
	int iTeam = message.ReadByte();

	LogToFile(LOGFILE, "VoteFail Usermessage: team: %d", iTeam);

	CreateTimer(DELAY, Timer_LogControllerValues, _, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}

public Action Timer_LogControllerValues(Handle timer)
{
	if (!CheckVoteController()) {
		return Plugin_Continue;
	}

	int iTeam = GetEntProp(g_VoteController, Prop_Send, "m_onlyTeamToVote");
	int activeIssue = GetEntProp(g_VoteController, Prop_Send, "m_activeIssueIndex");
	int potentialVotes = GetEntProp(g_VoteController, Prop_Send, "m_potentialVotes");
	int iVotesYes = GetEntProp(g_VoteController, Prop_Send, "m_votesYes");
	int iVotesNo = GetEntProp(g_VoteController, Prop_Send, "m_votesNo");
	
	LogToFile(LOGFILE, "Vote Controller, issue: %d, team: %d, potentialVotes: %d, countYes: %d, countNo: %d",
		activeIssue, iTeam, potentialVotes, iVotesYes, iVotesNo);

	return Plugin_Continue;
}

/*
Vote command
    - String		option1 through option5 (for TF2/CS:GO); Yes or No (for L4D/L4D2)
 */
public Action CommandVote(int client, const char[] command, int argc)
{
	char vote[MAX_ARG_SIZE];
	GetCmdArg(1, vote, sizeof(vote));

	LogToFile(LOGFILE, "%N used vote command: %s %s", client, command, vote);
	return Plugin_Continue;
}

/*
callvote command
	- String		Vote type (Valid types are sent in the VoteSetup message)
	- String		target (or type - target for Kick)
*/
public Action CommandCallVote(int client, const char[] command, int argc)
{
	char args[255];
	GetCmdArgString(args, sizeof(args));

	LogToFile(LOGFILE, "callvote command: client: %N, command: %s", client, args);
	return Plugin_Continue;
}
