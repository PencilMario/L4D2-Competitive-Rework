/*  SM Translator
 *
 *  Copyright (C) 2018 Francisco 'Franc1sco' García
 * 
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option) 
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT 
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with 
 * this program. If not, see http://www.gnu.org/licenses/.
 */

#include <sdktools>
#include <ripext>
#include <SteamWorks>
#include <colors>
#include <logger>

#define DATA "1.0"

Logger log;

public Plugin myinfo =
{
    name = "SM Translator",
    description = "Translate chat messages",
    author = "Franc1sco franug",
    version = DATA,
    url = "http://steamcommunity.com/id/franug"
};

char ServerLang[5];
char ServerCompleteLang[32];

bool g_translator[MAXPLAYERS + 1];

char baiduapi[256] = "https://aip.baidubce.com/rpc/2.0/mt/texttrans/v1?access_token="


public void OnPluginStart()
{
    log = new Logger("sm_translator", LoggerType_NewLogFile);
    log.IgnoreLevel = LogType_Debug;
    LoadTranslations("sm_translator.phrases.txt");
    
    CreateConVar("sm_translator_version", DATA, "SM Translator Version", FCVAR_SPONLY|FCVAR_NOTIFY);
    
    AddCommandListener(Command_Say, "say");	
    //AddCommandListener(Command_SayTeam, "say_team");	
    
    GetLanguageInfo(GetServerLanguage(), ServerLang, 3, ServerCompleteLang, 32);
    
    RegConsoleCmd("sm_translator", Command_Translator);
    
    for(int i = 1; i <= MaxClients; i++)
        {
            if(IsClientInGame(i) && !IsFakeClient(i))
            {
                OnClientPostAdminCheck(i);
            }
        }
    GetAccessToken("beLX1eoWGvtlzU0GGG542Tox", "znhKVCi8l1gN4V1tssD4TaIa9iwKs2Ek");

}

public Action Command_Translator(int client, int args)
{
    DoMenu(client);
    return Plugin_Handled;
}

public void OnClientPostAdminCheck(int client)
{
    g_translator[client] = false;
    CreateTimer(4.0, Timer_ShowMenu, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ShowMenu(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    
    if (!client || !IsClientInGame(client))return Plugin_Continue;
    
    if (GetServerLanguage() == GetClientLanguage(client))return Plugin_Continue;

    CPrintToChat(client, "{lightgreen}[TRANSLATOR]{green} %t", "Type in chat !translator for open again this menu", client);
    DoMenu(client);
    return Plugin_Continue;
}

void DoMenu(int client)
{
    char temp[128];
    
    Menu menu = new Menu(Menu_select);
    menu.SetTitle("%t", "This server have a translation plugin so you can talk in your own language and it will be translated to others.Use translator?",client);
    
    Format(temp, sizeof(temp), "%t", "Yes, I want to use chat in my native language",client);
    menu.AddItem("yes", temp);
    
    
    Format(temp, sizeof(temp), "%t (%s)","No, I want to use chat in the official server language by my own", ServerCompleteLang);
    menu.AddItem("no", temp);
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_select(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_Select)
    {
        char selection[128];
        menu.GetItem(param, selection, sizeof(selection));
        
        if (StrEqual(selection, "yes"))g_translator[client] = true;
        else g_translator[client] = false;
        
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}
public Action Command_SayTeam(int client, const char[] command, int args)
{
    if (!IsValidClient(client))return Plugin_Continue;
    
    char buffer[255];
    GetCmdArgString(buffer,sizeof(buffer));
    StripQuotes(buffer);
    
    if (strlen(buffer) < 1)return Plugin_Continue;
    
    char commands[255];
    
    GetCmdArg(1, commands, sizeof(commands));
    ReplaceString(commands, sizeof(commands), "!", "sm_", false);
    ReplaceString(commands, sizeof(commands), "/", "sm_", false);

    
    if (CommandExists(commands))return Plugin_Continue;
    
    char temp[3];
    
    // Foreign
    if(GetServerLanguage() != GetClientLanguage(client))
    {
        if (!g_translator[client])return Plugin_Continue;
        
        Handle request = CreateRequest(buffer, ServerLang, client);
        SteamWorks_SendHTTPRequest(request);
        
        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsClientInGame(i) && !IsFakeClient(i) && i != client && GetClientLanguage(client) != GetClientLanguage(i))
            {
                GetLanguageInfo(GetClientLanguage(i), temp, 3); // get Foreign language
                Handle request2 = CreateRequest(buffer, temp, i, client, true); // Translate not Foreign msg to Foreign player
                SteamWorks_SendHTTPRequest(request2);
            }
        }
    }
    else // Not foreign
    {
        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsClientInGame(i) && !IsFakeClient(i) && i != client)
            {
                if (!g_translator[i])continue;
                
                GetLanguageInfo(GetClientLanguage(i), temp, 3); // get Foreign language
                Handle request = CreateRequest(buffer, temp, i, client, true); // Translate not Foreign msg to Foreign player
                SteamWorks_SendHTTPRequest(request);
            }
        }
    }
    return Plugin_Continue;
}


public Action Command_Say(int client, const char[] command, int args)
{
    if (!IsValidClient(client))return Plugin_Continue;
    
    char buffer[255];
    GetCmdArgString(buffer,sizeof(buffer));
    StripQuotes(buffer);
    
    if (strlen(buffer) < 1)return Plugin_Continue;
    
    char commands[255];
    
    GetCmdArg(1, commands, sizeof(commands));
    ReplaceString(commands, sizeof(commands), "!", "sm_", false);
    ReplaceString(commands, sizeof(commands), "/", "sm_", false);
    
    if (CommandExists(commands))return Plugin_Continue;
    
    char temp[3];
    
    // Foreign
    if(GetServerLanguage() != GetClientLanguage(client))
    {
        if (!g_translator[client])return Plugin_Continue;
        
        Handle request = CreateRequest(buffer, ServerLang, client);
        SteamWorks_SendHTTPRequest(request);
        
        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsClientInGame(i) && !IsFakeClient(i) && i != client && GetClientLanguage(client) != GetClientLanguage(i))
            {
                GetLanguageInfo(GetClientLanguage(i), temp, 3); // get Foreign language
                Handle request2 = CreateRequest(buffer, temp, i, client); // Translate not Foreign msg to Foreign player
                SteamWorks_SendHTTPRequest(request2);
            }
        }
    }
    else // Not foreign
    {
        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsClientInGame(i) && !IsFakeClient(i) && i != client)
            {
                if (!g_translator[i])continue;
                
                GetLanguageInfo(GetClientLanguage(i), temp, 3); // get Foreign language
                Handle request = CreateRequest(buffer, temp, i, client); // Translate not Foreign msg to Foreign player
                SteamWorks_SendHTTPRequest(request);
            }
        }
    }
    return Plugin_Continue;
}

void GetAccessToken(char[] client_id, char[] client_secret)
{
    Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, "https://aip.baidubce.com/oauth/2.0/token");
    SteamWorks_SetHTTPRequestGetOrPostParameter(request, "grant_type", "client_credentials");
    SteamWorks_SetHTTPRequestGetOrPostParameter(request, "client_id", client_id);
    SteamWorks_SetHTTPRequestGetOrPostParameter(request, "client_secret", client_secret);
    SteamWorks_SetHTTPCallbacks(request, Callback_TokenGeted);
    SteamWorks_SendHTTPRequest(request);
}
public int Callback_TokenGeted(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
    int iBufferSize;
    SteamWorks_GetHTTPResponseBodySize(request, iBufferSize);
    
    // ==================处理返回json==================
    char[] result = new char[iBufferSize];  
    SteamWorks_GetHTTPResponseBodyData(request, result, iBufferSize);
    delete request;
    char[] t = new char[iBufferSize]; 
    JSONObject json;
    log.info("Translator: 获取token api 返回 - %s", result);
    json = JSONObject.FromString(result);
    json.GetString("access_token", t, iBufferSize);
    log.info("Translator: access_token - %s", t);
    Format(baiduapi, sizeof(baiduapi), "%s%s", baiduapi, t);
    delete json;
    log.info("Translator: API Authed: %s", baiduapi);
    return 0;
}
Handle CreateRequest(char[] input, char[] target, int client, int other = 0, bool teammate_only = false)
{
    Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, baiduapi);
    SteamWorks_SetHTTPRequestHeaderValue(request, "Content-Type", "application/json");
    SteamWorks_SetHTTPRequestHeaderValue(request, "Accept", "application/json");

    if (StrEqual(target, "ar")) Format(target, 5, "ara");
    else if (StrEqual(target, "bg")) Format(target, 5, "bul");
    else if (StrEqual(target, "cze")) Format(target, 5, "cs");
    else if (StrEqual(target, "da")) Format(target, 5, "dan");
    else if (StrEqual(target, "fi")) Format(target, 5, "fin");
    else if (StrEqual(target, "fr")) Format(target, 5, "fra");
    else if (StrEqual(target, "ko")) Format(target, 5, "kor");
    else if (StrEqual(target, "pl")) Format(target, 5, "pl");
    else if (StrEqual(target, "pt_p")) Format(target, 5, "pt");
    else if (StrEqual(target, "ro")) Format(target, 5, "rom");
    else if (StrEqual(target, "chi")) Format(target, 5, "zh");
    else if (StrEqual(target, "sk")) Format(target, 5, "slo");
    else if (StrEqual(target, "es")) Format(target, 5, "spa");
    else if (StrEqual(target, "sv")) Format(target, 5, "swe");
    else if (StrEqual(target, "zho")) Format(target, 5, "cht");
    else if (StrEqual(target, "ua")) Format(target, 5, "ukr");
    else if (StrEqual(target, "vi")) Format(target, 5, "vie");

    JSONObject bodyjson = new JSONObject();
    bodyjson.SetString("from", "auto");
    bodyjson.SetString("to", target);
    bodyjson.SetString("q", input);
    log.debug("目标: %s, 文本: \"%s\"", target, input);
    char body[16536];
    bodyjson.ToString(body, 16536);
    SteamWorks_SetHTTPRequestRawPostBody(request, "application/json", body, 256);
    SteamWorks_SetHTTPRequestContextValue(request, GetClientUserId(client), other>0?GetClientUserId(other):0);
    if (!teammate_only){
        SteamWorks_SetHTTPCallbacks(request, Callback_OnHTTPResponse);
    }else{
        SteamWorks_SetHTTPCallbacks(request, Callback_OnHTTPResponse_Teammate);
    }
    delete bodyjson;
    return request;
}

public void Callback_OnHTTPResponse(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int userid, int other)
{
    if (!bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
    {        
        return;
    }

    int iBufferSize;
    SteamWorks_GetHTTPResponseBodySize(request, iBufferSize);
    
    // ==================处理返回json==================
    char[] result = new char[iBufferSize];  
    SteamWorks_GetHTTPResponseBodyData(request, result, iBufferSize);
    delete request;
    char[] t = new char[iBufferSize]; 
    JSONObject json;
    json = JSONObject.FromString(result);
    if (json.HasKey("error_msg")){
        json.GetString("error_msg", t, iBufferSize);
        Format(result, iBufferSize, "Error: %s", t);
        log.error("翻译异常：%s | ", t);
        delete json;
    }
    else if (json.HasKey("result"))
    {
        JSONObject t_json = view_as<JSONObject>(json.Get("result"));
        JSONArray t_jsona = view_as<JSONArray>(t_json.Get("trans_result"))
        JSONObject t_json2 = view_as<JSONObject>(t_jsona.Get(0));
        t_json2.GetString("dst", t, iBufferSize);
        Format(result, iBufferSize, "%s", t);
        delete t_json;
        delete t_jsona;
        delete t_json2;
    }
    

    // ==================处理结束==================
    int client = GetClientOfUserId(userid);
    
    if (!client || !IsClientInGame(client))return;
    
    if(other == 0)
    {
        CPrintToChat(client, "{teamcolor}%N {%t}{default}: %s", client, "translated for others", result);
    }
    else
    {
        int i = GetClientOfUserId(other);
        if (!i || !IsClientInGame(i))return;
        CPrintToChat(client, "{teamcolor}%N {%t}{default}: %s", i, "translated for you", result);
    }
}  

public void Callback_OnHTTPResponse_Teammate(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int userid, int other)
{
    if (!bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
    {        
        return;
    }

    int iBufferSize;
    SteamWorks_GetHTTPResponseBodySize(request, iBufferSize);
    
    // ==================处理返回json==================
    char[] result = new char[iBufferSize];  
    SteamWorks_GetHTTPResponseBodyData(request, result, iBufferSize);
    delete request;
    char[] t = new char[iBufferSize]; 
    JSONObject json;
    json = JSONObject.FromString(result);
    if (json.HasKey("error_msg")){
        json.GetString("error_msg", t, iBufferSize);
        Format(result, iBufferSize, "Error: %s", t);
        log.error("翻译异常：%s", t);
        delete json;
    }
    else if (json.HasKey("result"))
    {
        JSONObject t_json = view_as<JSONObject>(json.Get("result"));
        JSONArray t_jsona = view_as<JSONArray>(t_json.Get("trans_result"))
        JSONObject t_json2 = view_as<JSONObject>(t_jsona.Get(0));
        t_json2.GetString("dst", t, iBufferSize);
        Format(result, iBufferSize, "%s", t);
        PrintToConsoleAll("Translator: dst: %s", result);
        delete t_json;
        delete t_jsona;
        delete t_json2;
    }
    

    // ==================处理结束==================
    int client = GetClientOfUserId(userid);
    
    if (!client || !IsClientInGame(client))return;
    
    if(other == 0)
    {
        CPrintToChat(client, "(team){teamcolor}%N {%t}{default}: %s", client, "translated for others", result);
    }
    else
    {
        int i = GetClientOfUserId(other);
        if (!i || !IsClientInGame(i))return;
        if (GetClientTeam(i) != GetClientTeam(other)) return;
        CPrintToChat(client, "(team){teamcolor}%N {%t}{default}: %s", i, "translated for you", result);
    }
}  


stock bool IsValidClient(int client, bool bAllowBots = false, bool bAllowDead = true)
{
    if (!(1 <= client <= MaxClients) || !IsClientInGame(client) || (IsFakeClient(client) && !bAllowBots) || IsClientSourceTV(client) || IsClientReplay(client) || (!bAllowDead && !IsPlayerAlive(client)))
    {
        return false;
    }
    return true;
}