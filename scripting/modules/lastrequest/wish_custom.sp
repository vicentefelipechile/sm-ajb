// =========================================================================================================
// Last Request - Custom
// =========================================================================================================

void AJB_LR_StartCustom(int prisoner)
{
	g_bAwaitingCustom = true;
	g_bMenuOpen = false;
	AJB_Chat(prisoner, "LR Custom Prompt");
	AJB_LR_ChatAll1N("LR Custom Waiting", prisoner);

	// Same countdown + 15s warning while waiting for chat.
	AJB_LR_StartMenuTimers(prisoner);
	// Replace timeout with custom-specific handler (warn timer already started).
	if (g_hMenuTimer != null)
	{
		delete g_hMenuTimer;
		g_hMenuTimer = null;
	}
	g_hMenuTimer = CreateTimer(g_cvMenuTime.FloatValue + 0.5, Timer_CustomTimeout, GetClientUserId(prisoner), TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_CustomTimeout(Handle timer, int userid)
{
	g_hMenuTimer = null;
	if (!g_bAwaitingCustom)
	{
		return Plugin_Stop;
	}

	g_bAwaitingCustom = false;
	int client = GetClientOfUserId(userid);
	if (client > 0)
	{
		AJB_LR_ChatAll1N("LR Timeout", client);
	}
	AJB_LR_Cleanup(false);
	return Plugin_Stop;
}

Action Listener_Say(int client, const char[] command, int argc)
{
	// Admin self-pick may type custom text while dead / off RED.
	if (!g_bAwaitingCustom || client < 1 || !AJB_LR_IsMenuAllowed(client))
	{
		return Plugin_Continue;
	}

	char text[192];
	GetCmdArgString(text, sizeof(text));
	StripQuotes(text);
	TrimString(text);

	if (text[0] == '\0' || text[0] == '/')
	{
		return Plugin_Continue;
	}

	g_bAwaitingCustom = false;
	AJB_LR_KillMenuTimer();

	// Custom text is announced now and again next round (warden can prepare).
	AJB_LR_ClearPendingWish();
	g_PendingWish = LRWish_Custom;
	strcopy(g_sPendingCustom, sizeof(g_sPendingCustom), text);
	AJB_LR_RememberChooser(client);
	AJB_LR_ChatAllCustom(client, text);
	AJB_LR_CloseMenuState();
	AJB_LR_MarkWishChosen();
	return Plugin_Handled;
}

