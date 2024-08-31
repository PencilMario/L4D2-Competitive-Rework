//用于插入二变倒计时的ui
Handle g_hInterrupt_UI;
//用于准备阶段在聊天内显示提示，而避免与readyup冲突
Handle g_hTipsInChat;

Action Timer_Interrupt_UI(Handle timer)
{
	if (g_iRoundState != 2)
	{
		delete g_hInterrupt_UI;
		return Plugin_Stop;
	}
	char info[100];
	Format(info, 100, "二变倒计时：%d 秒", g_iSeekTime - g_hRandomTime.IntValue);
	PrintHintTextToAll(info);
	return Plugin_Continue;
}

Action Timer_Repeat_UI(Handle timer)
{
	if (g_hInterrupt_UI != null)
	{
		return Plugin_Continue;
	}
	char info[100];
	switch (g_iRoundState)
	{
		case 0:
		{
			if (g_hTipsInChat == null)
			{
				g_hTipsInChat = CreateTimer(30.0, Timer_TipsInChat, _, TIMER_REPEAT);
			}
			return Plugin_Continue;
		}
		case 1:
		{
			Format(info, 100, "特感将于%d秒后开始行动", g_iHideTime);
		}
		case 2:
		{
			Format(info, 100, "回合剩余%d秒 生还:%d人 特感:%d人", g_iSeekTime, PlayerStatistics(2, true), PlayerStatistics(3, true));
		}
		case 3:
		{
			Format(info, 100, "回合结束, %s胜利!", g_iWinnerTeam == 2 ? "生还" : "特感");
		}
	}
	PrintHintTextToAll(info);
	return Plugin_Continue;
}

Action Timer_TipsInChat(Handle timer)
{
	if (g_iRoundState == 0 || g_iRoundState == 1)
	{
		CPrintToChatAll("{green}按下R键或输入!prop可以打开面板。");
		CPrintToChatAll("{green}服务器大于8人时使用!jg并选择阵营也可加入游戏。");
	}
	return Plugin_Continue;
}