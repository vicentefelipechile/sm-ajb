// =========================================================================================================
// Another Jailbreak — Admin tools module
// Menu + shortcuts for warden, rebel, cells, freeday, doors, status.
// Binary: plugins/ajb_admin.smx
// =========================================================================================================

#pragma semicolon 1
#pragma newdecls required

// =========================================================================================================
// Imports
// =========================================================================================================

#include <sourcemod>
#include <sdktools>

#undef REQUIRE_PLUGIN
#include <ajb/ajb>
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
	RegAdminCmd("sm_ajbadmin", Command_AdminMenu, ADMFLAG_GENERIC, "Open Another Jailbreak admin menu.");
	RegAdminCmd("sm_ajb_status", Command_Status, ADMFLAG_GENERIC, "Print AJB live status.");
	RegAdminCmd("sm_ajb_freeday", Command_Freeday, ADMFLAG_GENERIC, "Usage: sm_ajb_freeday <#userid|name> [0|1]");
	RegAdminCmd("sm_ajb_clearwarden", Command_ClearWarden, ADMFLAG_GENERIC, "Clear the current warden.");

	g_bHasCore = LibraryExists(AJB_LIBRARY);

	LogMessage("[AJB-Admin] loaded (core %s).", g_bHasCore ? "present" : "missing");
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

	AJB_Admin_ShowMain(client);
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

	// Individual freeday is a NEXT-round wish — never clears rebel this round.
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

void AJB_Admin_ShowMain(int client)
{
	Menu menu = new Menu(MenuHandler_AdminMain);
	menu.SetTitle("%T", "Admin Menu Title", client);

	menu.AddItem("status", "Status");
	menu.AddItem("open", "Open cells");
	menu.AddItem("close", "Close cells");
	menu.AddItem("clearw", "Clear warden");
	menu.AddItem("setw", "Set warden (pick player)");
	menu.AddItem("rebel", "Toggle rebel (pick player)");
	menu.AddItem("freeday", "Toggle freeday (pick player)");
	menu.AddItem("doorsr", "Reload door config");
	menu.AddItem("doorsl", "List door targets");

	menu.Display(client, 30);
}

public int MenuHandler_AdminMain(Menu menu, MenuAction action, int param1, int param2)
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
	if (!g_bHasCore || !AJB_IsEnabled())
	{
		return 0;
	}

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "status"))
	{
		FakeClientCommand(client, "sm_ajb_status");
		AJB_Admin_ShowMain(client);
	}
	else if (StrEqual(info, "open"))
	{
		AJB_OpenCells();
		AJB_Chat(client, "Admin Cells Opened");
		AJB_Admin_ShowMain(client);
	}
	else if (StrEqual(info, "close"))
	{
		AJB_CloseCells();
		AJB_Chat(client, "Admin Cells Closed");
		AJB_Admin_ShowMain(client);
	}
	else if (StrEqual(info, "clearw"))
	{
		AJB_ClearWarden();
		AJB_Chat(client, "Admin Warden Cleared");
		AJB_Admin_ShowMain(client);
	}
	else if (StrEqual(info, "setw"))
	{
		AJB_Admin_ShowPlayerPick(client, "setw");
	}
	else if (StrEqual(info, "rebel"))
	{
		AJB_Admin_ShowPlayerPick(client, "rebel");
	}
	else if (StrEqual(info, "freeday"))
	{
		AJB_Admin_ShowPlayerPick(client, "freeday");
	}
	else if (StrEqual(info, "doorsr"))
	{
		FakeClientCommand(client, "sm_ajb_doors_reload");
		AJB_Admin_ShowMain(client);
	}
	else if (StrEqual(info, "doorsl"))
	{
		FakeClientCommand(client, "sm_ajb_doors_list");
		AJB_Admin_ShowMain(client);
	}

	return 0;
}

void AJB_Admin_ShowPlayerPick(int client, const char[] mode)
{
	Menu menu = new Menu(MenuHandler_PlayerPick);
	menu.SetTitle("%T", "Admin Pick Player", client);

	// Encode mode in item info prefix: mode:userid
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char info[32];
		char name[64];
		Format(info, sizeof(info), "%s:%d", mode, GetClientUserId(i));
		GetClientName(i, name, sizeof(name));
		menu.AddItem(info, name);
	}

	menu.ExitBackButton = true;
	menu.Display(client, 30);
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
			AJB_Admin_ShowMain(param1);
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

	char parts[2][16];
	if (ExplodeString(info, ":", parts, 2, 16) < 2)
	{
		return 0;
	}

	int target = GetClientOfUserId(StringToInt(parts[1]));
	if (target <= 0 || !IsClientInGame(target))
	{
		AJB_Chat(client, "Admin Player Invalid");
		AJB_Admin_ShowMain(client);
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
			// Core admin command path.
			char cmd[64];
			Format(cmd, sizeof(cmd), "sm_ajb_setwarden #%d", GetClientUserId(target));
			FakeClientCommand(client, cmd);
		}
	}
	else if (StrEqual(parts[0], "rebel"))
	{
		bool next = !AJB_IsRebel(target);
		AJB_SetRebel(target, next);
		PrintToChat(client, "%T", next ? "Admin Rebel On" : "Admin Rebel Off", client, prefix, target);
	}
	else if (StrEqual(parts[0], "freeday"))
	{
		// Toggle next-round wish (pending), not current-round flag.
		bool next = !AJB_IsFreedayPending(target);
		AJB_SetPlayerFreeday(target, next);
		PrintToChat(client, "%T", next ? "Admin Freeday OnPlayer" : "Admin Freeday OffPlayer", client, prefix, target);
	}

	AJB_Admin_ShowMain(client);
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
		case AJBState_LastRequest:  strcopy(buffer, maxlen, "LR");
		case AJBState_SpecialDay:   strcopy(buffer, maxlen, "SpecialDay");
		case AJBState_RoundEnd:     strcopy(buffer, maxlen, "RoundEnd");
		default:                    strcopy(buffer, maxlen, "?");
	}
}


