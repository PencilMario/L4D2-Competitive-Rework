#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <l4d2util>
#include <left4dhooks>
#include <colors>
#include <sdkhooks>

#include <prophunt_single>

#include "prophunt_single\global_symbol.sp"
#include "prophunt_single\nativeNforwards.sp"
#include "prophunt_single\events.sp"
#include "prophunt_single\ph_helpers.sp"
#include "prophunt_single\otherforwards.sp"
#include "prophunt_single\survivor_menu.sp"
#include "prophunt_single\tank_menu.sp"
#include "prophunt_single\UI.sp"

#include "NepKeyValues.sp"
#define PropsFile "data/prophunt_props.txt"

KeyValues propinfos;
ConVar	  g_hAutoSetConvar;

public Plugin myinfo =
{
	name		= "L4D2 Prop Hunt",
	author		= "Nepkey",
	description = "躲猫猫玩法 - bug反馈请私信b站",
	version		= "1.01-release",
	url			= "null"
};

public void OnPluginStart()
{
	SetupNativeNForwards();
	HookTheEvents();
	LoadPropInfos();
	CreateTimer(1.0, Timer_Repeat_UI, _, TIMER_REPEAT);

	RegConsoleCmd("sm_prop", CMD_Prop);
	RegConsoleCmd("sm_jg", CMD_JG);

	g_hNavList = new ArrayList();
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_hFakeProps[i] = new ArrayList();
		g_hSelectList[i] = new ArrayList();
	}
	g_hHideTime		 = CreateConVar("l4d2_prophunt_hidetime", "90", "躲藏阶段持续时间");
	g_hSeekTime		 = CreateConVar("l4d2_prophunt_seektime", "420", "寻找阶段持续时间");
	g_hRandomTime	 = CreateConVar("l4d2_prophunt_randomtime", "120", "寻找阶段剩余多少秒时随机二变, 设置为0则禁用");
	g_hBasicDmg		 = CreateConVar("l4d2_prophunt_tankdmg", "25", "克的基础伤害");
	g_hGunDmg		 = CreateConVar("l4d2_prophunt_gundmg", "7", "持枪特感的基础伤害");
	g_hAutoSetConvar = CreateConVar("l4d2_prophunt_autocvar", "1", "插件是否自行更改cvar");
	
	// debug
	// RegAdminCmd("sm_dir", cmd_dir, ADMFLAG_KICK);
	// RegAdminCmd("sm_dir2", cmd_dir2, ADMFLAG_KICK);
}

public void OnPluginEnd()
{
	ResetConVar(FindConVar("sb_stop"));
	ResetConVar(FindConVar("survivor_max_incapacitated_count"));
	ResetConVar(FindConVar("pipe_bomb_timer_duration"));
	ResetConVar(FindConVar("sv_noclipspeed"));
	ResetConVar(FindConVar("z_frustration"));
}

public void LoadPropInfos()
{
	g_hModelList = new ArrayList(sizeof(ModelInfo));
	propinfos	 = InitializeKV(PropsFile, "prophunt_props");
	propinfos.GotoFirstSubKey();

	ModelInfo MI;
	do
	{
		char smodelnum[32];
		propinfos.GetSectionName(smodelnum, sizeof(smodelnum));
		MI.modelnum = StringToInt(smodelnum);
		propinfos.GetString("model", MI.model, sizeof(MI.model));
		propinfos.GetString("sname", MI.sname, sizeof(MI.sname));
		int iallowtp   = propinfos.GetNum("allowtp");
		MI.allowtp	   = view_as<bool>(iallowtp);
		int iallowfake = propinfos.GetNum("allowfake");
		MI.allowfake   = view_as<bool>(iallowfake);
		MI.dmgrevise   = propinfos.GetFloat("dmgrevise");
		MI.zaxisup	   = propinfos.GetFloat("zaxisup");
		g_hModelList.PushArray(MI);
	}
	while (propinfos.GotoNextKey());

	delete propinfos;
}

public void OnMapStart()
{
	RequestFrame(GetAllNavAreas, g_hNavList);

	AddFileToDownloadsTable("models/survivors/tank_namvet.mdl");
	AddFileToDownloadsTable("models/survivors/tank_namvet.phy");
	AddFileToDownloadsTable("models/survivors/tank_namvet.vvd");
	AddFileToDownloadsTable("models/survivors/tank_namvet.dx90.vtx");

	g_iRoundState = 0;
	Call_StartForward(g_hOnReadyStage_Post);
	Call_Finish();
}

public void OnReadyStage_Post()
{
	//重设数据
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bLockCamera[i]	  = false;
		g_iPropDownCount[i]	  = 4;
		g_iPropNum[i]		  = -1;
		g_iSkillCD[i]		  = 0;
		g_iVomitjar[i]		  = 3;
		g_iPipeBomb[i]		  = 3;
		g_iTankType[i]		  = 0;
		g_iTankAbility[i]	  = 0;
		g_iCreateFakeProps[i] = 3;
		g_hFakeProps[i].Clear();
		g_hSelectList[i].Clear();
	}
}

public void OnHidingStage_Post()
{
	// Convar设定
	CreateTimer(7.0, Timer_Delay_SetConvars, _, TIMER_FLAG_NO_MAPCHANGE);
	//锁定路程分
	L4D_SetVersusMaxCompletionScore(0);
	g_iHideTime = g_hHideTime.IntValue;
	g_iSeekTime = g_hSeekTime.IntValue;
	//将地图上的物理对象和物体进行转化
	ConvertProps();
	//将特感传送至随机起点并重生为克
	TPTanksToRandomStartPoint();
	SpawnTanks();
	//锁定克视角
	SetSIAngleLock(SetSI_Lock);
	//将终点安全室的门传走
	SetSafeRoomDoors(SafeDoor_End, SafeDoor_Displace);
	//开启躲藏倒计时
	CreateTimer(1.0, Timer_HidingTimeCountDown, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public void OnSeekingStage_Post()
{
	//处死AI
	KillPlayers(2, true);
	//动态处理回合时间
	DynamickSeekingTime();
	//解锁特感视角
	SetSIAngleLock(SetSI_Unlock);
	//开启搜寻倒计时
	CreateTimer(1.0, Timer_SeekingTimeCountDown, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public void OnEndStage_Post()
{
	//将所有处于锁定状态的生还解锁
	UnlockAngleALL();
	//杀死所有特感
	KillPlayers(3, false);
	// 20秒后杀死生还
	CreateTimer(20.0, Timer_KillAll, _, TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_HidingTimeCountDown(Handle timer)
{
	if (g_iRoundState != 1)
	{
		return Plugin_Stop;
	}
	if (g_iHideTime < 1)
	{
		g_iRoundState = 2;
		Call_StartForward(g_hOnSeekingStage_Post);
		Call_Finish();
		return Plugin_Stop;
	}
	g_iHideTime--;
	return Plugin_Continue;
}

Action Timer_SeekingTimeCountDown(Handle timer)
{
	if (g_iRoundState != 2)
	{
		return Plugin_Stop;
	}
	if (g_hRandomTime.IntValue != 0 && g_iSeekTime == g_hRandomTime.IntValue + 20 && g_iRoundState == 2)
	{
		g_hInterrupt_UI = CreateTimer(1.0, Timer_Interrupt_UI, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	if (g_hRandomTime.IntValue != 0 && g_iSeekTime == g_hRandomTime.IntValue && g_iRoundState == 2)
	{
		delete g_hInterrupt_UI;
		RandomModelAll();
	}
	if (g_iSeekTime < 1)
	{
		g_iWinnerTeam = 2;
		g_iRoundState = 3;
		Call_StartForward(g_hOnEndStage_Post);
		Call_Finish();
		return Plugin_Stop;
	}
	g_iSeekTime--;
	return Plugin_Continue;
}
Action Timer_KillAll(Handle Timer)
{
	if (g_iRoundState != 3)
	{
		return Plugin_Stop;
	}
	KillPlayers(2, false);
	return Plugin_Stop;
}

Action Timer_Delay_SetConvars(Handle timer)
{
	if (g_hAutoSetConvar.BoolValue)
	{
		SetConVarInt(FindConVar("survivor_max_incapacitated_count"), 0);
		SetConVarInt(FindConVar("z_frustration"), 0);
		SetConVarFloat(FindConVar("pipe_bomb_timer_duration"), 0.5);
		SetConVarFloat(FindConVar("sv_noclipspeed"), 1.2);
		SetConVarInt(FindConVar("sb_stop"), 1);
	}
	return Plugin_Stop;
}

Action CMD_Prop(int client, int args)
{
	if (IsValidClientIndex(client) && GetClientTeam(client) == 2)
	{
		SurvivorPropMenu(client);
	}
	else if (IsValidClientIndex(client) && GetClientTeam(client) == 3)
	{
		TankMenu(client);
	}
	else
	{
		ReplyToCommand(client, "[Prop]您所在的队伍不允许使用该指令。");
	}
	return Plugin_Handled;
}

Action CMD_JG(int client, int args)
{
	if (PlayerStatistics(0, false) <= 8)
	{
		CPrintToChat(client, "{olive}此功能只允许在服务器人数大于 {blue}8 {olive}时使用。");
		return Plugin_Handled;
	}
	Menu menu = new Menu(JGMenuHandler);
	menu.SetTitle("加入到哪边?");
	menu.AddItem("0", "- 生还者队伍 -");
	menu.AddItem("1", "- 感染者队伍 -");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

int JGMenuHandler(Menu menu, MenuAction action, int iClient, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0:
				{
					ChangeClientTeam(iClient, 2);
					if (g_iRoundState == 0 || g_iRoundState == 1)
					{
						L4D_RespawnPlayer(iClient);
					}
				}
				case 1:
				{
					ChangeClientTeam(iClient, 3);
					if (g_iRoundState == 1)
					{
						float pos[3];
						L4D_GetRandomPZSpawnPosition(iClient, 8, 100, pos);
						TeleportEntity(iClient, pos);
						CheatCommand(iClient, "z_spawn_old tank");
						float eyeAngles[3];
						GetClientEyeAngles(iClient, eyeAngles);
						eyeAngles[0] = 89.00;
						TeleportEntity(iClient, NULL_VECTOR, eyeAngles, NULL_VECTOR);
						SetEntityFlags(iClient, FL_CLIENT | FL_FROZEN);
					}
				}
			}
		}
	}
	return 0;
}

/*
Action cmd_dir(int client, int args)
{
	//CreateTimer(2.5, Timer_Repeats, client, TIMER_REPEAT);
}

Action cmd_dir2(int client, int args)
{
	ModelInfo MI;
	PrintToChatAll("有效模型数量：%d", g_hModelList.Length);

	for (int i = 0; i < g_hModelList.Length; i++)
	{
		g_hModelList.GetArray(i, MI);
		PrintToServer("模型序号：%d", MI.modelnum);
		PrintToServer("模型路径：%s", MI.model);
		PrintToServer("模型名称：%s", MI.sname);
		if (MI.allowtp) PrintToServer("允许传送");
		if (MI.allowtp) PrintToServer("允许假身");
		PrintToServer("伤害修正：%.2f", MI.dmgrevise);
		PrintToServer("z轴修正：%.2f", MI.zaxisup);
		PrintToServer("-----模型输出信息输出结束-----");
	}

}

Action Timer_Repeats(Handle timer, int client)
{
	int args = 0;
	if (args < 1)
	{
		if (g_iPropNum[client] < g_hModelList.Length)
		{
			g_iPropNum[client]++;
		}
		else
		{
			g_iPropNum[client] = g_hModelList.Length - 1;
			return Plugin_Stop;
		}
	}
	char modelpath[128];
	char modelname[64];
	GetPropInfo(client, 1, modelpath, sizeof(modelpath));
	GetPropInfo(client, 2, modelname, sizeof(modelname));
	PrecacheModel(modelpath, true);
	SetEntPropFloat(client, Prop_Send, "m_TimeForceExternalView", 99999.4);
	SetEntityModel(client, modelpath);

	PrintToChat(client, "模型序号:%d,模型路径:%s,模型名称:%s", GetPropInfo(client, 0, "", 0), modelpath, modelname);
	PrintToChat(client, "%s,%s", GetPropInfo(client, 4, "", 0) ? "允许传送" : "不允许传送", GetPropInfo(client, 5, "", 0) ? "允许假身" : "不允许假身");
	PrintToChat(client, "伤害修正:%.2f,z轴修正:%.2f", GetPropInfo(client, 5, "", 0), GetPropInfo(client, 6, "", 0));
	return Plugin_Continue;
}
*/