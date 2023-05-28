#pragma semicolon 1
#include <sourcemod>

int iTickrate;

public OnPluginStart() {
	iTickrate = GetCommandLineParamInt("-tickrate", 30);
	//SetRates();
}

/*public void OnConfigsExecuted() {
	SetRates();
}*/

public void OnAutoConfigsBuffered() {
	SetRates();
}

SetRates() {
	SetConVarInt(FindConVar("sv_minrate"), iTickrate * 1000, true, false);
	SetConVarInt(FindConVar("sv_maxrate"), iTickrate * 1000, true, false);
	SetConVarInt(FindConVar("sv_minupdaterate"), iTickrate, true, false);
	SetConVarInt(FindConVar("sv_maxupdaterate"), iTickrate, true, false);
	SetConVarInt(FindConVar("sv_mincmdrate"), iTickrate, true, false);
	SetConVarInt(FindConVar("sv_maxcmdrate"), iTickrate, true, false);
	SetConVarInt(FindConVar("net_splitpacket_maxrate"), (iTickrate * 1000) / 2, true, false);
	if (iTickrate > 30) {
		SetConVarInt(FindConVar("fps_max"), 0, false, false);
		SetConVarInt(FindConVar("sv_gravity"), 750, true, false);
	}
}