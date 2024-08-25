#if defined  _prophunt_single_included_
 #endinput
#endif
#define _prophunt_single_included_

/**
 * 在进入准备阶段后调用。
 */
forward void OnReadyStage_Post();

/**
 * 在进入躲藏阶段后调用。
 */
forward void OnHidingStage_Post();

/**
 * 进入搜寻阶段后调用。
 */
forward void OnSeekingStage_Post();

/**
 * 在进入结束阶段后调用。
 */
forward void OnEndStage_Post();

/**
 * 在玩家创造真身物件前调用。
 * 
 * @return          Plugin_Handle = 阻止, Plugin_Continue = 允许。
 */
forward Action OnCreateRealProp_Pre(int client, int entity);

/**
 * 在玩家创造真身物件后调用。如果OnCreateRealProp_Pre被阻止，
 * 将不会触发此转发。
 */
forward void OnCreateRealProp_Post(int client, int entity);

/**
 * 在玩家创造假身物件前调用。
 * 
 * @return          Plugin_Handle = 阻止, Plugin_Continue = 允许。
 */
forward Action OnCreateFakeProp_Pre(int client);

/**
 * 在玩家创造假身物件后调用。如果OnCreateFakeProp_Pre被阻止,
 * 将不会触发此转发。
 */
forward void OnCreateFakeProp_Post(int client, int entity);

/**
 * 在玩家发射投掷前调用。
 * 
 * @return          Plugin_Handle = 阻止, Plugin_Continue = 允许。
 */
forward Action OnLaunchBombs_Pre(int client);

/**
 * 在玩家发射投掷后调用。如果OnLaunchBombs_Pre被阻止,
 * 将不会触发此转发。
 */
forward void OnLaunchBombs_Post(int client);

/**
 * 在玩家传送至假身前调用。
 * 
 * @return          Plugin_Handle = 阻止, Plugin_Continue = 允许。
 */
forward Action OnTPFakeProp_Pre(int client, int entity);

/**
 * 在玩家传送至假身后调用。如果OnTPFakeProp_Pre被阻止,
 * 将不会触发此转发。
 */
forward void OnTPFakeProp_Post(int client, int entity);

/**
 * 获取回合状态。
 *
 * @return          0 = 准备阶段, 1 = 躲藏阶段, 2 = 搜寻阶段, 3 = 回合结束.
 */
native int GetPHRoundState();

/**
 * 设置回合状态并触发对应的倒计时或输出。
 * 请勿在阶段的Post转发中使用, 会引起无限循环。
 *
 */
native void SetPHRoundState(int PHRoundState);

/**
 * 本回合的躲猫猫是否正在进行中。
 *
 * @return          如果是就返回true, 否则为false.
 */
native bool IsPHRoundLive();

public SharedPlugin __pl_prophunt_single =
{
	name = "prophunt_single",
	file = "prophunt_single.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_prophunt_single_SetNTVOptional()
{
	MarkNativeAsOptional("GetPHRoundState");
	MarkNativeAsOptional("SetPHRoundState");
	MarkNativeAsOptional("IsPHRoundLive");	
}
#endif