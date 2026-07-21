// =========================================================================================================
// team_round_timer — stock TF2 HUD clock for prep + remaining round time
// jb maps often ship with none; create/reuse one AFTER teamplay_round_start (engine wipes earlier ones).
// =========================================================================================================

#define AJB_TIMER_NAME "ajb_round_timer"

static int g_iRoundTimerRef = INVALID_ENT_REFERENCE;
static Handle g_hTimerApply;

void AJB_Timer_OnMapStart()
{
	g_iRoundTimerRef = INVALID_ENT_REFERENCE;
	AJB_KillApplyTimer();
}

void AJB_KillApplyTimer()
{
	if (g_hTimerApply != null)
	{
		delete g_hTimerApply;
		g_hTimerApply = null;
	}
}

// Queue a HUD clock update. Delay is required: TF2 removes team_round_timer entities
// created before/at the exact start of teamplay_round_start.
void AJB_SetPhaseTimer(float seconds)
{
	if (seconds <= 0.0)
	{
		return;
	}

	AJB_KillApplyTimer();
	g_hTimerApply = CreateTimer(0.15, Timer_ApplyPhaseTimer, seconds, TIMER_FLAG_NO_MAPCHANGE);
}

// After prep (or immediately if prep is off): show the main jail round clock.
void AJB_StartRoundClock()
{
	float seconds = g_cvRoundTime.FloatValue;
	if (seconds <= 0.0)
	{
		AJB_KillApplyTimer();
		g_hTimerApply = CreateTimer(0.15, Timer_UnhideOnly, _, TIMER_FLAG_NO_MAPCHANGE);
		return;
	}

	AJB_SetPhaseTimer(seconds);
}

void AJB_ClearPhaseTimer()
{
	// Do not hide/disable the HUD clock — cells/prep end must leave the round timer visible.
	AJB_KillApplyTimer();
}

Action Timer_ApplyPhaseTimer(Handle timer, float seconds)
{
	g_hTimerApply = null;

	if (seconds <= 0.0 || !g_bModeActive)
	{
		return Plugin_Stop;
	}

	int ent = AJB_EnsureRoundTimer();
	if (ent == -1)
	{
		// One retry — entity budget/race can fail on the first attempt after map load.
		CreateTimer(0.5, Timer_RetryPhaseTimer, seconds, TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Stop;
	}

	AJB_ConfigureAndStartTimer(ent, seconds);
	return Plugin_Stop;
}

Action Timer_RetryPhaseTimer(Handle timer, float seconds)
{
	if (seconds <= 0.0 || !g_bModeActive)
	{
		return Plugin_Stop;
	}

	int ent = AJB_EnsureRoundTimer();
	if (ent == -1)
	{
		LogMessage("[AJB] Could not create team_round_timer after retry (HUD clock unavailable).");
		return Plugin_Stop;
	}

	AJB_ConfigureAndStartTimer(ent, seconds);
	return Plugin_Stop;
}

Action Timer_UnhideOnly(Handle timer)
{
	g_hTimerApply = null;

	int ent = AJB_EnsureRoundTimer();
	if (ent == -1)
	{
		return Plugin_Stop;
	}

	AJB_ShowRoundTimer(ent);
	AcceptEntityInput(ent, "Resume");
	return Plugin_Stop;
}

void AJB_ConfigureAndStartTimer(int timerEnt, float seconds)
{
	if (timerEnt == -1 || !IsValidEntity(timerEnt))
	{
		return;
	}

	// Only one timer may own the HUD; hide siblings first.
	AJB_HideOtherRoundTimers(timerEnt);
	AJB_ShowRoundTimer(timerEnt);

	// Order used by working TF2 plugins: Enable → ShowInHUD → SetTime → Resume.
	AcceptEntityInput(timerEnt, "Enable");

	SetVariantInt(1);
	AcceptEntityInput(timerEnt, "ShowInHUD");

	// Clear setup phase so the client draws the normal round clock (not setup bar).
	if (HasEntProp(timerEnt, Prop_Send, "m_nSetupTimeLength"))
	{
		SetEntProp(timerEnt, Prop_Send, "m_nSetupTimeLength", 0);
	}
	if (HasEntProp(timerEnt, Prop_Send, "m_bInSetup"))
	{
		SetEntProp(timerEnt, Prop_Send, "m_bInSetup", 0);
	}

	int secs = RoundToFloor(seconds);
	if (secs < 1)
	{
		secs = 1;
	}

	if (HasEntProp(timerEnt, Prop_Send, "m_nTimerMaxLength"))
	{
		SetEntProp(timerEnt, Prop_Send, "m_nTimerMaxLength", secs);
	}
	if (HasEntProp(timerEnt, Prop_Send, "m_nTimerLength"))
	{
		SetEntProp(timerEnt, Prop_Send, "m_nTimerLength", secs);
	}

	SetVariantFloat(float(secs));
	AcceptEntityInput(timerEnt, "SetTime");

	SetVariantInt(1);
	AcceptEntityInput(timerEnt, "AutoCountdown");

	AcceptEntityInput(timerEnt, "Resume");

	// Netprops as belt-and-suspenders after inputs (some maps fight SetTime alone).
	if (HasEntProp(timerEnt, Prop_Send, "m_flTimeRemaining"))
	{
		SetEntPropFloat(timerEnt, Prop_Send, "m_flTimeRemaining", float(secs));
	}
	if (HasEntProp(timerEnt, Prop_Send, "m_bTimerPaused"))
	{
		SetEntProp(timerEnt, Prop_Send, "m_bTimerPaused", 0);
	}
	if (HasEntProp(timerEnt, Prop_Send, "m_bIsDisabled"))
	{
		SetEntProp(timerEnt, Prop_Send, "m_bIsDisabled", 0);
	}
	if (HasEntProp(timerEnt, Prop_Send, "m_bShowInHUD"))
	{
		SetEntProp(timerEnt, Prop_Send, "m_bShowInHUD", 1);
	}

	g_iRoundTimerRef = EntIndexToEntRef(timerEnt);
	LogMessage("[AJB] Round HUD timer ready (ent=%d, %ds).", timerEnt, secs);
}

void AJB_ShowRoundTimer(int timerEnt)
{
	if (timerEnt == -1 || !IsValidEntity(timerEnt))
	{
		return;
	}

	if (HasEntProp(timerEnt, Prop_Send, "m_bIsDisabled"))
	{
		SetEntProp(timerEnt, Prop_Send, "m_bIsDisabled", 0);
	}
	if (HasEntProp(timerEnt, Prop_Send, "m_bShowInHUD"))
	{
		SetEntProp(timerEnt, Prop_Send, "m_bShowInHUD", 1);
	}
	if (HasEntProp(timerEnt, Prop_Send, "m_bAutoCountdown"))
	{
		SetEntProp(timerEnt, Prop_Send, "m_bAutoCountdown", 1);
	}

	AcceptEntityInput(timerEnt, "Enable");
	SetVariantInt(1);
	AcceptEntityInput(timerEnt, "ShowInHUD");
}

void AJB_HideOtherRoundTimers(int keep)
{
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "team_round_timer")) != -1)
	{
		if (ent == keep || !IsValidEntity(ent))
		{
			continue;
		}

		if (HasEntProp(ent, Prop_Send, "m_bShowInHUD"))
		{
			SetEntProp(ent, Prop_Send, "m_bShowInHUD", 0);
		}

		SetVariantInt(0);
		AcceptEntityInput(ent, "ShowInHUD");
	}
}

int AJB_EnsureRoundTimer()
{
	// Prefer our cached ref if still valid.
	if (g_iRoundTimerRef != INVALID_ENT_REFERENCE)
	{
		int cached = EntRefToEntIndex(g_iRoundTimerRef);
		if (cached != -1 && IsValidEntity(cached))
		{
			return cached;
		}
		g_iRoundTimerRef = INVALID_ENT_REFERENCE;
	}

	int timerEnt = AJB_FindPrimaryRoundTimer();
	if (timerEnt != -1)
	{
		g_iRoundTimerRef = EntIndexToEntRef(timerEnt);
		return timerEnt;
	}

	// Many jb maps ship without a usable HUD timer — create one after round start.
	timerEnt = CreateEntityByName("team_round_timer");
	if (timerEnt == -1 || !IsValidEntity(timerEnt))
	{
		LogMessage("[AJB] CreateEntityByName(team_round_timer) failed.");
		return -1;
	}

	DispatchKeyValue(timerEnt, "targetname", AJB_TIMER_NAME);
	DispatchKeyValue(timerEnt, "show_in_hud", "1");
	DispatchKeyValue(timerEnt, "auto_countdown", "1");
	DispatchKeyValue(timerEnt, "start_paused", "0");
	DispatchKeyValue(timerEnt, "timer_length", "600");
	DispatchKeyValue(timerEnt, "max_length", "0");
	DispatchKeyValue(timerEnt, "setup_length", "0");
	DispatchKeyValue(timerEnt, "reset_time", "1");
	DispatchKeyValue(timerEnt, "origin", "0 0 0");

	if (!DispatchSpawn(timerEnt))
	{
		LogMessage("[AJB] DispatchSpawn(team_round_timer) failed.");
		AcceptEntityInput(timerEnt, "Kill");
		return -1;
	}

	ActivateEntity(timerEnt);
	g_iRoundTimerRef = EntIndexToEntRef(timerEnt);
	LogMessage("[AJB] Created team_round_timer ent=%d.", timerEnt);
	return timerEnt;
}

int AJB_FindPrimaryRoundTimer()
{
	int ent = -1;
	int first = -1;
	int named = -1;

	while ((ent = FindEntityByClassname(ent, "team_round_timer")) != -1)
	{
		if (!IsValidEntity(ent))
		{
			continue;
		}

		if (first == -1)
		{
			first = ent;
		}

		char name[64];
		if (HasEntProp(ent, Prop_Data, "m_iName"))
		{
			GetEntPropString(ent, Prop_Data, "m_iName", name, sizeof(name));
			if (StrEqual(name, AJB_TIMER_NAME, false))
			{
				named = ent;
			}
		}
	}

	// Prefer our named entity so we don't fight a dead map timer.
	if (named != -1)
	{
		return named;
	}

	return first;
}
