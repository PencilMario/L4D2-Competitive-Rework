#if defined _exp_interface_included
 #endinput
#endif
#define _exp_interface_included


/**
 * @brief 当成功获取一个客户端的经验信息时被调用
 *
 * @param client		客户端
 * @param exp			客户端的经验评分
 *
 * @noreturn
 */
forward void L4D2_OnGetExp(int client, int exp);

/**
 * @brief 获取客户端的经验评分
 * @note 获取成就信息需要时间，请不要调用太快
 *
 * @param client		要获取的客户端
 *
 * @return				玩家的经验评分, -2 为查询失败, 0为未查询过（bot/客户端未authorization.
 */
native int L4D2_GetClientExp(int client);

public SharedPlugin __pl_exp_interface = 
{
	name = "exp_interface",
	file = "exp_interface.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_exp_interface_SetNTVOptional()
{
	MarkNativeAsOptional("L4D2_GetClientExp");
}
#endif