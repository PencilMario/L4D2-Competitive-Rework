public Action L4D_OnMaterializeFromGhostPre(int client)
{
	CPrintToChat(client, "{green}[!]此模式不允许主动复活普通特感。");
	return Plugin_Handled;
}

public Action L4D_OnTryOfferingTankBot(int tank_index, bool &enterStasis)
{
	ForcePlayerSuicide(tank_index);
	return Plugin_Handled;
}

public Action L4D_OnEnterGhostStatePre(int client)
{
	if (g_iRoundState == 1 || g_iRoundState == 2)
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action L4D_OnLedgeGrabbed(int client)
{
	return Plugin_Handled;
}

public Action L4D_OnSpawnSpecial(int& zombieClass, const float vecPos[3], const float vecAng[3])
{
	return Plugin_Handled;
}

public Action L4D_OnSpawnTank(const float vecPos[3], const float vecAng[3])
{
	return Plugin_Handled;
}

public Action L4D_OnSpawnWitch(const float vecPos[3], const float vecAng[3])
{
	return Plugin_Handled;
}

public void OnEntityCreated(int entity)
{
	RequestFrame(Handle_Commons, entity);
}
void Handle_Commons(int entity)
{
	if (!IsValidEdict(entity))
	{
		return;
	}
	char classname[64];
	GetEdictClassname(entity, classname, sizeof(classname));
	if (StrEqual(classname, "infected"))
	{
		AcceptEntityInput(entity, "Kill");
	}
	else if (StrEqual(classname, "instanced_scripted_scene"))
	{
		AcceptEntityInput(entity, "Kill");
	}
	else if (StrEqual(classname, "survivor_death_model"))
	{
		AcceptEntityInput(entity, "Kill");
	}
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if (buttons & IN_RELOAD && !(g_iLastButton[client] & IN_RELOAD))
	{
		if (GetClientTeam(client) == 2)
		{
			SurvivorPropMenu(client);
		}
		else if (GetClientTeam(client) == 3)
		{
			TankMenu(client);
		}
	}
	else if (buttons & IN_ATTACK2 && !(g_iLastButton[client] & IN_ATTACK2))
	{
		if (GetClientTeam(client) == 2 && !g_bLockCamera[client] && (g_iRoundState == 1 || g_iRoundState == 2))
		{
			float f_Ang[3];
			GetClientAbsAngles(client, f_Ang);
			f_Ang[0] = 0.00;
			TeleportEntity(client, NULL_VECTOR, f_Ang);
		}
	}
	g_iLastButton[client] = buttons;
	return Plugin_Changed;
}

public void OnClientConnected(int client)
{
	CreateTimer(5.0, Timer_Delay_AutoJG, client, TIMER_REPEAT);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_StartTouch, Touch_Player);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitchPost);
}

Action Timer_Delay_AutoJG(Handle timer, int client)
{
	if (!IsClientInGame(client))
	{
		return Plugin_Continue;
	}
	if (IsFakeClient(client))
	{
		return Plugin_Stop;
	}
	else if (!g_hAutoJG.BoolValue)
	{
		ChangeClientTeam(client, 1);
	}
	else if (g_iRoundState == 2 || g_iRoundState == 3)
	{
		ChangeClientTeam(client, 1);
	}
	else if (PlayerStatistics(2, false) >= PlayerStatistics(3, false) && PlayerStatistics(2, false) < g_hSurvivorLimit.IntValue)
	{
		ChangeClientTeam(client, 3);
	}
	else if (PlayerStatistics(3, false) > PlayerStatistics(2, false) && PlayerStatistics(3, false) < g_hTankLimit.IntValue)
	{
		ChangeClientTeam(client, 2);
		L4D_RespawnPlayer(client);
	}
	else
	{
		ChangeClientTeam(client, 1);
	}
	return Plugin_Stop;
}

public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKUnhook(client, SDKHook_StartTouch, Touch_Player);
	SDKUnhook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitchPost);
}

public Action Hook_WeaponCanUse(int client, int weapon)
{
	if (GetClientTeam(client) == 2)
	{
		return Plugin_Handled;
	}
	else
	{
		return Plugin_Continue;
	}
}

public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	if (!IsValidClientIndex(attacker) || !IsValidClientIndex(victim))
	{
		return Plugin_Continue;
	}
	int health = GetClientHealth(attacker);
	//拳头伤害
	if (!(damagetype & DMG_BULLET) && IsValidClientIndex(attacker) && GetClientTeam(victim) == 2 && !g_bLockCamera[victim] && GetClientTeam(attacker) == 3)
	{
		/*
		if (g_iPropNum[victim] != -1)
		{
			ModelInfo MI;
			g_hModelList.GetArray(g_iPropNum[victim], MI);
			damage *= MI.dmgrevise;
		}
		*/
		if (HasValidProp(victim))
		{
			float dmgrevise = GetPropInfo(victim, 5, "", 0);
			damage			= g_hBasicDmg.IntValue * dmgrevise;
		}
		SetEntityHealth(attacker, health + 2000);
		return Plugin_Changed;
	}
	//持枪特感
	if ((damagetype & DMG_BULLET) && GetClientTeam(attacker) == 3)
	{
		if (GetClientTeam(victim) == 3)
		{
			damage = 0.00;
			return Plugin_Changed;
		}
		/*
		if (g_iPropNum[victim] != -1)
		{
			ModelInfo MI;
			g_hModelList.GetArray(g_iPropNum[victim], MI);
			damage = 5.00 * MI.dmgrevise;
		}
		*/
		if (HasValidProp(victim))
		{
			float dmgrevise = GetPropInfo(victim, 5, "", 0);
			damage			= g_hGunDmg.IntValue * dmgrevise;
		}
		SetEntityHealth(attacker, health + 150);
		return Plugin_Changed;
	}
	//防止闪光弹误伤
	if (GetClientTeam(victim) == 2 && (damagetype & DMG_BLAST_SURFACE))
	{
		damage = 0.00;
		return Plugin_Changed;
	}
	//闪光弹命中克
	if (GetClientTeam(victim) == 3 && (damagetype & DMG_BLAST_SURFACE))
	{
		float percent = damage / 21.00;
		if (percent > 0.75)
		{
			percent = 1.0;
		}
		float	 duringtime = 3.0 * percent;
		DataPack dpin		= new DataPack();
		dpin.WriteCell(victim);
		dpin.WriteCell(1);
		dpin.WriteCell(percent);
		DataPack dpout = new DataPack();
		dpout.WriteCell(victim);
		dpout.WriteCell(0);
		dpout.WriteCell(percent);
		CreateTimer(0.01, FlashBomb, dpin, TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(duringtime, FlashBomb, dpout, TIMER_FLAG_NO_MAPCHANGE);
		damage = 0.00;
		float pos[3];
		GetClientAbsOrigin(victim, pos);
		L4D_StaggerPlayer(victim, attacker, pos);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

Action FlashBomb(Handle timer, DataPack dp)
{
	dp.Reset();
	UserMsg g_FadeUserMsgId;
	int		clients[2];
	clients[0]	   = dp.ReadCell();
	int	  isfadein = dp.ReadCell();
	float percent  = dp.ReadCell();
	int	  duration;
	int	  holdtime;
	int	  flags;

	if (isfadein == 1)
	{
		flags					= (0x0002 | 0x0010);
		holdtime				= RoundFloat(2000 * percent);
		duration				= 10;

		g_bFlashing[clients[0]] = true;
		Flashing(clients[0]);
	}
	else
	{
		flags					= (0x0001 | 0x0010);
		holdtime				= RoundFloat(255 * percent);
		duration				= holdtime;

		g_bFlashing[clients[0]] = false;
	}
	int color[4]	= { 255, 255, 255, 255 };
	g_FadeUserMsgId = GetUserMessageId("Fade");
	Handle message	= StartMessageEx(g_FadeUserMsgId, clients, 1);
	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(message);
		pb.SetInt("duration", duration);
		pb.SetInt("hold_time", holdtime);
		pb.SetInt("flags", flags);
		pb.SetColor("clr", color);
	}
	else
	{
		BfWriteShort(message, duration);
		BfWriteShort(message, holdtime);
		BfWriteShort(message, flags);
		BfWriteByte(message, color[0]);
		BfWriteByte(message, color[1]);
		BfWriteByte(message, color[2]);
		BfWriteByte(message, color[3]);
	}
	EndMessage();
	delete dp;
}

void Flashing(int client)
{
	if (g_bFlashing[client])
	{
		float fEyes[3];
		GetClientEyeAngles(client, fEyes);
		fEyes[0] = 89.00;
		TeleportEntity(client, NULL_VECTOR, fEyes, NULL_VECTOR);
		RequestFrame(Flashing, client);
	}
	else
	{
		float fEyes[3];
		GetClientEyeAngles(client, fEyes);
		fEyes[0] = 0.00;
		TeleportEntity(client, NULL_VECTOR, fEyes, NULL_VECTOR);
	}
}

void OnWeaponSwitchPost(int client, int weapon)
{
	if (!IsClientInGame(client) || GetClientTeam(client) != 3)
	{
		return;
	}
	MoveType flag = GetEntityMoveType(client);
	if (flag == MOVETYPE_LADDER)
	{
		return;
	}
	char weaponname[128];
	GetEntityClassname(weapon, weaponname, sizeof(weaponname));
	if (StrContains(weaponname, "smg") != -1)
	{
		SetEntityModel(client, "models/survivors/tank_namvet.mdl");
	}
	else
	{
		SetEntityModel(client, "models/infected/hulk.mdl");
	}
}

Action Touch_Player(int entity, int other)
{
	if (IsValidClientIndex(other) && GetClientTeam(entity) == 3 && GetClientTeam(other) == 2 && g_bLockCamera[other])
	{
		SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", other);
		CreateTimer(1.0, RemoveOwnerEntity, entity, TIMER_FLAG_NO_MAPCHANGE);
	}
	else if (g_iRoundState == 1 && IsValidClientIndex(other) && GetClientTeam(entity) == 3)
	{
		SetEntProp(entity, Prop_Send, "m_CollisionGroup", 1);
		CreateTimer(10.0, ResetEntitySolidType, entity, TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

Action RemoveOwnerEntity(Handle Timer, int client)
{
	SetEntPropEnt(client, Prop_Send, "m_hOwnerEntity", -1);
	return Plugin_Stop;
}
Action ResetEntitySolidType(Handle Timer, int client)
{
	SetEntProp(client, Prop_Send, "m_CollisionGroup", 5);
	return Plugin_Stop;
}