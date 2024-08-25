void HookTheEvents()
{
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_left_start_area", Event_PlayerLeftStartArea);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_team", Event_ChangeTeam);
	HookEvent("weapon_fire", Event_WeaponFire);
	HookEvent("player_bot_replace", OnTankGoneAi);
	HookEvent("round_end", Event_RoundEnd);
}

Action Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	g_iRoundState = 0;
	Call_StartForward(g_hOnReadyStage_Post);
	Call_Finish();
}

Action Event_PlayerLeftStartArea(Handle event, const char[] name, bool dontBroadcast)
{
	g_iRoundState = 1;
	Call_StartForward(g_hOnHidingStage_Post);
	Call_Finish();
}

Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int userId = GetEventInt(event, "userid");
	int user   = GetClientOfUserId(userId);
	if (g_iRoundState == 2 && !IsFakeClient(user))
	{
		PlayerStatus();
	}
}

public void Event_WeaponFire(Handle event, const char[] name, bool dontBroadcast)
{
	int userId = GetEventInt(event, "userid");
	int user   = GetClientOfUserId(userId);
	if (GetClientTeam(user) == 3 && g_iTankType[user] == 1)
	{
		SDKHooks_TakeDamage(user, user, user, 30.0);
	}
}

public void Event_ChangeTeam(Handle event, const char[] name, bool dontBroadcast)
{
	int userId			= GetEventInt(event, "userid");
	int user			= GetClientOfUserId(userId);
	g_bLockCamera[user] = false;
	CreateTimer(0.2, Delay_KillAIs, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void Event_RoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	L4D2_HideVersusScoreboard();
}

void PlayerStatus()
{
	if (g_iRoundState != 2)
	{
		return;
	}
	int iSurvivors, iTanks;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}
		if (GetClientTeam(i) == 2 && IsPlayerAlive(i) && !IsFakeClient(i))
		{
			iSurvivors++;
		}
		if (GetClientTeam(i) == 3 && GetEntProp(i, Prop_Send, "m_zombieClass") == 8 && IsPlayerAlive(i))
		{
			iTanks++;
		}
	}
	if (iSurvivors > 0 && iTanks > 0)
	{
		return;
	}
	if (iSurvivors == 0)
	{
		g_iWinnerTeam = 3;
	}
	else if (iTanks == 0)
	{
		g_iWinnerTeam = 2;
	}
	g_iRoundState = 3;
	Call_StartForward(g_hOnEndStage_Post);
	Call_Finish();
}

Action Delay_KillAIs(Handle hTimer)
{
	if (g_iRoundState == 2)
	{
		KillPlayers(2, true);
	}
}

//来自aitankgank.sp
void OnTankGoneAi(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iNewTank = GetClientOfUserId(hEvent.GetInt("bot"));

	if (GetClientTeam(iNewTank) == 3 && GetEntProp(iNewTank, Prop_Send, "m_zombieClass") == 8)
	{
		int iFormerTank = GetClientOfUserId(hEvent.GetInt("player"));
		if (iFormerTank == 0)
		{	 // if people disconnect, iFormerTank = 0 instead of the old player's id
			CreateTimer(1.0, Timed_CheckAndKill, iNewTank, TIMER_FLAG_NO_MAPCHANGE);
			return;
		}
		ForcePlayerSuicide(iNewTank);
	}
}

Action Timed_CheckAndKill(Handle hTimer, any iNewTank)
{
	if (IsFakeClient(iNewTank) && IsPlayerAlive(iNewTank))
	{
		ForcePlayerSuicide(iNewTank);
	}

	return Plugin_Stop;
}
