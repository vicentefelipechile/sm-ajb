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
#include <tf2_stocks>

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

// Guard-ban store (blocks a player from joining the guards/BLU team).
// Persisted in SQL (databases.cfg entry named by sm_ajb_admin_db), keyed by SteamID64.
// g_hBanCache mirrors active bans (steamid64 -> expire unix, 0 = permanent) so the
// player_team enforcement never has to hit the database synchronously.
ConVar g_cvDbConfig;
Database g_hDB;
StringMap g_hBanCache;

// =========================================================================================================
// Lifecycle
// =========================================================================================================

public void OnPluginStart()
{
	CreateConVar("sm_ajb_admin_version", PLUGIN_VERSION, "AJB Admin module version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_ajb_admin_enabled", "1", "Enable AJB admin menu.", _, true, 0.0, true, 1.0);
	g_cvDbConfig = CreateConVar("sm_ajb_admin_db", "ajb", "databases.cfg entry name used to store guard bans (SQLite or MySQL). The server owner configures the connection there.", _);

	AutoExecConfig(true, "ajb_admin");

	LoadTranslations("ajb_admin.phrases");
	LoadTranslations("common.phrases");

	RegAdminCmd("sm_ajb", Command_AdminMenu, ADMFLAG_GENERIC, "Open Another Jailbreak admin menu.");
	RegAdminCmd("sm_ajb_admin", Command_AdminMenu, ADMFLAG_GENERIC, "Open Another Jailbreak admin menu.");
	RegAdminCmd("sm_ajb_status", Command_Status, ADMFLAG_GENERIC, "Print AJB live status.");
	RegAdminCmd("sm_ajb_freeday", Command_Freeday, ADMFLAG_GENERIC, "Usage: sm_ajb_freeday <#userid|name> [0|1] (next-round wish)");
	RegAdminCmd("sm_ajb_clearwarden", Command_ClearWarden, ADMFLAG_GENERIC, "Clear the current warden.");

	// Guard-ban moderation (block from BLU/guards team).
	RegAdminCmd("sm_ajb_guardban", Command_GuardBan, ADMFLAG_BAN, "Usage: sm_ajb_guardban <#userid|name|steamid64> [minutes] [reason] (0 min = permanent).");
	RegAdminCmd("sm_ajb_unguardban", Command_GuardUnban, ADMFLAG_BAN, "Usage: sm_ajb_unguardban <#userid|name|steamid64>");
	RegAdminCmd("sm_ajb_guardbans", Command_GuardBanList, ADMFLAG_GENERIC, "List active guard bans.");

	HookEvent("player_team", Event_PlayerTeam_GuardBan, EventHookMode_Post);

	g_hBanCache = new StringMap();
	AJB_DB_Connect();

	g_bHasCore = LibraryExists(AJB_LIBRARY);
	g_bHasBoosts = LibraryExists(AJB_BOOSTS_LIBRARY);

	LogMessage("[AJB-Admin] loaded (core %s, boosts %s).",
		g_bHasCore ? "present" : "missing",
		g_bHasBoosts ? "present" : "missing");
}

public void OnMapStart()
{
	// Pick up bans applied on other servers sharing the database.
	if (g_hDB != null)
	{
		AJB_DB_LoadCache();
	}
}

public void OnPluginEnd()
{
	delete g_hBanCache;
	// g_hDB is a shared handle; drop our reference (SM closes it when unused).
	g_hDB = null;
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
	Format(line, sizeof(line), "%T", "Admin Menu Guard Ban", client);
	menu.AddItem("guardban", line);

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
	else if (StrEqual(info, "guardban"))
	{
		AJB_Admin_ShowPlayerPick(client, "guardban", fromTop);
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
	else if (StrEqual(parts[0], "guardban"))
	{
		char gsid[32];
		if (GetClientAuthId(target, AuthId_SteamID64, gsid, sizeof(gsid)))
		{
			char gname[64];
			GetClientName(target, gname, sizeof(gname));
			char aname[64];
			if (client == 0)
			{
				strcopy(aname, sizeof(aname), "CONSOLE");
			}
			else
			{
				GetClientName(client, aname, sizeof(aname));
			}
			// Menu bans are permanent; use the command for timed bans.
			AJB_AddGuardBan(gsid, gname, 0, "Menu (permanent)", aname);
			AJB_EnforceGuardBan(target);
			CPrintToChat(client, "%s Guard-banned %N (permanent).", prefix, target);
			LogAction(client, target, "\"%L\" guard-banned \"%L\" via menu (permanent)", client, target);
		}
		else
		{
			AJB_Chat(client, "Admin Player Invalid");
		}
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

// =========================================================================================================
// Guard bans (SQL-backed) — block a player from joining the guards / BLU team
// =========================================================================================================

void AJB_DB_Connect()
{
	char cfg[64];
	g_cvDbConfig.GetString(cfg, sizeof(cfg));
	if (cfg[0] == '\0')
	{
		strcopy(cfg, sizeof(cfg), "ajb");
	}

	if (!SQL_CheckConfig(cfg))
	{
		// Fall back to the stock SQLite entry so bans still persist.
		if (!SQL_CheckConfig("storage-local"))
		{
			LogError("[AJB-Admin] databases.cfg has no '%s' or 'storage-local' entry; guard bans will not persist. Add one (SQLite or MySQL).", cfg);
			return;
		}

		LogMessage("[AJB-Admin] databases.cfg has no '%s' entry; using 'storage-local'.", cfg);
		strcopy(cfg, sizeof(cfg), "storage-local");
	}

	Database.Connect(OnDBConnect, cfg);
}

public void OnDBConnect(Database db, const char[] error, any data)
{
	if (db == null)
	{
		LogError("[AJB-Admin] guard-ban DB connect failed: %s", error);
		return;
	}

	g_hDB = db;

	// Portable across SQLite and MySQL.
	char q[512];
	Format(q, sizeof(q),
		"CREATE TABLE IF NOT EXISTS ajb_guardbans ("
		... "steamid VARCHAR(32) NOT NULL PRIMARY KEY, "
		... "name VARCHAR(64), "
		... "reason VARCHAR(128), "
		... "admin VARCHAR(64), "
		... "created INT NOT NULL DEFAULT 0, "
		... "expire INT NOT NULL DEFAULT 0);");
	g_hDB.Query(OnCreateTable, q);
}

public void OnCreateTable(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
		LogError("[AJB-Admin] guard-ban table create failed: %s", error);
		return;
	}

	AJB_DB_LoadCache();
}

void AJB_DB_LoadCache()
{
	if (g_hDB == null)
	{
		return;
	}

	// Drop expired rows, then load what remains.
	char q[192];
	Format(q, sizeof(q), "DELETE FROM ajb_guardbans WHERE expire <> 0 AND expire <= %d;", GetTime());
	g_hDB.Query(OnWriteDone, q);

	g_hDB.Query(OnCacheLoaded, "SELECT steamid, expire FROM ajb_guardbans;");
}

public void OnCacheLoaded(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
		LogError("[AJB-Admin] guard-ban cache load failed: %s", error);
		return;
	}

	g_hBanCache.Clear();
	int now = GetTime();

	while (results.FetchRow())
	{
		char sid[32];
		results.FetchString(0, sid, sizeof(sid));
		int expire = results.FetchInt(1);
		if (expire != 0 && expire <= now)
		{
			continue;
		}
		g_hBanCache.SetValue(sid, expire);
	}

	// Enforce against anyone already sitting on guards (e.g. late plugin load).
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			AJB_EnforceGuardBan(i);
		}
	}
}

public void OnWriteDone(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null && error[0] != '\0')
	{
		LogError("[AJB-Admin] guard-ban DB write failed: %s", error);
	}
}

bool AJB_IsGuardBanned(const char[] steamid)
{
	if (g_hBanCache == null || steamid[0] == '\0')
	{
		return false;
	}

	int expire;
	if (!g_hBanCache.GetValue(steamid, expire))
	{
		return false;
	}

	if (expire != 0 && expire <= GetTime())
	{
		// Lazily expire in cache; the row is pruned on next LoadCache.
		g_hBanCache.Remove(steamid);
		if (g_hDB != null)
		{
			char esid[64];
			g_hDB.Escape(steamid, esid, sizeof(esid));
			char q[160];
			Format(q, sizeof(q), "DELETE FROM ajb_guardbans WHERE steamid = '%s';", esid);
			g_hDB.Query(OnWriteDone, q);
		}
		return false;
	}

	return true;
}

void AJB_AddGuardBan(const char[] steamid, const char[] name, int minutes, const char[] reason, const char[] admin)
{
	int expire = (minutes <= 0) ? 0 : GetTime() + minutes * 60;
	g_hBanCache.SetValue(steamid, expire);

	if (g_hDB == null)
	{
		LogError("[AJB-Admin] guard ban applied to cache only (no database): %s", steamid);
		return;
	}

	char esid[64], ename[160], ereason[320], eadmin[160];
	g_hDB.Escape(steamid, esid, sizeof(esid));
	g_hDB.Escape(name, ename, sizeof(ename));
	g_hDB.Escape(reason, ereason, sizeof(ereason));
	g_hDB.Escape(admin, eadmin, sizeof(eadmin));

	char q[768];
	Format(q, sizeof(q),
		"REPLACE INTO ajb_guardbans (steamid, name, reason, admin, created, expire) VALUES ('%s', '%s', '%s', '%s', %d, %d);",
		esid, ename, ereason, eadmin, GetTime(), expire);
	g_hDB.Query(OnWriteDone, q);
}

bool AJB_RemoveGuardBan(const char[] steamid)
{
	bool had = g_hBanCache.Remove(steamid);

	if (g_hDB != null)
	{
		char esid[64];
		g_hDB.Escape(steamid, esid, sizeof(esid));
		char q[160];
		Format(q, sizeof(q), "DELETE FROM ajb_guardbans WHERE steamid = '%s';", esid);
		g_hDB.Query(OnWriteDone, q);
		return true;
	}

	return had;
}

int AJB_GuardsTeam()
{
	ConVar cv = FindConVar("sm_ajb_guards_team");
	return (cv == null) ? 3 : cv.IntValue;
}

int AJB_PrisonersTeam()
{
	ConVar cv = FindConVar("sm_ajb_prisoners_team");
	return (cv == null) ? 2 : cv.IntValue;
}

// Resolve a command argument (#userid / name / raw SteamID64) to a SteamID64 string.
// Returns the resolved client (>0) when it matched a connected player, 0 for a raw
// SteamID64 (offline), or -1 when it could not be resolved (error already replied).
int AJB_ResolveSteamID64(int client, const char[] arg, char[] out, int maxlen)
{
	// Raw 17-digit SteamID64 → offline target.
	int len = strlen(arg);
	if (len == 17)
	{
		bool digits = true;
		for (int i = 0; i < len; i++)
		{
			if (arg[i] < '0' || arg[i] > '9')
			{
				digits = false;
				break;
			}
		}
		if (digits)
		{
			strcopy(out, maxlen, arg);
			return 0;
		}
	}

	int target = FindTarget(client, arg, true, false);
	if (target <= 0)
	{
		// FindTarget already replied with the reason.
		return -1;
	}

	if (!GetClientAuthId(target, AuthId_SteamID64, out, maxlen))
	{
		ReplyToCommand(client, "[AJB] Could not read that player's SteamID yet (still connecting?).");
		return -1;
	}

	return target;
}

void AJB_EnforceGuardBan(int client)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
	{
		return;
	}

	if (GetClientTeam(client) != AJB_GuardsTeam())
	{
		return;
	}

	char sid[32];
	if (!GetClientAuthId(client, AuthId_SteamID64, sid, sizeof(sid)))
	{
		return;
	}

	if (!AJB_IsGuardBanned(sid))
	{
		return;
	}

	TF2_ChangeClientTeam(client, view_as<TFTeam>(AJB_PrisonersTeam()));

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	CPrintToChat(client, "%s You are banned from the guards team.", prefix);
}

void Event_PlayerTeam_GuardBan(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0)
	{
		return;
	}

	if (event.GetInt("team") != AJB_GuardsTeam())
	{
		return;
	}

	// Let the team change settle before moving them back.
	RequestFrame(Frame_EnforceGuardBan, GetClientUserId(client));
}

void Frame_EnforceGuardBan(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0)
	{
		AJB_EnforceGuardBan(client);
	}
}

Action Command_GuardBan(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[AJB] Usage: sm_ajb_guardban <#userid|name|steamid64> [minutes] [reason] (0 = permanent).");
		return Plugin_Handled;
	}

	char arg[64];
	GetCmdArg(1, arg, sizeof(arg));

	char sid[32];
	int target = AJB_ResolveSteamID64(client, arg, sid, sizeof(sid));
	if (target < 0)
	{
		return Plugin_Handled;
	}

	int minutes = 0;
	if (args >= 2)
	{
		char m[16];
		GetCmdArg(2, m, sizeof(m));
		minutes = StringToInt(m);
		if (minutes < 0)
		{
			minutes = 0;
		}
	}

	char reason[128];
	if (args >= 3)
	{
		// Everything after the minutes argument is the reason.
		char full[256];
		GetCmdArgString(full, sizeof(full));
		AJB_ExtractReason(full, 2, reason, sizeof(reason));
	}
	if (reason[0] == '\0')
	{
		strcopy(reason, sizeof(reason), "No reason");
	}

	char targetName[64];
	if (target > 0)
	{
		GetClientName(target, targetName, sizeof(targetName));
	}
	else
	{
		strcopy(targetName, sizeof(targetName), sid);
	}

	char adminName[64];
	if (client == 0)
	{
		strcopy(adminName, sizeof(adminName), "CONSOLE");
	}
	else
	{
		GetClientName(client, adminName, sizeof(adminName));
	}

	AJB_AddGuardBan(sid, targetName, minutes, reason, adminName);

	if (target > 0)
	{
		AJB_EnforceGuardBan(target);
	}

	if (minutes <= 0)
	{
		ReplyToCommand(client, "[AJB] Guard-banned %s (permanent). Reason: %s", targetName, reason);
	}
	else
	{
		ReplyToCommand(client, "[AJB] Guard-banned %s for %d min. Reason: %s", targetName, minutes, reason);
	}

	LogAction(client, target > 0 ? target : -1, "\"%L\" guard-banned \"%s\" (%s) for %d minutes (reason: %s)",
		client, targetName, sid, minutes, reason);
	return Plugin_Handled;
}

Action Command_GuardUnban(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[AJB] Usage: sm_ajb_unguardban <#userid|name|steamid64>");
		return Plugin_Handled;
	}

	char arg[64];
	GetCmdArg(1, arg, sizeof(arg));

	char sid[32];
	int target = AJB_ResolveSteamID64(client, arg, sid, sizeof(sid));
	if (target < 0)
	{
		return Plugin_Handled;
	}

	if (AJB_RemoveGuardBan(sid))
	{
		ReplyToCommand(client, "[AJB] Removed guard ban for %s.", sid);
		LogAction(client, target > 0 ? target : -1, "\"%L\" removed guard ban for \"%s\"", client, sid);
	}
	else
	{
		ReplyToCommand(client, "[AJB] %s was not guard-banned.", sid);
	}
	return Plugin_Handled;
}

Action Command_GuardBanList(int client, int args)
{
	if (g_hDB == null)
	{
		ReplyToCommand(client, "[AJB] Guard-ban database is not connected.");
		return Plugin_Handled;
	}

	g_hDB.Query(OnListDone, "SELECT steamid, name, reason, expire FROM ajb_guardbans ORDER BY created DESC;",
		(client > 0) ? GetClientUserId(client) : 0);
	return Plugin_Handled;
}

public void OnListDone(Database db, DBResultSet results, const char[] error, any data)
{
	int client = (data > 0) ? GetClientOfUserId(data) : 0;

	if (results == null)
	{
		ReplyToCommand(client, "[AJB] Guard-ban list query failed: %s", error);
		return;
	}

	int now = GetTime();
	int shown = 0;

	ReplyToCommand(client, "[AJB] Active guard bans:");
	while (results.FetchRow())
	{
		char sid[32], name[64], reason[128];
		results.FetchString(0, sid, sizeof(sid));
		results.FetchString(1, name, sizeof(name));
		results.FetchString(2, reason, sizeof(reason));
		int expire = results.FetchInt(3);

		if (expire != 0 && expire <= now)
		{
			continue;
		}

		if (expire == 0)
		{
			ReplyToCommand(client, "  %s | %s | permanent | %s", sid, name, reason);
		}
		else
		{
			int mins = (expire - now) / 60;
			ReplyToCommand(client, "  %s | %s | %d min left | %s", sid, name, mins, reason);
		}
		shown++;
	}

	if (shown == 0)
	{
		ReplyToCommand(client, "  (none)");
	}
}

// Copy the command-argument string starting at token `skip` (0-based) into `out`.
void AJB_ExtractReason(const char[] full, int skip, char[] out, int maxlen)
{
	out[0] = '\0';
	int len = strlen(full);
	int i = 0;
	int token = 0;

	// Walk past `skip` whitespace-delimited tokens.
	while (i < len && token < skip)
	{
		while (i < len && full[i] == ' ')
		{
			i++;
		}
		while (i < len && full[i] != ' ')
		{
			i++;
		}
		token++;
	}

	while (i < len && full[i] == ' ')
	{
		i++;
	}

	if (i < len)
	{
		strcopy(out, maxlen, full[i]);
	}
}

