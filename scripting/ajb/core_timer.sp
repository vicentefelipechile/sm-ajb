// =========================================================================================================
// Phase countdown via team_round_timer (stock TF2 HUD) when possible
// =========================================================================================================

void AJB_SetPhaseTimer(float seconds)
{
	if (seconds <= 0.0)
	{
		AJB_ClearPhaseTimer();
		return;
	}

	int timer = AJB_FindPrimaryRoundTimer();
	if (timer == -1)
	{
		// No map timer — do not invent a permanent custom HUD clock for MVP.
		// Auto-open still runs on CreateTimer from core_rounds.
		LogMessage("[AJB] No team_round_timer found; phase time %.1fs will not show on stock HUD.", seconds);
		return;
	}

	// Resume + set remaining so the native HUD shows the countdown.
	SetVariantInt(1);
	AcceptEntityInput(timer, "ShowInHUD");

	SetVariantFloat(seconds);
	AcceptEntityInput(timer, "SetTime");

	AcceptEntityInput(timer, "Resume");
	AcceptEntityInput(timer, "Enable");
}

void AJB_ClearPhaseTimer()
{
	// Do not Disable map timers globally (jb maps may need them for doors/setup).
	// Pause only if we had forced a short phase countdown — best-effort pause.
	int timer = AJB_FindPrimaryRoundTimer();
	if (timer == -1)
	{
		return;
	}

	// Leaving the map timer alone after open is safer than killing it.
	// Pause is intentionally soft; maps that own the timer keep control after cells open.
}

int AJB_FindPrimaryRoundTimer()
{
	int ent = -1;
	int first = -1;

	while ((ent = FindEntityByClassname(ent, "team_round_timer")) != -1)
	{
		if (first == -1)
		{
			first = ent;
		}

		// Prefer timers that are already shown in HUD.
		if (HasEntProp(ent, Prop_Send, "m_bShowInHUD") && GetEntProp(ent, Prop_Send, "m_bShowInHUD") != 0)
		{
			return ent;
		}
	}

	return first;
}
