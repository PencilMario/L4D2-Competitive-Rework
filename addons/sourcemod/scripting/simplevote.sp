#include <sourcemod>
#include <builtinvotes>

Handle private_fs_hVote;

public bool s_CallVote(int iClient, const char[] info, BuiltinVoteHandler votes)
{
	if (GetClientTeam(iClient) == 1)	//禁止旁观发起投票
	{
		PrintToChat(iClient, "不允许旁观者发起该投票。");
		return false;
	}
	if (!IsBuiltinVoteInProgress())
	{
		int[] iPlayers	= new int[MaxClients];
		int iNumPlayers = 0;
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) == 1)
			{
				continue;
			}

			iPlayers[iNumPlayers++] = i;
		}

		char playername[32];
		GetClientName(iClient, playername, sizeof(playername));
		private_fs_hVote = CreateBuiltinVote(s_VoteActionHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
		// char infos[128];
		// FormatEx(infos, sizeof(infos), " %s", info);
		SetBuiltinVoteArgument(private_fs_hVote, info);
		SetBuiltinVoteInitiator(private_fs_hVote, iClient);					//设置投票发起者
		SetBuiltinVoteResultCallback(private_fs_hVote, votes);				//设置投票产生结果后执行的函数
		DisplayBuiltinVote(private_fs_hVote, iPlayers, iNumPlayers, 20);	//设置投票参加对象
		FakeClientCommand(iClient, "Vote Yes");								//默认发起投票的玩家同意该投票
		return true;
	}
	PrintToChat(iClient, "投票已在进行，结束前不允许发起投票。");
	return false;
}

public bool s_CallVote_ex(int iClient, int team, bool callerdefault, const char[] info, BuiltinVoteHandler votes)
{
	if (GetClientTeam(iClient) == 1)	//禁止旁观发起投票
	{
		PrintToChat(iClient, "不允许旁观者发起该投票。");
		return false;
	}
	if (!IsBuiltinVoteInProgress())
	{
		int[] iPlayers	= new int[MaxClients];
		int iNumPlayers = 0;
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != team || GetClientTeam(i) == 1)
			{
				continue;
			}

			iPlayers[iNumPlayers++] = i;
		}

		char playername[32];
		GetClientName(iClient, playername, sizeof(playername));
		private_fs_hVote = CreateBuiltinVote(s_VoteActionHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
		// char infos[128];
		// FormatEx(infos, sizeof(infos), " %s", info);
		SetBuiltinVoteArgument(private_fs_hVote, info);
		SetBuiltinVoteInitiator(private_fs_hVote, iClient);					//设置投票发起者
		SetBuiltinVoteResultCallback(private_fs_hVote, votes);				//设置投票产生结果后执行的函数
		DisplayBuiltinVote(private_fs_hVote, iPlayers, iNumPlayers, 20);	//设置投票参加对象
		if (callerdefault)
		{
			FakeClientCommand(iClient, "Vote Yes");	   //默认发起投票的玩家同意该投票
		}
		return true;
	}
	PrintToChat(iClient, "投票已在进行，结束前不允许发起投票。");
	return false;
}

public void s_VoteActionHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
	switch (action)
	{
		case BuiltinVoteAction_End:
		{
			delete vote;
			private_fs_hVote = null;
		}
		case BuiltinVoteAction_Cancel:
		{
			DisplayBuiltinVoteFail(vote, view_as<BuiltinVoteFailReason>(param1));
		}
	}
}

public bool IsVotePass_ex(Handle vote, int num_votes, const int[][] item_info)
{
	if (item_info[0][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2))
	{
		return true;
	}
	return false;
}

public bool IsVotePass(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++)
	{
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES)	  //列出选择同意的玩家
		{
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2))	   //设置投票成功的条件为过半同意
			{
				DisplayBuiltinVotePass(vote, "投票已通过");
				return true;
			}
		}
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
	return false;
}

/*
使用方法：
一：按BuiltinVoteHandler的参数构建方法，并在方法的首行使用IsVotePass来判断是否通过投票
二：在发起投票的地方使用s_CallVote(client,"投票内容",方法);
注：typedef BuiltinVoteHandler = function void(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info);

public void OnPluginStart()
{
	RegConsoleCmd("sm_bt", Callvote);
}

public Action Callvote(int iClient, int iArgs)
{
	s_CallVote(iClient,"发起测试投票",votetest);
}

public void votetest(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if(IsVotePass(vote, num_votes, num_clients, client_info, num_items, item_info))
	{
		PrintToChatAll("测试通过");
	}
}

*/