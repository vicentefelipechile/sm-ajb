// =========================================================================================================
// Another Jailbreak — Admin tools module
// Menu + shortcuts for warden, rebel, cells, freeday, doors, status.
// =========================================================================================================

#pragma semicolon 1
#pragma newdecls required

// =========================================================================================================
// Imports
// =========================================================================================================

#include <sourcemod>
#include <sdktools>
#include <adminmenu>

#undef REQUIRE_PLUGIN
#include <ajb/ajb>
#include <ajb/boosts>
#define REQUIRE_PLUGIN

#include <ajb/phrases>

// =========================================================================================================
// Constants
// =========================================================================================================

#define PLUGIN_VERSION "1.0.0"

// =========================================================================================================
// Plugin info
// =========================================================================================================

public Plugin myinfo =
{
	name        = "Another Jailbreak - Admin",
	author      = "SummerTYT",
	description = "Another Jailbreak — admin menu and moderation helpers.",
	version     = PLUGIN_VERSION,
	url         = ""
};

// =========================================================================================================
// State
// =========================================================================================================

ConVar g_cvEnabled;
bool g_bHasCore;
bool g_bHasBoosts;

TopMenu g_hAdminMenu;

// =========================================================================================================
// Lifecycle
// =========================================================================================================

public void OnPluginStart()
{
	CreateConVar("sm_ajb_admin_version", PLUGIN_VERSION, "AJB Admin module version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_ajb_admin_enabled", "1", "Enable AJB admin menu.", _, true, 0.0, true, 1.0);

	AutoExecConfig(true, "ajb_admin");

	LoadTranslations("ajb_admin.phrases");
	LoadTranslations("common.phrases");

	RegAdminCmd("sm_ajb", Command_AdminMenu, ADMFLAG_GENERIC, "Open Another Jailbreak admin menu.");
	RegAdminCmd("sm_ajb_admin", Command_AdminMenu, ADMFLAG_GENERIC, "Open Another Jailbreak admin menu.");
	RegAdminCmd("sm_ajb_status", Command_Status, ADMFLAG_GENERIC, "Print AJB live status.");
	RegAdminCmd("sm_ajb_freeday", Command_Freeday, ADMFLAG_GENERIC, "Usage: sm_ajb_freeday <#userid|name> [0|1] (next-round wish)");
	RegAdminCmd("sm_ajb_clearwarden", Command_ClearWarden, ADMFLAG_GENERIC, "Clear the current warden.");

	g_bHasCore = LibraryExists(AJB_LIBRARY);
	g_bHasBoosts = LibraryExists(AJB_BOOSTS_LIBRARY);

	LogMessage("[AJB-Admin] loaded (core %s, boosts %s).",
		g_bHasCore ? "present" : "missing",
		g_bHasBoosts ? "present" : "missing");
}

public void OnAllPluginsLoaded()
{
	if (LibraryExists("adminmenu"))
	{
		RegisterAdminMenuItem(GetAdminTopMenu());
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = true;
	}
	else if (StrEqual(name, AJB_BOOSTS_LIBRARY))
	{
		g_bHasBoosts = true;
	}
	else if (StrEqual(name, "adminmenu"))
	{
		RegisterAdminMenuItem(GetAdminTopMenu());
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = false;
	}
	else if (StrEqual(name, AJB_BOOSTS_LIBRARY))
	{
		g_bHasBoosts = false;
	}
	else if (StrEqual(name, "adminmenu"))
	{
		g_hAdminMenu = null;
	}
}

public void OnAdminMenuReady(Handle topmenu)
{
	RegisterAdminMenuItem(TopMenu.FromHandle(topmenu));
}

// =========================================================================================================
// Admin menu integration (/admin → Server Commands)
// =========================================================================================================

void RegisterAdminMenuItem(TopMenu menu)
{
	if (menu == null)
	{
		return;
	}

	if (menu == g_hAdminMenu)
	{
		return;
	}
	g_hAdminMenu = menu;

	TopMenuObject serverCommands = menu.FindCategory(ADMINMENU_SERVERCOMMANDS);
	if (serverCommands == INVALID_TOPMENUOBJECT)
	{
		LogError("[AJB-Admin] Admin menu category '%s' not found; AJB will not appear under /admin.", ADMINMENU_SERVERCOMMANDS);
		return;
	}

	menu.AddItem("sm_ajb", AdminMenu_AJB, serverCommands, "sm_ajb", ADMFLAG_GENERIC);
}

public void AdminMenu_AJB(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "%T", "Menu Item", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		AJB_Admin_ShowMain(param, true);
	}
}

// =========================================================================================================
// Commands
// =========================================================================================================

Action Command_AdminMenu(int client, int args)
{
	if (!g_cvEnabled.BoolValue)
	{
		AJB_Reply(client, "Admin Disabled");
		return Plugin_Handled;
	}

	if (!g_bHasCore || !AJB_IsEnabled())
	{
		AJB_Reply(client, "Admin Mode Inactive");
		return Plugin_Handled;
	}

	if (client == 0)
	{
		AJB_Reply(client, "Admin Ingame Only");
		return Plugin_Handled;
	}

	AJB_Admin_ShowMain(client, false);
	return Plugin_Handled;
}

Action Command_Status(int client, int args)
{
	if (!g_bHasCore)
	{
		AJB_Reply(client, "Admin Mode Inactive");
		return Plugin_Handled;
	}

	char stateName[32];
	AJB_Admin_StateName(AJB_GetRoundState(), stateName, sizeof(stateName));

	int warden = AJB_GetWarden();
	char wardenName[64];
	if (warden > 0 && IsClientInGame(warden))
	{
		GetClientName(warden, wardenName, sizeof(wardenName));
	}
	else
	{
		strcopy(wardenName, sizeof(wardenName), "-");
	}

	int rebels = 0;
	int freedays = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}
		if (AJB_IsRebel(i))
		{
			rebels++;
		}
		if (AJB_IsFreeday(i))
		{
			freedays++;
		}
	}

	ReplyToCommand(client, "[AJB] enabled=%d state=%s warden=%s rebels=%d freeday=%d",
		AJB_IsEnabled(), stateName, wardenName, rebels, freedays);
	return Plugin_Handled;
}

Action Command_Freeday(int client, int args)
{
	if (!g_bHasCore || !AJB_IsEnabled())
	{
		AJB_Reply(client, "Admin Mode Inactive");
		return Plugin_Handled;
	}

	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_ajb_freeday <#userid|name> [0|1]");
		return Plugin_Handled;
	}

	char targetArg[64];
	GetCmdArg(1, targetArg, sizeof(targetArg));

	char targetName[MAX_TARGET_LENGTH];
	int targetList[MAXPLAYERS];
	bool tnIsMl;
	int count = ProcessTargetString(targetArg, client, targetList, MAXPLAYERS, COMMAND_FILTER_CONNECTED, targetName, sizeof(targetName), tnIsMl);
	if (count <= 0)
	{
		ReplyToTargetError(client, count);
		return Plugin_Handled;
	}

	bool setFd = true;
	if (args >= 2)
	{
		char flag[8];
		GetCmdArg(2, flag, sizeof(flag));
		setFd = (StringToInt(flag) != 0);
	}

	for (int i = 0; i < count; i++)
	{
		AJB_SetPlayerFreeday(targetList[i], setFd);
	}

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	ReplyToCommand(client, "%T", setFd ? "Admin Freeday On" : "Admin Freeday Off", AJB_TransTarget(client), prefix, targetName);
	return Plugin_Handled;
}

Action Command_ClearWarden(int client, int args)
{
	if (!g_bHasCore || !AJB_IsEnabled())
	{
		AJB_Reply(client, "Admin Mode Inactive");
		return Plugin_Handled;
	}

	AJB_ClearWarden();
	AJB_Reply(client, "Admin Warden Cleared");
	return Plugin_Handled;
}

// =========================================================================================================
// Menu
// =========================================================================================================

void AJB_Admin_ShowMain(int client, bool fromAdminTopMenu)
{
	Menu menu = new Menu(MenuHandler_AdminMain);
	menu.SetTitle("%T", "Admin Menu Title", client);

	char line[64];
	Format(line, sizeof(line), "%T", "Admin Menu Status", client);
	menu.AddItem("status", line);
	Format(line, sizeof(line), "%T", "Admin Menu Open Cells", client);
	menu.AddItem("open", line);
	Format(line, sizeof(line), "%T", "Admin Menu Close Cells", client);
	menu.AddItem("close", line);
	Format(line, sizeof(line), "%T", "Admin Menu Clear Warden", client);
	menu.AddItem("clearw", line);
	Format(line, sizeof(line), "%T", "Admin Menu Set Warden", client);
	menu.AddItem("setw", line);
	Format(line, sizeof(line), "%T", "Admin Menu Toggle Rebel", client);
	menu.AddItem("rebel", line);
	Format(line, sizeof(line), "%T", "Admin Menu Toggle Freeday", client);
	menu.AddItem("freeday", line);

	if (g_bHasBoosts)
	{
		Format(line, sizeof(line), "%T", "Admin Menu Give Boost", client);
		menu.AddItem("giveboost", line);
		Format(line, sizeof(line), "%T", "Admin Menu Take Boost", client);
		menu.AddItem("takeboost", line);
	}

	Format(line, sizeof(line), "%T", "Admin Menu Reload Doors", client);
	menu.AddItem("doorsr", line);
	Format(line, sizeof(line), "%T", "Admin Menu List Doors", client);
	menu.AddItem("doorsl", line);

	menu.ExitBackButton = fromAdminTopMenu && g_hAdminMenu != null;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_AdminMain(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}

	if (action == MenuAction_Cancel)
	{
		if (param2 == MenuCancel_ExitBack && g_hAdminMenu != null)
		{
			g_hAdminMenu.Display(param1, TopMenuPosition_LastCategory);
		}
		return 0;
	}

	if (action != MenuAction_Select)
	{
		return 0;
	}

	int client = param1;
	if (!g_bHasCore || !AJB_IsEnabled())
	{
		return 0;
	}

	bool fromTop = menu.ExitBackButton;

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "status"))
	{
		FakeClientCommand(client, "sm_ajb_status");
		AJB_Admin_ShowMain(client, fromTop);
	}
	else if (StrEqual(info, "open"))
	{
		AJB_OpenCells();
		AJB_Chat(client, "Admin Cells Opened");
		AJB_Admin_ShowMain(client, fromTop);
	}
	else if (StrEqual(info, "close"))
	{
		AJB_CloseCells();
		AJB_Chat(client, "Admin Cells Closed");
		AJB_Admin_ShowMain(client, fromTop);
	}
	else if (StrEqual(info, "clearw"))
	{
		AJB_ClearWarden();
		AJB_Chat(client, "Admin Warden Cleared");
		AJB_Admin_ShowMain(client, fromTop);
	}
	else if (StrEqual(info, "setw"))
	{
		AJB_Admin_ShowPlayerPick(client, "setw", fromTop);
	}
	else if (StrEqual(info, "rebel"))
	{
		AJB_Admin_ShowPlayerPick(client, "rebel", fromTop);
	}
	else if (StrEqual(info, "freeday"))
	{
		AJB_Admin_ShowPlayerPick(client, "freeday", fromTop);
	}
	else if (StrEqual(info, "giveboost"))
	{
		if (!g_bHasBoosts)
		{
			AJB_Chat(client, "Admin Boosts Missing");
			AJB_Admin_ShowMain(client, fromTop);
			return 0;
		}
		AJB_Admin_ShowPlayerPick(client, "giveboost", fromTop);
	}
	else if (StrEqual(info, "takeboost"))
	{
		if (!g_bHasBoosts)
		{
			AJB_Chat(client, "Admin Boosts Missing");
			AJB_Admin_ShowMain(client, fromTop);
			return 0;
		}
		AJB_Admin_ShowPlayerPick(client, "takeboost", fromTop);
	}
	else if (StrEqual(info, "doorsr"))
	{
		FakeClientCommand(client, "sm_ajb_doors_reload");
		AJB_Admin_ShowMain(client, fromTop);
	}
	else if (StrEqual(info, "doorsl"))
	{
		FakeClientCommand(client, "sm_ajb_doors_list");
		AJB_Admin_ShowMain(client, fromTop);
	}

	return 0;
}

void AJB_Admin_ShowPlayerPick(int client, const char[] mode, bool fromAdminTopMenu)
{
	Menu menu = new Menu(MenuHandler_PlayerPick);
	menu.SetTitle("%T", "Admin Pick Player", client);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char info[48];
		char name[72];
		Format(info, sizeof(info), "%s:%d:%d", mode, GetClientUserId(i), fromAdminTopMenu ? 1 : 0);
		GetClientName(i, name, sizeof(name));

		// Show current boost total when adjusting points.
		if (g_bHasBoosts && (StrEqual(mode, "giveboost") || StrEqual(mode, "takeboost")))
		{
			Format(name, sizeof(name), "%s [%d]", name, AJB_Boosts_GetPoints(i));
		}

		menu.AddItem(info, name);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_PlayerPick(Menu menu, MenuAction action, int param1, int param2)
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
			AJB_Admin_ShowMain(param1, g_hAdminMenu != null);
		}
		return 0;
	}

	if (action != MenuAction_Select)
	{
		return 0;
	}

	int client = param1;
	char info[40];
	menu.GetItem(param2, info, sizeof(info));

	char parts[3][16];
	if (ExplodeString(info, ":", parts, 3, 16) < 2)
	{
		return 0;
	}

	bool fromTop = (parts[2][0] == '1');
	int target = GetClientOfUserId(StringToInt(parts[1]));
	if (target <= 0 || !IsClientInGame(target))
	{
		AJB_Chat(client, "Admin Player Invalid");
		AJB_Admin_ShowMain(client, fromTop);
		return 0;
	}

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));

	if (StrEqual(parts[0], "setw"))
	{
		if (!AJB_IsGuard(target) || !IsPlayerAlive(target))
		{
			AJB_Chat(client, "Admin Warden Guards Only");
		}
		else
		{
			char cmd[64];
			Format(cmd, sizeof(cmd), "sm_ajb_setwarden #%d", GetClientUserId(target));
			FakeClientCommand(client, cmd);
		}
	}
	else if (StrEqual(parts[0], "rebel"))
	{
		bool next = !AJB_IsRebel(target);
		AJB_SetRebel(target, next);
		CPrintToChat(client, "%T", next ? "Admin Rebel On" : "Admin Rebel Off", client, prefix, target);
	}
	else if (StrEqual(parts[0], "freeday"))
	{
		bool next = !AJB_IsFreedayPending(target);
		AJB_SetPlayerFreeday(target, next);
		CPrintToChat(client, "%T", next ? "Admin Freeday OnPlayer" : "Admin Freeday OffPlayer", client, prefix, target);
	}
	else if (StrEqual(parts[0], "giveboost") || StrEqual(parts[0], "takeboost"))
	{
		if (!g_bHasBoosts)
		{
			AJB_Chat(client, "Admin Boosts Missing");
			AJB_Admin_ShowMain(client, fromTop);
			return 0;
		}

		bool give = StrEqual(parts[0], "giveboost");
		AJB_Admin_ShowBoostAmount(client, target, give, fromTop);
		return 0;
	}

	AJB_Admin_ShowMain(client, fromTop);
	return 0;
}

// Pick how many points to give (+) or take (−).
void AJB_Admin_ShowBoostAmount(int client, int target, bool give, bool fromAdminTopMenu)
{
	if (!IsClientInGame(target))
	{
		AJB_Chat(client, "Admin Player Invalid");
		AJB_Admin_ShowMain(client, fromAdminTopMenu);
		return;
	}

	Menu menu = new Menu(MenuHandler_BoostAmount);
	char title[96];
	int pts = g_bHasBoosts ? AJB_Boosts_GetPoints(target) : 0;
	Format(title, sizeof(title), "%T", give ? "Admin Boost Give Title" : "Admin Boost Take Title", client, target, pts);
	menu.SetTitle(title);

	char info[32];
	char line[32];
	for (int n = 1; n <= 3; n++)
	{
		Format(info, sizeof(info), "%s:%d:%d:%d", give ? "g" : "t", GetClientUserId(target), n, fromAdminTopMenu ? 1 : 0);
		Format(line, sizeof(line), "%T", give ? "Admin Boost Give N" : "Admin Boost Take N", client, n);
		menu.AddItem(info, line);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_BoostAmount(Menu menu, MenuAction action, int param1, int param2)
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
			AJB_Admin_ShowMain(param1, g_hAdminMenu != null);
		}
		return 0;
	}

	if (action != MenuAction_Select)
	{
		return 0;
	}

	int client = param1;
	char info[32];
	menu.GetItem(param2, info, sizeof(info));

	char parts[4][12];
	if (ExplodeString(info, ":", parts, 4, 12) < 4)
	{
		return 0;
	}

	bool give = (parts[0][0] == 'g');
	bool fromTop = (parts[3][0] == '1');
	int target = GetClientOfUserId(StringToInt(parts[1]));
	int amount = StringToInt(parts[2]);

	if (target <= 0 || !IsClientInGame(target) || amount < 1 || amount > 3)
	{
		AJB_Chat(client, "Admin Player Invalid");
		AJB_Admin_ShowMain(client, fromTop);
		return 0;
	}

	if (!g_bHasBoosts)
	{
		AJB_Chat(client, "Admin Boosts Missing");
		AJB_Admin_ShowMain(client, fromTop);
		return 0;
	}

	int delta = give ? amount : -amount;
	int total = AJB_Boosts_AddPointsEx(target, delta);

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	CPrintToChat(client, "%T", give ? "Admin Boost Gave" : "Admin Boost Took", client, prefix, amount, target, total);

	// Notify the target when they are a different human player.
	if (target != client && !IsFakeClient(target))
	{
		char tprefix[32];
		AJB_GetPrefix(target, tprefix, sizeof(tprefix));
		CPrintToChat(target, "%T", give ? "Admin Boost Received" : "Admin Boost Removed", target, tprefix, amount, total);
	}

	AJB_Admin_ShowMain(client, fromTop);
	return 0;
}

// =========================================================================================================
// Helpers
// =========================================================================================================

void AJB_Admin_StateName(AJBRoundState state, char[] buffer, int maxlen)
{
	switch (state)
	{
		case AJBState_Disabled:     strcopy(buffer, maxlen, "Off");
		case AJBState_Waiting:      strcopy(buffer, maxlen, "Waiting");
		case AJBState_CellsLocked:  strcopy(buffer, maxlen, "CellsLocked");
		case AJBState_CellsOpen:    strcopy(buffer, maxlen, "CellsOpen");
		case AJBState_LRChoosing:   strcopy(buffer, maxlen, "LRChoosing");
		case AJBState_LRChosen:     strcopy(buffer, maxlen, "LRChosen");
		case AJBState_SpecialDay:   strcopy(buffer, maxlen, "SpecialDay");
		case AJBState_RoundEnd:     strcopy(buffer, maxlen, "RoundEnd");
		default:                    strcopy(buffer, maxlen, "?");
	}
}

