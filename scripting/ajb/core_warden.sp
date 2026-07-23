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
// Warden menu
// =========================================================================================================

// Action codes mapped per key. TF2's radio menu drops non-numbered menu items
// entirely (RAWLINE) and forces disabled items to eat a number — so the paged hub
// is built as a Panel: DrawText() renders un-numbered headers/separators that cost
// no slot, DrawItem() renders the numbered actions. Panel handlers receive the raw
// key pressed (not an info string), so each key is mapped to an action here.
#define WA_NONE          0
#define WA_OPEN          1
#define WA_CLOSE         2
#define WA_MARKER        3
#define WA_COLLISIONS    4
#define WA_RESIGN        5
#define WA_PAGE_NEXT     6
#define WA_GIVE_LR       7
#define WA_VOTE_YESNO    8
#define WA_VOTE_MULTI    9
#define WA_MARK_REBEL    10
#define WA_PARDON_REBEL  11
#define WA_PAGE_PREV     12
#define WA_EXIT          13
#define WA_FRIENDLYFIRE  14

// key (1..10) → action for the panel currently shown to each warden. Rebuilt on
// every AJB_Warden_ShowMenu so gating cvars can add/remove items without desyncing.
int g_iWardenKeyAction[MAXPLAYERS + 1][11];

// Section header rendered as "── <name> ──" on its own, un-numbered Panel line.
void AJB_Warden_PanelHeader(Panel panel, int client, const char[] phrase)
{
	char name[48];
	char line[64];
	Format(name, sizeof(name), "%T", phrase, client);
	Format(line, sizeof(line), "── %s ──", name);
	panel.DrawText(line);
}

// A plain un-numbered divider line (before the navigation row).
void AJB_Warden_PanelSeparator(Panel panel)
{
	panel.DrawText("──────────────");
}

// Draw one numbered action; assigns it the next key and records the mapping.
// Returns the next free key.
int AJB_Warden_PanelAction(Panel panel, int client, int key, int action, const char[] display)
{
	panel.DrawItem(display);
	g_iWardenKeyAction[client][key] = action;
	return key + 1;
}

// Paged hub as a Panel. Headers/separators (DrawText) cost no slot; only the
// DrawItem actions are numbered. The current page lives in g_iWardenMenuPage[client]
// so reopens (RequestFrame) land back on the same section after an action.
void AJB_Warden_ShowMenu(int client)
{
	if (!AJB_IsValidClient(client) || !AJB_IsWarden(client))
	{
		return;
	}

	int page = g_iWardenMenuPage[client];
	if (page < 0 || page > AJB_WARDEN_MENU_LAST_PAGE)
	{
		page = 0;
		g_iWardenMenuPage[client] = 0;
	}

	// Fresh key map for this render.
	for (int k = 0; k <= 10; k++)
	{
		g_iWardenKeyAction[client][k] = WA_NONE;
	}

	Panel panel = new Panel();

	// No panel title — the section headers carry the structure on their own.
	char line[64];
	int key = 1;

	if (page == 0)
	{
		AJB_Warden_PanelHeader(panel, client, "Warden Header Cells");

		Format(line, sizeof(line), "%T", "Warden Menu Open Cells", client);
		key = AJB_Warden_PanelAction(panel, client, key, WA_OPEN, line);

		Format(line, sizeof(line), "%T", "Warden Menu Close Cells", client);
		key = AJB_Warden_PanelAction(panel, client, key, WA_CLOSE, line);

		bool hasTools = (g_cvMarkerEnabled != null && g_cvMarkerEnabled.BoolValue)
			|| (g_cvCollisionsControl != null && g_cvCollisionsControl.BoolValue)
			|| (g_cvFFControl != null && g_cvFFControl.BoolValue);
		if (hasTools)
		{
			AJB_Warden_PanelHeader(panel, client, "Warden Header Tools");
		}

		if (g_cvMarkerEnabled != null && g_cvMarkerEnabled.BoolValue)
		{
			Format(line, sizeof(line), "%T", "Warden Menu Marker", client);
			key = AJB_Warden_PanelAction(panel, client, key, WA_MARKER, line);
		}

		// Toggle teammate push; label reflects the action, not the current state.
		if (g_cvCollisionsControl != null && g_cvCollisionsControl.BoolValue)
		{
			Format(line, sizeof(line), "%T", g_bTeamPush ? "Warden Menu Collisions Disable" : "Warden Menu Collisions Enable", client);
			key = AJB_Warden_PanelAction(panel, client, key, WA_COLLISIONS, line);
		}

		// Toggle friendly fire; label reflects the action, not the current state.
		if (g_cvFFControl != null && g_cvFFControl.BoolValue)
		{
			Format(line, sizeof(line), "%T", g_bFriendlyFire ? "Warden Menu FriendlyFire Disable" : "Warden Menu FriendlyFire Enable", client);
			key = AJB_Warden_PanelAction(panel, client, key, WA_FRIENDLYFIRE, line);
		}

		AJB_Warden_PanelHeader(panel, client, "Warden Header Manage");

		Format(line, sizeof(line), "%T", "Warden Menu Resign", client);
		key = AJB_Warden_PanelAction(panel, client, key, WA_RESIGN, line);

		AJB_Warden_PanelSeparator(panel);

		Format(line, sizeof(line), "%T", "Warden Page Next", client);
		key = AJB_Warden_PanelAction(panel, client, key, WA_PAGE_NEXT, line);
	}
	else
	{
		AJB_Warden_PanelHeader(panel, client, "Warden Header Events");

		// LR grant is handled by the lastrequest module via AJB_OnWardenGiveLR.
		Format(line, sizeof(line), "%T", "Warden Menu Give LR", client);
		key = AJB_Warden_PanelAction(panel, client, key, WA_GIVE_LR, line);

		if (g_cvVoteEnabled != null && g_cvVoteEnabled.BoolValue)
		{
			Format(line, sizeof(line), "%T", "Warden Menu Vote YesNo", client);
			key = AJB_Warden_PanelAction(panel, client, key, WA_VOTE_YESNO, line);

			Format(line, sizeof(line), "%T", "Warden Menu Vote Multi", client);
			key = AJB_Warden_PanelAction(panel, client, key, WA_VOTE_MULTI, line);
		}

		// Mark / pardon RED rebels (gated by sm_ajb_warden_rebel_control).
		if (g_cvWardenRebelControl != null && g_cvWardenRebelControl.BoolValue)
		{
			AJB_Warden_PanelHeader(panel, client, "Warden Header Rebels");

			Format(line, sizeof(line), "%T", "Warden Menu Mark Rebel", client);
			key = AJB_Warden_PanelAction(panel, client, key, WA_MARK_REBEL, line);

			Format(line, sizeof(line), "%T", "Warden Menu Pardon Rebel", client);
			key = AJB_Warden_PanelAction(panel, client, key, WA_PARDON_REBEL, line);
		}

		AJB_Warden_PanelSeparator(panel);

		Format(line, sizeof(line), "%T", "Warden Page Prev", client);
		key = AJB_Warden_PanelAction(panel, client, key, WA_PAGE_PREV, line);
	}

	// Exit pinned to key 0 (slot 10), the TF2 convention. Map both 0 and 10 since
	// the handler may report either for the "0" key.
	Format(line, sizeof(line), "%T", "Warden Menu Exit", client);
	panel.CurrentKey = 10;
	panel.DrawItem(line);
	g_iWardenKeyAction[client][10] = WA_EXIT;
	g_iWardenKeyAction[client][0] = WA_EXIT;

	panel.Send(client, AJB_Warden_PanelHandler, MENU_TIME_FOREVER);
	delete panel;
}

public int AJB_Warden_PanelHandler(Menu menu, MenuAction action, int param1, int param2)
{
	// Panels are freed right after Send; nothing to delete on End. ESC/timeout → close.
	if (action != MenuAction_Select)
	{
		return 0;
	}

	int client = param1;
	if (!g_bModeActive || !AJB_IsWarden(client))
	{
		return 0;
	}

	int act = (param2 >= 0 && param2 <= 10) ? g_iWardenKeyAction[client][param2] : WA_NONE;

	// Exit / page navigation are allowed regardless of alive state.
	if (act == WA_EXIT)
	{
		return 0;
	}
	if (act == WA_PAGE_NEXT)
	{
		g_iWardenMenuPage[client] = 1;
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}
	if (act == WA_PAGE_PREV)
	{
		g_iWardenMenuPage[client] = 0;
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}

	// Resign + team-push toggle are policy switches — allowed even while dead.
	if (act == WA_RESIGN)
	{
		AJB_Warden_ShowResignConfirm(client);
		return 0;
	}
	if (act == WA_COLLISIONS)
	{
		AJB_Collisions_Toggle();
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}
	if (act == WA_FRIENDLYFIRE)
	{
		AJB_FF_Toggle();
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}

	// Everything below needs a living warden.
	if (!IsPlayerAlive(client))
	{
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}

	switch (act)
	{
		case WA_OPEN:
		{
			AJB_OpenCellsInternal(true);
			RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		}
		case WA_CLOSE:
		{
			AJB_CloseCellsInternal(true);
			RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		}
		case WA_MARKER:
		{
			AJB_Warden_PlaceMarker(client);
			RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		}
		case WA_GIVE_LR:
		{
			Call_StartForward(g_hFwdWardenGiveLR);
			Call_PushCell(client);
			Call_Finish();
		}
		case WA_VOTE_YESNO:
		{
			// Prompt the warden to type the question; the poll shows to living prisoners.
			AJB_Warden_StartVoteCompose(client, AJB_VOTE_MODE_YESNO);
		}
		case WA_VOTE_MULTI:
		{
			// Prompt for "question | opt1 | opt2 | ..."; the poll shows to living prisoners.
			AJB_Warden_StartVoteCompose(client, AJB_VOTE_MODE_MULTI);
		}
		case WA_MARK_REBEL:
		{
			if (g_cvWardenRebelControl == null || !g_cvWardenRebelControl.BoolValue)
			{
				RequestFrame(Frame_WardenMenu, GetClientUserId(client));
				return 0;
			}
			AJB_Warden_ShowRebelPick(client, true);
		}
		case WA_PARDON_REBEL:
		{
			if (g_cvWardenRebelControl == null || !g_cvWardenRebelControl.BoolValue)
			{
				RequestFrame(Frame_WardenMenu, GetClientUserId(client));
				return 0;
			}
			AJB_Warden_ShowRebelPick(client, false);
		}
		default:
		{
			// Header/unmapped key — just refresh.
			RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		}
	}

	return 0;
}

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
		if (markMode == g_bRebel[i])
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
		|| (markMode == g_bRebel[target]))
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
