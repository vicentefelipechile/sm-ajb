// =========================================================================================================
// Pre-round preparation window
// BLU (guards) can move; RED (prisoners) stay locked in place for sm_ajb_prep_time seconds.
// =========================================================================================================

bool g_bPrepActive;
Handle g_hPrepEndTimer;
Handle g_hPrepTickTimer;

void AJB_Prep_Start()
{
	AJB_Prep_Stop(false);

	float prep = g_cvPrepTime.FloatValue;
	if (prep <= 0.0 || !g_bModeActive)
	{
		return;
	}

	g_bPrepActive = true;

	// Prefer stock TF2 timer HUD for the countdown.
	AJB_SetPhaseTimer(prep);

	// Apply immediately, then reassert (maps/engine may re-freeze or release players).
	AJB_Prep_ApplyAll();
	g_hPrepTickTimer = CreateTimer(0.5, Timer_PrepTick, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	g_hPrepEndTimer = CreateTimer(prep, Timer_PrepEnd, _, TIMER_FLAG_NO_MAPCHANGE);

	int seconds = RoundToNearest(prep);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		PrintToChat(i, "%T", "Prep Started", i, prefix, seconds);
	}
}

void AJB_Prep_Stop(bool announce)
{
	bool was = g_bPrepActive;
	g_bPrepActive = false;

	if (g_hPrepEndTimer != null)
	{
		delete g_hPrepEndTimer;
		g_hPrepEndTimer = null;
	}

	if (g_hPrepTickTimer != null)
	{
		delete g_hPrepTickTimer;
		g_hPrepTickTimer = null;
	}

	if (was)
	{
		// Release prisoners from prep freeze (cells still hold them if closed).
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || !IsPlayerAlive(i))
			{
				continue;
			}

			if (AJB_ClientIsPrisoner(i))
			{
				AJB_Prep_SetMovable(i, true);
			}
		}

		if (announce)
		{
			AJB_ChatAll("Prep Ended");
		}
	}
}

bool AJB_IsPrepActive()
{
	return g_bPrepActive;
}

Action Timer_PrepTick(Handle timer)
{
	if (!g_bPrepActive || !g_bModeActive)
	{
		g_hPrepTickTimer = null;
		return Plugin_Stop;
	}

	AJB_Prep_ApplyAll();
	return Plugin_Continue;
}

Action Timer_PrepEnd(Handle timer)
{
	g_hPrepEndTimer = null;
	AJB_Prep_Stop(true);
	return Plugin_Stop;
}

void AJB_Prep_ApplyAll()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		if (AJB_ClientIsGuard(i))
		{
			// Guards must be free to leave spawn, claim warden, stage.
			AJB_Prep_SetMovable(i, true);
		}
		else if (AJB_ClientIsPrisoner(i))
		{
			// Prisoners stay put for the prep window (cells + freeze).
			AJB_Prep_SetMovable(i, false);
		}
	}
}

void AJB_Prep_OnPlayerSpawn(int client)
{
	if (!g_bPrepActive || !g_bModeActive)
	{
		return;
	}

	// Defer one tick so TF2 spawn settles movetype.
	CreateTimer(0.05, Timer_PrepSpawn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_PrepSpawn(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!g_bPrepActive || !AJB_IsValidClient(client, true))
	{
		return Plugin_Stop;
	}

	if (AJB_ClientIsGuard(client))
	{
		AJB_Prep_SetMovable(client, true);
	}
	else if (AJB_ClientIsPrisoner(client))
	{
		AJB_Prep_SetMovable(client, false);
	}

	return Plugin_Stop;
}

void AJB_Prep_SetMovable(int client, bool movable)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	if (movable)
	{
		SetEntityMoveType(client, MOVETYPE_WALK);

		// Clear common TF2 lock conditions that setup/stuns apply.
		if (TF2_IsPlayerInCondition(client, TFCond_Dazed))
		{
			TF2_RemoveCondition(client, TFCond_Dazed);
		}
		if (TF2_IsPlayerInCondition(client, TFCond_FreezeInput))
		{
			TF2_RemoveCondition(client, TFCond_FreezeInput);
		}
	}
	else
	{
		SetEntityMoveType(client, MOVETYPE_NONE);
	}
}
