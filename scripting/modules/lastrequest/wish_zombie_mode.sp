// =========================================================================================================
// Last Request - Zombie Mode
// =========================================================================================================

// =========================================================================================================
// Zombie Mode
// =========================================================================================================
// Humans = RED, zombies = BLU. Grace -> patient zero -> 2 hits infect. Dead zombies respawn with uber.

void AJB_LR_DoZombieMode(int prisoner)
{
	AJB_LR_QueueWish(prisoner, LRWish_ZombieMode, "LR Chose ZombieMode");
}

void AJB_LR_ApplyZombieMode(const char[] chooser)
{
	g_bZombieMode = true;
	g_bZMGrace = true;
	g_bZMEnding = false;

	for (int i = 1; i <= MaxClients; i++)
	{
		g_iZMHits[i] = 0;
		g_bZMPendingInfect[i] = false;
		g_iZMPendingInfectBy[i] = 0;
		g_bZMTeamSwap[i] = false;
		g_iZMOriginalTeam[i] = 0;
		AJB_LR_ZM_KillRespawnTimer(i);
	}

	AJB_BeginCombatDay();
	AJB_ClearWarden();
	AJB_SetRebelOnHit(false);
	AJB_ClearPhaseTimer();

	AJB_OpenCells();
	if (g_bHasCore)
	{
		AJB_SetRoundState(AJBState_SpecialDay);
	}

	int redTeam = AJB_LR_GetPrisonersTeam();
	int blueTeam = AJB_LR_GetGuardsTeam();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		int team = GetClientTeam(i);
		// Snapshot real side before we fold everyone onto RED for the infection round.
		if (team == redTeam || team == blueTeam)
		{
			g_iZMOriginalTeam[i] = team;
		}

		if (team == blueTeam)
		{
			g_bZMTeamSwap[i] = true;
			ChangeClientTeam(i, 1);
			ChangeClientTeam(i, redTeam);
			g_bZMTeamSwap[i] = false;
		}

		if (!IsPlayerAlive(i) && GetClientTeam(i) == redTeam)
		{
			TF2_RespawnPlayer(i);
		}
	}

	RequestFrame(Frame_ZMArmHumans);

	float grace = g_cvZMInfectDelay.FloatValue;
	if (grace < 5.0)
	{
		grace = LR_ZM_INFECT_DEFAULT;
	}

	float roundTime = g_cvZMRoundTime.FloatValue;
	if (roundTime < 60.0)
	{
		roundTime = LR_ZM_ROUND_DEFAULT;
	}

	AJB_SetPhaseTimer(roundTime);
	AJB_LR_KillZMTimers();
	g_hZMGraceTimer = CreateTimer(grace, Timer_ZMGraceEnd, _, TIMER_FLAG_NO_MAPCHANGE);
	g_hZMEndTimer = CreateTimer(roundTime, Timer_ZMEnd, _, TIMER_FLAG_NO_MAPCHANGE);

	AJB_LR_ChatAllZombieApplied(chooser, grace);
}

void Frame_ZMArmHumans(any data)
{
	if (!g_bZombieMode)
	{
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i) && AJB_IsPrisoner(i))
		{
			AJB_LR_ZM_ArmHuman(i);
		}
	}
}

void AJB_LR_ZM_ArmHuman(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	TF2_RegeneratePlayer(client);
}

void AJB_LR_ZM_ArmZombie(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	TF2_RegeneratePlayer(client);
	AJB_LR_HG_StripToMelee(client);
}

void AJB_LR_ZM_OnPlayerSpawn(int client)
{
	if (!g_bZombieMode || !IsClientInGame(client) || IsFakeClient(client))
	{
		return;
	}

	int team = GetClientTeam(client);
	if (team < 2)
	{
		return;
	}

	RequestFrame(Frame_ZMArmClient, GetClientUserId(client));
}

void Frame_ZMArmClient(int userid)
{
	if (!g_bZombieMode)
	{
		return;
	}

	int client = GetClientOfUserId(userid);
	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	if (AJB_IsGuard(client))
	{
		AJB_LR_ZM_ArmZombie(client);
	}
	else if (AJB_IsPrisoner(client) && g_bZMGrace)
	{
		// Only re-arm humans during the pre-infection scatter window.
		AJB_LR_ZM_ArmHuman(client);
	}
}

Action AJB_LR_ZM_OnTakeDamage(int victim, int attacker, float damage)
{
	if (attacker < 1 || attacker > MaxClients || victim < 1 || victim > MaxClients)
	{
		return Plugin_Continue;
	}

	if (g_bZMGrace || g_bZMEnding)
	{
		return Plugin_Handled;
	}

	if (damage <= 0.0 || attacker == victim)
	{
		return Plugin_Continue;
	}

	int redTeam = AJB_LR_GetPrisonersTeam();
	int blueTeam = AJB_LR_GetGuardsTeam();

	// Only zombie -> human hits count toward infection.
	if (GetClientTeam(attacker) != blueTeam || GetClientTeam(victim) != redTeam)
	{
		return Plugin_Continue;
	}

	if (g_bZMPendingInfect[victim])
	{
		return Plugin_Continue;
	}

	g_iZMHits[victim]++;
	int need = g_cvZMHits.IntValue;
	if (need < 1)
	{
		need = LR_ZM_HITS_DEFAULT;
	}

	if (g_iZMHits[victim] >= need)
	{
		g_bZMPendingInfect[victim] = true;
		g_iZMPendingInfectBy[victim] = GetClientUserId(attacker);
		// Defer so a lethal hit can finish before team swap / respawn.
		RequestFrame(Frame_ZMInfect, GetClientUserId(victim));
	}

	return Plugin_Continue;
}

void Frame_ZMInfect(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client < 1)
	{
		return;
	}

	int attacker = GetClientOfUserId(g_iZMPendingInfectBy[client]);
	g_bZMPendingInfect[client] = false;
	g_iZMPendingInfectBy[client] = 0;

	if (!g_bZombieMode || g_bZMEnding || !IsClientInGame(client))
	{
		return;
	}

	// Still human, or already dead on RED/spec after a lethal infect hit.
	int team = GetClientTeam(client);
	int redTeam = AJB_LR_GetPrisonersTeam();
	if (team == AJB_LR_GetGuardsTeam())
	{
		return;
	}
	if (team != redTeam && IsPlayerAlive(client))
	{
		return;
	}

	AJB_LR_ZM_Infect(client, attacker, false);
}

// patientZero = first random pick (announces differently). attacker is optional (0 = none).
void AJB_LR_ZM_Infect(int client, int attacker, bool patientZero)
{
	if (!g_bZombieMode || g_bZMEnding || client < 1 || !IsClientInGame(client) || IsFakeClient(client))
	{
		return;
	}

	int blueTeam = AJB_LR_GetGuardsTeam();
	if (GetClientTeam(client) == blueTeam)
	{
		return;
	}

	g_iZMHits[client] = 0;
	g_bZMPendingInfect[client] = false;
	g_iZMPendingInfectBy[client] = 0;
	AJB_LR_ZM_KillRespawnTimer(client);

	float origin[3];
	float angles[3];
	bool hadPos = IsPlayerAlive(client);
	if (hadPos)
	{
		GetClientAbsOrigin(client, origin);
		GetClientEyeAngles(client, angles);
	}

	// Spectator transit avoids a direct cross-team death event mid-infect.
	g_bZMTeamSwap[client] = true;
	ChangeClientTeam(client, 1);
	ChangeClientTeam(client, blueTeam);
	g_bZMTeamSwap[client] = false;

	if (!IsPlayerAlive(client))
	{
		TF2_RespawnPlayer(client);
	}

	if (IsPlayerAlive(client))
	{
		AJB_LR_ZM_ArmZombie(client);
		if (hadPos)
		{
			float noVel[3];
			TeleportEntity(client, origin, angles, noVel);
		}
	}

	if (patientZero)
	{
		AJB_LR_ChatAll1N("LR ZM Patient Zero", client);
	}
	else if (attacker > 0 && IsClientInGame(attacker))
	{
		AJB_LR_ChatAll2N("LR ZM Infected", attacker, client);
	}
	else
	{
		AJB_LR_ChatAll1N("LR ZM Infected Solo", client);
	}

	RequestFrame(Frame_ZMCheckWinner);
}

void AJB_LR_ZM_OnPlayerDeath(int victim)
{
	if (!g_bZombieMode || g_bZMEnding || victim < 1 || victim > MaxClients)
	{
		return;
	}

	// Intentional team moves (gather / infect) kill via spectator transit - ignore those.
	if (g_bZMTeamSwap[victim])
	{
		return;
	}

	g_iZMHits[victim] = 0;

	int blueTeam = AJB_LR_GetGuardsTeam();
	// Event is post: team may already be spectator. Prefer "was zombie" via pending infect
	// (still human converting) vs schedule respawn only when still/on BLU or dead as guard role.
	// Use attacker-side role before death: if they had a pending infect, conversion frame owns them.
	if (g_bZMPendingInfect[victim])
	{
		return;
	}

	// Dead ringer already filtered. If they died as BLU zombie, respawn; else human wipe check.
	// Post-death GetClientTeam is often still the pre-death team in TF2.
	if (GetClientTeam(victim) == blueTeam)
	{
		AJB_LR_ZM_ScheduleRespawn(victim);
		return;
	}

	// Human death: no respawn - check if zombies wiped the living RED side.
	RequestFrame(Frame_ZMCheckWinner);
}

void AJB_LR_ZM_ScheduleRespawn(int client)
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	AJB_LR_ZM_KillRespawnTimer(client);

	float delay = g_cvZMRespawn.FloatValue;
	if (delay < 1.0)
	{
		delay = LR_ZM_RESPAWN_DEFAULT;
	}

	g_hZMRespawnTimer[client] = CreateTimer(delay, Timer_ZMRespawn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

void AJB_LR_ZM_KillRespawnTimer(int client)
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	if (g_hZMRespawnTimer[client] != null)
	{
		delete g_hZMRespawnTimer[client];
		g_hZMRespawnTimer[client] = null;
	}
}

void AJB_LR_ZM_KillAllRespawnTimers()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		AJB_LR_ZM_KillRespawnTimer(i);
	}
}

Action Timer_ZMRespawn(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0 && client <= MaxClients)
	{
		g_hZMRespawnTimer[client] = null;
	}

	if (!g_bZombieMode || g_bZMEnding)
	{
		return Plugin_Stop;
	}

	if (client < 1 || !IsClientInGame(client) || IsFakeClient(client))
	{
		return Plugin_Stop;
	}

	int blueTeam = AJB_LR_GetGuardsTeam();
	if (GetClientTeam(client) != blueTeam)
	{
		return Plugin_Stop;
	}

	if (IsPlayerAlive(client))
	{
		return Plugin_Stop;
	}

	TF2_RespawnPlayer(client);
	if (!IsPlayerAlive(client))
	{
		return Plugin_Stop;
	}

	AJB_LR_ZM_ArmZombie(client);
	AJB_LR_ZM_TeleportRespawn(client);

	float protect = g_cvZMSpawnProtect.FloatValue;
	if (protect > 0.0)
	{
		TF2_AddCondition(client, TFCond_Ubercharged, protect);
	}

	return Plugin_Stop;
}

void AJB_LR_ZM_TeleportRespawn(int client)
{
	float origin[3];
	float angles[3];
	float noVel[3];

	int mate = AJB_LR_ZM_PickAliveTeammate(client);
	if (mate > 0)
	{
		GetClientAbsOrigin(mate, origin);
		GetClientEyeAngles(mate, angles);
		origin[2] += LR_ZM_MATE_Z_OFFSET;
		TeleportEntity(client, origin, angles, noVel);
		return;
	}

	int spawn = AJB_LR_FindGuardSpawn();
	if (spawn != -1)
	{
		GetEntPropVector(spawn, Prop_Data, "m_vecOrigin", origin);
		GetEntPropVector(spawn, Prop_Data, "m_angRotation", angles);
		TeleportEntity(client, origin, angles, noVel);
	}
}

int AJB_LR_ZM_PickAliveTeammate(int self)
{
	int blueTeam = AJB_LR_GetGuardsTeam();
	int list[MAXPLAYERS];
	int count = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == self || !IsClientInGame(i) || !IsPlayerAlive(i) || IsFakeClient(i))
		{
			continue;
		}
		if (GetClientTeam(i) == blueTeam)
		{
			list[count++] = i;
		}
	}

	if (count <= 0)
	{
		return 0;
	}

	return list[GetRandomInt(0, count - 1)];
}

Action Timer_ZMGraceEnd(Handle timer)
{
	g_hZMGraceTimer = null;

	if (!g_bZombieMode || g_bZMEnding)
	{
		return Plugin_Stop;
	}

	g_bZMGrace = false;

	int redTeam = AJB_LR_GetPrisonersTeam();
	int candidates[MAXPLAYERS];
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i) && GetClientTeam(i) == redTeam)
		{
			candidates[count++] = i;
		}
	}

	if (count < 1)
	{
		g_bZMEnding = true;
		AJB_ChatAll("LR ZM NoHumans");
		if (g_bHasCore)
		{
			AJB_ForceTeamWin(AJB_LR_GetGuardsTeam());
		}
		return Plugin_Stop;
	}

	int pick = candidates[GetRandomInt(0, count - 1)];
	AJB_LR_ZM_Infect(pick, 0, true);
	AJB_ChatAll("LR ZM Grace End");
	return Plugin_Stop;
}

Action Timer_ZMEnd(Handle timer)
{
	g_hZMEndTimer = null;

	if (!g_bZombieMode || !g_bHasCore || g_bZMEnding)
	{
		return Plugin_Stop;
	}

	g_bZMEnding = true;

	int redTeam = AJB_LR_GetPrisonersTeam();
	bool anyHuman = false;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i) && GetClientTeam(i) == redTeam)
		{
			anyHuman = true;
			break;
		}
	}

	if (anyHuman)
	{
		AJB_ChatAll("LR ZM Humans Win");
		AJB_ForceTeamWin(redTeam);
	}
	else
	{
		AJB_ChatAll("LR ZM Zombies Win");
		AJB_ForceTeamWin(AJB_LR_GetGuardsTeam());
	}

	return Plugin_Stop;
}

void Frame_ZMCheckWinner(any data)
{
	if (!g_bZombieMode || g_bZMEnding || !g_bHasCore)
	{
		return;
	}

	// Patient zero not out yet - do not end on early deaths during scatter.
	if (g_bZMGrace)
	{
		return;
	}

	int redTeam = AJB_LR_GetPrisonersTeam();
	int aliveHumans = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i) && GetClientTeam(i) == redTeam)
		{
			aliveHumans++;
		}
	}

	if (aliveHumans <= 0)
	{
		g_bZMEnding = true;
		AJB_ChatAll("LR ZM Zombies Win");
		AJB_ForceTeamWin(AJB_LR_GetGuardsTeam());
	}
}

void AJB_LR_KillZMTimers()
{
	if (g_hZMGraceTimer != null)
	{
		delete g_hZMGraceTimer;
		g_hZMGraceTimer = null;
	}
	if (g_hZMEndTimer != null)
	{
		delete g_hZMEndTimer;
		g_hZMEndTimer = null;
	}
}

void AJB_LR_ChatAllZombieApplied(const char[] chooserName, float grace)
{
	int graceSec = RoundToFloor(grace);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", "LR Applied ZombieMode", i, prefix,
			chooserName[0] != '\0' ? chooserName : "LR", graceSec);
	}
}

