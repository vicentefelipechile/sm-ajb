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

int AJB_PickWeightedWardenGuard(int team)
{
	int candidates[MAXPLAYERS];
	int weights[MAXPLAYERS];
	int count = 0;
	int total = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != team)
		{
			continue;
		}

		int weight = AJB_WARDEN_WEIGHT_CAP;
		if (g_iWardenLastRound[i] > 0)
		{
			weight = g_iWardenRoundSerial - g_iWardenLastRound[i];
			if (weight < 1)
			{
				weight = 1;
			}
			else if (weight > AJB_WARDEN_WEIGHT_CAP)
			{
				weight = AJB_WARDEN_WEIGHT_CAP;
			}
		}

		candidates[count] = i;
		weights[count] = weight;
		total += weight;
		count++;
	}

	if (count == 0)
	{
		return 0;
	}

	int roll = GetRandomInt(0, total - 1);
	for (int i = 0; i < count; i++)
	{
		roll -= weights[i];
		if (roll < 0)
		{
			return candidates[i];
		}
	}

	return candidates[count - 1];
}

int AJB_CountOnTeam(int team)
{
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team)
		{
			count++;
		}
	}
	return count;
}

// Max guards allowed for the current population, honoring sm_ajb_guard_ratio (prisoners per
// guard). ratio <= 0 disables the cap. Once there are enough players to run a round we always
// allow at least one guard, so a near-empty server is never left with a prisoners-only team.
int AJB_MaxGuards()
{
	int ratio = g_cvGuardRatio.IntValue;
	if (ratio <= 0)
	{
		return MaxClients;
	}

	int total = AJB_CountOnTeam(AJB_GetGuardsTeam()) + AJB_CountOnTeam(AJB_GetPrisonersTeam());
	int maxGuards = total / (ratio + 1);
	if (maxGuards < 1 && total >= 2)
	{
		maxGuards = 1;
	}
	return maxGuards;
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

// =========================================================================================================
// Forced team names
// =========================================================================================================

void AJB_Teams_ApplyNames()
{
	if (!g_bModeActive)
	{
		return;
	}

	char guards[32];
	char prisoners[32];
	Format(guards, sizeof(guards), "%T", "Team Guards", LANG_SERVER);
	Format(prisoners, sizeof(prisoners), "%T", "Team Prisoners", LANG_SERVER);

	int guardsTeam = AJB_GetGuardsTeam();
	int prisonersTeam = AJB_GetPrisonersTeam();

	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "tf_team")) != -1)
	{
		int team = GetEntProp(ent, Prop_Send, "m_iTeamNum");
		if (team == guardsTeam)
		{
			SetEntPropString(ent, Prop_Send, "m_szTeamname", guards);
		}
		else if (team == prisonersTeam)
		{
			SetEntPropString(ent, Prop_Send, "m_szTeamname", prisoners);
		}
	}
}

// tf_team entities exist a beat after map spawn; delay so the write sticks.
Action Timer_ApplyTeamNames(Handle timer)
{
	AJB_Teams_ApplyNames();
	return Plugin_Stop;
}
