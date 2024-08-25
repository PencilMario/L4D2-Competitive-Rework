///////////////
//用于生还菜单//
///////////////
bool	  g_bLockCamera[MAXPLAYERS + 1];			   //生还者是否锁定视角
bool	  g_bFlashing[MAXPLAYERS + 1];				   //克是否正处于吃闪状态。
int		  g_iOwnProp[MAXPLAYERS + 1];				   //生还者锁定视角后其对应的实体id。
int		  g_iPropNum[MAXPLAYERS + 1] = { -1, ... };	   //生还者选择的模型序号
int		  g_iPropDownCount[MAXPLAYERS + 1];			   //生还者重选模型的次数。
int		  g_iCreateFakeProps[MAXPLAYERS + 1];		   //生还者创造假身的次数
int		  g_iPipeBomb[MAXPLAYERS + 1];				   //生还者发射闪光弹的次数
int		  g_iVomitjar[MAXPLAYERS + 1];				   //生还者发射胆汁的次数
float	  g_fLockOrigin[MAXPLAYERS + 1][3];			   //生还者锁定视角前的坐标，用于传送其生成的实体。
float	  g_fLockAngle[MAXPLAYERS + 1][3];			   //生还者锁定视角前的角度，用于传送其生成的实体。
ArrayList g_hFakeProps[MAXPLAYERS + 1];				   //储存假身的集合
///////////////
//用于坦克菜单//
///////////////
int		  g_iTankType[MAXPLAYERS + 1];		 // Tank类型
int		  g_iTankAbility[MAXPLAYERS + 1];	 //拳头能力的实体id
ArrayList g_hNavList;						 //储存用于传送的Navs
///////////////
//生还坦克共用//
///////////////
int		  g_iSkillCD[MAXPLAYERS + 1];		   //客户端使用技能的cd。
///////////////
//用于回合设置//
///////////////
int		  g_iHideTime;		//躲藏阶段持续时间
int		  g_iSeekTime;		//寻找阶段持续时间
int		  g_iWinnerTeam;	//谁赢了
int		  g_iRoundState;	//游戏状态。此变量不应该直接使用，而是用SetRoundState()和GetRoundState()来改变和获取回合状态。
ConVar	  g_hHideTime;		//躲藏阶段持续时间(ConVar)。
ConVar	  g_hSeekTime;		//寻找阶段持续时间(ConVar)。
ConVar	  g_hRandomTime;	//寻找阶段剩余多少秒时随机二变, 设置为0则禁用
ConVar	  g_hBasicDmg;		//克的基础伤害
ConVar	  g_hGunDmg;		//持枪特感的基础伤害
///////////////
//用于Helper //
///////////////
enum PHRoundState
{
	Round_Readyup = 0,	  //准备中
	Round_Hiding,		  //躲藏中
	Round_Seeking,		  //搜寻中
	Round_Over			  //已结束
};
enum PHPropType
{
	Prop_Own = 0,	 //真身
	Prop_Fake,		 //假身
	Prop_Other		 //地图上的其他物件
};
enum
{
	SafeDoor_Start = 0,
	SafeDoor_End,
	SafeDoor_Displace,
	SafeDoor_Kill,
	SafeDoor_Disable
};
enum
{
	SetSI_Lock = 0,
	SetSI_Unlock
};
///////////////
//用于检测按键//
///////////////
int g_iLastButton[MAXPLAYERS + 1];	  //客户端最后一次按下的按键。
///////////////
//用于全局转发//
///////////////
GlobalForward
	g_hOnReadyStage_Post,		 //准备阶段
	g_hOnHidingStage_Post,		 //躲藏阶段
	g_hOnSeekingStage_Post,		 //搜寻阶段
	g_hOnEndStage_Post,			 //回合结束
	g_hOnCreateRealProp_Pre,	 //玩家创建真身
	g_hOnCreateRealProp_Post,	 //玩家创建真身后
	g_hOnCreateFakeProp_Pre,	 //玩家创建假身
	g_hOnCreateFakeProp_Post,	 //玩家创建假身后
	g_hOnLaunchBombs_Pre,		 //玩家发射投掷
	g_hOnLaunchBombs_Post,		 //玩家发射投掷后
	g_hOnTPFakeProp_Pre,		 //玩家传送至假身
	g_hOnTPFakeProp_Post;		 //玩家传送至假身后
///////////////
//用于转储模型//
///////////////
ArrayList g_hModelList;	   //储存来自prophunt.txt的模型信息
enum struct ModelInfo
{
	//序号
	int	  modelnum;
	//模型路径
	char  model[128];
	//模型名
	char  sname[64];
	//是否允许tp
	bool  allowtp;
	//是否允许创造假身
	bool  allowfake;
	//伤害修正倍率
	float dmgrevise;
	// z轴修正
	float zaxisup;
}