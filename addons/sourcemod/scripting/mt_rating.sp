#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>
#include <mix_team>
#include <l4d2_round_ratingpro>

#include "include/mt_balance.inc"


public Plugin myinfo = {
	name = "MixTeamRating",
	author = "Codex",
	description = "按最近 N 场平均 RatingPro 分队的 mix 类型",
	version = "build_0001",
	url = "https://github.com/TouchMe-Inc/l4d2_mix_team"
};


// Libs
#define LIB_MIX_TEAM            "mix_team"
#define LIB_RATINGPRO           "l4d2_round_ratingpro"

// Other
#define TRANSLATIONS            "mt_rating.phrases"
#define MIX_TYPE                "rating"    // !mix rating
#define MIN_PLAYERS             4


ConVar
	g_hRequireData = null,
	g_hDefaultRating = null;

// 强度分与「是否用了缺省值」，均以 client index 为键，供 mt_balance 使用
float
	g_fScores[MAXPLAYERS + 1];

bool
	g_bFallback[MAXPLAYERS + 1],
	g_bAnyFallback = false,
	g_bMixTeamAvailable = false,
	g_bRatingProAvailable = false,
	g_bMixRegistered = false,
	g_bWarned = false;


/**
 * Called before OnPluginStart.
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_Left4Dead2) {
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	// 允许服务器不装 l4d2_round_ratingpro：此时本插件仍会加载，只是不注册 !mix rating。
	MarkNativeAsOptional("RatingPro_IsClientDataReady");
	MarkNativeAsOptional("RatingPro_GetClientRecentRating");

	return APLRes_Success;
}

/**
 * Loads dictionary files. On failure, stops the plugin execution.
 */
void InitTranslations()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "translations/" ... TRANSLATIONS ... ".txt");

	if (FileExists(sPath)) {
		LoadTranslations(TRANSLATIONS);
	} else {
		SetFailState("Path %s not found", sPath);
	}
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 */
public void OnPluginStart()
{
	InitTranslations();

	g_hRequireData = CreateConVar("sm_mt_rating_require_data", "1",
		"缺少最近 RatingPro 数据时是否取消本次 mix：1 = 取消，0 = 用 sm_mt_rating_default_rating 补齐",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_hDefaultRating = CreateConVar("sm_mt_rating_default_rating", "5.0",
		"sm_mt_rating_require_data=0 时，没有 RatingPro 数据的玩家使用的占位平均分（0-10）",
		FCVAR_NONE, true, 0.0, true, 10.0);
}

/**
 * Global event. Called when all plugins loaded.
 */
public void OnAllPluginsLoaded()
{
	RefreshLibraries();
	TryRegisterMix();
}

/**
 * Global event. Called when a library is added.
 */
public void OnLibraryAdded(const char[] sName)
{
	RefreshLibraries();
	TryRegisterMix();
}

/**
 * Global event. Called when a library is removed.
 */
public void OnLibraryRemoved(const char[] sName)
{
	RefreshLibraries();
}

/**
 * 记录依赖库是否可用：缺任何一个都不注册分队类型。
 */
void RefreshLibraries()
{
	g_bMixTeamAvailable = LibraryExists(LIB_MIX_TEAM);
	g_bRatingProAvailable = LibraryExists(LIB_RATINGPRO);
}

/**
 * 依赖齐全且尚未注册时，把 !mix rating 挂到 mix_team 的列表里。
 */
void TryRegisterMix()
{
	if (g_bMixRegistered) {
		return;
	}

	if (!g_bMixTeamAvailable || !g_bRatingProAvailable)
	{
		// 库可能在稍后才加载，这里只在第一次缺依赖时记一条日志，避免刷屏
		if (!g_bWarned)
		{
			LogError("[MixTeamRating] 缺少 %s 或 %s，!mix " ... MIX_TYPE ... " 不会注册",
				LIB_MIX_TEAM, LIB_RATINGPRO);
			g_bWarned = true;
		}

		return;
	}

	// 一队人数上限由 survivor_limit 决定，人数最少要能凑出两队
	ConVar hSurvivorLimit = FindConVar("survivor_limit");
	int iMaxPerTeam = (hSurvivorLimit != null) ? hSurvivorLimit.IntValue : 4;
	int iMinPlayers = iMaxPerTeam * 2;

	AddMix(MIX_TYPE, (iMinPlayers < MIN_PLAYERS) ? MIN_PLAYERS : iMinPlayers, 0);
	g_bMixRegistered = true;
}

/**
 * 投票标题。由 mix_team 按名字查找调用。
 */
public void GetVoteDisplayMessage(int iClient, char[] sTitle) {
	Format(sTitle, DISPLAY_MSG_SIZE, "%T", "VOTE_DISPLAY_MSG", iClient);
}

/**
 * 投票通过后的提示。由 mix_team 按名字查找调用。
 */
public void GetVoteEndMessage(int iClient, char[] sMsg) {
	Format(sMsg, VOTEEND_MSG_SIZE, "%T", "VOTE_END_MSG", iClient);
}

/**
 * Starting the mix.
 */
public Action OnMixInProgress()
{
	if (!g_bMixTeamAvailable || !g_bRatingProAvailable)
	{
		CPrintToChatAll("%t", "MIX_UNAVAILABLE");
		Call_AbortMix();
		return Plugin_Handled;
	}

	int[] iClients = new int[MT_BALANCE_MAX_PLAYERS];
	int iCount = MtBalanceCollectMembers(iClients, MT_BALANCE_MAX_PLAYERS);

	int iMaxPerTeam = 4;
	ConVar hSurvivorLimit = FindConVar("survivor_limit");

	if (hSurvivorLimit != null) {
		iMaxPerTeam = hSurvivorLimit.IntValue;
	}

	int iTeamSize = MtBalanceResolveTeamSize(iCount, iMaxPerTeam);

	if (iTeamSize < 1)
	{
		CPrintToChatAll("%t", "MIX_NOT_ENOUGH_PLAYERS");
		Call_AbortMix();
		return Plugin_Handled;
	}

	// 读取每个人最近 N 场的平均 RatingPro；缺数据时按 sm_mt_rating_require_data 决定取消还是补默认值
	g_bAnyFallback = false;

	for (int i = 0; i < iCount; i++)
	{
		int iClient = iClients[i];
		float fAverage = 0.0;
		float fAverageRaw = 0.0;
		int iSamples = 0;
		bool bReady = false;

		if (RatingPro_IsClientDataReady(iClient)
		&& RatingPro_GetClientRecentRating(iClient, fAverage, fAverageRaw, iSamples)
		&& iSamples > 0
		&& fAverage > 0.0) {
			bReady = true;
		}

		if (!bReady)
		{
			if (g_hRequireData.BoolValue)
			{
				char sName[MAX_NAME_LENGTH];
				GetClientName(iClient, sName, sizeof(sName));

				CPrintToChatAll("%t", "MIX_NO_DATA", sName);
				Call_AbortMix();
				return Plugin_Handled;
			}

			fAverage = g_hDefaultRating.FloatValue;
			g_bFallback[iClient] = true;
			g_bAnyFallback = true;
		}

		else {
			g_bFallback[iClient] = false;
		}

		g_fScores[iClient] = fAverage;
	}

	// 排序 + 分队：人数对半，两边平均 RatingPro 总和尽量接近
	MtBalanceSortDesc(iClients, iCount, g_fScores);

	int[] iSurvivors = new int[MT_BALANCE_MAX_PLAYERS];
	int[] iInfected = new int[MT_BALANCE_MAX_PLAYERS];

	MtSplit tSplit;
	MtBalanceSplit(iClients, iCount, iTeamSize, g_fScores, iSurvivors, iInfected, tSplit);

	if (!MtBalanceApply(iSurvivors, iTeamSize, iInfected, iTeamSize, TEAM_SURVIVOR, TEAM_INFECTED))
	{
		CPrintToChatAll("%t", "MIX_ASSIGN_FAILED");
		Call_AbortMix();
		return Plugin_Handled;
	}

	char sDiff[MT_BALANCE_VALUE_SIZE];
	Format(sDiff, sizeof(sDiff), "%.2f", tSplit.diff);

	CPrintToChatAll("%t", "MIX_HEADER", iCount, iTeamSize, sDiff);
	MtBalancePrintTeam("SURVIVORS_LINE", "SURVIVORS_LINE_MORE", iSurvivors, iTeamSize, g_fScores, g_bFallback, 2);
	MtBalancePrintTeam("INFECTED_LINE", "INFECTED_LINE_MORE", iInfected, iTeamSize, g_fScores, g_bFallback, 2);

	if (tSplit.leftover > 0) {
		CPrintToChatAll("%t", "MIX_LEFTOVER", tSplit.leftover);
	}

	if (g_bAnyFallback) {
		CPrintToChatAll("%t", "MIX_FALLBACK_NOTE");
	}

	return Plugin_Continue;
}
