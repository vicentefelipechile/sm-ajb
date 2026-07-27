// =========================================================================================================
// Round state machine + TF2 round events
// =========================================================================================================

// How many times we've re-deferred the first-round freeday waiting for the engine to exit preround.
// Reset at round start; caps out at AJB_FREEDAY_ARENA_MAX_RETRIES to avoid infinite deferral.
static int g_iFreedayArenaRetries;
#define AJB_FREEDAY_ARENA_MAX_RETRIES 30   // 30 × 0.5s = 15s ceiling

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

// End the round for `team` (TF2: 2=RED, 3=BLU). Uses game_round_win so the engine
// fires teamplay_round_win / scoreboard / nextround — not chat-only.
void AJB_ForceTeamWin(int team)
{
	if (!g_bModeActive)
	{
		return;
	}

	if (g_RoundState == AJBState_RoundEnd || g_RoundState == AJBState_Disabled || g_RoundState == AJBState_Waiting)
	{
		return;
	}

	if (team != 2 && team != 3)
	{
		return;
	}

	// Mark AJB phase early; Event_RoundWin will clean runtime when the engine fires.
	AJB_SetRoundState(AJBState_RoundEnd);
	AJB_KillRoundExpireTimer();

	int ent = CreateEntityByName("game_round_win");
	if (ent == -1 || !IsValidEntity(ent))
	{
		LogMessage("[AJB] CreateEntityByName(game_round_win) failed (team=%d).", team);
		return;
	}

	DispatchSpawn(ent);

	// Winning team.
	if (HasEntProp(ent, Prop_Data, "m_iTeamNum"))
	{
		SetEntProp(ent, Prop_Data, "m_iTeamNum", team);
	}

	// Jail maps need entity regen (doors/logic) between rounds.
	if (HasEntProp(ent, Prop_Data, "m_bForceMapReset"))
	{
		SetEntProp(ent, Prop_Data, "m_bForceMapReset", 1);
	}

	AcceptEntityInput(ent, "RoundWin");

	// One-shot entity — drop it next frame.
	CreateTimer(0.1, Timer_RemoveEntity, EntIndexToEntRef(ent), TIMER_FLAG_NO_MAPCHANGE);

	LogMessage("[AJB] ForceTeamWin team=%d via game_round_win.", team);
}

Action Timer_RemoveEntity(Handle timer, int ref)
{
	int ent = EntRefToEntIndex(ref);
	if (ent != -1 && IsValidEntity(ent))
	{
		AcceptEntityInput(ent, "Kill");
	}
	return Plugin_Stop;
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
	AJB_Freekill_Reset();
	g_bLastPrisonerAnnounced = false;
	g_bRebelOnHit = true;
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
	AJB_FlagSet(client, AJB_PF_REBEL, false);
	AJB_FlagSet(client, AJB_PF_FREEDAY, false);
	g_fGuardMarkRebelLastTime[client] = 0.0;
}

void AJB_ApplyPendingFreedays()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!AJB_FlagGet(i, AJB_PF_FREEDAY_PENDING))
		{
			continue;
		}

		AJB_FlagSet(i, AJB_PF_FREEDAY_PENDING, false);

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

	// Pre-round is a free-for-all; the JB team ratio locks in now that the round is live.
	AJB_Balance_OnLiveRoundBegin();

	AJB_ScheduleAutoWarden();

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

	g_iWardenRoundSerial++;

	AJB_Teams_ApplyNames();
	AJB_ApplyEngineMovementPolicy();

	AJB_CleanupRoundRuntime();
	AJB_ResetPlayerFlags();
	// Teammate push starts disabled every round; the warden may re-enable it.
	AJB_Collisions_ResetForRound();
	// Friendly fire also starts disabled every round.
	AJB_FF_ResetForRound();
	AJB_LoadMapDoors();
	// Close cells for the new round (does not force engine map regen).
	AJB_ResetCellsForRound();

	AJB_SetRoundState(AJBState_CellsLocked);

	// First round of each map: automatic freedsay for all (5 min, no warden, cells open).
	// Deferred off teamplay_round_start — opening cells / firing map button+relay I/O inside
	// the round-start event has segfaulted on dense JB maps (e.g. jb_snowday_v9).
	// On arena maps, Timer_FirstRoundFreeday further defers until the engine exits
	// GR_STATE_PREROUND (logic_relay Trigger during preround crashes arena infra).
	if (g_iWardenRoundSerial == 1)
	{
		g_iFreedayArenaRetries = 0;
		CreateTimer(0.35, Timer_FirstRoundFreeday, _, TIMER_FLAG_NO_MAPCHANGE);
		return;
	}

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

	AJB_ChatAll("Prepare");
}

void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bModeActive)
	{
		return;
	}

	int team = event.GetInt("team");

	if (g_iWarden != 0)
	{
		AJB_ClearWarden(true);
	}

	AJB_CleanupRoundRuntime();
	AJB_SetRoundState(AJBState_RoundEnd);
	AJB_FireRoundWin(team);
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
	if (event.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER)
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
		AJB_FlagSet(victim, AJB_PF_REBEL, false);
	}

	// Eternal Reward (YER / Wanga Prick) automatic disguise logic for RED spies killing BLUs
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (AJB_IsValidClient(attacker) && AJB_IsValidClient(victim) && attacker != victim)
	{
		if (GetClientTeam(attacker) == AJB_TEAM_RED && GetClientTeam(victim) == AJB_TEAM_BLU)
		{
			if (TF2_GetPlayerClass(attacker) == TFClass_Spy)
			{
				int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
				if (weapon > MaxClients && IsValidEntity(weapon))
				{
					int defIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
					if (defIndex == 225 || defIndex == 574) // Your Eternal Reward or Wanga Prick
					{
						TF2_DisguisePlayer(attacker, TFTeam_Blue, TF2_GetPlayerClass(victim), victim);
					}
				}
			}
		}
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
		AJB_FlagSet(client, AJB_PF_REBEL, false);
	}

	// Enforce the JB guard ratio: bounce excess guards back to the prisoners.
	AJB_Balance_OnPlayerTeam(client, team);
}

void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bModeActive || (!g_cvRebelOnDamage.BoolValue && !g_cvRebelOnWardenDamage.BoolValue))
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

// First map-round freedsay — runs a beat after teamplay_round_start so entity I/O is safe.
Action Timer_FirstRoundFreeday(Handle timer)
{
	if (!g_bModeActive)
	{
		return Plugin_Stop;
	}

	// Only the first live round of the map should freedsay; a late fire after round end is a no-op.
	if (g_RoundState == AJBState_RoundEnd || g_RoundState == AJBState_Disabled || g_RoundState == AJBState_Waiting)
	{
		return Plugin_Stop;
	}

	// ARENA CRASH FIX: On arena maps, firing Trigger on logic_relay entities while the engine
	// is still in GR_STATE_PREROUND (3) chains into arena round infrastructure that is not
	// fully initialized — segfaulting the server on maps like jb_snowday_v9. Re-schedule
	// until the engine transitions to GR_STATE_RND_RUNNING (4) or later.
	if (AJB_IsArenaMap())
	{
		int engState = GameRules_GetProp("m_iRoundState");
		if (engState <= 3 && g_iFreedayArenaRetries < AJB_FREEDAY_ARENA_MAX_RETRIES)
		{
			g_iFreedayArenaRetries++;
			if (g_iFreedayArenaRetries == 1)
			{
				LogMessage("[AJB] First-round freedsay: arena eng_state=%d, deferring until round is active.", engState);
			}
			CreateTimer(0.5, Timer_FirstRoundFreeday, _, TIMER_FLAG_NO_MAPCHANGE);
			return Plugin_Stop;
		}

		if (g_iFreedayArenaRetries >= AJB_FREEDAY_ARENA_MAX_RETRIES)
		{
			LogMessage("[AJB] First-round freedsay: arena retry limit reached (eng_state=%d), proceeding anyway.",
				GameRules_GetProp("m_iRoundState"));
		}
	}

	// Step logs help pinpoint native crashes (SM log is the last line before a segfault).
	LogMessage("[AJB] First-round freedsay: begin (arena=%d, retries=%d).", AJB_IsArenaMap() ? 1 : 0, g_iFreedayArenaRetries);

	AJB_BeginFreedayAllCosmetic();
	LogMessage("[AJB] First-round freedsay: cells/cosmetic done.");

	AJB_NotifyLiveRoundBegin();
	LogMessage("[AJB] First-round freedsay: live-round begin done.");

	// 5-minute window. On arena maps SetPhaseTimer is a no-op for the entity HUD;
	// the SM expire timer still ends the round.
	AJB_SetPhaseTimer(300.0);
	AJB_StartRoundExpireTimer(300.0);
	LogMessage("[AJB] First-round freedsay: timers armed.");

	AJB_ChatAll("First Round Freeday");
	AJB_ChatAll("Prepare");
	LogMessage("[AJB] First-round freedsay: complete.");
	return Plugin_Stop;
}

// Called once the preround ends (AJB_NotifyLiveRoundBegin). If sm_ajb_warden_auto is on and no
// warden is set, schedule the pick after sm_ajb_warden_auto_delay seconds (0 = immediately, a tiny
// deferral so it runs after the live-round state settles).
void AJB_ScheduleAutoWarden()
{
	if (!g_bModeActive || !g_cvWardenAuto.BoolValue || g_iWarden != 0)
	{
		return;
	}

	float delay = g_cvWardenAutoDelay.FloatValue;
	if (delay < 0.1)
	{
		delay = 0.1;
	}

	CreateTimer(delay, Timer_AutoWarden, _, TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_AutoWarden(Handle timer)
{
	if (!g_bModeActive || g_iWarden != 0 || !AJB_CanClaimWarden())
	{
		return Plugin_Stop;
	}

	int team = AJB_GetGuardsTeam();
	int pick = g_cvWardenAutoMode.BoolValue
		? AJB_PickWeightedWardenGuard(team)
		: AJB_PickRandomAliveOnTeam(team);
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
