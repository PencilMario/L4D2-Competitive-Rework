//以下来自zipcore
/* Available icons
	"icon_bulb"
	"icon_caution"
	"icon_alert"
	"icon_alert_red"
	"icon_tip"
	"icon_skull"
	"icon_no"
	"icon_run"
	"icon_interact"
	"icon_button"
	"icon_door"
	"icon_arrow_plain"
	"icon_arrow_plain_white_dn"
	"icon_arrow_plain_white_up"
	"icon_arrow_up"
	"icon_arrow_right"
	"icon_fire"
	"icon_present"
	"use_binding"
*/
//用于插入显示ui
Handle g_hInterrupt_UI;

Action Timer_Interrupt_UI(Handle timer)
{
	if (g_iRoundState != 2)
	{
		delete g_hInterrupt_UI;
		return Plugin_Stop;
	}
	int	 white[3] = { 255, 255, 255 };
	// int red[3]	 = { 255, 0, 0 };
	char info[100];
	Format(info, 100, "二变倒计时：%d 秒", g_iSeekTime - g_hRandomTime.IntValue);
	PrintHintTextToAll(info);
	// DisplayInstructorHintAll(1.00, 0.0, 0.0, true, false, "icon_alert_red", "", "", true, white, false, info);
	return Plugin_Continue;
}

Action Timer_Repeat_UI(Handle timer)
{
	if (g_hInterrupt_UI != null)
	{
		return Plugin_Continue;
	}
	int	 white[3] = { 255, 255, 255 };
	int	 red[3]	  = { 255, 0, 0 };
	char info[100];
	switch (g_iRoundState)
	{
		case 0:
		{
			Format(info, 100, "按下R键或输入!prop可以打开面板。");
			PrintHintTextToAll(info);
			// DisplayInstructorHintAll(1.00, 0.0, 0.0, true, false, "icon_tip", "", "", true, white, false, info);
			return Plugin_Continue;
		}
		case 1:
		{
			Format(info, 100, "特感将于%d秒后开始行动", g_iHideTime);
			if (g_iHideTime > 10)
			{
				PrintHintTextToAll(info);
				// DisplayInstructorHintAll(1.00, 0.0, 0.0, true, false, "icon_info", "", "", true, white, false, info);
			}
			else
			{
				PrintHintTextToAll(info);
				// DisplayInstructorHintAll(1.00, 0.0, 0.0, true, false, "icon_alert", "", "", true, red, true, info);
			}
			return Plugin_Continue;
		}
		case 2:
		{
			/*否则震动属性将持续下去
			if (g_iSeekTime == g_hSeekTime.IntValue)
			{
				return Plugin_Continue;
			}
            */
			Format(info, 100, "回合剩余%d秒 生还:%d人 特感:%d人", g_iSeekTime, PlayerStatistics(2, true), PlayerStatistics(3, true));
			if (g_iSeekTime > 60)
			{
				PrintHintTextToAll(info);
				// DisplayInstructorHintAll(1.00, 0.0, 0.0, true, false, "icon_info", "", "", true, white, false, info);
			}
			else
			{
				PrintHintTextToAll(info);
				// DisplayInstructorHintAll(1.00, 0.0, 0.0, true, false, "icon_alert", "", "", true, red, true, info);
			}
			return Plugin_Continue;
		}
		case 3:
		{
			Format(info, 100, "回合结束, %s 胜利!", g_iWinnerTeam == 2 ? "生还" : "特感");
			PrintHintTextToAll(info);
			// DisplayInstructorHintAll(1.00, 0.0, 0.0, true, false, "icon_info", "", "", true, white, false, info);
		}
	}
	return Plugin_Continue;
}

void DisplayInstructorHint(int iTargetEntity, float fTime, float fHeight, float fRange, bool bFollow, bool bShowOffScreen, char[] sIconOnScreen, char[] sIconOffScreen, char[] sCmd, bool bShowTextAlways, int iColor[3], bool bShake, char sText[100])
{
	int iEntity = CreateEntityByName("env_instructor_hint");

	if (iEntity <= 0)
		return;

	char sBuffer[32];
	FormatEx(sBuffer, sizeof(sBuffer), "%d", iTargetEntity);

	// Target
	DispatchKeyValue(iTargetEntity, "targetname", sBuffer);
	DispatchKeyValue(iEntity, "hint_target", sBuffer);

	// Static
	FormatEx(sBuffer, sizeof(sBuffer), "%d", !bFollow);
	DispatchKeyValue(iEntity, "hint_static", sBuffer);

	// Timeout
	FormatEx(sBuffer, sizeof(sBuffer), "%d", RoundToFloor(fTime));
	DispatchKeyValue(iEntity, "hint_timeout", sBuffer);
	if (fTime > 0.0)
		RemoveTheEntity(iEntity, fTime);

	// Height
	FormatEx(sBuffer, sizeof(sBuffer), "%d", RoundToFloor(fHeight));
	DispatchKeyValue(iEntity, "hint_icon_offset", sBuffer);

	// Range
	FormatEx(sBuffer, sizeof(sBuffer), "%d", RoundToFloor(fRange));
	DispatchKeyValue(iEntity, "hint_range", sBuffer);

	// Show off screen
	FormatEx(sBuffer, sizeof(sBuffer), "%d", !bShowOffScreen);
	DispatchKeyValue(iEntity, "hint_nooffscreen", sBuffer);

	// Icons
	DispatchKeyValue(iEntity, "hint_icon_onscreen", sIconOnScreen);
	DispatchKeyValue(iEntity, "hint_icon_offscreen", sIconOffScreen);

	// Command binding
	DispatchKeyValue(iEntity, "hint_binding", sCmd);

	// Show text behind walls
	FormatEx(sBuffer, sizeof(sBuffer), "%d", bShowTextAlways);
	DispatchKeyValue(iEntity, "hint_forcecaption", sBuffer);

	// Text color
	FormatEx(sBuffer, sizeof(sBuffer), "%d %d %d", iColor[0], iColor[1], iColor[2]);
	DispatchKeyValue(iEntity, "hint_color", sBuffer);

	// Shake
	FormatEx(sBuffer, sizeof(sBuffer), "%d", bShake);
	DispatchKeyValue(iEntity, "hint_shakeoption", sBuffer);

	// Text
	ReplaceString(sText, sizeof(sText), "\n", " ");
	DispatchKeyValue(iEntity, "hint_caption", sText);

	DispatchSpawn(iEntity);
	AcceptEntityInput(iEntity, "ShowHint");
}

void DisplayInstructorHintAll(float fTime, float fHeight, float fRange, bool bFollow, bool bShowOffScreen, char[] sIconOnScreen, char[] sIconOffScreen, char[] sCmd, bool bShowTextAlways, int iColor[3], bool bShake, char sText[100])
{
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			if (g_bDefaultUIType[i])
			{
				PrintHintText(i, sText);
				return;
			}
			else if (GetClientTeam(i) == 1 || !IsPlayerAlive(i) || IsGhost(i))
			{
				PrintHintText(i, sText);
				return;
			}
			int iEntity = CreateEntityByName("env_instructor_hint");

			if (iEntity <= 0)
				return;

			char sBuffer[32];
			FormatEx(sBuffer, sizeof(sBuffer), "%d", i);

			// Target
			DispatchKeyValue(i, "targetname", sBuffer);
			DispatchKeyValue(iEntity, "hint_target", sBuffer);

			// Static
			FormatEx(sBuffer, sizeof(sBuffer), "%d", !bFollow);
			DispatchKeyValue(iEntity, "hint_static", sBuffer);

			// Timeout
			FormatEx(sBuffer, sizeof(sBuffer), "%d", RoundToFloor(fTime));
			DispatchKeyValue(iEntity, "hint_timeout", sBuffer);
			if (fTime > 0.0)
				RemoveTheEntity(iEntity, fTime);

			// Height
			FormatEx(sBuffer, sizeof(sBuffer), "%d", RoundToFloor(fHeight));
			DispatchKeyValue(iEntity, "hint_icon_offset", sBuffer);

			// Range
			FormatEx(sBuffer, sizeof(sBuffer), "%d", RoundToFloor(fRange));
			DispatchKeyValue(iEntity, "hint_range", sBuffer);

			// Show off screen
			FormatEx(sBuffer, sizeof(sBuffer), "%d", !bShowOffScreen);
			DispatchKeyValue(iEntity, "hint_nooffscreen", sBuffer);

			// Icons
			DispatchKeyValue(iEntity, "hint_icon_onscreen", sIconOnScreen);
			DispatchKeyValue(iEntity, "hint_icon_offscreen", sIconOffScreen);

			// Command binding
			DispatchKeyValue(iEntity, "hint_binding", sCmd);

			// Show text behind walls
			FormatEx(sBuffer, sizeof(sBuffer), "%d", bShowTextAlways);
			DispatchKeyValue(iEntity, "hint_forcecaption", sBuffer);

			// Text color
			FormatEx(sBuffer, sizeof(sBuffer), "%d %d %d", iColor[0], iColor[1], iColor[2]);
			DispatchKeyValue(iEntity, "hint_color", sBuffer);

			// Shake
			FormatEx(sBuffer, sizeof(sBuffer), "%d", bShake);
			DispatchKeyValue(iEntity, "hint_shakeoption", sBuffer);

			// Text
			ReplaceString(sText, sizeof(sText), "\n", " ");
			DispatchKeyValue(iEntity, "hint_caption", sText);

			DispatchSpawn(iEntity);
			AcceptEntityInput(iEntity, "ShowHint");
		}
	}
}

void RemoveTheEntity(int entity, float time)
{
	if (time == 0.0)
	{
		if (IsValidEntity(entity))
		{
			char edictname[32];
			GetEdictClassname(entity, edictname, 32);

			if (!StrEqual(edictname, "player"))
				AcceptEntityInput(entity, "kill");
		}
	}
	else if (time > 0.0)
		CreateTimer(time, RemoveEntityTimer, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
}

public Action RemoveEntityTimer(Handle Timer, any entityRef)
{
	int entity = EntRefToEntIndex(entityRef);
	if (entity != INVALID_ENT_REFERENCE)
		RemoveEntity(entity);	 // RemoveEntity(...) is capable of handling references

	return (Plugin_Stop);
}

public Action OnNormalSoundPlayed(char sample[PLATFORM_MAX_PATH], int &entity, float &volume, int &level, int &pitch, float pos[3], int &flags, float &delay)
{
	if (0 < entity <= MaxClients)
	{
		if (StrContains(sample, "beepclear") != -1)
		{
			PrintToChatAll("找到目标声音");
			StopSound(entity, SNDCHAN_STATIC, "ui/beepclear.wav");
			return Plugin_Stop;
		}
	}
	return Plugin_Continue;
}