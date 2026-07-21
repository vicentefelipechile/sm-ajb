// =========================================================================================================
// Another Jailbreak — Special Days module
// Freeday (all prisoners free) + War Day (open combat). Started by warden or admin.
// =========================================================================================================

#pragma semicolon 1
#pragma newdecls required

// =========================================================================================================
// Imports
// =========================================================================================================

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>

#undef REQUIRE_PLUGIN
#include <ajb/ajb>
#define REQUIRE_PLUGIN

#include <ajb/phrases>

// =========================================================================================================
// Constants
// =========================================================================================================

#define PLUGIN_VERSION "1.0.0"

enum AJB_DayType
{
	Day_None = 0,
	Day_Freeday,
	Day_WarDay
};

// =========================================================================================================
// Plugin info
// =========================================================================================================

public Plugin myinfo =
{
	name        = "Another Jailbreak - Days",
	author      = "SummerTYT",
	description = "Another Jailbreak — special days (Freeday, War Day).",
	version     = PLUGIN_VERSION,
	url         = ""
};

// =========================================================================================================
// ConVars / state
// =========================================================================================================

ConVar g_cvEnabled;
ConVar g_cvWardenOnly;

bool g_bHasCore;
AJB_DayType g_ActiveDay;

// =========================================================================================================
// Lifecycle
// =========================================================================================================

public void OnPluginStart()
{
	CreateConVar("sm_ajb_day_version", PLUGIN_VERSION, "AJB Days module version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_ajb_day_enabled", "1", "Enable special days.", _, true, 0.0, true, 1.0);
	g_cvWardenOnly = CreateConVar("sm_ajb_day_warden_only", "1", "1 = only warden (or admins) can start days.", _, true, 0.0, true, 1.0);

	AutoExecConfig(true, "ajb_days");

	LoadTranslations("ajb_days.phrases");
	LoadTranslations("common.phrases");

	RegConsoleCmd("sm_ajb_day", Command_DayMenu, "Open special day menu (warden/admin).");
	RegConsoleCmd("sm_ajb_days", Command_DayMenu, "Open special day menu (warden/admin).");
	RegConsoleCmd("sm_ajb_startfreeday", Command_Freeday, "Start a Freeday day this round.");
	RegConsoleCmd("sm_ajb_startwarday", Command_WarDay, "Start a War Day this round.");
	RegAdminCmd("sm_ajb_day_end", Command_EndDay, ADMFLAG_GENERIC, "End the active special day early.");

	HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("teamplay_round_win", Event_RoundWin, EventHookMode_PostNoCopy);

	g_bHasCore = LibraryExists(AJB_LIBRARY);
	g_ActiveDay = Day_None;

	LogMessage("[AJB-Days] loaded (core %s).", g_bHasCore ? "present" : "missing");
}

public void OnPluginEnd()
{
	AJB_Days_Clear(false);
}

public void OnMapEnd()
{
	AJB_Days_Clear(false);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = true;
		LogMessage("[AJB-Days] core attached.");
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = false;
		g_ActiveDay = Day_None;
		LogMessage("[AJB-Days] core detached.");
	}
}

// =========================================================================================================
// Events
// =========================================================================================================

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_ActiveDay = Day_None;
}

void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
	g_ActiveDay = Day_None;
}

public void AJB_OnRoundStateChange(AJBRoundState oldState, AJBRoundState newState)
{
	if (newState == AJBState_RoundEnd || newState == AJBState_Waiting || newState == AJBState_Disabled)
	{
		g_ActiveDay = Day_None;
	}
}

// =========================================================================================================
// Commands
// =========================================================================================================

Action Command_DayMenu(int client, int args)
{
	if (!AJB_Days_CanUse(client, true))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_Days);
	menu.SetTitle("%T", "Day Menu Title", client);
	menu.AddItem("freeday", "Freeday");
	menu.AddItem("warday", "War Day");
	if (g_ActiveDay != Day_None)
	{
		menu.AddItem("end", "End current day");
	}
	menu.Display(client, 20);
	return Plugin_Handled;
}

public int MenuHandler_Days(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}

	if (action != MenuAction_Select)
	{
		return 0;
	}

	int client = param1;
	if (!AJB_Days_CanUse(client, false))
	{
		return 0;
	}

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "freeday"))
	{
		AJB_Days_StartFreeday(client);
	}
	else if (StrEqual(info, "warday"))
	{
		AJB_Days_StartWarDay(client);
	}
	else if (StrEqual(info, "end"))
	{
		AJB_Days_End(client);
	}

	return 0;
}

Action Command_Freeday(int client, int args)
{
	if (!AJB_Days_CanUse(client, true))
	{
		return Plugin_Handled;
	}

	AJB_Days_StartFreeday(client);
	return Plugin_Handled;
}

Action Command_WarDay(int client, int args)
{
	if (!AJB_Days_CanUse(client, true))
	{
		return Plugin_Handled;
	}

	AJB_Days_StartWarDay(client);
	return Plugin_Handled;
}

Action Command_EndDay(int client, int args)
{
	if (!g_bHasCore || !AJB_IsEnabled())
	{
		AJB_Reply(client, "Day Mode Inactive");
		return Plugin_Handled;
	}

	AJB_Days_End(client);
	return Plugin_Handled;
}

// =========================================================================================================
// Access
// =========================================================================================================

bool AJB_Days_CanUse(int client, bool reply)
{
	if (!g_cvEnabled.BoolValue)
	{
		if (reply)
		{
			AJB_Reply(client, "Day Disabled");
		}
		return false;
	}

	if (!g_bHasCore || !AJB_IsEnabled())
	{
		if (reply)
		{
			AJB_Reply(client, "Day Mode Inactive");
		}
		return false;
	}

	if (client == 0)
	{
		return true;
	}

	if (!IsClientInGame(client))
	{
		return false;
	}

	if (CheckCommandAccess(client, "sm_ajb_day_admin", ADMFLAG_GENERIC))
	{
		return true;
	}

	if (g_cvWardenOnly.BoolValue)
	{
		if (AJB_GetWarden() != client)
		{
			if (reply)
			{
				AJB_Reply(client, "Day Warden Only");
			}
			return false;
		}
	}
	else if (!AJB_IsGuard(client))
	{
		if (reply)
		{
			AJB_Reply(client, "Day Guards Only");
		}
		return false;
	}

	return true;
}

// =========================================================================================================
// Day implementations
// =========================================================================================================

bool AJB_Days_CanStart(int starter)
{
	AJBRoundState state = AJB_GetRoundState();
	if (state == AJBState_Disabled || state == AJBState_Waiting || state == AJBState_RoundEnd)
	{
		if (starter > 0)
		{
			AJB_Reply(starter, "Day Bad State");
		}
		return false;
	}

	if (state == AJBState_LastRequest)
	{
		if (starter > 0)
		{
			AJB_Reply(starter, "Day During LR");
		}
		return false;
	}

	if (g_ActiveDay != Day_None)
	{
		if (starter > 0)
		{
			AJB_Reply(starter, "Day Already Active");
		}
		return false;
	}

	return true;
}

void AJB_Days_StartFreeday(int starter)
{
	if (!AJB_Days_CanStart(starter))
	{
		return;
	}

	// Cosmetic global freeday (same as LR “Freeday for all”).
	g_ActiveDay = Day_Freeday;
	AJB_BeginFreedayAllCosmetic();

	if (starter > 0 && IsClientInGame(starter))
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}

			char prefix[32];
			AJB_GetPrefix(i, prefix, sizeof(prefix));
			CPrintToChat(i, "%T", "Day Freeday Started", i, prefix, starter);
		}
	}
	else
	{
		AJB_ChatAll("Day Freeday Started Console");
	}
}

void AJB_Days_StartWarDay(int starter)
{
	if (!AJB_Days_CanStart(starter))
	{
		return;
	}

	g_ActiveDay = Day_WarDay;
	AJB_BeginCombatDay();

	if (starter > 0 && IsClientInGame(starter))
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}

			char prefix[32];
			AJB_GetPrefix(i, prefix, sizeof(prefix));
			CPrintToChat(i, "%T", "Day WarDay Started", i, prefix, starter);
		}
	}
	else
	{
		AJB_ChatAll("Day WarDay Started Console");
	}
}

void AJB_Days_End(int starter)
{
	if (g_ActiveDay == Day_None)
	{
		if (starter > 0)
		{
			AJB_Reply(starter, "Day None Active");
		}
		return;
	}

	AJB_DayType ended = g_ActiveDay;
	AJB_Days_Clear(true);

	if (g_bHasCore && AJB_IsEnabled())
	{
		AJBRoundState state = AJB_GetRoundState();
		if (state == AJBState_SpecialDay)
		{
			AJB_SetRoundState(AJBState_CellsOpen);
		}
	}

	char dayName[32];
	AJB_Days_GetName(ended, dayName, sizeof(dayName));

	if (starter > 0 && IsClientInGame(starter))
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}

			char prefix[32];
			AJB_GetPrefix(i, prefix, sizeof(prefix));
			CPrintToChat(i, "%T", "Day Ended", i, prefix, starter, dayName);
		}
	}
	else
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}

			char prefix[32];
			AJB_GetPrefix(i, prefix, sizeof(prefix));
			CPrintToChat(i, "%T", "Day Ended Console", i, prefix, dayName);
		}
	}
}

void AJB_Days_Clear(bool clearFreedays)
{
	AJB_DayType previous = g_ActiveDay;

	if (clearFreedays && g_bHasCore && AJB_IsEnabled() && previous == Day_Freeday)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && AJB_IsPrisoner(i))
			{
				AJB_GiveFreedayNow(i, false);
			}
		}
	}

	g_ActiveDay = Day_None;
}

void AJB_Days_GetName(AJB_DayType day, char[] buffer, int maxlen)
{
	switch (day)
	{
		case Day_Freeday: strcopy(buffer, maxlen, "Freeday");
		case Day_WarDay:  strcopy(buffer, maxlen, "War Day");
		default:          strcopy(buffer, maxlen, "Day");
	}
}
