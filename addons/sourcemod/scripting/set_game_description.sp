#include <sourcemod>
#include <SteamWorks>

#pragma semicolon 1
#pragma newdecls required

char g_sName[64];
char g_sMapName[64];
ConVar config;

public Plugin myinfo = {
    name = "Description",
    author = "sp",
    description = "修改游戏desc",
    version = "1.0.0",
    url = ""
};

public void OnMapStart()
{   
    char cfgName[32];
    config = FindConVar("l4d_ready_cfg_name");
    if (config != INVALID_HANDLE){
        config.GetString(cfgName, sizeof(cfgName));
        Format(g_sName, sizeof(g_sName), "%s", cfgName);
    }
}

public void OnGameFrame()
{
    SteamWorks_SetGameDescription(g_sName);
}
