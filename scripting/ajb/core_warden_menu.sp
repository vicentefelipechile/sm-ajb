// =========================================================================================================
// Configurable warden menu — configs/ajb/warden_menu.cfg
// =========================================================================================================
// The server owner lays out the warden menu in KeyValues. Each first-level key is a
// page (its name renders as the page header), each entry is "label" "command":
//
//   "WardenMenu"
//   {
//       "Primera Pagina"
//       {
//           "--- Celdas ---"       ""            // empty value = text line, costs no slot
//           "Abrir celdas"         "sm_ajb_open" // anything else = console command run as the warden
//       }
//   }
//
// Labels prefixed with "phrase:" are looked up in the translations file. A page may
// hold up to 9 numbered items (Panel keys 1-9); extra items are dropped with a log.
// Exit is always pinned to key 0/10. With more than one page a Prev/Next row is
// appended automatically (pages defining sm_ajb_menu_next/prev skip the auto entry).
// Missing/empty file falls back to the built-in two-page menu (same layout as the
// shipped default config).

#define AJB_WARDEN_MENU_FILE        "configs/ajb/warden_menu.cfg"
#define AJB_WARDEN_MENU_MAX_PAGES   8
#define AJB_WARDEN_MENU_MAX_ENTRIES 16
#define AJB_WARDEN_MENU_MAX_ITEMS   9
#define AJB_WARDEN_MENU_TITLE_LEN   64
#define AJB_WARDEN_MENU_ENTRY_LEN   64
#define AJB_WARDEN_MENU_CMD_LEN     96

char g_szWardenMenuPageTitle[AJB_WARDEN_MENU_MAX_PAGES][AJB_WARDEN_MENU_TITLE_LEN];
char g_szWardenMenuEntryLabel[AJB_WARDEN_MENU_MAX_PAGES][AJB_WARDEN_MENU_MAX_ENTRIES][AJB_WARDEN_MENU_ENTRY_LEN];
char g_szWardenMenuEntryCmd[AJB_WARDEN_MENU_MAX_PAGES][AJB_WARDEN_MENU_MAX_ENTRIES][AJB_WARDEN_MENU_CMD_LEN];
int g_iWardenMenuEntryCount[AJB_WARDEN_MENU_MAX_PAGES];
int g_iWardenMenuPageCount;

// key (1..9) → entry index in the currently shown page; -1 = unmapped; the negative
// sentinels below are the auto-appended page navigation. Rebuilt on every
// AJB_Warden_ShowMenu so config reloads can never desync a stale mapping.
#define AJB_WARDEN_KEY_AUTO_PREV  -2
#define AJB_WARDEN_KEY_AUTO_NEXT  -3
int g_iWardenKeyEntry[MAXPLAYERS + 1][11];

void AJB_WardenMenu_OnPluginStart()
{
	RegAdminCmd("sm_ajb_menu_reload", Command_MenuReload, ADMFLAG_CONFIG, "Reload configs/ajb/warden_menu.cfg.");
	RegConsoleCmd("sm_ajb_marker", Command_WardenMarker, "Warden/admin: place a 'come here' marker at the crosshair.");
	RegConsoleCmd("sm_ajb_collisions", Command_WardenCollisions, "Warden/admin: toggle teammate push.");
	RegConsoleCmd("sm_ajb_friendlyfire", Command_WardenFriendlyFire, "Warden/admin: toggle friendly fire.");
	RegConsoleCmd("sm_ajb_vote_yesno", Command_WardenVoteYesNo, "Warden: start a Yes/No vote.");
	RegConsoleCmd("sm_ajb_vote_multi", Command_WardenVoteMulti, "Warden: start a multiple-choice vote.");
	RegConsoleCmd("sm_ajb_warden_markrebel", Command_WardenMarkRebel, "Warden: mark a prisoner as rebel.");
	RegConsoleCmd("sm_ajb_warden_pardonrebel", Command_WardenPardonRebel, "Warden: pardon a rebel.");
	RegConsoleCmd("sm_ajb_menu_next", Command_MenuNext, "Warden: open the next warden menu page.");
	RegConsoleCmd("sm_ajb_menu_prev", Command_MenuPrev, "Warden: open the previous warden menu page.");

	AJB_WardenMenu_Load();
}

void AJB_WardenMenu_OnMapStart()
{
	// Cheap reload so owner edits apply without a manual command.
	AJB_WardenMenu_Load();
}

Action Command_MenuReload(int client, int args)
{
	AJB_WardenMenu_Load();
	ReplyToCommand(client, "[AJB] Warden menu reloaded (%d page(s)).", g_iWardenMenuPageCount);
	return Plugin_Handled;
}

void AJB_WardenMenu_Load()
{
	g_iWardenMenuPageCount = 0;

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), AJB_WARDEN_MENU_FILE);

	if (FileExists(path))
	{
		KeyValues kv = new KeyValues("WardenMenu");
		if (kv.ImportFromFile(path))
		{
			AJB_WardenMenu_LoadPages(kv);
			delete kv;

			if (g_iWardenMenuPageCount > 0)
			{
				LogMessage("[AJB] warden_menu.cfg: %d page(s).", g_iWardenMenuPageCount);
				return;
			}

			LogMessage("[AJB] %s has no pages — using built-in warden menu.", AJB_WARDEN_MENU_FILE);
		}
		else
		{
			LogError("[AJB] Failed to parse %s — using built-in warden menu.", path);
			delete kv;
		}
	}
	else
	{
		LogMessage("[AJB] %s missing — using built-in warden menu.", AJB_WARDEN_MENU_FILE);
	}

	AJB_WardenMenu_LoadBuiltin();
}

void AJB_WardenMenu_LoadPages(KeyValues kv)
{
	if (!kv.GotoFirstSubKey(false))
	{
		return;
	}

	do
	{
		if (g_iWardenMenuPageCount >= AJB_WARDEN_MENU_MAX_PAGES)
		{
			LogError("[AJB] warden_menu.cfg has more than %d pages — extra pages ignored.", AJB_WARDEN_MENU_MAX_PAGES);
			break;
		}

		int page = g_iWardenMenuPageCount;
		kv.GetSectionName(g_szWardenMenuPageTitle[page], AJB_WARDEN_MENU_TITLE_LEN);

		int entries = 0;
		int items = 0;
		if (kv.GotoFirstSubKey(false))
		{
			do
			{
				if (entries >= AJB_WARDEN_MENU_MAX_ENTRIES)
				{
					LogError("[AJB] warden_menu.cfg page \"%s\": more than %d entries — extra entries ignored.",
						g_szWardenMenuPageTitle[page], AJB_WARDEN_MENU_MAX_ENTRIES);
					break;
				}

				kv.GetSectionName(g_szWardenMenuEntryLabel[page][entries], AJB_WARDEN_MENU_ENTRY_LEN);
				kv.GetString(NULL_STRING, g_szWardenMenuEntryCmd[page][entries], AJB_WARDEN_MENU_CMD_LEN);
				if (g_szWardenMenuEntryCmd[page][entries][0] != '\0')
				{
					items++;
				}
				entries++;
			} while (kv.GotoNextKey(false));
			kv.GoBack();
		}

		if (items > AJB_WARDEN_MENU_MAX_ITEMS)
		{
			LogError("[AJB] warden_menu.cfg page \"%s\": %d numbered items (max %d) — extra items are not drawn.",
				g_szWardenMenuPageTitle[page], items, AJB_WARDEN_MENU_MAX_ITEMS);
		}

		g_iWardenMenuEntryCount[page] = entries;
		g_iWardenMenuPageCount++;
	} while (kv.GotoNextKey(false));
	kv.GoBack();
}

// =========================================================================================================
// Built-in fallback (missing/empty config): same layout as the shipped default config.
// =========================================================================================================

void AJB_WardenMenu_LoadBuiltin()
{
	g_iWardenMenuPageCount = 0;

	AJB_WardenMenu_BuiltinPage("phrase:Warden Menu Title Shortcuts");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Header Cells", "");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Menu Open Cells", "sm_ajb_open");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Menu Close Cells", "sm_ajb_close");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Header Tools", "");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Menu Marker", "sm_ajb_marker");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Menu Collisions Enable", "sm_ajb_collisions");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Menu FriendlyFire Enable", "sm_ajb_friendlyfire");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Header Manage", "");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Menu Resign", "sm_ajb_uw");
	AJB_WardenMenu_EndPage();

	AJB_WardenMenu_BuiltinPage("phrase:Warden Menu Title Events");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Header Events", "");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Menu Give LR", "sm_ajb_lr");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Menu Vote YesNo", "sm_ajb_vote_yesno");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Menu Vote Multi", "sm_ajb_vote_multi");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Header Rebels", "");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Menu Mark Rebel", "sm_ajb_warden_markrebel");
	AJB_WardenMenu_BuiltinEntry("phrase:Warden Menu Pardon Rebel", "sm_ajb_warden_pardonrebel");
	AJB_WardenMenu_EndPage();
}

void AJB_WardenMenu_BuiltinPage(const char[] title)
{
	strcopy(g_szWardenMenuPageTitle[g_iWardenMenuPageCount], AJB_WARDEN_MENU_TITLE_LEN, title);
	g_iWardenMenuEntryCount[g_iWardenMenuPageCount] = 0;
}

void AJB_WardenMenu_BuiltinEntry(const char[] label, const char[] cmd)
{
	int page = g_iWardenMenuPageCount;
	int entry = g_iWardenMenuEntryCount[page];
	strcopy(g_szWardenMenuEntryLabel[page][entry], AJB_WARDEN_MENU_ENTRY_LEN, label);
	strcopy(g_szWardenMenuEntryCmd[page][entry], AJB_WARDEN_MENU_CMD_LEN, cmd);
	g_iWardenMenuEntryCount[page]++;
}

void AJB_WardenMenu_EndPage()
{
	g_iWardenMenuPageCount++;
}

// =========================================================================================================
// Warden menu render
// =========================================================================================================

// TF2's radio menu drops non-numbered menu items entirely (RAWLINE) and forces disabled
// items to eat a number — so the paged hub is built as a Panel: DrawText() renders
// un-numbered headers/separators that cost no slot, DrawItem() renders the numbered
// actions. Panel handlers receive the raw key pressed (not an info string), so each key
// maps to the config entry drawn on it (g_iWardenKeyEntry).
void AJB_Warden_ShowMenu(int client)
{
	if (!AJB_IsValidClient(client) || !AJB_IsWarden(client))
	{
		return;
	}

	if (g_iWardenMenuPageCount <= 0)
	{
		AJB_WardenMenu_Load();
	}

	int page = g_iWardenMenuPage[client];
	if (page < 0 || page >= g_iWardenMenuPageCount)
	{
		page = 0;
		g_iWardenMenuPage[client] = 0;
	}

	// Fresh key map for this render.
	for (int k = 0; k <= 10; k++)
	{
		g_iWardenKeyEntry[client][k] = -1;
	}

	Panel panel = new Panel();

	// No panel title — the page header carries the structure on its own.
	AJB_Warden_PanelHeaderLabel(panel, client, g_szWardenMenuPageTitle[page]);

	char line[96];
	int key = 1;
	for (int e = 0; e < g_iWardenMenuEntryCount[page]; e++)
	{
		char cmd[AJB_WARDEN_MENU_CMD_LEN];
		strcopy(cmd, sizeof(cmd), g_szWardenMenuEntryCmd[page][e]);

		// Empty command = un-numbered text line, costs no slot.
		if (cmd[0] == '\0')
		{
			AJB_Warden_PanelText(panel, client, g_szWardenMenuEntryLabel[page][e]);
			continue;
		}

		// Feature toggled off → drop the item (mirrors the old built-in gating).
		if (AJB_Warden_MenuCommandGated(cmd))
		{
			continue;
		}

		// A page holds at most 9 numbered items (Panel keys 1..9).
		if (key > AJB_WARDEN_MENU_MAX_ITEMS)
		{
			continue;
		}

		AJB_Warden_PanelItemLabel(client, cmd, g_szWardenMenuEntryLabel[page][e], line, sizeof(line));
		panel.CurrentKey = key;
		panel.DrawItem(line);
		g_iWardenKeyEntry[client][key] = e;
		key++;
	}

	// Page navigation is menu chrome, not a warden function — with more than one page
	// a separator + Prev/Next row is appended automatically (translated). Pages that
	// already place the nav command themselves are skipped to avoid duplicates.
	if (g_iWardenMenuPageCount > 1)
	{
		bool wantPrev = page > 0;
		bool wantNext = page < g_iWardenMenuPageCount - 1;
		if (wantPrev || wantNext)
		{
			for (int e = 0; e < g_iWardenMenuEntryCount[page]; e++)
			{
				if (StrEqual(g_szWardenMenuEntryCmd[page][e], "sm_ajb_menu_prev"))
				{
					wantPrev = false;
				}
				if (StrEqual(g_szWardenMenuEntryCmd[page][e], "sm_ajb_menu_next"))
				{
					wantNext = false;
				}
			}

			// Nav consumes numbered slots like any item — a full page loses it.
			if ((wantPrev || wantNext) && key <= AJB_WARDEN_MENU_MAX_ITEMS)
			{
				panel.DrawText("──────────────");
			}
			if (wantPrev && key <= AJB_WARDEN_MENU_MAX_ITEMS)
			{
				Format(line, sizeof(line), "%T", "Warden Page Prev", client);
				panel.CurrentKey = key;
				panel.DrawItem(line);
				g_iWardenKeyEntry[client][key] = AJB_WARDEN_KEY_AUTO_PREV;
				key++;
			}
			if (wantNext && key <= AJB_WARDEN_MENU_MAX_ITEMS)
			{
				Format(line, sizeof(line), "%T", "Warden Page Next", client);
				panel.CurrentKey = key;
				panel.DrawItem(line);
				g_iWardenKeyEntry[client][key] = AJB_WARDEN_KEY_AUTO_NEXT;
				key++;
			}
		}
	}

	// Exit pinned to key 0 (slot 10), the TF2 convention. The handler maps both 0 and
	// 10 to exit since it may report either for the "0" key.
	Format(line, sizeof(line), "%T", "Warden Menu Exit", client);
	panel.CurrentKey = 10;
	panel.DrawItem(line);

	panel.Send(client, AJB_Warden_PanelHandler, MENU_TIME_FOREVER);
	delete panel;
}

// Section header rendered as "── <name> ──" on its own, un-numbered Panel line.
void AJB_Warden_PanelHeaderLabel(Panel panel, int client, const char[] label)
{
	char name[AJB_WARDEN_MENU_TITLE_LEN];
	AJB_Warden_ResolveLabel(client, label, name, sizeof(name));

	char line[96];
	Format(line, sizeof(line), "── %s ──", name);
	panel.DrawText(line);
}

// A plain un-numbered text line.
void AJB_Warden_PanelText(Panel panel, int client, const char[] label)
{
	char line[96];
	AJB_Warden_ResolveLabel(client, label, line, sizeof(line));
	panel.DrawText(line);
}

// "phrase:Name" labels translate; anything else is drawn verbatim.
void AJB_Warden_ResolveLabel(int client, const char[] label, char[] out, int maxlen)
{
	if (StrContains(label, "phrase:") == 0)
	{
		Format(out, maxlen, "%T", label[7], client);
	}
	else
	{
		strcopy(out, maxlen, label);
	}
}

// Item display text. The collision/FF toggles flip their label to reflect the current
// state (same behavior as the old built-in menu) — but only for phrase labels, so a
// literal label stays exactly as the owner wrote it.
void AJB_Warden_PanelItemLabel(int client, const char[] cmd, const char[] label, char[] out, int maxlen)
{
	if (StrContains(label, "phrase:") != 0)
	{
		strcopy(out, maxlen, label);
		return;
	}

	if (StrEqual(cmd, "sm_ajb_collisions"))
	{
		Format(out, maxlen, "%T", g_bTeamPush ? "Warden Menu Collisions Disable" : "Warden Menu Collisions Enable", client);
		return;
	}
	if (StrEqual(cmd, "sm_ajb_friendlyfire"))
	{
		Format(out, maxlen, "%T", g_bFriendlyFire ? "Warden Menu FriendlyFire Disable" : "Warden Menu FriendlyFire Enable", client);
		return;
	}

	Format(out, maxlen, "%T", label[7], client);
}

// =========================================================================================================
// Warden menu panel handler — commands run as the warden
// =========================================================================================================

// Item hidden when its feature ConVar is off (mirrors the old built-in menu gating).
bool AJB_Warden_MenuCommandGated(const char[] cmd)
{
	if (StrEqual(cmd, "sm_ajb_marker"))
	{
		return g_cvMarkerEnabled == null || !g_cvMarkerEnabled.BoolValue;
	}
	if (StrEqual(cmd, "sm_ajb_collisions"))
	{
		return g_cvCollisionsControl == null || !g_cvCollisionsControl.BoolValue;
	}
	if (StrEqual(cmd, "sm_ajb_friendlyfire"))
	{
		return g_cvFFControl == null || !g_cvFFControl.BoolValue;
	}
	if (StrEqual(cmd, "sm_ajb_vote_yesno") || StrEqual(cmd, "sm_ajb_vote_multi"))
	{
		return g_cvVoteEnabled == null || !g_cvVoteEnabled.BoolValue;
	}
	if (StrEqual(cmd, "sm_ajb_warden_markrebel") || StrEqual(cmd, "sm_ajb_warden_pardonrebel"))
	{
		return g_cvWardenRebelControl == null || !g_cvWardenRebelControl.BoolValue;
	}
	return false;
}

// Commands that own the screen flow (they open their own panel or change the page) —
// the warden menu must NOT reopen after them, or it would stomp their panel.
// (sm_ajb_lr is handled separately via the AJB_OnWardenGiveLR forward.)
bool AJB_Warden_MenuCommandOwnsMenu(const char[] cmd)
{
	return StrEqual(cmd, "sm_ajb_uw")
		|| StrEqual(cmd, "sm_ajb_vote_yesno")
		|| StrEqual(cmd, "sm_ajb_vote_multi")
		|| StrEqual(cmd, "sm_ajb_warden_markrebel")
		|| StrEqual(cmd, "sm_ajb_warden_pardonrebel")
		|| StrEqual(cmd, "sm_ajb_menu_next")
		|| StrEqual(cmd, "sm_ajb_menu_prev");
}

// Commands a dead warden may still run from the menu (policy toggles + navigation).
bool AJB_Warden_MenuCommandAllowedDead(const char[] cmd)
{
	return StrEqual(cmd, "sm_ajb_uw")
		|| StrEqual(cmd, "sm_ajb_collisions")
		|| StrEqual(cmd, "sm_ajb_friendlyfire")
		|| StrEqual(cmd, "sm_ajb_menu_next")
		|| StrEqual(cmd, "sm_ajb_menu_prev");
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

	// Exit pinned to key 0/10, the TF2 convention.
	int key = param2;
	if (key == 0 || key == 10)
	{
		return 0;
	}

	// Config may have been reloaded since the panel was drawn — validate the mapping.
	int page = g_iWardenMenuPage[client];
	int entry = (key >= 1 && key <= 9) ? g_iWardenKeyEntry[client][key] : -1;

	// Auto page nav (drawn by the menu, not the config) — allowed even while dead.
	if (entry == AJB_WARDEN_KEY_AUTO_PREV)
	{
		g_iWardenMenuPage[client] = (page > 0) ? page - 1 : 0;
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}
	if (entry == AJB_WARDEN_KEY_AUTO_NEXT)
	{
		int next = page + 1;
		g_iWardenMenuPage[client] = (next >= g_iWardenMenuPageCount) ? g_iWardenMenuPageCount - 1 : next;
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}

	if (entry < 0 || page < 0 || page >= g_iWardenMenuPageCount || entry >= g_iWardenMenuEntryCount[page])
	{
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}

	char cmd[AJB_WARDEN_MENU_CMD_LEN];
	strcopy(cmd, sizeof(cmd), g_szWardenMenuEntryCmd[page][entry]);
	if (cmd[0] == '\0')
	{
		// Text line pressed — just refresh.
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}

	// Everything except policy toggles/navigation needs a living warden.
	if (!IsPlayerAlive(client) && !AJB_Warden_MenuCommandAllowedDead(cmd))
	{
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
		return 0;
	}

	// LR grant goes through the AJB_OnWardenGiveLR forward (public API, handled by the
	// lastrequest module) — the console command exists too, but the forward keeps the
	// module flow single-sourced. It owns the screen, so no menu reopen here.
	if (StrEqual(cmd, "sm_ajb_lr"))
	{
		Call_StartForward(g_hFwdWardenGiveLR);
		Call_PushCell(client);
		Call_Finish();
		return 0;
	}

	// Run the command as the warden; menu-opening commands keep the screen to themselves.
	FakeClientCommandEx(client, cmd);
	if (!AJB_Warden_MenuCommandOwnsMenu(cmd))
	{
		RequestFrame(Frame_WardenMenu, GetClientUserId(client));
	}

	return 0;
}

// =========================================================================================================
// Standalone warden tool commands (bindable, also usable from the config menu)
// =========================================================================================================

// Warden-or-admin gate for the tool commands (mirrors AJB_CanControlCells).
bool AJB_Warden_OrAdmin(int client)
{
	if (AJB_IsWarden(client))
	{
		return true;
	}
	return CheckCommandAccess(client, "sm_ajb_warden_tools", ADMFLAG_GENERIC);
}

Action Command_WardenMarker(int client, int args)
{
	if (client == 0)
	{
		AJB_Reply(client, "Ingame Only");
		return Plugin_Handled;
	}
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}
	if (!AJB_Warden_OrAdmin(client))
	{
		AJB_Reply(client, "Warden Not You");
		return Plugin_Handled;
	}
	if (!IsPlayerAlive(client))
	{
		AJB_Reply(client, "Warden Alive Only");
		return Plugin_Handled;
	}

	AJB_Warden_PlaceMarker(client);
	return Plugin_Handled;
}

Action Command_WardenCollisions(int client, int args)
{
	if (client == 0)
	{
		AJB_Reply(client, "Ingame Only");
		return Plugin_Handled;
	}
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}
	if (!AJB_Warden_OrAdmin(client))
	{
		AJB_Reply(client, "Warden Not You");
		return Plugin_Handled;
	}

	// Announces the new state to everyone itself.
	AJB_Collisions_Toggle();
	return Plugin_Handled;
}

Action Command_WardenFriendlyFire(int client, int args)
{
	if (client == 0)
	{
		AJB_Reply(client, "Ingame Only");
		return Plugin_Handled;
	}
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}
	if (!AJB_Warden_OrAdmin(client))
	{
		AJB_Reply(client, "Warden Not You");
		return Plugin_Handled;
	}

	// Announces the new state to everyone itself.
	AJB_FF_Toggle();
	return Plugin_Handled;
}

Action Command_WardenVoteYesNo(int client, int args)
{
	if (client == 0)
	{
		AJB_Reply(client, "Ingame Only");
		return Plugin_Handled;
	}
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}
	if (!AJB_IsWarden(client))
	{
		AJB_Reply(client, "Warden Not You");
		return Plugin_Handled;
	}

	AJB_Warden_StartVoteCompose(client, AJB_VOTE_MODE_YESNO);
	return Plugin_Handled;
}

Action Command_WardenVoteMulti(int client, int args)
{
	if (client == 0)
	{
		AJB_Reply(client, "Ingame Only");
		return Plugin_Handled;
	}
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}
	if (!AJB_IsWarden(client))
	{
		AJB_Reply(client, "Warden Not You");
		return Plugin_Handled;
	}

	AJB_Warden_StartVoteCompose(client, AJB_VOTE_MODE_MULTI);
	return Plugin_Handled;
}

Action Command_WardenMarkRebel(int client, int args)
{
	if (client == 0)
	{
		AJB_Reply(client, "Ingame Only");
		return Plugin_Handled;
	}
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}
	if (!AJB_IsWarden(client))
	{
		AJB_Reply(client, "Warden Not You");
		return Plugin_Handled;
	}
	if (!IsPlayerAlive(client))
	{
		AJB_Reply(client, "Warden Alive Only");
		return Plugin_Handled;
	}

	AJB_Warden_ShowRebelPick(client, true);
	return Plugin_Handled;
}

Action Command_WardenPardonRebel(int client, int args)
{
	if (client == 0)
	{
		AJB_Reply(client, "Ingame Only");
		return Plugin_Handled;
	}
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}
	if (!AJB_IsWarden(client))
	{
		AJB_Reply(client, "Warden Not You");
		return Plugin_Handled;
	}
	if (!IsPlayerAlive(client))
	{
		AJB_Reply(client, "Warden Alive Only");
		return Plugin_Handled;
	}

	AJB_Warden_ShowRebelPick(client, false);
	return Plugin_Handled;
}

Action Command_MenuNext(int client, int args)
{
	if (client == 0)
	{
		AJB_Reply(client, "Ingame Only");
		return Plugin_Handled;
	}
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}
	if (!AJB_IsWarden(client))
	{
		AJB_Reply(client, "Warden Not You");
		return Plugin_Handled;
	}

	int page = g_iWardenMenuPage[client] + 1;
	if (page >= g_iWardenMenuPageCount)
	{
		page = g_iWardenMenuPageCount - 1;
	}
	g_iWardenMenuPage[client] = page;
	RequestFrame(Frame_WardenMenu, GetClientUserId(client));
	return Plugin_Handled;
}

Action Command_MenuPrev(int client, int args)
{
	if (client == 0)
	{
		AJB_Reply(client, "Ingame Only");
		return Plugin_Handled;
	}
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}
	if (!AJB_IsWarden(client))
	{
		AJB_Reply(client, "Warden Not You");
		return Plugin_Handled;
	}

	int page = g_iWardenMenuPage[client] - 1;
	if (page < 0)
	{
		page = 0;
	}
	g_iWardenMenuPage[client] = page;
	RequestFrame(Frame_WardenMenu, GetClientUserId(client));
	return Plugin_Handled;
}
