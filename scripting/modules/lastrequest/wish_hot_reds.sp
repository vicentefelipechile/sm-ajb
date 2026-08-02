// =========================================================================================================
// Last Request - Hot Reds
// =========================================================================================================

void AJB_LR_DoHotReds(int prisoner)
{
	// NEXT round hot reds.
	AJB_LR_QueueWish(prisoner, LRWish_HotReds, "LR Chose HotReds");
}

Action Timer_HotReds(Handle timer)
{
	if (!g_bHotReds || !g_bHasCore || !AJB_IsEnabled())
	{
		g_hHotTimer = null;
		return Plugin_Stop;
	}

	float dmg = g_cvHotDamage.FloatValue;
	if (dmg < 1.0)
	{
		dmg = LR_HOT_DPS;
	}

	// Snapshot living guards + origins once (O(n)) so the red x guard proximity test below is not
	// re-fetching positions and re-testing team membership for every pair each 0.5s tick.
	int guards[MAXPLAYERS];
	float guardPos[MAXPLAYERS][3];
	int guardCount = 0;
	for (int b = 1; b <= MaxClients; b++)
	{
		if (IsClientInGame(b) && IsPlayerAlive(b) && AJB_IsGuard(b))
		{
			guards[guardCount] = b;
			GetClientAbsOrigin(b, guardPos[guardCount]);
			guardCount++;
		}
	}

	if (guardCount == 0)
	{
		return Plugin_Continue;
	}

	for (int r = 1; r <= MaxClients; r++)
	{
		if (!IsClientInGame(r) || !IsPlayerAlive(r) || !AJB_IsPrisoner(r))
		{
			continue;
		}

		float rPos[3];
		GetClientAbsOrigin(r, rPos);

		for (int g = 0; g < guardCount; g++)
		{
			if (GetVectorDistance(rPos, guardPos[g], true) <= 6400.0)
			{
				SDKHooks_TakeDamage(guards[g], 0, 0, dmg, DMG_BURN);
			}
		}
	}

	return Plugin_Continue;
}

Action AJB_LR_OnStartTouch(int entity, int other)
{
	if (!g_bHotReds || !g_bHasCore)
	{
		return Plugin_Continue;
	}

	if (entity < 1 || entity > MaxClients || other < 1 || other > MaxClients)
	{
		return Plugin_Continue;
	}

	if (!IsClientInGame(entity) || !IsPlayerAlive(entity) || !IsClientInGame(other) || !IsPlayerAlive(other))
	{
		return Plugin_Continue;
	}

	// Prisoner touches guard -> burn guard (no auto-rebel; damage as world to skip rebel + block).
	int blu = 0;
	if (AJB_IsPrisoner(entity) && AJB_IsGuard(other))
	{
		blu = other;
	}
	else if (AJB_IsPrisoner(other) && AJB_IsGuard(entity))
	{
		blu = entity;
	}
	else
	{
		return Plugin_Continue;
	}

	float dmg = g_cvHotDamage.FloatValue;
	if (dmg < 1.0)
	{
		dmg = LR_HOT_DPS;
	}

	// attacker=0 so core does not mark rebel / block non-rebel prisoner damage.
	SDKHooks_TakeDamage(blu, 0, 0, dmg, DMG_BURN);
	return Plugin_Continue;
}

void AJB_LR_KillHotTimer()
{
	if (g_hHotTimer != null)
	{
		delete g_hHotTimer;
		g_hHotTimer = null;
	}
}

