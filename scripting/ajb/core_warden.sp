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

	Call_StartForward(g_hFwdWarden);
	Call_PushCell(old);
	Call_PushCell(client);
	Call_Finish();

	if (announce)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}

			char prefix[32];
			AJB_GetPrefix(i, prefix, sizeof(prefix));
			PrintToChat(i, "%T", "Warden Claimed", i, prefix, client);
		}
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
			PrintToChat(i, "%T", "Warden Cleared", i, prefix, old);
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
		AJB_Reply(client, "Warden Already You");
		return Plugin_Handled;
	}

	AJB_SetWarden(client, true);
	return Plugin_Handled;
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

	AJB_ClearWarden(true);
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
