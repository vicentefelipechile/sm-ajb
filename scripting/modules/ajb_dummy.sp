// =========================================================================================================
// Another Jailbreak — Dummy module (Passive API Smoke Test & Diagnostics)
// Strictly informational and read-only. Proves API attach/detach and logs forwards
// without interfering in gameplay or modifying game state.
// =========================================================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#undef REQUIRE_PLUGIN
#include <ajb/ajb>
#define REQUIRE_PLUGIN

#define PLUGIN_VERSION "1.2.0"

public Plugin myinfo =
{
	name        = "Another Jailbreak - Dummy & Diagnostics",
	author      = "SummerTYT",
	description = "Another Jailbreak — Passive API smoke test & read-only diagnostic module.",
	version     = PLUGIN_VERSION,
	url         = ""
};

bool g_bHasCore;
bool g_bHudEnabled[MAXPLAYERS + 1];
Handle g_hDebugHudTimer = null;
Handle g_hHudSync = null;

public void OnPluginStart()
{
	CreateConVar("sm_ajb_dummy_version", PLUGIN_VERSION, "AJB Dummy module version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	// Strictly informational commands
	RegAdminCmd("sm_ajb_dummy_status", Command_DummyStatus, ADMFLAG_GENERIC, "Print AJB status info from dummy module.");
	RegAdminCmd("sm_ajb_dummy_inspect", Command_Inspect, ADMFLAG_GENERIC, "Inspect detailed AJB player state: sm_ajb_dummy_inspect <target>");
	RegAdminCmd("sm_ajb_dummy_hud", Command_ToggleHud, ADMFLAG_GENERIC, "Toggle passive real-time AJB debug HUD overlay.");

	g_hHudSync = CreateHudSynchronizer();

	g_bHasCore = LibraryExists(AJB_LIBRARY);
	if (g_bHasCore)
	{
		LogMessage("[AJB-Dummy] attached | enabled=%d state=%d warden=%d",
			AJB_IsEnabled(),
			view_as<int>(AJB_GetRoundState()),
			AJB_GetWarden());
	}
	else
	{
		LogMessage("[AJB-Dummy] core missing at load (will attach on OnLibraryAdded).");
	}
}

public void OnClientDisconnect(int client)
{
	g_bHudEnabled[client] = false;
	EnsureDebugHudTimer();
}

public void OnPluginEnd()
{
	if (g_hDebugHudTimer != null)
	{
		delete g_hDebugHudTimer;
		g_hDebugHudTimer = null;
	}
	LogMessage("[AJB-Dummy] unload clean.");
}

public void OnLibraryAdded(const char[] name)
{
	if (!StrEqual(name, AJB_LIBRARY))
	{
		return;
	}

	g_bHasCore = true;
	LogMessage("[AJB-Dummy] core late-attached | enabled=%d", AJB_IsEnabled());
}

public void OnLibraryRemoved(const char[] name)
{
	if (!StrEqual(name, AJB_LIBRARY))
	{
		return;
	}

	g_bHasCore = false;
	LogMessage("[AJB-Dummy] core removed — module stays loaded, natives avoided.");
}

// =========================================================================================================
// Read-Only Informational Commands
// =========================================================================================================

Action Command_DummyStatus(int client, int args)
{
	if (!g_bHasCore)
	{
		ReplyToCommand(client, "[AJB-Dummy] Core library is not attached.");
		return Plugin_Handled;
	}

	ReplyToCommand(client, "[AJB-Dummy] Status Report:");
	ReplyToCommand(client, " - Core Enabled: %s", AJB_IsEnabled() ? "Yes" : "No");
	ReplyToCommand(client, " - Round State: %d", view_as<int>(AJB_GetRoundState()));
	ReplyToCommand(client, " - Warden Index: %d", AJB_GetWarden());
	ReplyToCommand(client, " - Is Combat Day: %s", AJB_IsCombatDay() ? "Yes" : "No");
	ReplyToCommand(client, " - Is Freeday Cosmetic: %s", AJB_IsFreedayAllCosmetic() ? "Yes" : "No");

	return Plugin_Handled;
}

Action Command_Inspect(int client, int args)
{
	if (!g_bHasCore)
	{
		ReplyToCommand(client, "[AJB-Dummy] Core library is not attached.");
		return Plugin_Handled;
	}

	if (args < 1)
	{
		ReplyToCommand(client, "[AJB-Dummy] Usage: sm_ajb_dummy_inspect <target>");
		return Plugin_Handled;
	}

	char arg1[64];
	GetCmdArg(1, arg1, sizeof(arg1));

	int target = FindTarget(client, arg1, true, false);
	if (target == -1)
	{
		return Plugin_Handled;
	}

	char name[MAX_NAME_LENGTH];
	GetClientName(target, name, sizeof(name));

	ReplyToCommand(client, "[AJB-Dummy] Inspection Report for '%s' (Client %d):", name, target);
	ReplyToCommand(client, " - Is In Game: %s", IsClientInGame(target) ? "Yes" : "No");
	ReplyToCommand(client, " - Is Alive: %s", IsPlayerAlive(target) ? "Yes" : "No");
	ReplyToCommand(client, " - Team: %d (Guard=%s, Prisoner=%s)",
		GetClientTeam(target),
		AJB_IsGuard(target) ? "Yes" : "No",
		AJB_IsPrisoner(target) ? "Yes" : "No");
	ReplyToCommand(client, " - Is Warden: %s", (AJB_GetWarden() == target) ? "Yes" : "No");
	ReplyToCommand(client, " - Is Rebel: %s", AJB_IsRebel(target) ? "Yes" : "No");
	ReplyToCommand(client, " - Is Freeday (Active): %s", AJB_IsFreeday(target) ? "Yes" : "No");
	ReplyToCommand(client, " - Is Freeday (Pending): %s", AJB_IsFreedayPending(target) ? "Yes" : "No");

	return Plugin_Handled;
}

// =========================================================================================================
// Passive Real-Time Debug Overlay HUD (For Admins)
// =========================================================================================================

Action Command_ToggleHud(int client, int args)
{
	if (client < 1 || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}

	g_bHudEnabled[client] = !g_bHudEnabled[client];
	ReplyToCommand(client, "[AJB-Dummy] Real-time Debug HUD overlay %s.", g_bHudEnabled[client] ? "ENABLED" : "DISABLED");

	EnsureDebugHudTimer();
	return Plugin_Handled;
}

void EnsureDebugHudTimer()
{
	bool anyActive = false;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bHudEnabled[i] && IsClientInGame(i))
		{
			anyActive = true;
			break;
		}
	}

	if (anyActive && g_hDebugHudTimer == null)
	{
		g_hDebugHudTimer = CreateTimer(0.5, Timer_DebugHud, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	else if (!anyActive && g_hDebugHudTimer != null)
	{
		delete g_hDebugHudTimer;
		g_hDebugHudTimer = null;
	}
}

Action Timer_DebugHud(Handle timer)
{
	if (!g_bHasCore)
	{
		return Plugin_Continue;
	}

	int warden = AJB_GetWarden();
	char wardenName[32] = "None";
	if (warden > 0 && IsClientInGame(warden))
	{
		GetClientName(warden, wardenName, sizeof(wardenName));
	}

	char hudText[256];
	Format(hudText, sizeof(hudText),
		"--- AJB REAL-TIME DEBUG ---\nCore: %s | State: %d\nWarden: %s (#%d)\nCombatDay: %s | FreedayAll: %s\nRebelOnHit: %s",
		AJB_IsEnabled() ? "ENABLED" : "DISABLED",
		view_as<int>(AJB_GetRoundState()),
		wardenName, warden,
		AJB_IsCombatDay() ? "Yes" : "No",
		AJB_IsFreedayAllCosmetic() ? "Yes" : "No",
		AJB_GetRebelOnHit() ? "Yes" : "No");

	SetHudTextParams(0.02, 0.25, 0.6, 0, 255, 255, 255, 0, 0.0, 0.0, 0.0);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bHudEnabled[i] && IsClientInGame(i))
		{
			ShowSyncHudText(i, g_hHudSync, "%s", hudText);
		}
	}

	return Plugin_Continue;
}

// =========================================================================================================
// Purely Passive Event Forwards Audit Logging (100% Read-Only)
// =========================================================================================================

public void AJB_OnRoundStateChange(AJBRoundState oldState, AJBRoundState newState)
{
	LogMessage("[AJB-Dummy] OnRoundStateChange %d -> %d", view_as<int>(oldState), view_as<int>(newState));
}

public void AJB_OnLiveRoundBegin()
{
	LogMessage("[AJB-Dummy] OnLiveRoundBegin");
}

public void AJB_OnRoundWin(int team)
{
	LogMessage("[AJB-Dummy] OnRoundWin team=%d", team);
}

public void AJB_OnPhaseTimerExpired()
{
	LogMessage("[AJB-Dummy] OnPhaseTimerExpired");
}

public void AJB_OnModeChanged(bool enabled)
{
	LogMessage("[AJB-Dummy] OnModeChanged enabled=%d", enabled);
}

public void AJB_OnPrepStart(float duration)
{
	LogMessage("[AJB-Dummy] OnPrepStart duration=%.1f", duration);
}

public void AJB_OnPrepEnd()
{
	LogMessage("[AJB-Dummy] OnPrepEnd");
}

public void AJB_OnWardenChanged(int oldWarden, int newWarden)
{
	LogMessage("[AJB-Dummy] OnWardenChanged %d -> %d", oldWarden, newWarden);
}

public void AJB_OnWardenGiveLR(int warden)
{
	LogMessage("[AJB-Dummy] OnWardenGiveLR warden=%d", warden);
}

public void AJB_OnCellsOpened()
{
	LogMessage("[AJB-Dummy] OnCellsOpened");
}

public void AJB_OnCellsClosed()
{
	LogMessage("[AJB-Dummy] OnCellsClosed");
}

public void AJB_OnLastPrisoner(int client)
{
	LogMessage("[AJB-Dummy] OnLastPrisoner client=%d", client);
}

public void AJB_OnWardenMarkerPlaced(int warden)
{
	LogMessage("[AJB-Dummy] OnWardenMarkerPlaced warden=%d", warden);
}

public void AJB_OnRebel(int client, bool isRebel)
{
	LogMessage("[AJB-Dummy] OnRebel client=%d isRebel=%d", client, isRebel);
}

public void AJB_OnFreedayChanged(int client, bool freeday, bool isPending)
{
	LogMessage("[AJB-Dummy] OnFreedayChanged client=%d freeday=%d pending=%d", client, freeday, isPending);
}

public void AJB_OnGuardBounced(int client)
{
	LogMessage("[AJB-Dummy] OnGuardBounced client=%d", client);
}

public void AJB_OnCombatDayStart()
{
	LogMessage("[AJB-Dummy] OnCombatDayStart");
}

public void AJB_OnFreedayAllStart()
{
	LogMessage("[AJB-Dummy] OnFreedayAllStart");
}

public void AJB_OnFriendlyFireChanged(bool enabled)
{
	LogMessage("[AJB-Dummy] OnFriendlyFireChanged enabled=%d", enabled);
}

public void AJB_OnTeamPushChanged(bool enabled)
{
	LogMessage("[AJB-Dummy] OnTeamPushChanged enabled=%d", enabled);
}

public void AJB_OnFreekillDetected(int attacker, int victimCount)
{
	LogMessage("[AJB-Dummy] OnFreekillDetected attacker=%d victims=%d", attacker, victimCount);
}
