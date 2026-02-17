#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#undef REQUIRE_PLUGIN
#include <l4d_boss_vote>
#include <readyup>
#include <l4d2util>
#define REQUIRE_PLUGIN
#include <colors>
#include <witch_and_tankifier>
#include <l4d2_hybrid_scoremod>
#include <exp_interface>
#define PLUGIN_VERSION "1.0.0"

// 基于Target5150/MoYu_Server_Stupid_Plugins的tank发光插件Predict Tank Glow重新修改。
public Plugin myinfo = 
{
    name = "[L4D & 2] TankFight",
    author = "Forgetest, sp",
    description = "Predicts flow tank positions and fakes models with glow (mimic \"Dark Carnival: Remix\").",
    version = PLUGIN_VERSION,
    url = "https://github.com/Target5150/MoYu_Server_Stupid_Plugins"
};

//=========================================================================================================

#define GAMEDATA_FILE "l4d_predict_tank_glow"
#include "tankglow/tankglow_defines.inc"

bool g_bLeft4Dead2;
CZombieManager ZombieManager;

// order is foreign referred in `PickTankVariant()`
#define TANK_VARIANT_SLOT (sizeof(g_sTankModels)-1)
#define TANK_MODEL_STRLEN 128

#define IS_INFECTED(%1)         (GetClientTeam(%1) == 3)
#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_VALID_INFECTED(%1)   (IS_VALID_INGAME(%1) && IS_INFECTED(%1))
#define IS_VALID_INGAME(%1)     (IS_VALID_CLIENT(%1) && IsClientInGame(%1))
#define ZC_TANK    8


int g_iMapTFType = 0;
int g_iTankFightCurrentRound = 0;  // 当前战斗轮数
ConVar g_cvTankFightRounds;
ConVar g_cvTankFightSurvivorScorePerTank;
ConVar g_cvVsDefibPenalty;
int g_iOriginalDefibPenalty = 0;  // 保存vs_defib_penalty的原始值
float g_fLastSpecialInfectedDamageTime = 0.0;  // 记录最后一次特感伤害生还者的时间

// 保存每一轮Tank的位置用于换边时保持一致
float g_vTankPositionsByRound[10][3];
float g_vTankAnglesByRound[10][3];
float g_fTankFlowPercentByRound[10];  // 保存每一轮随机选择的流程百分比
bool g_bTankPositionSavedByRound[10];
bool g_bTankPositionsPreGenerated = false;  // 标记位置是否已预生成

enum /*strMapType*/
{
    MP_FINALE
};

enum
{
    TYPE_NORMAL = 10,
    TYPE_FINISH = 11,
    TYPE_STATIC = 12
};
static char g_sTankModels[][TANK_MODEL_STRLEN] = {
    "models/infected/hulk.mdl",
    "models/infected/hulk_dlc3.mdl",
    "models/infected/hulk_l4d1.mdl",
    "N/A" // TankVariant slot
};

// 是懒狗，所以
static char g_sSurvivorModels_Plugin[][TANK_MODEL_STRLEN] = {
    "models/survivors/survivor_producer.mdl",//2代
    "models/survivors/survivor_manager.mdl",//1代
    "models/survivors/survivor_manager.mdl",//1代
    "N/A" // TankVariant slot
};

int g_iTankGlowModel = INVALID_ENT_REFERENCE;
int g_iSurvivorGlowModel = INVALID_ENT_REFERENCE;
float g_vTankModelPos[3], g_vTankModelAng[3];
float g_vSurvivorModelPos[3], g_vSurvivorModelAng[3];
bool g_bMissionFinalMapCache = false;
bool g_bMissionFinalMapCacheValid = false;
enum struct TFRoundData{
    float fSurvivorPercentReal; // 实际刷新的位置
    float fSurvivorPercentTarget; // 目标位置

    void Reset(){
        this.fSurvivorPercentReal = 0.0;
        this.fSurvivorPercentTarget = 0.0;
    }
}
TFRoundData TFData;
//=========================================================================================================

// !!! remove this line if you want to include info_editor
native void InfoEditor_GetString(int pThis, const char[] keyname, char[] dest, int destLen);

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    switch (GetEngineVersion())
    {
        case Engine_Left4Dead: g_bLeft4Dead2 = false;
        case Engine_Left4Dead2: g_bLeft4Dead2 = true;
        default:
        {
            strcopy(error, err_max, "Plugin supports Left 4 Dead & 2 only.");
            return APLRes_SilentFailure;
        }
    }
    
    MarkNativeAsOptional("InfoEditor_GetString");
    return APLRes_Success;
}

// 按E应传送到克局位置
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon) 
{
	if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != L4D2Team_Infected)
			return Plugin_Continue;
	
    if (!IsInfectedGhost(client)) return Plugin_Continue;
    if (!IsInReady()) return Plugin_Continue;
	
    if (buttons & IN_USE)
	{
		TeleportEntity(client, g_vSurvivorModelPos, g_vSurvivorModelAng);
        return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnPluginStart()
{
    LoadSDK();


    g_cvTankFightRounds = CreateConVar("l4d_tankfight_rounds",
                                "1",
                                "Number of tank fight rounds per match.\n"
                            ...	"1 = 1 round, 2 = 2 rounds, etc.",
                                FCVAR_SPONLY,
                                true, 1.0, true, 10.0);

    g_cvTankFightSurvivorScorePerTank = CreateConVar("l4d_tankfight_survivor_score_per_tank",
                                "0",
                                "Score bonus for survivors for each tank spawned.\n"
                            ...	"0 = no bonus, positive numbers add to survivor score",
                                FCVAR_SPONLY,
                                true, 0.0);

    g_cvVsDefibPenalty = FindConVar("vs_defib_penalty");
    if (g_cvVsDefibPenalty != null)
    {
        // 保存原始值
        g_iOriginalDefibPenalty = g_cvVsDefibPenalty.IntValue;
        // 设置为负的tank分数
        g_cvVsDefibPenalty.IntValue = -g_cvTankFightSurvivorScorePerTank.IntValue;
    }

    HookEvent("round_start", Event_RoundStart);
    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("round_end", RoundEnd_Event);
    HookEvent("player_incapacitated", Event_PlayerIncap);
    HookEvent("player_hurt", Event_PlayerHurt);
    TFData.Reset();

    // 注册指令
    RegConsoleCmd("sm_health", Command_ShowTankScore);
    RegConsoleCmd("sm_tank", Command_ShowTankPositions);
    RegConsoleCmd("sm_witch", Command_ShowTankPositions);
}
public void OnRoundIsLive()
{
    g_iTankFightCurrentRound = 0;  // 重置轮数计数器
    CPrintToChatAll("[{green}!{default}] {olive}Tank fight 简要说明");
    CPrintToChatAll("只有克局，克死亡后进入加时阶段。如果所有人都被扶起来且未被控回合结束！");
    CPrintToChatAll("游戏开始后，生还者会被传送到地图上发光的生还者模型");
    CPrintToChatAll("本场比赛将进行 {olive}%d {default}轮 Tank 战斗", g_cvTankFightRounds.IntValue);

    // 预生成所有轮次的Tank位置
    CreateTimer(0.1, Timer_PreGenerateTankPositions, .flags = TIMER_FLAG_NO_MAPCHANGE);
    g_cvVsDefibPenalty.IntValue = -g_cvTankFightSurvivorScorePerTank.IntValue;
}

/**
 * 获取所有可用的流程百分比
 * @param outPercents 输出数组，存放所有有效的百分比
 * @return 返回有效百分比的个数
 */
int GetAllValidTankPercents(ArrayList outPercents)
{
    outPercents.Clear();

    for (int percent = 1; percent <= 99; percent++)
    {
        if (IsTankPercentValid(percent))
        {
            float flowPercent = float(percent) / 100.0;
            outPercents.Push(flowPercent);
        }
    }

    return outPercents.Length;
}

/**y
 * 从所有可用进度中随机选择一个
 * @return 返回随机选择的流程百分比
 */
float GetRandomValidTankPercent()
{
    ArrayList validPercents = new ArrayList();
    int count = GetAllValidTankPercents(validPercents);

    if (count == 0)
    {
        // 如果没有有效位置，返回默认百分比
        delete validPercents;
        return L4D2Direct_GetVSTankFlowPercent(0);
    }

    int randomIndex = GetRandomInt(0, count - 1);
    float result = validPercents.Get(randomIndex);

    delete validPercents;
    return result;
}

/**
 * 从所有可用进度中随机选择一个不重复的
 * @param usedPercents 已使用过的百分比列表
 * @param tolerance 容差值（防浮点数精度问题）
 * @return 返回随机选择的流程百分比，如果没有可用的返回-1.0
 */
float GetUniqueRandomValidTankPercent(ArrayList usedPercents, float tolerance = 0.001)
{
    ArrayList validPercents = new ArrayList();
    int count = GetAllValidTankPercents(validPercents);

    if (count == 0)
    {
        delete validPercents;
        return -1.0;
    }

    // 移除已使用过的百分比
    for (int i = validPercents.Length - 1; i >= 0; i--)
    {
        float percent = validPercents.Get(i);
        bool isUsed = false;

        for (int j = 0; j < usedPercents.Length; j++)
        {
            float usedPercent = usedPercents.Get(j);
            if (FloatAbs(percent - usedPercent) < tolerance)
            {
                isUsed = true;
                break;
            }
        }

        if (isUsed)
        {
            validPercents.Erase(i);
        }
    }

    // 如果没有可用的百分比了
    if (validPercents.Length == 0)
    {
        delete validPercents;
        return -1.0;
    }

    int randomIndex = GetRandomInt(0, validPercents.Length - 1);
    float result = validPercents.Get(randomIndex);

    delete validPercents;
    return result;
}

/**
 * 对Tank位置数据进行排序（按流程百分比升序排列）
 * 将四个相关联的数组同时排序，保持数据对应关系
 */
void SortTankPositions()
{
    int numRounds = g_cvTankFightRounds.IntValue;
    if (numRounds <= 1) return;

    // 冒泡排序
    for (int i = 0; i < numRounds - 1; i++)
    {
        for (int j = 0; j < numRounds - i - 1; j++)
        {
            // 只比较已保存的位置
            if (!g_bTankPositionSavedByRound[j] || !g_bTankPositionSavedByRound[j + 1])
                continue;

            // 如果当前百分比大于下一个百分比，则交换
            if (g_fTankFlowPercentByRound[j] > g_fTankFlowPercentByRound[j + 1])
            {
                // 交换流程百分比
                float tempFlow = g_fTankFlowPercentByRound[j];
                g_fTankFlowPercentByRound[j] = g_fTankFlowPercentByRound[j + 1];
                g_fTankFlowPercentByRound[j + 1] = tempFlow;

                // 交换Tank位置
                float tempPos[3];
                tempPos = g_vTankPositionsByRound[j];
                g_vTankPositionsByRound[j] = g_vTankPositionsByRound[j + 1];
                g_vTankPositionsByRound[j + 1] = tempPos;

                // 交换Tank角度
                float tempAng[3];
                tempAng = g_vTankAnglesByRound[j];
                g_vTankAnglesByRound[j] = g_vTankAnglesByRound[j + 1];
                g_vTankAnglesByRound[j + 1] = tempAng;
            }
        }
    }

    PrintToConsoleAll("[TankFight] Tank位置已按流程百分比排序");
}

/**
 * 预生成所有Tank战斗轮次的位置
 */
Action Timer_PreGenerateTankPositions(Handle timer)
{
    if (!L4D_IsVersusMode()) return Plugin_Stop;

    int numRounds = g_cvTankFightRounds.IntValue;

    // 如果已经生成过，直接使用已有结果
    if (g_bTankPositionsPreGenerated)
    {
        PrintToConsoleAll("[TankFight] Tank 位置已在之前生成，直接使用已有结果");
        int validCount = 0;
        for (int i = 0; i < numRounds; i++)
        {
            if (g_bTankPositionSavedByRound[i])
            {
                validCount++;
                PrintToConsoleAll("[TankFight] 已有位置 Round %d: Flow: %.2f%%, Pos=[%.1f, %.1f, %.1f]", i,
                    g_fTankFlowPercentByRound[i] * 100.0,
                    g_vTankPositionsByRound[i][0], g_vTankPositionsByRound[i][1], g_vTankPositionsByRound[i][2]);
            }
        }
        CPrintToChatAll("[{green}!{default}] 使用已保存的 {olive}%d {default}轮 Tank 位置", validCount);
        return Plugin_Stop;
    }

    PrintToConsoleAll("[TankFight] 开始预生成 %d 轮 Tank 位置...", numRounds);

    // 用于记录已使用的百分比，防止重复
    ArrayList usedPercents = new ArrayList();

    for (int round = 0; round < numRounds; round++)
    {
        float target_percent = GetUniqueRandomValidTankPercent(usedPercents);

        // 如果没有找到不重复的百分比，使用默认的
        if (target_percent < 0.0)
        {
            target_percent = L4D2Direct_GetVSTankFlowPercent(0);
            PrintToConsoleAll("[TankFight] Round %d: 警告 - 无可用的不重复位置，使用默认流程百分比 %.2f%%", round, target_percent * 100.0);
        }

        // 记录已使用的百分比
        usedPercents.Push(target_percent);

        // 保存随机选择的流程百分比
        g_fTankFlowPercentByRound[round] = target_percent;

        // 将百分比转换为具体坐标保存
        TerrorNavArea nav = GetBossSpawnAreaForFlow(target_percent);
        if (nav.Valid())
        {
            float vPos[3], vAng[3];
            L4D_FindRandomSpot(view_as<int>(nav), vPos);
            vPos[2] -= 8.0;

            vAng[0] = 0.0;
            vAng[1] = GetRandomFloat(0.0, 360.0);
            vAng[2] = 0.0;

            g_vTankPositionsByRound[round] = vPos;
            g_vTankAnglesByRound[round] = vAng;
            g_bTankPositionSavedByRound[round] = true;

            PrintToConsoleAll("[TankFight] Round %d: 位置已预生成，Flow: %.2f%%", round, target_percent * 100.0);
        }
        else
        {
            PrintToConsoleAll("[TankFight] Round %d: 警告 - 无法找到有效位置", round);
        }
    }

    delete usedPercents;


    g_bTankPositionsPreGenerated = true;
    CPrintToChatAll("[{green}!{default}] 所有 {olive}%d {default}轮的 Tank 位置已预生成完毕！", numRounds);
    SortTankPositions();
    SetTankPercent(RoundToFloor(g_fTankFlowPercentByRound[0] * 100.0));
    return Plugin_Stop;
}

public Action IsTankFightEnd(Handle timer)
{
    if (IsTankInGame()) return Plugin_Continue;
    if (!IsCanEndRound()) return Plugin_Continue;

    // 检查5秒内是否有特感对生还者造成伤害
    float timeSinceLastDamage = GetGameTime() - g_fLastSpecialInfectedDamageTime;
    if (timeSinceLastDamage < 5.0) return Plugin_Continue;

    // 防止影响下一队
    if (IsInReady()) return Plugin_Stop;
    PrintToConsoleAll("EndTankFightRound()");
    EndTankFightRound();

    // 仅在真正结束比赛时重置，循环时不重置
    if (g_iTankFightCurrentRound >= g_cvTankFightRounds.IntValue)
    {
        TFData.Reset();
    }

    return Plugin_Stop;
}

bool IsTankInGame()
{
    for (int client = 1; client <= MaxClients; client++) {
        if (IS_VALID_INFECTED(client) && IsPlayerAlive(client) && GetEntProp(client, Prop_Send, "m_zombieClass") == ZC_TANK) {
            return true;
        }
    }
    return false;
}

bool IsCanEndRound(){
    for (int i = 1; i <= MaxClients; i++){
        if (!IsClientInGame(i)) continue;
        if (!IsPlayerAlive(i)) continue;
        if (IsSurvivor(i)){
            if (IsIncapacitated(i) || IsHangingFromLedge(i) || IsSurvivorAttacked(i)) return false;
        }
    }
    return true;
}

bool AllSurInjured(){
    for (int i = 1; i <= MaxClients; i++){
        if (!IsClientInGame(i)) continue;
        if (!IsPlayerAlive(i)) continue;
        if (IsSurvivor(i)){
            if (!(IsIncapacitated(i) || IsHangingFromLedge(i))) return false;
        }
    }
    return true;
}
int healthbonus, damageBonus, pillsBonus;
// 传送生还者到安全屋并结束本回合
void EndTankFightRound(){
    // 如果是团灭则不做处理
    if (AllSurInjured()) return;

    g_iTankFightCurrentRound++;
    CPrintToChatAll("[{green}!{default}] 第 {olive}%d {default}轮结束！", g_iTankFightCurrentRound);

    // 检查是否还有更多轮数
    if (g_iTankFightCurrentRound < g_cvTankFightRounds.IntValue)
    {
        CPrintToChatAll("[{green}!{default}] 准备第 {olive}%d {default}轮 Tank 战斗...", g_iTankFightCurrentRound + 1);
        TeleportAllSurvivorToPercentFlow(0.01);
        // 重置位置和数据
        g_vTankModelPos = NULL_VECTOR;
        g_vTankModelAng = NULL_VECTOR;
        g_vSurvivorModelAng = NULL_VECTOR;
        g_vSurvivorModelPos = NULL_VECTOR;
        TFData.Reset();

        // 重新初始化下一轮
        GenerateAndSetTankPosition(g_iTankFightCurrentRound);
        TFData.fSurvivorPercentTarget = L4D2Direct_GetVSTankFlowPercent(InSecondHalfOfRound()) - 0.12;
        TFData.fSurvivorPercentReal = L4D2Direct_GetVSTankFlowPercent(InSecondHalfOfRound()) - 0.24;
        PrintToConsoleAll("TFData.fSurvivorPercent: %f/%f", TFData.fSurvivorPercentTarget, TFData.fSurvivorPercentReal);
        CPrintToChatAll("[{green}!{default}] Tank生成位置：%f", L4D2Direct_GetVSTankFlowPercent(InSecondHalfOfRound()));
        CreateTimer(5.0, Timer_DelayProcess, .flags = TIMER_FLAG_NO_MAPCHANGE);
        //CreateTimer(10.5, Timer_AccessTankWarp, false, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    // 所有轮次完成，真正结束比赛
    CPrintToChatAll("[{green}!{default}] 所有 {olive}%d {default}轮 Tank 战斗已结束！", g_iTankFightCurrentRound);

    if (g_iMapTFType == TYPE_FINISH){
        healthbonus = SMPlus_GetHealthBonus();
        damageBonus	= SMPlus_GetDamageBonus();
        pillsBonus	= SMPlus_GetPillsBonus();
        bool bFlipped = !!GameRules_GetProp("m_bAreTeamsFlipped");
        int SurvivorTeamIndex = bFlipped ? 1 : 0;
        int survScore = L4D2Direct_GetVSCampaignScore(SurvivorTeamIndex);
        L4D2Direct_SetVSCampaignScore(SurvivorTeamIndex, survScore + healthbonus + damageBonus + pillsBonus);
        CreateTimer(3.5, AnnounceResult);
        CheatCommand("scenario_end", "");
    }else{
        CheatCommand("sm_warpend", "");
    }
}


Action AnnounceResult(Handle timer)
{
    CPrintToChatAll("[{green}!{default}] 生还者本关得分：{olive}+%i", healthbonus + damageBonus + pillsBonus);
    return Plugin_Stop;
}

//=========================================================================================================

/**
 * @brief Called when the boss percents are updated.
 * @remarks Triggered via boss votes, force tanks, force witches.
 * @remarks Special value: -1 indicates ignored in change, 0 disabled (no spawn).
 */
public void OnUpdateBosses(int iTankFlow, int iWitchFlow)
{
    if (iTankFlow > 0)
    {
        Event_RoundStart(null, "", false);
    }
}

//=========================================================================================================

void RoundEnd_Event(Event event, const char[] name, bool dontBroadcast)
{
}
void Event_PlayerIncap(Event event, const char[] name, bool dontBroadcast){
}
void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));

    // 检查攻击者是否是特感（不是Tank）
    if (!IS_VALID_INFECTED(attacker) || !IsSurvivor(victim)) return;

    int zombieClass = GetEntProp(attacker, Prop_Send, "m_zombieClass");
    if (zombieClass == ZC_TANK) return;  // Tank伤害不计入此检查

    // 记录最后一次特感伤害的时间
    g_fLastSpecialInfectedDamageTime = GetGameTime();
}
void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (!L4D_IsVersusMode()) return;

    // 重置特感伤害时间
    g_fLastSpecialInfectedDamageTime = GetGameTime();

    bool bIsSecondHalf = !!GameRules_GetProp("m_bInSecondHalfOfRound", 1);

    if (!bIsSecondHalf)
    {
        // 第一半场开始，重置所有位置（新游戏）
        g_vTankModelPos = NULL_VECTOR;
        g_vTankModelAng = NULL_VECTOR;
        g_vSurvivorModelAng = NULL_VECTOR;
        g_vSurvivorModelPos = NULL_VECTOR;
    }
    else
    {
        // 换边开始，重置当前轮数计数（因为要从第一轮重新开始）
        g_iTankFightCurrentRound = 0;
        g_vTankModelPos = NULL_VECTOR;
        g_vTankModelAng = NULL_VECTOR;
        g_vSurvivorModelAng = NULL_VECTOR;
        g_vSurvivorModelPos = NULL_VECTOR;
    }

    // Need to delay a bit, seems crashing otherwise.
    CreateTimer(1.0, Timer_DelayProcess, .flags = TIMER_FLAG_NO_MAPCHANGE);

    // TODO: Is there a hook?
    CreateTimer(5.0, Timer_AccessTankWarp, false, TIMER_FLAG_NO_MAPCHANGE);
}

public Action SelectSurvivorSpawnPosition(Handle timer){
    if (TFData.fSurvivorPercentReal < 0.0) TFData.fSurvivorPercentReal = 0.01;
    TeleportAllSurvivorToPercentFlow(TFData.fSurvivorPercentReal);
    if (FindAliveTankClient() != -1){
        return Plugin_Stop;
    }
    TFData.fSurvivorPercentReal += 0.02;
    if (TFData.fSurvivorPercentReal > TFData.fSurvivorPercentTarget){
        return Plugin_Stop;
    }
    CreateTimer(0.3, SelectSurvivorSpawnPosition);
    return Plugin_Continue;
}
public Action L4D_OnFirstSurvivorLeftSafeArea(int x){
    if (IsInReady()) return Plugin_Continue;
    if (g_iMapTFType == TYPE_STATIC) return Plugin_Continue;

    // 起始进度从 tankflow - 0.24 开始，每次增加 0.03，直至 tankflow - 0.12 为止
    TFData.fSurvivorPercentTarget = L4D2Direct_GetVSTankFlowPercent(0) - 0.12;
    TFData.fSurvivorPercentReal = L4D2Direct_GetVSTankFlowPercent(0) - 0.24;
    if (TFData.fSurvivorPercentReal < 0.0) TFData.fSurvivorPercentReal = 0.0;

    if (!IsInReady()){
        CreateTimer(0.3, SelectSurvivorSpawnPosition);
    } else {
        return Plugin_Continue;
    }

    if (IsValidEdict(g_iSurvivorGlowModel)){
        RemoveEntity(g_iSurvivorGlowModel);
        g_iSurvivorGlowModel = INVALID_ENT_REFERENCE;
    }

    // Disable special spawns temporarily
    ConVar spawn = FindConVar("director_no_specials");
    spawn.IntValue = 1;
    PrintToChatAll("特感将在7S以后允许复活！");
    CreateTimer(0.1, Timer_DelaySpawn, false, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
    return Plugin_Continue;
}

public void OnPluginEnd()
{
    // 还原 vs_defib_penalty 的原始值
    if (g_cvVsDefibPenalty != null)
    {
        g_cvVsDefibPenalty.IntValue = g_iOriginalDefibPenalty;
    }
}

public void OnMapStart()
{
    g_bMissionFinalMapCacheValid = false;

    // 清空已有的Tank位置数据
    g_bTankPositionsPreGenerated = false;
    for (int i = 0; i < sizeof(g_bTankPositionSavedByRound); i++)
    {
        g_bTankPositionSavedByRound[i] = false;
        g_vTankPositionsByRound[i] = NULL_VECTOR;
        g_vTankAnglesByRound[i] = NULL_VECTOR;
        g_fTankFlowPercentByRound[i] = 0.0;
    }
    PrintToConsoleAll("[TankFight] OnMapStart: 已清空所有预生成的Tank位置数据");

    for (int i = 0; i < sizeof(g_sTankModels); ++i){
        PrecacheModel(g_sTankModels[i]);
        PrecacheModel(g_sSurvivorModels_Plugin[i]);
    }
    if (IsStaticTankMap()){
        g_iMapTFType = TYPE_STATIC;
    }else if (IsMissionFinalMap()){
        g_iMapTFType = TYPE_FINISH;
    }else{
        g_iMapTFType = TYPE_NORMAL;
    }
    if (g_iMapTFType == TYPE_STATIC)
    {
        CreateTimer(20.0, Timer_AnounceChangeMap);
    }
}
public void OnMapEnd()
{
    strcopy(g_sTankModels[TANK_VARIANT_SLOT], TANK_MODEL_STRLEN, "N/A");
    strcopy(g_sSurvivorModels_Plugin[TANK_VARIANT_SLOT], TANK_MODEL_STRLEN, "N/A");
    g_iTankFightCurrentRound++;
    g_iTankFightCurrentRound = 0;
    g_bTankPositionsPreGenerated = false;
    for (int i = 0; i < sizeof(g_bTankPositionSavedByRound); i++)
    {
        g_bTankPositionSavedByRound[i] = false;
        g_vTankPositionsByRound[i] = NULL_VECTOR;
        g_vTankAnglesByRound[i] = NULL_VECTOR;
        g_fTankFlowPercentByRound[i] = 0.0;
    }
}

Action Timer_AnounceChangeMap(Handle Timer)
{
    CPrintToChatAll("[{green}!{default}] Tank Fight模式不支持当前地图，在20秒后将自动换图！");
    CreateTimer(20.0, ChangtToNewMap, _,TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

Action Timer_DelaySpawn(Handle timer)
{
    static int iCount = 0;
    iCount++;

    if (iCount >= 70) {
        iCount = 0;
        ConVar spawn = FindConVar("director_no_specials");
        spawn.IntValue = 0;
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

bool IsMissionFinalMap()
{
    if (g_bMissionFinalMapCacheValid) {
        return g_bMissionFinalMapCache;
    }

    if (L4D_IsMissionFinalMap()) {
        g_bMissionFinalMapCache = true;
        g_bMissionFinalMapCacheValid = true;
        return true;
    }

    char g_sMapName[48][32];
    GetCurrentMap(g_sMapName[g_iTankFightCurrentRound], 32);
    Handle g_hTrieMaps;
    // finales
    g_hTrieMaps = CreateTrie();
    SetTrieValue(g_hTrieMaps, "c1m4_atrium",					MP_FINALE);
    SetTrieValue(g_hTrieMaps, "c2m5_concert",				MP_FINALE);
    SetTrieValue(g_hTrieMaps, "c3m4_plantation",				MP_FINALE);
    SetTrieValue(g_hTrieMaps, "c4m5_milltown_escape",		   MP_FINALE);
    SetTrieValue(g_hTrieMaps, "c5m5_bridge",					MP_FINALE);
    SetTrieValue(g_hTrieMaps, "c6m3_port",					  MP_FINALE);
    SetTrieValue(g_hTrieMaps, "c7m3_port",					  MP_FINALE);
    SetTrieValue(g_hTrieMaps, "c8m5_rooftop",					MP_FINALE);
    SetTrieValue(g_hTrieMaps, "c9m2_lots",					  MP_FINALE);
    SetTrieValue(g_hTrieMaps, "c10m5_houseboat",					MP_FINALE);
    SetTrieValue(g_hTrieMaps, "c11m5_runwayc",		MP_FINALE);
    SetTrieValue(g_hTrieMaps, "c12m5_cornfield",		MP_FINALE);
    SetTrieValue(g_hTrieMaps, "c13m4_cutthroatcreek",		   MP_FINALE);
    SetTrieValue(g_hTrieMaps, "c14m2_lighthouse",		   MP_FINALE);

    // since L4D_IsMissionFinalMap() is bollocksed, simple map string check
    int mapType;
    bool bIsFinal = false;
    if (GetTrieValue(g_hTrieMaps, g_sMapName[g_iTankFightCurrentRound], mapType)) {
        bIsFinal = (mapType == MP_FINALE);
    }

    delete g_hTrieMaps;
    g_bMissionFinalMapCache = bIsFinal;
    g_bMissionFinalMapCacheValid = true;
    return bIsFinal;
}

Action ChangtToNewMap(Handle Timer)
{
    char newmap[32];
    ArrayList offmaps = new ArrayList(32);
    offmaps.PushString("c1m1_hotel");
    offmaps.PushString("c2m1_highway");
    offmaps.PushString("c3m1_plankcountry");
    offmaps.PushString("c4m1_milltown_a");
    offmaps.PushString("c5m1_waterfront");
    offmaps.PushString("c6m1_riverbank");
    offmaps.PushString("c8m1_apartment");
    offmaps.PushString("c10m1_caves");
    offmaps.PushString("c11m1_greenhouse");
    offmaps.PushString("c12m1_hilltop");
    //offmaps.PushString("c13m1_alpinecreek");
    int i = GetRandomInt(0, offmaps.Length - 1);
    offmaps.GetString(i, newmap, sizeof(newmap));
    
    
    ForceChangeLevel(newmap, "No Support Fin map");
    return Plugin_Stop;
}

Action Timer_DelayProcess(Handle timer)
{
    if (!L4D_IsVersusMode()) return Plugin_Stop;
    
    if (IsValidEdict(g_iTankGlowModel))
    {
        RemoveEntity(g_iTankGlowModel);
        g_iTankGlowModel = INVALID_ENT_REFERENCE;
    }
    if (IsValidEdict(g_iSurvivorGlowModel))
    {
        RemoveEntity(g_iSurvivorGlowModel);
        g_iSurvivorGlowModel = INVALID_ENT_REFERENCE;
    }
    GenerateAndSetTankPosition(g_iTankFightCurrentRound);
    EnableTankSpawn();
    CreateTimer(0.3, SelectSurvivorSpawnPosition);
    g_iTankGlowModel = ProcessPredictModel(g_vTankModelPos, g_vTankModelAng);
    g_iSurvivorGlowModel = ProcessSurPredictModel(g_vSurvivorModelPos, g_vSurvivorModelAng);
    if (g_iTankGlowModel != INVALID_ENT_REFERENCE)
        g_iTankGlowModel = EntIndexToEntRef(g_iTankGlowModel);
    if (g_iSurvivorGlowModel != INVALID_ENT_REFERENCE)
        g_iSurvivorGlowModel = EntIndexToEntRef(g_iSurvivorGlowModel);
    
    FreezePoints();

    return Plugin_Stop;
}

void EnableTankSpawn(){
    L4D2Direct_SetTankPassedCount(0);
    L4D2Direct_SetVSTankToSpawnThisRound(0, true);
    L4D2Direct_SetVSTankToSpawnThisRound(1, true);
}

Action Timer_AccessTankWarp(Handle timer, bool isRetry)
{
    if (!L4D_IsVersusMode()) return Plugin_Stop;
    
    if (g_bLeft4Dead2 && IsValidEdict(g_iTankGlowModel))
    {
        char buffer[256];
        
        L4D2_GetVScriptOutput("ret <- ( \"anv_tankwarps\" in getroottable() );<RETURN>ret</RETURN>", buffer, sizeof(buffer));
        if (strcmp(buffer, "1") != 0)
        {
            // retry or seeu
            if (!isRetry) CreateTimer(15.0, Timer_AccessTankWarp, true, TIMER_FLAG_NO_MAPCHANGE);
            return Plugin_Stop;
        }
        
        /**
         *	if ( "anv_tankwarps" in getroottable() )
         *	{
         *		::anv_tankwarps.OnGameEvent_tank_spawn(
         *		{
         *			userid = 0,
         *			tankid = %d
         *		} );
         *		::anv_tankwarps.iTankCount--;
         *	}
         */
        FormatEx(buffer, sizeof(buffer),
            "::anv_tankwarps.OnGameEvent_tank_spawn(\
            {\
                userid = 0,\
                tankid = %d\
            } );\
            ::anv_tankwarps.iTankCount--;",
            EntRefToEntIndex(g_iTankGlowModel)
        );
        
        /**
         *	Code for re-organized community update. Commented for afterward use.
         *
         *	---------------------------------------------
         *
         *	if ( "CommunityUpdate" in getroottable() )
         *	{
         *		CommunityUpdate().OnGameEvent_tank_spawn(
         *		{
         *			userid = 0,
         *			tankid = %d
         *		} );
         *		CommunityUpdate().m_iTankCount--;
         *	}
         */
    }
    
    return Plugin_Stop;
}

void FreezePoints()
{
    CPrintToChatAll("[{green}!{default}] Tank Fight 模式下没有路程分！");
    L4D_SetVersusMaxCompletionScore(0);
}

void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (!L4D_IsVersusMode()) return;
    GameRules_SetProp("m_iVersusDefibsUsed", g_iTankFightCurrentRound+1, 4, GameRules_GetProp("m_bAreTeamsFlipped", 4, 0));

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
        return;

    int currentRound = g_iTankFightCurrentRound;

    // 检查是否有预生成的位置
    if (g_bTankPositionsPreGenerated && g_bTankPositionSavedByRound[currentRound])
    {
        float vPos[3], vAng[3];
        vPos[0] = g_vTankPositionsByRound[currentRound][0];
        vPos[1] = g_vTankPositionsByRound[currentRound][1];
        vPos[2] = g_vTankPositionsByRound[currentRound][2];
        vAng[0] = g_vTankAnglesByRound[currentRound][0];
        vAng[1] = g_vTankAnglesByRound[currentRound][1];
        vAng[2] = g_vTankAnglesByRound[currentRound][2];

        // 将Tank传送到预生成的位置
        TeleportEntity(client, vPos, vAng, NULL_VECTOR);
        PrintToConsoleAll("[TankFight] Event_TankSpawn - Tank 已传送到预生成位置 Round: %d", currentRound);
    }

    if (IsValidEdict(g_iTankGlowModel))
        RemoveEntity(g_iTankGlowModel);

    g_iTankGlowModel = INVALID_ENT_REFERENCE;

    // 移除生还者发光模型
    if (IsValidEdict(g_iSurvivorGlowModel))
        RemoveEntity(g_iSurvivorGlowModel);

    g_iSurvivorGlowModel = INVALID_ENT_REFERENCE;

    CPrintToChatAll("[{green}!{default}] Tank 已生成，进行第 {olive}%d {default}轮战斗 ({olive}%d{default}/{olive}%d{default})",
                       currentRound + 1, currentRound + 1, g_cvTankFightRounds.IntValue);


    CreateTimer(0.3, IsTankFightEnd, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

//=========================================================================================================

/**
 * 生成并设置Tank的位置百分比
 * @param iRound 当前轮次
 */
void GenerateAndSetTankPosition(int iRound)
{
    // 如果位置已预生成，使用预生成的位置和百分比
    if (g_bTankPositionsPreGenerated && iRound < sizeof(g_vTankPositionsByRound) && g_bTankPositionSavedByRound[iRound])
    {
        // 使用保存的流程百分比
        float target_percent = g_fTankFlowPercentByRound[iRound];
        L4D2Direct_SetVSTankFlowPercent(0, target_percent);
        L4D2Direct_SetVSTankFlowPercent(1, target_percent);
        PrintToConsoleAll("[TankFight] GenerateAndSetTankPosition - Round: %d (预生成), Flow Percent: %.2f%%", iRound, target_percent * 100.0);
        return;
    }

    // 备用逻辑：如果预生成失败，使用新的随机选择机制
    float target_percent = GetRandomValidTankPercent();

    // 设置Tank的流程百分比
    L4D2Direct_SetVSTankFlowPercent(0, target_percent);
    L4D2Direct_SetVSTankFlowPercent(1, target_percent);
    PrintToConsoleAll("[TankFight] GenerateAndSetTankPosition - Round: %d, Flow Percent: %.2f%%", iRound, target_percent * 100.0);
}

int ProcessPredictModel(float vPos[3], float vAng[3])
{
    int currentRound = g_iTankFightCurrentRound;

    // 始终使用预生成的位置（包括第一个tank）
    if (g_bTankPositionsPreGenerated && g_bTankPositionSavedByRound[currentRound])
    {
        vPos[0] = g_vTankPositionsByRound[currentRound][0];
        vPos[1] = g_vTankPositionsByRound[currentRound][1];
        vPos[2] = g_vTankPositionsByRound[currentRound][2];
        vAng[0] = g_vTankAnglesByRound[currentRound][0];
        vAng[1] = g_vTankAnglesByRound[currentRound][1];
        vAng[2] = g_vTankAnglesByRound[currentRound][2];
        PrintToConsoleAll("[TankFight] ProcessPredictModel - 使用预生成位置 Round: %d", currentRound);
        return CreateTankGlowModel(vPos, vAng);
    }

    if (GetVectorLength(vPos) == 0.0)
    {
        if (L4D2Direct_GetVSTankToSpawnThisRound(0))
        {

            // 根据当前Tank流程百分比获取位置
            for (float p = L4D2Direct_GetVSTankFlowPercent(0); p < 1.0; p += 0.01)
            {
                TerrorNavArea nav = GetBossSpawnAreaForFlow(p);
                if (nav.Valid())
                {
                    L4D_FindRandomSpot(view_as<int>(nav), vPos);
                    vPos[2] -= 8.0; // less floating off ground

                    vAng[0] = 0.0;
                    vAng[1] = GetRandomFloat(0.0, 360.0);
                    vAng[2] = 0.0;

                    break;
                }
            }
        }
    }

    if (GetVectorLength(vPos) == 0.0)
        return -1;

    return CreateTankGlowModel(vPos, vAng);
}

/**
 * 在指定位置生成一瓶止痛片
 */
void SpawnPainPillsAtPosition(const float vPos[3], const float vAng[3])
{
    int entity = CreateEntityByName("weapon_pain_pills");
    if (entity == -1) return;

    DispatchSpawn(entity);

    // 增加高度200
    float spawnPos[3];
    spawnPos[0] = vPos[0];
    spawnPos[1] = vPos[1];
    spawnPos[2] = vPos[2] + 100.0;

    TeleportEntity(entity, spawnPos, vAng, NULL_VECTOR);
}

/**
 * 给所有生还者补充弹药
 */
void GiveAmmoToAllSurvivors()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsSurvivor(i) && IsPlayerAlive(i))
        {
            CheatCommand("give", "ammo", i);
        }
    }
}

/**
 * 获取生还者模型的刷新位置
 */
int ProcessSurPredictModel(float vPos[3], float vAng[3])
{
    if (GetVectorLength(vPos) == 0.0)
    {
        if (L4D2Direct_GetVSTankToSpawnThisRound(0))
        {
            // 从 -12% 反方向获取位置
            for (float p = L4D2Direct_GetVSTankFlowPercent(0) -0.12; p > 0.0; p -= 0.01)
            {
                TerrorNavArea nav = GetBossSpawnAreaForFlow(p);
                if (nav.Valid())
                {
                    L4D_FindRandomSpot(view_as<int>(nav), vPos);
                    vPos[2] -= 8.0; // less floating off ground

                    vAng[0] = 0.0;
                    vAng[1] = GetRandomFloat(0.0, 360.0);
                    vAng[2] = 0.0;

                    break;
                }
            }
        }
    }

    if (GetVectorLength(vPos) == 0.0)
        return -1;

    // 从第二个克开始生成药物和补充弹药
    if (g_iTankFightCurrentRound >= 1)
    {
        SpawnPainPillsAtPosition(vPos, vAng);
        GiveAmmoToAllSurvivors();
    }

    return CreateSurvivorGlowModel(vPos, vAng);
}

TerrorNavArea GetBossSpawnAreaForFlow(float flow)
{
    float vPos[3];
    TheEscapeRoute().GetPositionOnPath(flow, vPos);
    
    TerrorNavArea nav = TerrorNavArea(vPos);
    if (!nav.Valid())
        return NULL_NAV_AREA;
    
    ArrayList aList = new ArrayList();
    while( !nav.IsValidForWanderingPopulation()
        || nav.m_isUnderwater
        || (nav.GetCenter(vPos), vPos[2] += 10.0, !ZombieManager.IsSpaceForZombieHere(vPos))
        || nav.m_activeSurvivors )
    {
        if (aList.FindValue(nav) != -1)
        {
            delete aList;
            return NULL_NAV_AREA;
        }
        
        if (nav.Valid())
            aList.Push(nav);
        
        nav = nav.GetNextEscapeStep();
    }
    
    delete aList;
    return nav;
}

//=========================================================================================================

//=========================================================================================================

int CreateGlowModel(const float vPos[3], const float vAng[3], const char[] modelPath, const char[] defaultAnim)
{
    int entity = CreateEntityByName("prop_dynamic");
    if (entity == -1)
        return -1;

    SetEntityModel(entity, modelPath);
    DispatchKeyValue(entity, "disableshadows", "1");
    DispatchKeyValue(entity, "DefaultAnim", defaultAnim);
    DispatchSpawn(entity);

    SetEntProp(entity, Prop_Send, "m_CollisionGroup", 0);
    SetEntProp(entity, Prop_Send, "m_nSolidType", 0);
    L4D2_SetEntityGlow(entity, L4D2Glow_Constant, 0, 0, {77, 102, 255}, false);
    TeleportEntity(entity, vPos, vAng, NULL_VECTOR);

    return entity;
}

int CreateSurvivorGlowModel(const float vPos[3], const float vAng[3])
{
    return CreateGlowModel(vPos, vAng, g_sSurvivorModels_Plugin[PickTankVariant()], "Idle_Calm_Pistol");
}

int CreateTankGlowModel(const float vPos[3], const float vAng[3])
{
    return CreateGlowModel(vPos, vAng, g_sTankModels[PickTankVariant()], "idle");
}

//=========================================================================================================

public void OnGetMissionInfo(int pThis)
{
    if (strcmp(g_sTankModels[TANK_VARIANT_SLOT], "N/A") == 0)
    {
        static char buffer[64];
        FormatEx(buffer, sizeof(buffer), "modes/versus/%i/TankVariant", L4D_GetCurrentChapter());
        InfoEditor_GetString(pThis, buffer, g_sTankModels[TANK_VARIANT_SLOT], TANK_MODEL_STRLEN);
    }
}

int PickTankVariant()
{
    if (strcmp(g_sTankModels[TANK_VARIANT_SLOT], "N/A") != 0)
        return TANK_VARIANT_SLOT;
    
    if (!g_bLeft4Dead2 || L4D2_GetSurvivorSetMod() == 2)
        return 0;
    
    // in case some characteristic configs enables flow tank
    char sCurrentMap[64];
    GetCurrentMap(sCurrentMap, sizeof(sCurrentMap));
    if (strcmp(sCurrentMap, "c7m1_docks") == 0)
        return 1;
    
    return 2;
}

void CheatCommand(const char[] sCmd, const char[] sArgs = "", int target = 0)
{
    int client = target;

    // 如果没有指定target或target无效，找到第一个有效的玩家（默认行为）
    if (!client || !IsClientInGame(client) || IsFakeClient(client))
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i))
            {
                client = i;
                break;
            }
        }
    }

    if (!client) return;

    int admindata = GetUserFlagBits(client);
    SetUserFlagBits(client, ADMFLAG_ROOT);
    int iFlags = GetCommandFlags(sCmd);
    SetCommandFlags(sCmd, iFlags & ~FCVAR_CHEAT);
    FakeClientCommand(client, "%s %s", sCmd, sArgs);
    SetCommandFlags(sCmd, iFlags);
    SetUserFlagBits(client, admindata);
}
void TeleportAllSurvivorToPercentFlow(float TargetPercent)
{
    float vPos[3], vAng[3];
    // 从 -12% 反方向获取位置
    for (float p = TargetPercent; p > 0.0; p -= 0.01)
    {
        TerrorNavArea nav = GetBossSpawnAreaForFlow(p);
        if (nav.Valid())
        {
            L4D_FindRandomSpot(view_as<int>(nav), vPos);
            vPos[2] -= 8.0; // less floating off ground

            vAng[0] = 0.0;
            vAng[1] = GetRandomFloat(0.0, 360.0);
            vAng[2] = 0.0;
            for (int i = 1; i <= MaxClients; i++){
                if (IsClientInGame(i) && IsSurvivor(i)){
                    TeleportEntity(i, vPos, vAng, NULL_VECTOR);
                }
            }
            break;
        }
    }
}

/**
 * 显示当前每只tank刷出的奖励分的指令处理函数
 * 支持 sm_cur 指令
 */
public Action Command_ShowTankScore(int client, int args)
{
    int scorePerTank = g_cvTankFightSurvivorScorePerTank.IntValue;
    int totalTanks = g_iTankFightCurrentRound;
    int totalScore = scorePerTank * totalTanks;

    CPrintToChat(client, "[{green}!{default}] 每只Tank奖励分: {olive}%d", scorePerTank);

    return Plugin_Continue;
}

/**
 * 显示本局Tank出现位置的指令处理函数
 * 支持 sm_tank, sm_witch 两个指令
 */
public Action Command_ShowTankPositions(int client, int args)
{
    if (!g_bTankPositionsPreGenerated)
    {
        CPrintToChat(client, "[{green}!{default}] Tank 位置尚未预生成");
        return Plugin_Handled;
    }

    int numRounds = g_cvTankFightRounds.IntValue;
    CPrintToChat(client, "[{green}!{default}] ========== 本局 Tank 位置信息 ==========");
    CPrintToChat(client, "[{green}!{default}] 总轮数: {olive}%d", numRounds);

    int validCount = 0;
    for (int i = 0; i < numRounds; i++)
    {
        if (g_bTankPositionSavedByRound[i])
        {
            validCount++;
            float flowPercent = g_fTankFlowPercentByRound[i] * 100.0;
            CPrintToChat(client, "[{green}!{default}] 第 {olive}%d {default}轮 - 流程: {olive}%.2f%% {default}",
                        i + 1, flowPercent);
        }
    }


    return Plugin_Handled;
}
//=========================================================================================================