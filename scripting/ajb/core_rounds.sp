// =========================================================================================================
// Round state machine + TF2 round events
// AJB does NOT force engine wins, map resets, or mp_restart* — only reacts to stock round events.
// =========================================================================================================

void AJB_SetRoundState(AJBRoundState newState)
{
	if (g_RoundState == newState)
	{
		return;
	}

	AJBRoundState oldState = g_RoundState;
	g_RoundState = newState;

	Call_StartForward(g_hFwdRoundState);
	Call_PushCell(oldState);
	Call_PushCell(newState);
	Call_Finish();
}

// Stop AJB runtime that must not leak into the next round (warden, prep, clocks).
void AJB_CleanupRoundRuntime()
{
	AJB_Prep_Stop();
	AJB_KillCellsAutoTimer();
	AJB_KillRoundExpireTimer();
	AJB_KillApplyTimer();
	AJB_DestroyPluginRoundTimer();
	AJB_ClearWarden(false);
	AJB_Settings_ClearRoundModes();
	g_bLastPrisonerAnnounced = false;
}

void AJB_ResetPlayerFlags()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		AJB_ResetClientFlags(i);
	}
}

void AJB_ResetClientFlags(int client)
{
	g_bRebel[client] = false;
	g_bFreeday[client] = false;
}

void AJB_ApplyPendingFreedays()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bFreedayPending[i])
		{
			continue;
		}

		g_bFreedayPending[i] = false;

		if (!IsClientInGame(i))
		{
			continue;
		}

		AJB_ApplyFreedayNow(i, true);

		if (!IsFakeClient(i))
		{
			char prefix[32];
			AJB_GetPrefix(i, prefix, sizeof(prefix));
			CPrintToChat(i, "%T", "Freeday Active Now", i, prefix);
		}
	}
}

// Called once when the live round begins (after prep, or immediately if prep is off).
// Do not call during preround/prep.
void AJB_NotifyLiveRoundBegin()
{
	if (!g_bModeActive)
	{
		return;
	}

	AJB_ApplyPendingFreedays();

	if (g_hFwdLiveRoundBegin != null)
	{
		Call_StartForward(g_hFwdLiveRoundBegin);
		Call_Finish();
	}
}

void Event_WaitingBegins(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bModeActive)
	{
		return;
	}

	AJB_SetRoundState(AJBState_Waiting);
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bModeActive)
	{
		return;
	}

	LogMessage("[AJB] teamplay_round_start eng_state=%d.", GameRules_GetProp("m_iRoundState"));

	AJB_ApplyEngineMovementPolicy();

	AJB_CleanupRoundRuntime();
	AJB_ResetPlayerFlags();
	// Personal freedays from LR are applied on live-round begin (after prep), not in preround.
	AJB_LoadMapDoors();
	// Close cells for the new round (does not force engine map regen).
	AJB_ResetCellsForRound();

	AJB_SetRoundState(AJBState_CellsLocked);

	float prep = g_cvPrepTime.FloatValue;
	float autoOpen = g_cvCellsAutoOpen.FloatValue;

	if (prep > 0.0)
	{
		AJB_Prep_Start();

		if (autoOpen > 0.0)
		{
			AJB_StartCellsAutoTimer(prep + autoOpen);
		}
		// Live-round begin (wishes / freedays) waits until Timer_PrepEnd.
	}
	else
	{
		AJB_StartRoundClock();

		if (autoOpen > 0.0)
		{
			AJB_StartCellsAutoTimer(autoOpen);
		}

		// No prep → round is live immediately.
		AJB_NotifyLiveRoundBegin();
	}

	// Auto-warden only after prep (same gate as !w claim).
	if (g_cvWardenAuto.BoolValue)
	{
		float delay = (prep > 0.0) ? (prep + 0.25) : 1.0;
		CreateTimer(delay, Timer_AutoWarden, _, TIMER_FLAG_NO_MAPCHANGE);
	}

	AJB_ChatAll("Prepare");
}

void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bModeActive)
	{
		return;
	}

	if (g_iWarden != 0)
	{
		AJB_ClearWarden(true);
	}

	AJB_CleanupRoundRuntime();
	AJB_SetRoundState(AJBState_RoundEnd);
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bModeActive)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!AJB_IsValidClient(client))
	{
		return;
	}

	if (g_cvStripPrisoners.BoolValue && AJB_ClientIsPrisoner(client))
	{
		CreateTimer(0.1, Timer_StripPrisoner, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}

	AJB_Prep_OnPlayerSpawn(client);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bModeActive)
	{
		return;
	}

	// Dead Ringer / feign death fires player_death but the spy is not really dead.
	if (event.GetInt("deathflags") & TF_DEATHFLAG_DEADRINGER)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim == g_iWarden)
	{
		AJB_ClearWarden(true);
	}

	if (AJB_IsValidClient(victim))
	{
		g_bRebel[victim] = false;
	}

	// Last-prisoner announce only (no forced round end).
	CreateTimer(0.15, Timer_PostDeathChecks, _, TIMER_FLAG_NO_MAPCHANGE);
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bModeActive)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!AJB_IsValidClient(client))
	{
		return;
	}

	int team = event.GetInt("team");
	int oldTeam = event.GetInt("oldteam");

	if (client == g_iWarden && team != AJB_GetGuardsTeam())
	{
		AJB_ClearWarden(true);
	}

	// Only clear rebel on a real team switch (not re-fires with the same team).
	if (team != oldTeam)
	{
		g_bRebel[client] = false;
	}
}

void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bModeActive || !g_cvRebelOnDamage.BoolValue)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (victim < 1 || attacker < 1)
	{
		return;
	}

	AJB_TryRebelFromAttack(attacker, victim);
}

Action Timer_PostDeathChecks(Handle timer)
{
	if (!g_bModeActive)
	{
		return Plugin_Stop;
	}

	AJB_CheckLastPrisoner();
	return Plugin_Stop;
}

Action Timer_AutoWarden(Handle timer)
{
	if (!g_bModeActive || g_iWarden != 0 || !AJB_CanClaimWarden())
	{
		return Plugin_Stop;
	}

	int pick = AJB_PickRandomAliveOnTeam(AJB_GetGuardsTeam());
	if (pick != 0)
	{
		AJB_SetWarden(pick, true);
	}
	return Plugin_Stop;
}

void AJB_StartCellsAutoTimer(float seconds)
{
	AJB_KillCellsAutoTimer();
	if (seconds <= 0.0)
	{
		return;
	}

	g_hCellsAutoTimer = CreateTimer(seconds, Timer_CellsAutoOpen, _, TIMER_FLAG_NO_MAPCHANGE);
}

void AJB_KillCellsAutoTimer()
{
	if (g_hCellsAutoTimer != null)
	{
		delete g_hCellsAutoTimer;
		g_hCellsAutoTimer = null;
	}
}

Action Timer_CellsAutoOpen(Handle timer)
{
	g_hCellsAutoTimer = null;
	if (!g_bModeActive)
	{
		return Plugin_Stop;
	}

	AJB_OpenCellsInternal(true);
	return Plugin_Stop;
}
