// =========================================================================================================
// Another Jailbreak — Last Request
// Classic JB wishes (not melee duels): freeday, warday, class warfare, custom, hot reds,
// suicide, low grav, hide and seek, hunger games.
// =========================================================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <dhooks>

#undef REQUIRE_PLUGIN
#include <ajb/ajb>
#define REQUIRE_PLUGIN

#include <ajb/phrases>

#define PLUGIN_VERSION "1.2.0"

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
// A forced map vote can hijack the panel slot; retry the timeout instead of dropping the offer.
#define LR_REOPEN_RETRY       5.0
#define LR_HG_GRACE_DEFAULT   30.0
#define LR_HG_ROUND_DEFAULT   300.0

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
	LRWish_HideSeek,
	LRWish_HungerGames,
	LRWish_Sniper,
	LRWish_SetAllClass,
	LRWish_GuardMelee
};

enum AJB_SetAllClassTarget
{
	SetAllClass_All = 0,
	SetAllClass_RedOnly,
	SetAllClass_BluOnly
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
ConVar g_cvHGGraceTime;
ConVar g_cvHGRoundTime;
ConVar g_cvSniperMin;
ConVar g_cvSniperMax;
ConVar g_cvSniperForce;
ConVar g_cvEngineFriendlyFire;
ConVar g_cvEngineSvTags;

DynamicHook g_hSetWinningTeam;
bool g_bHasCore;

int g_iPrisoner;
bool g_bMenuOpen;
bool g_bAwaitingCustom;
bool g_bHotReds;
bool g_bLowGravity;
int g_iSavedGravity = -1;

// Sniper wish: random kills during round with velocity push
bool g_bSniper;
Handle g_hSniperTimer;

// Hide and Seek: BLU are frozen "seekers" for the hide window, RED run and hide.
bool g_bHideSeek;

// Hunger Games: everyone on RED, grace then friendly fire FFA.
bool g_bHungerGames;
bool g_bHGGrace;           // true until FF is enabled
bool g_bHGMeleeOnly;
bool g_bHGClassLock;       // forced class for everyone
TFClassType g_HGClass;
bool g_bHGEnding;          // true while we force the round end (ignore extra death checks)
bool g_bHGOriginalBlu[MAXPLAYERS + 1];

// Guard Melee: guards are stripped to melee only next round
bool g_bGuardMeleeActive;

// Set All Class: forced class for target team(s) next round
bool g_bSetAllClassActive;
AJB_SetAllClassTarget g_SetAllClassTarget;
TFClassType g_SetAllClassType;

Handle g_hMenuTimer;
Handle g_hMenuWarnTimer;
Handle g_hSuicideTimer;
Handle g_hHotTimer;
Handle g_hHSHideTimer;   // fires when the hide window ends → release seekers
Handle g_hHSEndTimer;    // authoritative 5-minute round end (hiders win on timeout)
Handle g_hHGGraceTimer;
Handle g_hHGEndTimer;

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

// Hunger Games options chosen with the wish (applied next live round).
bool g_PendingHGMeleeOnly;
bool g_PendingHGClassRandom;
TFClassType g_PendingHGClass; // Unknown = any (keep each player's class)

// Set All Class options chosen with the wish
AJB_SetAllClassTarget g_PendingSetAllClassTarget;
TFClassType g_PendingSetAllClassType;

// Draft options while the chooser is still in the HG / SetAllClass config menus.
bool g_bHGDraftMelee;
bool g_bHGDraftClassRandom;
TFClassType g_HGDraftClass;

AJB_SetAllClassTarget g_DraftSetAllClassTarget;
TFClassType g_DraftSetAllClassType;

// Active Class Warfare lock (this live round).
bool g_bClassWarfareActive;
TFClassType g_ActiveClassRed;
TFClassType g_ActiveClassBlu;



bool AJB_LR_IsGrantBlocked()
{
	if (!g_bHasCore)
	{
		return false;
	}
	return (g_PendingWish != LRWish_None || g_bMenuOpen || g_bAwaitingCustom || g_iPrisoner > 0);
}

void AJB_LR_CloseMenuState()
{
	g_bMenuOpen = false;
	g_bAwaitingCustom = false;
	g_iPrisoner = 0;
	AJB_LR_KillMenuTimer();
}

void AJB_LR_MarkWishChosen()
{
	if (g_bHasCore && AJB_GetRoundState() == AJBState_LRChoosing)
	{
		AJB_SetRoundState(AJBState_CellsOpen);
	}
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

Action Timer_MenuWarn(Handle timer, int userid)
{
	g_hMenuWarnTimer = null;
	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client) && (g_bMenuOpen || g_bAwaitingCustom) && client == g_iPrisoner)
	{
		AJB_Chat(client, "LR Menu Warn");
	}
	return Plugin_Stop;
}

Action Timer_MenuTimeout(Handle timer, int userid)
{
	g_hMenuTimer = null;
	if (!g_bMenuOpen)
	{
		return Plugin_Stop;
	}

	g_bMenuOpen = false;
	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client))
	{
		AJB_LR_ChatAll1N("LR Timeout", client);
	}

	AJB_LR_Cleanup(false);
	return Plugin_Stop;
}

void AJB_LR_StartMenuTimers(int prisoner)
{
	AJB_LR_KillMenuTimer();
	float time = g_cvMenuTime.FloatValue;
	if (time < 5.0)
	{
		time = 30.0;
	}
	int userid = GetClientUserId(prisoner);
	g_hMenuTimer = CreateTimer(time, Timer_MenuTimeout, userid, TIMER_FLAG_NO_MAPCHANGE);
	if (time > 15.0)
	{
		g_hMenuWarnTimer = CreateTimer(time - 15.0, Timer_MenuWarn, userid, TIMER_FLAG_NO_MAPCHANGE);
	}
}

void AJB_LR_ShowGrantMenu(int warden)
{
	if (warden < 1 || !IsClientInGame(warden) || !IsPlayerAlive(warden))
	{
		return;
	}

	Menu menu = new Menu(MenuHandler_Grant);
	char title[64];
	Format(title, sizeof(title), "%T", "LR Grant Menu Title", warden);
	menu.SetTitle(title);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && AJB_IsPrisoner(i))
		{
			char useridStr[16], name[64];
			IntToString(GetClientUserId(i), useridStr, sizeof(useridStr));
			GetClientName(i, name, sizeof(name));
			menu.AddItem(useridStr, name);
		}
	}

	menu.ExitButton = true;
	menu.Display(warden, 20);
}

public int MenuHandler_Grant(Menu menu, MenuAction action, int param1, int param2)
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

	int warden = param1;
	if (AJB_GetWarden() != warden)
	{
		return 0;
	}

	char info[16];
	menu.GetItem(param2, info, sizeof(info));
	int target = GetClientOfUserId(StringToInt(info));

	if (target > 0 && IsClientInGame(target) && IsPlayerAlive(target) && AJB_IsPrisoner(target))
	{
		AJB_LR_OpenForPrisoner(target);
		AJB_LR_ChatAll2N("LR Granted By Warden", warden, target);
	}
	return 0;
}

void AJB_LR_OpenForPrisoner(int prisoner)
{
	if (prisoner < 1 || !IsClientInGame(prisoner) || !IsPlayerAlive(prisoner))
	{
		return;
	}

	g_iPrisoner = prisoner;
	g_bMenuOpen = true;
	g_bAwaitingCustom = false;

	if (g_bHasCore)
	{
		AJB_SetRoundState(AJBState_LRChoosing);
	}

	AJB_LR_ShowWishMenu(prisoner);
	AJB_LR_StartMenuTimers(prisoner);
}

void AJB_LR_ShowWishMenu(int prisoner)
{
	if (prisoner < 1 || !IsClientInGame(prisoner) || !IsPlayerAlive(prisoner))
	{
		return;
	}

	Menu menu = new Menu(MenuHandler_Wish);
	char title[64], line[96];
	Format(title, sizeof(title), "%T", "LR Wish Menu Title", prisoner);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", "LR Wish FreedayMe", prisoner);
	menu.AddItem("freeday_me", line);

	Format(line, sizeof(line), "%T", "LR Wish FreedayOthers", prisoner);
	menu.AddItem("freeday_others", line);

	Format(line, sizeof(line), "%T", "LR Wish FreedayAll", prisoner);
	menu.AddItem("freeday_all", line);

	Format(line, sizeof(line), "%T", "LR Wish WarDay", prisoner);
	menu.AddItem("warday", line);

	Format(line, sizeof(line), "%T", "LR Wish ClassWarfare", prisoner);
	menu.AddItem("classwarfare", line);

	Format(line, sizeof(line), "%T", "LR Wish SetAllClass", prisoner);
	menu.AddItem("setallclass", line);

	Format(line, sizeof(line), "%T", "LR Wish GuardMelee", prisoner);
	menu.AddItem("guardmelee", line);

	Format(line, sizeof(line), "%T", "LR Wish Custom", prisoner);
	menu.AddItem("custom", line);

	Format(line, sizeof(line), "%T", "LR Wish HotReds", prisoner);
	menu.AddItem("hotreds", line);

	Format(line, sizeof(line), "%T", "LR Wish LowGravity", prisoner);
	menu.AddItem("lowgravity", line);

	Format(line, sizeof(line), "%T", "LR Wish HideSeek", prisoner);
	menu.AddItem("hideseek", line);

	Format(line, sizeof(line), "%T", "LR Wish HungerGames", prisoner);
	menu.AddItem("hungergames", line);

	Format(line, sizeof(line), "%T", "LR Wish Sniper", prisoner);
	menu.AddItem("sniper", line);

	Format(line, sizeof(line), "%T", "LR Wish Suicide", prisoner);
	menu.AddItem("suicide", line);

	menu.ExitButton = false;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));
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

	char info[32];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "freeday_me"))
	{
		AJB_LR_DoFreedayMe(client);
	}
	else if (StrEqual(info, "freeday_others"))
	{
		g_iFreedayMenuPage = 0;
		g_iFreedayPickCount = 0;
		for (int i = 1; i <= MaxClients; i++) g_bPickedFreeday[i] = false;
		AJB_LR_ShowFreedayOthersMenu(client);
	}
	else if (StrEqual(info, "freeday_all"))
	{
		AJB_LR_DoFreedayAll(client);
	}
	else if (StrEqual(info, "warday"))
	{
		AJB_LR_DoWarDay(client);
	}
	else if (StrEqual(info, "classwarfare"))
	{
		AJB_LR_DoClassWarfare(client);
	}
	else if (StrEqual(info, "setallclass"))
	{
		AJB_LR_StartSetAllClassConfig(client);
	}
	else if (StrEqual(info, "guardmelee"))
	{
		AJB_LR_DoGuardMelee(client);
	}
	else if (StrEqual(info, "custom"))
	{
		AJB_LR_StartCustom(client);
	}
	else if (StrEqual(info, "hotreds"))
	{
		AJB_LR_DoHotReds(client);
	}
	else if (StrEqual(info, "lowgravity"))
	{
		AJB_LR_DoLowGravity(client);
	}
	else if (StrEqual(info, "hideseek"))
	{
		AJB_LR_DoHideSeek(client);
	}
	else if (StrEqual(info, "hungergames"))
	{
		AJB_LR_StartHungerGamesConfig(client);
	}
	else if (StrEqual(info, "sniper"))
	{
		AJB_LR_DoSniper(client);
	}
	else if (StrEqual(info, "suicide"))
	{
		AJB_LR_DoSuicide(client);
	}

	return 0;
}

void AJB_LR_HG_OnPlayerDeath(int victim)
{
	if (!g_bHungerGames || g_bHGEnding)
	{
		return;
	}

	if (victim > 0 && victim <= MaxClients && g_bHGOriginalBlu[victim])
	{
		g_bHGOriginalBlu[victim] = false;
		if (IsClientInGame(victim))
		{
			TF2_ChangeClientTeam(victim, view_as<TFTeam>(AJB_LR_GetGuardsTeam()));
		}
	}

	RequestFrame(Frame_HGCheckWinner);
}









public void OnMapStart()
{
	if (g_hSetWinningTeam != null)
	{
		g_hSetWinningTeam.HookGamerules(Hook_Pre, Detour_SetWinningTeam);
	}
}

public MRESReturn Detour_SetWinningTeam(DHookReturn hReturn, DHookParam hParams)
{
	if (g_bHungerGames && !g_bHGEnding)
	{
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

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
	g_cvHGGraceTime = CreateConVar("sm_ajb_lr_hg_grace_time", "30", "Hunger Games: seconds after live round begin before friendly fire turns on.", _, true, 5.0, true, 120.0);
	g_cvHGRoundTime = CreateConVar("sm_ajb_lr_hg_round_time", "300", "Hunger Games: total round duration in seconds (survivors win on timeout).", _, true, 60.0, true, 900.0);
	g_cvSniperMin = CreateConVar("sm_ajb_lr_sniper_min", "10.0", "Sniper: minimum interval in seconds between sniper shots.", _, true, 2.0, true, 300.0);
	g_cvSniperMax = CreateConVar("sm_ajb_lr_sniper_max", "25.0", "Sniper: maximum interval in seconds between sniper shots.", _, true, 5.0, true, 600.0);
	g_cvSniperForce = CreateConVar("sm_ajb_lr_sniper_force", "800.0", "Sniper: ragdoll / impact force impulse.", _, true, 100.0, true, 3000.0);

	g_cvEngineFriendlyFire = FindConVar("mp_friendlyfire");
	g_cvEngineSvTags = FindConVar("sv_tags");

	GameData conf = new GameData("ajb.games");
	if (conf != null)
	{
		int offset = conf.GetOffset("SetWinningTeam");
		if (offset != -1)
		{
			g_hSetWinningTeam = new DynamicHook(offset, HookType_GameRules, ReturnType_Void, ThisPointer_Ignore);
			g_hSetWinningTeam.AddParam(HookParamType_Int);
			g_hSetWinningTeam.AddParam(HookParamType_Int);
			g_hSetWinningTeam.AddParam(HookParamType_Bool);
			g_hSetWinningTeam.AddParam(HookParamType_Bool);
			g_hSetWinningTeam.AddParam(HookParamType_Bool);
			g_hSetWinningTeam.AddParam(HookParamType_Bool);
		}
		else
		{
			LogError("[AJB-LR] No se encontró el offset de SetWinningTeam en ajb.games.txt");
		}
		delete conf;
	}
	else
	{
		LogError("[AJB-LR] No se pudo cargar ajb.games.txt");
	}

	AutoExecConfig(true, "ajb_lastrequest");

	LoadTranslations("ajb_lastrequest.phrases");
	LoadTranslations("ajb_admin.phrases");
	LoadTranslations("ajb.phrases");
	LoadTranslations("common.phrases");

	RegConsoleCmd("sm_ajb_lr", Command_LR, "Warden: grant Last Request to a prisoner.");
	RegAdminCmd("sm_ajb_lr_force", Command_ForceLR, ADMFLAG_GENERIC, "Force LR menu for a living prisoner.");
	RegConsoleCmd("sm_reopenlr", Command_ReopenLR, "Prisoner: reopen your Last Request menu if it got closed (e.g. by a map vote).");
	RegConsoleCmd("sm_ajb_reopenlr", Command_ReopenLR, "Prisoner: reopen your Last Request menu if it got closed (e.g. by a map vote).");

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	// Pre: swallow engine auto-wins while HG is live; only g_bHGEnding ends (last standing / timeout).
	HookEvent("teamplay_round_win", Event_RoundWinPre, EventHookMode_Pre);
	HookEvent("teamplay_round_win", Event_RoundWin, EventHookMode_PostNoCopy);

	AddCommandListener(Listener_Say, "say");
	AddCommandListener(Listener_Say, "say_team");

	g_bHasCore = LibraryExists(AJB_LIBRARY);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SDKHook(i, SDKHook_StartTouch, AJB_LR_OnStartTouch);
			SDKHook(i, SDKHook_OnTakeDamage, AJB_LR_OnTakeDamage);
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
	SDKHook(client, SDKHook_OnTakeDamage, AJB_LR_OnTakeDamage);
	g_bPickedFreeday[client] = false;
}

public Action AJB_LR_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (!g_bHungerGames)
	{
		return Plugin_Continue;
	}

	if (attacker > 0 && attacker <= MaxClients && victim > 0 && victim <= MaxClients)
	{
		if (g_bHGGrace)
		{
			return Plugin_Handled;
		}

		int redTeam = AJB_LR_GetPrisonersTeam();
		if (GetClientTeam(attacker) != redTeam || GetClientTeam(victim) != redTeam)
		{
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
	g_bPickedFreeday[client] = false;
	g_bHGOriginalBlu[client] = false;

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

public void AJB_OnLiveRoundBegin()
{
	AJB_LR_ApplyPendingWish();
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	// Clear active mid-round effects only. Pending wish waits for AJB_OnLiveRoundBegin
	// (after prep / real round start — never during preround).
	AJB_LR_ClearClassWarfareActive();
	AJB_LR_Cleanup(false);
}

// While HG is running, only plugin-driven ends (g_bHGEnding) should be visible as a win.
// Empty-team auto-wins are blocked by mp_ignore_round_win_conditions (set before team moves).
// If an unexpected win still fires, suppress client broadcast but do NOT Plugin_Handled —
// Post hooks (including our cleanup) must still run.
Action Event_RoundWinPre(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bHungerGames || g_bHGEnding)
	{
		return Plugin_Continue;
	}

	event.BroadcastDisabled = true;
	LogMessage("[AJB-LR] Unexpected teamplay_round_win during Hunger Games (not plugin-ended); suppressed broadcast.");
	return Plugin_Changed;
}

void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
	// Keep g_PendingWish — it is for the NEXT live round.
	AJB_LR_ClearClassWarfareActive();
	// Hunger Games may still be active until win cleanup — tear it down without announcing abort.
	AJB_LR_Cleanup(false);
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	if (g_bHungerGames)
	{
		AJB_LR_HG_OnPlayerSpawn(client);
		return;
	}

	if (g_bClassWarfareActive)
	{
		AJB_LR_ForceClassWarfareClass(client);
	}

	if (g_bSetAllClassActive)
	{
		AJB_LR_ForceSetAllClass(client);
	}

	if (g_bGuardMeleeActive && g_bHasCore && AJB_IsGuard(client))
	{
		RequestFrame(Frame_StripGuardToMelee, GetClientUserId(client));
	}
}

void Frame_StripGuardToMelee(int userid)
{
	if (!g_bGuardMeleeActive)
	{
		return;
	}

	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && AJB_IsGuard(client))
	{
		AJB_LR_StripGuardToMelee(client);
	}
}

void AJB_LR_StripGuardToMelee(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	// Remove all weapon slots except Melee (slot 2)
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Primary);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Secondary);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Grenade);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Building);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_PDA);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Item1);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Item2);

	if (TF2_GetPlayerClass(client) == TFClass_Spy)
	{
		if (TF2_IsPlayerInCondition(client, TFCond_Stealthed))
		{
			TF2_RemoveCondition(client, TFCond_Stealthed);
		}
		if (TF2_IsPlayerInCondition(client, TFCond_Disguised))
		{
			TF2_RemoveCondition(client, TFCond_Disguised);
		}
	}

	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if (melee != -1 && IsValidEntity(melee))
	{
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", melee);
	}
}

void AJB_LR_ClearPendingWish()
{
	g_PendingWish = LRWish_None;
	g_sPendingCustom[0] = '\0';
	g_PendingClassRed = TFClass_Unknown;
	g_PendingClassBlu = TFClass_Unknown;
	g_sPendingChooserName[0] = '\0';
	g_PendingHGMeleeOnly = false;
	g_PendingHGClassRandom = false;
	g_PendingHGClass = TFClass_Unknown;
	g_PendingSetAllClassTarget = SetAllClass_All;
	g_PendingSetAllClassType = TFClass_Scout;
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
	bool meleeOnly = g_PendingHGMeleeOnly;
	bool classRandom = g_PendingHGClassRandom;
	TFClassType hgClass = g_PendingHGClass;
	AJB_SetAllClassTarget setAllTarget = g_PendingSetAllClassTarget;
	TFClassType setAllClass = g_PendingSetAllClassType;
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
		case LRWish_SetAllClass:
		{
			AJB_LR_ApplySetAllClass(chooser, setAllTarget, setAllClass);
		}
		case LRWish_GuardMelee:
		{
			AJB_LR_ApplyGuardMelee(chooser);
		}
		case LRWish_Custom:
		{
			// Custom is a normal round: only re-announce the wish text (no auto-open cells).
			AJB_LR_ChatAllCustomApplied(chooser, custom);
		}
		case LRWish_HotReds:
		{
			g_bHotReds = true;
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
		case LRWish_HungerGames:
		{
			AJB_LR_ApplyHungerGames(chooser, meleeOnly, classRandom, hgClass);
		}
		case LRWish_Sniper:
		{
			AJB_LR_ApplySniper(chooser);
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

	// Snapshot living guards + origins once (O(n)) so the red×guard proximity test below is not
	// re-fetching positions and re-testing team membership for every pair each 0.5s tick.
	int guards[MAXPLAYERS];
	float guardPos[MAXPLAYERS][3];
	int guardCount = 0;
	for (int b = 1; b <= MaxClients; b++)
	{
		if (IsClientInGame(b) && IsPlayerAlive(b) && AJB_IsGuard(b))
		{
			guards[guardCount] = b;
			GetClientAbsOrigin(b, guardPos[guardCount]);
			guardCount++;
		}
	}

	if (guardCount == 0)
	{
		return Plugin_Continue;
	}

	for (int r = 1; r <= MaxClients; r++)
	{
		if (!IsClientInGame(r) || !IsPlayerAlive(r) || !AJB_IsPrisoner(r))
		{
			continue;
		}

		float rPos[3];
		GetClientAbsOrigin(r, rPos);

		for (int g = 0; g < guardCount; g++)
		{
			if (GetVectorDistance(rPos, guardPos[g]) <= 80.0)
			{
				SDKHooks_TakeDamage(guards[g], 0, 0, dmg, DMG_BURN);
			}
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
	int blu = 0;
	if (AJB_IsPrisoner(entity) && AJB_IsGuard(other))
	{
		blu = other;
	}
	else if (AJB_IsPrisoner(other) && AJB_IsGuard(entity))
	{
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
	SDKHooks_TakeDamage(blu, 0, 0, dmg, DMG_BURN);
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
// Hunger Games — config menu (class + weapons) then queue for next live round
// =========================================================================================================

void AJB_LR_StartHungerGamesConfig(int prisoner)
{
	// Defaults: any class, full loadout. Chooser can change before confirm.
	g_bHGDraftMelee = false;
	g_bHGDraftClassRandom = false;
	g_HGDraftClass = TFClass_Unknown;
	g_bMenuOpen = true;
	AJB_LR_ShowHungerGamesMenu(prisoner);
	AJB_LR_StartMenuTimers(prisoner);
}

void AJB_LR_ShowHungerGamesMenu(int prisoner)
{
	if (prisoner < 1 || !IsClientInGame(prisoner))
	{
		return;
	}

	Menu menu = new Menu(MenuHandler_HungerGames);
	char title[64];
	char line[96];
	char classLabel[32];
	AJB_LR_HG_ClassOptionLabel(prisoner, classLabel, sizeof(classLabel));

	Format(title, sizeof(title), "%T", "LR HG Menu Title", prisoner);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", "LR HG Opt Class", prisoner, classLabel);
	menu.AddItem("class", line);

	Format(line, sizeof(line), "%T",
		g_bHGDraftMelee ? "LR HG Opt Melee On" : "LR HG Opt Melee Off", prisoner);
	menu.AddItem("melee", line);

	Format(line, sizeof(line), "%T", "LR HG Opt Confirm", prisoner);
	menu.AddItem("confirm", line);

	Format(line, sizeof(line), "%T", "LR HG Opt Back", prisoner);
	menu.AddItem("back", line);

	menu.ExitButton = false;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));
}

void AJB_LR_HG_ClassOptionLabel(int client, char[] buffer, int maxlen)
{
	if (g_bHGDraftClassRandom)
	{
		Format(buffer, maxlen, "%T", "LR HG Class Random", client);
		return;
	}

	if (g_HGDraftClass == TFClass_Unknown)
	{
		Format(buffer, maxlen, "%T", "LR HG Class Any", client);
		return;
	}

	char name[32];
	AJB_LR_ClassName(g_HGDraftClass, name, sizeof(name));
	strcopy(buffer, maxlen, name);
}

public int MenuHandler_HungerGames(Menu menu, MenuAction action, int param1, int param2)
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

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "class"))
	{
		AJB_LR_ShowHungerGamesClassMenu(client);
		return 0;
	}

	if (StrEqual(info, "melee"))
	{
		g_bHGDraftMelee = !g_bHGDraftMelee;
		AJB_LR_ShowHungerGamesMenu(client);
		return 0;
	}

	if (StrEqual(info, "back"))
	{
		AJB_LR_ShowWishMenu(client);
		return 0;
	}

	if (StrEqual(info, "confirm"))
	{
		AJB_LR_KillMenuTimer();
		g_bMenuOpen = false;

		AJB_LR_ClearPendingWish();
		g_PendingWish = LRWish_HungerGames;
		g_PendingHGMeleeOnly = g_bHGDraftMelee;
		g_PendingHGClassRandom = g_bHGDraftClassRandom;
		g_PendingHGClass = g_HGDraftClass;
		AJB_LR_RememberChooser(client);
		AJB_LR_ChatAllHungerGamesChose(client, g_bHGDraftMelee, g_bHGDraftClassRandom, g_HGDraftClass);
		AJB_LR_CloseMenuState();
		AJB_LR_MarkWishChosen();
	}

	return 0;
}

void AJB_LR_ShowHungerGamesClassMenu(int prisoner)
{
	Menu menu = new Menu(MenuHandler_HungerGamesClass);
	char title[64];
	char line[64];
	Format(title, sizeof(title), "%T", "LR HG Class Title", prisoner);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", "LR HG Class Any", prisoner);
	menu.AddItem("any", line);
	Format(line, sizeof(line), "%T", "LR HG Class Random", prisoner);
	menu.AddItem("random", line);

	static const TFClassType kClasses[] = {
		TFClass_Scout, TFClass_Soldier, TFClass_Pyro, TFClass_DemoMan,
		TFClass_Heavy, TFClass_Engineer, TFClass_Medic, TFClass_Sniper, TFClass_Spy
	};

	for (int i = 0; i < sizeof(kClasses); i++)
	{
		char info[8];
		IntToString(view_as<int>(kClasses[i]), info, sizeof(info));
		AJB_LR_ClassName(kClasses[i], line, sizeof(line));
		menu.AddItem(info, line);
	}

	menu.ExitButton = false;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));
}

public int MenuHandler_HungerGamesClass(Menu menu, MenuAction action, int param1, int param2)
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

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "any"))
	{
		g_bHGDraftClassRandom = false;
		g_HGDraftClass = TFClass_Unknown;
	}
	else if (StrEqual(info, "random"))
	{
		g_bHGDraftClassRandom = true;
		g_HGDraftClass = TFClass_Unknown;
	}
	else
	{
		g_bHGDraftClassRandom = false;
		g_HGDraftClass = view_as<TFClassType>(StringToInt(info));
	}

	AJB_LR_ShowHungerGamesMenu(client);
	return 0;
}

void AJB_LR_ChatAllHungerGamesChose(int chooser, bool meleeOnly, bool classRandom, TFClassType cls)
{
	char fixedClass[32];
	if (!classRandom && cls != TFClass_Unknown)
	{
		AJB_LR_ClassName(cls, fixedClass, sizeof(fixedClass));
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));

		char locClass[32];
		char locWeapons[32];
		if (classRandom)
		{
			Format(locClass, sizeof(locClass), "%T", "LR HG Class Random", i);
		}
		else if (cls == TFClass_Unknown)
		{
			Format(locClass, sizeof(locClass), "%T", "LR HG Class Any", i);
		}
		else
		{
			strcopy(locClass, sizeof(locClass), fixedClass);
		}
		Format(locWeapons, sizeof(locWeapons), "%T",
			meleeOnly ? "LR HG Weapons Melee" : "LR HG Weapons Full", i);

		CPrintToChat(i, "%T", "LR Chose HungerGames", i, prefix, chooser, locClass, locWeapons);
	}
}

// =========================================================================================================
// Hunger Games — live round
// =========================================================================================================

void AJB_LR_ApplyHungerGames(const char[] chooser, bool meleeOnly, bool classRandom, TFClassType cls)
{
	g_bHungerGames = true;
	g_bHGGrace = true;
	g_bHGEnding = false;
	g_bHGMeleeOnly = meleeOnly;
	g_bHGClassLock = false;
	g_HGClass = TFClass_Unknown;

	if (classRandom)
	{
		g_bHGClassLock = true;
		g_HGClass = view_as<TFClassType>(GetRandomInt(view_as<int>(TFClass_Scout), view_as<int>(TFClass_Engineer)));
	}
	else if (cls != TFClass_Unknown)
	{
		g_bHGClassLock = true;
		g_HGClass = cls;
	}

	// Combat day: full loadouts allowed, no warden claim, freekill rules relaxed.
	AJB_BeginCombatDay();
	AJB_ClearWarden();
	AJB_SetRebelOnHit(false);

	// Friendly fire stays off for the grace window (same-team damage blocked by engine).
	AJB_LR_HG_SetFriendlyFire(false);

	// Core jail clock still awards guards on expire — HG owns the end (last standing / timeout).
	AJB_ClearPhaseTimer();

	// Cells must be open so RED and BLU can reach each other.
	AJB_OpenCells();
	if (g_bHasCore)
	{
		AJB_SetRoundState(AJBState_SpecialDay);
	}

	// Force everyone onto the RED team and respawn dead prisoners.
	int redTeam = AJB_LR_GetPrisonersTeam();
	int blueTeam = AJB_LR_GetGuardsTeam();
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bHGOriginalBlu[i] = false;
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			// Move Guards to RED team
			if (GetClientTeam(i) == blueTeam)
			{
				g_bHGOriginalBlu[i] = true;
				TF2_ChangeClientTeam(i, view_as<TFTeam>(redTeam));
			}

			// Respawn if they are dead (so everyone participates)
			if (!IsPlayerAlive(i) && AJB_IsPrisoner(i))
			{
				TF2_RespawnPlayer(i);
			}
		}
	}

	RequestFrame(Frame_HGArmAll);

	float grace = g_cvHGGraceTime.FloatValue;
	if (grace < 5.0)
	{
		grace = LR_HG_GRACE_DEFAULT;
	}

	float roundTime = g_cvHGRoundTime.FloatValue;
	if (roundTime < 60.0)
	{
		roundTime = LR_HG_ROUND_DEFAULT;
	}

	// HUD only — authoritative end is g_hHGEndTimer / last-standing (not core guards-win expire).
	AJB_SetPhaseTimer(roundTime);
	AJB_LR_KillHGTimers();
	g_hHGGraceTimer = CreateTimer(grace, Timer_HGGraceEnd, _, TIMER_FLAG_NO_MAPCHANGE);
	g_hHGEndTimer = CreateTimer(roundTime, Timer_HGEnd, _, TIMER_FLAG_NO_MAPCHANGE);

	AJB_LR_ChatAllHungerGamesApplied(chooser, meleeOnly, g_bHGClassLock, g_HGClass, grace);
}

void Frame_HGArmAll(any data)
{
	if (!g_bHungerGames)
	{
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && AJB_IsPrisoner(i))
		{
			AJB_LR_HG_ArmPlayer(i);
		}
	}
}

void AJB_LR_HG_OnPlayerSpawn(int client)
{
	if (!g_bHungerGames || !IsClientInGame(client) || IsFakeClient(client))
	{
		return;
	}

	int team = GetClientTeam(client);
	if (team < 2)
	{
		return;
	}

	RequestFrame(Frame_HGArmClient, GetClientUserId(client));
}

void Frame_HGArmClient(int userid)
{
	if (!g_bHungerGames)
	{
		return;
	}

	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && AJB_IsPrisoner(client))
	{
		AJB_LR_HG_ArmPlayer(client);
	}
}

void AJB_LR_HG_ArmPlayer(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	if (g_bHGClassLock && g_HGClass != TFClass_Unknown)
	{
		if (TF2_GetPlayerClass(client) != g_HGClass)
		{
			TF2_SetPlayerClass(client, g_HGClass, false, true);
		}
	}

	// Full unrestricted stock loadout (combat day already cleared rebel/freeday flags).
	TF2_RegeneratePlayer(client);

	if (g_bHGMeleeOnly)
	{
		AJB_LR_HG_StripToMelee(client);
	}
}

void AJB_LR_HG_StripToMelee(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	// Hard melee-only (no prisoner allowlist) so HG is fair for everyone.
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Primary);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Secondary);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Grenade);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Building);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_PDA);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Item1);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Item2);

	if (TF2_GetPlayerClass(client) == TFClass_Spy)
	{
		if (TF2_IsPlayerInCondition(client, TFCond_Stealthed))
		{
			TF2_RemoveCondition(client, TFCond_Stealthed);
		}
		if (TF2_IsPlayerInCondition(client, TFCond_Disguised))
		{
			TF2_RemoveCondition(client, TFCond_Disguised);
		}
	}

	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if (melee != -1 && IsValidEntity(melee))
	{
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", melee);
	}
}

void AJB_LR_HG_SetFriendlyFire(bool enabled)
{
	if (g_cvEngineFriendlyFire == null)
	{
		return;
	}

	int ffFlags = g_cvEngineFriendlyFire.Flags;
	g_cvEngineFriendlyFire.Flags = ffFlags & ~FCVAR_NOTIFY;

	int tagFlags = 0;
	if (g_cvEngineSvTags != null)
	{
		tagFlags = g_cvEngineSvTags.Flags;
		g_cvEngineSvTags.Flags = tagFlags & ~FCVAR_NOTIFY;
	}

	g_cvEngineFriendlyFire.SetInt(enabled ? 1 : 0);

	g_cvEngineFriendlyFire.Flags = ffFlags;
	if (g_cvEngineSvTags != null)
	{
		g_cvEngineSvTags.Flags = tagFlags;
	}
}

Action Timer_HGGraceEnd(Handle timer)
{
	g_hHGGraceTimer = null;

	if (!g_bHungerGames)
	{
		return Plugin_Stop;
	}

	g_bHGGrace = false;
	AJB_LR_HG_SetFriendlyFire(true);
	AJB_ChatAll("LR HG Grace End");
	return Plugin_Stop;
}

Action Timer_HGEnd(Handle timer)
{
	g_hHGEndTimer = null;

	if (!g_bHungerGames || !g_bHasCore || g_bHGEnding)
	{
		return Plugin_Stop;
	}

	g_bHGEnding = true;
	AJB_ChatAll("LR HG TimeUp");
	AJB_ForceTeamWin(AJB_LR_GetPrisonersTeam());
	return Plugin_Stop;
}

void Frame_HGCheckWinner(any data)
{
	if (!g_bHungerGames || g_bHGEnding || !g_bHasCore)
	{
		return;
	}

	// Grace is loot/scatter time — do not end on deaths during the window.
	if (g_bHGGrace)
	{
		return;
	}

	int alive = 0;
	int last = 0;
	int redTeam = AJB_LR_GetPrisonersTeam();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i) && GetClientTeam(i) == redTeam)
		{
			alive++;
			last = i;
		}
	}

	if (alive == 1 && last > 0)
	{
		g_bHGEnding = true;
		AJB_LR_ChatAll1N("LR HG Winner", last);
		AJB_ForceTeamWin(GetClientTeam(last));
	}
	else if (alive <= 0)
	{
		g_bHGEnding = true;
		AJB_ChatAll("LR HG NoWinner");
		AJB_ForceTeamWin(AJB_LR_GetPrisonersTeam());
	}
}

void AJB_LR_KillHGTimers()
{
	if (g_hHGGraceTimer != null)
	{
		delete g_hHGGraceTimer;
		g_hHGGraceTimer = null;
	}
	if (g_hHGEndTimer != null)
	{
		delete g_hHGEndTimer;
		g_hHGEndTimer = null;
	}
}

void AJB_LR_ChatAllHungerGamesApplied(const char[] chooserName, bool meleeOnly, bool classLock, TFClassType cls, float grace)
{
	char classLabel[32];
	if (!classLock)
	{
		strcopy(classLabel, sizeof(classLabel), "Any");
	}
	else
	{
		AJB_LR_ClassName(cls, classLabel, sizeof(classLabel));
	}

	int graceSec = RoundToFloor(grace);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));

		char locClass[32];
		char locWeapons[32];
		if (!classLock)
		{
			Format(locClass, sizeof(locClass), "%T", "LR HG Class Any", i);
		}
		else
		{
			strcopy(locClass, sizeof(locClass), classLabel);
		}
		Format(locWeapons, sizeof(locWeapons), "%T",
			meleeOnly ? "LR HG Weapons Melee" : "LR HG Weapons Full", i);

		CPrintToChat(i, "%T", "LR Applied HungerGames", i, prefix,
			chooserName[0] != '\0' ? chooserName : "LR", locClass, locWeapons, graceSec);
	}
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

void AJB_LR_DoSniper(int prisoner)
{
	// NEXT round Sniper wish.
	AJB_LR_QueueWish(prisoner, LRWish_Sniper, "LR Chose Sniper");
}

void AJB_LR_ApplySniper(const char[] chooser)
{
	g_bSniper = true;
	AJB_LR_KillSniperTimer();

	float minTime = g_cvSniperMin.FloatValue;
	float maxTime = g_cvSniperMax.FloatValue;
	if (maxTime < minTime)
	{
		maxTime = minTime;
	}

	float nextInterval = GetRandomFloat(minTime, maxTime);
	g_hSniperTimer = CreateTimer(nextInterval, Timer_SniperShot, _, TIMER_FLAG_NO_MAPCHANGE);

	AJB_LR_ChatAllQueuedApplied(chooser, "LR Applied Sniper");
}

Action Timer_SniperShot(Handle timer)
{
	g_hSniperTimer = null;

	if (!g_bSniper || !g_bHasCore || !AJB_IsEnabled())
	{
		return Plugin_Stop;
	}

	// Pick a random alive player (Prisoner or Guard)
	int candidates[MAXPLAYERS];
	int count = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i))
		{
			// Ignore indestructible or godmode if any, but standard alive players:
			candidates[count++] = i;
		}
	}

	if (count > 0)
	{
		int victim = candidates[GetRandomInt(0, count - 1)];

		// Play sniper gunshot sound globally
		EmitSoundToAll("weapons/sniper_railgun_shot.wav", victim, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE);
		EmitSoundToAll("weapons/sniper_shoot.wav", victim, SNDCHAN_STATIC, SNDLEVEL_GUNFIRE);

		// Random 3D direction vector
		float forceMag = g_cvSniperForce.FloatValue;
		float vecForce[3];
		vecForce[0] = GetRandomFloat(-1.0, 1.0);
		vecForce[1] = GetRandomFloat(-1.0, 1.0);
		vecForce[2] = GetRandomFloat(0.3, 1.0); // slight upward bias for dramatic ragdoll launch
		NormalizeVector(vecForce, vecForce);
		ScaleVector(vecForce, forceMag);

		// Announce sniper hit in chat / screen center
		char prefix[32];
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				AJB_GetPrefix(i, prefix, sizeof(prefix));
				CPrintToChat(i, "%T", "LR Sniper Shot", i, prefix, victim);
			}
		}

		// Apply lethal damage with force
		SDKHooks_TakeDamage(victim, 0, 0, 5000.0, DMG_BULLET | DMG_CRIT, -1, vecForce);

		// Post-frame ragdoll force impulse boost for TF2 ragdolls
		DataPack pack = new DataPack();
		pack.WriteCell(GetClientUserId(victim));
		pack.WriteFloat(vecForce[0]);
		pack.WriteFloat(vecForce[1]);
		pack.WriteFloat(vecForce[2]);
		RequestFrame(Frame_ApplyRagdollForce, pack);
	}

	// Schedule next shot if round is still active
	float minTime = g_cvSniperMin.FloatValue;
	float maxTime = g_cvSniperMax.FloatValue;
	if (maxTime < minTime)
	{
		maxTime = minTime;
	}

	float nextInterval = GetRandomFloat(minTime, maxTime);
	g_hSniperTimer = CreateTimer(nextInterval, Timer_SniperShot, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

void Frame_ApplyRagdollForce(DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	float force[3];
	force[0] = pack.ReadFloat();
	force[1] = pack.ReadFloat();
	force[2] = pack.ReadFloat();
	delete pack;

	int client = GetClientOfUserId(userid);
	if (client < 1 || !IsClientInGame(client))
	{
		return;
	}

	int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if (ragdoll > 0 && IsValidEntity(ragdoll))
	{
		TeleportEntity(ragdoll, NULL_VECTOR, NULL_VECTOR, force);
	}
}

void AJB_LR_KillSniperTimer()
{
	if (g_hSniperTimer != null)
	{
		delete g_hSniperTimer;
		g_hSniperTimer = null;
	}
}

// =========================================================================================================
// Cleanup
// =========================================================================================================

void AJB_LR_Cleanup(bool announce)
{
	bool was = (g_iPrisoner > 0 || g_bMenuOpen || g_bAwaitingCustom || g_bHotReds || g_bLowGravity || g_bHideSeek || g_bHungerGames || g_bSniper);
	bool wasChoosing = g_bHasCore && AJB_GetRoundState() == AJBState_LRChoosing;

	AJB_LR_KillMenuTimer();
	AJB_LR_KillSuicideTimer();
	AJB_LR_KillHotTimer();
	AJB_LR_KillHSTimers();
	AJB_LR_KillHGTimers();
	AJB_LR_KillSniperTimer();

	g_iPrisoner = 0;
	g_bMenuOpen = false;
	g_bAwaitingCustom = false;
	g_iFreedayPickCount = 0;
	g_bHGDraftMelee = false;
	g_bHGDraftClassRandom = false;
	g_HGDraftClass = TFClass_Unknown;

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
	}

	if (g_bSniper)
	{
		g_bSniper = false;
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

	if (g_bHungerGames)
	{
		g_bHungerGames = false;
		g_bHGGrace = false;
		g_bHGMeleeOnly = false;
		g_bHGClassLock = false;
		g_HGClass = TFClass_Unknown;
		g_bHGEnding = false;
		AJB_LR_HG_SetFriendlyFire(false);
		if (g_bHasCore)
		{
			AJB_SetRebelOnHit(true);
		}

		int blueTeam = AJB_LR_GetGuardsTeam();
		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_bHGOriginalBlu[i])
			{
				g_bHGOriginalBlu[i] = false;
				if (IsClientInGame(i) && GetClientTeam(i) != blueTeam)
				{
					TF2_ChangeClientTeam(i, view_as<TFTeam>(blueTeam));
				}
			}
		}
	}

	g_bGuardMeleeActive = false;
	g_bSetAllClassActive = false;
	g_SetAllClassTarget = SetAllClass_All;
	g_SetAllClassType = TFClass_Unknown;

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

// =========================================================================================================
// Guard Melee Only
// =========================================================================================================

void AJB_LR_DoGuardMelee(int prisoner)
{
	AJB_LR_QueueWish(prisoner, LRWish_GuardMelee, "LR Chose GuardMelee");
}

void AJB_LR_ApplyGuardMelee(const char[] chooserName)
{
	g_bGuardMeleeActive = true;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}
		if (g_bHasCore && AJB_IsGuard(i))
		{
			AJB_LR_StripGuardToMelee(i);
		}
	}

	AJB_OpenCells();
	AJB_LR_ChatAllQueuedApplied(chooserName, "LR Applied GuardMelee");
}

// =========================================================================================================
// Set All Class
// =========================================================================================================

void AJB_LR_StartSetAllClassConfig(int prisoner)
{
	g_DraftSetAllClassTarget = SetAllClass_All;
	g_DraftSetAllClassType = TFClass_Scout;
	g_bMenuOpen = true;
	AJB_LR_ShowSetAllClassMenu(prisoner);
	AJB_LR_StartMenuTimers(prisoner);
}

void AJB_LR_ShowSetAllClassMenu(int prisoner)
{
	if (prisoner < 1 || !IsClientInGame(prisoner))
	{
		return;
	}

	Menu menu = new Menu(MenuHandler_SetAllClass);
	char title[64];
	char line[96];
	char targetLabel[32];
	char classLabel[32];

	AJB_LR_SetAllClassTargetLabel(prisoner, g_DraftSetAllClassTarget, targetLabel, sizeof(targetLabel));
	AJB_LR_ClassName(g_DraftSetAllClassType, classLabel, sizeof(classLabel));

	Format(title, sizeof(title), "%T", "LR SetAllClass Menu Title", prisoner);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", "LR SetAllClass Opt Target", prisoner, targetLabel);
	menu.AddItem("target", line);

	Format(line, sizeof(line), "%T", "LR SetAllClass Opt Class", prisoner, classLabel);
	menu.AddItem("class", line);

	Format(line, sizeof(line), "%T", "LR SetAllClass Opt Confirm", prisoner);
	menu.AddItem("confirm", line);

	Format(line, sizeof(line), "%T", "LR SetAllClass Opt Back", prisoner);
	menu.AddItem("back", line);

	menu.ExitButton = false;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));
}

void AJB_LR_SetAllClassTargetLabel(int client, AJB_SetAllClassTarget target, char[] buffer, int maxlen)
{
	switch (target)
	{
		case SetAllClass_All:     Format(buffer, maxlen, "%T", "LR SetAllClass Target All", client);
		case SetAllClass_RedOnly: Format(buffer, maxlen, "%T", "LR SetAllClass Target Red", client);
		case SetAllClass_BluOnly: Format(buffer, maxlen, "%T", "LR SetAllClass Target Blu", client);
	}
}

public int MenuHandler_SetAllClass(Menu menu, MenuAction action, int param1, int param2)
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

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "target"))
	{
		AJB_LR_ShowSetAllClassTargetMenu(client);
		return 0;
	}

	if (StrEqual(info, "class"))
	{
		AJB_LR_ShowSetAllClassTypeMenu(client);
		return 0;
	}

	if (StrEqual(info, "back"))
	{
		AJB_LR_ShowWishMenu(client);
		return 0;
	}

	if (StrEqual(info, "confirm"))
	{
		AJB_LR_KillMenuTimer();
		g_bMenuOpen = false;

		AJB_LR_ClearPendingWish();
		g_PendingWish = LRWish_SetAllClass;
		g_PendingSetAllClassTarget = g_DraftSetAllClassTarget;
		g_PendingSetAllClassType = g_DraftSetAllClassType;
		AJB_LR_RememberChooser(client);
		AJB_LR_ChatAllSetAllClassChose(client, g_DraftSetAllClassTarget, g_DraftSetAllClassType);
		AJB_LR_CloseMenuState();
		AJB_LR_MarkWishChosen();
	}

	return 0;
}

void AJB_LR_ShowSetAllClassTargetMenu(int prisoner)
{
	Menu menu = new Menu(MenuHandler_SetAllClassTarget);
	char title[64];
	char line[64];
	Format(title, sizeof(title), "%T", "LR SetAllClass Target Title", prisoner);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", "LR SetAllClass Target All", prisoner);
	menu.AddItem("0", line);
	Format(line, sizeof(line), "%T", "LR SetAllClass Target Red", prisoner);
	menu.AddItem("1", line);
	Format(line, sizeof(line), "%T", "LR SetAllClass Target Blu", prisoner);
	menu.AddItem("2", line);

	menu.ExitButton = false;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));
}

public int MenuHandler_SetAllClassTarget(Menu menu, MenuAction action, int param1, int param2)
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

	char info[16];
	menu.GetItem(param2, info, sizeof(info));
	g_DraftSetAllClassTarget = view_as<AJB_SetAllClassTarget>(StringToInt(info));

	AJB_LR_ShowSetAllClassMenu(client);
	return 0;
}

void AJB_LR_ShowSetAllClassTypeMenu(int prisoner)
{
	Menu menu = new Menu(MenuHandler_SetAllClassType);
	char title[64];
	char line[64];
	Format(title, sizeof(title), "%T", "LR SetAllClass Class Title", prisoner);
	menu.SetTitle(title);

	static const TFClassType kClasses[] = {
		TFClass_Scout, TFClass_Soldier, TFClass_Pyro, TFClass_DemoMan,
		TFClass_Heavy, TFClass_Engineer, TFClass_Medic, TFClass_Sniper, TFClass_Spy
	};

	for (int i = 0; i < sizeof(kClasses); i++)
	{
		char info[8];
		IntToString(view_as<int>(kClasses[i]), info, sizeof(info));
		AJB_LR_ClassName(kClasses[i], line, sizeof(line));
		menu.AddItem(info, line);
	}

	menu.ExitButton = false;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));
}

public int MenuHandler_SetAllClassType(Menu menu, MenuAction action, int param1, int param2)
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

	char info[16];
	menu.GetItem(param2, info, sizeof(info));
	g_DraftSetAllClassType = view_as<TFClassType>(StringToInt(info));

	AJB_LR_ShowSetAllClassMenu(client);
	return 0;
}

void AJB_LR_ApplySetAllClass(const char[] chooserName, AJB_SetAllClassTarget target, TFClassType cls)
{
	g_bSetAllClassActive = true;
	g_SetAllClassTarget = target;
	g_SetAllClassType = cls;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		if (AJB_LR_IsSetAllClassTarget(i, target))
		{
			TF2_SetPlayerClass(i, cls, false, true);
			TF2_RegeneratePlayer(i);
		}
	}

	AJB_LR_ChatAllSetAllClassApplied(chooserName, target, cls);
}

bool AJB_LR_IsSetAllClassTarget(int client, AJB_SetAllClassTarget target)
{
	if (!g_bHasCore)
	{
		return false;
	}

	switch (target)
	{
		case SetAllClass_All:     return AJB_IsPrisoner(client) || AJB_IsGuard(client);
		case SetAllClass_RedOnly: return AJB_IsPrisoner(client);
		case SetAllClass_BluOnly: return AJB_IsGuard(client);
	}
	return false;
}

void AJB_LR_ForceSetAllClass(int client)
{
	if (!g_bSetAllClassActive || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	if (!AJB_LR_IsSetAllClassTarget(client, g_SetAllClassTarget))
	{
		return;
	}

	if (TF2_GetPlayerClass(client) == g_SetAllClassType)
	{
		return;
	}

	TF2_SetPlayerClass(client, g_SetAllClassType, false, true);
	TF2_RegeneratePlayer(client);
}

void AJB_LR_ChatAllSetAllClassChose(int chooser, AJB_SetAllClassTarget target, TFClassType cls)
{
	char className[32];
	AJB_LR_ClassName(cls, className, sizeof(className));

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		char targetLabel[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		AJB_LR_SetAllClassTargetLabel(i, target, targetLabel, sizeof(targetLabel));

		CPrintToChat(i, "%T", "LR Chose SetAllClass", i, prefix, chooser, targetLabel, className);
	}
}

void AJB_LR_ChatAllSetAllClassApplied(const char[] chooserName, AJB_SetAllClassTarget target, TFClassType cls)
{
	char className[32];
	AJB_LR_ClassName(cls, className, sizeof(className));

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		char targetLabel[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		AJB_LR_SetAllClassTargetLabel(i, target, targetLabel, sizeof(targetLabel));

		CPrintToChat(i, "%T", "LR Applied SetAllClass", i, prefix, chooserName[0] != '\0' ? chooserName : "LR", targetLabel, className);
	}
}

void AJB_LR_ChatAll2N(const char[] phrase, int player1, int player2)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", phrase, i, prefix, player1, player2);
	}
}

public Action Command_LR(int client, int args)
{
	if (!g_cvEnabled.BoolValue || !g_bHasCore || !AJB_IsEnabled())
	{
		return Plugin_Handled;
	}

	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return Plugin_Handled;
	}

	if (AJB_GetWarden() != client)
	{
		AJB_Reply(client, "LR Warden Only");
		return Plugin_Handled;
	}

	if (AJB_LR_IsGrantBlocked())
	{
		AJB_Reply(client, "LR Already Active");
		return Plugin_Handled;
	}

	AJB_LR_ShowGrantMenu(client);
	return Plugin_Handled;
}

public Action Command_ForceLR(int client, int args)
{
	if (!g_bHasCore || !AJB_IsEnabled())
	{
		return Plugin_Handled;
	}

	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_ajb_lr_force <#userid|name>");
		return Plugin_Handled;
	}

	char arg1[64];
	GetCmdArg(1, arg1, sizeof(arg1));
	int target = FindTarget(client, arg1, true, false);
	if (target == -1)
	{
		return Plugin_Handled;
	}

	if (!IsPlayerAlive(target) || !AJB_IsPrisoner(target))
	{
		ReplyToCommand(client, "[AJB] Target must be a living prisoner.");
		return Plugin_Handled;
	}

	AJB_LR_OpenForPrisoner(target);
	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	StrCat(prefix, sizeof(prefix), " ");
	CShowActivity2(client, prefix, "%t", "Activity Forced LR", target);
	return Plugin_Handled;
}

public Action Command_ReopenLR(int client, int args)
{
	if (!g_cvEnabled.BoolValue || !g_bHasCore || !AJB_IsEnabled())
	{
		return Plugin_Handled;
	}

	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client) || !AJB_IsPrisoner(client))
	{
		return Plugin_Handled;
	}

	if (client != g_iPrisoner || AJB_GetRoundState() != AJBState_LRChoosing)
	{
		AJB_Reply(client, "LR Reopen Not Eligible");
		return Plugin_Handled;
	}

	AJB_LR_ShowWishMenu(client);
	AJB_Reply(client, "LR Reopen Success");
	return Plugin_Handled;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (event.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim < 1)
	{
		return;
	}

	if (g_bHungerGames)
	{
		AJB_LR_HG_OnPlayerDeath(victim);
	}

	if (victim == g_iPrisoner)
	{
		if (g_bAwaitingCustom)
		{
			g_bAwaitingCustom = false;
		}
		AJB_LR_Cleanup(true);
	}
}
