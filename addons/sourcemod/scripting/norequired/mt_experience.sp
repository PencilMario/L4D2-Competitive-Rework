#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>
#include <mix_team>
#include <steamworks>

enum struct Player{
	int id;
	int rankpoint; // Unfortunately, it's zero here.
	int gametime;
	int tankrocks;
	float winrounds;
	int versustotal;
	int versuswin;
	int versuslose;
	int smgkills;
	int shotgunkills;
	int type;
}
ArrayList g_Lteam1, g_Lteam2, g_Lplayers;
Player tempPlayer;
ConVar temp_prp;
ConVar g_team_allocation;
Handle h_mixTimer;
int g_iPlayerRP[MAXPLAYERS + 1] = {-1};
int g_iTeamData[3];
int g_iCheckingClientRPid = 0;  
int g_iMaxRetry = 5;        
bool g_bchecking = false;               // Retrieve the RP status of a single player.
bool g_bcheckfinished = false;          // All members of the mix have been checked.


public Plugin myinfo = { 
	name = "MixTeamExperience",
	author = "SirP",
	description = "Adds mix team by game experience",
	version = "1.2.0"
};


#define TRANSLATIONS            "mt_experience.phrases"

#define MIN_PLAYERS             8

// Player type
#define PTYPE_SMG               0
#define PTYPE_SHOTGUN           1

// Macros
#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_REAL_CLIENT(%1)      (IsClientInGame(%1) && !IsFakeClient(%1))


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
	g_Lplayers = new ArrayList(sizeof(Player));
	temp_prp = CreateConVar("itemp_prp", "-1", "TempVariable");
	g_team_allocation = CreateConVar("sm_mix_exp_type", "1", "强制选择MIX的分队算法。0=自动选择 1=尽量平均(Average) 2=尽量平衡(Balance) 3=优先喷子(Slot)");

}

public void OnAllPluginsLoaded() {
	AddMix("exp", MIN_PLAYERS, 0);
}

public void GetVoteDisplayMessage(int iClient, char[] sDisplayMsg) {
	Format(sDisplayMsg, DISPLAY_MSG_SIZE, "%T", "VOTE_DISPLAY_MSG", iClient);
}

public void GetVoteEndMessage(int iClient, char[] sMsg) {
	Format(sMsg, VOTEEND_MSG_SIZE, "%T", "VOTE_END_MSG", iClient);
}


/**
 * The main process of MIX. 
 * Although there may be more efficient ways to implement it, I don't want to change it XD
 * 
 * @noreturn    
 */

public Action TimerCallback(Handle timer)
{
	if (g_iCheckingClientRPid == 0){
		CPrintToChatAll("%t", "START_GET_INFO");
		g_iCheckingClientRPid++;
	}
	while (g_iCheckingClientRPid <= MaxClients)
	{
		if (g_bchecking) break;
		if (!IsClientInGame(g_iCheckingClientRPid) || !IsMixMember(g_iCheckingClientRPid) || IsFakeClient(g_iCheckingClientRPid)) {
			g_iCheckingClientRPid++;
		}
		else
		{
			break;
		}
	}
	
	if(!g_bchecking){
		g_bchecking = true;

		int res = GetClientRP(g_iCheckingClientRPid);
		if (res == -2){
			if (g_iMaxRetry > 0){
				//CPrintToConsoleAll("%t", "FAIL_PLAYER_INFO_RETRY", g_iCheckingClientRPid, g_iMaxRetry);
				temp_prp.IntValue = -1;
				g_iMaxRetry--;
				g_bchecking = false;
				return Plugin_Continue;
			}
			else {
				CPrintToChatAll("%t", "FAIL_PLAYER_HIDE_INFO_STOP", g_iCheckingClientRPid);
				OnMixFailed("");
				Call_AbortMix();
				return Plugin_Stop;  
			}
		}
	}
	g_iMaxRetry = 5;
	if (g_iCheckingClientRPid > MaxClients) g_bcheckfinished = true;
	if (!g_bcheckfinished){
		if (temp_prp.IntValue == -1){
			return Plugin_Continue;
		} else {
			g_iPlayerRP[g_iCheckingClientRPid] = temp_prp.IntValue;
			g_bchecking = false;
		}
		g_bchecking = false;

		g_iCheckingClientRPid++;
		if (g_iCheckingClientRPid <= MaxClients){
			return Plugin_Continue;
		}
	}
	
	CPrintToChatAll("%t", "CHECK_DONE");
	MixMembers();
	Call_FinishMix();
	return Plugin_Stop;
}

/** 
 * Called when the mix operation fails.
 * 
 * @noreturn
 */
public void OnMixFailed(const char[] sMixName){
	KillTimer(h_mixTimer);
	h_mixTimer = INVALID_HANDLE;
}


/**
 * After obtaining the RP of all team members, 
 * traverse and save the function's results that have the smallest point difference between the two sides.
 * 
 * @noreturn
 * */
void MixMembers(){
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || !IsMixMember(iClient)) {
			continue;
		}
		if (g_iPlayerRP[iClient] == -1) continue;
		tempPlayer.id = iClient;
		tempPlayer.rankpoint = g_iPlayerRP[iClient];
		g_Lplayers.PushArray(tempPlayer);
	}
	g_Lplayers.SortCustom(SortByRank);
	int surrankpoint, infrankpoint = 0;

	SelAndMix();

	PrintToConsoleAll("%t", "EXP_EQUATION");
	PrintToConsoleAll("-----------------------------------------------------------");

	for (int i = 0; i < g_Lteam1.Length; i++)
	{
		g_Lteam1.GetArray(i, tempPlayer);
		if (IsMixMember(tempPlayer.id)) SetClientTeam(tempPlayer.id, TEAM_SURVIVOR);
		surrankpoint += g_iPlayerRP[tempPlayer.id];
	}
	for (int i = 0; i < g_Lteam2.Length; i++)
	{
		g_Lteam2.GetArray(i, tempPlayer);
		if (IsMixMember(tempPlayer.id)) SetClientTeam(tempPlayer.id, TEAM_INFECTED);
		infrankpoint += g_iPlayerRP[tempPlayer.id];
	}
	g_iTeamData[0] = surrankpoint;
	g_iTeamData[1] = infrankpoint;
	g_iTeamData[2] = abs(surrankpoint - infrankpoint);
	CreateTimer(2.0, PrintResult);
}

/**
 * Starting the mix.
 */
public Action OnMixInProgress()
{
	g_Lplayers.Clear();
	g_iCheckingClientRPid = 0;
	g_bchecking = false;
	g_bcheckfinished = false;
	h_mixTimer = CreateTimer(0.5, TimerCallback, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	return Plugin_Handled;
}

int SortByRank(int indexFirst, int indexSecond, Handle hArrayList, Handle hndl)
{
	Player tPlayerFirst, tPlayerSecond;

	GetArrayArray(hArrayList, indexFirst, tPlayerFirst);
	GetArrayArray(hArrayList, indexSecond, tPlayerSecond);

	if (g_iPlayerRP[tPlayerFirst.id] < g_iPlayerRP[tPlayerSecond.id]) {
		return -1;
	}

	if (g_iPlayerRP[tPlayerFirst.id] > g_iPlayerRP[tPlayerSecond.id]) {
		return 1;
	}

	return 0;
}

/**
 * Calculate the difference in RP between the two groups of players.
 * 
 * @param array1    The first group of players.
 * @param array2    The second group of players.
 * @return          Point differential.
 */
int diff_sum(ArrayList array1, ArrayList array2)
{
	int sum1 = 0;
	int sum2 = 0;
	for (int i = 0; i < array1.Length; i++)
	{
		array1.GetArray(i, tempPlayer);
		sum1 += g_iPlayerRP[tempPlayer.id];
	}
	for (int i = 0; i < array2.Length; i++)
	{
		array2.GetArray(i, tempPlayer);
		sum2 += g_iPlayerRP[tempPlayer.id];
	}
	return abs(sum1 - sum2);
}

/**
 * Output the result when the mix is finished.
 * Retrieve the data from the global variable "g_iTeamData".
 * 
 * g_iTeamData[0] - Survivors RP
 * g_iTeamData[1] - Infected RP
 * g_iTeamData[2] - difference between the two teams
 * 
 * This approach is necessary as it appears that passing multiple arguments into 
 * the "CreateTimer()" function is not possible (or beyond my current ability).
 */
public Action PrintResult(Handle timer)
{
	CPrintToChatAll("%t", "MIX_FINISH");
	CPrintToChatAll("%t", "SUR_TOTAL_RP", g_iTeamData[0]);
	CPrintToChatAll("%t", "INF_TOTAL_RP", g_iTeamData[1]);
	CPrintToChatAll("%t", "DIFF_RP", g_iTeamData[2]);
	CPrintToChatAll("%t", "HINT_CONSOLE");
	return Plugin_Stop;
}

void PrintMixMethod(int type)
{
	switch (type){
		case 1:
		{
			CPrintToChatAll("%t", "MIXMETHOD_AVERAGE");
		}
		case 2:
		{
			CPrintToChatAll("%t", "MIXMETHOD_BALANCE");
		}
		case 3:
		{
			CPrintToChatAll("%t", "MIXMETHOD_SLOT");
		}
		default:
		{
			CPrintToChatAll("%t", "MIXMETHOD_BALANCE");
		}
	}
}

/**
 * Select a feasible mixing method.
 * 
 * Slot - Attempt to ensure that both parties have one shotgun player can each, 
 *        and distribute the remaining cans equally among the other individuals.
 * Average - Ensure that the scores of both parties are as evenly distributed as possible, 
 *           but the score difference among all individuals cannot be greater than 2000.
 * Balance - Both parties have similar overall strength and composition.
 * 
 * @noreturn
 */
void SelAndMix(){
	bool result;
	if (!g_team_allocation.IntValue){
		if (slot_diff()){
			PrintMixMethod(3);
		}else if(min_diff()){
			PrintMixMethod(1);
		}else if(balance_diff()){
			PrintMixMethod(2);
		}
	}else{
		switch (g_team_allocation.IntValue){
			case 1:
			{
				result = min_diff(true);
			}
			case 2:
			{
				result = balance_diff();
			}
			case 3:
			{
				result = slot_diff();
			}
			default:
			{
				result = balance_diff();
			}
		}
		if (!result){
			CPrintToChatAll("%t", "MIXMETHOD_FAIL");
			Call_AbortMix();
			OnMixFailed("");
		}
		else
		{
			PrintMixMethod(g_team_allocation.IntValue);
		}
	}
}

/**
 * Allocate based on the players' preferred weapons. 
 * Prioritize ensuring that each team has one shotgun player (top 4 ranking), 
 * and distribute the rest evenly among the remaining players.
 * 
 * @return true if the distribution can be completed smoothly, false otherwise.
 */
bool slot_diff(){
	g_Lplayers.SortCustom(SortByRank);
	ArrayList t_Lplayers = new ArrayList();
	bool p1, p2 = false;
	Player Shotgun1, Shotgun2;
	int i, g;  //shotgun index
	int maxdiff = 2147483647;
	for (i = 0; i < 4; i++){
		g_Lplayers.GetArray(i, tempPlayer);
		if (tempPlayer.type == PTYPE_SHOTGUN){
			if (!p1){
				g_Lplayers.GetArray(i, Shotgun1);
				p1 = true;
				for (g = i+1; g < 4; g++){
					g_Lplayers.GetArray(i, tempPlayer);
					if (tempPlayer.type == PTYPE_SHOTGUN){
						if (!p2){
							g_Lplayers.GetArray(i, Shotgun2);
							p2 = true;
						}
					}
				}
			}
		}
	}
	if (!(p1 && p2)) return false;
	for (int n = 0; i < g_Lplayers.Length; i++){
		if (n != i && n != g){
			g_Lplayers.GetArray(n, tempPlayer);
			t_Lplayers.PushArray(tempPlayer);
		}
	}
	t_Lplayers.SortCustom(SortByRank);

	for (int j = 0; j < t_Lplayers.Length - 2; j++)
	{
		for (int k = j + 1; k < t_Lplayers.Length - 1; k++)
		{
			for (int l = k + 1; l < t_Lplayers.Length; l++)
			{
				ArrayList group1 = new ArrayList();
				group1.Resize(4);
				t_Lplayers.GetArray(j, tempPlayer);  
				group1.SetArray(1,tempPlayer);
				t_Lplayers.GetArray(k, tempPlayer);  
				group1.SetArray(2,tempPlayer);
				t_Lplayers.GetArray(l, tempPlayer);  
				group1.SetArray(3,tempPlayer);
				int m, n, o;
				for (m=0; m<t_Lplayers.Length; m++){
					if (m != j && m != k && m != l) break;
				}
				for (n=0; n<t_Lplayers.Length; n++){
					if ( n != j && n != k && n != l && n != m) break;
				}
				for (o=0; o<t_Lplayers.Length; o++){
					if ( o != j && o != k && o != l && o != m && o != n) break;
				}
			   
				
				ArrayList group2 = new ArrayList();
				group2.Resize(4);
				t_Lplayers.GetArray(m, tempPlayer);  
				group2.SetArray(0,tempPlayer);
				t_Lplayers.GetArray(n, tempPlayer);  
				group2.SetArray(1,tempPlayer);
				t_Lplayers.GetArray(o, tempPlayer);  
				group2.SetArray(2,tempPlayer);
				int diff = diff_sum(group1, group2);
				if (diff < maxdiff)
				{
					maxdiff = diff;
					if (g_Lteam1 != INVALID_HANDLE){
						g_Lteam1.Resize(0);
					}
					if (g_Lteam2 != INVALID_HANDLE){
						g_Lteam2.Resize(0);
					}
					g_Lteam1 = group1.Clone();
					g_Lteam2 = group2.Clone();
				}
				delete group1;
				delete group2;
			}
		}
	}
	g_Lteam1.PushArray(Shotgun1);
	g_Lteam2.PushArray(Shotgun2);
	return true;
}

/**
 * Simply balancing the team.
 * 1368 - 2457
 * This is suitable when at least 2/4 players' roleplaying abilities far surpass those of the remaining players.
 * 
 * @return true
 */
bool balance_diff()
{
	g_Lplayers.SortCustom(SortByRank);
	ArrayList group1 = new ArrayList();
	ArrayList group2 = new ArrayList();
	group1.Resize(4);
	g_Lplayers.GetArray(0, tempPlayer);  
	group1.SetArray(0,tempPlayer);
	g_Lplayers.GetArray(2, tempPlayer);  
	group1.SetArray(1,tempPlayer);
	g_Lplayers.GetArray(5, tempPlayer);  
	group1.SetArray(2,tempPlayer);
	g_Lplayers.GetArray(7, tempPlayer);  
	group1.SetArray(3,tempPlayer);

	group2.Resize(4);
	g_Lplayers.GetArray(1, tempPlayer);  
	group2.SetArray(0,tempPlayer);
	g_Lplayers.GetArray(3, tempPlayer);  
	group2.SetArray(1,tempPlayer);
	g_Lplayers.GetArray(4, tempPlayer);  
	group2.SetArray(2,tempPlayer);
	g_Lplayers.GetArray(6, tempPlayer);  
	group2.SetArray(3,tempPlayer);

	g_Lteam1 = group1.Clone();
	g_Lteam2 = group2.Clone();
	return true;
}

/**
 * Find all possible ways of grouping and return the minimum point difference along with
 * the corresponding groupings.
 * This is suitable when the overall skill gap is relatively small.
 * 
 * @return true if the distribution can be completed smoothly, false otherwise.
 */
bool min_diff(bool force = false)
{
	g_Lplayers.SortCustom(SortByRank);
	int maxrp = 0;
	int minrp = 2147483647;
	for (int i = 0; i < g_Lplayers.Length; i++)
	{
		g_Lplayers.GetArray(i, tempPlayer);
		if (g_iPlayerRP[tempPlayer.id] > maxrp){
			maxrp = g_iPlayerRP[tempPlayer.id];
		}
		if (g_iPlayerRP[tempPlayer.id] < minrp){
			minrp = g_iPlayerRP[tempPlayer.id];
		}
	}
	if (abs(maxrp - minrp) > 2500 && !force) return false;
	int maxdiff = 2147483647;

	for (int i = 0; i < g_Lplayers.Length - 3; i++)
	{
		for (int j = i + 1; j < g_Lplayers.Length - 2; j++)
		{
			for (int k = j + 1; k < g_Lplayers.Length - 1; k++)
			{
				for (int l = k + 1; l < g_Lplayers.Length; l++)
				{
					ArrayList group1 = new ArrayList();
					group1.Resize(4);
					g_Lplayers.GetArray(i, tempPlayer);  
					group1.SetArray(0,tempPlayer);
					g_Lplayers.GetArray(j, tempPlayer);  
					group1.SetArray(1,tempPlayer);
					g_Lplayers.GetArray(k, tempPlayer);  
					group1.SetArray(2,tempPlayer);
					g_Lplayers.GetArray(l, tempPlayer);  
					group1.SetArray(3,tempPlayer);

					int m, n, o, p;
					for (m=0; m<g_Lplayers.Length; m++){
						if (m != i && m != j && m != k && m != l) break;
					}
					for (n=0; n<g_Lplayers.Length; n++){
						if (n != i && n != j && n != k && n != l && n != m) break;
					}
					for (o=0; o<g_Lplayers.Length; o++){
						if (o != i && o != j && o != k && o != l && o != m && o != n) break;
					}
					for (p=0; p<g_Lplayers.Length; p++){
						if (p != i && p != j && p != k && p != l && p != m && p != n && p != o) break;
					}                    
					
					ArrayList group2 = new ArrayList();
					group2.Resize(4);
					g_Lplayers.GetArray(m, tempPlayer);  
					group2.SetArray(0,tempPlayer);
					g_Lplayers.GetArray(n, tempPlayer);  
					group2.SetArray(1,tempPlayer);
					g_Lplayers.GetArray(o, tempPlayer);  
					group2.SetArray(2,tempPlayer);
					g_Lplayers.GetArray(p, tempPlayer);  
					group2.SetArray(3,tempPlayer);

					int diff = diff_sum(group1, group2);
					if (diff < maxdiff)
					{
						maxdiff = diff;
						if (g_Lteam1 != INVALID_HANDLE){
							g_Lteam1.Resize(0);
						}
						if (g_Lteam2 != INVALID_HANDLE){
							g_Lteam2.Resize(0);
						}
						g_Lteam1 = group1.Clone();
						g_Lteam2 = group2.Clone();
					}
					delete group1;
					delete group2;

				}
			}
		}
	}
	return true;
}


/**
 * Retrieve the player's experience rating and save it to the RP array, 
 * 
 * @param iClient player id
 * @return Client Rankpoint. if failed will return -2
 */
int GetClientRP(int iClient)
{
	Player iPlayer;
	iPlayer.id = iClient;
	SteamWorks_RequestStats(iClient, 550/*APP L4D2*/);
	bool status = SteamWorks_GetStatCell(iClient, "Stat.TotalPlayTime.Total", iPlayer.gametime);
	if (!status){
		return -2;
	}
	iPlayer.gametime = iPlayer.gametime/3600;
	SteamWorks_GetStatCell(iClient, "Stat.SpecAttack.Tank", iPlayer.tankrocks);
	SteamWorks_GetStatCell(iClient, "Stat.GamesLost.Versus", iPlayer.versuslose);
	SteamWorks_GetStatCell(iClient, "Stat.GamesWon.Versus", iPlayer.versuswin);
	iPlayer.versustotal = iPlayer.versuslose + iPlayer.versuswin;
	iPlayer.smgkills = 0;
	int t_kills;
	SteamWorks_GetStatCell(iClient, "Stat.smg_silenced.Kills.Total", t_kills);
	iPlayer.smgkills += t_kills;
	SteamWorks_GetStatCell(iClient, "Stat.smg.Kills.Total", t_kills);
	iPlayer.smgkills += t_kills;
	SteamWorks_GetStatCell(iClient, "Stat.shotgun_chrome.Kills.Total", t_kills);
	iPlayer.shotgunkills += t_kills;
	SteamWorks_GetStatCell(iClient, "Stat.pumpshotgun.Kills.Total", t_kills);
	iPlayer.shotgunkills += t_kills;
	iPlayer.winrounds = float(iPlayer.versuswin) / float(iPlayer.versustotal);
	if(iPlayer.versustotal < 700) iPlayer.winrounds = 0.5;
	iPlayer.rankpoint = Calculate_RP(iPlayer);
	temp_prp.IntValue = iPlayer.rankpoint;
	if (iPlayer.shotgunkills > iPlayer.smgkills){
		iPlayer.type = PTYPE_SHOTGUN;
	}else{
		iPlayer.type = PTYPE_SMG;
	}
	return temp_prp.IntValue;
}

/**
 * Calculate the player's RP
 * 
 * @param tPlayer A Player object
 * @return tPlayer's RP
 */
int Calculate_RP(Player tPlayer)
{
	int killtotal = tPlayer.shotgunkills + tPlayer.smgkills;
	float shotgunperc = float(tPlayer.shotgunkills) / float(killtotal);   
	float rpm = float(tPlayer.tankrocks) / float(tPlayer.gametime);
	float rp = tPlayer.winrounds * (0.55 * float(tPlayer.gametime) + float(tPlayer.tankrocks) * rpm + 
		float(killtotal) * 0.005 * (1.0 + shotgunperc));
	PrintToConsoleAll("%N  %f=%f*(0.55*%i*+%i*%f+%i*0.005*(1+%f))",tPlayer.id, rp, tPlayer.winrounds ,tPlayer.gametime, tPlayer.tankrocks, rpm,
		killtotal, shotgunperc);
	CPrintToChatAll("%t", "SHOW_ONE_RP", tPlayer.id, RoundToNearest(rp));
	return RoundToNearest(rp);
}

/**
 * Calculate the absolute value.
 * 
 * @param value
 * @return The absolute value of "value".
 */
int abs(int value){
	return (value < 0) ? -value : value;   
}
