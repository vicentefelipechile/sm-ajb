// =========================================================================================================
// Natives + forward registration (public API surface)
// =========================================================================================================

void AJB_CreateForwards()
{
	g_hFwdRoundState = CreateGlobalForward("AJB_OnRoundStateChange", ET_Ignore, Param_Cell, Param_Cell);
	g_hFwdWarden = CreateGlobalForward("AJB_OnWardenChanged", ET_Ignore, Param_Cell, Param_Cell);
	g_hFwdRebel = CreateGlobalForward("AJB_OnRebel", ET_Ignore, Param_Cell, Param_Cell);
	g_hFwdCellsOpened = CreateGlobalForward("AJB_OnCellsOpened", ET_Ignore);
	g_hFwdCellsClosed = CreateGlobalForward("AJB_OnCellsClosed", ET_Ignore);
	g_hFwdLastPrisoner = CreateGlobalForward("AJB_OnLastPrisoner", ET_Ignore, Param_Cell);
}

void AJB_RegisterNatives()
{
	CreateNative("AJB_IsEnabled", Native_IsEnabled);
	CreateNative("AJB_GetRoundState", Native_GetRoundState);
	CreateNative("AJB_GetWarden", Native_GetWarden);
	CreateNative("AJB_ClearWarden", Native_ClearWarden);
	CreateNative("AJB_IsPrisoner", Native_IsPrisoner);
	CreateNative("AJB_IsGuard", Native_IsGuard);
	CreateNative("AJB_IsRebel", Native_IsRebel);
	CreateNative("AJB_IsFreeday", Native_IsFreeday);
	CreateNative("AJB_IsFreedayPending", Native_IsFreedayPending);
	CreateNative("AJB_SetRebel", Native_SetRebel);
	CreateNative("AJB_SetPlayerFreeday", Native_SetPlayerFreeday);
	CreateNative("AJB_GiveFreedayNow", Native_GiveFreedayNow);
	CreateNative("AJB_OpenCells", Native_OpenCells);
	CreateNative("AJB_CloseCells", Native_CloseCells);
	CreateNative("AJB_SetPhaseTimer", Native_SetPhaseTimer);
	CreateNative("AJB_SetRoundState", Native_SetRoundState);
	CreateNative("AJB_ForceTeamWin", Native_ForceTeamWin);
}

public int Native_IsEnabled(Handle plugin, int numParams)
{
	return g_bModeActive;
}

public int Native_GetRoundState(Handle plugin, int numParams)
{
	return view_as<int>(g_RoundState);
}

public int Native_GetWarden(Handle plugin, int numParams)
{
	return g_iWarden;
}

public int Native_ClearWarden(Handle plugin, int numParams)
{
	AJB_ClearWarden(true);
	return 0;
}

public int Native_IsPrisoner(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return AJB_ClientIsPrisoner(client);
}

public int Native_IsGuard(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return AJB_ClientIsGuard(client);
}

public int Native_IsRebel(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!AJB_IsValidClient(client))
	{
		return false;
	}
	return g_bRebel[client];
}

public int Native_IsFreeday(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!AJB_IsValidClient(client))
	{
		return false;
	}
	return g_bFreeday[client];
}

public int Native_SetRebel(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool rebel = GetNativeCell(2) != 0;
	AJB_SetRebelInternal(client, rebel, true);
	return 0;
}

public int Native_SetPlayerFreeday(Handle plugin, int numParams)
{
	// Public API: individual wishes always queue for the NEXT round.
	int client = GetNativeCell(1);
	bool freeday = GetNativeCell(2) != 0;
	AJB_QueueFreeday(client, freeday);
	return 0;
}

public int Native_GiveFreedayNow(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool freeday = GetNativeCell(2) != 0;
	AJB_ApplyFreedayNow(client, freeday);
	return 0;
}

public int Native_IsFreedayPending(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients)
	{
		return false;
	}
	return g_bFreedayPending[client];
}

public int Native_OpenCells(Handle plugin, int numParams)
{
	return AJB_OpenCellsInternal(true);
}

public int Native_CloseCells(Handle plugin, int numParams)
{
	return AJB_CloseCellsInternal(true);
}

public int Native_SetPhaseTimer(Handle plugin, int numParams)
{
	float seconds = view_as<float>(GetNativeCell(1));
	AJB_SetPhaseTimer(seconds);
	return 0;
}

public int Native_SetRoundState(Handle plugin, int numParams)
{
	if (!g_bModeActive)
	{
		return false;
	}

	AJBRoundState state = view_as<AJBRoundState>(GetNativeCell(1));
	AJB_SetRoundState(state);
	return true;
}

public int Native_ForceTeamWin(Handle plugin, int numParams)
{
	if (!g_bModeActive)
	{
		return 0;
	}

	int team = GetNativeCell(1);
	if (team != AJB_TEAM_RED && team != AJB_TEAM_BLU)
	{
		return 0;
	}

	AJB_ForceRoundWin(team);
	return 0;
}
