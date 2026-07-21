// =========================================================================================================
// Another Jailbreak — Last Request module
// Warden grants LR via their menu; prisoner then picks type + opponent (melee / fair fight).
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

#undef REQUIRE_PLUGIN
#include <ajb/ajb>
#define REQUIRE_PLUGIN

#include <ajb/phrases>

// =========================================================================================================
// Constants
// =========================================================================================================

#define PLUGIN_VERSION      "1.0.0"
#define LR_MENU_TIMEOUT     20.0
#define LR_COUNTDOWN        3.0
#define LR_NEAR_RADIUS      200.0
#define LR_NEAR_MAX         3

enum AJB_LRType
{
	LR_None = 0,
	LR_MeleeDuel,
	LR_FairFight
};

// =========================================================================================================
// Plugin info
// =========================================================================================================

public Plugin myinfo =
{
	name        = "Another Jailbreak - Last Request",
	author      = "SummerTYT",
	description = "Another Jailbreak — Last Request (TF2 melee / fair duel).",
	version     = PLUGIN_VERSION,
	url         = ""
};

// =========================================================================================================
// ConVars / state
// =========================================================================================================

ConVar g_cvEnabled;
ConVar g_cvMenuTime;

bool g_bHasCore;

int g_iPrisoner;
int g_iOpponent;
AJB_LRType g_LRType;
bool g_bLrActive;
bool g_bLrFighting;
bool g_bMenuOpen;

Handle g_hMenuTimer;
Handle g_hCountdownTimer;
int g_iCountdownLeft;

bool g_bDamageHooked[MAXPLAYERS + 1];

// =========================================================================================================
// Lifecycle
// =========================================================================================================

public void OnPluginStart()
{
	CreateConVar("sm_ajb_lr_version", PLUGIN_VERSION, "AJB Last Request module version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_ajb_lr_enabled", "1", "Enable Last Request offers.", _, true, 0.0, true, 1.0);
	g_cvMenuTime = CreateConVar("sm_ajb_lr_menu_time", "20", "Seconds the prisoner has to pick an LR.", _, true, 5.0, true, 60.0);

	AutoExecConfig(true, "ajb_lastrequest");

	LoadTranslations("ajb_lastrequest.phrases");
	LoadTranslations("ajb.phrases");
	LoadTranslations("common.phrases");

	RegConsoleCmd("sm_ajb_lr", Command_LR, "Warden: grant Last Request to a prisoner (same as warden menu).");
	RegAdminCmd("sm_ajb_lr_force", Command_ForceLR, ADMFLAG_GENERIC, "Force LR menu for a living prisoner (or the only one left).");

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("teamplay_round_win", Event_RoundWin, EventHookMode_PostNoCopy);

	g_bHasCore = LibraryExists(AJB_LIBRARY);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			AJB_LR_HookClient(i);
		}
	}

	LogMessage("[AJB-LR] loaded (core %s).", g_bHasCore ? "present" : "missing");
}

public void OnPluginEnd()
{
	AJB_LR_Abort(false);
}

public void OnMapEnd()
{
	AJB_LR_Abort(false);
}

public void OnClientPutInServer(int client)
{
	AJB_LR_HookClient(client);
}

public void OnClientDisconnect(int client)
{
	g_bDamageHooked[client] = false;

	if (!g_bLrActive)
	{
		return;
	}

	if (client == g_iPrisoner || client == g_iOpponent)
	{
		if (g_bLrFighting)
		{
			int winnerTeam = (client == g_iPrisoner) ? AJB_TEAM_BLU : AJB_TEAM_RED;
			AJB_LR_Finish(winnerTeam, true);
		}
		else
		{
			AJB_LR_Abort(true);
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = true;
		LogMessage("[AJB-LR] core attached.");
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = false;
		AJB_LR_Abort(false);
		LogMessage("[AJB-LR] core detached.");
	}
}

// =========================================================================================================
// Core forwards
// =========================================================================================================

public void AJB_OnLastPrisoner(int client)
{
	// Hint only — LR is never auto-granted; warden must give it from their menu.
	if (!g_cvEnabled.BoolValue || !g_bHasCore || !AJB_IsEnabled())
	{
		return;
	}

	if (g_bLrActive || g_bMenuOpen)
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

	if (g_bLrActive || g_bMenuOpen)
	{
		AJB_Reply(warden, "LR Already Active");
		AJB_ShowWardenMenu(warden);
		return;
	}

	AJB_LR_ShowGrantMenu(warden);
}

// =========================================================================================================
// Events
// =========================================================================================================

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	AJB_LR_Abort(false);
}

void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
	AJB_LR_Abort(false);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bLrActive || !g_bLrFighting)
	{
		return;
	}

	// Feign death is not a real kill — do not end the LR fight.
	if (event.GetInt("deathflags") & TF_DEATHFLAG_DEADRINGER)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim != g_iPrisoner && victim != g_iOpponent)
	{
		return;
	}

	int winnerTeam;
	if (victim == g_iPrisoner)
	{
		winnerTeam = AJB_TEAM_BLU;
	}
	else
	{
		winnerTeam = AJB_TEAM_RED;
	}

	AJB_LR_Finish(winnerTeam, true);
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

	if (client == 0 || !IsClientInGame(client))
	{
		AJB_Reply(client, "LR Ingame Only");
		return Plugin_Handled;
	}

	if (!g_cvEnabled.BoolValue)
	{
		AJB_Reply(client, "LR Mode Inactive");
		return Plugin_Handled;
	}

	if (g_bLrActive || g_bMenuOpen)
	{
		AJB_Reply(client, "LR Already Active");
		return Plugin_Handled;
	}

	// Same path as warden menu — only the warden grants LR.
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

	// Optional target: sm_ajb_lr_force <#userid|name>; otherwise first/only living prisoner.
	int target = 0;
	if (args >= 1)
	{
		char arg[64];
		GetCmdArg(1, arg, sizeof(arg));
		target = FindTarget(client, arg, false, false);
		if (target <= 0)
		{
			return Plugin_Handled;
		}
		if (!IsPlayerAlive(target) || !AJB_IsPrisoner(target))
		{
			AJB_Reply(client, "LR No Prisoner");
			return Plugin_Handled;
		}
	}
	else
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i) && AJB_IsPrisoner(i))
			{
				if (target != 0)
				{
					// Multiple prisoners — open grant menu for the admin if they are in-game warden path, else error.
					AJB_Reply(client, "LR Force Need Target");
					return Plugin_Handled;
				}
				target = i;
			}
		}

		if (target == 0)
		{
			AJB_Reply(client, "LR No Prisoner");
			return Plugin_Handled;
		}
	}

	AJB_LR_Abort(false);
	AJB_LR_Offer(target);
	return Plugin_Handled;
}

// =========================================================================================================
// Warden grant menu (sorted by distance)
// =========================================================================================================

void AJB_LR_ShowGrantMenu(int warden)
{
	if (!IsClientInGame(warden) || !IsPlayerAlive(warden))
	{
		return;
	}

	// Collect living prisoners with distance to warden.
	int clients[MAXPLAYERS];
	float dists[MAXPLAYERS];
	int count = 0;

	float wOrigin[3];
	GetClientAbsOrigin(warden, wOrigin);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || !AJB_IsPrisoner(i))
		{
			continue;
		}

		float pOrigin[3];
		GetClientAbsOrigin(i, pOrigin);
		clients[count] = i;
		dists[count] = GetVectorDistance(wOrigin, pOrigin);
		count++;
	}

	if (count == 0)
	{
		AJB_Reply(warden, "LR No Prisoner");
		AJB_ShowWardenMenu(warden);
		return;
	}

	// Sort ascending by distance (simple insertion — MaxClients is small).
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

	// First up to LR_NEAR_MAX within LR_NEAR_RADIUS → "nearby"; everyone else → "others".
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
	char back[64];
	Format(title, sizeof(title), "%T", "LR Grant Title", warden);
	menu.SetTitle(title);

	if (nearCount > 0)
	{
		Format(header, sizeof(header), "%T", "LR Grant Nearby Header", warden);
		menu.AddItem("hdr_near", header, ITEMDRAW_DISABLED);

		for (int n = 0; n < nearCount; n++)
		{
			int idx = nearIdx[n];
			int ply = clients[idx];
			char id[8];
			IntToString(GetClientUserId(ply), id, sizeof(id));
			GetClientName(ply, line, sizeof(line));
			menu.AddItem(id, line);
		}
	}

	// Remaining prisoners (farther than nearby cap, or outside radius).
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

	// Always offer return to the main warden panel.
	Format(back, sizeof(back), "%T", "Warden Menu Back", warden);
	menu.AddItem("back", back);
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
		// Escape / SM back → main warden menu.
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

	if (StrEqual(id, "back") || StrContains(id, "hdr_") == 0)
	{
		if (StrContains(id, "hdr_") == 0)
		{
			AJB_LR_ShowGrantMenu(warden);
		}
		else
		{
			AJB_ShowWardenMenu(warden);
		}
		return 0;
	}

	if (g_bLrActive || g_bMenuOpen)
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

	// Grant LR to the prisoner, then put the warden back on their main menu.
	AJB_LR_Offer(prisoner);
	AJB_ShowWardenMenu(warden);
	return 0;
}

// =========================================================================================================
// Offer / menus
// =========================================================================================================

void AJB_LR_Offer(int prisoner)
{
	if (!IsClientInGame(prisoner) || !IsPlayerAlive(prisoner))
	{
		return;
	}

	g_iPrisoner = prisoner;
	g_iOpponent = 0;
	g_LRType = LR_None;
	g_bLrActive = false;
	g_bLrFighting = false;
	g_bMenuOpen = true;

	AJB_LR_ChatAll1N("LR Offered", prisoner);

	Menu menu = new Menu(MenuHandler_LRType);
	char title[64];
	char melee[64];
	char fair[64];
	char skip[64];
	Format(title, sizeof(title), "%T", "LR Menu Title", prisoner);
	Format(melee, sizeof(melee), "%T", "LR Type Melee", prisoner);
	Format(fair, sizeof(fair), "%T", "LR Type Fair", prisoner);
	Format(skip, sizeof(skip), "%T", "LR Type Skip", prisoner);
	menu.SetTitle(title);
	menu.AddItem("melee", melee);
	menu.AddItem("fair", fair);
	menu.AddItem("skip", skip);
	menu.ExitButton = false;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));

	AJB_LR_KillMenuTimer();
	g_hMenuTimer = CreateTimer(g_cvMenuTime.FloatValue + 0.5, Timer_MenuTimeout, GetClientUserId(prisoner), TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_MenuTimeout(Handle timer, int userid)
{
	g_hMenuTimer = null;

	int client = GetClientOfUserId(userid);
	if (!g_bMenuOpen)
	{
		return Plugin_Stop;
	}

	g_bMenuOpen = false;
	if (client > 0)
	{
		AJB_LR_ChatAll1N("LR Timeout", client);
	}
	return Plugin_Stop;
}

void AJB_LR_KillMenuTimer()
{
	if (g_hMenuTimer != null)
	{
		delete g_hMenuTimer;
		g_hMenuTimer = null;
	}
}

public int MenuHandler_LRType(Menu menu, MenuAction action, int param1, int param2)
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
	if (client != g_iPrisoner || !IsClientInGame(client))
	{
		return 0;
	}

	AJB_LR_KillMenuTimer();
	g_bMenuOpen = false;

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "skip"))
	{
		AJB_LR_ChatAll1N("LR Skipped", client);
		g_iPrisoner = 0;
		return 0;
	}

	if (StrEqual(info, "melee"))
	{
		g_LRType = LR_MeleeDuel;
	}
	else
	{
		g_LRType = LR_FairFight;
	}

	AJB_LR_ShowOpponentMenu(client);
	return 0;
}

void AJB_LR_ShowOpponentMenu(int prisoner)
{
	Menu menu = new Menu(MenuHandler_Opponent);
	menu.SetTitle("%T", "LR Pick Guard", prisoner);

	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || !AJB_IsGuard(i))
		{
			continue;
		}

		char id[8];
		char name[64];
		IntToString(i, id, sizeof(id));
		GetClientName(i, name, sizeof(name));

		if (AJB_GetWarden() == i)
		{
			Format(name, sizeof(name), "[W] %s", name);
		}

		menu.AddItem(id, name);
		count++;
	}

	if (count == 0)
	{
		delete menu;
		AJB_ChatAll("LR No Guards");
		g_iPrisoner = 0;
		g_LRType = LR_None;
		return;
	}

	menu.ExitButton = false;
	g_bMenuOpen = true;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));
}

public int MenuHandler_Opponent(Menu menu, MenuAction action, int param1, int param2)
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

	g_bMenuOpen = false;

	char id[8];
	menu.GetItem(param2, id, sizeof(id));
	int opponent = StringToInt(id);

	if (opponent < 1 || !IsClientInGame(opponent) || !IsPlayerAlive(opponent) || !AJB_IsGuard(opponent))
	{
		AJB_Chat(client, "LR Guard Invalid");
		AJB_LR_ShowOpponentMenu(client);
		return 0;
	}

	AJB_LR_Begin(client, opponent, g_LRType);
	return 0;
}

// =========================================================================================================
// Fight lifecycle
// =========================================================================================================

void AJB_LR_Begin(int prisoner, int opponent, AJB_LRType type)
{
	g_iPrisoner = prisoner;
	g_iOpponent = opponent;
	g_LRType = type;
	g_bLrActive = true;
	g_bLrFighting = false;

	AJB_SetRoundState(AJBState_LastRequest);

	char typeName[32];
	AJB_LR_TypeName(type, typeName, sizeof(typeName));
	AJB_LR_ChatAllStarted(prisoner, opponent, typeName);

	// Prep both fighters.
	AJB_LR_PrepFighter(prisoner, type);
	AJB_LR_PrepFighter(opponent, type);

	AJB_LR_KillCountdown();
	g_iCountdownLeft = 3;
	PrintCenterTextAll("%t", "LR Countdown", g_iCountdownLeft);
	g_hCountdownTimer = CreateTimer(1.0, Timer_Countdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_Countdown(Handle timer)
{
	g_iCountdownLeft--;

	if (g_iCountdownLeft <= 0)
	{
		g_hCountdownTimer = null;
		g_bLrFighting = true;
		PrintCenterTextAll("%t", "LR Fight");
		AJB_ChatAll("LR Fight Chat");
		return Plugin_Stop;
	}

	PrintCenterTextAll("%t", "LR Countdown", g_iCountdownLeft);
	return Plugin_Continue;
}

void AJB_LR_KillCountdown()
{
	if (g_hCountdownTimer != null)
	{
		delete g_hCountdownTimer;
		g_hCountdownTimer = null;
	}
}

void AJB_LR_PrepFighter(int client, AJB_LRType type)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	TF2_RegeneratePlayer(client);

	if (type == LR_MeleeDuel)
	{
		TF2_RemoveWeaponSlot(client, TFWeaponSlot_Primary);
		TF2_RemoveWeaponSlot(client, TFWeaponSlot_Secondary);
		TF2_RemoveWeaponSlot(client, TFWeaponSlot_Grenade);
		TF2_RemoveWeaponSlot(client, TFWeaponSlot_Building);
		TF2_RemoveWeaponSlot(client, TFWeaponSlot_PDA);

		int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
		if (melee != -1)
		{
			SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", melee);
		}
	}
}

void AJB_LR_Finish(int winnerTeam, bool announce)
{
	if (!g_bLrActive && !g_bLrFighting)
	{
		// Still clear partial state.
	}

	int prisoner = g_iPrisoner;
	int opponent = g_iOpponent;

	g_bLrActive = false;
	g_bLrFighting = false;
	g_bMenuOpen = false;
	g_iPrisoner = 0;
	g_iOpponent = 0;
	g_LRType = LR_None;

	AJB_LR_KillMenuTimer();
	AJB_LR_KillCountdown();

	if (announce && g_bHasCore && AJB_IsEnabled())
	{
		if (winnerTeam == AJB_TEAM_RED)
		{
			AJB_LR_ChatAll1N("LR Prisoner Wins", prisoner);
		}
		else
		{
			AJB_LR_ChatAll1N("LR Guard Wins", opponent);
		}

		AJB_ForceTeamWin(winnerTeam);
	}
}

void AJB_LR_Abort(bool announce)
{
	AJB_LR_KillMenuTimer();
	AJB_LR_KillCountdown();

	bool was = g_bLrActive || g_bMenuOpen;
	g_bLrActive = false;
	g_bLrFighting = false;
	g_bMenuOpen = false;
	g_iPrisoner = 0;
	g_iOpponent = 0;
	g_LRType = LR_None;

	if (announce && was)
	{
		AJB_ChatAll("LR Aborted");
	}
}

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

void AJB_LR_ChatAllStarted(int prisoner, int opponent, const char[] typeName)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", "LR Started", i, prefix, prisoner, opponent, typeName);
	}
}

void AJB_LR_TypeName(AJB_LRType type, char[] buffer, int maxlen)
{
	switch (type)
	{
		case LR_MeleeDuel: strcopy(buffer, maxlen, "Melee Duel");
		case LR_FairFight: strcopy(buffer, maxlen, "Fair Fight");
		default:           strcopy(buffer, maxlen, "LR");
	}
}

// =========================================================================================================
// Damage filter — only the two duelists may hurt each other during LR fight
// =========================================================================================================

void AJB_LR_HookClient(int client)
{
	if (g_bDamageHooked[client] || !IsClientInGame(client))
	{
		return;
	}

	SDKHook(client, SDKHook_OnTakeDamage, AJB_LR_OnTakeDamage);
	g_bDamageHooked[client] = true;
}

Action AJB_LR_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (!g_bLrActive || !g_bHasCore)
	{
		return Plugin_Continue;
	}

	if (!g_bLrFighting)
	{
		if (AJB_LR_IsDuelist(victim) || AJB_LR_IsDuelist(attacker))
		{
			damage = 0.0;
			return Plugin_Changed;
		}
		return Plugin_Continue;
	}

	bool victimDuel = AJB_LR_IsDuelist(victim);
	bool attackerDuel = AJB_LR_IsDuelist(attacker);

	if (!victimDuel && !attackerDuel)
	{
		return Plugin_Continue;
	}

	if (victimDuel && attackerDuel && victim != attacker)
	{
		return Plugin_Continue;
	}

	if (victimDuel || attackerDuel)
	{
		damage = 0.0;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

bool AJB_LR_IsDuelist(int client)
{
	return client > 0 && (client == g_iPrisoner || client == g_iOpponent);
}
