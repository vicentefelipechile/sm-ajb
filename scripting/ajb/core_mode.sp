// =========================================================================================================
// Mode enable / map prefix detection + engine movement cvar policy
// =========================================================================================================

// tf_player_movement_restart_freeze is FCVAR_REPLICATED. Client.dll CanPlayerMove reads it:
//   bNoMovement = InRoundRestart() && freeze_cvar
// Without setting it to 0, a server-only DHooks detour cannot unstick the local player's
// prediction — CalculateMaxSpeed returns 1.0f on the client and you feel frozen.
// RED are locked separately via MOVETYPE_NONE (networked) + server detour returning false.
static ConVar g_cvEngineRestartFreeze;
static int g_iSavedRestartFreeze = -1;

void AJB_ApplyEngineMovementPolicy()
{
	if (g_cvEngineRestartFreeze == null)
	{
		g_cvEngineRestartFreeze = FindConVar("tf_player_movement_restart_freeze");
	}

	if (g_cvEngineRestartFreeze == null)
	{
		LogError("[AJB] tf_player_movement_restart_freeze ConVar not found.");
		return;
	}

	if (g_bModeActive)
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

void AJB_RefreshModeActive()
{
	if (g_cvEnabled == null || !g_cvEnabled.BoolValue)
	{
		g_bModeActive = false;
		AJB_ApplyEngineMovementPolicy();
		return;
	}

	if (g_cvForce != null && g_cvForce.BoolValue)
	{
		g_bModeActive = true;
		AJB_ApplyEngineMovementPolicy();
		return;
	}

	char prefix[AJB_MAX_MAP_PREFIX_LEN];
	g_cvMapPrefix.GetString(prefix, sizeof(prefix));
	if (prefix[0] == '\0')
	{
		g_bModeActive = false;
		AJB_ApplyEngineMovementPolicy();
		return;
	}

	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));

	g_bModeActive = (StrContains(map, prefix, false) == 0);
	AJB_ApplyEngineMovementPolicy();
}

int AJB_GetGuardsTeam()
{
	return g_cvGuardsTeam.IntValue;
}

int AJB_GetPrisonersTeam()
{
	return g_cvPrisonersTeam.IntValue;
}
