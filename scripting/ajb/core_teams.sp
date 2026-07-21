// =========================================================================================================
// Team helpers (RED prisoners / BLU guards by default)
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

bool AJB_ClientIsPrisoner(int client)
{
	if (!AJB_IsValidClient(client))
	{
		return false;
	}

	return GetClientTeam(client) == AJB_GetPrisonersTeam();
}

bool AJB_ClientIsGuard(int client)
{
	if (!AJB_IsValidClient(client))
	{
		return false;
	}

	return GetClientTeam(client) == AJB_GetGuardsTeam();
}

int AJB_CountAliveOnTeam(int team)
{
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		if (GetClientTeam(i) == team)
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

	// Last Request module owns win/loss while a duel is active.
	if (g_RoundState == AJBState_Disabled || g_RoundState == AJBState_Waiting
		|| g_RoundState == AJBState_RoundEnd || g_RoundState == AJBState_LastRequest)
	{
		return;
	}

	int prisoners = AJB_CountAliveOnTeam(AJB_GetPrisonersTeam());
	int guards = AJB_CountAliveOnTeam(AJB_GetGuardsTeam());

	// Empty server / both sides wiped without a fight — do not spam round wins.
	if (prisoners == 0 && guards == 0)
	{
		return;
	}

	// If only one side ever had players (solo testing), skip auto-win.
	int totalHumans = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) >= AJB_TEAM_RED)
		{
			totalHumans++;
		}
	}
	if (totalHumans < 2)
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

void AJB_ForceRoundWin(int team)
{
	if (g_RoundState == AJBState_RoundEnd)
	{
		return;
	}

	AJB_SetRoundState(AJBState_RoundEnd);

	// TF2: game_round_win entity is the standard plugin approach.
	int ent = CreateEntityByName("game_round_win");
	if (ent == -1)
	{
		return;
	}

	DispatchSpawn(ent);
	SetEntProp(ent, Prop_Data, "m_iTeamNum", team);
	AcceptEntityInput(ent, "RoundWin");

	// Entity is one-shot; remove next frame.
	CreateTimer(0.1, Timer_RemoveEntity, EntIndexToEntRef(ent), TIMER_FLAG_NO_MAPCHANGE);
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
