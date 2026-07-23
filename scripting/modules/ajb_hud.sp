// =========================================================================================================
// Another Jailbreak — HUD extras module
// Shows warden name, round phase, and rebel hints. Does NOT own the primary countdown clock
// =========================================================================================================

#pragma semicolon 1
#pragma newdecls required

// =========================================================================================================
// Imports
// =========================================================================================================

#include <sourcemod>
#include <sdktools>

#undef REQUIRE_PLUGIN
#include <ajb/ajb>
#define REQUIRE_PLUGIN

// =========================================================================================================
// Constants
// =========================================================================================================

#define PLUGIN_VERSION "1.0.0"
#define HUD_REFRESH    1.0

// =========================================================================================================
// Plugin info
// =========================================================================================================

public Plugin myinfo =
{
	name        = "Another Jailbreak - HUD",
	author      = "SummerTYT",
	description = "Another Jailbreak — warden/phase HUD extras (not the round timer).",
	version     = PLUGIN_VERSION,
	url         = ""
};

// =========================================================================================================
// ConVars / state
// =========================================================================================================

ConVar g_cvEnabled;
bool g_bHasCore;
Handle g_hHudSync;
Handle g_hRefreshTimer;

// =========================================================================================================
// Lifecycle
// =========================================================================================================

public void OnPluginStart()
{
	CreateConVar("sm_ajb_hud_version", PLUGIN_VERSION, "AJB HUD module version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_ajb_hud_enabled", "1", "Enable AJB HUD extras.", _, true, 0.0, true, 1.0);

	AutoExecConfig(true, "ajb_hud");

	g_hHudSync = CreateHudSynchronizer();
	g_bHasCore = LibraryExists(AJB_LIBRARY);

	if (g_bHasCore)
	{
		AJB_Hud_StartTimer();
	}

	LogMessage("[AJB-HUD] loaded (core %s).", g_bHasCore ? "present" : "missing");
}

public void OnPluginEnd()
{
	AJB_Hud_StopTimer();
}

public void OnMapStart()
{
	if (g_bHasCore)
	{
		AJB_Hud_StartTimer();
	}
}

public void OnMapEnd()
{
	AJB_Hud_StopTimer();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = true;
		AJB_Hud_StartTimer();
		LogMessage("[AJB-HUD] core attached.");
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = false;
		AJB_Hud_StopTimer();
		LogMessage("[AJB-HUD] core detached.");
	}
}

// =========================================================================================================
// Core forwards
// =========================================================================================================

public void AJB_OnWardenChanged(int oldWarden, int newWarden)
{
	AJB_Hud_PaintAll();
}

public void AJB_OnRoundStateChange(AJBRoundState oldState, AJBRoundState newState)
{
	AJB_Hud_PaintAll();
}

public void AJB_OnRebel(int client, bool isRebel)
{
	AJB_Hud_PaintAll();
}

public void AJB_OnCellsOpened()
{
	AJB_Hud_PaintAll();
}

// =========================================================================================================
// Timer / draw
// =========================================================================================================

void AJB_Hud_StartTimer()
{
	AJB_Hud_StopTimer();
	g_hRefreshTimer = CreateTimer(HUD_REFRESH, Timer_HudRefresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void AJB_Hud_StopTimer()
{
	if (g_hRefreshTimer != null)
	{
		delete g_hRefreshTimer;
		g_hRefreshTimer = null;
	}
}

Action Timer_HudRefresh(Handle timer)
{
	AJB_Hud_PaintAll();
	return Plugin_Continue;
}

void AJB_Hud_PaintAll()
{
	if (!g_cvEnabled.BoolValue || !g_bHasCore || !AJB_IsEnabled())
	{
		return;
	}

	char line[256];
	AJB_Hud_BuildLine(line, sizeof(line));

	// HUD params are global draw state for the following ShowSyncHudText calls, not per-client — set once.
	SetHudTextParams(-1.0, 0.08, HUD_REFRESH + 0.15, 255, 220, 100, 255, 0, 0.0, 0.0, 0.0);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		ShowSyncHudText(i, g_hHudSync, "%s", line);
	}
}

void AJB_Hud_BuildLine(char[] buffer, int maxlen)
{
	AJBRoundState state = AJB_GetRoundState();
	int warden = AJB_GetWarden();

	char stateName[32];
	AJB_Hud_StateName(state, stateName, sizeof(stateName));

	char wardenName[64];
	if (warden > 0 && IsClientInGame(warden))
	{
		GetClientName(warden, wardenName, sizeof(wardenName));
	}
	else
	{
		strcopy(wardenName, sizeof(wardenName), "—");
	}

	int rebels = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && AJB_IsRebel(i))
		{
			rebels++;
		}
	}

	Format(buffer, maxlen, "AJB | %s | Warden: %s | Rebels: %d", stateName, wardenName, rebels);
}

void AJB_Hud_StateName(AJBRoundState state, char[] buffer, int maxlen)
{
	switch (state)
	{
		case AJBState_Disabled:     strcopy(buffer, maxlen, "Off");
		case AJBState_Waiting:      strcopy(buffer, maxlen, "Waiting");
		case AJBState_CellsLocked:  strcopy(buffer, maxlen, "Cells Locked");
		case AJBState_CellsOpen:    strcopy(buffer, maxlen, "Cells Open");
		case AJBState_LRChoosing:   strcopy(buffer, maxlen, "Choosing LR");
		case AJBState_LRChosen:     strcopy(buffer, maxlen, "LR Chosen");
		case AJBState_SpecialDay:   strcopy(buffer, maxlen, "Special Day");
		case AJBState_RoundEnd:     strcopy(buffer, maxlen, "Round End");
		default:                    strcopy(buffer, maxlen, "?");
	}
}
