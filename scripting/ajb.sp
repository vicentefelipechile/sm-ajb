// =========================================================================================================
// Another Jailbreak (AJB) — TF2 core mode
// =========================================================================================================

#pragma semicolon 1
#pragma newdecls required

// =========================================================================================================
// Imports
// =========================================================================================================

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <tf2>
#include <tf2_stocks>

#undef REQUIRE_PLUGIN
#include <tf2attributes>
#define REQUIRE_PLUGIN

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
ConVar g_cvForce;
ConVar g_cvGuardsTeam;
ConVar g_cvPrisonersTeam;
ConVar g_cvGuardRatio;
ConVar g_cvCellsAutoOpen;
ConVar g_cvWardenAuto;
ConVar g_cvWardenAutoDelay;
ConVar g_cvWardenAutoMode;
ConVar g_cvRebelOnDamage;
ConVar g_cvRebelOnWardenDamage;
ConVar g_cvWardenRebelControl;
// When false, prisoner→guard hits never auto-rebel (used by LR “Hot Reds”).
bool g_bRebelOnHit = true;
ConVar g_cvStripPrisoners;
ConVar g_cvBlockBuildings;
ConVar g_cvBlockPrisonerDamage;
ConVar g_cvDoorAuto;
ConVar g_cvDoorAutoRadius;
ConVar g_cvGenConfig;
ConVar g_cvPrepTime;
ConVar g_cvRoundTime;

// =========================================================================================================
// Runtime state
// =========================================================================================================

bool g_bModeActive;
AJBRoundState g_RoundState = AJBState_Disabled;

int g_iWarden;
int g_iWardenLastRound[MAXPLAYERS + 1];
int g_iWardenRoundSerial;
int g_iWardenMenuPage[MAXPLAYERS + 1];   // current page of the paged warden menu
bool g_bRebel[MAXPLAYERS + 1];
bool g_bFreeday[MAXPLAYERS + 1];
bool g_bFreedayPending[MAXPLAYERS + 1];
bool g_bSDKHooked[MAXPLAYERS + 1];

bool g_bLastPrisonerAnnounced;

char g_sDoorNames[AJB_MAX_DOOR_NAMES][AJB_MAX_DOOR_NAME_LEN];
int g_iDoorNameCount;

int g_iDoorHammerIds[AJB_MAX_DOOR_NAMES];
int g_iDoorHammerCount;

Handle g_hFwdRoundState;
Handle g_hFwdWarden;
Handle g_hFwdRebel;
Handle g_hFwdCellsOpened;
Handle g_hFwdCellsClosed;
Handle g_hFwdLastPrisoner;
Handle g_hFwdWardenGiveLR;
// Fired when the live round begins (after prep, or immediately if prep is 0).
Handle g_hFwdLiveRoundBegin;

Handle g_hCellsAutoTimer;

// =========================================================================================================
// Core fragments
// =========================================================================================================

#include "ajb/core_mode.sp"
#include "ajb/core_teams.sp"
#include "ajb/core_balance.sp"
#include "ajb/core_settings.sp"
#include "ajb/core_rounds.sp"
#include "ajb/core_warden_marker.sp"
#include "ajb/core_warden_votes.sp"
#include "ajb/core_collisions.sp"
#include "ajb/core_friendlyfire.sp"
#include "ajb/core_warden.sp"
#include "ajb/core_warden_health.sp"
#include "ajb/core_rules.sp"
#include "ajb/core_weapons.sp"
#include "ajb/core_doors.sp"
#include "ajb/core_timer.sp"
#include "ajb/core_prep.sp"
#include "ajb/core_movement.sp"
#include "ajb/core_sentry.sp"
#include "ajb/core_freekill.sp"
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
	g_cvForce = CreateConVar("sm_ajb_force", "0", "1 = force AJB on even if the map prefix does not match. Prefixes live in configs/ajb/settings.cfg (map_prefixes).", _, true, 0.0, true, 1.0);
	g_cvGuardsTeam = CreateConVar("sm_ajb_guards_team", "3", "Team index for guards (TF2 BLU = 3).", _, true, 2.0, true, 3.0);
	g_cvPrisonersTeam = CreateConVar("sm_ajb_prisoners_team", "2", "Team index for prisoners (TF2 RED = 2).", _, true, 2.0, true, 3.0);
	// Enforced by core_balance: guards are capped to ~1 per this many prisoners (0 = no cap).
	g_cvGuardRatio = CreateConVar("sm_ajb_guard_ratio", "2", "Prisoners per guard for team balance: guards are capped to ~1 per this many prisoners (0 = disable cap).", _, true, 0.0);
	g_cvCellsAutoOpen = CreateConVar("sm_ajb_cells_auto_open", "0", "Seconds after round start before cells auto-open (0 = manual only). Uses team_round_timer when possible.", _, true, 0.0);
	g_cvWardenAuto = CreateConVar("sm_ajb_warden_auto", "0", "1 = auto-assign a random living guard as warden when the preround ends and none is set.", _, true, 0.0, true, 1.0);
	g_cvWardenAutoDelay = CreateConVar("sm_ajb_warden_auto_delay", "0", "Seconds to wait after the preround ends before auto-assigning warden (0 = immediately, 1..10 = delay). Requires sm_ajb_warden_auto 1.", _, true, 0.0, true, 10.0);
	g_cvWardenAutoMode = CreateConVar("sm_ajb_warden_auto_mode", "0", "Auto-warden pick: 0 = uniform random, 1 = weighted toward guards who have not been warden recently.", _, true, 0.0, true, 1.0);
	g_cvRebelOnDamage = CreateConVar("sm_ajb_rebel_on_damage", "1", "1 = mark prisoner as rebel when they damage a BLU guard (see sm_ajb_rebel_on_warden_damage for the warden).", _, true, 0.0, true, 1.0);
	g_cvRebelOnWardenDamage = CreateConVar("sm_ajb_rebel_on_warden_damage", "1", "1 = mark prisoner as rebel when they damage the warden. Set this 1 and sm_ajb_rebel_on_damage 0 to let prisoners hit BLU freely except the warden.", _, true, 0.0, true, 1.0);
	g_cvWardenRebelControl = CreateConVar("sm_ajb_warden_rebel_control", "1", "1 = warden can mark/pardon RED rebels from the warden menu.", _, true, 0.0, true, 1.0);
	g_cvStripPrisoners = CreateConVar("sm_ajb_strip_prisoners", "1", "1 = strip prisoners to melee on spawn.", _, true, 0.0, true, 1.0);
	g_cvBlockBuildings = CreateConVar("sm_ajb_block_buildings", "0", "1 = block Engineer buildings while AJB is active (see sm_ajb_allow_sentry for sentry exception). Default 0 = allow builds.", _, true, 0.0, true, 1.0);
	g_cvBlockPrisonerDamage = CreateConVar("sm_ajb_block_prisoner_damage", "1", "1 = block non-rebel prisoner damage to guards (freeday does not bypass this).", _, true, 0.0, true, 1.0);
	g_cvDoorAuto = CreateConVar("sm_ajb_door_auto", "1", "1 = when no cell doors are found by config/name, auto-detect door-like entities near the RED spawn and cache them by map id.", _, true, 0.0, true, 1.0);
	g_cvDoorAutoRadius = CreateConVar("sm_ajb_door_auto_radius", "800", "Max distance from a RED spawn for auto-door detection, in units.", _, true, 64.0);
	g_cvGenConfig = CreateConVar("sm_ajb_gen_config_auto", "1", "1 = auto-generate a per-map config stub (configs/ajb/maps/<map>.cfg) when one does not exist.", _, true, 0.0, true, 1.0);
	g_cvPrepTime = CreateConVar("sm_ajb_prep_time", "10", "Preparation seconds at round start: BLU can move, RED stay frozen in cells (0 = off).", _, true, 0.0, true, 60.0);
	g_cvRoundTime = CreateConVar("sm_ajb_round_time", "600", "Main round HUD duration in seconds (0 = no main clock). Does not force engine wins.", _, true, 0.0);

	AJB_WardenHealth_OnPluginStart();
	AJB_Marker_OnPluginStart();
	AJB_Votes_OnPluginStart();
	// CanPlayerMove detour before mode policy (so policy sees detour active).
	AJB_Movement_OnPluginStart();
	// Sentry FindTarget detour (rebels-only).
	AJB_Sentry_OnPluginStart();
	// Ammo-pack arming for stripped prisoners.
	AJB_Weapons_OnPluginStart();
	AJB_Settings_OnPluginStart();
	AJB_Balance_OnPluginStart();
	AJB_Freekill_OnPluginStart();
	AJB_Collisions_OnPluginStart();
	AJB_FF_OnPluginStart();

	AutoExecConfig(true, "ajb");
	// Mid-map reload: hook packs already in the world (OnMapStart will not re-run).
	AJB_Weapons_OnMapStart();

	g_cvEnabled.AddChangeHook(OnAjbCvarChanged);
	g_cvForce.AddChangeHook(OnAjbCvarChanged);

	// Short alias (only exceptions to sm_ajb_*): /w and !w
	RegConsoleCmd("sm_w", Command_Warden, "Claim warden / open warden menu.");
	RegConsoleCmd("sm_ajb_w", Command_Warden, "Claim warden / open warden menu.");
	RegConsoleCmd("sm_ajb_warden", Command_Warden, "Claim warden / open warden menu.");
	RegConsoleCmd("sm_ajb_menu", Command_WardenMenu, "Open warden menu.");
	RegConsoleCmd("sm_ajb_wm", Command_WardenMenu, "Open warden menu.");
	RegConsoleCmd("sm_ajb_uw", Command_UnWarden, "Resign warden.");
	RegConsoleCmd("sm_ajb_unwarden", Command_UnWarden, "Resign warden.");
	RegConsoleCmd("sm_ajb_open", Command_OpenCells, "Open cell doors (warden or admin).");
	RegConsoleCmd("sm_ajb_close", Command_CloseCells, "Close cell doors (warden or admin).");

	AJB_Freekill_RegisterCommands();

	RegAdminCmd("sm_ajb_balance", Command_AjbBalance, ADMFLAG_GENERIC, "Force the JB team balance now (move excess guards to prisoners).");
	RegAdminCmd("sm_ajb_setwarden", Command_AdminSetWarden, ADMFLAG_GENERIC, "Usage: sm_ajb_setwarden <#userid|name>");
	RegAdminCmd("sm_ajb_rebel", Command_AdminRebel, ADMFLAG_GENERIC, "Usage: sm_ajb_rebel <#userid|name> [0|1]");

	HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("teamplay_round_win", Event_RoundWin, EventHookMode_Post);
	HookEvent("teamplay_waiting_begins", Event_WaitingBegins, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("player_builtobject", Event_PlayerBuiltObject, EventHookMode_Pre);
	// Backup rebel mark when damage actually lands (belt for OnTakeDamage order quirks).
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			AJB_HookClient(i);
		}
	}

	RegAdminCmd("sm_ajb_doors_reload", Command_DoorsReload, ADMFLAG_CONFIG, "Reload per-map doors + teleports (configs/ajb/maps/<map>.cfg).");
	RegAdminCmd("sm_ajb_doors_list", Command_DoorsList, ADMFLAG_CONFIG, "List configured door targetnames.");
	RegAdminCmd("sm_ajb_gen_config", Command_GenConfig, ADMFLAG_CONFIG, "(Re)generate the per-map config stub from live entities (overwrites).");

	AJB_RefreshModeActive();
	if (g_bModeActive)
	{
		AJB_SetRoundState(AJBState_Waiting);
		AJB_LoadMapDoors();
		AJB_HookAllClients();
		// Mid-map reload: restore HUD clock without waiting for next round.
		CreateTimer(0.5, Timer_LateStartRoundClock, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		AJB_UnhookAllClients();
	}

	LogMessage("[AJB] Another Jailbreak %s loaded (mode %s, guard_ratio=%d, tf2attribs=%s).",
		AJB_PLUGIN_VERSION,
		g_bModeActive ? "active" : "inactive",
		g_cvGuardRatio.IntValue,
		g_bTf2Attribs ? "yes" : "no");
}

public void OnAllPluginsLoaded()
{
	g_bTf2Attribs = LibraryExists("tf2attributes");
	if (g_bTf2Attribs && g_iWarden > 0)
	{
		AJB_WardenHealth_Apply(g_iWarden);
	}
}

public void OnLibraryAdded(const char[] name)
{
	AJB_WardenHealth_OnLibraryAdded(name);
}

public void OnLibraryRemoved(const char[] name)
{
	AJB_WardenHealth_OnLibraryRemoved(name);
}

Action Timer_LateStartRoundClock(Handle timer)
{
	// Mid-map plugin reload only: restore the main clock if a round is already live
	// and prep is not owning the HUD. Never steal the prep countdown on map load.
	if (!g_bModeActive || AJB_IsPrepActive())
	{
		return Plugin_Stop;
	}

	if (g_RoundState == AJBState_CellsLocked || g_RoundState == AJBState_CellsOpen
		|| AJB_IsLRPhase(g_RoundState) || g_RoundState == AJBState_SpecialDay)
	{
		if (!AJB_IsRoundExpireTimerActive() && g_cvRoundTime.FloatValue > 0.0)
		{
			AJB_StartRoundClock();
		}
	}
	return Plugin_Stop;
}

public void OnPluginEnd()
{
	AJB_Prep_Stop();
	AJB_ClearPhaseTimer();
	AJB_KillRoundExpireTimer();
	AJB_KillCellsAutoTimer();
	AJB_ClearWarden(false);
	AJB_Sentry_OnPluginEnd();
	AJB_Movement_OnPluginEnd();
	AJB_Collisions_OnPluginEnd();
	AJB_FF_OnPluginEnd();
	// Restore stock engine freeze if fallback changed it.
	g_bModeActive = false;
	AJB_ApplyEngineMovementPolicy();
}

public void OnMapStart()
{
	AJB_Settings_OnMapStart();
	AJB_RefreshModeActive();
	AJB_ResetPlayerFlags();
	AJB_ClearWarden(false);
	AJB_Prep_Stop();
	AJB_KillCellsAutoTimer();
	AJB_ClearPhaseTimer();
	AJB_Timer_OnMapStart();
	AJB_Weapons_OnMapStart();
	AJB_Weapons_OnMapStartLoadout();
	AJB_Marker_OnMapStart();
	g_iDoorNameCount = 0;

	if (g_bModeActive)
	{
		AJB_LoadMapDoors();
		AJB_SetRoundState(AJBState_Waiting);
		AJB_HookAllClients();
		// tf_team entities are ready a beat after map spawn; name them then.
		CreateTimer(1.0, Timer_ApplyTeamNames, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		AJB_SetRoundState(AJBState_Disabled);
		AJB_UnhookAllClients();
	}
}

public void OnMapEnd()
{
	AJB_Prep_Stop();
	AJB_KillCellsAutoTimer();
	AJB_ClearPhaseTimer();
	AJB_ClearWarden(false);
	AJB_Marker_Clear();
	AJB_Votes_Reset();
	g_bModeActive = false;
	g_RoundState = AJBState_Disabled;
}

public void OnClientPutInServer(int client)
{
	AJB_ResetClientFlags(client);
	g_bFreedayPending[client] = false;
	g_iWardenLastRound[client] = 0;
	g_iWardenMenuPage[client] = 0;
	AJB_HookClient(client);
}

public void OnClientDisconnect(int client)
{
	if (g_iWarden == client)
	{
		AJB_ClearWarden(true);
	}

	AJB_Freekill_OnClientDisconnect(client);

	AJB_ResetClientFlags(client);
	g_bFreedayPending[client] = false;
	AJB_UnhookClient(client);

	// Disconnect can decide last-prisoner / round end without a death event.
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

Action Command_GenConfig(int client, int args)
{
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}

	char fileMap[PLATFORM_MAX_PATH];
	AJB_GetShortMapName(fileMap, sizeof(fileMap));

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));

	if (AJB_GenerateMapConfigStub(fileMap, true))
	{
		ReplyToCommand(client, "%s Generated configs/ajb/maps/%s.cfg — prune non-cell doors, then sm_ajb_doors_reload.", prefix, fileMap);
	}
	else
	{
		ReplyToCommand(client, "%s Failed to generate config for %s (see server log).", prefix, fileMap);
	}
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


