// =========================================================================================================
// Another Jailbreak - Last Request
// Classic JB wishes (not melee duels): freeday, warday, class warfare, custom, hot reds,
// suicide, low grav, hide and seek, hunger games, zombie mode.
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

#define PLUGIN_VERSION "1.3.0"

#define LR_SUICIDE_DELAY   5.0
#define LR_HOT_DPS         8.0
#define LR_HOT_TICK        0.5
#define LR_GRAVITY_VALUE   200
#define LR_NEAR_RADIUS     200.0
#define LR_NEAR_MAX        3
#define LR_FREEDAY_OTHERS_MAX 3
// Numbered keys: 1-6 players | 7 Confirm | 8 Prev | 9 Next.
// Separators use ITEMDRAW_RAWLINE (no number). Title ends with ----.
#define LR_FREEDAY_PAGE_SIZE  6
// A forced map vote can hijack the panel slot; retry the timeout instead of dropping the offer.
#define LR_REOPEN_RETRY       5.0
#define LR_HG_GRACE_DEFAULT   30.0
#define LR_HG_ROUND_DEFAULT   300.0
#define LR_ZM_INFECT_DEFAULT  20.0
#define LR_ZM_HITS_DEFAULT    2
#define LR_ZM_RESPAWN_DEFAULT 5.0
#define LR_ZM_PROTECT_DEFAULT 5.0
#define LR_ZM_ROUND_DEFAULT   300.0
#define LR_ZM_MATE_Z_OFFSET   8.0

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
	LRWish_GuardMelee,
	LRWish_ZombieMode,
	LRWish_CellWars
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
	description = "Another Jailbreak - classic Last Request wishes.",
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
ConVar g_cvZMInfectDelay;
ConVar g_cvZMHits;
ConVar g_cvZMRespawn;
ConVar g_cvZMSpawnProtect;
ConVar g_cvZMRoundTime;
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

// Zombie Mode: everyone RED (humans); after grace one BLU patient-zero; 2 hits infect.
// Team is the role: RED = human, BLU = zombie (combat day + balance skip keep this stable).
bool g_bZombieMode;
bool g_bZMGrace;           // true until patient zero is chosen
bool g_bZMEnding;
// Pre-mode team (2/3) so cleanup can put everyone back on their real side.
int g_iZMOriginalTeam[MAXPLAYERS + 1];
int g_iZMHits[MAXPLAYERS + 1];
bool g_bZMPendingInfect[MAXPLAYERS + 1]; // RequestFrame in flight - avoid double infect
int g_iZMPendingInfectBy[MAXPLAYERS + 1]; // attacker userid for deferred infect announce
bool g_bZMTeamSwap[MAXPLAYERS + 1];       // ignore death events from intentional team moves
Handle g_hZMRespawnTimer[MAXPLAYERS + 1];

// Cell Wars: everyone on RED locked in cells. FF on from start. Jump to teleport.
bool g_bCellWars;
bool g_bCWMeleeOnly;
bool g_bCWEnding;
bool g_bCWOriginalBlu[MAXPLAYERS + 1];
int g_iCWLastButtons[MAXPLAYERS + 1];
Handle g_hCWEndTimer;
bool g_PendingCWMeleeOnly;
bool g_bCWDraftMelee;
ConVar g_cvCWRoundTime;

// Admin self-pick: open the full wish menu regardless of team/alive state.
bool g_bAdminForcingWish;
int g_iAdminClient;

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
Handle g_hHSHideTimer;   // fires when the hide window ends -> release seekers
Handle g_hHSEndTimer;    // authoritative 5-minute round end (hiders win on timeout)
Handle g_hHGGraceTimer;
Handle g_hHGEndTimer;
Handle g_hZMGraceTimer;  // fires -> pick patient zero
Handle g_hZMEndTimer;    // timeout -> humans win if any RED alive

// Freeday multi-pick (panel; chooser listed first, then other living prisoners)
bool g_bPickedFreeday[MAXPLAYERS + 1];
int g_iFreedayPickCount;
int g_iFreedayMenuPage;
// Panel keys 1..PAGE_SIZE -> userid for that row (0 = empty spacer).
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

// True while this client may drive wish menus (living LR prisoner, or admin self-pick).
bool AJB_LR_IsMenuAllowed(int client)
{
	if (client < 1 || !IsClientInGame(client))
	{
		return false;
	}
	if (g_bAdminForcingWish && client == g_iAdminClient)
	{
		return true;
	}
	return (client == g_iPrisoner && IsPlayerAlive(client));
}

void AJB_LR_CloseMenuState()
{
	g_bMenuOpen = false;
	g_bAwaitingCustom = false;
	g_iPrisoner = 0;
	g_bAdminForcingWish = false;
	g_iAdminClient = 0;
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
	if (prisoner < 1 || !IsClientInGame(prisoner))
	{
		return;
	}
	if (!g_bAdminForcingWish && !IsPlayerAlive(prisoner))
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

	Format(line, sizeof(line), "%T", "LR Wish ZombieMode", prisoner);
	menu.AddItem("zombiemode", line);

	Format(line, sizeof(line), "%T", "LR Wish CellWars", prisoner);
	menu.AddItem("cellwars", line);

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
	if (!IsClientInGame(client) || !AJB_LR_IsMenuAllowed(client))
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
	else if (StrEqual(info, "zombiemode"))
	{
		AJB_LR_DoZombieMode(client);
	}
	else if (StrEqual(info, "cellwars"))
	{
		AJB_LR_StartCellWarsConfig(client);
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
	if (g_bZombieMode && !g_bZMEnding)
	{
		return MRES_Supercede;
	}
	if (g_bCellWars && !g_bCWEnding)
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
	g_cvZMInfectDelay = CreateConVar("sm_ajb_lr_zm_infect_delay", "20", "Zombie Mode: seconds after live round begin before the first random zombie is chosen.", _, true, 5.0, true, 60.0);
	g_cvZMHits = CreateConVar("sm_ajb_lr_zm_hits", "2", "Zombie Mode: damaging hits from zombies required to infect a human.", _, true, 1.0, true, 10.0);
	g_cvZMRespawn = CreateConVar("sm_ajb_lr_zm_respawn", "5", "Zombie Mode: seconds before a dead zombie respawns.", _, true, 1.0, true, 30.0);
	g_cvZMSpawnProtect = CreateConVar("sm_ajb_lr_zm_spawn_protect", "5", "Zombie Mode: invulnerability seconds after a zombie respawns (spawn-camp protection).", _, true, 0.0, true, 30.0);
	g_cvZMRoundTime = CreateConVar("sm_ajb_lr_zm_round_time", "300", "Zombie Mode: total round duration in seconds (humans win on timeout if any remain).", _, true, 60.0, true, 900.0);
	g_cvCWRoundTime = CreateConVar("sm_ajb_lr_cw_round_time", "300", "Cell Wars: total round duration in seconds (survivors win on timeout).", _, true, 60.0, true, 900.0);
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
			LogError("[AJB-LR] Failed to load ajb.games.txt");
		}
		delete conf;
	}
	else
	{
		LogError("[AJB-LR] Failed to load ajb.games.txt");
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

	RegAdminCmd("sm_ajb_lr_force_admin", Command_ForceAdminLR, ADMFLAG_GENERIC, "Open LR menu as admin to force a wish.");

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
	g_iCWLastButtons[client] = 0;
}

public Action AJB_LR_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (g_bZombieMode)
	{
		return AJB_LR_ZM_OnTakeDamage(victim, attacker, damage);
	}

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
	g_bCWOriginalBlu[client] = false;
	g_iZMOriginalTeam[client] = 0;
	g_iZMHits[client] = 0;
	g_bZMPendingInfect[client] = false;
	g_iZMPendingInfectBy[client] = 0;
	g_bZMTeamSwap[client] = false;
	AJB_LR_ZM_KillRespawnTimer(client);

	if (client == g_iPrisoner)
	{
		if (g_bAwaitingCustom)
		{
			g_bAwaitingCustom = false;
		}
		AJB_LR_Cleanup(true);
		return;
	}

	if (g_bZombieMode && !g_bZMEnding)
	{
		RequestFrame(Frame_ZMCheckWinner);
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
	// (after prep / real round start - never during preround).
	AJB_LR_ClearClassWarfareActive();
	AJB_LR_Cleanup(false);
}

// While HG is running, only plugin-driven ends (g_bHGEnding) should be visible as a win.
// Empty-team auto-wins are blocked by mp_ignore_round_win_conditions (set before team moves).
// If an unexpected win still fires, suppress client broadcast but do NOT Plugin_Handled -
// Post hooks (including our cleanup) must still run.
Action Event_RoundWinPre(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bHungerGames && !g_bHGEnding)
	{
		event.BroadcastDisabled = true;
		LogMessage("[AJB-LR] Unexpected teamplay_round_win during Hunger Games (not plugin-ended); suppressed broadcast.");
		return Plugin_Changed;
	}

	if (g_bZombieMode && !g_bZMEnding)
	{
		event.BroadcastDisabled = true;
		LogMessage("[AJB-LR] Unexpected teamplay_round_win during Zombie Mode (not plugin-ended); suppressed broadcast.");
		return Plugin_Changed;
	}

	if (g_bCellWars && !g_bCWEnding)
	{
		event.BroadcastDisabled = true;
		LogMessage("[AJB-LR] Unexpected teamplay_round_win during Cell Wars (not plugin-ended); suppressed broadcast.");
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
	// Keep g_PendingWish - it is for the NEXT live round.
	AJB_LR_ClearClassWarfareActive();
	// Hunger Games may still be active until win cleanup - tear it down without announcing abort.
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

	if (g_bZombieMode)
	{
		AJB_LR_ZM_OnPlayerSpawn(client);
		return;
	}

	if (g_bCellWars)
	{
		AJB_LR_CW_OnPlayerSpawn(client);
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
	g_PendingCWMeleeOnly = false;
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
	bool meleeOnlyCW = g_PendingCWMeleeOnly;
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
		case LRWish_ZombieMode:
		{
			AJB_LR_ApplyZombieMode(chooser);
		}
		case LRWish_CellWars:
		{
			AJB_LR_ApplyCellWars(chooser, meleeOnlyCW);
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


// =========================================================================================================
// Cleanup
// =========================================================================================================

void AJB_LR_Cleanup(bool announce)
{
	bool was = (g_iPrisoner > 0 || g_bMenuOpen || g_bAwaitingCustom || g_bHotReds || g_bLowGravity || g_bHideSeek || g_bHungerGames || g_bZombieMode || g_bSniper || g_bCellWars);
	bool wasChoosing = g_bHasCore && AJB_GetRoundState() == AJBState_LRChoosing;

	AJB_LR_KillMenuTimer();
	AJB_LR_KillSuicideTimer();
	AJB_LR_KillHotTimer();
	AJB_LR_KillHSTimers();
	AJB_LR_KillHGTimers();
	AJB_LR_KillZMTimers();
	AJB_LR_ZM_KillAllRespawnTimers();
	AJB_LR_KillSniperTimer();
	AJB_LR_KillCWTimers();

	g_iPrisoner = 0;
	g_bAdminForcingWish = false;
	g_iAdminClient = 0;
	g_bMenuOpen = false;
	g_bAwaitingCustom = false;
	g_iFreedayPickCount = 0;
	g_bHGDraftMelee = false;
	g_bHGDraftClassRandom = false;
	g_HGDraftClass = TFClass_Unknown;
	g_bCWDraftMelee = false;

	for (int i = 1; i <= MaxClients; i++)
	{
		g_bPickedFreeday[i] = false;
	}

	// Abort while still picking -> leave LR phase (do not clear a queued wish).
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

	if (g_bHasCore)
	{
		AJB_SetRebelOnHit(true);
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

	if (g_bZombieMode)
	{
		g_bZombieMode = false;
		g_bZMGrace = false;
		g_bZMEnding = false;

		for (int i = 1; i <= MaxClients; i++)
		{
			g_iZMHits[i] = 0;
			g_bZMPendingInfect[i] = false;
			g_iZMPendingInfectBy[i] = 0;
			g_bZMTeamSwap[i] = false;

			int want = g_iZMOriginalTeam[i];
			g_iZMOriginalTeam[i] = 0;
			if (want < 2 || !IsClientInGame(i))
			{
				continue;
			}

			// Put every participant back on the team they had before Zombie Mode started.
			if (GetClientTeam(i) != want)
			{
				TF2_ChangeClientTeam(i, view_as<TFTeam>(want));
			}
		}
	}

	if (g_bCellWars)
	{
		g_bCellWars = false;
		g_bCWMeleeOnly = false;
		g_bCWEnding = false;
		AJB_LR_HG_SetFriendlyFire(false);

		int blueTeam = AJB_LR_GetGuardsTeam();
		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_bCWOriginalBlu[i])
			{
				g_bCWOriginalBlu[i] = false;
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
	AJB_AdminBroadcast(client, "Activity Forced LR", target);
	return Plugin_Handled;
}

// Admin opens the same wish menu a prisoner would - no team / alive gate.
public Action Command_ForceAdminLR(int client, int args)
{
	if (!g_cvEnabled.BoolValue || !g_bHasCore || !AJB_IsEnabled())
	{
		return Plugin_Handled;
	}

	if (client < 1 || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}

	if (AJB_LR_IsGrantBlocked())
	{
		AJB_Reply(client, "LR Already Active");
		return Plugin_Handled;
	}

	g_bAdminForcingWish = true;
	g_iAdminClient = client;
	// Reuse chooser slot so queue/announce paths keep a single owner.
	g_iPrisoner = client;
	g_bMenuOpen = true;
	g_bAwaitingCustom = false;

	if (g_bHasCore)
	{
		AJB_SetRoundState(AJBState_LRChoosing);
	}

	AJB_LR_ShowWishMenu(client);
	AJB_LR_StartMenuTimers(client);

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	StrCat(prefix, sizeof(prefix), " ");
	AJB_AdminBroadcast(client, "Activity Admin Pick Wish");
	LogAction(client, -1, "\"%L\" opened admin self-pick Last Request menu", client);
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

	if (g_bZombieMode)
	{
		AJB_LR_ZM_OnPlayerDeath(victim);
	}

	if (g_bCellWars)
	{
		AJB_LR_CW_OnPlayerDeath(victim);
	}

	// Admin self-pick survives death; normal LR chooser does not.
	if (victim == g_iPrisoner && !g_bAdminForcingWish)
	{
		if (g_bAwaitingCustom)
		{
			g_bAwaitingCustom = false;
		}
		AJB_LR_Cleanup(true);
	}
}

// =========================================================================================================
// Wish implementations (included fragments - one compilation unit)
// =========================================================================================================

#include "lastrequest/wish_freeday.sp"
#include "lastrequest/wish_warday.sp"
#include "lastrequest/wish_class_warfare.sp"
#include "lastrequest/wish_set_all_class.sp"
#include "lastrequest/wish_guard_melee.sp"
#include "lastrequest/wish_custom.sp"
#include "lastrequest/wish_hot_reds.sp"
#include "lastrequest/wish_suicide.sp"
#include "lastrequest/wish_low_gravity.sp"
#include "lastrequest/wish_hide_seek.sp"
#include "lastrequest/wish_hunger_games.sp"
#include "lastrequest/wish_zombie_mode.sp"
#include "lastrequest/wish_cell_wars.sp"
#include "lastrequest/wish_sniper.sp"
