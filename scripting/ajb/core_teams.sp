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

void AJB_CheckWinConditions()
{
	if (!g_bModeActive)
	{
		return;
	}

	if (g_RoundState == AJBState_Disabled || g_RoundState == AJBState_Waiting
		|| g_RoundState == AJBState_RoundEnd || g_RoundState == AJBState_LastRequest)
	{
		return;
	}

	int prisoners = AJB_CountAliveOnTeam(AJB_GetPrisonersTeam());
	int guards = AJB_CountAliveOnTeam(AJB_GetGuardsTeam());

	if (prisoners == 0 && guards == 0)
	{
		return;
	}

	// Count anyone on a playable team (humans OR bots). The old "2 humans" gate
	// silently disabled all wins during solo + bot testing.
	int onTeams = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) >= AJB_TEAM_RED)
		{
			onTeams++;
		}
	}
	if (onTeams < 1)
	{
		return;
	}

	if (prisoners == 0 && guards > 0)
	{
		AJB_ForceRoundWin(AJB_GetGuardsTeam());
		return;
	}

	if (guards == 0 && prisoners > 0)
	{
		AJB_ForceRoundWin(AJB_GetPrisonersTeam());
	}
}

// Proper TF2 round end: game_round_win with force_map_reset so the map regenerates.
// Valve wiki: force_map_reset should be true when TeamNum is set (avoids broken/crashy wins).
void AJB_ForceRoundWin(int team)
{
	if (g_RoundState == AJBState_RoundEnd)
	{
		return;
	}

	if (team != AJB_TEAM_RED && team != AJB_TEAM_BLU)
	{
		return;
	}

	// Stop AJB-side clocks/state immediately so nothing "continues" across the boundary.
	AJB_CleanupRoundRuntime();
	g_bOwnedRoundWin = true;
	AJB_SetRoundState(AJBState_RoundEnd);

	char teamStr[8];
	IntToString(team, teamStr, sizeof(teamStr));

	int ent = CreateEntityByName("game_round_win");
	if (ent == -1 || !IsValidEntity(ent))
	{
		LogMessage("[AJB] game_round_win create failed — mp_restartgame 1.");
		g_bWaitingForNewRound = true;
		ServerCommand("mp_restartgame 1");
		return;
	}

	// Keyvalues BEFORE spawn (engine reads them at spawn time).
	// force_map_reset=1 is what regenerates map entities (doors/logic) for the next round.
	DispatchKeyValue(ent, "targetname", "ajb_round_win");
	DispatchKeyValue(ent, "force_map_reset", "1");
	DispatchKeyValue(ent, "switch_teams", "0");
	DispatchKeyValue(ent, "TeamNum", teamStr);

	if (!DispatchSpawn(ent))
	{
		LogMessage("[AJB] game_round_win spawn failed — mp_restartgame 1.");
		AcceptEntityInput(ent, "Kill");
		g_bWaitingForNewRound = true;
		ServerCommand("mp_restartgame 1");
		return;
	}

	if (HasEntProp(ent, Prop_Data, "m_bForceMapReset"))
	{
		SetEntProp(ent, Prop_Data, "m_bForceMapReset", 1);
	}
	if (HasEntProp(ent, Prop_Data, "m_bSwitchTeamsOnMapWin"))
	{
		SetEntProp(ent, Prop_Data, "m_bSwitchTeamsOnMapWin", 0);
	}
	if (HasEntProp(ent, Prop_Data, "m_iTeamNum"))
	{
		SetEntProp(ent, Prop_Data, "m_iTeamNum", team);
	}
	if (HasEntProp(ent, Prop_Send, "m_iTeamNum"))
	{
		SetEntProp(ent, Prop_Send, "m_iTeamNum", team);
	}

	SetVariantInt(team);
	AcceptEntityInput(ent, "SetTeam");
	AcceptEntityInput(ent, "RoundWin");

	LogMessage("[AJB] Natural round end via ForceRoundWin team=%d force_map_reset=1.", team);

	// If teamplay_round_start never arrives (jb maps that ignore game_round_win), hard restart.
	g_bWaitingForNewRound = true;
	CreateTimer(18.0, Timer_EnsureNewRoundStarted, _, TIMER_FLAG_NO_MAPCHANGE);

	// Clean the entity after intermission (do not kill at 0.1s — that aborted wins).
	CreateTimer(20.0, Timer_RemoveEntity, EntIndexToEntRef(ent), TIMER_FLAG_NO_MAPCHANGE);
}

// If Event_RoundStart never cleared g_bWaitingForNewRound, the engine ignored RoundWin.
Action Timer_EnsureNewRoundStarted(Handle timer)
{
	if (!g_bModeActive || !g_bWaitingForNewRound)
	{
		return Plugin_Stop;
	}

	LogMessage("[AJB] No teamplay_round_start after win — mp_restartgame 1 (map ignored game_round_win).");
	g_bWaitingForNewRound = false;
	ServerCommand("mp_restartgame 1");
	return Plugin_Stop;
}

Action Timer_RemoveEntity(Handle timer, int ref)
{
	int ent = EntRefToEntIndex(ref);
	if (ent != INVALID_ENT_REFERENCE && IsValidEntity(ent))
	{
		AcceptEntityInput(ent, "Kill");
	}
	return Plugin_Stop;
}
