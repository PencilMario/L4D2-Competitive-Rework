#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#define PL_VERSION "2.1"

new Handle:hWeaponSwitchFwd;

new Float:fLastMeleeSwing[MAXPLAYERS + 1];
new Float:fLastSwitchToMelee[MAXPLAYERS + 1];
new bool:bLate;
new bool:bFastMeleed[MAXPLAYERS + 1];

ConVar c_fasemelee_fatigue;

public Plugin myinfo =
{
	name = "Fast melee fix",
	author = "sheo",
	description = "Fixes the bug with too fast melee attacks",
	version = PL_VERSION,
	url = "http://steamcommunity.com/groups/b1com"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	bLate = late;
	return APLRes_Success;
}

public OnPluginStart()
{
	decl String:gfstring[128];
	GetGameFolderName(gfstring, sizeof(gfstring));
	if (!StrEqual(gfstring, "left4dead2", false))
	{
		SetFailState("Plugin supports Left 4 dead 2 only!");
	}
	HookEvent("weapon_fire", Event_WeaponFire);
	CreateConVar("l4d2_fast_melee_fix_version", PL_VERSION, "Fast melee fix version");
	c_fasemelee_fatigue = CreateConVar("l4d2_fast_melee_fatigue", "0", "1=速砍计入推, 没推时才阻止速砍, 0=阻止速砍");
	if (bLate)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				SDKHook(i, SDKHook_WeaponSwitchPost, OnWeaponSwitched);
			}
		}
	}

	hWeaponSwitchFwd = CreateGlobalForward("OnClientMeleeSwitch", ET_Ignore, Param_Cell, Param_Cell);
}

public OnClientPutInServer(client)
{
	if (!IsFakeClient(client))
	{
		SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitched);
	}
	fLastMeleeSwing[client] = 0.0;
}

Action:Event_WeaponFire(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0 && !IsFakeClient(client))
	{
		decl String:sBuffer[64];
		GetEventString(event, "weapon", sBuffer, sizeof(sBuffer));
		if (StrEqual(sBuffer, "melee"))
		{
			fLastMeleeSwing[client] = GetGameTime(); // 上次近战
			// 检测是否进行速砍了
			if (c_fasemelee_fatigue.IntValue && (fLastSwitchToMelee[client] - fLastMeleeSwing[client]) < 0.92){
				bFastMeleed[client] = true;
				PrintHintText(client, "你正在进行速砍!\n你的速砍将视为一次推\n当你不能推时, 你将不能进行速砍!");
				int id = L4D2_GetWeaponIdByWeaponName(sBuffer);
				float time = GetEntPropFloat(client, Prop_Send, "m_flNextShoveTime") + L4D2_GetFloatMeleeAttribute(id, L4D2FMWA_RefireDelay);		
				SetEntPropFloat(client, Prop_Send, "m_flNextPrimaryAttack", time);	
				}
		}
	}
}

void OnWeaponSwitched(client, weapon)
{
	if (!IsFakeClient(client) && IsValidEntity(weapon))
	{
		decl String:sBuffer[32];
		GetEntityClassname(weapon, sBuffer, sizeof(sBuffer));
		if (StrEqual(sBuffer, "weapon_melee"))
		{
			fLastSwitchToMelee[client] = GetGameTime();// 上次切换到近战
			new Float:fShouldbeNextAttack = fLastMeleeSwing[client];
			
			if (!c_fasemelee_fatigue.IntValue) {bFastMeleed[client] = false;fShouldbeNextAttack = fLastMeleeSwing[client] + 0.92;}
			// 已经速砍过了
			if (bFastMeleed[client])
			{
				// 右键是否在cd？
				float time = GetEntPropFloat(client, Prop_Send, "m_flNextShoveTime")
				if (time - GetGameTime() > 0){
					//bFastMeleed[client];	
				}else{
					fShouldbeNextAttack = fLastMeleeSwing[client] + 0.92
				}
				bFastMeleed[client] = false;
			}

			
			new Float:fByServerNextAttack = GetGameTime() + 0.4;
			
			SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", (fShouldbeNextAttack > fByServerNextAttack) ? fShouldbeNextAttack : fByServerNextAttack);

			Call_StartForward(hWeaponSwitchFwd);

			Call_PushCell(client);

			Call_PushCell(weapon);

			Call_Finish();
		}
	}
}