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
// Dead/alive voice separation (independent of BaseComm global mute).
ConVar g_cvDeadTalk;
ConVar g_cvDeadTalkCrossTeam;
// Admin flag(s) that let a player talk directly to everyone (bypass dead/alive routing).
ConVar g_cvBypassFlags;

bool g_bHasCore;
bool g_bHasBaseComm;

// True if AJB applied the mute (so we only undo our own).
bool g_bAjbMuted[MAXPLAYERS + 1];

// Last-known alive state, so a revive (which may not fire player_spawn) still
// re-runs the voice matrix. Updated by the watchdog timer.
bool g_bWasAlive[MAXPLAYERS + 1];

// A voice-matrix rebuild is queued for next frame; coalesces bursts of life/team
// events (mass slay, round end) into a single O(n^2) rebuild instead of one each.
bool g_bVoiceRefreshQueued;

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
	g_cvDeadTalk = CreateConVar("sm_ajb_mute_deadtalk", "1", "1 = dead players cannot be heard by the living, but hear/talk to each other by voice.", _, true, 0.0, true, 1.0);
	g_cvDeadTalkCrossTeam = CreateConVar("sm_ajb_mute_deadtalk_crossteam", "1", "1 = all dead players hear each other; 0 = only dead teammates (requires sm_ajb_mute_deadtalk 1).", _, true, 0.0, true, 1.0);
	g_cvBypassFlags = CreateConVar("sm_ajb_mute_bypass_flags", "b", "Admin flag(s) that can always talk to/hear everyone regardless of dead/alive (empty = nobody). Default 'b' = generic admin.", _);

	AutoExecConfig(true, "ajb_mutes");

	g_cvEnabled.AddChangeHook(OnMuteCvarChanged);
	g_cvMutePrisoners.AddChangeHook(OnMuteCvarChanged);
	g_cvDeadTalk.AddChangeHook(OnMuteCvarChanged);
	g_cvDeadTalkCrossTeam.AddChangeHook(OnMuteCvarChanged);
	g_cvBypassFlags.AddChangeHook(OnMuteCvarChanged);

	g_bHasCore = LibraryExists(AJB_LIBRARY);
	g_bHasBaseComm = LibraryExists("basecomm");

	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

	// Catch revives (medic resurrect, admin/warden revive) that never fire player_spawn.
	CreateTimer(1.0, Timer_LifeStateWatch, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	if (g_bHasCore)
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
	AJB_Voice_ClearAll();
}

public void OnMapEnd()
{
	g_bVoiceRefreshQueued = false;
	AJB_Mutes_ClearAll(true);
	AJB_Voice_ClearAll();
}

public void OnClientDisconnect(int client)
{
	g_bAjbMuted[client] = false;
	g_bWasAlive[client] = false;
	// A leaver changes the dead/alive matrix for everyone else.
	AJB_Voice_RefreshAll();
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
	// Alive-state changed: recompute who can hear whom.
	AJB_Voice_RefreshAll();
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		// A dead prisoner must lose its BaseComm mute so it can talk to other dead.
		AJB_Mutes_ApplyClient(client);
	}
	AJB_Voice_RefreshAll();
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
	AJB_Voice_RefreshAll();
}

void OnMuteCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	AJB_Mutes_RefreshAll();
}

// Some revive paths (medic resurrect, admin/warden "revive") flip a player back to
// alive without a player_spawn event. Poll life state and refresh when it changes.
Action Timer_LifeStateWatch(Handle timer)
{
	bool changed = false;

	for (int i = 1; i <= MaxClients; i++)
	{
		bool alive = IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i);
		if (alive != g_bWasAlive[i])
		{
			g_bWasAlive[i] = alive;
			changed = true;
		}
	}

	if (changed)
	{
		// A prisoner that got revived must also lose its BaseComm mute.
		AJB_Mutes_RefreshAll();
	}

	return Plugin_Continue;
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

	if (g_cvUnmuteOnLR.BoolValue && AJB_IsLRPhase(state))
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

	// Bypass-flag admins are never globally muted (they may always talk).
	if (AJB_Voice_HasBypass(client))
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

	// Dead players are never globally muted: the dead-voice layer routes them
	// (living can't hear them, other dead can). BaseComm mute would kill both.
	if (!IsPlayerAlive(client))
	{
		return false;
	}

	if (g_cvUnmuteOnFreeday.BoolValue && AJB_IsFreeday(client))
	{
		return false;
	}

	// Rebels may speak (standard JB — status must be audible/usable).
	if (AJB_IsRebel(client))
	{
		return false;
	}

	return true;
}

void AJB_Mutes_RefreshAll()
{
	if (g_bHasBaseComm)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				AJB_Mutes_ApplyClient(i);
			}
		}
	}

	AJB_Voice_RefreshAll();
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

// =========================================================================================================
// Dead / alive voice routing (SetListenOverride)
// Living never hear the dead; the dead hear/talk to each other. Independent of BaseComm mute.
// =========================================================================================================

bool AJB_Voice_Enabled()
{
	if (!g_cvEnabled.BoolValue || !g_cvDeadTalk.BoolValue)
	{
		return false;
	}

	if (!g_bHasCore || !AJB_IsEnabled())
	{
		return false;
	}

	AJBRoundState state = AJB_GetRoundState();
	if (state == AJBState_Disabled || state == AJBState_Waiting)
	{
		return false;
	}

	return true;
}

// Coalesce: many life/team events can fire in the same frame (mass slay, round end,
// mass freekill). Collapse them to a single rebuild on the next frame instead of one
// full O(n^2) SetListenOverride sweep per event.
void AJB_Voice_RefreshAll()
{
	if (g_bVoiceRefreshQueued)
	{
		return;
	}

	g_bVoiceRefreshQueued = true;
	RequestFrame(Frame_VoiceRefresh);
}

void Frame_VoiceRefresh(any data)
{
	g_bVoiceRefreshQueued = false;
	AJB_Voice_DoRefreshAll();
}

void AJB_Voice_DoRefreshAll()
{
	if (!AJB_Voice_Enabled())
	{
		AJB_Voice_ClearAll();
		return;
	}

	bool crossTeam = g_cvDeadTalkCrossTeam.BoolValue;

	// Parse the bypass flag string once for the whole matrix, not once per client.
	int need = AJB_Voice_BypassBits();

	// Precompute bypass so we don't re-check it in the inner loop.
	bool bypass[MAXPLAYERS + 1];
	for (int i = 1; i <= MaxClients; i++)
	{
		bypass[i] = AJB_Voice_FlagsMatch(i, need);
	}

	for (int recv = 1; recv <= MaxClients; recv++)
	{
		if (!IsClientInGame(recv) || IsFakeClient(recv))
		{
			continue;
		}

		bool recvDead = !IsPlayerAlive(recv);
		int recvTeam = GetClientTeam(recv);

		for (int send = 1; send <= MaxClients; send++)
		{
			if (send == recv || !IsClientInGame(send) || IsFakeClient(send))
			{
				continue;
			}

			ListenOverride override = Listen_Default;

			if (bypass[send] || bypass[recv])
			{
				// A bypass-flag admin always talks to / hears everyone.
				override = Listen_Yes;
			}
			else if (!IsPlayerAlive(send))
			{
				if (!recvDead)
				{
					// Living never hear the dead.
					override = Listen_No;
				}
				else if (crossTeam || GetClientTeam(send) == recvTeam)
				{
					// Dead hear each other (all dead, or same-team only).
					override = Listen_Yes;
				}
			}

			SetListenOverride(recv, send, override);
		}
	}
}

// Bits for the configured bypass flags (0 = none / empty). Parse once, then reuse
// across the voice matrix instead of re-reading the cvar string per client.
int AJB_Voice_BypassBits()
{
	char flags[32];
	g_cvBypassFlags.GetString(flags, sizeof(flags));
	if (flags[0] == '\0')
	{
		return 0;
	}

	return ReadFlagString(flags);
}

// True if the client holds any of the given bypass bits (root always qualifies).
bool AJB_Voice_FlagsMatch(int client, int need)
{
	if (need == 0 || client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
	{
		return false;
	}

	int have = GetUserFlagBits(client);
	return (have & ADMFLAG_ROOT) != 0 || (have & need) != 0;
}

// True if the client holds any of the configured bypass flags (root always qualifies).
bool AJB_Voice_HasBypass(int client)
{
	return AJB_Voice_FlagsMatch(client, AJB_Voice_BypassBits());
}

void AJB_Voice_ClearAll()
{
	for (int recv = 1; recv <= MaxClients; recv++)
	{
		if (!IsClientInGame(recv) || IsFakeClient(recv))
		{
			continue;
		}

		for (int send = 1; send <= MaxClients; send++)
		{
			if (send == recv || !IsClientInGame(send) || IsFakeClient(send))
			{
				continue;
			}

			SetListenOverride(recv, send, Listen_Default);
		}
	}
}
