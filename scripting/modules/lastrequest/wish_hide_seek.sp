// =========================================================================================================
// Last Request - Hide and Seek
// =========================================================================================================

void AJB_LR_DoHideSeek(int prisoner)
{
	// NEXT round Hide and Seek.
	AJB_LR_QueueWish(prisoner, LRWish_HideSeek, "LR Chose HideSeek");
}

// =========================================================================================================
// Hide and Seek
// =========================================================================================================

// Applied at live-round begin (after prep): gather + freeze BLU seekers at the first
// spawn, open cells so RED can run and hide, then run the hide window and 5-min clock.
void AJB_LR_ApplyHideSeek(const char[] chooser)
{
	g_bHideSeek = true;

	// Doors open so hiders can run.
	AJB_OpenCells();

	if (g_bHasCore)
	{
		AJB_SetRoundState(AJBState_SpecialDay);
		AJB_ClearWarden();
	}

	// First spawn point for the guards' team - all seekers stack on it (expected).
	int spawn = AJB_LR_FindGuardSpawn();
	float origin[3];
	float angles[3];
	bool haveSpawn = (spawn != -1);
	if (haveSpawn)
	{
		GetEntPropVector(spawn, Prop_Data, "m_vecOrigin", origin);
		GetEntPropVector(spawn, Prop_Data, "m_angRotation", angles);
	}

	float noVel[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || !AJB_IsGuard(i))
		{
			continue;
		}

		if (haveSpawn)
		{
			TeleportEntity(i, origin, angles, noVel);
		}
		AJB_LR_SetSeekerFrozen(i, true);
	}

	// 5-minute HUD clock + authoritative end (hiders win if time runs out).
	float roundTime = g_cvHSRoundTime.FloatValue;
	AJB_SetPhaseTimer(roundTime);

	AJB_LR_KillHSTimers();
	g_hHSEndTimer = CreateTimer(roundTime, Timer_HSEnd, _, TIMER_FLAG_NO_MAPCHANGE);
	g_hHSHideTimer = CreateTimer(g_cvHSHideTime.FloatValue, Timer_HSRelease, _, TIMER_FLAG_NO_MAPCHANGE);

	AJB_LR_ChatAllQueuedApplied(chooser, "LR Applied HideSeek");
}

// Freeze/unfreeze a seeker in place (networked hard lock, like the core prep freeze).
void AJB_LR_SetSeekerFrozen(int client, bool frozen)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	MoveType mt = GetEntityMoveType(client);
	if (mt == MOVETYPE_NOCLIP || mt == MOVETYPE_OBSERVER)
	{
		return;
	}

	if (frozen)
	{
		if (mt != MOVETYPE_NONE)
		{
			SetEntityMoveType(client, MOVETYPE_NONE);
		}
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", 1.0);
	}
	else
	{
		if (mt != MOVETYPE_WALK)
		{
			SetEntityMoveType(client, MOVETYPE_WALK);
		}
		float speed = GetEntPropFloat(client, Prop_Send, "m_flMaxspeed");
		if (speed < 10.0)
		{
			SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", 300.0);
		}
	}
}


Action Timer_HSRelease(Handle timer)
{
	g_hHSHideTimer = null;

	if (!g_bHideSeek)
	{
		return Plugin_Stop;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && AJB_IsGuard(i))
		{
			AJB_LR_SetSeekerFrozen(i, false);
		}
	}

	AJB_ChatAll("LR HideSeek Released");
	return Plugin_Stop;
}

Action Timer_HSEnd(Handle timer)
{
	g_hHSEndTimer = null;

	if (!g_bHideSeek || !g_bHasCore)
	{
		return Plugin_Stop;
	}

	// Time up: the hiders (RED) survived -> prisoners win.
	AJB_ChatAll("LR HideSeek TimeUp");
	AJB_ForceTeamWin(AJB_GetPrisonersTeam());
	return Plugin_Stop;
}

void AJB_LR_KillHSTimers()
{
	if (g_hHSHideTimer != null)
	{
		delete g_hHSHideTimer;
		g_hHSHideTimer = null;
	}
	if (g_hHSEndTimer != null)
	{
		delete g_hHSEndTimer;
		g_hHSEndTimer = null;
	}
}

