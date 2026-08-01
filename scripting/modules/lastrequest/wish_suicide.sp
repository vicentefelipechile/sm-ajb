// =========================================================================================================
// Last Request - Suicide
// =========================================================================================================

// Instant wish: chosen now -> countdown -> die. Does not change the rest of the round.
void AJB_LR_DoSuicide(int prisoner)
{
	// End LR menu state immediately (wish already chosen).
	AJB_LR_KillMenuTimer();
	g_bMenuOpen = false;
	g_bAwaitingCustom = false;
	g_iPrisoner = 0;
	AJB_LR_MarkWishChosen();

	AJB_LR_ChatAll1N("LR Chose Suicide", prisoner);

	float delay = g_cvSuicideDelay.FloatValue;
	if (delay < 1.0)
	{
		delay = LR_SUICIDE_DELAY;
	}

	int left = RoundToFloor(delay);
	if (left < 1)
	{
		left = 1;
	}

	AJB_LR_KillSuicideTimer();
	// Store remaining seconds in timer data via userid pack: use repeating 1s countdown.
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(prisoner));
	pack.WriteCell(left);
	g_hSuicideTimer = CreateTimer(1.0, Timer_SuicideCountdown, pack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);

	if (prisoner > 0 && IsClientInGame(prisoner))
	{
		PrintCenterText(prisoner, "%t", "LR Suicide Countdown", left);
	}
}

Action Timer_SuicideCountdown(Handle timer, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	int left = pack.ReadCell();

	int client = GetClientOfUserId(userid);
	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		g_hSuicideTimer = null;
		return Plugin_Stop;
	}

	left--;
	if (left <= 0)
	{
		g_hSuicideTimer = null;
		ForcePlayerSuicide(client);
		return Plugin_Stop;
	}

	// Rewrite pack for next tick (DataPack position after Read is at end; rewrite cells).
	pack.Reset();
	pack.WriteCell(userid);
	pack.WriteCell(left);

	PrintCenterText(client, "%t", "LR Suicide Countdown", left);
	return Plugin_Continue;
}

void AJB_LR_KillSuicideTimer()
{
	if (g_hSuicideTimer != null)
	{
		delete g_hSuicideTimer;
		g_hSuicideTimer = null;
	}
}

