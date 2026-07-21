// =========================================================================================================
// Another Jailbreak — Voice / mute module
// Mutes prisoners during active jail rounds via BaseComm. Does not replace admin mutes.
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
#include <basecomm>
#define REQUIRE_PLUGIN

// =========================================================================================================
// Constants
// =========================================================================================================

#define PLUGIN_VERSION "1.0.0"

// =========================================================================================================
// Plugin info
// =========================================================================================================

public Plugin myinfo =
{
	name        = "Another Jailbreak - Mutes",
	author      = "SummerTYT",
	description = "Another Jailbreak — prisoner mute / voice rules (BaseComm).",
	version     = PLUGIN_VERSION,
	url         = ""
};

// =========================================================================================================
// ConVars / state
// =========================================================================================================

ConVar g_cvEnabled;
ConVar g_cvMutePrisoners;
ConVar g_cvUnmuteOnFreeday;
ConVar g_cvUnmuteOnLR;

bool g_bHasCore;
bool g_bHasBaseComm;

// True if AJB applied the mute (so we only undo our own).
bool g_bAjbMuted[MAXPLAYERS + 1];

// =========================================================================================================
// Lifecycle
// =========================================================================================================

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("BaseComm_IsClientMuted");
	MarkNativeAsOptional("BaseComm_SetClientMute");
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_ajb_mute_version", PLUGIN_VERSION, "AJB Mutes module version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_ajb_mute_enabled", "1", "Enable AJB mute rules.", _, true, 0.0, true, 1.0);
	g_cvMutePrisoners = CreateConVar("sm_ajb_mute_prisoners", "1", "1 = mute prisoners while jail round is active.", _, true, 0.0, true, 1.0);
	g_cvUnmuteOnFreeday = CreateConVar("sm_ajb_mute_unmute_freeday", "1", "1 = do not mute freeday prisoners.", _, true, 0.0, true, 1.0);
	g_cvUnmuteOnLR = CreateConVar("sm_ajb_mute_unmute_lr", "1", "1 = unmute when round enters Last Request.", _, true, 0.0, true, 1.0);

	AutoExecConfig(true, "ajb_mutes");

	g_cvEnabled.AddChangeHook(OnMuteCvarChanged);
	g_cvMutePrisoners.AddChangeHook(OnMuteCvarChanged);

	g_bHasCore = LibraryExists(AJB_LIBRARY);
	g_bHasBaseComm = LibraryExists("basecomm");

	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

	if (g_bHasCore && g_bHasBaseComm)
	{
		AJB_Mutes_RefreshAll();
	}

	LogMessage("[AJB-Mutes] loaded (core=%s basecomm=%s).",
		g_bHasCore ? "yes" : "no",
		g_bHasBaseComm ? "yes" : "no");
}

public void OnPluginEnd()
{
	AJB_Mutes_ClearAll(true);
}

public void OnMapEnd()
{
	AJB_Mutes_ClearAll(true);
}

public void OnClientDisconnect(int client)
{
	g_bAjbMuted[client] = false;
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = true;
		AJB_Mutes_RefreshAll();
	}
	else if (StrEqual(name, "basecomm"))
	{
		g_bHasBaseComm = true;
		AJB_Mutes_RefreshAll();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = false;
		AJB_Mutes_ClearAll(true);
	}
	else if (StrEqual(name, "basecomm"))
	{
		g_bHasBaseComm = false;
		for (int i = 1; i <= MaxClients; i++)
		{
			g_bAjbMuted[i] = false;
		}
	}
}

// =========================================================================================================
// Core forwards
// =========================================================================================================

public void AJB_OnRoundStateChange(AJBRoundState oldState, AJBRoundState newState)
{
	AJB_Mutes_RefreshAll();
}

public void AJB_OnWardenChanged(int oldWarden, int newWarden)
{
	AJB_Mutes_RefreshAll();
}

public void AJB_OnRebel(int client, bool isRebel)
{
	AJB_Mutes_ApplyClient(client);
}

// =========================================================================================================
// Events
// =========================================================================================================

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		AJB_Mutes_ApplyClient(client);
	}
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		RequestFrame(Frame_ApplyClient, GetClientUserId(client));
	}
}

void Frame_ApplyClient(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0)
	{
		AJB_Mutes_ApplyClient(client);
	}
}

void OnMuteCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	AJB_Mutes_RefreshAll();
}

// =========================================================================================================
// Policy
// =========================================================================================================

bool AJB_Mutes_ShouldMutePrisoners()
{
	if (!g_cvEnabled.BoolValue || !g_cvMutePrisoners.BoolValue)
	{
		return false;
	}

	if (!g_bHasCore || !g_bHasBaseComm || !AJB_IsEnabled())
	{
		return false;
	}

	AJBRoundState state = AJB_GetRoundState();

	if (state == AJBState_Disabled || state == AJBState_Waiting || state == AJBState_RoundEnd)
	{
		return false;
	}

	if (g_cvUnmuteOnLR.BoolValue && state == AJBState_LastRequest)
	{
		return false;
	}

	if (state == AJBState_SpecialDay)
	{
		return false;
	}

	return true;
}

bool AJB_Mutes_ShouldMuteClient(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
	{
		return false;
	}

	if (!AJB_Mutes_ShouldMutePrisoners())
	{
		return false;
	}

	if (!AJB_IsPrisoner(client))
	{
		return false;
	}

	if (g_cvUnmuteOnFreeday.BoolValue && AJB_IsFreeday(client))
	{
		return false;
	}

	return true;
}

void AJB_Mutes_RefreshAll()
{
	if (!g_bHasBaseComm)
	{
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			AJB_Mutes_ApplyClient(i);
		}
	}
}

void AJB_Mutes_ApplyClient(int client)
{
	if (!g_bHasBaseComm || client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}

	bool wantMute = AJB_Mutes_ShouldMuteClient(client);

	if (wantMute)
	{
		AJB_Mutes_Mute(client);
	}
	else
	{
		AJB_Mutes_UnmuteIfOurs(client);
	}
}

void AJB_Mutes_Mute(int client)
{
	if (BaseComm_IsClientMuted(client))
	{
		if (!g_bAjbMuted[client])
		{
			return;
		}
		return;
	}

	if (BaseComm_SetClientMute(client, true))
	{
		g_bAjbMuted[client] = true;
	}
}

void AJB_Mutes_UnmuteIfOurs(int client)
{
	if (!g_bAjbMuted[client])
	{
		return;
	}

	if (BaseComm_IsClientMuted(client))
	{
		BaseComm_SetClientMute(client, false);
	}

	g_bAjbMuted[client] = false;
}

void AJB_Mutes_ClearAll(bool unmute)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bAjbMuted[i])
		{
			continue;
		}

		if (unmute && g_bHasBaseComm && IsClientInGame(i) && BaseComm_IsClientMuted(i))
		{
			BaseComm_SetClientMute(i, false);
		}

		g_bAjbMuted[i] = false;
	}
}
