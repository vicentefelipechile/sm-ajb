// =========================================================================================================
// Another Jailbreak — Warden voice control and explicit living/dead channels
// =========================================================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>

#undef REQUIRE_PLUGIN
#include <ajb/ajb>
#define REQUIRE_PLUGIN
#include <ajb/phrases>
#include <ajb/voice>

// =========================================================================================================
// State
// =========================================================================================================

#define PLUGIN_VERSION "1.1.0"

ConVar g_cvEnabled;
bool g_bHasCore;
bool g_bWardenMuted[MAXPLAYERS + 1];
bool g_bWasAlive[MAXPLAYERS + 1];
int g_iLastFlags[MAXPLAYERS + 1];
int g_iMuteRevision;
int g_iMenuRevision[MAXPLAYERS + 1];
Handle g_hLifeWatch;
Handle g_hVoiceRefresh;
ListenOverride g_LastVoice[MAXPLAYERS + 1][MAXPLAYERS + 1];

public Plugin myinfo =
{
	name        = "Another Jailbreak - Mutes",
	author      = "SummerTYT",
	description = "Warden mutes and living/dead voice channels; admins always bypass AJB rules.",
	version     = PLUGIN_VERSION,
	url         = ""
};

// =========================================================================================================
// Voice policy
// =========================================================================================================

bool AJB_Voice_Enabled()
{
	if (!g_cvEnabled.BoolValue || !g_bHasCore || !AJB_IsEnabled())
	{
		return false;
	}
	AJBRoundState state = AJB_GetRoundState();
	return state != AJBState_Disabled && state != AJBState_Waiting;
}

void AJB_Mutes_Reset()
{
	g_iMuteRevision++;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bWardenMuted[i] = false;
	}
}

void AJB_Voice_ClearAll()
{
	for (int recv = 1; recv <= MaxClients; recv++)
	{
		for (int send = 1; send <= MaxClients; send++)
		{
			if (g_LastVoice[recv][send] != Listen_Default && recv != send
				&& IsClientInGame(recv) && IsClientInGame(send))
			{
				SetListenOverride(recv, send, Listen_Default);
			}
			g_LastVoice[recv][send] = Listen_Default;
		}
	}
}

void AJB_Voice_RefreshAll()
{
	if (g_hVoiceRefresh == null)
	{
		g_hVoiceRefresh = CreateTimer(0.1, Timer_VoiceRefresh, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

void AJB_Voice_DoRefreshAll()
{
	if (!AJB_Voice_Enabled())
	{
		AJB_Voice_ClearAll();
		return;
	}

	bool ingame[MAXPLAYERS + 1];
	bool alive[MAXPLAYERS + 1];
	bool admin[MAXPLAYERS + 1];
	for (int i = 1; i <= MaxClients; i++)
	{
		ingame[i] = IsClientInGame(i) && !IsFakeClient(i);
		alive[i] = ingame[i] && IsPlayerAlive(i);
		g_bWasAlive[i] = alive[i];
		g_iLastFlags[i] = ingame[i] ? GetUserFlagBits(i) : 0;
		admin[i] = ingame[i] && AJB_Voice_IsAdmin(g_iLastFlags[i]);
	}

	for (int recv = 1; recv <= MaxClients; recv++)
	{
		if (!ingame[recv])
		{
			continue;
		}
		for (int send = 1; send <= MaxClients; send++)
		{
			if (send == recv || !ingame[send])
			{
				continue;
			}

			ListenOverride override = AJB_Voice_GetOverride(alive[send], alive[recv],
				g_bWardenMuted[send], admin[send], admin[recv]);
			if (g_LastVoice[recv][send] != override)
			{
				SetListenOverride(recv, send, override);
				g_LastVoice[recv][send] = override;
			}
		}
	}
}

bool AJB_Mutes_CanControl(int client)
{
	if (client < 1 || !IsClientInGame(client))
	{
		AJB_Reply(client, "Ingame Only");
		return false;
	}
	if (!AJB_Voice_Enabled() || AJB_GetRoundState() == AJBState_RoundEnd)
	{
		AJB_Reply(client, "Mode Inactive");
		return false;
	}
	if (AJB_GetWarden() != client)
	{
		AJB_Reply(client, "Warden Not You");
		return false;
	}
	if (!IsPlayerAlive(client))
	{
		AJB_Reply(client, "Warden Alive Only");
		return false;
	}
	return true;
}

void AJB_Mutes_ShowMenu(int client, int position = 0)
{
	g_iMenuRevision[client] = g_iMuteRevision;
	Menu menu = new Menu(MenuHandler_Mutes);
	menu.SetTitle("%T", "Warden Mutes Title", client);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || i == client)
		{
			continue;
		}
		char info[12], line[160];
		IntToString(GetClientUserId(i), info, sizeof(info));
		char phrase[40] = "Warden Mutes Mute";
		if (!IsPlayerAlive(i))
		{
			strcopy(phrase, sizeof(phrase), g_bWardenMuted[i] ? "Warden Mutes Unmute Dead" : "Warden Mutes Mute Dead");
		}
		else if (g_bWardenMuted[i])
		{
			strcopy(phrase, sizeof(phrase), "Warden Mutes Unmute");
		}
		Format(line, sizeof(line), "%T", phrase, client, i);
		menu.AddItem(info, line);
	}
	menu.ExitBackButton = true;
	menu.DisplayAt(client, position, MENU_TIME_FOREVER);
}

// =========================================================================================================
// Lifecycle
// =========================================================================================================

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	__pl_ajb_SetNTVOptional();
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_ajb_mute_version", PLUGIN_VERSION, "AJB Mutes module version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_ajb_mute_enabled", "1", "Enable warden mutes and living/dead voice channels.", _, true, 0.0, true, 1.0);
	g_cvEnabled.AddChangeHook(OnMuteCvarChanged);
	AutoExecConfig(true, "ajb_mutes");
	LoadTranslations("ajb.phrases");
	LoadTranslations("common.phrases");
	RegConsoleCmd("sm_ajb_mutes", Command_WardenMutes, "Warden: mute/unmute players for this round; admins are exempt.");
	HookEvent("player_spawn", Event_PlayerLife, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerLife, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_Post);
	g_bHasCore = LibraryExists(AJB_LIBRARY);
	AJB_Voice_RefreshAll();
}

public void OnMapStart()
{
	delete g_hLifeWatch;
	g_hLifeWatch = CreateTimer(1.0, Timer_LifeStateWatch, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	AJB_Mutes_Reset();
	AJB_Voice_RefreshAll();
}

public void OnMapEnd()
{
	delete g_hLifeWatch;
	delete g_hVoiceRefresh;
	AJB_Mutes_Reset();
	AJB_Voice_ClearAll();
}

public void OnPluginEnd()
{
	delete g_hLifeWatch;
	delete g_hVoiceRefresh;
	AJB_Voice_ClearAll();
}

public void OnClientPutInServer(int client)
{
	g_bWardenMuted[client] = false;
	g_bWasAlive[client] = false;
	g_iLastFlags[client] = 0;
	AJB_Voice_RefreshAll();
}

public void OnClientPostAdminCheck(int client)
{
	AJB_Voice_RefreshAll();
}

public void OnClientDisconnect(int client)
{
	g_bWardenMuted[client] = false;
	g_bWasAlive[client] = false;
	g_iLastFlags[client] = 0;
	// SDKTools resets disconnected slots; invalidate our matching cache as well.
	for (int i = 1; i <= MaxClients; i++)
	{
		g_LastVoice[client][i] = Listen_Default;
		g_LastVoice[i][client] = Listen_Default;
	}
	AJB_Voice_RefreshAll();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = true;
		AJB_Voice_RefreshAll();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = false;
		AJB_Mutes_Reset();
		AJB_Voice_ClearAll();
	}
}

public void AJB_OnModeChanged(bool enabled)
{
	if (!enabled)
	{
		AJB_Mutes_Reset();
	}
	AJB_Voice_DoRefreshAll();
}

public void AJB_OnRoundStateChange(AJBRoundState oldState, AJBRoundState newState)
{
	if (newState == AJBState_RoundEnd || newState == AJBState_Disabled || newState == AJBState_Waiting)
	{
		AJB_Mutes_Reset();
	}
	AJB_Voice_DoRefreshAll();
}

// =========================================================================================================
// Events / timers
// =========================================================================================================

void Event_PlayerLife(Event event, const char[] name, bool dontBroadcast)
{
	if (StrEqual(name, "player_death") && (event.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER))
	{
		return;
	}
	AJB_Voice_RefreshAll();
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	AJB_Voice_RefreshAll();
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	AJB_Mutes_Reset();
	AJB_Voice_RefreshAll();
}

void OnMuteCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_cvEnabled.BoolValue)
	{
		AJB_Mutes_Reset();
	}
	AJB_Voice_DoRefreshAll();
}

Action Timer_VoiceRefresh(Handle timer)
{
	g_hVoiceRefresh = null;
	AJB_Voice_DoRefreshAll();
	return Plugin_Stop;
}

Action Timer_LifeStateWatch(Handle timer)
{
	if (!AJB_Voice_Enabled())
	{
		return Plugin_Continue;
	}
	bool changed;
	for (int i = 1; i <= MaxClients; i++)
	{
		bool ingame = IsClientInGame(i) && !IsFakeClient(i);
		bool alive = ingame && IsPlayerAlive(i);
		int flags = ingame ? GetUserFlagBits(i) : 0;
		if (alive != g_bWasAlive[i] || flags != g_iLastFlags[i])
		{
			g_bWasAlive[i] = alive;
			g_iLastFlags[i] = flags;
			changed = true;
		}
	}
	if (changed)
	{
		AJB_Voice_RefreshAll();
	}
	return Plugin_Continue;
}

// =========================================================================================================
// Warden interface
// =========================================================================================================

Action Command_WardenMutes(int client, int args)
{
	if (AJB_Mutes_CanControl(client))
	{
		AJB_Mutes_ShowMenu(client);
	}
	return Plugin_Handled;
}

public int MenuHandler_Mutes(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}
	if (action == MenuAction_Cancel)
	{
		if (item == MenuCancel_ExitBack && g_bHasCore && IsClientInGame(client))
		{
			AJB_ShowWardenMenu(client);
		}
		return 0;
	}
	if (action != MenuAction_Select || !AJB_Mutes_CanControl(client))
	{
		return 0;
	}
	if (g_iMenuRevision[client] != g_iMuteRevision)
	{
		AJB_Mutes_ShowMenu(client);
		return 0;
	}

	char info[12];
	menu.GetItem(item, info, sizeof(info));
	int target = GetClientOfUserId(StringToInt(info));
	if (target == 0 || !IsClientInGame(target) || IsFakeClient(target))
	{
		AJB_Chat(client, "Warden Mutes Target Gone");
	}
	else if (AJB_Voice_IsAdmin(GetUserFlagBits(target)))
	{
		AJB_Chat(client, "Warden Mutes Admin Exempt");
	}
	else
	{
		g_bWardenMuted[target] = !g_bWardenMuted[target];
		AJB_Voice_DoRefreshAll();
		AJB_ChatAll2N(g_bWardenMuted[target] ? "Warden Mutes Applied" : "Warden Mutes Removed", client, target);
	}
	AJB_Mutes_ShowMenu(client, menu.Selection);
	return 0;
}
