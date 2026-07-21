// =========================================================================================================
// Pre-round preparation window
// BLU (guards) can move; RED (prisoners) stay locked in place for sm_ajb_prep_time seconds.
// =========================================================================================================

bool g_bPrepActive;
Handle g_hPrepEndTimer;
Handle g_hPrepTickTimer;

void AJB_Prep_Start()
{
	AJB_Prep_Stop();

	float prep = g_cvPrepTime.FloatValue;
	if (prep <= 0.0 || !g_bModeActive)
	{
		return;
	}

	g_bPrepActive = true;

	// Freeze cvar must be 0 before BLU clients try to walk (replicated + detour stack).
	AJB_ApplyEngineMovementPolicy();

	AJB_SetPhaseTimer(prep);

	AJB_Prep_ApplyAll();
	g_hPrepTickTimer = CreateTimer(0.5, Timer_PrepTick, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	g_hPrepEndTimer = CreateTimer(prep, Timer_PrepEnd, _, TIMER_FLAG_NO_MAPCHANGE);
}

void AJB_Prep_Stop()
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

	if (!was)
	{
		return;
	}

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
	AJB_Prep_Stop();
	// Prep used the HUD clock for countdown — hand it back to the main round timer.
	AJB_StartRoundClock();
	// Live round: apply queued LR wishes, personal freedays, etc. (not during preround).
	AJB_NotifyLiveRoundBegin();
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
			AJB_Prep_SetMovable(i, true);
		}
		else if (AJB_ClientIsPrisoner(i))
		{
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

	// Never fight admin/debug movement (sm_noclip → MOVETYPE_NOCLIP every prep tick was stripping it).
	MoveType mt = GetEntityMoveType(client);
	if (mt == MOVETYPE_NOCLIP || mt == MOVETYPE_OBSERVER)
	{
		return;
	}

	if (movable)
	{
		// Guards: walk + real maxspeed (engine may have left flMaxspeed at 1.0 from freeze).
		if (mt != MOVETYPE_WALK)
		{
			SetEntityMoveType(client, MOVETYPE_WALK);
		}

		// Push a sane class speed so prediction is not stuck at 1.0 hu/s.
		float speed = GetEntPropFloat(client, Prop_Send, "m_flMaxspeed");
		if (speed < 10.0)
		{
			SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", 300.0);
		}

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
		// Prisoners: networked hard lock (client sees MOVETYPE_NONE even if freeze cvar is 0).
		if (mt != MOVETYPE_NONE)
		{
			SetEntityMoveType(client, MOVETYPE_NONE);
		}
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", 1.0);
	}
}
