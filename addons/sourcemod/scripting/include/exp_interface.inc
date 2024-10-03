#if defined _exp_interface_included
 #endinput
#endif
#define _exp_interface_included

enum {
	EXPRANK_1,
	EXPRANK_2,
	EXPRANK_3,
	EXPRANK_4,
	EXPRANK_5,
	EXPRANK_6,
	EXPRANK_7,
	EXPRANK_8,
	EXPRANK_9,
	EXPRANK_SIZE
}

static int EXPRankTable[EXPRANK_SIZE] = {
	20850,//0.01%
	18630,//0.1%
	14846,//1%
	7980,//5%
	3584,//20%
	1949,//35%
	952,//50%
	290,//70%
	0//100%
}
static char EXPRankNames[EXPRANK_SIZE][] = {
	"活化石登",
	"超级老登",
	"老登",
	"小老登",
	"中登",
	"小中登",
	"小登",
	"小小登",
	"看不见登"
}
/**
 * @brief 获取客户端的等级
 *
 * @param client		客户端
 *
 * @return				等级
 */
int L4D2_GetClientExpRankLevel(int client){
	int rank = L4D2_GetClientExp(client);
	for (int i = 0; i < EXPRANK_SIZE; i++){
		if (rank > EXPRankTable[i]) return i;
	}
	return 0;
}

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
 * @note 成就信息将在OnClientPutServer后获取，请至少等待4s
 *
 * @param client		要获取的客户端
 *
 * @return				玩家的经验评分, -2 为查询失败, 0为未查询过（bot）.
 */
native int L4D2_GetClientExp(int client);

/**
 * @brief 检查所有人的经验评分，如果有人查询失败就再次查询
 * @note 请之多等待4s以查询完成
 */
native void L4D2_CheckAndGetAllClientExp();

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
	MarkNativeAsOptional("L4D2_OnGetExp");
}
#endif