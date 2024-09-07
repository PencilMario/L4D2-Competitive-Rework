/*
*	Extra Menu API - Test Plugin
*	Copyright (C) 2022 Silvers
*
*	This program is free software: you can redistribute it and/or modify
*	it under the terms of the GNU General Public License as published by
*	the Free Software Foundation, either version 3 of the License, or
*	(at your option) any later version.
*
*	This program is distributed in the hope that it will be useful,
*	but WITHOUT ANY WARRANTY; without even the implied warranty of
*	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*	GNU General Public License for more details.
*
*	You should have received a copy of the GNU General Public License
*	along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/



#define PLUGIN_VERSION 		"1.4"

/*======================================================================================
    Plugin Info:

*	Name	:	[ANY] Extra Menu API - Test Plugin
*	Author	:	SilverShot
*	Descrp	:	Allows plugins to create menus with more than 1-7 selectable entries and more functionality.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=338863
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
    Change Log:

1.4 (15-Oct-2022)
    - Added the alternative buttons demonstration to the "ExtraMenu_Create" native.

1.2 (15-Aug-2022)
    - Added a "meter" options demonstration.

1.0 (30-Jul-2022)
    - Initial release.

======================================================================================*/


#include <sourcemod>
#include <extra_menu>
#include <adminmenu>
#pragma semicolon 1
#pragma newdecls required


ExtraMenu g_Extramenu;
Handle hAdminMenu;

int g_RemoveLobby,g_playnumber,g_skipsteamcheck, g_infrespawn, g_Tankrespawnarea, g_reset_tank_iron, g_saveprops;



// ====================================================================================================
//					PLUGIN INFO
// ====================================================================================================



// ====================================================================================================
//					MAIN FUNCTIONS
// ====================================================================================================
public void OnPluginStart()
{
    TopMenu topmenu;
    if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
    {
      /* If so, manually fire the callback */
      OnAdminMenuReady(topmenu);
    }
    RegAdminCmd("sm_setmenu", CmdMenuTest, ADMFLAG_ROOT);
}
public void OnAllPluginsLoaded(){
	if (LibraryExists("extra_menu")) OnLibraryAdded("extra_menu");
}
public void OnLibraryAdded(const char[] name)
{
    if( strcmp(name, "extra_menu") == 0 )
    {
        g_Extramenu = ExtraMenu(false, "", true);
        g_Extramenu.AddEntry                            ("<服务器控制菜单 Page1>");
        g_Extramenu.AddEntry                            ("使用W/S选择选项, A/D进行调整");
        g_Extramenu.AddEntry                            ("  ");
        g_Extramenu.AddEntry                            ("A. 服务器控制");
        g_RemoveLobby = g_Extramenu.AddEntryOnly        ("1. 移除大厅匹配");
        g_skipsteamcheck = g_Extramenu.AddEntryCvarSwitch("2. 跳过steam验证 _OPT_", "sv_steam_bypass", 15, false);
        g_playnumber = g_Extramenu.AddEntryCvarAdd      ("3. 服务器人数: _OPT_", "sv_maxplayers", 13, false, 1, 1, GetConvarIntEx("slots_max_slots"));
        g_Extramenu.AddEntry                            ("  ");
        g_Extramenu.AddEntry                            ("B. 特感设置 ");
        g_infrespawn = g_Extramenu.AddEntryCvarAdd      ("1. 特感复活时间: _OPT_", "z_respawn_interval", 18,false,  1, 5, 20);
        g_Tankrespawnarea = g_Extramenu.AddEntryAdd     ("2. Tank刷新位置: _OPT_", false,  20, 5, 20, 80);
        g_reset_tank_iron = g_Extramenu.AddEntryOnly    ("3. 铁位置重置");
        g_saveprops = g_Extramenu.AddEntryOnly          ("4. 保存当前铁位置");
        g_Extramenu.AddEntry                            ("  ");



    }
}

public void OnLibraryRemoved(const char[] name)
{
    if( strcmp(name, "extra_menu") == 0 )
    {
        OnPluginEnd();
    }
}
public void OnAdminMenuReady(Handle menu) {
    /* If the category is third party, it will have its own unique name. */
    TopMenuObject sv_commands = FindTopMenuCategory(menu, ADMINMENU_SERVERCOMMANDS);
    if (menu == hAdminMenu && sv_commands != INVALID_TOPMENUOBJECT)
    {
      return;
    }
    AddToTopMenu(menu, "游戏规则设置", TopMenuObject_Item, Menu_CategoryHandler, sv_commands);
    hAdminMenu = menu;
}
public void Menu_CategoryHandler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int client, char[] buffer, int maxlength) {
	switch (action)
    {    
        case TopMenuAction_DisplayOption:
        {
          strcopy(buffer, maxlength, "游戏规则设置项");
        }
        case TopMenuAction_SelectOption , TopMenuAction_DrawOption:
        {
          //do
            //BuildMenu()
            g_Extramenu.Show(client);
        }
    }
}

// Always clean up the menu when finished
public void OnPluginEnd()
{
    g_Extramenu.Close();
}

// Display menu
Action CmdMenuTest(int client, int args)
{
    g_Extramenu.Show(client, MENU_TIME_FOREVER);
    return Plugin_Handled;
}

public void ExtraMenu_OnSelect(int client, int menu_id, int option, int value){
    if (menu_id != g_Extramenu._index) return;
    if (option == g_RemoveLobby) {
        ServerCommand("sm_unreserve;sm_cvar sv_force_unreserved 1; sm_cvar sv_tags hidden; sm_cvar sv_steamgroup 0");
    }
    else if (option == g_skipsteamcheck) {
        ServerCommand("sm_cvar sv_steam_bypass %i", value);
    }
    else if (option == g_playnumber){
        ServerCommand("sm_cvar sv_maxplayers %i", value);
    }
    else if (option == g_infrespawn){
        ServerCommand("sm_cvar z_respawn_interval %i", value);
    }
    else if (option == g_Tankrespawnarea){
        ServerCommand("sm_ftank %i", value);
    }
    else if (option == g_reset_tank_iron){
        ServerCommand("sm_resetprop");
    }
    else if (option == g_saveprops){
        ServerCommand("sm_saveprop");
    }
    
}


int GetConvarIntEx(char[] cvar){
    ConVar c = FindConVar(cvar);
    if (c != null){
        return c.IntValue;
    }else{
        return -1;
    }
}

/* int GetConvarFloattoIntEx(char[] cvar, float multi){
    ConVar c = FindConVar(cvar);
    if (c != null){
        return RoundToCeil(c.FloatValue * multi);
    }else{
        return -1;
    }
}
 */