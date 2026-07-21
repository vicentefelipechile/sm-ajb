// =========================================================================================================
// Round / timer watchdog
//
// TF2 model (SDK / Valve wiki):
//   - team_round_timer is a HUD entity only. SetTime/Resume paint the clock; it does NOT end the round.
//   - Ending a round requires game rules (game_round_win / SetStalemate / objective).
//   - m_iRoundState on gamerules tracks engine phase (PREROUND, RND_RUNNING, TEAM_WIN, ...).
//
// AJB model:
//   - Prep uses a short HUD clock; then AJB_StartRoundClock() starts HUD + SM expire timer.
//   - Expire timer is authoritative for time-up → ForceRoundWin(guards).
//   - This watchdog detects stuck phases (no RoundStart, no clock, dead timer) and recovers:
//       soft → re-bootstrap clock/cells
//       hard → mp_restartgame
//       full → changelevel same map (full entity reload)
// =========================================================================================================

// Engine gamerules round states (shared/teamplayroundbased_gamerules)
#define AJB_GR_STATE_INIT           0
#define AJB_GR_STATE_PREGAME        1
#define AJB_GR_STATE_STARTGAME      2
#define AJB_GR_STATE_PREROUND       3
#define AJB_GR_STATE_RND_RUNNING    4
#define AJB_GR_STATE_TEAM_WIN       5
#define AJB_GR_STATE_RESTART        6
#define AJB_GR_STATE_STALEMATE      7
#define AJB_GR_STATE_GAME_OVER      8
#define AJB_GR_STATE_BONUS          9
#define AJB_GR_STATE_BETWEEN_RNDS   10

ConVar g_cvWatchdog;
ConVar g_cvWatchdogReloadMap;

Handle g_hWatchdogTimer;

float g_fLastRoundStartTime;
float g_fLastMainClockStartTime;
float g_fWaitingForRoundSince;
float g_fStuckWinSince;
int g_iWatchdogSoftFixes;
int g_iWatchdogHardFixes;

void AJB_Watchdog_OnPluginStart()
{
	g_cvWatchdog = CreateConVar(
		"sm_ajb_watchdog",
		"1",
		"1 = monitor round/timer health and auto-recover stuck states.",
		_, true, 0.0, true, 1.0);

	g_cvWatchdogReloadMap = CreateConVar(
		"sm_ajb_watchdog_reload_map",
		"1",
		"1 = if stuck after soft/hard recovery fails, ForceChangeLevel the current map (full entity reload).",
		_, true, 0.0, true, 1.0);

	g_fLastRoundStartTime = 0.0;
	g_fLastMainClockStartTime = 0.0;
	g_fWaitingForRoundSince = 0.0;
	g_fStuckWinSince = 0.0;
	g_iWatchdogSoftFixes = 0;
	g_iWatchdogHardFixes = 0;
}

void AJB_Watchdog_OnMapStart()
{
	g_fLastRoundStartTime = 0.0;
	g_fLastMainClockStartTime = 0.0;
	g_fWaitingForRoundSince = 0.0;
	g_fStuckWinSince = 0.0;
	g_iWatchdogSoftFixes = 0;
	g_iWatchdogHardFixes = 0;
	AJB_Watchdog_Start();
}

void AJB_Watchdog_OnMapEnd()
{
	AJB_Watchdog_Stop();
}

void AJB_Watchdog_Start()
{
	AJB_Watchdog_Stop();
	if (!g_cvWatchdog.BoolValue)
	{
		return;
	}

	g_hWatchdogTimer = CreateTimer(2.0, Timer_WatchdogTick, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void AJB_Watchdog_Stop()
{
	if (g_hWatchdogTimer != null)
	{
		delete g_hWatchdogTimer;
		g_hWatchdogTimer = null;
	}
}

void AJB_Watchdog_MarkRoundStart()
{
	g_fLastRoundStartTime = GetGameTime();
	g_fLastMainClockStartTime = 0.0;
	g_iWatchdogSoftFixes = 0;
	// Keep hard-fix budget across soft recoveries within the same map session.
}

void AJB_Watchdog_MarkMainClockStart()
{
	g_fLastMainClockStartTime = GetGameTime();
}

int AJB_GetEngineRoundState()
{
	// teamplayroundbased_gamerules: m_iRoundState
	return GameRules_GetProp("m_iRoundState");
}

bool AJB_Watchdog_HasHudTimer()
{
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "team_round_timer")) != -1)
	{
		if (IsValidEntity(ent))
		{
			return true;
		}
	}
	return false;
}

Action Timer_WatchdogTick(Handle timer)
{
	if (!g_cvWatchdog.BoolValue || !g_bModeActive)
	{
		return Plugin_Continue;
	}

	float now = GetGameTime();
	int eng = AJB_GetEngineRoundState();

	// ------------------------------------------------------------------
	// 1) Waiting forever for a new round after we forced a win
	// ------------------------------------------------------------------
	if (g_bWaitingForNewRound)
	{
		if (g_fWaitingForRoundSince <= 0.0)
		{
			g_fWaitingForRoundSince = now;
		}

		if (now - g_fWaitingForRoundSince > 22.0)
		{
			g_fWaitingForRoundSince = 0.0;
			AJB_Watchdog_RecoverFullMap("stuck waiting for teamplay_round_start after win");
			return Plugin_Continue;
		}
	}
	else
	{
		g_fWaitingForRoundSince = 0.0;
	}

	// ------------------------------------------------------------------
	// 2) Engine says ROUND RUNNING but AJB never bootstrapped RoundStart
	// ------------------------------------------------------------------
	if (eng == AJB_GR_STATE_RND_RUNNING)
	{
		if (g_fLastRoundStartTime <= 0.0
			|| ((now - g_fLastRoundStartTime) > 5.0
				&& (g_RoundState == AJBState_Waiting || g_RoundState == AJBState_Disabled
					|| g_RoundState == AJBState_RoundEnd)))
		{
			LogMessage("[AJB-Watchdog] engine RND_RUNNING but AJB not bootstrapped (state=%d) — soft bootstrap.", g_RoundState);
			AJB_Watchdog_RecoverSoftBootstrap();
			return Plugin_Continue;
		}

		float prep = g_cvPrepTime.FloatValue;
		float roundT = g_cvRoundTime.FloatValue;
		float sinceStart = (g_fLastRoundStartTime > 0.0) ? (now - g_fLastRoundStartTime) : 0.0;

		// 3) Main expire timer missing after prep window (or after main clock should have started)
		bool pastPrep = sinceStart > (prep + 2.0)
			|| (g_fLastMainClockStartTime > 0.0 && (now - g_fLastMainClockStartTime) > 1.0);

		if (roundT > 0.0
			&& (g_RoundState == AJBState_CellsLocked || g_RoundState == AJBState_CellsOpen
				|| g_RoundState == AJBState_LastRequest || g_RoundState == AJBState_SpecialDay)
			&& pastPrep
			&& !AJB_IsRoundExpireTimerActive())
		{
			LogMessage("[AJB-Watchdog] main expire timer missing mid-round (state=%d t=%.1f) — restarting clock.",
				g_RoundState, sinceStart);
			AJB_Watchdog_RecoverSoftClock();
			return Plugin_Continue;
		}

		// 4) HUD timer entity vanished mid-round
		if (roundT > 0.0
			&& (g_RoundState == AJBState_CellsLocked || g_RoundState == AJBState_CellsOpen)
			&& sinceStart > (prep + 2.0)
			&& !AJB_Watchdog_HasHudTimer())
		{
			LogMessage("[AJB-Watchdog] no team_round_timer entity mid-round — recreating HUD clock.");
			AJB_Watchdog_RecoverSoftClock();
			return Plugin_Continue;
		}

		// 5) Round ran longer than prep + round_time + grace → expire missed
		if (roundT > 0.0
			&& (g_RoundState == AJBState_CellsLocked || g_RoundState == AJBState_CellsOpen)
			&& sinceStart > (prep + roundT + 15.0))
		{
			LogMessage("[AJB-Watchdog] round overrun (%.0fs > prep+round+15) — forcing guards win.", sinceStart);
			AJB_ForceRoundWin(AJB_GetGuardsTeam());
			return Plugin_Continue;
		}
	}

	// ------------------------------------------------------------------
	// 6) Stuck in TEAM_WIN / BONUS / BETWEEN forever
	// ------------------------------------------------------------------
	if (eng == AJB_GR_STATE_TEAM_WIN || eng == AJB_GR_STATE_BONUS || eng == AJB_GR_STATE_BETWEEN_RNDS
		|| eng == AJB_GR_STATE_RESTART)
	{
		if (g_bWaitingForNewRound || g_RoundState == AJBState_RoundEnd)
		{
			if (g_fStuckWinSince <= 0.0)
			{
				g_fStuckWinSince = now;
			}
			if (now - g_fStuckWinSince > 30.0)
			{
				g_fStuckWinSince = 0.0;
				AJB_Watchdog_RecoverFullMap("engine stuck in win/bonus/between without new round");
			}
		}
		else
		{
			g_fStuckWinSince = 0.0;
		}
	}
	else
	{
		g_fStuckWinSince = 0.0;
	}

	return Plugin_Continue;
}

void AJB_Watchdog_RecoverSoftClock()
{
	g_iWatchdogSoftFixes++;
	if (g_iWatchdogSoftFixes > 3)
	{
		AJB_Watchdog_RecoverHardRestart("too many soft clock fixes");
		return;
	}

	// Re-apply main clock (HUD + expire). Do not end the round.
	if (g_cvRoundTime.FloatValue > 0.0)
	{
		// Remaining estimate: full restart of clock is safer than partial.
		AJB_StartRoundClock();
	}
	else
	{
		AJB_SetPhaseTimer(60.0); // at least show something
	}
}

void AJB_Watchdog_RecoverSoftBootstrap()
{
	g_iWatchdogSoftFixes++;
	if (g_iWatchdogSoftFixes > 2)
	{
		AJB_Watchdog_RecoverHardRestart("bootstrap failed repeatedly");
		return;
	}

	// Synthesize what Event_RoundStart does without waiting for the event.
	LogMessage("[AJB-Watchdog] synthesizing RoundStart bootstrap.");
	g_bWaitingForNewRound = false;
	AJB_CleanupRoundRuntime();
	AJB_ResetPlayerFlags();
	AJB_LoadMapDoors();
	AJB_ResetCellsForRound();
	AJB_SetRoundState(AJBState_CellsLocked);
	g_bOwnedRoundWin = false;
	AJB_Watchdog_MarkRoundStart();

	float prep = g_cvPrepTime.FloatValue;
	if (prep > 0.0)
	{
		AJB_Prep_Start();
	}
	else
	{
		AJB_StartRoundClock();
	}
	AJB_StartWinCheckTimer();
	AJB_ChatAll("Prepare");
}

void AJB_Watchdog_RecoverHardRestart(const char[] reason)
{
	g_iWatchdogHardFixes++;
	LogMessage("[AJB-Watchdog] HARD recovery (mp_restartgame 1): %s", reason);
	g_bWaitingForNewRound = true;
	ServerCommand("mp_restartgame 1");

	if (g_iWatchdogHardFixes >= 2 && g_cvWatchdogReloadMap.BoolValue)
	{
		// Next tick after restartgame may still fail — schedule full map reload.
		CreateTimer(8.0, Timer_WatchdogMaybeReloadMap, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action Timer_WatchdogMaybeReloadMap(Handle timer)
{
	if (!g_bModeActive || !g_cvWatchdogReloadMap.BoolValue)
	{
		return Plugin_Stop;
	}

	// If we still have not had a fresh RoundStart since hard restarts, reload the map.
	if (g_fLastRoundStartTime <= 0.0 || (GetGameTime() - g_fLastRoundStartTime) > 60.0)
	{
		AJB_Watchdog_RecoverFullMap("hard restart did not produce a healthy RoundStart");
	}
	return Plugin_Stop;
}

void AJB_Watchdog_RecoverFullMap(const char[] reason)
{
	if (!g_cvWatchdogReloadMap.BoolValue)
	{
		LogMessage("[AJB-Watchdog] FULL map reload requested but sm_ajb_watchdog_reload_map=0: %s", reason);
		ServerCommand("mp_restartgame 1");
		return;
	}

	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	LogMessage("[AJB-Watchdog] FULL map reload (changelevel %s): %s", map, reason);

	// ForceChangeLevel is the cleanest full entity/world reload for the same map.
	ForceChangeLevel(map, "AJB watchdog: stuck round/timer recovery");
}
