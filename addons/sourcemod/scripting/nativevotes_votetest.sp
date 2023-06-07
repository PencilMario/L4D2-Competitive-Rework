
#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>

#include "include/nativevotes_rework"


public Plugin myinfo = 
{
	name = "NativeVotesRevorkTest",
	author = "Powerlord",
	description = "Test",
	version = "build_0001",
	url = "https://github.com/TouchMe-Inc/l4d2_nativevotes_rework"
}


public void OnPluginStart() {
	RegAdminCmd("voteyesno", Cmd_TestYesNo, ADMFLAG_VOTE, "Test Yes/No votes");
}

public Action Cmd_TestYesNo(int iClient, int args)
{
	if (!NativeVotes_IsNewVoteAllowed())
	{
		int seconds = NativeVotes_CheckVoteDelay();
		ReplyToCommand(iClient, "Vote is not allowed for %d more seconds", seconds);
		return Plugin_Handled;
	}

	NativeVote hVote = new NativeVote(HandlerCustomYesNo, NativeVotesType_Custom_YesNo);

	hVote.Initiator = iClient;
	hVote.SetDetails("My old details");

	int iTotalPlayers;
	int[] iPlayers = new int[MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
	{
		if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer)) {
			continue;
		}

		iPlayers[iTotalPlayers++] = iPlayer;
	}

	hVote.DisplayVote(iPlayers, iTotalPlayers, 20);

	return Plugin_Handled;
}

public Action HandlerCustomYesNo(NativeVote hVote, VoteAction iAction, int iParam1, int iParam2)
{
	switch (iAction)
	{
		case VoteAction_Start: {
			PrintToChatAll("Voting has begun by %N", iParam1);
		}

		case VoteAction_Display:
		{
			char display[64];
			Format(display, sizeof(display), "%N sees this message", iParam1);
			hVote.SetDetails(display);
			return Plugin_Changed;
		}

		case VoteAction_Select:
		{
			PrintToChatAll("Player %N select %s", iParam1, iParam2 == NATIVEVOTES_VOTE_YES ? "yes" : "no");
		}

		case VoteAction_Cancel:
		{
			hVote.DisplayFail();
		}

		case VoteAction_Finish:
		{
			if (iParam1 == NATIVEVOTES_VOTE_NO)
			{
				hVote.DisplayFail();
			}
			else
			{
				hVote.DisplayPass("Test Yes/No Vote Passed!");
				// Do something because it passed
			}
		}

		case VoteAction_End: {
			hVote.Close();
		}
	}

	return Plugin_Continue;
}

