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

int g_iClientCoin[MAXPLAYERS], g_ClientCoinSpend_Team[MAXPLAYERS];

int g_iMenuSelfCoin;



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
    RegConsoleCmd("sm_gamble", CmdMenuTest);
}
public void OnAllPluginsLoaded(){
	if (LibraryExists("extra_menu")) OnLibraryAdded("extra_menu");
}
public void OnLibraryAdded(const char[] name)
{
    if( strcmp(name, "extra_menu") == 0 )
    {
        g_Extramenu = ExtraMenu(false, "", true);
        g_Extramenu.AddEntryText("<< 菠菜大世界 >>");
        g_iMenuSelfCoin = g_Extramenu.AddEntryText("g_iMenuSelfCoin", true);
        g_Extramenu.AddEntryText("");
        

    }
}

public void OnLibraryRemoved(const char[] name)
{
    if( strcmp(name, "extra_menu") == 0 )
    {
        OnPluginEnd();
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