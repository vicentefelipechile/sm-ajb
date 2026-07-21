// =========================================================================================================
// Round state machine + TF2 round events
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

// Stop every AJB runtime clock/state that must not leak into the next round.
// Map entity regeneration is handled by game_round_win force_map_reset — not door spam.
void AJB_CleanupRoundRuntime()
{
	AJB_Prep_Stop();
	AJB_KillCellsAutoTimer();
	AJB_KillRoundExpireTimer();
	AJB_KillApplyTimer();
	AJB_KillWinCheckTimer();
	AJB_DestroyPluginRoundTimer();
	AJB_ClearWarden(false);
	g_bLastPrisonerAnnounced = false;
}

void AJB_StartWinCheckTimer()
{
	AJB_KillWinCheckTimer();
	// Periodic wipe detect — death hooks alone can miss multi-frame edge cases.
	g_hWinCheckTimer = CreateTimer(1.0, Timer_WinCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void AJB_KillWinCheckTimer()
{
	if (g_hWinCheckTimer != null)
	{
		delete g_hWinCheckTimer;
		g_hWinCheckTimer = null;
	}
}

Action Timer_WinCheck(Handle timer)
{
	if (!g_bModeActive)
	{
		g_hWinCheckTimer = null;
		return Plugin_Stop;
	}

	if (g_RoundState == AJBState_RoundEnd || g_RoundState == AJBState_Waiting
		|| g_RoundState == AJBState_Disabled)
	{
		return Plugin_Continue;
	}

	AJB_CheckLastPrisoner();
	AJB_CheckWinConditions();
	return Plugin_Continue;
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

		g_bFreeday[i] = true;

		if (!IsFakeClient(i))
		{
			char prefix[32];
			AJB_GetPrefix(i, prefix, sizeof(prefix));
			CPrintToChat(i, "%T", "Freeday Active Now", i, prefix);
		}
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

	LogMessage("[AJB] teamplay_round_start — full round bootstrap (owned_win=%d eng_state=%d).",
		g_bOwnedRoundWin, GameRules_GetProp("m_iRoundState"));

	// Every round: re-assert freeze cvar=0 so clients can predict movement in PREROUND.
	// (Plugin reload / soft win / other plugins can flip it back to 1.)
	AJB_ApplyEngineMovementPolicy();

	// Engine advanced — cancel the "stuck after win" watchdog.
	g_bWaitingForNewRound = false;
	AJB_Watchdog_MarkRoundStart();

	// Fresh round boundary: clear AJB runtime, re-discover doors after map reset.
	AJB_CleanupRoundRuntime();
	AJB_ResetPlayerFlags();
	AJB_ApplyPendingFreedays();
	AJB_LoadMapDoors();

	// force_map_reset (our wins) regenerates the map. Engine soft-wins do not —
	// always snap cells closed so a dirty world cannot carry open cages forward.
	AJB_ResetCellsForRound();

	AJB_SetRoundState(AJBState_CellsLocked);
	g_bOwnedRoundWin = false;

	float prep = g_cvPrepTime.FloatValue;
	float autoOpen = g_cvCellsAutoOpen.FloatValue;

	if (prep > 0.0)
	{
		// HUD shows prep countdown first; main round clock starts when prep ends.
		AJB_Prep_Start();

		if (autoOpen > 0.0)
		{
			AJB_StartCellsAutoTimer(prep + autoOpen);
		}
	}
	else
	{
		// No prep — show the full round clock immediately.
		AJB_StartRoundClock();

		if (autoOpen > 0.0)
		{
			AJB_StartCellsAutoTimer(autoOpen);
		}
	}

	// Natural end of round: detect wipes every second (not only on death events).
	AJB_StartWinCheckTimer();

	if (g_cvWardenAuto.BoolValue)
	{
		CreateTimer(1.0, Timer_AutoWarden, _, TIMER_FLAG_NO_MAPCHANGE);
	}

	// One short line for round start (prep + cells are implied).
	AJB_ChatAll("Prepare");
}

void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bModeActive)
	{
		return;
	}

	// Engine may fire this without force_map_reset (soft win). Our ForceRoundWin
	// already cleaned up and set RoundEnd; still safe to re-run cleanup.
	if (!g_bOwnedRoundWin)
	{
		LogMessage("[AJB] teamplay_round_win without AJB ForceRoundWin — map may not regenerate; snap cells next start.");
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
	// Must not strip warden, clear rebel, or trigger last-prisoner / round-end from it.
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

	// Defer checks so multi-kills in one frame settle.
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

	if (client == g_iWarden && event.GetInt("team") != AJB_GetGuardsTeam())
	{
		AJB_ClearWarden(true);
	}

	g_bRebel[client] = false;
}

Action Timer_PostDeathChecks(Handle timer)
{
	if (!g_bModeActive)
	{
		return Plugin_Stop;
	}

	AJB_CheckLastPrisoner();
	AJB_CheckWinConditions();
	return Plugin_Stop;
}

Action Timer_AutoWarden(Handle timer)
{
	if (!g_bModeActive || g_iWarden != 0)
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
	g_hCellsAutoTimer = CreateTimer(seconds, Timer_AutoOpenCells, _, TIMER_FLAG_NO_MAPCHANGE);
}

void AJB_KillCellsAutoTimer()
{
	if (g_hCellsAutoTimer != null)
	{
		delete g_hCellsAutoTimer;
		g_hCellsAutoTimer = null;
	}
}

Action Timer_AutoOpenCells(Handle timer)
{
	g_hCellsAutoTimer = null;

	if (!g_bModeActive || g_RoundState != AJBState_CellsLocked)
	{
		return Plugin_Stop;
	}

	AJB_OpenCellsInternal(true);
	return Plugin_Stop;
}
