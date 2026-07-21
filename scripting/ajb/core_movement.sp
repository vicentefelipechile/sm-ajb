// =========================================================================================================
// Movement control for AJB prep / engine preround
//
// SDK (tf_player_shared.cpp — shared server+CLIENT):
//   CanPlayerMove() is false when InRoundRestart() && tf_player_movement_restart_freeze.
//   CalculateMaxSpeed() returns 1.0f when !CanPlayerMove().
//
// CRITICAL: CanPlayerMove lives in CLIENT.dll too. A server-only DHooks detour does NOT
// change what the local client predicts. The freeze cvar is FCVAR_REPLICATED, so it must
// be 0 for BLU's client to accept movement. RED stay locked with networked MOVETYPE_NONE
// (+ server detour forcing false as authority).
//
// Stack:
//   1) tf_player_movement_restart_freeze = 0  → client+server engine freeze off
//   2) DHooks CanPlayerMove POST            → server policy (guards true / prisoners false)
//   3) core_prep MOVETYPE_NONE on RED        → networked hard lock prisoners see
// =========================================================================================================

#define AJB_GAMEDATA_FILE "ajb.games"

DynamicDetour g_hDetourCanPlayerMove;
bool g_bCanPlayerMoveHooked;

void AJB_Movement_OnPluginStart()
{
	g_bCanPlayerMoveHooked = false;

	GameData gd = new GameData(AJB_GAMEDATA_FILE);
	if (gd == null)
	{
		LogError("[AJB] Missing gamedata %s.txt — freeze cvar only.", AJB_GAMEDATA_FILE);
		return;
	}

	g_hDetourCanPlayerMove = DynamicDetour.FromConf(gd, "CTFPlayer::CanPlayerMove");
	delete gd;

	if (g_hDetourCanPlayerMove == null)
	{
		LogError("[AJB] Failed to create detour CTFPlayer::CanPlayerMove.");
		return;
	}

	if (!g_hDetourCanPlayerMove.Enable(Hook_Post, Detour_CanPlayerMove_Post))
	{
		LogError("[AJB] Failed to enable CTFPlayer::CanPlayerMove detour.");
		delete g_hDetourCanPlayerMove;
		g_hDetourCanPlayerMove = null;
		return;
	}

	g_bCanPlayerMoveHooked = true;
	LogMessage("[AJB] CTFPlayer::CanPlayerMove detour armed (server authority; freeze cvar still required for client).");
}

void AJB_Movement_OnPluginEnd()
{
	if (g_hDetourCanPlayerMove != null)
	{
		g_hDetourCanPlayerMove.Disable(Hook_Post, Detour_CanPlayerMove_Post);
		delete g_hDetourCanPlayerMove;
		g_hDetourCanPlayerMove = null;
	}
	g_bCanPlayerMoveHooked = false;
}

bool AJB_Movement_DetourActive()
{
	return g_bCanPlayerMoveHooked;
}

// Server-side authority. Client still needs freeze cvar=0 (replicated) to predict movement.
public MRESReturn Detour_CanPlayerMove_Post(int client, DHookReturn hReturn)
{
	if (!g_bModeActive)
	{
		return MRES_Ignored;
	}

	if (client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		return MRES_Ignored;
	}

	MoveType mt = GetEntityMoveType(client);
	if (mt == MOVETYPE_NOCLIP || mt == MOVETYPE_OBSERVER)
	{
		return MRES_Ignored;
	}

	// Prep: explicit roles.
	if (AJB_IsPrepActive())
	{
		if (AJB_ClientIsGuard(client))
		{
			hReturn.Value = true;
			return MRES_Override;
		}
		if (AJB_ClientIsPrisoner(client))
		{
			hReturn.Value = false;
			return MRES_Override;
		}
		return MRES_Ignored;
	}

	// Outside prep but engine still in PREROUND: let playable teams move (JB has no setup doors).
	int eng = GameRules_GetProp("m_iRoundState");
	if (eng == 3) // GR_STATE_PREROUND
	{
		if (GetClientTeam(client) >= AJB_TEAM_RED)
		{
			hReturn.Value = true;
			return MRES_Override;
		}
	}

	return MRES_Ignored;
}
