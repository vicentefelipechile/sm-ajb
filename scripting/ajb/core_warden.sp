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
	g_iWardenLastRound[client] = g_iWardenRoundSerial;
	// New wardenship always starts on the first menu page.
	g_iWardenMenuPage[client] = 0;

	// Strip vision from previous warden; grant native see-enemy-health to the new one.
	if (old > 0 && IsClientInGame(old))
	{
		AJB_WardenHealth_Remove(old);
	}
	AJB_WardenHealth_Apply(client);

	// Overhead "Warden" label follows the new warden; clears with them (see AJB_ClearWarden).
	AJB_Label_Show(client);

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

		AJB_ChatAll1S("Warden Claimed", nameTagged);
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

	// A warden's marker and overhead label should not outlive their wardenship.
	AJB_Marker_Clear();
	AJB_Label_Hide();
	// Drop any half-composed vote the resigning warden was typing.
	AJB_Votes_Reset();

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
		AJB_ChatAll1N("Warden Cleared", old);
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

// Claim / auto-warden only during a live round — never prep (preround) or postround.
bool AJB_CanClaimWarden()
{
	if (!g_bModeActive)
	{
		return false;
	}

	// Prep window = first N seconds after teamplay_round_start (preround for JB).
	if (AJB_IsPrepActive())
	{
		return false;
	}

	// War Day / Class Warfare / Freeday-all: no warden claim.
	if (AJB_NoWardenClaim())
	{
		return false;
	}

	if (g_RoundState == AJBState_Disabled
		|| g_RoundState == AJBState_Waiting
		|| g_RoundState == AJBState_RoundEnd
		|| g_RoundState == AJBState_SpecialDay)
	{
		return false;
	}

	return g_RoundState == AJBState_CellsLocked
		|| g_RoundState == AJBState_CellsOpen
		|| AJB_IsLRPhase(g_RoundState);
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

	// Already warden: open menu only while the round is still live.
	if (g_iWarden == client)
	{
		if (!AJB_CanClaimWarden())
		{
			AJB_Reply(client, "Warden Claim Not Now");
			return Plugin_Handled;
		}

		// A fresh /warden always opens on the first page, never a stale section.
		g_iWardenMenuPage[client] = 0;
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return Plugin_Handled;
	}

	// Fresh claim blocked in prep / waiting / round end.
	if (!AJB_CanClaimWarden())
	{
		AJB_Reply(client, "Warden Claim Not Now");
		return Plugin_Handled;
	}

	if (g_iWarden != 0)
	{
		char prefix[32];
		AJB_GetPrefix(client, prefix, sizeof(prefix));
		CReplyToCommand(client, "%T", "Warden Already Taken", client, prefix, g_iWarden);
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

	// Fresh command open always starts on the first page; reopens keep the page.
	g_iWardenMenuPage[client] = 0;
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
// Warden menu (configurable layout) lives in core_warden_menu.sp
// =========================================================================================================

// markMode = true  → list non-rebel living prisoners (set rebel)
// markMode = false → list rebel living prisoners (pardon)
void AJB_Warden_ShowRebelPick(int client, bool markMode)
{
	if (!AJB_IsValidClient(client) || !AJB_IsWarden(client))
	{
		return;
	}

	if (g_cvWardenRebelControl == null || !g_cvWardenRebelControl.BoolValue)
	{
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return;
	}

	Menu menu = new Menu(MenuHandler_WardenRebel);
	char title[96];
	char line[64];
	Format(title, sizeof(title), "%T", markMode ? "Warden Mark Rebel Title" : "Warden Pardon Rebel Title", client);
	menu.SetTitle(title);

	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || !AJB_ClientIsPrisoner(i))
		{
			continue;
		}

		// Mark: only non-rebels. Pardon: only rebels.
		if (markMode == AJB_FlagGet(i, AJB_PF_REBEL))
		{
			continue;
		}

		char id[12];
		// Encode action + userid so the handler knows mark vs pardon without extra state.
		Format(id, sizeof(id), "%c%d", markMode ? 'M' : 'P', GetClientUserId(i));
		GetClientName(i, line, sizeof(line));
		menu.AddItem(id, line);
		count++;
	}

	if (count < 1)
	{
		delete menu;
		AJB_Chat(client, markMode ? "Warden Rebel None" : "Warden Pardon None");
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return;
	}

	// Only ExitBackButton — do not also AddItem("back") or the list shows two "Volver".
	menu.ExitButton = false;
	menu.ExitBackButton = true;
	menu.Display(client, 0);
}

public int MenuHandler_WardenRebel(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}

	int client = param1;

	if (action == MenuAction_Cancel)
	{
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

	if (g_cvWardenRebelControl == null || !g_cvWardenRebelControl.BoolValue)
	{
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}

	if (!IsPlayerAlive(client))
	{
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	bool markMode = (info[0] == 'M');
	if (info[0] != 'M' && info[0] != 'P')
	{
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}

	int target = GetClientOfUserId(StringToInt(info[1]));
	if (target < 1
		|| !IsClientInGame(target)
		|| !IsPlayerAlive(target)
		|| !AJB_ClientIsPrisoner(target)
		|| (markMode == AJB_FlagGet(target, AJB_PF_REBEL)))
	{
		// Invalid / already in desired state — refresh the same pick list.
		AJB_Warden_ShowRebelPick(client, markMode);
		return 0;
	}

	AJB_SetRebelInternal(target, markMode, true, client);
	// Stay on the same submenu so the warden can process several players.
	AJB_Warden_ShowRebelPick(client, markMode);
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
	char line[64];
	Format(title, sizeof(title), "%T", "Warden Resign Confirm Title", client);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", "Warden Resign Confirm Yes", client);
	menu.AddItem("yes", line);

	// Explicit "No" as item 2 so both choices sit next to each other.
	Format(line, sizeof(line), "%T", "Warden Resign Confirm No", client);
	menu.AddItem("no", line);

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

	// "no" (or anything else) → reopen the main menu on the page it was left on.
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

Action Command_UnWardenInstant(int client, int args)
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

	// Resign warden instantly with no confirmation panel
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
		// client may be 0 (console) → auto phrase without actor name.
		AJB_SetRebelInternal(targetList[i], setRebel, true, client);
	}

	return Plugin_Handled;
}

// =========================================================================================================
// Guard /markrebel command + menu
// =========================================================================================================

Action Command_GuardMarkRebel(int client, int args)
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

	if (g_cvGuardMarkRebelEnabled == null || !g_cvGuardMarkRebelEnabled.BoolValue)
	{
		AJB_Reply(client, "Guard Mark Rebel Disabled");
		return Plugin_Handled;
	}

	if (!AJB_ClientIsGuard(client))
	{
		AJB_Reply(client, "Guard Mark Rebel Guards Only");
		return Plugin_Handled;
	}

	if (!IsPlayerAlive(client))
	{
		AJB_Reply(client, "Guard Mark Rebel Alive Only");
		return Plugin_Handled;
	}

	float cooldown = g_cvGuardMarkRebelCooldown.FloatValue;
	if (cooldown > 0.0)
	{
		float now = GetEngineTime();
		float elapsed = now - g_fGuardMarkRebelLastTime[client];
		if (elapsed < cooldown)
		{
			int remaining = RoundToCeil(cooldown - elapsed);
			char prefix[32];
			AJB_GetPrefix(client, prefix, sizeof(prefix));
			CReplyToCommand(client, "%T", "Guard Mark Rebel Cooldown", client, prefix, remaining);
			return Plugin_Handled;
		}
	}

	AJB_Guard_ShowRebelPick(client);
	return Plugin_Handled;
}

void AJB_Guard_ShowRebelPick(int client)
{
	if (!AJB_IsValidClient(client) || !AJB_ClientIsGuard(client) || !IsPlayerAlive(client))
	{
		return;
	}

	if (g_cvGuardMarkRebelEnabled == null || !g_cvGuardMarkRebelEnabled.BoolValue)
	{
		return;
	}

	Menu menu = new Menu(MenuHandler_GuardRebel);
	char title[96];
	char line[64];
	Format(title, sizeof(title), "%T", "Guard Mark Rebel Title", client);
	menu.SetTitle(title);

	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || !AJB_ClientIsPrisoner(i))
		{
			continue;
		}

		if (AJB_FlagGet(i, AJB_PF_REBEL))
		{
			continue;
		}

		char id[12];
		Format(id, sizeof(id), "%d", GetClientUserId(i));
		GetClientName(i, line, sizeof(line));
		menu.AddItem(id, line);
		count++;
	}

	if (count < 1)
	{
		delete menu;
		AJB_Chat(client, "Guard Mark Rebel None");
		return;
	}

	menu.ExitButton = true;
	menu.Display(client, 0);
}

public int MenuHandler_GuardRebel(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}

	int client = param1;
	if (action != MenuAction_Select)
	{
		return 0;
	}

	if (!g_bModeActive || !AJB_ClientIsGuard(client) || !IsPlayerAlive(client))
	{
		return 0;
	}

	if (g_cvGuardMarkRebelEnabled == null || !g_cvGuardMarkRebelEnabled.BoolValue)
	{
		return 0;
	}

	float cooldown = g_cvGuardMarkRebelCooldown.FloatValue;
	float now = GetEngineTime();
	if (cooldown > 0.0)
	{
		float elapsed = now - g_fGuardMarkRebelLastTime[client];
		if (elapsed < cooldown)
		{
			int remaining = RoundToCeil(cooldown - elapsed);
			char prefix[32];
			AJB_GetPrefix(client, prefix, sizeof(prefix));
			CPrintToChat(client, "%T", "Guard Mark Rebel Cooldown", client, prefix, remaining);
			return 0;
		}
	}

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	int target = GetClientOfUserId(StringToInt(info));
	if (target < 1
		|| !IsClientInGame(target)
		|| !IsPlayerAlive(target)
		|| !AJB_ClientIsPrisoner(target)
		|| AJB_FlagGet(target, AJB_PF_REBEL))
	{
		AJB_Guard_ShowRebelPick(client);
		return 0;
	}

	g_fGuardMarkRebelLastTime[client] = now;
	AJB_SetRebelInternal(target, true, true, client);
	return 0;
}

// =========================================================================================================
// Repeat Order command
// =========================================================================================================

Action Command_Repeat(int client, int args)
{
	if (!g_cvRepeatEnabled.BoolValue)
	{
		return Plugin_Handled;
	}

	if (client <= 0 || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}

	if (!g_bModeActive)
	{
		return Plugin_Handled;
	}

	if (!AJB_ClientIsPrisoner(client) || !IsPlayerAlive(client))
	{
		AJB_Reply(client, "Repeat Prisoners Only");
		return Plugin_Handled;
	}

	if (g_iWarden <= 0)
	{
		AJB_Reply(client, "Repeat No Warden");
		return Plugin_Handled;
	}
	
	float now = GetGameTime();
	if (now < g_fNextRepeatTime[client])
	{
		int remaining = RoundToCeil(g_fNextRepeatTime[client] - now);
		char prefix[32];
		AJB_GetPrefix(client, prefix, sizeof(prefix));
		CReplyToCommand(client, "%T", "Repeat Cooldown", client, prefix, remaining);
		return Plugin_Handled;
	}
	
	g_fNextRepeatTime[client] = now + g_cvRepeatCooldown.FloatValue;
	
	// Chat message
	AJB_ChatAll1N("Repeat Requested", client);
	
	// Annotation over player
	AJB_Repeat_ShowAnnotation(client, g_cvRepeatMarkerTime.FloatValue);
	
	// Sound
	EmitSoundToAll("ui/hint.wav", client, SNDCHAN_AUTO, SNDLEVEL_NORMAL);

	return Plugin_Handled;
}

void AJB_Repeat_ShowAnnotation(int target, float life)
{
	Event ev = CreateEvent("show_annotation", true);
	if (ev == null)
	{
		return;
	}

	char text[64];
	Format(text, sizeof(text), "Repeat Order!");
	
	g_iRepeatAnnId = ++g_iRepeatAnnSerial;

	ev.SetInt("follow_entindex", target);
	ev.SetInt("id", g_iRepeatAnnId);
	ev.SetString("text", text);
	ev.SetFloat("lifetime", life);
	ev.SetInt("visibilityBitfield", 0);
	ev.Fire();
}

