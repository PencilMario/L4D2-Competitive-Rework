void SurvivorPropMenu(int client)
{
	Menu menu = new Menu(PropMenuHandler);
	menu.SetTitle("躲猫猫-生还面板 ");
	menu.AddItem("0", "- 切换第一/第三人称 -");
	menu.AddItem("1", "- 固定模型/恢复移动 -");
	menu.AddItem("2", "-  向准星处发射胆汁 -");
	menu.AddItem("3", "-  向准星发射闪光弹 -");
	menu.AddItem("4", "-      创造假身     -");
	menu.AddItem("5", "-   发动飞雷神之术  -");
	menu.AddItem("6", "-      模型选单     -");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int PropMenuHandler(Menu menu, MenuAction action, int iClient, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Select:
		{
			if (GetClientTeam(iClient) != 2 || !IsPlayerAlive(iClient))
			{
				return 0;
			}
			switch (param2)
			{
				case 0:
				{
					SwitchPerson(iClient);
					SurvivorPropMenu(iClient);
				}
				case 1:
				{
					LockAngle(true, iClient);
				}
				case 2:
				{
					OnLaunchBomb(iClient, 1);
				}
				case 3:
				{
					OnLaunchBomb(iClient, 2);
				}
				case 4:
				{
					CreateFakeProp(iClient);
				}
				case 5:
				{
					TpToFakeProp(iClient);
				}
				case 6:
				{
					if (g_iRoundState != 1 && g_iRoundState != 2)
					{
						CPrintToChat(iClient, "{green}回合尚未开始, 不允许更换模型。");
						SurvivorPropMenu(iClient);
					}
					else if (g_bLockCamera[iClient])
					{
						CPrintToChat(iClient, "{green}固定模型期间不能更换模型。");
						SurvivorPropMenu(iClient);
					}
					else
					{
						SelectModel(iClient);
					}
				}
			}
		}
	}
	return 0;
}

void SwitchPerson(int client)
{
	float time = GetEntPropFloat(client, Prop_Send, "m_TimeForceExternalView");

	if (time > 1.0)
	{
		SetEntPropFloat(client, Prop_Send, "m_TimeForceExternalView", 0.4);
		CPrintToChat(client, "{green}已切换至第一人称。");
	}
	else
	{
		SetEntPropFloat(client, Prop_Send, "m_TimeForceExternalView", 99999.4);
		CPrintToChat(client, "{green}已切换至第三人称。");
	}
}

void LockAngle(bool showmenu, int iClient)
{
	if (g_iRoundState == 0 || g_iRoundState == 3)
	{
		CPrintToChat(iClient, "{green}现在不能锁定视角。");
	}
	else if (g_iPropNum[iClient] == -1)
	{
		CPrintToChat(iClient, "{green}未选择模型, 不能锁定视角。");
	}
	else if (!g_bLockCamera[iClient] && !(GetEntityFlags(iClient) & FL_ONGROUND))
	{
		CPrintToChat(iClient, "{green}不允许在空中锁定视角。");
	}
	else if (IsClientInWater(iClient) && !g_hAllowInWater.BoolValue)
	{
		CPrintToChat(iClient, "{green}不允许在水中锁定视角。");
	}
	else
	{
		LockSelf(iClient);
		if (showmenu)
		{
			SurvivorPropMenu(iClient);
		}
	}
}

void LockSelf(int client)
{
	if (!g_bLockCamera[client])
	{
		Action result = CreateProp(client, Prop_Own);
		if (result == Plugin_Handled)
		{
			// Pre被拦截
			return;
		}
		SetEntityMoveType(client, MOVETYPE_NOCLIP);
		SetEntityRenderMode(client, RENDER_TRANSALPHA);
		SetEntityRenderColor(client, 255, 255, 255, 0);
		float time = GetEntPropFloat(client, Prop_Send, "m_TimeForceExternalView");
		if (time > 1.0)
		{
			SetEntPropFloat(client, Prop_Send, "m_TimeForceExternalView", 0.4);
		}
		CPrintToChat(client, "{green}已固定模型并修正碰撞箱, 启用自由观看。");
		SetEntityModel(client, "");
		g_bLockCamera[client] = true;
		if (IsValidEntity(g_iGlowEntity[client]))
		{
			AcceptEntityInput(g_iGlowEntity[client], "Kill");
		}
		PropProTect(client);
	}
	else
	{
		char sModel[128];
		GetPropInfo(client, 1, sModel, sizeof(sModel));
		SetEntityModel(client, sModel);
		SetEntityMoveType(client, MOVETYPE_WALK);
		SetEntityRenderMode(client, RENDER_TRANSALPHA);
		SetEntityRenderColor(client, 255, 255, 255, 255);
		TeleportEntity(client, g_fLockOrigin[client], g_fLockAngle[client], NULL_VECTOR);
		if (IsValidEdict(g_iOwnProp[client]))
		{
			RemoveEntity(g_iOwnProp[client]);
		}
		g_bLockCamera[client] = false;
		SetEntityFlags(client, FL_CLIENT);

		float time = GetEntPropFloat(client, Prop_Send, "m_TimeForceExternalView");
		if (time < 1.0)
		{
			SetEntPropFloat(client, Prop_Send, "m_TimeForceExternalView", 99999.4);
		}

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && GetClientTeam(i) == 3)
			{
				int iParent = GetEntPropEnt(i, Prop_Send, "m_hOwnerEntity");
				if (iParent == client)
				{
					SetEntPropEnt(i, Prop_Send, "m_hOwnerEntity", -1);
				}
			}
		}

		if (IsValidEntity(g_iGlowEntity[client]))
		{
			AcceptEntityInput(g_iGlowEntity[client], "Kill");
		}
		CreatePropGlow(client);
		CPrintToChat(client, "{green}已恢复自由移动。");
	}
}

void OnLaunchBomb(int client, int bombtype)
{
	Action result;
	Call_StartForward(g_hOnLaunchBombs_Pre);
	Call_PushCell(client);
	Call_Finish(result);
	if (result == Plugin_Handled)
	{
		return;
	}
	if (g_iRoundState != 2)
	{
		CPrintToChat(client, "{green}非寻找阶段不允许发射投掷物。");
	}
	else
	{
		LaunchGrande(client, bombtype);
	}
	SurvivorPropMenu(client);
}

void LaunchGrande(int client, int bombtype)
{
	float speed = 750.0;
	float origin[3];
	float angle[3];
	float direction[3];
	GetClientEyeAngles(client, angle);
	GetClientEyePosition(client, origin);
	GetAngleVectors(angle, direction, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(direction, direction);
	ScaleVector(direction, speed);

	switch (bombtype)
	{
		case 1:
		{
			if (g_iVomitjar[client] > 0)
			{
				L4D2_VomitJarPrj(client, origin, direction);
				g_iVomitjar[client]--;
				CPrintToChat(client, "{default}剩余发射胆汁次数: {green}%d {default}次", g_iVomitjar[client]);
			}
			else
			{
				CPrintToChat(client, "{green}胆汁的发射次数已用完。");
			}
		}
		case 2:
		{
			if (g_iPipeBomb[client] > 0)
			{
				L4D_PipeBombPrj(client, origin, direction);
				g_iPipeBomb[client]--;
				CPrintToChat(client, "{default}剩余发射闪光弹次数: {green}%d {default}次", g_iPipeBomb[client]);
			}
			else
			{
				CPrintToChat(client, "{green}闪光弹的发射次数已用完。");
			}
		}
	}

	Call_StartForward(g_hOnLaunchBombs_Post);
	Call_PushCell(client);
	Call_Finish();
}

void CreateFakeProp(int client)
{
	int result;
	Call_StartForward(g_hOnCreateFakeProp_Pre);
	Call_PushCell(client);
	Call_Finish(result);
	if (result > 2)
	{
		return;
	}
	if (g_iRoundState != 1 && g_iRoundState != 2)
	{
		CPrintToChat(client, "{green}现在不能创造假身。");
	}
	else if (g_iCreateFakeProps[client] == 0)
	{
		CPrintToChat(client, "{green}创造假身的次数已用完。");
	}
	else if (g_iPropNum[client] == -1)
	{
		CPrintToChat(client, "{green}未选择模型, 不能创建假身。");
	}
	else if (!GetPropInfo(client, 4, "", 0))
	{
		CPrintToChat(client, "{green}当前模型不允许创造假身。");
	}
	else if (g_bLockCamera[client])
	{
		CPrintToChat(client, "{green}锁定视角期间不允许创造假身。");
	}
	else if (!g_bLockCamera[client] && !(GetEntityFlags(client) & FL_ONGROUND))
	{
		CPrintToChat(client, "{green}不允许在空中创造假身。");
	}
	else
	{
		CreateProp(client, Prop_Fake);
	}
	SurvivorPropMenu(client);
}

void TpToFakeProp(int iClient)
{
	/*
	ModelInfo MI;
	g_hModelList.GetArray(g_iPropNum[iClient], MI);
	if (!MI.allowtp)
	{
		PrintToChat(iClient, "你当前的模型不允许使用该技能。");
		return;
	}
	*/
	if (HasValidProp(iClient) && !GetPropInfo(iClient, 3, "", 0))
	{
		CPrintToChat(iClient, "{green}你当前的模型不允许传送。");
		return;
	}
	if (g_hFakeProps[iClient].Length < 1)
	{
		CPrintToChat(iClient, "{green}你没有可以用于传送的假身噢!");
		return;
	}
	else if (g_iSkillCD[iClient] > 0)
	{
		CPrintToChat(iClient, "{green}技能冷却中, 请在{blue} %d {green}秒后再使用技能。", g_iSkillCD[iClient]);
		return;
	}
	Menu menu = new Menu(TpToFakePropMenuHandler);
	menu.SetTitle("想要传送到哪个假身?");
	for (int i = 0; i < g_hFakeProps[iClient].Length; i++)
	{
		int	 id = g_hFakeProps[iClient].Get(i);
		char sid[16];
		Format(sid, sizeof(sid), "%d", id);
		menu.AddItem(sid, sid);
	}
	menu.ExitBackButton = true;
	menu.Display(iClient, MENU_TIME_FOREVER);
}
int TpToFakePropMenuHandler(Menu menu, MenuAction action, int iClient, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Select:
		{
			if (GetClientTeam(iClient) != 2 || !IsPlayerAlive(iClient))
			{
				return 0;
			}
			char info[16];
			if (menu.GetItem(param2, info, sizeof(info)))
			{
				Action result;
				Call_StartForward(g_hOnTPFakeProp_Pre);
				Call_PushCell(iClient);
				Call_PushCell(StringToInt(info));
				Call_Finish(result);
				if (result == Plugin_Handled)
				{
					return 0;
				}
				int entity = StringToInt(info);
				if (!IsValidEdict(entity))
				{
					CPrintToChat(iClient, "{green}假身被摧毁了, 传送失败!");
					TpToFakeProp(iClient);
					return 0;
				}
				if (g_bLockCamera[iClient])
				{
					LockSelf(iClient);
				}
				float fOrigin[3];
				GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", fOrigin);
				float fAngles[3];
				GetEntPropVector(entity, Prop_Data, "m_angRotation", fAngles);
				TeleportEntity(iClient, fOrigin, fAngles);

				SDKUnhook(entity, SDKHook_OnTakeDamage, OnFakePropTakeDamage);
				AcceptEntityInput(entity, "Kill");
				int index = g_hFakeProps[iClient].FindValue(entity);
				if (index != -1)
				{
					g_hFakeProps[iClient].Erase(index);
				}
				PrintHintText(iClient, "传送完成。");
				SurvivorPropMenu(iClient);
				g_iSkillCD[iClient] = g_hSurvivorTPCD.IntValue;
				CreateTimer(1.0, Timer_SurvivorSkillCD, iClient, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);

				Call_StartForward(g_hOnTPFakeProp_Post);
				Call_PushCell(iClient);
				Call_Finish();
			}
		}
	}
	return 0;
}

void SelectModel(int client)
{
	if (g_hSelectList[client].Length == 0 && g_iPropDownCount[client] == 0)
	{
		CPrintToChat(client, "{green}你的刷新次数已用完。");
		return;
	}
	if (g_hSelectList[client].Length == 0)
	{
		int i = 0;
		do
		{
			int index = GetRandomInt(0, g_hModelList.Length - 1);
			if (g_hSelectList[client].FindValue(index) == -1)
			{
				g_hSelectList[client].Push(index);
				i++;
			}
		}
		while (i < 6);
		g_iPropDownCount[client]--;
	}
	Menu menu = new Menu(SelectModelMenuHandler);
	menu.SetTitle("模型选单~你还有 %d 次刷新机会", g_iPropDownCount[client]);
	for (int j = 0; j < g_hSelectList[client].Length; j++)
	{
		ModelInfo MI;
		g_hModelList.GetArray(g_hSelectList[client].Get(j), MI);
		char info[32];
		Format(info, sizeof(info), "%d", MI.modelnum);
		menu.AddItem(info, MI.sname);
	}
	if (g_iPropDownCount[client] > 0)
	{
		menu.AddItem("-1", "刷新选单");
	}
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int SelectModelMenuHandler(Menu menu, MenuAction action, int iClient, int param1)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if (param1 == MenuCancel_ExitBack)
				SurvivorPropMenu(iClient);
		}
		case MenuAction_Select:
		{
			if (GetClientTeam(iClient) != 2 || !IsPlayerAlive(iClient))
			{
				return 0;
			}
			char sModelNum[64];
			if (menu.GetItem(param1, sModelNum, sizeof(sModelNum)))
			{
				int iModelNum = StringToInt(sModelNum);
				if (iModelNum == -1)
				{
					g_hSelectList[iClient].Clear();
					SelectModel(iClient);
					return 0;
				}
				ModelInfo MI;
				g_hModelList.GetArray(iModelNum, MI);
				g_iPropNum[iClient] = iModelNum;
				PrecacheModel(MI.model, true);
				SetEntPropFloat(iClient, Prop_Send, "m_TimeForceExternalView", 99999.4);
				SetEntityModel(iClient, MI.model);
				OutPutModelInfo(iClient);
				if (IsValidEntity(g_iGlowEntity[iClient]))
				{
					AcceptEntityInput(g_iGlowEntity[iClient], "Kill");
				}
				CreatePropGlow(iClient);
				g_hSelectList[iClient].Clear();
				SurvivorPropMenu(iClient);
			}
		}
	}
	return 0;
}
void OutPutModelInfo(int client)
{
	ModelInfo MI;
	g_hModelList.GetArray(g_iPropNum[client], MI);
	CPrintToChat(client, "{default}你已选择模型:{green} %s {default}伤害修正为:{blue} %.2f", MI.sname, MI.dmgrevise);
	CPrintToChat(client, "%s", MI.allowtp ? "{blue}该模型允许飞雷神传送。" : "{red}该模型不能飞雷神传送。");
	CPrintToChat(client, "%s", MI.allowfake ? "{blue}该模型允许创造假身。" : "{red}该模型不能创造假身。");
	CPrintToChat(client, "{green}紫色光圈为实时模型角度, 用于快速确定方向\n按下右键可以把摄像机的x轴设置为0(便于模型的其余轴与光圈对齐))");
	CPrintToChat(client, "%s", g_hGlowInWater.BoolValue ? "{red}若你处于水中, 该紫圈会暴露给1500码内的克。" : "{blue}已禁用水中暴露紫圈。");
}

Action Timer_SurvivorSkillCD(Handle timer, int client)
{
	if (g_iSkillCD[client] > 0)
	{
		g_iSkillCD[client]--;
		return Plugin_Continue;
	}
	return Plugin_Stop;
}

Action Timer_ProtectCD(Handle timer, int client)
{
	if (g_iDetectProtectCD[client] > 0)
	{
		g_iDetectProtectCD[client]--;
		return Plugin_Continue;
	}
	CPrintToChat(client, "{green}[!]你的探测保护已解除。");
	return Plugin_Stop;
}

void PropProTect(int client)
{
	if (g_iRoundState == 0 || g_iRoundState == 3)
	{
		return;
	}
	if (!IsClientInGame(client) || GetClientTeam(client) != 2 || !IsPlayerAlive(client) || !g_bLockCamera[client])
	{
		if (IsValidEdict(g_iOwnProp[client]))
		{
			AcceptEntityInput(g_iOwnProp[client], "Kill");
		}
		return;
	}
	if (!IsValidEdict(g_iOwnProp[client]))
	{
		char sModel[128];
		GetPropInfo(client, 1, sModel, sizeof(sModel));
		int iProp = CreateEntityByName("prop_dynamic_override");
		if (!IsValidEntity(iProp))
		{
			return;
		}
		DispatchKeyValue(iProp, "model", sModel);
		DispatchKeyValue(iProp, "disableshadows", "1");
		SetEntProp(iProp, Prop_Data, "m_nSolidType", 6);
		DispatchSpawn(iProp);

		SetEntPropEnt(iProp, Prop_Send, "m_hOwnerEntity", client);
		SetEntityFlags(iProp, FL_CLIENT | FL_ATCONTROLS);

		float fix_origin[3];
		fix_origin[0] = g_fLockOrigin[client][0];
		fix_origin[1] = g_fLockOrigin[client][1];
		float zaxisup = GetPropInfo(client, 6, "", 0);
		fix_origin[2] = g_fLockOrigin[client][2] + zaxisup;
		TeleportEntity(iProp, fix_origin, g_fLockAngle[client], NULL_VECTOR);

		SDKHook(iProp, SDKHook_OnTakeDamage, OnRealPropTakeDamage);
		g_iOwnProp[client] = iProp;
	}
	RequestFrame(PropProTect, client);
}