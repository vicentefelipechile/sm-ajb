// =========================================================================================================
// Mode enable / map prefix detection + engine cvar policy
// =========================================================================================================

// tf_player_movement_restart_freeze is FCVAR_REPLICATED. Client.dll CanPlayerMove reads it:
//   bNoMovement = InRoundRestart() && freeze_cvar
// Without setting it to 0, a server-only DHooks detour cannot unstick the local player's
// prediction — CalculateMaxSpeed returns 1.0f on the client and you feel frozen.
// RED are locked separately via MOVETYPE_NONE (networked) + server detour returning false.
static ConVar g_cvEngineRestartFreeze;
static int g_iSavedRestartFreeze = -1;

// Arena spectator queue is useless (and noisy) on JB maps — force off while AJB is active.
static ConVar g_cvEngineArenaUseQueue;
static int g_iSavedArenaUseQueue = -1;

// Stock autobalance fights JB team composition (few BLU, many RED) — disable while active.
static ConVar g_cvEngineTeamsUnbalance;
static int g_iSavedTeamsUnbalance = -1;

void AJB_ApplyEngineCvarPolicy()
{
	AJB_ApplyEngineMovementPolicy();
	AJB_ApplyEngineArenaQueuePolicy();
	AJB_ApplyEngineTeamsUnbalancePolicy();
}

// Back-compat name used across core_rounds / OnPluginEnd.
void AJB_ApplyEngineMovementPolicy()
{
	if (g_cvEngineRestartFreeze == null)
	{
		g_cvEngineRestartFreeze = FindConVar("tf_player_movement_restart_freeze");
	}

	if (g_cvEngineRestartFreeze == null)
	{
		LogError("[AJB] tf_player_movement_restart_freeze ConVar not found.");
	}
	else if (g_bModeActive)
	{
		if (g_iSavedRestartFreeze < 0)
		{
			g_iSavedRestartFreeze = g_cvEngineRestartFreeze.IntValue;
		}

		// Always force 0 while AJB is active. FCVAR_REPLICATED: SetInt notifies clients
		// so client CanPlayerMove matches (server-only detour is not enough).
		int before = g_cvEngineRestartFreeze.IntValue;
		g_cvEngineRestartFreeze.SetInt(0);
		if (before != 0)
		{
			// Console path as belt for any client that missed the net ConVar update.
			ServerCommand("tf_player_movement_restart_freeze 0");
			LogMessage("[AJB] tf_player_movement_restart_freeze 0 (was %d; replicated — BLU can move in preround).", before);
		}
	}
	else if (g_iSavedRestartFreeze >= 0)
	{
		int restore = g_iSavedRestartFreeze;
		g_iSavedRestartFreeze = -1;
		g_cvEngineRestartFreeze.SetInt(restore);
		LogMessage("[AJB] restored tf_player_movement_restart_freeze to %d.", restore);
	}
}

void AJB_ApplyEngineArenaQueuePolicy()
{
	if (g_cvEngineArenaUseQueue == null)
	{
		g_cvEngineArenaUseQueue = FindConVar("tf_arena_use_queue");
	}

	if (g_cvEngineArenaUseQueue == null)
	{
		// Non-fatal: cvar only exists on TF2; still log once if missing.
		static bool s_bLoggedMissing;
		if (!s_bLoggedMissing)
		{
			s_bLoggedMissing = true;
			LogError("[AJB] tf_arena_use_queue ConVar not found.");
		}
		return;
	}

	if (g_bModeActive)
	{
		if (g_iSavedArenaUseQueue < 0)
		{
			g_iSavedArenaUseQueue = g_cvEngineArenaUseQueue.IntValue;
		}

		int before = g_cvEngineArenaUseQueue.IntValue;
		if (before != 0)
		{
			g_cvEngineArenaUseQueue.SetInt(0);
			LogMessage("[AJB] tf_arena_use_queue 0 (was %d).", before);
		}
		else
		{
			// Ensure it stays 0 even if something else flipped it after we saved.
			g_cvEngineArenaUseQueue.SetInt(0);
		}
	}
	else if (g_iSavedArenaUseQueue >= 0)
	{
		int restore = g_iSavedArenaUseQueue;
		g_iSavedArenaUseQueue = -1;
		g_cvEngineArenaUseQueue.SetInt(restore);
		LogMessage("[AJB] restored tf_arena_use_queue to %d.", restore);
	}
}

void AJB_ApplyEngineTeamsUnbalancePolicy()
{
	if (g_cvEngineTeamsUnbalance == null)
	{
		g_cvEngineTeamsUnbalance = FindConVar("mp_teams_unbalance_limit");
	}

	if (g_cvEngineTeamsUnbalance == null)
	{
		static bool s_bLoggedMissing;
		if (!s_bLoggedMissing)
		{
			s_bLoggedMissing = true;
			LogError("[AJB] mp_teams_unbalance_limit ConVar not found.");
		}
		return;
	}

	if (g_bModeActive)
	{
		if (g_iSavedTeamsUnbalance < 0)
		{
			g_iSavedTeamsUnbalance = g_cvEngineTeamsUnbalance.IntValue;
		}

		int before = g_cvEngineTeamsUnbalance.IntValue;
		g_cvEngineTeamsUnbalance.SetInt(0);
		if (before != 0)
		{
			LogMessage("[AJB] mp_teams_unbalance_limit 0 (was %d).", before);
		}
	}
	else if (g_iSavedTeamsUnbalance >= 0)
	{
		int restore = g_iSavedTeamsUnbalance;
		g_iSavedTeamsUnbalance = -1;
		g_cvEngineTeamsUnbalance.SetInt(restore);
		LogMessage("[AJB] restored mp_teams_unbalance_limit to %d.", restore);
	}
}

void AJB_RefreshModeActive()
{
	if (g_cvEnabled == null || !g_cvEnabled.BoolValue)
	{
		g_bModeActive = false;
		AJB_ApplyEngineCvarPolicy();
		return;
	}

	if (g_cvForce != null && g_cvForce.BoolValue)
	{
		g_bModeActive = true;
		AJB_ApplyEngineCvarPolicy();
		return;
	}

	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));

	g_bModeActive = AJB_MapMatchesPrefix(map);
	AJB_ApplyEngineCvarPolicy();
}

int AJB_GetGuardsTeam()
{
	return g_cvGuardsTeam.IntValue;
}

int AJB_GetPrisonersTeam()
{
	return g_cvPrisonersTeam.IntValue;
}
