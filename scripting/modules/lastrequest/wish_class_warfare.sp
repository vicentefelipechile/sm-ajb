// =========================================================================================================
// Last Request - Class Warfare
// =========================================================================================================

void AJB_LR_ClearClassWarfareActive()
{
	g_bClassWarfareActive = false;
	g_ActiveClassRed = TFClass_Unknown;
	g_ActiveClassBlu = TFClass_Unknown;
}

// Two different random classes (Scout..Engineer).
void AJB_LR_PickTeamClasses(TFClassType &redCls, TFClassType &bluCls)
{
	redCls = view_as<TFClassType>(GetRandomInt(view_as<int>(TFClass_Scout), view_as<int>(TFClass_Engineer)));
	do
	{
		bluCls = view_as<TFClassType>(GetRandomInt(view_as<int>(TFClass_Scout), view_as<int>(TFClass_Engineer)));
	}
	while (bluCls == redCls);
}

void AJB_LR_ForceClassWarfareClass(int client)
{
	if (!g_bClassWarfareActive || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	TFClassType want = TFClass_Unknown;
	if (g_bHasCore && AJB_IsPrisoner(client))
	{
		want = g_ActiveClassRed;
	}
	else if (g_bHasCore && AJB_IsGuard(client))
	{
		want = g_ActiveClassBlu;
	}

	if (want == TFClass_Unknown || TF2_GetPlayerClass(client) == want)
	{
		return;
	}

	TF2_SetPlayerClass(client, want, false, true);
	TF2_RegeneratePlayer(client);
}

// Class Warfare: one random class for RED, another for BLU (never the same).
void AJB_LR_DoClassWarfare(int prisoner)
{
	TFClassType redCls, bluCls;
	AJB_LR_PickTeamClasses(redCls, bluCls);

	AJB_LR_ClearPendingWish();
	g_PendingWish = LRWish_ClassWarfare;
	g_PendingClassRed = redCls;
	g_PendingClassBlu = bluCls;
	AJB_LR_RememberChooser(prisoner);
	// Classes announced when applied next live round.
	AJB_LR_ChatAll1N("LR Chose ClassWarfare", prisoner);
	AJB_LR_CloseMenuState();
	AJB_LR_MarkWishChosen();
}

