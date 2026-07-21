// =========================================================================================================
// Another Jailbreak (AJB) — Core mode plugin for Team Fortress 2
// Owns round lifecycle, teams, warden, rules, doors, native timer bridge, and public API.
// Feature modules load from plugins/ajb/*.smx and talk through include/ajb/ajb.inc.
// =========================================================================================================

#pragma semicolon 1
#pragma newdecls required

// =========================================================================================================
// Imports
// =========================================================================================================

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>

#include <ajb/enums>
#include <ajb/constants>
#include <ajb/phrases>

// =========================================================================================================
// Plugin info
// =========================================================================================================

public Plugin myinfo =
{
	name        = "Another Jailbreak",
	author      = "SummerTYT",
	description = "TF2-native jailbreak core (Another Jailbreak). Modules live under plugins/ajb/.",
	version     = AJB_PLUGIN_VERSION,
	url         = ""
};

// =========================================================================================================
// ConVars
// =========================================================================================================

ConVar g_cvEnabled;
ConVar g_cvMapPrefix;
ConVar g_cvForce;
ConVar g_cvGuardsTeam;
ConVar g_cvPrisonersTeam;
ConVar g_cvGuardRatio;
ConVar g_cvCellsAutoOpen;
ConVar g_cvWardenAuto;
ConVar g_cvRebelOnDamage;
ConVar g_cvStripPrisoners;
ConVar g_cvBlockBuildings;
ConVar g_cvBlockPrisonerDamage;
ConVar g_cvPrepTime;

// =========================================================================================================
// Runtime state
// =========================================================================================================

bool g_bModeActive;
AJBRoundState g_RoundState = AJBState_Disabled;

int g_iWarden;
bool g_bRebel[MAXPLAYERS + 1];
bool g_bFreeday[MAXPLAYERS + 1];
// Individual "wish" freeday: granted this round, active NEXT round only.
bool g_bFreedayPending[MAXPLAYERS + 1];
bool g_bSDKHooked[MAXPLAYERS + 1];

// One-shot per round so LR modules are not spammed every death tick.
bool g_bLastPrisonerAnnounced;

char g_sDoorNames[AJB_MAX_DOOR_NAMES][AJB_MAX_DOOR_NAME_LEN];
int g_iDoorNameCount;

Handle g_hFwdRoundState;
Handle g_hFwdWarden;
Handle g_hFwdRebel;
Handle g_hFwdCellsOpened;
Handle g_hFwdCellsClosed;
Handle g_hFwdLastPrisoner;

Handle g_hCellsAutoTimer;

// Prep window state lives in core_prep.sp (g_bPrepActive, timers).

// =========================================================================================================
// Core fragments (same compile unit)
// =========================================================================================================

#include "ajb/core_mode.sp"
#include "ajb/core_teams.sp"
#include "ajb/core_rounds.sp"
#include "ajb/core_warden.sp"
#include "ajb/core_rules.sp"
#include "ajb/core_weapons.sp"
#include "ajb/core_doors.sp"
#include "ajb/core_timer.sp"
#include "ajb/core_prep.sp"
#include "ajb/core_api.sp"

// =========================================================================================================
// Lifecycle
// =========================================================================================================

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_TF2)
	{
		strcopy(error, err_max, "Another Jailbreak is TF2-only.");
		return APLRes_Failure;
	}

	RegPluginLibrary(AJB_LIBRARY);
	AJB_RegisterNatives();
	AJB_CreateForwards();
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations(AJB_TRANSLATIONS_FILE);
	LoadTranslations("common.phrases");

	CreateConVar("sm_ajb_version", AJB_PLUGIN_VERSION, "Another Jailbreak version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	g_cvEnabled = CreateConVar("sm_ajb_enabled", "1", "Master switch for Another Jailbreak.", _, true, 0.0, true, 1.0);
	g_cvMapPrefix = CreateConVar("sm_ajb_map_prefix", "jb_", "Map name prefix that enables AJB (empty = never by prefix).", _);
	g_cvForce = CreateConVar("sm_ajb_force", "0", "1 = force AJB on even if the map prefix does not match.", _, true, 0.0, true, 1.0);
	g_cvGuardsTeam = CreateConVar("sm_ajb_guards_team", "3", "Team index for guards (TF2 BLU = 3).", _, true, 2.0, true, 3.0);
	g_cvPrisonersTeam = CreateConVar("sm_ajb_prisoners_team", "2", "Team index for prisoners (TF2 RED = 2).", _, true, 2.0, true, 3.0);
	// Reserved for Phase 1+ autobalance; exposed now so cfg/ajb.cfg is stable.
	g_cvGuardRatio = CreateConVar("sm_ajb_guard_ratio", "3", "Target prisoners per guard for soft balance hints (0 = disable). Not enforced yet.", _, true, 0.0);
	g_cvCellsAutoOpen = CreateConVar("sm_ajb_cells_auto_open", "0", "Seconds after round start before cells auto-open (0 = manual only). Uses team_round_timer when possible.", _, true, 0.0);
	g_cvWardenAuto = CreateConVar("sm_ajb_warden_auto", "0", "1 = auto-assign a random living guard as warden when none is set.", _, true, 0.0, true, 1.0);
	g_cvRebelOnDamage = CreateConVar("sm_ajb_rebel_on_damage", "1", "1 = mark prisoner as rebel when they damage a guard.", _, true, 0.0, true, 1.0);
	g_cvStripPrisoners = CreateConVar("sm_ajb_strip_prisoners", "1", "1 = strip prisoners to melee on spawn.", _, true, 0.0, true, 1.0);
	g_cvBlockBuildings = CreateConVar("sm_ajb_block_buildings", "1", "1 = block Engineer building placement while AJB is active.", _, true, 0.0, true, 1.0);
	g_cvBlockPrisonerDamage = CreateConVar("sm_ajb_block_prisoner_damage", "1", "1 = block non-rebel prisoner damage to guards (freeday does not bypass this).", _, true, 0.0, true, 1.0);
	g_cvPrepTime = CreateConVar("sm_ajb_prep_time", "10", "Preparation seconds at round start: BLU can move, RED stay frozen in cells (0 = off).", _, true, 0.0, true, 60.0);

	AutoExecConfig(true, "ajb");

	g_cvEnabled.AddChangeHook(OnAjbCvarChanged);
	g_cvForce.AddChangeHook(OnAjbCvarChanged);
	g_cvMapPrefix.AddChangeHook(OnAjbCvarChanged);

	RegConsoleCmd("sm_w", Command_Warden, "Claim warden (guards only).");
	RegConsoleCmd("sm_warden", Command_Warden, "Claim warden (guards only).");
	RegConsoleCmd("sm_uw", Command_UnWarden, "Resign warden.");
	RegConsoleCmd("sm_unwarden", Command_UnWarden, "Resign warden.");
	RegConsoleCmd("sm_open", Command_OpenCells, "Open cell doors (warden or admin).");
	RegConsoleCmd("sm_close", Command_CloseCells, "Close cell doors (warden or admin).");

	RegAdminCmd("sm_ajb_setwarden", Command_AdminSetWarden, ADMFLAG_GENERIC, "Usage: sm_ajb_setwarden <#userid|name>");
	RegAdminCmd("sm_ajb_rebel", Command_AdminRebel, ADMFLAG_GENERIC, "Usage: sm_ajb_rebel <#userid|name> [0|1]");

	HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("teamplay_round_win", Event_RoundWin, EventHookMode_Post);
	HookEvent("teamplay_waiting_begins", Event_WaitingBegins, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("player_builtobject", Event_PlayerBuiltObject, EventHookMode_Pre);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			AJB_HookClient(i);
		}
	}

	RegAdminCmd("sm_ajb_doors_reload", Command_DoorsReload, ADMFLAG_CONFIG, "Reload per-map door targetnames.");
	RegAdminCmd("sm_ajb_doors_list", Command_DoorsList, ADMFLAG_CONFIG, "List configured door targetnames.");

	AJB_RefreshModeActive();
	if (g_bModeActive)
	{
		AJB_SetRoundState(AJBState_Waiting);
		AJB_LoadMapDoors();
		AJB_HookAllClients();
	}
	else
	{
		AJB_UnhookAllClients();
	}

	LogMessage("[AJB] Another Jailbreak %s loaded (mode %s, guard_ratio=%d).", AJB_PLUGIN_VERSION, g_bModeActive ? "active" : "inactive", g_cvGuardRatio.IntValue);
}

public void OnPluginEnd()
{
	AJB_Prep_Stop(false);
	AJB_ClearPhaseTimer();
	AJB_KillCellsAutoTimer();
	AJB_ClearWarden(false);
}

public void OnMapStart()
{
	AJB_RefreshModeActive();
	AJB_ResetPlayerFlags();
	AJB_ClearWarden(false);
	AJB_Prep_Stop(false);
	AJB_KillCellsAutoTimer();
	AJB_ClearPhaseTimer();
	g_iDoorNameCount = 0;

	if (g_bModeActive)
	{
		AJB_LoadMapDoors();
		AJB_SetRoundState(AJBState_Waiting);
		AJB_HookAllClients();
	}
	else
	{
		AJB_SetRoundState(AJBState_Disabled);
		AJB_UnhookAllClients();
	}
}

public void OnMapEnd()
{
	AJB_Prep_Stop(false);
	AJB_KillCellsAutoTimer();
	AJB_ClearPhaseTimer();
	AJB_ClearWarden(false);
	g_bModeActive = false;
	g_RoundState = AJBState_Disabled;
}

public void OnClientPutInServer(int client)
{
	AJB_ResetClientFlags(client);
	g_bFreedayPending[client] = false;
	AJB_HookClient(client);
}

public void OnClientDisconnect(int client)
{
	if (g_iWarden == client)
	{
		AJB_ClearWarden(true);
	}

	AJB_ResetClientFlags(client);
	g_bFreedayPending[client] = false;
	AJB_UnhookClient(client);

	// After disconnect, re-check win / last-prisoner (suicide/disconnect edge cases).
	if (g_bModeActive)
	{
		CreateTimer(0.15, Timer_PostDeathChecks, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

// =========================================================================================================
// Cvar change
// =========================================================================================================

void OnAjbCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	bool wasActive = g_bModeActive;
	AJB_RefreshModeActive();

	if (g_bModeActive && !wasActive)
	{
		AJB_LoadMapDoors();
		AJB_SetRoundState(AJBState_Waiting);
		AJB_HookAllClients();
		LogMessage("[AJB] Mode enabled mid-session.");
	}
	else if (!g_bModeActive && wasActive)
	{
		AJB_KillCellsAutoTimer();
		AJB_ClearPhaseTimer();
		AJB_ClearWarden(false);
		AJB_SetRoundState(AJBState_Disabled);
		AJB_UnhookAllClients();
		LogMessage("[AJB] Mode disabled mid-session.");
	}
}

// =========================================================================================================
// Admin door helpers (core; full admin UI lives in ajb_admin module)
// =========================================================================================================

Action Command_DoorsReload(int client, int args)
{
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}

	AJB_LoadMapDoors();

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	ReplyToCommand(client, "%T", "Doors Reloaded", AJB_TransTarget(client), prefix, g_iDoorNameCount);
	return Plugin_Handled;
}

Action Command_DoorsList(int client, int args)
{
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	ReplyToCommand(client, "%T", "Doors List Header", AJB_TransTarget(client), prefix, g_iDoorNameCount);
	for (int i = 0; i < g_iDoorNameCount; i++)
	{
		ReplyToCommand(client, "  [%d] %s", i + 1, g_sDoorNames[i]);
	}
	return Plugin_Handled;
}
