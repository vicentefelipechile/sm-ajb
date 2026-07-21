// =========================================================================================================
// Another Jailbreak — Boosts
// Round points + temporary gameplay boosts (NOT a general store/shop; no cosmetics/gadgets).
// Binary: plugins/ajb_boosts.smx
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

#define PLUGIN_VERSION "1.0.0"

#define BOOST_ID_IRON_NECK     "iron_neck"
#define BOOST_ID_IRON_NECK_II  "iron_neck_2"
#define BOOST_ID_REVIVE        "revive"

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
ConVar g_cvSpendCap;
ConVar g_cvBluEvery;

bool g_bHasCore;

int g_iPoints[MAXPLAYERS + 1];
int g_iSpentThisRound[MAXPLAYERS + 1];
int g_iBackstabCharges[MAXPLAYERS + 1];

// BLU passive: award every N completed rounds (server-wide counter of finished jail rounds).
int g_iFinishedRoundCount;

bool g_bDamageHooked[MAXPLAYERS + 1];

// =========================================================================================================
// Lifecycle
// =========================================================================================================

public void OnPluginStart()
{
	CreateConVar("sm_ajb_boosts_version", PLUGIN_VERSION, "AJB Boosts module version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_ajb_boosts_enabled", "1", "Enable the boosts system.", _, true, 0.0, true, 1.0);
	g_cvMaxPoints = CreateConVar("sm_ajb_boosts_max_points", "9", "Max points a player can hold (0 = unlimited).", _, true, 0.0);
	g_cvSpendCap = CreateConVar("sm_ajb_boosts_spend_cap", "3", "Max points spendable per round (0 = unlimited).", _, true, 0.0);
	g_cvBluEvery = CreateConVar("sm_ajb_boosts_blu_every", "2", "BLU surviving players get +1 extra every N finished rounds.", _, true, 1.0);

	AutoExecConfig(true, "ajb_boosts");

	LoadTranslations("ajb_boosts.phrases");
	LoadTranslations("common.phrases");

	RegConsoleCmd("sm_boosts", Command_Boosts, "Open the boosts menu.");
	RegConsoleCmd("sm_boost", Command_Boosts, "Alias of sm_boosts.");
	RegConsoleCmd("sm_points", Command_Points, "Show your boost points.");
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
	// No persistent DB in v1.
}

public void OnMapStart()
{
	g_iFinishedRoundCount = 0;
}

public void OnClientPutInServer(int client)
{
	g_iPoints[client] = 0;
	g_iSpentThisRound[client] = 0;
	g_iBackstabCharges[client] = 0;
	AJB_Boosts_HookClient(client);
}

public void OnClientDisconnect(int client)
{
	g_iPoints[client] = 0;
	g_iSpentThisRound[client] = 0;
	g_iBackstabCharges[client] = 0;
	g_bDamageHooked[client] = false;
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
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iSpentThisRound[i] = 0;
		g_iBackstabCharges[i] = 0;
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

		// Survive until round end → +1
		AJB_Boosts_AddPoints(i, 1, "survive");

		// BLU extra every N finished rounds (must also be alive at end)
		if (bluPassiveRound && AJB_IsGuard(i))
		{
			AJB_Boosts_AddPoints(i, 1, "blu_passive");
		}
	}

	// Unused charges expire at round end.
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iBackstabCharges[i] = 0;
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
	ReplyToCommand(client, "%T", "Boosts Points", client, prefix, g_iPoints[client]);
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

	int maxPts = g_cvMaxPoints.IntValue;
	int next = g_iPoints[client] + amount;
	if (maxPts > 0 && next > maxPts)
	{
		next = maxPts;
	}
	if (next < 0)
	{
		next = 0;
	}

	int gained = next - g_iPoints[client];
	g_iPoints[client] = next;

	if (gained > 0 && !StrEqual(reason, "admin"))
	{
		char prefix[32];
		AJB_GetPrefix(client, prefix, sizeof(prefix));
		PrintToChat(client, "%T", "Boosts Points Gained", client, prefix, gained, g_iPoints[client]);
	}
}

bool AJB_Boosts_TrySpend(int client, int cost)
{
	if (cost < 1 || cost > 3)
	{
		return false;
	}

	int cap = g_cvSpendCap.IntValue;
	if (cap > 0 && (g_iSpentThisRound[client] + cost) > cap)
	{
		char prefix[32];
		AJB_GetPrefix(client, prefix, sizeof(prefix));
		PrintToChat(client, "%T", "Boosts Spend Cap", client, prefix, cap);
		return false;
	}

	if (g_iPoints[client] < cost)
	{
		char prefix[32];
		AJB_GetPrefix(client, prefix, sizeof(prefix));
		PrintToChat(client, "%T", "Boosts Not Enough", client, prefix, cost, g_iPoints[client]);
		return false;
	}

	g_iPoints[client] -= cost;
	g_iSpentThisRound[client] += cost;
	return true;
}

// =========================================================================================================
// Menu
// =========================================================================================================

void AJB_Boosts_ShowMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Boosts);
	menu.SetTitle("%T", "Boosts Menu Title", client, g_iPoints[client], g_iSpentThisRound[client]);

	// Role-gated entries (gameplay boosts only).
	if (AJB_IsGuard(client))
	{
		char line[128];
		Format(line, sizeof(line), "%T", "Boost Iron Neck", client);
		menu.AddItem(BOOST_ID_IRON_NECK, line);

		Format(line, sizeof(line), "%T", "Boost Iron Neck II", client);
		menu.AddItem(BOOST_ID_IRON_NECK_II, line);

		if (AJB_GetWarden() == client)
		{
			Format(line, sizeof(line), "%T", "Boost Revive", client);
			menu.AddItem(BOOST_ID_REVIVE, line);
		}
	}
	else if (AJB_IsPrisoner(client))
	{
		// No RED boosts in v1 catalog — show empty state line.
		char line[128];
		Format(line, sizeof(line), "%T", "Boosts None For Role", client);
		menu.AddItem("none", line, ITEMDRAW_DISABLED);
	}
	else
	{
		char line[128];
		Format(line, sizeof(line), "%T", "Boosts Join Team", client);
		menu.AddItem("none", line, ITEMDRAW_DISABLED);
	}

	menu.Display(client, 30);
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

	char id[32];
	menu.GetItem(param2, id, sizeof(id));

	if (StrEqual(id, BOOST_ID_IRON_NECK))
	{
		AJB_Boosts_BuyIronNeck(client, 1, 1);
	}
	else if (StrEqual(id, BOOST_ID_IRON_NECK_II))
	{
		AJB_Boosts_BuyIronNeck(client, 2, 3);
	}
	else if (StrEqual(id, BOOST_ID_REVIVE))
	{
		AJB_Boosts_BuyRevive(client);
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

	// Do not stack infinite charges — replace with higher package if buying II over I.
	if (!AJB_Boosts_TrySpend(client, cost))
	{
		AJB_Boosts_ShowMenu(client);
		return;
	}

	if (charges > g_iBackstabCharges[client])
	{
		g_iBackstabCharges[client] = charges;
	}
	else
	{
		g_iBackstabCharges[client] += charges;
	}

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	PrintToChat(client, "%T", "Boosts Purchased Iron Neck", client, prefix, g_iBackstabCharges[client], g_iPoints[client]);
	AJB_Boosts_ShowMenu(client);
}

void AJB_Boosts_BuyRevive(int client)
{
	if (AJB_GetWarden() != client || !IsPlayerAlive(client))
	{
		AJB_Chat(client, "Boosts Warden Only");
		return;
	}

	if (AJB_GetRoundState() == AJBState_LastRequest)
	{
		AJB_Chat(client, "Boosts No LR");
		return;
	}

	// Pay only when a target is chosen.
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

		// Prefer AJB roles when available.
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

	if (AJB_GetRoundState() == AJBState_LastRequest)
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

	if (!AJB_Boosts_TrySpend(client, 3))
	{
		return 0;
	}

	// TF2 revive: respawn at team spawn.
	TF2_RespawnPlayer(target);

	// Prisoners stay under jail loadout rules (core strip on spawn timer).
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		PrintToChat(i, "%T", "Boosts Revived", i, prefix, client, target);
	}

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	PrintToChat(client, "%T", "Boosts Points Left", client, prefix, g_iPoints[client]);
	return 0;
}

// =========================================================================================================
// Backstab save (Iron neck)
// =========================================================================================================

void AJB_Boosts_HookClient(int client)
{
	if (g_bDamageHooked[client] || !IsClientInGame(client))
	{
		return;
	}

	SDKHook(client, SDKHook_OnTakeDamage, AJB_Boosts_OnTakeDamage);
	g_bDamageHooked[client] = true;
}

Action AJB_Boosts_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (!g_cvEnabled.BoolValue || g_iBackstabCharges[victim] <= 0)
	{
		return Plugin_Continue;
	}

	if (!IsClientInGame(victim) || !IsPlayerAlive(victim))
	{
		return Plugin_Continue;
	}

	// Only Spy backstabs.
	if (damagecustom != TF_CUSTOM_BACKSTAB)
	{
		return Plugin_Continue;
	}

	g_iBackstabCharges[victim]--;

	// Survive: leave the victim critically low instead of dead.
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
		PrintToChat(victim, "%T", "Boosts Backstab Saved", victim, prefix, g_iBackstabCharges[victim]);
		if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
		{
			AJB_GetPrefix(attacker, prefix, sizeof(prefix));
			PrintToChat(attacker, "%T", "Boosts Backstab Blocked", attacker, prefix, victim);
		}

		return Plugin_Changed;
	}

	return Plugin_Continue;
}
