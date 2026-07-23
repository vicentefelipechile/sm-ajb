// =========================================================================================================
// Another Jailbreak — Boosts
// Round points + temporary gameplay boosts (NOT a general store/shop; no cosmetics/gadgets).
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

// Own library name for natives (see include/ajb/boosts.inc).
#define AJB_BOOSTS_LIBRARY "ajb_boosts"

#include <ajb/phrases>

// =========================================================================================================
// Constants
// =========================================================================================================

#define PLUGIN_VERSION "1.0.0"

#define BOOST_ID_IRON_NECK     "iron_neck"
#define BOOST_ID_IRON_NECK_II  "iron_neck_2"
#define BOOST_ID_REVIVE        "revive"

// RED (prisoner) boosts
#define BOOST_ID_SECOND_WIND   "second_wind"
#define BOOST_ID_MAD_MILK      "mad_milk"
#define BOOST_ID_MELEE_CRIT    "melee_crit"
#define BOOST_ID_JARATE        "jarate"
#define BOOST_ID_REGEN         "regen"

#define BOOST_COST_IRON_NECK     1
#define BOOST_COST_IRON_NECK_II  3
#define BOOST_COST_REVIVE        3

#define BOOST_COST_SECOND_WIND   1
#define BOOST_COST_MAD_MILK      1
#define BOOST_COST_MELEE_CRIT    2
#define BOOST_COST_JARATE        3
#define BOOST_COST_REGEN         3

#define BOOST_CHARGES_IRON_NECK     1
#define BOOST_CHARGES_IRON_NECK_II  2

#define BOOST_SECOND_WIND_HP     50
#define BOOST_REGEN_INSTANT_HP   50
#define BOOST_REGEN_DURATION     20.0
#define BOOST_REGEN_PER_TICK     5
#define BOOST_REGEN_TICK         1.0
#define BOOST_JAR_THROW_SPEED    1200.0

// Per-player boolean state packed into one bitfield cell (see BoostPlayer.flags).
#define BF_MELEE_CRIT    (1 << 0)   // RED: next melee hit is a full crit
#define BF_DAMAGE_HOOKED (1 << 1)   // OnTakeDamage hooked for this client

// =========================================================================================================
// Plugin info
// =========================================================================================================

public Plugin myinfo =
{
	name        = "Another Jailbreak - Boosts",
	author      = "SummerTYT",
	description = "Another Jailbreak — round points and temporary gameplay boosts (not a store).",
	version     = PLUGIN_VERSION,
	url         = ""
};

// =========================================================================================================
// ConVars / state
// =========================================================================================================

ConVar g_cvEnabled;
ConVar g_cvMaxPoints;
ConVar g_cvBluEvery;

bool g_bHasCore;

// Cached mirror of g_cvEnabled: OnTakeDamage is hooked on every client and fires for all
// server-wide damage, so its early-out reads a bool instead of the ConVar accessor per hit.
bool g_bBoostsEnabled;

// All per-player boost data in one contiguous struct (cache locality; bools packed into flags).
enum struct BoostPlayer
{
	int points;
	int spentThisRound;
	int backstabCharges;   // BLU iron-neck backstab saves left
	float regenEnd;        // RED passive regen deadline (GetGameTime)
	Handle regenTimer;
	int flags;             // BF_* bitfield
}

BoostPlayer g_Boost[MAXPLAYERS + 1];

// Counts finished jail rounds for BLU passive points (every N rounds).
int g_iFinishedRoundCount;

// Flag accessors — the compiler inlines these to the same and/or/andnot it would emit inline.
bool Boost_HasFlag(int client, int flag)
{
	return (g_Boost[client].flags & flag) != 0;
}

void Boost_SetFlag(int client, int flag, bool on)
{
	if (on)
	{
		g_Boost[client].flags |= flag;
	}
	else
	{
		g_Boost[client].flags &= ~flag;
	}
}

// =========================================================================================================
// Lifecycle
// =========================================================================================================

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("AJB_Boosts_GetPoints", Native_Boosts_GetPoints);
	CreateNative("AJB_Boosts_AddPointsEx", Native_Boosts_AddPointsEx);
	RegPluginLibrary(AJB_BOOSTS_LIBRARY);
	return APLRes_Success;
}

public int Native_Boosts_GetPoints(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients)
	{
		return 0;
	}
	return g_Boost[client].points;
}

public int Native_Boosts_AddPointsEx(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int amount = GetNativeCell(2);
	AJB_Boosts_AddPoints(client, amount, "admin");
	if (client < 1 || client > MaxClients)
	{
		return 0;
	}
	return g_Boost[client].points;
}

public void OnPluginStart()
{
	CreateConVar("sm_ajb_boosts_version", PLUGIN_VERSION, "AJB Boosts module version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_ajb_boosts_enabled", "1", "Enable the boosts system.", _, true, 0.0, true, 1.0);
	g_bBoostsEnabled = g_cvEnabled.BoolValue;
	g_cvEnabled.AddChangeHook(OnBoostsEnabledChanged);
	g_cvMaxPoints = CreateConVar("sm_ajb_boosts_max_points", "3", "Max points a player can EARN-hold (0 = unlimited). Admin grants ignore this.", _, true, 0.0);
	g_cvBluEvery = CreateConVar("sm_ajb_boosts_blu_every", "2", "BLU surviving players get +1 extra every N finished rounds.", _, true, 1.0);

	AutoExecConfig(true, "ajb_boosts");

	LoadTranslations("ajb_boosts.phrases");
	LoadTranslations("ajb.phrases");
	LoadTranslations("common.phrases");

	// Short aliases (exceptions to sm_ajb_*): /boost, /boosts
	RegConsoleCmd("sm_boost", Command_Boosts, "Open the boosts menu.");
	RegConsoleCmd("sm_boosts", Command_Boosts, "Open the boosts menu.");
	RegConsoleCmd("sm_ajb_boosts", Command_Boosts, "Open the boosts menu.");
	RegConsoleCmd("sm_ajb_points", Command_Points, "Show your boost points.");
	RegAdminCmd("sm_ajb_boosts_give", Command_GivePoints, ADMFLAG_GENERIC, "Usage: sm_ajb_boosts_give <#userid|name> <amount>");

	HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("teamplay_round_win", Event_RoundWin, EventHookMode_Post);

	g_bHasCore = LibraryExists(AJB_LIBRARY);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			AJB_Boosts_HookClient(i);
		}
	}

	LogMessage("[AJB-Boosts] loaded (core %s).", g_bHasCore ? "present" : "missing");
}

public void OnPluginEnd()
{
}

public void OnMapStart()
{
	g_iFinishedRoundCount = 0;
}

public void OnClientPutInServer(int client)
{
	AJB_Boosts_ResetClient(client);
	AJB_Boosts_HookClient(client);
}

public void OnClientDisconnect(int client)
{
	AJB_Boosts_ResetClient(client);
	Boost_SetFlag(client, BF_DAMAGE_HOOKED, false);
}

// Full per-player wipe (points included) — connect/disconnect boundary.
void AJB_Boosts_ResetClient(int client)
{
	AJB_Boosts_StopRegen(client);
	g_Boost[client].points = 0;
	g_Boost[client].spentThisRound = 0;
	g_Boost[client].backstabCharges = 0;
	Boost_SetFlag(client, BF_MELEE_CRIT, false);
}

public void OnBoostsEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_bBoostsEnabled = convar.BoolValue;
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
	}
}

// =========================================================================================================
// Events
// =========================================================================================================

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	int maxPts = g_cvMaxPoints.IntValue;

	for (int i = 1; i <= MaxClients; i++)
	{
		g_Boost[i].spentThisRound = 0;
		g_Boost[i].backstabCharges = 0;
		Boost_SetFlag(i, BF_MELEE_CRIT, false);
		AJB_Boosts_StopRegen(i);

		// Cap holdings to max (e.g. after cvar change or leftover from older builds).
		if (maxPts > 0 && g_Boost[i].points > maxPts)
		{
			g_Boost[i].points = maxPts;
		}
	}
}

void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnabled.BoolValue || !g_bHasCore || !AJB_IsEnabled())
	{
		return;
	}

	g_iFinishedRoundCount++;

	bool bluPassiveRound = (g_iFinishedRoundCount % g_cvBluEvery.IntValue) == 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		AJB_Boosts_AddPoints(i, 1, "survive");

		if (bluPassiveRound && AJB_IsGuard(i))
		{
			AJB_Boosts_AddPoints(i, 1, "blu_passive");
		}
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		g_Boost[i].backstabCharges = 0;
		Boost_SetFlag(i, BF_MELEE_CRIT, false);
		AJB_Boosts_StopRegen(i);
	}
}

// =========================================================================================================
// Commands
// =========================================================================================================

Action Command_Points(int client, int args)
{
	if (client == 0)
	{
		AJB_Reply(client, "Boosts Ingame Only");
		return Plugin_Handled;
	}

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	ReplyToCommand(client, "%T", "Boosts Points", client, prefix, g_Boost[client].points);
	return Plugin_Handled;
}

Action Command_Boosts(int client, int args)
{
	if (!g_cvEnabled.BoolValue)
	{
		AJB_Reply(client, "Boosts Disabled");
		return Plugin_Handled;
	}

	if (!g_bHasCore || !AJB_IsEnabled())
	{
		AJB_Reply(client, "Boosts Mode Inactive");
		return Plugin_Handled;
	}

	if (client == 0 || !IsClientInGame(client))
	{
		AJB_Reply(client, "Boosts Ingame Only");
		return Plugin_Handled;
	}

	AJB_Boosts_ShowMenu(client);
	return Plugin_Handled;
}

Action Command_GivePoints(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "Usage: sm_ajb_boosts_give <#userid|name> <amount>");
		return Plugin_Handled;
	}

	char targetArg[64];
	GetCmdArg(1, targetArg, sizeof(targetArg));
	char amountArg[16];
	GetCmdArg(2, amountArg, sizeof(amountArg));
	int amount = StringToInt(amountArg);

	char targetName[MAX_TARGET_LENGTH];
	int targetList[MAXPLAYERS];
	bool tnIsMl;
	int count = ProcessTargetString(targetArg, client, targetList, MAXPLAYERS, COMMAND_FILTER_CONNECTED, targetName, sizeof(targetName), tnIsMl);
	if (count <= 0)
	{
		ReplyToTargetError(client, count);
		return Plugin_Handled;
	}

	for (int i = 0; i < count; i++)
	{
		AJB_Boosts_AddPoints(targetList[i], amount, "admin");
	}

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	ReplyToCommand(client, "%T", "Boosts Admin Gave", AJB_TransTarget(client), prefix, amount, targetName);
	return Plugin_Handled;
}

// =========================================================================================================
// Points
// =========================================================================================================

void AJB_Boosts_AddPoints(int client, int amount, const char[] reason)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || amount == 0)
	{
		return;
	}

	// Admin grants are intentional and bypass the earn-holdings cap; earned points respect it.
	bool isAdmin = StrEqual(reason, "admin");
	int maxPts = g_cvMaxPoints.IntValue;
	int next = g_Boost[client].points + amount;
	if (!isAdmin && maxPts > 0 && next > maxPts)
	{
		next = maxPts;
	}
	if (next < 0)
	{
		next = 0;
	}

	int gained = next - g_Boost[client].points;
	g_Boost[client].points = next;

	if (gained > 0 && !StrEqual(reason, "admin"))
	{
		char prefix[32];
		AJB_GetPrefix(client, prefix, sizeof(prefix));
		CPrintToChat(client, "%T", "Boosts Points Gained", client, prefix, gained, g_Boost[client].points);
	}
}

bool AJB_Boosts_TrySpend(int client, int cost)
{
	if (cost < 1)
	{
		return false;
	}

	if (g_Boost[client].points < cost)
	{
		char prefix[32];
		AJB_GetPrefix(client, prefix, sizeof(prefix));
		CPrintToChat(client, "%T", "Boosts Not Enough", client, prefix, cost, g_Boost[client].points);
		return false;
	}

	g_Boost[client].points -= cost;
	g_Boost[client].spentThisRound += cost;
	return true;
}

// =========================================================================================================
// Menu
// =========================================================================================================

void AJB_Boosts_ShowMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Boosts);

	// Title layout:
	//   Boosts
	//   ------
	//   Points: N
	//   Spent: N
	//   ------
	char title[192];
	Format(title, sizeof(title), "%T", "Boosts Menu Title", client, g_Boost[client].points, g_Boost[client].spentThisRound);
	menu.SetTitle(title);

	// Dead players may open the panel to plan, but purchases stay locked.
	int draw = IsPlayerAlive(client) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED;

	char line[128];
	if (AJB_IsGuard(client))
	{
		// Cost is code-owned; translations only hold the description.
		Format(line, sizeof(line), "%T", "Boost Iron Neck", client, BOOST_COST_IRON_NECK);
		menu.AddItem(BOOST_ID_IRON_NECK, line, draw);

		Format(line, sizeof(line), "%T", "Boost Iron Neck II", client, BOOST_COST_IRON_NECK_II);
		menu.AddItem(BOOST_ID_IRON_NECK_II, line, draw);

		if (AJB_GetWarden() == client)
		{
			Format(line, sizeof(line), "%T", "Boost Revive", client, BOOST_COST_REVIVE);
			menu.AddItem(BOOST_ID_REVIVE, line, draw);
		}
	}
	else if (AJB_IsPrisoner(client))
	{
		Format(line, sizeof(line), "%T", "Boost Second Wind", client, BOOST_COST_SECOND_WIND);
		menu.AddItem(BOOST_ID_SECOND_WIND, line, draw);

		Format(line, sizeof(line), "%T", "Boost Mad Milk", client, BOOST_COST_MAD_MILK);
		menu.AddItem(BOOST_ID_MAD_MILK, line, draw);

		Format(line, sizeof(line), "%T", "Boost Melee Crit", client, BOOST_COST_MELEE_CRIT);
		menu.AddItem(BOOST_ID_MELEE_CRIT, line, draw);

		Format(line, sizeof(line), "%T", "Boost Jarate", client, BOOST_COST_JARATE);
		menu.AddItem(BOOST_ID_JARATE, line, draw);

		Format(line, sizeof(line), "%T", "Boost Regen", client, BOOST_COST_REGEN);
		menu.AddItem(BOOST_ID_REGEN, line, draw);
	}
	else
	{
		Format(line, sizeof(line), "%T", "Boosts Join Team", client);
		menu.AddItem("none", line, ITEMDRAW_DISABLED);
	}

	// 0. Exit / Salir (SourceMod core phrase by client language)
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Boosts(Menu menu, MenuAction action, int param1, int param2)
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
	if (!g_cvEnabled.BoolValue || !g_bHasCore || !AJB_IsEnabled())
	{
		return 0;
	}

	// Items are disabled while dead; still guard purchases server-side.
	if (!IsPlayerAlive(client))
	{
		AJB_Boosts_ShowMenu(client);
		return 0;
	}

	char id[32];
	menu.GetItem(param2, id, sizeof(id));

	if (StrEqual(id, BOOST_ID_IRON_NECK))
	{
		AJB_Boosts_BuyIronNeck(client, BOOST_CHARGES_IRON_NECK, BOOST_COST_IRON_NECK);
	}
	else if (StrEqual(id, BOOST_ID_IRON_NECK_II))
	{
		AJB_Boosts_BuyIronNeck(client, BOOST_CHARGES_IRON_NECK_II, BOOST_COST_IRON_NECK_II);
	}
	else if (StrEqual(id, BOOST_ID_REVIVE))
	{
		AJB_Boosts_BuyRevive(client);
	}
	else if (StrEqual(id, BOOST_ID_SECOND_WIND))
	{
		AJB_Boosts_BuySecondWind(client);
	}
	else if (StrEqual(id, BOOST_ID_MAD_MILK))
	{
		AJB_Boosts_BuyJarThrow(client, true);
	}
	else if (StrEqual(id, BOOST_ID_MELEE_CRIT))
	{
		AJB_Boosts_BuyMeleeCrit(client);
	}
	else if (StrEqual(id, BOOST_ID_JARATE))
	{
		AJB_Boosts_BuyJarThrow(client, false);
	}
	else if (StrEqual(id, BOOST_ID_REGEN))
	{
		AJB_Boosts_BuyRegen(client);
	}

	return 0;
}

// =========================================================================================================
// Purchases
// =========================================================================================================

void AJB_Boosts_BuyIronNeck(int client, int charges, int cost)
{
	if (!AJB_IsGuard(client) || !IsPlayerAlive(client))
	{
		AJB_Chat(client, "Boosts Guards Alive Only");
		return;
	}

	if (!AJB_Boosts_TrySpend(client, cost))
	{
		AJB_Boosts_ShowMenu(client);
		return;
	}

	if (charges > g_Boost[client].backstabCharges)
	{
		g_Boost[client].backstabCharges = charges;
	}
	else
	{
		g_Boost[client].backstabCharges += charges;
	}

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	CPrintToChat(client, "%T", "Boosts Purchased Iron Neck", client, prefix, g_Boost[client].backstabCharges, g_Boost[client].points);
	AJB_Boosts_ShowMenu(client);
}

void AJB_Boosts_BuyRevive(int client)
{
	if (AJB_GetWarden() != client || !IsPlayerAlive(client))
	{
		AJB_Chat(client, "Boosts Warden Only");
		return;
	}

	if (AJB_IsLRPhase(AJB_GetRoundState()))
	{
		AJB_Chat(client, "Boosts No LR");
		return;
	}

	AJB_Boosts_ShowReviveTargets(client);
}

void AJB_Boosts_ShowReviveTargets(int client)
{
	Menu menu = new Menu(MenuHandler_Revive);
	menu.SetTitle("%T", "Boosts Revive Pick", client);

	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || IsPlayerAlive(i))
		{
			continue;
		}

		int team = GetClientTeam(i);
		if (team != AJB_TEAM_RED && team != AJB_TEAM_BLU)
		{
			continue;
		}

		if (g_bHasCore && !AJB_IsPrisoner(i) && !AJB_IsGuard(i))
		{
			continue;
		}

		char info[8];
		char name[64];
		IntToString(GetClientUserId(i), info, sizeof(info));
		GetClientName(i, name, sizeof(name));

		if (team == AJB_TEAM_RED)
		{
			Format(name, sizeof(name), "[RED] %s", name);
		}
		else
		{
			Format(name, sizeof(name), "[BLU] %s", name);
		}

		menu.AddItem(info, name);
		count++;
	}

	if (count == 0)
	{
		delete menu;
		AJB_Chat(client, "Boosts Revive None");
		return;
	}

	menu.ExitBackButton = true;
	menu.Display(client, 30);
}

public int MenuHandler_Revive(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}

	if (action == MenuAction_Cancel)
	{
		if (param2 == MenuCancel_ExitBack)
		{
			AJB_Boosts_ShowMenu(param1);
		}
		return 0;
	}

	if (action != MenuAction_Select)
	{
		return 0;
	}

	int client = param1;
	if (AJB_GetWarden() != client)
	{
		return 0;
	}

	if (AJB_IsLRPhase(AJB_GetRoundState()))
	{
		AJB_Chat(client, "Boosts No LR");
		return 0;
	}

	char info[8];
	menu.GetItem(param2, info, sizeof(info));
	int target = GetClientOfUserId(StringToInt(info));

	if (target <= 0 || !IsClientInGame(target) || IsPlayerAlive(target))
	{
		AJB_Chat(client, "Boosts Revive Invalid");
		return 0;
	}

	int team = GetClientTeam(target);
	if (team != AJB_TEAM_RED && team != AJB_TEAM_BLU)
	{
		AJB_Chat(client, "Boosts Revive Invalid");
		return 0;
	}

	if (!AJB_Boosts_TrySpend(client, BOOST_COST_REVIVE))
	{
		return 0;
	}

	TF2_RespawnPlayer(target);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", "Boosts Revived", i, prefix, client, target);
	}

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	CPrintToChat(client, "%T", "Boosts Points Left", client, prefix, g_Boost[client].points);
	return 0;
}

// =========================================================================================================
// RED purchases
// =========================================================================================================

bool AJB_Boosts_RequireLivingPrisoner(int client)
{
	if (!g_bHasCore || !AJB_IsPrisoner(client) || !IsPlayerAlive(client))
	{
		AJB_Chat(client, "Boosts Prisoners Alive Only");
		return false;
	}
	return true;
}

void AJB_Boosts_BuySecondWind(int client)
{
	if (!AJB_Boosts_RequireLivingPrisoner(client))
	{
		return;
	}

	if (!AJB_Boosts_TrySpend(client, BOOST_COST_SECOND_WIND))
	{
		AJB_Boosts_ShowMenu(client);
		return;
	}

	AJB_Boosts_AddHealth(client, BOOST_SECOND_WIND_HP, true);

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	CPrintToChat(client, "%T", "Boosts Purchased Second Wind", client, prefix, BOOST_SECOND_WIND_HP, g_Boost[client].points);
	AJB_Boosts_ShowMenu(client);
}

// milk = true → Mad Milk; false → Jarate. Throws along eye forward.
void AJB_Boosts_BuyJarThrow(int client, bool milk)
{
	if (!AJB_Boosts_RequireLivingPrisoner(client))
	{
		return;
	}

	int cost = milk ? BOOST_COST_MAD_MILK : BOOST_COST_JARATE;
	if (!AJB_Boosts_TrySpend(client, cost))
	{
		AJB_Boosts_ShowMenu(client);
		return;
	}

	if (!AJB_Boosts_ThrowJar(client, milk))
	{
		// Refund if the projectile failed to spawn.
		g_Boost[client].points += cost;
		g_Boost[client].spentThisRound -= cost;
		if (g_Boost[client].spentThisRound < 0)
		{
			g_Boost[client].spentThisRound = 0;
		}
		AJB_Chat(client, "Boosts Throw Failed");
		AJB_Boosts_ShowMenu(client);
		return;
	}

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	CPrintToChat(client, "%T", milk ? "Boosts Purchased Mad Milk" : "Boosts Purchased Jarate", client, prefix, g_Boost[client].points);
	AJB_Boosts_ShowMenu(client);
}

void AJB_Boosts_BuyMeleeCrit(int client)
{
	if (!AJB_Boosts_RequireLivingPrisoner(client))
	{
		return;
	}

	if (Boost_HasFlag(client, BF_MELEE_CRIT))
	{
		AJB_Chat(client, "Boosts Melee Crit Already");
		AJB_Boosts_ShowMenu(client);
		return;
	}

	if (!AJB_Boosts_TrySpend(client, BOOST_COST_MELEE_CRIT))
	{
		AJB_Boosts_ShowMenu(client);
		return;
	}

	Boost_SetFlag(client, BF_MELEE_CRIT, true);

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	CPrintToChat(client, "%T", "Boosts Purchased Melee Crit", client, prefix, g_Boost[client].points);
	AJB_Boosts_ShowMenu(client);
}

void AJB_Boosts_BuyRegen(int client)
{
	if (!AJB_Boosts_RequireLivingPrisoner(client))
	{
		return;
	}

	if (!AJB_Boosts_TrySpend(client, BOOST_COST_REGEN))
	{
		AJB_Boosts_ShowMenu(client);
		return;
	}

	AJB_Boosts_AddHealth(client, BOOST_REGEN_INSTANT_HP, true);
	AJB_Boosts_StartRegen(client, BOOST_REGEN_DURATION);

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	CPrintToChat(client, "%T", "Boosts Purchased Regen", client, prefix, BOOST_REGEN_INSTANT_HP, RoundToNearest(BOOST_REGEN_DURATION), g_Boost[client].points);
	AJB_Boosts_ShowMenu(client);
}

void AJB_Boosts_AddHealth(int client, int amount, bool allowOverheal = false)
{
	if (amount <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	int health = GetClientHealth(client) + amount;
	int maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
	int cap = allowOverheal ? (maxHealth + amount) : maxHealth;
	if (health > cap)
	{
		health = cap;
	}
	SetEntityHealth(client, health);
}

void AJB_Boosts_StopRegen(int client)
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	if (g_Boost[client].regenTimer != null)
	{
		delete g_Boost[client].regenTimer;
		g_Boost[client].regenTimer = null;
	}
	g_Boost[client].regenEnd = 0.0;
}

void AJB_Boosts_StartRegen(int client, float duration)
{
	AJB_Boosts_StopRegen(client);
	g_Boost[client].regenEnd = GetGameTime() + duration;
	g_Boost[client].regenTimer = CreateTimer(BOOST_REGEN_TICK, Timer_BoostRegen, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_BoostRegen(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client) || GetGameTime() >= g_Boost[client].regenEnd)
	{
		if (client >= 1 && client <= MaxClients && g_Boost[client].regenTimer == timer)
		{
			g_Boost[client].regenTimer = null;
			g_Boost[client].regenEnd = 0.0;
		}
		return Plugin_Stop;
	}

	// Passive heal toward max HP (no stacking overheal from ticks).
	AJB_Boosts_AddHealth(client, BOOST_REGEN_PER_TICK, false);
	return Plugin_Continue;
}

bool AJB_Boosts_ThrowJar(int client, bool milk)
{
	float eye[3];
	float ang[3];
	float fwd[3];
	float vel[3];
	float pos[3];

	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, ang);
	GetAngleVectors(ang, fwd, NULL_VECTOR, NULL_VECTOR);

	pos[0] = eye[0] + fwd[0] * 16.0;
	pos[1] = eye[1] + fwd[1] * 16.0;
	pos[2] = eye[2] + fwd[2] * 16.0;

	vel[0] = fwd[0] * BOOST_JAR_THROW_SPEED;
	vel[1] = fwd[1] * BOOST_JAR_THROW_SPEED;
	vel[2] = fwd[2] * BOOST_JAR_THROW_SPEED;

	int ent = CreateEntityByName(milk ? "tf_projectile_jar_milk" : "tf_projectile_jar");
	if (ent == -1 || !IsValidEntity(ent))
	{
		return false;
	}

	int team = GetClientTeam(client);
	SetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity", client);
	SetEntPropEnt(ent, Prop_Send, "m_hThrower", client);
	SetEntProp(ent, Prop_Send, "m_iTeamNum", team);
	SetEntProp(ent, Prop_Data, "m_iTeamNum", team);

	DispatchSpawn(ent);
	TeleportEntity(ent, pos, ang, vel);
	return true;
}

// =========================================================================================================
// Damage hooks (Iron neck + melee crit)
// =========================================================================================================

void AJB_Boosts_HookClient(int client)
{
	if (Boost_HasFlag(client, BF_DAMAGE_HOOKED) || !IsClientInGame(client))
	{
		return;
	}

	SDKHook(client, SDKHook_OnTakeDamage, AJB_Boosts_OnTakeDamage);
	Boost_SetFlag(client, BF_DAMAGE_HOOKED, true);
}

Action AJB_Boosts_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (!g_bBoostsEnabled)
	{
		return Plugin_Continue;
	}

	bool changed = false;

	// RED boost: first melee hit is a full crit.
	if (attacker >= 1 && attacker <= MaxClients
		&& Boost_HasFlag(attacker, BF_MELEE_CRIT)
		&& attacker != victim
		&& IsClientInGame(attacker)
		&& IsPlayerAlive(attacker))
	{
		bool isMelee = false;
		if (weapon > MaxClients && IsValidEntity(weapon))
		{
			int melee = GetPlayerWeaponSlot(attacker, TFWeaponSlot_Melee);
			isMelee = (melee == weapon);
		}
		if (!isMelee && (damagetype & DMG_CLUB) == DMG_CLUB)
		{
			isMelee = true;
		}

		if (isMelee)
		{
			damagetype |= DMG_CRIT;
			Boost_SetFlag(attacker, BF_MELEE_CRIT, false);
			changed = true;

			char prefix[32];
			AJB_GetPrefix(attacker, prefix, sizeof(prefix));
			CPrintToChat(attacker, "%T", "Boosts Melee Crit Used", attacker, prefix);
		}
	}

	// BLU boost: iron neck survives one backstab.
	if (g_Boost[victim].backstabCharges > 0
		&& IsClientInGame(victim)
		&& IsPlayerAlive(victim)
		&& damagecustom == TF_CUSTOM_BACKSTAB)
	{
		g_Boost[victim].backstabCharges--;

		int health = GetClientHealth(victim);
		if (damage >= float(health))
		{
			damage = float(health - 1);
			if (damage < 0.0)
			{
				damage = 0.0;
			}

			char prefix[32];
			AJB_GetPrefix(victim, prefix, sizeof(prefix));
			CPrintToChat(victim, "%T", "Boosts Backstab Saved", victim, prefix, g_Boost[victim].backstabCharges);
			if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
			{
				AJB_GetPrefix(attacker, prefix, sizeof(prefix));
				CPrintToChat(attacker, "%T", "Boosts Backstab Blocked", attacker, prefix, victim);
			}

			return Plugin_Changed;
		}
	}

	return changed ? Plugin_Changed : Plugin_Continue;
}
