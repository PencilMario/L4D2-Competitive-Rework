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
#include "simplevote.sp"
#define PropsFile "data/prophunt_props.txt"

KeyValues propinfos;
ConVar	  g_hAutoSetConvar;

public Plugin myinfo =
{
	name		= "L4D2 Prop Hunt",
	author		= "Nepkey",
	description = "躲猫猫玩法 - bug反馈请私信b站",
	version		= "1.03-release",
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
	RegConsoleCmd("sm_v28", CMD_VoteMode);

	g_hNavList = new ArrayList();
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_hFakeProps[i]	 = new ArrayList();
		g_hSelectList[i] = new ArrayList();
	}
	g_hHideTime		   = CreateConVar("l4d2_prophunt_hidetime", "90", "躲藏阶段持续时间");
	g_hSeekTime		   = CreateConVar("l4d2_prophunt_seektime", "440", "寻找阶段持续时间");
	g_hRandomTime	   = CreateConVar("l4d2_prophunt_randomtime", "140", "寻找阶段剩余多少秒时随机二变, 设置为0则禁用");
	g_hBasicDmg		   = CreateConVar("l4d2_prophunt_tankdmg", "25", "克的基础伤害");
	g_hGunDmg		   = CreateConVar("l4d2_prophunt_gundmg", "7", "持枪特感的基础伤害");
	g_hFlashCount	   = CreateConVar("l4d2_prophunt_flashcount", "3", "生还每回合闪光弹的数量");
	g_hVomitjarCount   = CreateConVar("l4d2_prophunt_vomitjarcount", "3", "生还每回合胆汁的数量");
	g_hTankDetectCD	   = CreateConVar("l4d2_prophunt_detectcd", "30", "克探测技能的CD");
	g_hTankDetectcount = CreateConVar("l4d2_prophunt_detectcount", "5", "克一次探测报告多少次位置");
	g_hTankTPCD		   = CreateConVar("l4d2_prophunt_tanktpcd", "20", "克传送技能的CD");
	g_hSurvivorTPCD	   = CreateConVar("l4d2_prophunt_survivortpcd", "120", "生还飞雷神技能的CD");
	g_hFakePropCount   = CreateConVar("l4d2_prophunt_fakepropcount", "3", "生还能放的假身数量");
	g_hPropDownCount   = CreateConVar("l4d2_prophunt_loadpropcount", "3", "生还刷新模型选单列表的次数");
	g_hDetectProtectCD = CreateConVar("l4d2_prophunt_detectdedprotect", "60", "生还被探测的保护时间");
	g_hAllowInWater	   = CreateConVar("l4d2_prophunt_allowinwater", "0", "是否允许生还在水里锁定视角");
	g_hGlowInWater	   = CreateConVar("l4d2_prophunt_glowinwater", "1", "水里的未锁定视角的生还是否会被克看到其紫色光圈");
	g_hAutoSetConvar   = CreateConVar("l4d2_prophunt_autocvar", "1", "插件是否自行更改cvar");
	g_hAutoJG		   = CreateConVar("l4d2_prophunt_autojg", "1", "插件是否在下一章节自动将旁观扔进队伍里");
	g_hSurvivorLimit   = CreateConVar("l4d2_prophunt_survivorlimit", "14", "允许的最大生还数量");
	g_hTankLimit	   = CreateConVar("l4d2_prophunt_tanklimit", "14", "允许的最大特感数量");
	g_hDifferenceMax   = CreateConVar("l4d2_prophunt_teamdiffmax", "2", "允许队伍相差的人数, 达到此数值时阻止玩家进入人数较多的队伍(请勿设置为0)");
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
	PrecacheModel("models/survivors/tank_namvet.mdl", true);

	g_bMultiMode ? ServerCommand("exec prophunt/prophun_14hunman.cfg") : ServerCommand("exec prophunt/prophun_28hunman.cfg");
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
		g_iPropDownCount[i]	  = g_hPropDownCount.IntValue + 1;
		g_iPropNum[i]		  = -1;
		g_iSkillCD[i]		  = 0;
		g_iDetectProtectCD[i] = 0;
		g_iVomitjar[i]		  = g_hVomitjarCount.IntValue;
		g_iPipeBomb[i]		  = g_hFlashCount.IntValue;
		g_iCreateFakeProps[i] = g_hFakePropCount.IntValue;
		g_iOwnProp[i]		  = -1;
		g_iGlowEntity[i]	  = -1;
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
		if (g_hInterrupt_UI != INVALID_HANDLE)
		{
			KillTimer(g_hInterrupt_UI);
			g_hInterrupt_UI = INVALID_HANDLE;
		}
		SetSIAngleLock(SetSI_Lock);
		g_hInterrupt_UI = CreateTimer(1.0, Timer_Freeze_UI, GetGameTime() + 20.0, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
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
	if (GetClientTeam(client) != 1)
	{
		ChangeClientTeam(client, 1);
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
					if (PlayerStatistics(2, false) > g_hSurvivorLimit.IntValue)
					{
						CPrintToChat(iClient, "{green}目标队伍人数已达上限, 请加入特感队伍。");
					}
					else if (PlayerStatistics(2, false) >= PlayerStatistics(3, false) + g_hDifferenceMax.IntValue)
					{
						CPrintToChat(iClient, "{green}双方人数差达到 %d, 请加入特感队伍。", g_hDifferenceMax.IntValue);
					}
					else
					{
						ChangeClientTeam(iClient, 2);
						if (g_iRoundState == 0 || g_iRoundState == 1)
						{
							L4D_RespawnPlayer(iClient);
						}
					}
				}
				case 1:
				{
					if (PlayerStatistics(3, false) > g_hTankLimit.IntValue)
					{
						CPrintToChat(iClient, "{green}目标队伍人数已达上限, 请加入生还队伍。");
					}
					else if (PlayerStatistics(3, false) >= PlayerStatistics(2, false) + g_hDifferenceMax.IntValue)
					{
						CPrintToChat(iClient, "{green}双方人数差达到 %d, 请加入生还队伍。", g_hDifferenceMax.IntValue);
					}
					else
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
	}
	return 0;
}

Action CMD_VoteMode(int client, int args)
{
	if (!g_bMultiMode)
	{
		s_CallVote(client, "将游戏数据设置为28人规格?", VoteMode);
	}
	else
	{
		s_CallVote(client, "将游戏数据设置为14人规格?", VoteMode);
	}
}
void VoteMode(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (IsVotePass(vote, num_votes, num_clients, client_info, num_items, item_info))
	{
		g_bMultiMode ? ServerCommand("exec prophunt_14hunman.cfg") : ServerCommand("exec prophunt_28hunman.cfg");
		g_bMultiMode = !g_bMultiMode;
		if(g_iRoundState == 0)
		{
			CPrintToChatAll("{green}已切换到对应规格的设置。");
		}
		else
		{
			CPrintToChatAll("{green}已切换到对应规格的设置, 下回合生效。");
		}
	}
}