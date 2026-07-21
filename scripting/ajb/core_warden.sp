// =========================================================================================================
// Warden claim / clear
// =========================================================================================================

void AJB_SetWarden(int client, bool announce)
{
	if (!AJB_IsValidClient(client) || !AJB_ClientIsGuard(client))
	{
		return;
	}

	int old = g_iWarden;
	if (old == client)
	{
		return;
	}

	g_iWarden = client;

	// Strip vision from previous warden; grant native see-enemy-health to the new one.
	if (old > 0 && IsClientInGame(old))
	{
		AJB_WardenHealth_Remove(old);
	}
	AJB_WardenHealth_Apply(client);

	Call_StartForward(g_hFwdWarden);
	Call_PushCell(old);
	Call_PushCell(client);
	Call_Finish();

	if (announce)
	{
		// Color the name in code — translation slot {2} is a pre-tagged string.
		char name[64];
		char nameTagged[96];
		GetClientName(client, name, sizeof(name));
		Format(nameTagged, sizeof(nameTagged), "{lightgreen}%s{default}", name);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}

			char prefix[64];
			AJB_GetPrefix(i, prefix, sizeof(prefix));
			CPrintToChat(i, "%T", "Warden Claimed", i, prefix, nameTagged);
		}
	}

	// Next frame: Display() during the same stack as claim often fails to show.
	if (IsClientInGame(client) && !IsFakeClient(client))
	{
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
	}
}

void AJB_ClearWarden(bool announce)
{
	if (g_iWarden == 0)
	{
		return;
	}

	int old = g_iWarden;
	g_iWarden = 0;

	if (old > 0 && IsClientInGame(old))
	{
		AJB_WardenHealth_Remove(old);
	}

	Call_StartForward(g_hFwdWarden);
	Call_PushCell(old);
	Call_PushCell(0);
	Call_Finish();

	if (!announce)
	{
		return;
	}

	if (AJB_IsValidClient(old))
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}

			char prefix[32];
			AJB_GetPrefix(i, prefix, sizeof(prefix));
			CPrintToChat(i, "%T", "Warden Cleared", i, prefix, old);
		}
	}
	else
	{
		AJB_ChatAll("Warden Cleared Unknown");
	}
}

bool AJB_IsWarden(int client)
{
	return client > 0 && client == g_iWarden;
}

bool AJB_CanControlCells(int client)
{
	if (!AJB_IsValidClient(client))
	{
		return false;
	}

	if (AJB_IsWarden(client))
	{
		return true;
	}

	return CheckCommandAccess(client, "sm_ajb_cells", ADMFLAG_GENERIC);
}

Action Command_Warden(int client, int args)
{
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}

	if (client == 0)
	{
		AJB_Reply(client, "Ingame Only");
		return Plugin_Handled;
	}

	if (!AJB_ClientIsGuard(client) || !IsPlayerAlive(client))
	{
		AJB_Reply(client, "Warden Guards Only");
		return Plugin_Handled;
	}

	if (g_iWarden != 0 && g_iWarden != client)
	{
		char prefix[32];
		AJB_GetPrefix(client, prefix, sizeof(prefix));
		ReplyToCommand(client, "%T", "Warden Already Taken", client, prefix, g_iWarden);
		return Plugin_Handled;
	}

	if (g_iWarden == client)
	{
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return Plugin_Handled;
	}

	AJB_SetWarden(client, true);
	return Plugin_Handled;
}

Action Command_WardenMenu(int client, int args)
{
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}

	if (client == 0)
	{
		AJB_Reply(client, "Ingame Only");
		return Plugin_Handled;
	}

	if (!AJB_IsWarden(client))
	{
		AJB_Reply(client, "Warden Not You");
		return Plugin_Handled;
	}

	RequestFrame(Frame_WardenMenu, GetClientUserId(client));
	return Plugin_Handled;
}

void Frame_WardenMenu(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0)
	{
		AJB_Warden_ShowMenu(client);
	}
}

// =========================================================================================================
// Warden menu
// =========================================================================================================

void AJB_Warden_ShowMenu(int client)
{
	if (!AJB_IsValidClient(client) || !AJB_IsWarden(client))
	{
		return;
	}

	Menu menu = new Menu(MenuHandler_Warden);

	// Format first — SetTitle("%T", ...) is unreliable if the phrase set just reloaded.
	char title[64];
	char line[64];
	Format(title, sizeof(title), "%T", "Warden Menu Title", client);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", "Warden Menu Open Cells", client);
	menu.AddItem("open", line);

	Format(line, sizeof(line), "%T", "Warden Menu Close Cells", client);
	menu.AddItem("close", line);

	// LR grant is handled by the lastrequest module via AJB_OnWardenGiveLR.
	Format(line, sizeof(line), "%T", "Warden Menu Give LR", client);
	menu.AddItem("give_lr", line);

	Format(line, sizeof(line), "%T", "Warden Menu Resign", client);
	menu.AddItem("resign", line);

	menu.ExitButton = true;
	// 0 = stay open until dismissed (MENU_TIME_FOREVER).
	menu.Display(client, 0);
}

public int MenuHandler_Warden(Menu menu, MenuAction action, int param1, int param2)
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
	if (!g_bModeActive || !AJB_IsWarden(client))
	{
		return 0;
	}

	// Resign is allowed while dead; cell control needs a living warden.
	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "resign"))
	{
		AJB_Warden_ShowResignConfirm(client);
		return 0;
	}

	if (!IsPlayerAlive(client))
	{
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}

	if (StrEqual(info, "open"))
	{
		AJB_OpenCellsInternal(true);
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
	}
	else if (StrEqual(info, "close"))
	{
		AJB_CloseCellsInternal(true);
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
	}
	else if (StrEqual(info, "give_lr"))
	{
		Call_StartForward(g_hFwdWardenGiveLR);
		Call_PushCell(client);
		Call_Finish();
	}

	return 0;
}

void AJB_Warden_ShowResignConfirm(int client)
{
	if (!AJB_IsValidClient(client) || !AJB_IsWarden(client))
	{
		return;
	}

	Menu menu = new Menu(MenuHandler_WardenResign);
	char title[96];
	char yes[64];
	char back[64];
	Format(title, sizeof(title), "%T", "Warden Resign Confirm Title", client);
	Format(yes, sizeof(yes), "%T", "Warden Resign Confirm Yes", client);
	Format(back, sizeof(back), "%T", "Warden Menu Back", client);
	menu.SetTitle(title);
	menu.AddItem("yes", yes);
	menu.AddItem("back", back);
	// Submenus always return to the main warden panel — no bare exit.
	menu.ExitButton = false;
	menu.ExitBackButton = true;
	menu.Display(client, 0);
}

public int MenuHandler_WardenResign(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}

	int client = param1;

	if (action == MenuAction_Cancel)
	{
		// 0 / EscapeBack / Escape → always re-open main warden menu while still warden.
		if (g_bModeActive && AJB_IsWarden(client))
		{
			RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		}
		return 0;
	}

	if (action != MenuAction_Select)
	{
		return 0;
	}

	if (!g_bModeActive || !AJB_IsWarden(client))
	{
		return 0;
	}

	char info[8];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "yes"))
	{
		AJB_ClearWarden(true);
		return 0;
	}

	// "back" or any non-yes → main menu
	RequestFrame(Frame_WardenMenu, GetClientUserId(client));
	return 0;
}

Action Command_UnWarden(int client, int args)
{
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}

	if (client == 0)
	{
		AJB_Reply(client, "Ingame Only");
		return Plugin_Handled;
	}

	if (!AJB_IsWarden(client))
	{
		AJB_Reply(client, "Warden Not You");
		return Plugin_Handled;
	}

	// Chat command also requires confirmation.
	AJB_Warden_ShowResignConfirm(client);
	return Plugin_Handled;
}

Action Command_OpenCells(int client, int args)
{
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}

	if (client != 0 && !AJB_CanControlCells(client))
	{
		AJB_Reply(client, "No Cell Access");
		return Plugin_Handled;
	}

	if (!AJB_OpenCellsInternal(true))
	{
		AJB_Reply(client, "Cells Open Failed");
		return Plugin_Handled;
	}

	return Plugin_Handled;
}

Action Command_CloseCells(int client, int args)
{
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}

	if (client != 0 && !AJB_CanControlCells(client))
	{
		AJB_Reply(client, "No Cell Access");
		return Plugin_Handled;
	}

	if (!AJB_CloseCellsInternal(true))
	{
		AJB_Reply(client, "Cells Close Failed");
		return Plugin_Handled;
	}

	return Plugin_Handled;
}

Action Command_AdminSetWarden(int client, int args)
{
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}

	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_ajb_setwarden <#userid|name>");
		return Plugin_Handled;
	}

	char targetArg[64];
	GetCmdArg(1, targetArg, sizeof(targetArg));

	char targetName[MAX_TARGET_LENGTH];
	int targetList[MAXPLAYERS];
	bool tnIsMl;
	int count = ProcessTargetString(targetArg, client, targetList, MAXPLAYERS, COMMAND_FILTER_ALIVE, targetName, sizeof(targetName), tnIsMl);
	if (count <= 0)
	{
		ReplyToTargetError(client, count);
		return Plugin_Handled;
	}

	int target = targetList[0];
	if (!AJB_ClientIsGuard(target))
	{
		AJB_Reply(client, "Warden Guards Only");
		return Plugin_Handled;
	}

	AJB_SetWarden(target, true);
	return Plugin_Handled;
}

Action Command_AdminRebel(int client, int args)
{
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}

	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_ajb_rebel <#userid|name> [0|1]");
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

	bool setRebel = true;
	if (args >= 2)
	{
		char flag[8];
		GetCmdArg(2, flag, sizeof(flag));
		setRebel = (StringToInt(flag) != 0);
	}

	for (int i = 0; i < count; i++)
	{
		AJB_SetRebelInternal(targetList[i], setRebel, true);
	}

	return Plugin_Handled;
}
