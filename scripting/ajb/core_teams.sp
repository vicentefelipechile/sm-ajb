// =========================================================================================================
// Team helpers + last-prisoner check + forced round wins
// =========================================================================================================

bool AJB_IsValidClient(int client, bool aliveOnly = false)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	if (aliveOnly && !IsPlayerAlive(client))
	{
		return false;
	}

	return true;
}

bool AJB_ClientIsGuard(int client)
{
	if (!AJB_IsValidClient(client))
	{
		return false;
	}

	return GetClientTeam(client) == AJB_GetGuardsTeam();
}

bool AJB_ClientIsPrisoner(int client)
{
	if (!AJB_IsValidClient(client))
	{
		return false;
	}

	return GetClientTeam(client) == AJB_GetPrisonersTeam();
}

int AJB_CountAliveOnTeam(int team)
{
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == team)
		{
			count++;
		}
	}
	return count;
}

int AJB_FindFirstAliveOnTeam(int team)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == team)
		{
			return i;
		}
	}
	return 0;
}

int AJB_PickRandomAliveOnTeam(int team)
{
	int candidates[MAXPLAYERS];
	int count = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == team)
		{
			candidates[count++] = i;
		}
	}

	if (count == 0)
	{
		return 0;
	}

	return candidates[GetRandomInt(0, count - 1)];
}

void AJB_CheckLastPrisoner()
{
	if (!g_bModeActive || g_bLastPrisonerAnnounced)
	{
		return;
	}

	if (g_RoundState != AJBState_CellsLocked && g_RoundState != AJBState_CellsOpen)
	{
		return;
	}

	int alive = AJB_CountAliveOnTeam(AJB_GetPrisonersTeam());
	if (alive != 1)
	{
		return;
	}

	int last = AJB_FindFirstAliveOnTeam(AJB_GetPrisonersTeam());
	if (last == 0)
	{
		return;
	}

	g_bLastPrisonerAnnounced = true;

	Call_StartForward(g_hFwdLastPrisoner);
	Call_PushCell(last);
	Call_Finish();
}

// Win / force-round / map-reset machinery was removed — it fought the engine and made rounds worse.
// AJB no longer ends rounds or restarts the map. Engine / map logic owns that.
