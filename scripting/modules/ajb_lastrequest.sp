// =========================================================================================================
// Another Jailbreak — Last Request
// Classic JB wishes (not melee duels): freeday, warday, class warfare, custom, hot reds, suicide, low grav.
// =========================================================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>

#undef REQUIRE_PLUGIN
#include <ajb/ajb>
#define REQUIRE_PLUGIN

#include <ajb/phrases>

#define PLUGIN_VERSION "1.1.0"

#define LR_SUICIDE_DELAY   5.0
#define LR_HOT_DPS         8.0
#define LR_HOT_TICK        0.5
#define LR_GRAVITY_VALUE   200
#define LR_NEAR_RADIUS     200.0
#define LR_NEAR_MAX        3
#define LR_FREEDAY_OTHERS_MAX 3
// Numbered keys: 1–6 players | 7 Confirm | 8 Prev | 9 Next.
// Separators use ITEMDRAW_RAWLINE (no number). Title ends with ----.
#define LR_FREEDAY_PAGE_SIZE  6

enum AJB_LRWish
{
	LRWish_None = 0,
	LRWish_FreedayMe,
	LRWish_FreedayOthers,
	LRWish_FreedayAll,
	LRWish_WarDay,
	LRWish_ClassWarfare,
	LRWish_Custom,
	LRWish_HotReds,
	LRWish_Suicide,
	LRWish_LowGravity,
	LRWish_HideSeek
};

public Plugin myinfo =
{
	name        = "Another Jailbreak - Last Request",
	author      = "SummerTYT",
	description = "Another Jailbreak — classic Last Request wishes.",
	version     = PLUGIN_VERSION,
	url         = ""
};

ConVar g_cvEnabled;
ConVar g_cvMenuTime;
ConVar g_cvSuicideDelay;
ConVar g_cvHotDamage;
ConVar g_cvGravity;
ConVar g_cvHSHideTime;
ConVar g_cvHSRoundTime;

bool g_bHasCore;

int g_iPrisoner;
bool g_bMenuOpen;
bool g_bAwaitingCustom;
bool g_bHotReds;
bool g_bLowGravity;
int g_iSavedGravity = -1;

// Hide and Seek: BLU are frozen "seekers" for the hide window, RED run and hide.
bool g_bHideSeek;

Handle g_hMenuTimer;
Handle g_hMenuWarnTimer;
Handle g_hSuicideTimer;
Handle g_hHotTimer;
Handle g_hHSHideTimer;   // fires when the hide window ends → release seekers
Handle g_hHSEndTimer;    // authoritative 5-minute round end (hiders win on timeout)

// Seconds remaining when the hurry warning fires (half of menu time).
int g_iMenuWarnLeft;

// Freeday multi-pick (panel; chooser listed first, then other living prisoners)
bool g_bPickedFreeday[MAXPLAYERS + 1];
int g_iFreedayPickCount;
int g_iFreedayMenuPage;
// Panel keys 1..PAGE_SIZE → userid for that row (0 = empty spacer).
int g_iFreedaySlotUserId[LR_FREEDAY_PAGE_SIZE];

// ----- Queued for NEXT round (not applied when chosen, except suicide) -----
AJB_LRWish g_PendingWish;
char g_sPendingCustom[192];
TFClassType g_PendingClassRed;  // prisoners
TFClassType g_PendingClassBlu;  // guards
char g_sPendingChooserName[64];

// Active Class Warfare lock (this live round).
bool g_bClassWarfareActive;
TFClassType g_ActiveClassRed;
TFClassType g_ActiveClassBlu;

// =========================================================================================================
// Lifecycle
// =========================================================================================================

public void OnPluginStart()
{
	CreateConVar("sm_ajb_lr_version", PLUGIN_VERSION, "AJB Last Request module version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_ajb_lr_enabled", "1", "Enable Last Request offers.", _, true, 0.0, true, 1.0);
	g_cvMenuTime = CreateConVar("sm_ajb_lr_menu_time", "30", "Seconds the prisoner has to pick an LR.", _, true, 5.0, true, 90.0);
	g_cvSuicideDelay = CreateConVar("sm_ajb_lr_suicide_delay", "5", "Seconds before suicide LR kills the prisoner.", _, true, 1.0, true, 30.0);
	g_cvHotDamage = CreateConVar("sm_ajb_lr_hot_damage", "8", "Damage per tick when Hot Reds touch a guard.", _, true, 1.0, true, 100.0);
	g_cvGravity = CreateConVar("sm_ajb_lr_low_gravity", "200", "sv_gravity value for Low Gravity LR (stock is 800).", _, true, 50.0, true, 800.0);
	g_cvHSHideTime = CreateConVar("sm_ajb_lr_hs_hide_time", "30", "Hide and Seek: seconds RED get to hide before the frozen BLU seekers are released.", _, true, 5.0, true, 120.0);
	g_cvHSRoundTime = CreateConVar("sm_ajb_lr_hs_round_time", "300", "Hide and Seek: total round duration in seconds (hiders win on timeout).", _, true, 60.0, true, 900.0);

	AutoExecConfig(true, "ajb_lastrequest");

	LoadTranslations("ajb_lastrequest.phrases");
	LoadTranslations("ajb.phrases");
	LoadTranslations("common.phrases");

	RegConsoleCmd("sm_ajb_lr", Command_LR, "Warden: grant Last Request to a prisoner.");
	RegAdminCmd("sm_ajb_lr_force", Command_ForceLR, ADMFLAG_GENERIC, "Force LR menu for a living prisoner.");

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("teamplay_round_win", Event_RoundWin, EventHookMode_PostNoCopy);

	AddCommandListener(Listener_Say, "say");
	AddCommandListener(Listener_Say, "say_team");

	g_bHasCore = LibraryExists(AJB_LIBRARY);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SDKHook(i, SDKHook_StartTouch, AJB_LR_OnStartTouch);
		}
	}

	LogMessage("[AJB-LR] loaded (core %s).", g_bHasCore ? "present" : "missing");
}

public void OnPluginEnd()
{
	AJB_LR_Cleanup(false);
}

public void OnMapEnd()
{
	AJB_LR_Cleanup(false);
	AJB_LR_ClearPendingWish();
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_StartTouch, AJB_LR_OnStartTouch);
	g_bPickedFreeday[client] = false;
}

public void OnClientDisconnect(int client)
{
	g_bPickedFreeday[client] = false;

	if (client == g_iPrisoner)
	{
		if (g_bAwaitingCustom)
		{
			g_bAwaitingCustom = false;
		}
		AJB_LR_Cleanup(true);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = false;
		AJB_LR_Cleanup(false);
	}
}

// =========================================================================================================
// Core forwards / events
// =========================================================================================================

public void AJB_OnLastPrisoner(int client)
{
	if (!g_cvEnabled.BoolValue || !g_bHasCore || !AJB_IsEnabled())
	{
		return;
	}

	// No hint if a wish is already open, queued, or mid-pick.
	if (AJB_LR_IsGrantBlocked())
	{
		return;
	}

	if (client > 0 && IsClientInGame(client))
	{
		AJB_LR_ChatAll1N("LR Last Prisoner Hint", client);
	}
}

public void AJB_OnWardenGiveLR(int warden)
{
	if (!g_cvEnabled.BoolValue || !g_bHasCore || !AJB_IsEnabled())
	{
		return;
	}

	if (warden < 1 || !IsClientInGame(warden) || !IsPlayerAlive(warden))
	{
		return;
	}

	if (AJB_GetWarden() != warden)
	{
		return;
	}

	// Warden cannot grant another LR once a wish is picked/queued (admin force only).
	if (AJB_LR_IsGrantBlocked())
	{
		AJB_Reply(warden, "LR Already Active");
		AJB_ShowWardenMenu(warden);
		return;
	}

	AJB_LR_ShowGrantMenu(warden);
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	// Clear active mid-round effects only. Pending wish waits for AJB_OnLiveRoundBegin
	// (after prep / real round start — never during preround).
	AJB_LR_ClearClassWarfareActive();
	AJB_LR_Cleanup(false);
}

void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
	// Keep g_PendingWish — it is for the NEXT live round.
	AJB_LR_ClearClassWarfareActive();
	AJB_LR_Cleanup(false);
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bClassWarfareActive)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	AJB_LR_ForceClassWarfareClass(client);
}

// Core fires this when prep ends, or right after round start if prep time is 0.
public void AJB_OnLiveRoundBegin()
{
	if (!g_cvEnabled.BoolValue || !g_bHasCore || !AJB_IsEnabled())
	{
		return;
	}

	AJB_LR_ApplyPendingWish();
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (event.GetInt("deathflags") & TF_DEATHFLAG_DEADRINGER)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim == g_iPrisoner && (g_bMenuOpen || g_bAwaitingCustom))
	{
		AJB_LR_Cleanup(true);
	}
}

// =========================================================================================================
// Commands
// =========================================================================================================

Action Command_LR(int client, int args)
{
	if (!g_bHasCore || !AJB_IsEnabled())
	{
		AJB_Reply(client, "LR Mode Inactive");
		return Plugin_Handled;
	}

	if (client == 0)
	{
		AJB_Reply(client, "LR Ingame Only");
		return Plugin_Handled;
	}

	if (!g_cvEnabled.BoolValue)
	{
		AJB_Reply(client, "LR Mode Inactive");
		return Plugin_Handled;
	}

	if (AJB_LR_IsGrantBlocked())
	{
		AJB_Reply(client, "LR Already Active");
		return Plugin_Handled;
	}

	if (AJB_GetWarden() != client || !IsPlayerAlive(client))
	{
		AJB_Reply(client, "LR Warden Only");
		return Plugin_Handled;
	}

	AJB_LR_ShowGrantMenu(client);
	return Plugin_Handled;
}

Action Command_ForceLR(int client, int args)
{
	if (!g_bHasCore || !AJB_IsEnabled())
	{
		AJB_Reply(client, "LR Mode Inactive");
		return Plugin_Handled;
	}

	int target = 0;
	if (args >= 1)
	{
		char arg[64];
		GetCmdArg(1, arg, sizeof(arg));
		target = FindTarget(client, arg, false, false);
		if (target <= 0 || !IsPlayerAlive(target) || !AJB_IsPrisoner(target))
		{
			AJB_Reply(client, "LR No Prisoner");
			return Plugin_Handled;
		}
	}
	else
	{
		int count = 0;
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i) && AJB_IsPrisoner(i))
			{
				target = i;
				count++;
				if (count > 1)
				{
					AJB_Reply(client, "LR Force Need Target");
					return Plugin_Handled;
				}
			}
		}
		if (count < 1)
		{
			AJB_Reply(client, "LR No Prisoner");
			return Plugin_Handled;
		}
	}

	// Admin override: drop any open menu / queued wish, then offer.
	AJB_LR_Cleanup(false);
	AJB_LR_ClearPendingWish();
	AJB_LR_Offer(target);
	return Plugin_Handled;
}

// =========================================================================================================
// Warden grant menu (nearby / others)
// =========================================================================================================

void AJB_LR_ShowGrantMenu(int warden)
{
	int clients[MAXPLAYERS];
	float dists[MAXPLAYERS];
	int count = 0;

	float wPos[3];
	GetClientAbsOrigin(warden, wPos);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || !AJB_IsPrisoner(i))
		{
			continue;
		}

		float pPos[3];
		GetClientAbsOrigin(i, pPos);
		clients[count] = i;
		dists[count] = GetVectorDistance(wPos, pPos);
		count++;
	}

	if (count < 1)
	{
		AJB_Reply(warden, "LR No Prisoner");
		AJB_ShowWardenMenu(warden);
		return;
	}

	for (int i = 1; i < count; i++)
	{
		int cKey = clients[i];
		float dKey = dists[i];
		int j = i - 1;
		while (j >= 0 && dists[j] > dKey)
		{
			clients[j + 1] = clients[j];
			dists[j + 1] = dists[j];
			j--;
		}
		clients[j + 1] = cKey;
		dists[j + 1] = dKey;
	}

	int nearIdx[LR_NEAR_MAX];
	int nearCount = 0;
	bool used[MAXPLAYERS + 1];

	for (int i = 0; i < count && nearCount < LR_NEAR_MAX; i++)
	{
		if (dists[i] <= LR_NEAR_RADIUS)
		{
			nearIdx[nearCount++] = i;
			used[clients[i]] = true;
		}
	}

	Menu menu = new Menu(MenuHandler_Grant);
	char title[64];
	char header[64];
	char line[72];
	Format(title, sizeof(title), "%T", "LR Grant Title", warden);
	menu.SetTitle(title);

	if (nearCount > 0)
	{
		Format(header, sizeof(header), "%T", "LR Grant Nearby Header", warden);
		menu.AddItem("hdr_near", header, ITEMDRAW_DISABLED);

		for (int n = 0; n < nearCount; n++)
		{
			int ply = clients[nearIdx[n]];
			char id[8];
			IntToString(GetClientUserId(ply), id, sizeof(id));
			GetClientName(ply, line, sizeof(line));
			menu.AddItem(id, line);
		}
	}

	bool hasOther = false;
	for (int i = 0; i < count; i++)
	{
		if (!used[clients[i]])
		{
			hasOther = true;
			break;
		}
	}

	if (hasOther)
	{
		Format(header, sizeof(header), "%T", "LR Grant Others Header", warden);
		menu.AddItem("hdr_other", header, ITEMDRAW_DISABLED);

		for (int i = 0; i < count; i++)
		{
			int ply = clients[i];
			if (used[ply])
			{
				continue;
			}

			char id[8];
			IntToString(GetClientUserId(ply), id, sizeof(id));
			GetClientName(ply, line, sizeof(line));
			menu.AddItem(id, line);
		}
	}

	menu.ExitButton = false;
	menu.ExitBackButton = true;
	menu.Display(warden, 0);
}

public int MenuHandler_Grant(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}

	int warden = param1;

	if (action == MenuAction_Cancel)
	{
		if (g_bHasCore && AJB_IsEnabled() && AJB_GetWarden() == warden)
		{
			AJB_ShowWardenMenu(warden);
		}
		return 0;
	}

	if (action != MenuAction_Select)
	{
		return 0;
	}

	if (!g_bHasCore || !AJB_IsEnabled() || AJB_GetWarden() != warden || !IsPlayerAlive(warden))
	{
		return 0;
	}

	char id[8];
	menu.GetItem(param2, id, sizeof(id));

	if (StrContains(id, "hdr_") == 0)
	{
		AJB_LR_ShowGrantMenu(warden);
		return 0;
	}

	if (AJB_LR_IsGrantBlocked())
	{
		AJB_Reply(warden, "LR Already Active");
		AJB_ShowWardenMenu(warden);
		return 0;
	}

	int prisoner = GetClientOfUserId(StringToInt(id));
	if (prisoner < 1 || !IsClientInGame(prisoner) || !IsPlayerAlive(prisoner) || !AJB_IsPrisoner(prisoner))
	{
		AJB_Reply(warden, "LR Prisoner Invalid");
		AJB_LR_ShowGrantMenu(warden);
		return 0;
	}

	AJB_LR_Offer(prisoner);
	AJB_ShowWardenMenu(warden);
	return 0;
}

// =========================================================================================================
// Prisoner wish menu
// =========================================================================================================

void AJB_LR_Offer(int prisoner)
{
	if (!IsClientInGame(prisoner) || !IsPlayerAlive(prisoner))
	{
		return;
	}

	g_iPrisoner = prisoner;
	g_bMenuOpen = true;
	g_bAwaitingCustom = false;
	g_iFreedayPickCount = 0;
	g_iFreedayMenuPage = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bPickedFreeday[i] = false;
	}

	if (g_bHasCore)
	{
		AJB_SetRoundState(AJBState_LRChoosing);
	}

	AJB_LR_ChatAll1N("LR Offered", prisoner);
	AJB_LR_ShowWishMenu(prisoner);
}

void AJB_LR_ShowWishMenu(int prisoner)
{
	Menu menu = new Menu(MenuHandler_Wish);
	char title[64];
	char line[96];
	Format(title, sizeof(title), "%T", "LR Menu Title", prisoner);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", "LR Wish Freeday Me", prisoner);
	menu.AddItem("fd_me", line);
	Format(line, sizeof(line), "%T", "LR Wish Freeday Others", prisoner);
	menu.AddItem("fd_others", line);
	Format(line, sizeof(line), "%T", "LR Wish Freeday All", prisoner);
	menu.AddItem("fd_all", line);
	Format(line, sizeof(line), "%T", "LR Wish WarDay", prisoner);
	menu.AddItem("warday", line);
	Format(line, sizeof(line), "%T", "LR Wish ClassWarfare", prisoner);
	menu.AddItem("classwar", line);
	Format(line, sizeof(line), "%T", "LR Wish Custom", prisoner);
	menu.AddItem("custom", line);
	Format(line, sizeof(line), "%T", "LR Wish HotReds", prisoner);
	menu.AddItem("hot", line);
	Format(line, sizeof(line), "%T", "LR Wish Suicide", prisoner);
	menu.AddItem("suicide", line);
	Format(line, sizeof(line), "%T", "LR Wish LowGravity", prisoner);
	menu.AddItem("lowgrav", line);
	Format(line, sizeof(line), "%T", "LR Wish HideAndSeek", prisoner);
	menu.AddItem("hideseek", line);

	menu.ExitButton = false;
	g_bMenuOpen = true;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));

	AJB_LR_StartMenuTimers(prisoner);
}

void AJB_LR_StartMenuTimers(int prisoner)
{
	AJB_LR_KillMenuTimer();

	float total = g_cvMenuTime.FloatValue;
	if (total < 5.0)
	{
		total = 5.0;
	}

	int userid = GetClientUserId(prisoner);

	g_hMenuTimer = CreateTimer(total + 0.5, Timer_MenuTimeout, userid, TIMER_FLAG_NO_MAPCHANGE);

	// Warn at the halfway point. Truncate (floor) so the chat number is always an int
	// e.g. menu_time 30 → 15; 31 → 15; 20 → 10. Timer fires after the same truncated half.
	int halfSec = RoundToFloor(total * 0.5);
	if (halfSec < 1)
	{
		halfSec = 1;
	}
	g_iMenuWarnLeft = halfSec;

	// Only schedule if there is a meaningful wait before the warn.
	if (total > 2.0 && float(halfSec) < total)
	{
		g_hMenuWarnTimer = CreateTimer(float(halfSec), Timer_MenuWarnHalfway, userid, TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action Timer_MenuWarnHalfway(Handle timer, int userid)
{
	g_hMenuWarnTimer = null;

	if (!g_bMenuOpen && !g_bAwaitingCustom)
	{
		return Plugin_Stop;
	}

	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client) && client == g_iPrisoner)
	{
		char prefix[32];
		AJB_GetPrefix(client, prefix, sizeof(prefix));
		CPrintToChat(client, "%T", "LR Menu Hurry", client, prefix, g_iMenuWarnLeft);
	}

	return Plugin_Stop;
}

Action Timer_MenuTimeout(Handle timer, int userid)
{
	g_hMenuTimer = null;
	if (!g_bMenuOpen && !g_bAwaitingCustom)
	{
		return Plugin_Stop;
	}

	int client = GetClientOfUserId(userid);
	g_bMenuOpen = false;
	g_bAwaitingCustom = false;
	if (client > 0)
	{
		AJB_LR_ChatAll1N("LR Timeout", client);
	}
	g_iPrisoner = 0;
	return Plugin_Stop;
}

void AJB_LR_KillMenuTimer()
{
	if (g_hMenuTimer != null)
	{
		delete g_hMenuTimer;
		g_hMenuTimer = null;
	}
	if (g_hMenuWarnTimer != null)
	{
		delete g_hMenuWarnTimer;
		g_hMenuWarnTimer = null;
	}
}

public int MenuHandler_Wish(Menu menu, MenuAction action, int param1, int param2)
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
	if (client != g_iPrisoner || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return 0;
	}

	AJB_LR_KillMenuTimer();
	g_bMenuOpen = false;

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "fd_me"))
	{
		AJB_LR_DoFreedayMe(client);
	}
	else if (StrEqual(info, "fd_others"))
	{
		g_iFreedayMenuPage = 0;
		AJB_LR_ShowFreedayOthersMenu(client);
		AJB_LR_StartMenuTimers(client);
	}
	else if (StrEqual(info, "fd_all"))
	{
		AJB_LR_DoFreedayAll(client);
	}
	else if (StrEqual(info, "warday"))
	{
		AJB_LR_DoWarDay(client);
	}
	else if (StrEqual(info, "classwar"))
	{
		AJB_LR_DoClassWarfare(client);
	}
	else if (StrEqual(info, "custom"))
	{
		AJB_LR_StartCustom(client);
	}
	else if (StrEqual(info, "hot"))
	{
		AJB_LR_DoHotReds(client);
	}
	else if (StrEqual(info, "suicide"))
	{
		AJB_LR_DoSuicide(client);
	}
	else if (StrEqual(info, "lowgrav"))
	{
		AJB_LR_DoLowGravity(client);
	}
	else if (StrEqual(info, "hideseek"))
	{
		AJB_LR_DoHideSeek(client);
	}

	return 0;
}

// =========================================================================================================
// Wish implementations
// =========================================================================================================

// Close the LR menu after a wish is locked in (queued or instant).
void AJB_LR_CloseMenuState()
{
	g_iPrisoner = 0;
	g_bMenuOpen = false;
	g_bAwaitingCustom = false;
	AJB_LR_KillMenuTimer();
}

// Wish locked → HUD "LR Chosen" (still LR phase for rules).
void AJB_LR_MarkWishChosen()
{
	if (g_bHasCore)
	{
		AJB_SetRoundState(AJBState_LRChosen);
	}
}

// Warden cannot grant another LR while one is open, being typed, queued, or suicide countdown.
// Admin force clears this and re-offers.
bool AJB_LR_IsGrantBlocked()
{
	return g_iPrisoner > 0
		|| g_bMenuOpen
		|| g_bAwaitingCustom
		|| g_PendingWish != LRWish_None
		|| g_hSuicideTimer != null;
}

void AJB_LR_ClearPendingWish()
{
	g_PendingWish = LRWish_None;
	g_sPendingCustom[0] = '\0';
	g_PendingClassRed = TFClass_Unknown;
	g_PendingClassBlu = TFClass_Unknown;
	g_sPendingChooserName[0] = '\0';
}

void AJB_LR_ClearClassWarfareActive()
{
	g_bClassWarfareActive = false;
	g_ActiveClassRed = TFClass_Unknown;
	g_ActiveClassBlu = TFClass_Unknown;
}

// Two different random classes (Scout..Engineer).
void AJB_LR_PickTeamClasses(TFClassType &redCls, TFClassType &bluCls)
{
	redCls = view_as<TFClassType>(GetRandomInt(view_as<int>(TFClass_Scout), view_as<int>(TFClass_Engineer)));
	do
	{
		bluCls = view_as<TFClassType>(GetRandomInt(view_as<int>(TFClass_Scout), view_as<int>(TFClass_Engineer)));
	}
	while (bluCls == redCls);
}

void AJB_LR_ForceClassWarfareClass(int client)
{
	if (!g_bClassWarfareActive || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	TFClassType want = TFClass_Unknown;
	if (g_bHasCore && AJB_IsPrisoner(client))
	{
		want = g_ActiveClassRed;
	}
	else if (g_bHasCore && AJB_IsGuard(client))
	{
		want = g_ActiveClassBlu;
	}

	if (want == TFClass_Unknown || TF2_GetPlayerClass(client) == want)
	{
		return;
	}

	TF2_SetPlayerClass(client, want, false, true);
	TF2_RegeneratePlayer(client);
}

void AJB_LR_RememberChooser(int prisoner)
{
	g_sPendingChooserName[0] = '\0';
	if (prisoner > 0 && IsClientInGame(prisoner))
	{
		GetClientName(prisoner, g_sPendingChooserName, sizeof(g_sPendingChooserName));
	}
}

// Queue a round-altering wish for the NEXT round. Announce now, apply on next round start.
void AJB_LR_QueueWish(int prisoner, AJB_LRWish wish, const char[] phraseKey)
{
	AJB_LR_ClearPendingWish();
	g_PendingWish = wish;
	AJB_LR_RememberChooser(prisoner);

	if (prisoner > 0 && IsClientInGame(prisoner))
	{
		AJB_LR_ChatAll1N(phraseKey, prisoner);
	}

	AJB_LR_CloseMenuState();
	AJB_LR_MarkWishChosen();
}

void AJB_LR_ApplyPendingWish()
{
	if (!g_bHasCore || !AJB_IsEnabled() || g_PendingWish == LRWish_None)
	{
		return;
	}

	// Snapshot then clear so re-entrancy / double round-start is safe.
	AJB_LRWish apply = g_PendingWish;
	char custom[192];
	strcopy(custom, sizeof(custom), g_sPendingCustom);
	TFClassType clsRed = g_PendingClassRed;
	TFClassType clsBlu = g_PendingClassBlu;
	char chooser[64];
	strcopy(chooser, sizeof(chooser), g_sPendingChooserName);

	AJB_LR_ClearPendingWish();

	switch (apply)
	{
		case LRWish_FreedayMe, LRWish_FreedayOthers:
		{
			// Personal freedays already queued in core (AJB_SetPlayerFreeday) and applied at round start.
			AJB_LR_ChatAllQueuedApplied(chooser, "LR Applied Freeday");
		}
		case LRWish_FreedayAll:
		{
			AJB_BeginFreedayAllCosmetic();
			AJB_LR_ChatAllQueuedApplied(chooser, "LR Applied Freeday All");
		}
		case LRWish_WarDay:
		{
			AJB_BeginCombatDay();
			AJB_LR_ChatAllQueuedApplied(chooser, "LR Applied WarDay");
		}
		case LRWish_ClassWarfare:
		{
			// Safety: never apply same class to both teams.
			if (clsRed == TFClass_Unknown || clsBlu == TFClass_Unknown || clsRed == clsBlu)
			{
				AJB_LR_PickTeamClasses(clsRed, clsBlu);
			}

			g_bClassWarfareActive = true;
			g_ActiveClassRed = clsRed;
			g_ActiveClassBlu = clsBlu;

			for (int i = 1; i <= MaxClients; i++)
			{
				if (!IsClientInGame(i) || !IsPlayerAlive(i))
				{
					continue;
				}
				if (AJB_IsPrisoner(i))
				{
					TF2_SetPlayerClass(i, clsRed, false, true);
				}
				else if (AJB_IsGuard(i))
				{
					TF2_SetPlayerClass(i, clsBlu, false, true);
				}
			}
			// Combat day regenerates loadouts after class is set.
			AJB_BeginCombatDay();
			AJB_LR_ChatAllClassApplied(chooser, clsRed, clsBlu);
		}
		case LRWish_Custom:
		{
			AJB_OpenCells();
			AJB_LR_ChatAllCustomApplied(chooser, custom);
		}
		case LRWish_HotReds:
		{
			g_bHotReds = true;
			AJB_SetRebelOnHit(false);
			AJB_OpenCells();
			AJB_SetRoundState(AJBState_SpecialDay);
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientInGame(i) && AJB_IsPrisoner(i))
				{
					AJB_SetRebel(i, false);
				}
			}
			AJB_LR_KillHotTimer();
			g_hHotTimer = CreateTimer(LR_HOT_TICK, Timer_HotReds, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			AJB_LR_ChatAllQueuedApplied(chooser, "LR Applied HotReds");
		}
		case LRWish_LowGravity:
		{
			ConVar cv = FindConVar("sv_gravity");
			if (cv != null)
			{
				if (g_iSavedGravity < 0)
				{
					g_iSavedGravity = cv.IntValue;
				}
				cv.SetInt(g_cvGravity.IntValue);
				g_bLowGravity = true;
			}
			AJB_OpenCells();
			AJB_LR_ChatAllQueuedApplied(chooser, "LR Applied LowGravity");
		}
		case LRWish_HideSeek:
		{
			AJB_LR_ApplyHideSeek(chooser);
		}
		default:
		{
		}
	}
}

void AJB_LR_DoFreedayMe(int prisoner)
{
	// Next round personal freeday (core pending flag).
	AJB_SetPlayerFreeday(prisoner, true);
	AJB_LR_QueueWish(prisoner, LRWish_FreedayMe, "LR Chose Freeday Me");
}

// Build ordered list: chooser first, then every other living prisoner.
int AJB_LR_CollectFreedayTargets(int prisoner, int[] list, int maxList)
{
	int n = 0;
	if (prisoner > 0 && IsClientInGame(prisoner) && IsPlayerAlive(prisoner) && AJB_IsPrisoner(prisoner))
	{
		list[n++] = prisoner;
	}

	for (int i = 1; i <= MaxClients && n < maxList; i++)
	{
		if (i == prisoner || !IsClientInGame(i) || !IsPlayerAlive(i) || !AJB_IsPrisoner(i))
		{
			continue;
		}
		list[n++] = i;
	}
	return n;
}

void AJB_LR_ShowFreedayOthersMenu(int prisoner)
{
	int list[MAXPLAYERS + 1];
	int total = AJB_LR_CollectFreedayTargets(prisoner, list, sizeof(list));
	if (total < 1)
	{
		AJB_Chat(prisoner, "LR Freeday Others None");
		AJB_LR_ShowWishMenu(prisoner);
		return;
	}

	int pages = (total + LR_FREEDAY_PAGE_SIZE - 1) / LR_FREEDAY_PAGE_SIZE;
	if (pages < 1)
	{
		pages = 1;
	}
	if (g_iFreedayMenuPage >= pages)
	{
		g_iFreedayMenuPage = pages - 1;
	}
	if (g_iFreedayMenuPage < 0)
	{
		g_iFreedayMenuPage = 0;
	}

	// Panel: DrawText = ---- without a number (Radio Menu cannot do that).
	// Keys: 1–6 players | 7 Confirm | 8 Prev | 9 Next
	Panel panel = new Panel();

	char title[64];
	Format(title, sizeof(title), "%T", "LR Freeday Others Title", prisoner, g_iFreedayPickCount, LR_FREEDAY_OTHERS_MAX);
	panel.SetTitle(title);

	char sep[32];
	Format(sep, sizeof(sep), "%T", "Menu Separator", prisoner);
	panel.DrawText(sep);

	int start = g_iFreedayMenuPage * LR_FREEDAY_PAGE_SIZE;
	for (int slot = 0; slot < LR_FREEDAY_PAGE_SIZE; slot++)
	{
		g_iFreedaySlotUserId[slot] = 0;
		int idx = start + slot;
		if (idx < total)
		{
			int target = list[idx];
			g_iFreedaySlotUserId[slot] = GetClientUserId(target);

			char name[72];
			GetClientName(target, name, sizeof(name));
			if (g_bPickedFreeday[target])
			{
				Format(name, sizeof(name), "[*] %s", name);
			}
			panel.DrawItem(name);
		}
		else
		{
			panel.DrawItem(" ", ITEMDRAW_SPACER);
		}
	}

	panel.DrawText(sep);

	char line[72];
	Format(line, sizeof(line), "%T", "LR Freeday Others Confirm", prisoner);
	panel.DrawItem(line);

	int prevStyle = (g_iFreedayMenuPage <= 0) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;
	int nextStyle = (g_iFreedayMenuPage >= pages - 1) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;

	Format(line, sizeof(line), "%T", "LR Freeday Others Prev", prisoner);
	panel.DrawItem(line, prevStyle);
	Format(line, sizeof(line), "%T", "LR Freeday Others Next", prisoner);
	panel.DrawItem(line, nextStyle);

	g_bMenuOpen = true;
	panel.Send(prisoner, PanelHandler_FreedayOthers, RoundToFloor(g_cvMenuTime.FloatValue));
}

public int PanelHandler_FreedayOthers(Menu menu, MenuAction action, int param1, int param2)
{
	// Panel callback: param2 is the DrawItem key (DrawText lines do not consume keys).
	if (action != MenuAction_Select)
	{
		return 0;
	}

	int client = param1;
	if (client != g_iPrisoner || !IsClientInGame(client))
	{
		return 0;
	}

	// 1..6 = player row, 7 = confirm, 8 = prev, 9 = next
	if (param2 == 8)
	{
		if (g_iFreedayMenuPage > 0)
		{
			g_iFreedayMenuPage--;
		}
		AJB_LR_ShowFreedayOthersMenu(client);
		return 0;
	}

	if (param2 == 9)
	{
		g_iFreedayMenuPage++;
		AJB_LR_ShowFreedayOthersMenu(client);
		return 0;
	}

	if (param2 == 7)
	{
		if (g_iFreedayPickCount < 1)
		{
			AJB_Chat(client, "LR Freeday Others Need One");
			AJB_LR_ShowFreedayOthersMenu(client);
			return 0;
		}

		AJB_LR_ShowFreedayReviewPanel(client);
		return 0;
	}

	if (param2 < 1 || param2 > LR_FREEDAY_PAGE_SIZE)
	{
		return 0;
	}

	int target = GetClientOfUserId(g_iFreedaySlotUserId[param2 - 1]);
	if (target < 1 || !IsClientInGame(target) || !IsPlayerAlive(target) || !AJB_IsPrisoner(target))
	{
		AJB_LR_ShowFreedayOthersMenu(client);
		return 0;
	}

	if (g_bPickedFreeday[target])
	{
		g_bPickedFreeday[target] = false;
		g_iFreedayPickCount--;
		if (g_iFreedayPickCount < 0)
		{
			g_iFreedayPickCount = 0;
		}
	}
	else
	{
		if (g_iFreedayPickCount >= LR_FREEDAY_OTHERS_MAX)
		{
			AJB_Chat(client, "LR Freeday Others Cap");
		}
		else
		{
			g_bPickedFreeday[target] = true;
			g_iFreedayPickCount++;
		}
	}

	AJB_LR_ShowFreedayOthersMenu(client);
	return 0;
}

// Review selected names before locking the wish (requires ≥1 pick).
void AJB_LR_ShowFreedayReviewPanel(int prisoner)
{
	Panel panel = new Panel();

	char title[72];
	Format(title, sizeof(title), "%T", "LR Freeday Others Review Title", prisoner, g_iFreedayPickCount);
	panel.SetTitle(title);

	char sep[32];
	Format(sep, sizeof(sep), "%T", "Menu Separator", prisoner);
	panel.DrawText(sep);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bPickedFreeday[i] || !IsClientInGame(i))
		{
			continue;
		}

		char name[64];
		GetClientName(i, name, sizeof(name));
		panel.DrawText(name);
	}

	panel.DrawText(sep);

	char line[72];
	Format(line, sizeof(line), "%T", "LR Freeday Others Review Yes", prisoner);
	panel.DrawItem(line);
	Format(line, sizeof(line), "%T", "LR Freeday Others Review No", prisoner);
	panel.DrawItem(line);

	g_bMenuOpen = true;
	panel.Send(prisoner, PanelHandler_FreedayReview, RoundToFloor(g_cvMenuTime.FloatValue));
}

public int PanelHandler_FreedayReview(Menu menu, MenuAction action, int param1, int param2)
{
	if (action != MenuAction_Select)
	{
		return 0;
	}

	int client = param1;
	if (client != g_iPrisoner || !IsClientInGame(client))
	{
		return 0;
	}

	// 1 = yes (lock wish), 2 = no (back to picker)
	if (param2 == 2)
	{
		AJB_LR_ShowFreedayOthersMenu(client);
		return 0;
	}

	if (param2 != 1)
	{
		return 0;
	}

	if (g_iFreedayPickCount < 1)
	{
		AJB_Chat(client, "LR Freeday Others Need One");
		AJB_LR_ShowFreedayOthersMenu(client);
		return 0;
	}

	g_bMenuOpen = false;
	int given = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bPickedFreeday[i] && IsClientInGame(i) && AJB_IsPrisoner(i))
		{
			AJB_SetPlayerFreeday(i, true);
			given++;
		}
		g_bPickedFreeday[i] = false;
	}
	g_iFreedayPickCount = 0;
	g_iFreedayMenuPage = 0;
	AJB_LR_ChatAllFreedayOthers(client, given);
	AJB_LR_ClearPendingWish();
	g_PendingWish = LRWish_FreedayOthers;
	AJB_LR_RememberChooser(client);
	AJB_LR_CloseMenuState();
	AJB_LR_MarkWishChosen();
	return 0;
}

void AJB_LR_DoFreedayAll(int prisoner)
{
	// NEXT round: cosmetic global freeday.
	AJB_LR_QueueWish(prisoner, LRWish_FreedayAll, "LR Chose Freeday All");
}

void AJB_LR_DoWarDay(int prisoner)
{
	// NEXT round: full combat day (makes sense with full teams).
	AJB_LR_QueueWish(prisoner, LRWish_WarDay, "LR Chose WarDay");
}

// Class Warfare: one random class for RED, another for BLU (never the same).
void AJB_LR_DoClassWarfare(int prisoner)
{
	TFClassType redCls, bluCls;
	AJB_LR_PickTeamClasses(redCls, bluCls);

	AJB_LR_ClearPendingWish();
	g_PendingWish = LRWish_ClassWarfare;
	g_PendingClassRed = redCls;
	g_PendingClassBlu = bluCls;
	AJB_LR_RememberChooser(prisoner);
	// Classes announced when applied next live round.
	AJB_LR_ChatAll1N("LR Chose ClassWarfare", prisoner);
	AJB_LR_CloseMenuState();
	AJB_LR_MarkWishChosen();
}

void AJB_LR_StartCustom(int prisoner)
{
	g_bAwaitingCustom = true;
	g_bMenuOpen = false;
	AJB_Chat(prisoner, "LR Custom Prompt");
	AJB_LR_ChatAll1N("LR Custom Waiting", prisoner);

	// Same countdown + 15s warning while waiting for chat.
	AJB_LR_StartMenuTimers(prisoner);
	// Replace timeout with custom-specific handler (warn timer already started).
	if (g_hMenuTimer != null)
	{
		delete g_hMenuTimer;
		g_hMenuTimer = null;
	}
	g_hMenuTimer = CreateTimer(g_cvMenuTime.FloatValue + 0.5, Timer_CustomTimeout, GetClientUserId(prisoner), TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_CustomTimeout(Handle timer, int userid)
{
	g_hMenuTimer = null;
	if (!g_bAwaitingCustom)
	{
		return Plugin_Stop;
	}

	g_bAwaitingCustom = false;
	int client = GetClientOfUserId(userid);
	if (client > 0)
	{
		AJB_LR_ChatAll1N("LR Timeout", client);
	}
	g_iPrisoner = 0;
	return Plugin_Stop;
}

Action Listener_Say(int client, const char[] command, int argc)
{
	if (!g_bAwaitingCustom || client != g_iPrisoner || client < 1)
	{
		return Plugin_Continue;
	}

	char text[192];
	GetCmdArgString(text, sizeof(text));
	StripQuotes(text);
	TrimString(text);

	if (text[0] == '\0' || text[0] == '/')
	{
		return Plugin_Continue;
	}

	g_bAwaitingCustom = false;
	AJB_LR_KillMenuTimer();

	// Custom text is announced now and again next round (warden can prepare).
	AJB_LR_ClearPendingWish();
	g_PendingWish = LRWish_Custom;
	strcopy(g_sPendingCustom, sizeof(g_sPendingCustom), text);
	AJB_LR_RememberChooser(client);
	AJB_LR_ChatAllCustom(client, text);
	AJB_LR_CloseMenuState();
	AJB_LR_MarkWishChosen();
	return Plugin_Handled;
}

void AJB_LR_DoHotReds(int prisoner)
{
	// NEXT round hot reds.
	AJB_LR_QueueWish(prisoner, LRWish_HotReds, "LR Chose HotReds");
}

Action Timer_HotReds(Handle timer)
{
	if (!g_bHotReds || !g_bHasCore || !AJB_IsEnabled())
	{
		g_hHotTimer = null;
		return Plugin_Stop;
	}

	float dmg = g_cvHotDamage.FloatValue;
	if (dmg < 1.0)
	{
		dmg = LR_HOT_DPS;
	}

	for (int r = 1; r <= MaxClients; r++)
	{
		if (!IsClientInGame(r) || !IsPlayerAlive(r) || !AJB_IsPrisoner(r))
		{
			continue;
		}

		float rPos[3];
		GetClientAbsOrigin(r, rPos);

		for (int b = 1; b <= MaxClients; b++)
		{
			if (!IsClientInGame(b) || !IsPlayerAlive(b) || !AJB_IsGuard(b))
			{
				continue;
			}

			float bPos[3];
			GetClientAbsOrigin(b, bPos);
			if (GetVectorDistance(rPos, bPos) > 80.0)
			{
				continue;
			}

			SDKHooks_TakeDamage(b, r, 0, dmg, DMG_BURN);
		}
	}

	return Plugin_Continue;
}

Action AJB_LR_OnStartTouch(int entity, int other)
{
	if (!g_bHotReds || !g_bHasCore)
	{
		return Plugin_Continue;
	}

	if (entity < 1 || entity > MaxClients || other < 1 || other > MaxClients)
	{
		return Plugin_Continue;
	}

	if (!IsClientInGame(entity) || !IsPlayerAlive(entity) || !IsClientInGame(other) || !IsPlayerAlive(other))
	{
		return Plugin_Continue;
	}

	// Prisoner touches guard → burn guard (no auto-rebel; damage as world to skip rebel + block).
	int red = 0;
	int blu = 0;
	if (AJB_IsPrisoner(entity) && AJB_IsGuard(other))
	{
		red = entity;
		blu = other;
	}
	else if (AJB_IsPrisoner(other) && AJB_IsGuard(entity))
	{
		red = other;
		blu = entity;
	}
	else
	{
		return Plugin_Continue;
	}

	float dmg = g_cvHotDamage.FloatValue;
	if (dmg < 1.0)
	{
		dmg = LR_HOT_DPS;
	}

	// attacker=0 so core does not mark rebel / block non-rebel prisoner damage.
	SDKHooks_TakeDamage(blu, red, 0, dmg, DMG_BURN);
	return Plugin_Continue;
}

// Instant wish: chosen now → countdown → die. Does not change the rest of the round.
void AJB_LR_DoSuicide(int prisoner)
{
	// End LR menu state immediately (wish already chosen).
	AJB_LR_KillMenuTimer();
	g_bMenuOpen = false;
	g_bAwaitingCustom = false;
	g_iPrisoner = 0;
	AJB_LR_MarkWishChosen();

	AJB_LR_ChatAll1N("LR Chose Suicide", prisoner);

	float delay = g_cvSuicideDelay.FloatValue;
	if (delay < 1.0)
	{
		delay = LR_SUICIDE_DELAY;
	}

	int left = RoundToFloor(delay);
	if (left < 1)
	{
		left = 1;
	}

	AJB_LR_KillSuicideTimer();
	// Store remaining seconds in timer data via userid pack: use repeating 1s countdown.
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(prisoner));
	pack.WriteCell(left);
	g_hSuicideTimer = CreateTimer(1.0, Timer_SuicideCountdown, pack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);

	if (prisoner > 0 && IsClientInGame(prisoner))
	{
		PrintCenterText(prisoner, "%t", "LR Suicide Countdown", left);
	}
}

Action Timer_SuicideCountdown(Handle timer, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	int left = pack.ReadCell();

	int client = GetClientOfUserId(userid);
	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		g_hSuicideTimer = null;
		return Plugin_Stop;
	}

	left--;
	if (left <= 0)
	{
		g_hSuicideTimer = null;
		ForcePlayerSuicide(client);
		return Plugin_Stop;
	}

	// Rewrite pack for next tick (DataPack position after Read is at end; rewrite cells).
	pack.Reset();
	pack.WriteCell(userid);
	pack.WriteCell(left);

	PrintCenterText(client, "%t", "LR Suicide Countdown", left);
	return Plugin_Continue;
}

void AJB_LR_DoLowGravity(int prisoner)
{
	// NEXT round low gravity.
	AJB_LR_QueueWish(prisoner, LRWish_LowGravity, "LR Chose LowGravity");
}

void AJB_LR_DoHideSeek(int prisoner)
{
	// NEXT round Hide and Seek.
	AJB_LR_QueueWish(prisoner, LRWish_HideSeek, "LR Chose HideSeek");
}

// =========================================================================================================
// Hide and Seek
// =========================================================================================================

// Applied at live-round begin (after prep): gather + freeze BLU seekers at the first
// spawn, open cells so RED can run and hide, then run the hide window and 5-min clock.
void AJB_LR_ApplyHideSeek(const char[] chooser)
{
	g_bHideSeek = true;
	AJB_SetRoundState(AJBState_SpecialDay);

	// Doors open so hiders can run.
	AJB_OpenCells();

	// First spawn point for the guards' team — all seekers stack on it (expected).
	int spawn = AJB_LR_FindGuardSpawn();
	float origin[3];
	float angles[3];
	bool haveSpawn = (spawn != -1);
	if (haveSpawn)
	{
		GetEntPropVector(spawn, Prop_Data, "m_vecOrigin", origin);
		GetEntPropVector(spawn, Prop_Data, "m_angRotation", angles);
	}

	float noVel[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || !AJB_IsGuard(i))
		{
			continue;
		}

		if (haveSpawn)
		{
			TeleportEntity(i, origin, angles, noVel);
		}
		AJB_LR_SetSeekerFrozen(i, true);
	}

	// 5-minute HUD clock + authoritative end (hiders win if time runs out).
	float roundTime = g_cvHSRoundTime.FloatValue;
	AJB_SetPhaseTimer(roundTime);

	AJB_LR_KillHSTimers();
	g_hHSEndTimer = CreateTimer(roundTime, Timer_HSEnd, _, TIMER_FLAG_NO_MAPCHANGE);
	g_hHSHideTimer = CreateTimer(g_cvHSHideTime.FloatValue, Timer_HSRelease, _, TIMER_FLAG_NO_MAPCHANGE);

	AJB_LR_ChatAllQueuedApplied(chooser, "LR Applied HideSeek");
}

// Freeze/unfreeze a seeker in place (networked hard lock, like the core prep freeze).
void AJB_LR_SetSeekerFrozen(int client, bool frozen)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	MoveType mt = GetEntityMoveType(client);
	if (mt == MOVETYPE_NOCLIP || mt == MOVETYPE_OBSERVER)
	{
		return;
	}

	if (frozen)
	{
		if (mt != MOVETYPE_NONE)
		{
			SetEntityMoveType(client, MOVETYPE_NONE);
		}
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", 1.0);
	}
	else
	{
		if (mt != MOVETYPE_WALK)
		{
			SetEntityMoveType(client, MOVETYPE_WALK);
		}
		float speed = GetEntPropFloat(client, Prop_Send, "m_flMaxspeed");
		if (speed < 10.0)
		{
			SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", 300.0);
		}
	}
}

// First info_player_teamspawn of the guards' team (fallback: first spawn of any team).
int AJB_LR_FindGuardSpawn()
{
	int guardTeam = AJB_LR_GetGuardsTeam();
	int ent = -1;
	int first = -1;

	while ((ent = FindEntityByClassname(ent, "info_player_teamspawn")) != -1)
	{
		if (!IsValidEntity(ent))
		{
			continue;
		}

		if (first == -1)
		{
			first = ent;
		}

		if (HasEntProp(ent, Prop_Data, "m_iTeamNum")
			&& GetEntProp(ent, Prop_Data, "m_iTeamNum") == guardTeam)
		{
			return ent;
		}
	}

	return first;
}

int AJB_LR_GetGuardsTeam()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && AJB_IsGuard(i))
		{
			return GetClientTeam(i);
		}
	}
	return 3; // BLU default
}

int AJB_LR_GetPrisonersTeam()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && AJB_IsPrisoner(i))
		{
			return GetClientTeam(i);
		}
	}
	return 2; // RED default
}

Action Timer_HSRelease(Handle timer)
{
	g_hHSHideTimer = null;

	if (!g_bHideSeek)
	{
		return Plugin_Stop;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && AJB_IsGuard(i))
		{
			AJB_LR_SetSeekerFrozen(i, false);
		}
	}

	AJB_ChatAll("LR HideSeek Released");
	return Plugin_Stop;
}

Action Timer_HSEnd(Handle timer)
{
	g_hHSEndTimer = null;

	if (!g_bHideSeek || !g_bHasCore)
	{
		return Plugin_Stop;
	}

	// Time up: the hiders (RED) survived → prisoners win.
	AJB_ChatAll("LR HideSeek TimeUp");
	AJB_ForceTeamWin(AJB_LR_GetPrisonersTeam());
	return Plugin_Stop;
}

void AJB_LR_KillHSTimers()
{
	if (g_hHSHideTimer != null)
	{
		delete g_hHSHideTimer;
		g_hHSHideTimer = null;
	}
	if (g_hHSEndTimer != null)
	{
		delete g_hHSEndTimer;
		g_hHSEndTimer = null;
	}
}

// =========================================================================================================
// Cleanup
// =========================================================================================================

void AJB_LR_Cleanup(bool announce)
{
	bool was = (g_iPrisoner > 0 || g_bMenuOpen || g_bAwaitingCustom || g_bHotReds || g_bLowGravity || g_bHideSeek);
	bool wasChoosing = g_bHasCore && AJB_GetRoundState() == AJBState_LRChoosing;

	AJB_LR_KillMenuTimer();
	AJB_LR_KillSuicideTimer();
	AJB_LR_KillHotTimer();
	AJB_LR_KillHSTimers();

	g_iPrisoner = 0;
	g_bMenuOpen = false;
	g_bAwaitingCustom = false;
	g_iFreedayPickCount = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		g_bPickedFreeday[i] = false;
	}

	// Abort while still picking → leave LR phase (do not clear a queued wish).
	if (wasChoosing && g_PendingWish == LRWish_None && g_bHasCore)
	{
		AJB_SetRoundState(AJBState_CellsOpen);
	}

	if (g_bHotReds)
	{
		g_bHotReds = false;
		if (g_bHasCore)
		{
			AJB_SetRebelOnHit(true);
		}
	}

	if (g_bLowGravity)
	{
		g_bLowGravity = false;
		ConVar cv = FindConVar("sv_gravity");
		if (cv != null && g_iSavedGravity >= 0)
		{
			cv.SetInt(g_iSavedGravity);
		}
		g_iSavedGravity = -1;
	}

	if (g_bHideSeek)
	{
		g_bHideSeek = false;
		// Unfreeze any seekers still locked from the hide window.
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i) && AJB_IsGuard(i))
			{
				AJB_LR_SetSeekerFrozen(i, false);
			}
		}
	}

	if (announce && was)
	{
		AJB_ChatAll("LR Aborted");
	}
}

void AJB_LR_KillSuicideTimer()
{
	if (g_hSuicideTimer != null)
	{
		delete g_hSuicideTimer;
		g_hSuicideTimer = null;
	}
}

void AJB_LR_KillHotTimer()
{
	if (g_hHotTimer != null)
	{
		delete g_hHotTimer;
		g_hHotTimer = null;
	}
}

// =========================================================================================================
// Chat helpers
// =========================================================================================================

void AJB_LR_ChatAll1N(const char[] phrase, int player)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", phrase, i, prefix, player);
	}
}

void AJB_LR_ChatAllFreedayOthers(int chooser, int count)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", "LR Chose Freeday Others", i, prefix, chooser, count);
	}
}

void AJB_LR_ChatAllQueuedApplied(const char[] chooserName, const char[] phrase)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		if (chooserName[0] != '\0')
		{
			CPrintToChat(i, "%T", phrase, i, prefix, chooserName);
		}
		else
		{
			CPrintToChat(i, "%T", phrase, i, prefix, "LR");
		}
	}
}

void AJB_LR_ChatAllClassApplied(const char[] chooserName, TFClassType redCls, TFClassType bluCls)
{
	char redName[32];
	char bluName[32];
	AJB_LR_ClassName(redCls, redName, sizeof(redName));
	AJB_LR_ClassName(bluCls, bluName, sizeof(bluName));

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", "LR Applied ClassWarfare", i, prefix,
			chooserName[0] != '\0' ? chooserName : "LR", redName, bluName);
	}
}

void AJB_LR_ChatAllCustomApplied(const char[] chooserName, const char[] text)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", "LR Applied Custom", i, prefix, chooserName[0] != '\0' ? chooserName : "LR", text);
	}
}

void AJB_LR_ChatAllCustom(int chooser, const char[] text)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", "LR Chose Custom", i, prefix, chooser, text);
	}
}

void AJB_LR_ClassName(TFClassType cls, char[] buffer, int maxlen)
{
	switch (cls)
	{
		case TFClass_Scout:    strcopy(buffer, maxlen, "Scout");
		case TFClass_Sniper:   strcopy(buffer, maxlen, "Sniper");
		case TFClass_Soldier:  strcopy(buffer, maxlen, "Soldier");
		case TFClass_DemoMan:  strcopy(buffer, maxlen, "Demoman");
		case TFClass_Medic:    strcopy(buffer, maxlen, "Medic");
		case TFClass_Heavy:    strcopy(buffer, maxlen, "Heavy");
		case TFClass_Pyro:     strcopy(buffer, maxlen, "Pyro");
		case TFClass_Spy:      strcopy(buffer, maxlen, "Spy");
		case TFClass_Engineer: strcopy(buffer, maxlen, "Engineer");
		default:               strcopy(buffer, maxlen, "Class");
	}
}
