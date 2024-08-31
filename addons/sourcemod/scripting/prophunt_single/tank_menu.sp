void TankMenu(int client)
{
	Menu menu = new Menu(TankMenuHandler);
	menu.SetTitle("躲猫猫 - Tank面板");
	menu.AddItem("0", "- 随机传送至一名生还附近 -");
	menu.AddItem("1", "-  探测1500码内的生还者  -");
	menu.AddItem("2", "-     获取smg     -");
	menu.AddItem("3", "获取smg后,你可以用Q键1键和滚轮切换武器");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int TankMenuHandler(Menu menu, MenuAction action, int iClient, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Select:
		{
			if (GetClientTeam(iClient) != 3 || !IsPlayerAlive(iClient) || IsGhost(iClient))
			{
				return 0;
			}
			if (g_iRoundState != 2)
			{
				CPrintToChat(iClient, "{green}现在还不能使用Tank的技能。");
				return 0;
			}
			switch (param2)
			{
				case 0:
					RamdomTeleport(iClient);
				case 1:
					SurvivorDetect(iClient, 1500.0);
				case 2:
					GiveGun(iClient);
			}
		}
	}
	return 0;
}

void GetSurvivorsToArray(ArrayList al)
{
	al.Clear();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
		{
			if (g_iDetectProtectCD[i] > 0)
			{
				continue;
			}
			al.Push(i);
		}
	}
}

void RamdomTeleport(int client)
{
	if (g_iSkillCD[client] > 0)
	{
		CPrintToChat(client, "{green}技能冷却中, 请在{blue} %d {green}秒后再使用技能。", g_iSkillCD[client]);
		return;
	}
	ArrayList al = new ArrayList();
	GetSurvivorsToArray(al);
	if (al.Length < 1)
	{
		CPrintToChat(client, "{green}技能释放失败, 场上没有存活的生还, 或目标处于探测保护状态。");
		return;
	}
	int	  index = al.Get(GetRandomInt(0, al.Length - 1));
	float tppos[3];
	if (g_bLockCamera[index])
	{
		GetRandomTPPos(g_iOwnProp[index], tppos);
	}
	else
	{
		GetRandomTPPos(index, tppos);
	}
	if (tppos[0] == 0 && tppos[1] == 0 && tppos[2] == 0)
	{
		CPrintToChat(client, "{green}传送失败, 生还所处位置不允许在附近生成特感。");
	}
	else
	{
		CPrintToChat(client, "{green}传送完成。", index);
		TeleportEntity(client, tppos, NULL_VECTOR, NULL_VECTOR);
		g_iSkillCD[client] = g_hTankTPCD.IntValue;
		CreateTimer(1.0, Timer_TankSkillCD, client, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	}
	delete al;
}

void SurvivorDetect(int client, float targetdistance)
{
	bool hasdetected;
	if (g_iSkillCD[client] > 0)
	{
		CPrintToChat(client, "{green}技能冷却中, 请在{blue} %d {green}秒后再使用技能。", g_iSkillCD[client]);
		return;
	}
	ArrayList al = new ArrayList();
	GetSurvivorsToArray(al);
	if (al.Length < 1)
	{
		CPrintToChat(client, "{green}技能释放失败, 场上没有存活的生还, 或目标处于探测保护状态。");
		return;
	}
	for (int i = 0; i < al.Length; i++)
	{
		int player = al.Get(i);
		int index;
		if (g_bLockCamera[player])
		{
			index = g_iOwnProp[player];
		}
		else
		{
			index = player;
		}
		float survivorPos[3];
		float tankPos[3];
		GetEntPropVector(index, Prop_Data, "m_vecAbsOrigin", survivorPos);
		GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", tankPos);
		float distance = GetVectorDistance(survivorPos, tankPos);
		if (distance < targetdistance)
		{
			if (g_hDetect.BoolValue)
			{
				DataPack dp = new DataPack();
				dp.WriteCell(client);
				dp.WriteCell(player);
				dp.WriteFloat(GetGameTime() + g_hTankDetectcount.IntValue + 1.0);
				CreateTimer(1.0, Sustain_DetectSurvivor, dp, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
				CPrintToChat(player, "{green}[!]你已被{red} %N {green}探测, 启动 %d 秒的探测保护。", client, g_hDetectProtectCD.IntValue);
				//这条函数在生还的面板里。
				g_iDetectProtectCD[player] = g_hDetectProtectCD.IntValue;
				CreateTimer(1.0, Timer_ProtectCD, player, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
				hasdetected = true;
				break;
			}
			else
			{
				if (!g_bLockCamera[player])
				{
					CPrintToChat(client, "{green}探测到目标{blue} %N {green}距离你{blue} %d {green}码。", player, RoundFloat(distance));
				}
				else
				{
					CPrintToChat(client, "{green}探测到目标{blue} %N {green}留下的实体距离你{blue} %d {green}码。", player, RoundFloat(distance));
				}
				CPrintToChat(player, "{green}[!]你已被{red} %N {green}探测。", client);
				hasdetected = true;
				break;
			}
		}
	}
	if (!hasdetected)
	{
		CPrintToChat(client, "{green}没有找到生还, 请前往其他区域探测。");
	}
	g_iSkillCD[client] = g_hTankDetectCD.IntValue;
	CreateTimer(1.0, Timer_TankSkillCD, client, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	delete al;
	return;
}

Action Timer_TankSkillCD(Handle timer, int client)
{
	if (g_iSkillCD[client] > 0)
	{
		g_iSkillCD[client]--;
		return Plugin_Continue;
	}
	return Plugin_Stop;
}

void GiveGun(int client)
{
	if (!IsValidEdict(g_iTankSmg[client]))
	{
		g_iTankSmg[client] = CreateEntityByName("weapon_smg");
		DispatchSpawn(g_iTankSmg[client]);
		if (g_iTankSmg[client] != -1)
		{
			EquipPlayerWeapon(client, g_iTankSmg[client]);
			SetEntPropEnt(client, Prop_Send, "m_customAbility", -1);
			PrecacheModel("models/survivors/tank_namvet.mdl", true);
			SetEntityModel(client, "models/survivors/tank_namvet.mdl");
			CheatCommand(client, "give ammo");
		}
	}
}

Action Sustain_DetectSurvivor(Handle timer, DataPack dp)
{
	dp.Reset();
	int	  tank	 = dp.ReadCell();
	int	  target = dp.ReadCell();
	float time	 = dp.ReadFloat() - GetGameTime();
	int	  entity;
	if (!IsValidClientIndex(target) || !IsClientInGame(target) || !IsValidClientIndex(tank) || !IsClientInGame(tank) || !IsPlayerAlive(target))
	{
		return Plugin_Stop;
	}
	if (g_bLockCamera[target])
	{
		entity = g_iOwnProp[target];
	}
	else
	{
		entity = target;
	}
	if (time >= 0)
	{
		float survivorPos[3];
		float tankPos[3];
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", survivorPos);
		GetEntPropVector(tank, Prop_Data, "m_vecAbsOrigin", tankPos);
		float distance = GetVectorDistance(survivorPos, tankPos);
		if (entity == target)
		{
			CPrintToChat(tank, "{green}探测到目标{blue} %N {green}距离你{blue} %d {green}码。", target, RoundFloat(distance));
		}
		else
		{
			CPrintToChat(tank, "{green}探测到目标{blue} %N {green}留下的实体距离你{blue} %d {green}码。", target, RoundFloat(distance));
		}
		return Plugin_Continue;
	}
	else
	{
		return Plugin_Stop;
	}
}

// entity>=1为有目标传送，<1为无目标随机传送（仅用于将克复活到不同的位置）
void GetRandomTPPos(int entity, float Pos[3])
{
	float fPos[3];
	float fTpPos[3];
	if (entity >= 1)
	{
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", fPos);
	}
	int iCount;
	while (fTpPos[0] == 0.00)
	{
		int iIndex = GetRandomInt(0, g_hNavList.Length - 1);
		int iNav   = g_hNavList.Get(iIndex);
		L4D_FindRandomSpot(iNav, fTpPos);
		if (entity < 1 && !L4D_IsPositionInFirstCheckpoint(fTpPos))
		{
			Pos[0] = fTpPos[0];
			Pos[1] = fTpPos[1];
			Pos[2] = fTpPos[2];
			break;
		}
		float iDistance = GetVectorDistance(fPos, fTpPos);
		iCount++;
		if (iDistance >= 1000.00 && iDistance <= 2500.00)
		{
			Pos[0] = fTpPos[0];
			Pos[1] = fTpPos[1];
			Pos[2] = fTpPos[2];
			break;
		}
		else
		{
			fTpPos[0] = 0.00;
			fTpPos[1] = 0.00;
			fTpPos[2] = 0.00;
		}
		if (iCount > 150)
		{
			break;
		}
	}
}