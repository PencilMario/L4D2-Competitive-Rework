void TankMenu(int client)
{
	Menu menu = new Menu(TankMenuHandler);
	menu.SetTitle("躲猫猫 - Tank面板");
	menu.AddItem("0", "- 随机传送至一名生还附近 -");
	menu.AddItem("1", "- 探测1500码内的生还者 -");
	menu.AddItem("2", "-    变身为持枪特感    -");
	menu.AddItem("2", "-    切换至拳砖模式    -");
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
			if (GetClientTeam(iClient) != 3)
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
					SwitchGunMode(iClient);
				case 3:
					SwitchPunchMode(iClient);
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
			if (!g_bLockCamera[i])
			{
				al.Push(i);
			}
			else
			{
				al.Push(g_iOwnProp[i]);
			}
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
		CPrintToChat(client, "{green}技能释放失败, 场上没有存活的生还。");
		return;
	}
	int	  index = al.Get(GetRandomInt(0, al.Length - 1));
	float tppos[3];
	GetRandomTPPos(index, tppos);
	if (tppos[0] == 0 && tppos[1] == 0 && tppos[2] == 0)
	{
		CPrintToChat(client, "{green}传送失败, 生还所处位置不允许在附近生成特感。");
	}
	else
	{
		CPrintToChat(client, "{green}传送完成。", index);
		TeleportEntity(client, tppos, NULL_VECTOR, NULL_VECTOR);
		g_iSkillCD[client] = 20;
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
	if (g_iTankType[client] != 0)
	{
		CPrintToChat(client, "{green}你的当前形态不允许使用探测技能。");
		return;
	}
	ArrayList al = new ArrayList();
	GetSurvivorsToArray(al);
	if (al.Length < 1)
	{
		CPrintToChat(client, "{green}技能释放失败, 场上没有存活的生还。");
		return;
	}
	for (int i = 0; i < al.Length; i++)
	{
		int index = al.Get(i);
		int player;
		if (!IsValidClientIndex(index))
		{
			player = GetEntPropEnt(index, Prop_Send, "m_hOwnerEntity");
		}
		else
		{
			player = index;
		}
		float survivorPos[3];
		float tankPos[3];
		GetEntPropVector(index, Prop_Data, "m_vecAbsOrigin", survivorPos);
		GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", tankPos);
		float distance = GetVectorDistance(survivorPos, tankPos);
		if (distance < targetdistance)
		{
			DataPack dp = new DataPack();
			dp.WriteCell(client);
			dp.WriteCell(player);
			dp.WriteFloat(GetGameTime() + 5.0);
			CreateTimer(1.0, Sustain_DetectSurvivor, dp, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
			hasdetected = true;
			break;
		}
	}
	if (!hasdetected)
	{
		CPrintToChat(client, "{green}没有找到生还, 请前往其他区域探测。");
	}
	g_iSkillCD[client] = 30;
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

void SwitchGunMode(int client)
{
	if (GetClientTeam(client) != 3 || g_iTankType[client] == 1)
	{
		return;
	}
	if (g_iSkillCD[client] > 0)
	{
		CPrintToChat(client, "{green}技能冷却中, 请在{blue} %d {green}秒后再使用技能。", g_iSkillCD[client]);
		return;
	}
	int oldW = GetPlayerWeaponSlot(client, 0);
	int newW = CreateEntityByName("weapon_smg_silenced");
	DispatchSpawn(newW);
	if (oldW != -1 && newW != -1)
	{
		RemovePlayerItem(client, oldW);
		EquipPlayerWeapon(client, newW);
		g_iTankAbility[client] = GetEntPropEnt(client, Prop_Send, "m_customAbility");
		SetEntPropEnt(client, Prop_Send, "m_customAbility", -1);
		PrecacheModel("models/survivors/tank_namvet.mdl");
		SetEntityModel(client, "models/survivors/tank_namvet.mdl");
		CheatCommand(client, "give ammo");
		g_iTankType[client] = 1;
		g_iSkillCD[client]	= 1;
		CreateTimer(1.0, Timer_TankSkillCD, client, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	}
}

void SwitchPunchMode(int client)
{
	if (GetClientTeam(client) != 3 || g_iTankType[client] == 0)
	{
		return;
	}
	if (g_iSkillCD[client] > 0)
	{
		CPrintToChat(client, "{green}技能冷却中, 请在{blue} %d {green}秒后再使用技能。", g_iSkillCD[client]);
		return;
	}
	int oldW = GetPlayerWeaponSlot(client, 0);
	if (oldW != -1)
	{
		RemovePlayerItem(client, oldW);
		CheatCommand(client, "give tank_claw");
		SetEntPropEnt(client, Prop_Send, "m_customAbility", g_iTankAbility[client]);
		SetEntityModel(client, "models/infected/hulk.mdl");
		g_iTankType[client] = 0;
		g_iSkillCD[client]	= 1;
		CreateTimer(1.0, Timer_TankSkillCD, client, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	}
}

Action Sustain_DetectSurvivor(Handle timer, DataPack dp)
{
	dp.Reset();
	int	  tank	 = dp.ReadCell();
	int	  target = dp.ReadCell();
	float time	 = dp.ReadFloat() - GetGameTime();
	int	  entity;
	if (!IsPlayerAlive(target))
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