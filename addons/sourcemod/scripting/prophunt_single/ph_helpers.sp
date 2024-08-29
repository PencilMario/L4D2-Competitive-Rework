void SetSafeRoomDoors(int doortype, int changetype)
{
	int iDoor = -1;
	for (int i = MAXPLAYERS + 1; i < GetEntityCount(); i++)
	{
		if (!IsValidEdict(i))
		{
			continue;
		}

		char sModel[128];
		GetEntityClassname(i, sModel, sizeof(sModel));
		if (!StrEqual(sModel, "prop_door_rotating_checkpoint"))
		{
			continue;
		}

		switch (doortype)
		{
			case SafeDoor_Start:
			{
				if (GetEntProp(i, Prop_Send, "m_bLocked", 4) == 1)
				{
					iDoor = i;
				}
			}
			case SafeDoor_End:
			{
				if (GetEntProp(i, Prop_Send, "m_bLocked", 4) != 1)
				{
					iDoor = i;
				}
			}
		}

		if (!IsValidEdict(iDoor))
		{
			continue;
		}
		switch (changetype)
		{
			case SafeDoor_Displace:
			{
				float fZeroPos[3];
				TeleportEntity(iDoor, fZeroPos, NULL_VECTOR, NULL_VECTOR);
			}
			case SafeDoor_Kill:
			{
				AcceptEntityInput(iDoor, "Kill");
			}
			case SafeDoor_Disable:
			{
				AcceptEntityInput(iDoor, "Disable");
			}
		}
	}
}

void TeleortTeamToSafeRoom(int teamnum)
{
	int endDoor = FindEntityByClassname(MaxClients + 1, "prop_door_rotating_checkpoint");
	if (endDoor == -1)
	{
		CPrintToChatAll("{red}警告：没有找到安全门。");
		return;
	}
	float fDoorPos[3];
	float fTpPos[3];
	GetEntPropVector(endDoor, Prop_Data, "m_vecAbsOrigin", fDoorPos);
	int safeRoom = L4D_GetNearestNavArea(fDoorPos);
	L4D_FindRandomSpot(safeRoom, fTpPos);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == teamnum)
		{
			TeleportEntity(i, fTpPos, NULL_VECTOR, NULL_VECTOR);
		}
	}
}

void SetSIAngleLock(int changetype)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 3)
		{
			switch (changetype)
			{
				case SetSI_Lock:
				{
					float eyeAngles[3];
					GetClientEyeAngles(i, eyeAngles);
					eyeAngles[0] = 89.00;
					TeleportEntity(i, NULL_VECTOR, eyeAngles, NULL_VECTOR);
					SetEntityFlags(i, FL_CLIENT | FL_FROZEN);
				}
				case SetSI_Unlock:
				{
					SetEntityFlags(i, FL_CLIENT);
				}
			}
		}
	}
}

void SpawnTanks()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 3 && IsGhost(i))
		{
			CheatCommand(i, "z_spawn_old tank");
			GiveGun(i);
			CPrintToChat(i, "{green}回合内可以用1、Q和滚轮切换武器类别。");
		}
	}
}

void TPTanksToRandomStartPoint()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 3)
		{
			float pos[3];
			L4D_GetRandomPZSpawnPosition(i, 8, 100, pos);
			TeleportEntity(i, pos);
		}
	}
}

bool IsGhost(int client)
{
	return !!GetEntProp(client, Prop_Send, "m_isGhost", 1);
}

void KillPlayers(int teamnum, bool onlyfakeclients)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == teamnum && IsPlayerAlive(i))
		{
			if (onlyfakeclients)
			{
				if (IsFakeClient(i))
				{
					ForcePlayerSuicide(i);
				}
			}
			else
			{
				ForcePlayerSuicide(i);
			}
		}
	}
}

void UnlockAngleALL()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
		{
			if (g_bLockCamera[i])
			{
				LockSelf(i);
			}
		}
	}
}

void ConvertProps()
{
	for (int i = MAXPLAYERS + 1; i < GetEntityCount(); i++)
	{
		if (!IsValidEdict(i))
		{
			continue;
		}
		char sClassname[128];
		char sModelname[128];
		GetEntityClassname(i, sClassname, sizeof(sClassname));
		GetEntPropString(i, Prop_Data, "m_ModelName", sModelname, sizeof(sModelname));
		if (StrContains(sClassname, "prop_physics") != -1 || StrContains(sClassname, "prop_dynamic") != -1)
		{
			if (StrContains(sModelname, "ventbreakable") != -1 || StrContains(sModelname, "window") != -1 || StrContains(sModelname, "glass") != -1)
			{
				RemoveEdict(i);
				continue;
			}
			CreateProp(i, Prop_Other);
			RemoveEdict(i);
		}
	}
}

void CheatCommand(int client, const char[] sCommand)
{
	if (client == 0 || !IsClientInGame(client))
		return;

	char sCmd[16];
	SplitString(sCommand, " ", sCmd, sizeof(sCmd));
	int bits = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(sCmd);
	SetCommandFlags(sCmd, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, sCommand);
	SetCommandFlags(sCmd, flags);
	SetUserFlagBits(client, bits);
	if (sCommand[0] == 'g' && strcmp(sCommand[5], "health") == 0)
	{
		SetEntPropFloat(client, Prop_Send, "m_healthBuffer", 0.0);
	}
}

void DynamickSeekingTime()
{
	int iSurvivors, iTanks;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}
		if (GetClientTeam(i) == 2 && !IsFakeClient(i))
		{
			iSurvivors++;
		}
		if (GetClientTeam(i) == 3)
		{
			iTanks++;
		}
	}
	if (iTanks == 0)
	{
		iTanks++;
	}
	float fTimePercent = float(iSurvivors) / float(iTanks);
	if (fTimePercent >= 1.5)
	{
		fTimePercent = 1.5;
	}
	else if (fTimePercent <= 0.2)
	{
		fTimePercent = 0.2;
	}
	g_iSeekTime = RoundFloat(g_iSeekTime * fTimePercent);
	PrintToChatAll("根据队伍人数调整此回合时间为 %d 秒", g_iSeekTime);
}

void GetAllNavAreas(ArrayList aList)
{
	aList.Clear();
	L4D_GetAllNavAreas(aList);
}

int PlayerStatistics(int teamnum, bool onlyalive)
{
	int iCount;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (teamnum == 0)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				if (onlyalive)
				{
					if (IsPlayerAlive(i) && GetEntProp(i, Prop_Send, "m_isGhost") != 1)
					{
						iCount++;
					}
				}
				else
				{
					iCount++;
				}
			}
		}
		else
		{
			if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == teamnum)
			{
				if (onlyalive)
				{
					if (IsPlayerAlive(i) && GetEntProp(i, Prop_Send, "m_isGhost") != 1)
					{
						iCount++;
					}
				}
				else
				{
					iCount++;
				}
			}
		}
	}
	return iCount;
}

Action CreateProp(int entity, PHPropType phtype)
{
	char   sModel[128];
	float  fAngles[3];
	float  fOrigin[3];
	int	   iProp;
	Action result;
	if (phtype == Prop_Own || phtype == Prop_Fake)
	{
		GetPropInfo(entity, 1, sModel, sizeof(sModel));
	}
	else
	{
		GetEntPropString(entity, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
	}
	PrecacheModel(sModel, true);
	iProp = CreateEntityByName("prop_dynamic_override");

	if (!IsValidEntity(iProp))
	{
		return Plugin_Handled;
	}
	switch (phtype)
	{
		case Prop_Own:
		{
			Call_StartForward(g_hOnCreateRealProp_Pre);
			Call_PushCell(entity);
			Call_PushCell(iProp);
			Call_Finish(result);
			GetClientAbsAngles(entity, g_fLockAngle[entity]);
			GetClientAbsOrigin(entity, g_fLockOrigin[entity]);
		}
		case Prop_Fake:
		{
			Call_StartForward(g_hOnCreateFakeProp_Pre);
			Call_PushCell(entity);
			Call_PushCell(iProp);
			Call_Finish(result);
			GetClientAbsAngles(entity, g_fLockAngle[entity]);
			GetClientAbsOrigin(entity, g_fLockOrigin[entity]);
		}
		case Prop_Other:
		{
			GetEntPropVector(entity, Prop_Data, "m_angRotation", fAngles);
			GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", fOrigin);
		}
	}
	if (result == Plugin_Handled)
	{
		return Plugin_Handled;
	}
	DispatchKeyValue(iProp, "model", sModel);
	DispatchKeyValue(iProp, "disableshadows", "1");
	SetEntProp(iProp, Prop_Data, "m_nSolidType", 6);
	DispatchSpawn(iProp);
	if (phtype != Prop_Other)
	{
		SetEntPropEnt(iProp, Prop_Send, "m_hOwnerEntity", entity);
		SetEntityFlags(iProp, FL_CLIENT | FL_ATCONTROLS);
	}
	if (phtype == Prop_Other)
	{
		TeleportEntity(iProp, fOrigin, fAngles, NULL_VECTOR);
	}
	else
	{
		float fix_origin[3];
		fix_origin[0] = g_fLockOrigin[entity][0];
		fix_origin[1] = g_fLockOrigin[entity][1];
		float zaxisup = GetPropInfo(entity, 6, "", 0);
		fix_origin[2] = g_fLockOrigin[entity][2] + zaxisup;
		TeleportEntity(iProp, fix_origin, g_fLockAngle[entity], NULL_VECTOR);
	}

	switch (phtype)
	{
		case Prop_Own:
		{
			SDKHook(iProp, SDKHook_OnTakeDamage, OnRealPropTakeDamage);
			g_iOwnProp[entity] = iProp;
			Call_StartForward(g_hOnCreateRealProp_Post);
			Call_PushCell(entity);
			Call_PushCell(iProp);
			Call_Finish();
		}
		case Prop_Fake:
		{
			SDKHook(iProp, SDKHook_OnTakeDamage, OnFakePropTakeDamage);
			g_hFakeProps[entity].Push(iProp);
			g_iCreateFakeProps[entity]--;
			CPrintToChat(entity, "{green}成功创建, 假身id为: {blue}%d  {green}剩余创建次数: {blue}%d", iProp, g_iCreateFakeProps[entity]);
			Call_StartForward(g_hOnCreateFakeProp_Post);
			Call_PushCell(entity);
			Call_PushCell(iProp);
			Call_Finish();
		}
		case Prop_Other:
		{
			SDKHook(iProp, SDKHook_OnTakeDamage, OnOtherPropTakeDamage);
		}
	}
	return Plugin_Continue;
}

Action OnRealPropTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3])
{
	if (!IsValidClientIndex(attacker) || GetClientTeam(attacker) != 3)
	{
		return Plugin_Handled;
	}
	int iParent = GetEntPropEnt(victim, Prop_Send, "m_hOwnerEntity");
	if (!IsValidClientIndex(iParent) || !IsClientInGame(iParent))
	{
		return Plugin_Handled;
	}
	float dmgrevise = GetPropInfo(iParent, 5, "", 0);
	int	  heal;
	if ((damagetype & DMG_BULLET) && GetClientTeam(attacker) == 3)
	{
		damage = g_hGunDmg.IntValue * dmgrevise;
		heal   = 150;
	}
	else
	{
		damage = g_hBasicDmg.IntValue * dmgrevise;
		heal   = RoundFloat(damage * 100);
	}
	if (g_bLockCamera[iParent] && iParent != -1)
	{
		SetEntityMoveType(iParent, MOVETYPE_FLY);
		SDKHooks_TakeDamage(iParent, inflictor, attacker, damage, damagetype, weapon);
		int health = GetClientHealth(attacker);
		SetEntityHealth(attacker, health + heal);
		SetEntityMoveType(iParent, MOVETYPE_NOCLIP);
	}
	RequestFrame(DeathCheck, victim);
	return Plugin_Handled;
}

Action OnFakePropTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3])
{
	if (!IsValidClientIndex(attacker) || GetClientTeam(attacker) != 3)
	{
		return Plugin_Handled;
	}
	int iParent = GetEntPropEnt(victim, Prop_Send, "m_hOwnerEntity");
	int index	= g_hFakeProps[iParent].FindValue(victim);
	if (index != -1)
	{
		g_hFakeProps[iParent].Erase(index);
	}
	if (IsClientInGame(iParent))
	{
		CPrintToChat(iParent, "{green}你创造的假身(id %d)已被{red} %N {green}摧毁。", victim, attacker);
		CPrintToChat(attacker, "{green}你摧毁了{blue} %N {green}的一个假身。", iParent);
	}
	else
	{
		CPrintToChat(attacker, "{green}你摧毁了一个未知来源的假身。");
	}
	int health = GetClientHealth(attacker);
	SetEntityHealth(attacker, health + 1000);

	SDKUnhook(victim, SDKHook_OnTakeDamage, OnFakePropTakeDamage);
	AcceptEntityInput(victim, "Kill");
	return Plugin_Handled;
}

Action OnOtherPropTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3])
{
	if (!IsValidClientIndex(attacker) || GetClientTeam(attacker) != 3)
	{
		return Plugin_Handled;
	}
	if (!(damagetype & DMG_BULLET) && GetClientTeam(attacker) == 3)
	{
		SDKHooks_TakeDamage(attacker, inflictor, attacker, 1000.00, damagetype, weapon);
	}
	return Plugin_Handled;
}

bool HasValidProp(int client)
{
	return g_iPropNum[client] == -1 ? false : true;
}

/**
 * 查询非string信息可随意输入buffer参数和maxlength参数
 *
 * @param client		目标
 * @param num		0 = 模型序号,1 = 模型路径,2 = 模型名称,3 = 是否允许tp,4 = 是否允许创造假身,5 = 伤害修正倍数,6 = 模型z轴修正
 *
 */
any GetPropInfo(int client, int num, char[] buffer, int maxlength)
{
	if (g_iPropNum[client] == -1)
	{
		return 0;
	}
	ModelInfo MI;
	g_hModelList.GetArray(g_iPropNum[client], MI);
	switch (num)
	{
		case 0:
		{
			return MI.modelnum;
		}
		case 1:
		{
			Format(buffer, maxlength, "%s", MI.model);
			return 0;
		}
		case 2:
		{
			Format(buffer, maxlength, "%s", MI.sname);
			return 0;
		}
		case 3:
		{
			return MI.allowtp;
		}
		case 4:
		{
			return MI.allowfake;
		}
		case 5:
		{
			return MI.dmgrevise;
		}
		case 6:
		{
			return MI.zaxisup;
		}
	}
	return 0;
}

void RandomModelAll()
{
	UnlockAngleALL();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && !IsFakeClient(i) && IsPlayerAlive(i))
		{
			RandomModel(i);
		}
	}
}

void RandomModel(int client)
{
	g_iPropNum[client] = GetRandomInt(0, g_hModelList.Length - 1);
	if (g_bLockCamera[client])
	{
		LockSelf(client);
	}
	char sModelPath[128];
	GetPropInfo(client, 1, sModelPath, sizeof(sModelPath));
	PrecacheModel(sModelPath, true);
	SetEntPropFloat(client, Prop_Send, "m_TimeForceExternalView", 99999.4);
	SetEntityModel(client, sModelPath);
	OutPutModelInfo(client);
	if (IsValidEntity(g_iGlowEntity[client]))
	{
		AcceptEntityInput(g_iGlowEntity[client], "Kill");
	}
	CreatePropGlow(client);
}

void DeathCheck(int entity)
{
	int iParent = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (!IsValidClientIndex(iParent) || !IsClientInGame(iParent) || !IsPlayerAlive(iParent) || GetClientTeam(iParent) != 2)
	{
		SDKUnhook(entity, SDKHook_OnTakeDamage, OnRealPropTakeDamage);
		AcceptEntityInput(entity, "Kill");
	}
}

void CreatePropGlow(int iTarget)
{
	int iEntity = CreateEntityByName("prop_dynamic_override");
	if (iEntity == -1)
	{
		return;
	}

	float vOrigin[3];
	float vAngles[3];
	GetEntPropVector(iTarget, Prop_Send, "m_vecOrigin", vOrigin);
	GetEntPropVector(iTarget, Prop_Data, "m_angRotation", vAngles);

	char sModelName[PLATFORM_MAX_PATH];
	GetPropInfo(iTarget, 1, sModelName, sizeof(sModelName));
	PrecacheModel(sModelName, true);
	SetEntityModel(iEntity, sModelName);
	DispatchSpawn(iEntity);

	SetEntProp(iEntity, Prop_Send, "m_CollisionGroup", 0);
	SetEntProp(iEntity, Prop_Send, "m_nSolidType", 0);
	SetEntProp(iEntity, Prop_Send, "m_nGlowRange", 1500);
	SetEntProp(iEntity, Prop_Send, "m_nGlowRangeMin", 0);
	SetEntProp(iEntity, Prop_Send, "m_iGlowType", 2);
	SetEntProp(iEntity, Prop_Send, "m_glowColorOverride", 8388736);
	AcceptEntityInput(iEntity, "StartGlowing");
	SetEntityRenderMode(iEntity, RENDER_NONE);
	SetEntityRenderColor(iEntity, 0, 0, 0, 0);

	TeleportEntity(iEntity, vOrigin, vAngles, NULL_VECTOR);
	SetVariantString("!activator");
	AcceptEntityInput(iEntity, "SetParent", iTarget);

	SetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity", iTarget);
	g_iGlowEntity[iTarget] = iEntity;
	SDKHook(iEntity, SDKHook_SetTransmit, OnTransmit);
}

public Action OnTransmit(int iEntity, int iClient)
{
	if (!IsValidEdict(iEntity))
	{
		SDKUnhook(iEntity, SDKHook_SetTransmit, OnTransmit);
		return Plugin_Handled;
	}
	int iParent = GetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity");
	if (iParent > 0 && GetClientTeam(iParent) == 2)
	{
		return Plugin_Continue;
	}
	if (iParent > 0 && IsClientInWater(iParent) && GetClientTeam(iClient) == 3 && g_hGlowInWater.BoolValue)
	{
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

bool IsClientInWater(int client)
{
	return GetEntityFlags(client) & FL_INWATER ? true : false;
}