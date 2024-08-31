void SetupNativeNForwards()
{
	CreateNative("GetPHRoundState", Native_GetPHRoundState);
	CreateNative("SetPHRoundState", Native_SetPHRoundState);
	CreateNative("IsPHRoundLive", Native_IsPHRoundLive);

	g_hOnReadyStage_Post	 = new GlobalForward("OnReadyStage_Post", ET_Ignore);
	g_hOnHidingStage_Post	 = new GlobalForward("OnHidingStage_Post", ET_Ignore);
	g_hOnSeekingStage_Post	 = new GlobalForward("OnSeekingStage_Post", ET_Ignore);
	g_hOnEndStage_Post		 = new GlobalForward("OnEndStage_Post", ET_Ignore);
	g_hOnCreateRealProp_Pre	 = new GlobalForward("OnCreateRealProp_Pre", ET_Single, Param_Cell, Param_Cell);
	g_hOnCreateRealProp_Post = new GlobalForward("OnCreateRealProp_Post", ET_Ignore, Param_Cell, Param_Cell);
	g_hOnCreateFakeProp_Pre	 = new GlobalForward("OnCreateFakeProp_Pre", ET_Single, Param_Cell, Param_Cell);
	g_hOnCreateFakeProp_Post = new GlobalForward("OnCreateFakeProp_Post", ET_Ignore, Param_Cell, Param_Cell);
	g_hOnTPFakeProp_Pre		 = new GlobalForward("OnTPFakeProp_Pre", ET_Single, Param_Cell, Param_Cell);
	g_hOnTPFakeProp_Post	 = new GlobalForward("OnTPFakeProp_Post", ET_Ignore, Param_Cell, Param_Cell);
	g_hOnLaunchBombs_Pre	 = new GlobalForward("OnLaunchBombs_Pre", ET_Single, Param_Cell);
	g_hOnLaunchBombs_Post	 = new GlobalForward("OnLaunchBombs_Post", ET_Ignore, Param_Cell);
	
	RegPluginLibrary("prophunt_single");
}

any Native_GetPHRoundState(Handle plugin, int numParams)
{
	return g_iRoundState;
}

any Native_IsPHRoundLive(Handle plugin, int numParams)
{
	return (g_iRoundState == 2 || g_iRoundState == 3) ? true : false;
}

any Native_SetPHRoundState(Handle plugin, int numParams)
{
	PHRoundState iStateToSet = view_as<PHRoundState>(GetNativeCell(1));
	switch (iStateToSet)
	{
		case Round_Hiding:
		{
			g_iRoundState = 1;
			Call_StartForward(g_hOnHidingStage_Post);
			Call_Finish();
		}
		case Round_Seeking:
		{
			g_iRoundState = 2;
			Call_StartForward(g_hOnSeekingStage_Post);
			Call_Finish();
		}
		case Round_Over:
		{
			g_iRoundState = 3;
			Call_StartForward(g_hOnEndStage_Post);
			Call_Finish();
		}
	}
	return 0;
}