// =========================================================================================================
// Last Request - Freeday
// =========================================================================================================

void AJB_LR_DoFreedayMe(int prisoner)
{
	// Next round personal freeday (core pending flag).
	AJB_SetPlayerFreeday(prisoner, true);
	AJB_LR_QueueWish(prisoner, LRWish_FreedayMe, "LR Chose Freeday Me");
}

// Build ordered list: chooser first, then every other living prisoner.
int AJB_LR_CollectFreedayTargets(int prisoner, int[] list, int maxList)
{
	int n = 0;
	if (prisoner > 0 && IsClientInGame(prisoner) && IsPlayerAlive(prisoner) && AJB_IsPrisoner(prisoner))
	{
		list[n++] = prisoner;
	}

	for (int i = 1; i <= MaxClients && n < maxList; i++)
	{
		if (i == prisoner || !IsClientInGame(i) || !IsPlayerAlive(i) || !AJB_IsPrisoner(i))
		{
			continue;
		}
		list[n++] = i;
	}
	return n;
}

void AJB_LR_ShowFreedayOthersMenu(int prisoner)
{
	int list[MAXPLAYERS + 1];
	int total = AJB_LR_CollectFreedayTargets(prisoner, list, sizeof(list));
	if (total < 1)
	{
		AJB_Chat(prisoner, "LR Freeday Others None");
		AJB_LR_ShowWishMenu(prisoner);
		return;
	}

	int pages = (total + LR_FREEDAY_PAGE_SIZE - 1) / LR_FREEDAY_PAGE_SIZE;
	if (pages < 1)
	{
		pages = 1;
	}
	if (g_iFreedayMenuPage >= pages)
	{
		g_iFreedayMenuPage = pages - 1;
	}
	if (g_iFreedayMenuPage < 0)
	{
		g_iFreedayMenuPage = 0;
	}

	// Panel: DrawText = ---- without a number (Radio Menu cannot do that).
	// Keys: 1-6 players | 7 Confirm | 8 Prev | 9 Next
	Panel panel = new Panel();

	char title[64];
	Format(title, sizeof(title), "%T", "LR Freeday Others Title", prisoner, g_iFreedayPickCount, LR_FREEDAY_OTHERS_MAX);
	panel.SetTitle(title);

	char sep[32];
	Format(sep, sizeof(sep), "%T", "Menu Separator", prisoner);
	panel.DrawText(sep);

	int start = g_iFreedayMenuPage * LR_FREEDAY_PAGE_SIZE;
	for (int slot = 0; slot < LR_FREEDAY_PAGE_SIZE; slot++)
	{
		g_iFreedaySlotUserId[slot] = 0;
		int idx = start + slot;
		if (idx < total)
		{
			int target = list[idx];
			g_iFreedaySlotUserId[slot] = GetClientUserId(target);

			char name[72];
			GetClientName(target, name, sizeof(name));
			if (g_bPickedFreeday[target])
			{
				Format(name, sizeof(name), "[*] %s", name);
			}
			panel.DrawItem(name);
		}
		else
		{
			panel.DrawItem(" ", ITEMDRAW_SPACER);
		}
	}

	panel.DrawText(sep);

	char line[72];
	Format(line, sizeof(line), "%T", "LR Freeday Others Confirm", prisoner);
	panel.DrawItem(line);

	int prevStyle = (g_iFreedayMenuPage <= 0) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;
	int nextStyle = (g_iFreedayMenuPage >= pages - 1) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;

	Format(line, sizeof(line), "%T", "LR Freeday Others Prev", prisoner);
	panel.DrawItem(line, prevStyle);
	Format(line, sizeof(line), "%T", "LR Freeday Others Next", prisoner);
	panel.DrawItem(line, nextStyle);

	g_bMenuOpen = true;
	panel.Send(prisoner, PanelHandler_FreedayOthers, RoundToFloor(g_cvMenuTime.FloatValue));
	delete panel;
}

public int PanelHandler_FreedayOthers(Menu menu, MenuAction action, int param1, int param2)
{
	// Panel callback: param2 is the DrawItem key (DrawText lines do not consume keys).
	if (action != MenuAction_Select)
	{
		return 0;
	}

	int client = param1;
	if (!AJB_LR_IsMenuAllowed(client))
	{
		return 0;
	}

	// 1..6 = player row, 7 = confirm, 8 = prev, 9 = next
	if (param2 == 8)
	{
		if (g_iFreedayMenuPage > 0)
		{
			g_iFreedayMenuPage--;
		}
		AJB_LR_ShowFreedayOthersMenu(client);
		return 0;
	}

	if (param2 == 9)
	{
		g_iFreedayMenuPage++;
		AJB_LR_ShowFreedayOthersMenu(client);
		return 0;
	}

	if (param2 == 7)
	{
		if (g_iFreedayPickCount < 1)
		{
			AJB_Chat(client, "LR Freeday Others Need One");
			AJB_LR_ShowFreedayOthersMenu(client);
			return 0;
		}

		AJB_LR_ShowFreedayReviewPanel(client);
		return 0;
	}

	if (param2 < 1 || param2 > LR_FREEDAY_PAGE_SIZE)
	{
		return 0;
	}

	int target = GetClientOfUserId(g_iFreedaySlotUserId[param2 - 1]);
	if (target < 1 || !IsClientInGame(target) || !IsPlayerAlive(target) || !AJB_IsPrisoner(target))
	{
		AJB_LR_ShowFreedayOthersMenu(client);
		return 0;
	}

	if (g_bPickedFreeday[target])
	{
		g_bPickedFreeday[target] = false;
		g_iFreedayPickCount--;
		if (g_iFreedayPickCount < 0)
		{
			g_iFreedayPickCount = 0;
		}
	}
	else
	{
		if (g_iFreedayPickCount >= LR_FREEDAY_OTHERS_MAX)
		{
			AJB_Chat(client, "LR Freeday Others Cap");
		}
		else
		{
			g_bPickedFreeday[target] = true;
			g_iFreedayPickCount++;
		}
	}

	AJB_LR_ShowFreedayOthersMenu(client);
	return 0;
}

// Review selected names before locking the wish (requires >=1 pick).
void AJB_LR_ShowFreedayReviewPanel(int prisoner)
{
	Panel panel = new Panel();

	char title[72];
	Format(title, sizeof(title), "%T", "LR Freeday Others Review Title", prisoner, g_iFreedayPickCount);
	panel.SetTitle(title);

	char sep[32];
	Format(sep, sizeof(sep), "%T", "Menu Separator", prisoner);
	panel.DrawText(sep);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bPickedFreeday[i] || !IsClientInGame(i))
		{
			continue;
		}

		char name[64];
		GetClientName(i, name, sizeof(name));
		panel.DrawText(name);
	}

	panel.DrawText(sep);

	char line[72];
	Format(line, sizeof(line), "%T", "LR Freeday Others Review Yes", prisoner);
	panel.DrawItem(line);
	Format(line, sizeof(line), "%T", "LR Freeday Others Review No", prisoner);
	panel.DrawItem(line);

	g_bMenuOpen = true;
	panel.Send(prisoner, PanelHandler_FreedayReview, RoundToFloor(g_cvMenuTime.FloatValue));
	delete panel;
}

public int PanelHandler_FreedayReview(Menu menu, MenuAction action, int param1, int param2)
{
	if (action != MenuAction_Select)
	{
		return 0;
	}

	int client = param1;
	if (!AJB_LR_IsMenuAllowed(client))
	{
		return 0;
	}

	// 1 = yes (lock wish), 2 = no (back to picker)
	if (param2 == 2)
	{
		AJB_LR_ShowFreedayOthersMenu(client);
		return 0;
	}

	if (param2 != 1)
	{
		return 0;
	}

	if (g_iFreedayPickCount < 1)
	{
		AJB_Chat(client, "LR Freeday Others Need One");
		AJB_LR_ShowFreedayOthersMenu(client);
		return 0;
	}

	g_bMenuOpen = false;
	int given = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bPickedFreeday[i] && IsClientInGame(i) && AJB_IsPrisoner(i))
		{
			AJB_SetPlayerFreeday(i, true);
			given++;
		}
		g_bPickedFreeday[i] = false;
	}
	g_iFreedayPickCount = 0;
	g_iFreedayMenuPage = 0;
	AJB_LR_ChatAllFreedayOthers(client, given);
	AJB_LR_ClearPendingWish();
	g_PendingWish = LRWish_FreedayOthers;
	AJB_LR_RememberChooser(client);
	AJB_LR_CloseMenuState();
	AJB_LR_MarkWishChosen();
	return 0;
}

void AJB_LR_DoFreedayAll(int prisoner)
{
	// NEXT round: cosmetic global freeday.
	AJB_LR_QueueWish(prisoner, LRWish_FreedayAll, "LR Chose Freeday All");
}

