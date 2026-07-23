// =========================================================================================================
// Warden votes — Yes/No and multiple-choice polls shown to living prisoners (RED) by default.
// The warden composes the question (and options) via chat; the poll itself uses SourceMod's
// native vote panel (Menu.DisplayVote), so only one vote runs server-wide at a time.
//
// Audience: sm_ajb_warden_vote_audience — 0 = living prisoners only, 1 = all living players.
// Players who die DURING a vote simply keep whatever they already cast; that is fine by design.
// =========================================================================================================

#define AJB_VOTE_MODE_NONE     0
#define AJB_VOTE_MODE_YESNO    1
#define AJB_VOTE_MODE_MULTI    2

#define AJB_VOTE_MIN_OPTIONS   2
#define AJB_VOTE_MAX_OPTIONS   5
#define AJB_VOTE_OPTION_LEN    128
#define AJB_VOTE_COMPOSE_TIME  30.0   // seconds the warden has to type the question before we give up

ConVar g_cvVoteEnabled;
ConVar g_cvVoteTime;
ConVar g_cvVoteAudience;

int g_iVoteComposer;      // client currently typing a vote question (0 = none)
int g_iVoteComposeMode;   // AJB_VOTE_MODE_*
Handle g_hVoteComposeTimer;

void AJB_Votes_OnPluginStart()
{
	g_cvVoteEnabled = CreateConVar(
		"sm_ajb_warden_vote",
		"1",
		"1 = warden can start Yes/No and multiple-choice votes from the menu.",
		_, true, 0.0, true, 1.0);

	g_cvVoteTime = CreateConVar(
		"sm_ajb_warden_vote_time",
		"20.0",
		"How long a warden vote panel stays open, in seconds.",
		_, true, 5.0, true, 60.0);

	g_cvVoteAudience = CreateConVar(
		"sm_ajb_warden_vote_audience",
		"0",
		"Who sees warden votes: 0 = living prisoners (RED) only, 1 = all living players.",
		_, true, 0.0, true, 1.0);

	// One shared listener catches the warden's next chat line while composing.
	AddCommandListener(Listener_WardenVoteSay, "say");
	AddCommandListener(Listener_WardenVoteSay, "say_team");
}

// Drop any half-composed vote (map change, warden resign/disconnect, round end).
// Does NOT cancel a poll already handed to the engine — that finishes on its own.
void AJB_Votes_Reset()
{
	g_iVoteComposer = 0;
	g_iVoteComposeMode = AJB_VOTE_MODE_NONE;

	if (g_hVoteComposeTimer != null)
	{
		delete g_hVoteComposeTimer;
		g_hVoteComposeTimer = null;
	}
}

// ---------------------------------------------------------------------------------------------------------
// Menu entry (page 1) → ask the warden to type the question in chat.
// ---------------------------------------------------------------------------------------------------------

void AJB_Warden_StartVoteCompose(int client, int mode)
{
	if (g_cvVoteEnabled == null || !g_cvVoteEnabled.BoolValue)
	{
		AJB_Reply(client, "Warden Vote Disabled");
		return;
	}

	if (!AJB_IsValidClient(client, true) || !AJB_IsWarden(client))
	{
		return;
	}

	// One SourceMod vote at a time, and one composer at a time.
	if (IsVoteInProgress() || g_iVoteComposer > 0)
	{
		AJB_Reply(client, "Warden Vote In Progress");
		return;
	}

	// No point opening a poll nobody can see.
	int clients[MAXPLAYERS];
	if (AJB_Votes_BuildAudience(clients, sizeof(clients)) < 1)
	{
		AJB_Reply(client, "Warden Vote No Audience");
		return;
	}

	g_iVoteComposer = client;
	g_iVoteComposeMode = mode;

	if (g_hVoteComposeTimer != null)
	{
		delete g_hVoteComposeTimer;
	}
	g_hVoteComposeTimer = CreateTimer(AJB_VOTE_COMPOSE_TIME, Timer_VoteComposeTimeout, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

	AJB_Reply(client, mode == AJB_VOTE_MODE_YESNO ? "Warden Vote Prompt YesNo" : "Warden Vote Prompt Multi");
}

Action Timer_VoteComposeTimeout(Handle timer, int userid)
{
	g_hVoteComposeTimer = null;

	int client = GetClientOfUserId(userid);
	if (g_iVoteComposer > 0 && client == g_iVoteComposer)
	{
		g_iVoteComposer = 0;
		g_iVoteComposeMode = AJB_VOTE_MODE_NONE;
		if (client > 0)
		{
			AJB_Reply(client, "Warden Vote Timeout");
		}
	}
	return Plugin_Stop;
}

// ---------------------------------------------------------------------------------------------------------
// Capture the composing warden's chat line.
// ---------------------------------------------------------------------------------------------------------

Action Listener_WardenVoteSay(int client, const char[] command, int argc)
{
	if (g_iVoteComposer <= 0 || client != g_iVoteComposer)
	{
		return Plugin_Continue;
	}

	// Warden must still be a living warden to finalize; otherwise drop the compose state.
	if (!g_bModeActive || !AJB_IsWarden(client) || !IsPlayerAlive(client))
	{
		AJB_Votes_Reset();
		return Plugin_Continue;
	}

	char text[192];
	GetCmdArgString(text, sizeof(text));
	StripQuotes(text);
	TrimString(text);

	if (text[0] == '\0')
	{
		return Plugin_Continue;   // empty line — keep waiting, let it through
	}

	// Explicit escape hatch.
	if (StrEqual(text, "cancel", false) || StrEqual(text, "!cancel", false))
	{
		AJB_Votes_Reset();
		AJB_Reply(client, "Warden Vote Cancelled");
		return Plugin_Handled;
	}

	// Real chat commands (leading /) pass through; stay in compose mode.
	if (text[0] == '/')
	{
		return Plugin_Continue;
	}

	if (g_iVoteComposeMode == AJB_VOTE_MODE_YESNO)
	{
		AJB_Votes_Reset();
		AJB_Votes_LaunchYesNo(client, text);
		return Plugin_Handled;
	}

	// Multiple choice: "question | option1 | option2 | ..." (2..5 options).
	char parts[AJB_VOTE_MAX_OPTIONS + 1][AJB_VOTE_OPTION_LEN];
	int n = ExplodeString(text, "|", parts, sizeof(parts), sizeof(parts[]));
	for (int i = 0; i < n; i++)
	{
		TrimString(parts[i]);
	}

	if (n < 1 || parts[0][0] == '\0')
	{
		AJB_Reply(client, "Warden Vote Multi Need Options");
		return Plugin_Handled;   // keep composing so the warden can retype
	}

	char options[AJB_VOTE_MAX_OPTIONS][AJB_VOTE_OPTION_LEN];
	int optCount = 0;
	for (int i = 1; i < n && optCount < AJB_VOTE_MAX_OPTIONS; i++)
	{
		if (parts[i][0] == '\0')
		{
			continue;
		}
		strcopy(options[optCount], AJB_VOTE_OPTION_LEN, parts[i]);
		optCount++;
	}

	if (optCount < AJB_VOTE_MIN_OPTIONS)
	{
		AJB_Reply(client, "Warden Vote Multi Need Options");
		return Plugin_Handled;   // keep composing
	}

	AJB_Votes_Reset();
	AJB_Votes_Launch(client, parts[0], options, optCount);
	return Plugin_Handled;
}

// ---------------------------------------------------------------------------------------------------------
// Launching the native vote panel.
// ---------------------------------------------------------------------------------------------------------

void AJB_Votes_LaunchYesNo(int warden, const char[] question)
{
	// Vote panels are a single shared menu, so option labels use the server language.
	char options[2][AJB_VOTE_OPTION_LEN];
	Format(options[0], AJB_VOTE_OPTION_LEN, "%T", "Warden Vote Yes", LANG_SERVER);
	Format(options[1], AJB_VOTE_OPTION_LEN, "%T", "Warden Vote No", LANG_SERVER);

	AJB_Votes_Launch(warden, question, options, 2);
}

void AJB_Votes_Launch(int warden, const char[] question, const char[][] options, int optCount)
{
	int clients[MAXPLAYERS];
	int total = AJB_Votes_BuildAudience(clients, sizeof(clients));
	if (total < 1)
	{
		AJB_Reply(warden, "Warden Vote No Audience");
		return;
	}

	// Re-check right before display: another vote may have started while composing.
	if (IsVoteInProgress())
	{
		AJB_Reply(warden, "Warden Vote In Progress");
		return;
	}

	Menu menu = new Menu(MenuHandler_WardenVote, MENU_ACTIONS_ALL);
	menu.SetTitle("%s", question);

	for (int i = 0; i < optCount; i++)
	{
		char info[8];
		IntToString(i, info, sizeof(info));
		menu.AddItem(info, options[i]);
	}

	menu.ExitButton = false;

	int time = RoundToNearest(g_cvVoteTime.FloatValue);
	if (time < 5)
	{
		time = 5;
	}

	menu.DisplayVote(clients, total, time);
	AJB_Votes_AnnounceStart(warden, question);
}

// Fill clients[] with the eligible audience; returns how many.
int AJB_Votes_BuildAudience(int[] clients, int maxClients)
{
	bool everyone = (g_cvVoteAudience != null && g_cvVoteAudience.IntValue == 1);

	int count = 0;
	for (int i = 1; i <= MaxClients && count < maxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		if (!everyone && !AJB_ClientIsPrisoner(i))
		{
			continue;
		}

		clients[count++] = i;
	}
	return count;
}

public int MenuHandler_WardenVote(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_VoteCancel:
		{
			// param1 == VoteCancel_NoVotes means the panel closed with nobody voting.
			if (param1 == VoteCancel_NoVotes)
			{
				AJB_ChatAll("Warden Vote No Result");
			}
		}
		case MenuAction_VoteEnd:
		{
			char display[AJB_VOTE_OPTION_LEN];
			char info[8];
			menu.GetItem(param1, info, sizeof(info), _, display, sizeof(display));

			int votes, totalVotes;
			GetMenuVoteInfo(param2, votes, totalVotes);

			AJB_Votes_AnnounceResult(display, votes, totalVotes);
		}
	}
	return 0;
}

// ---------------------------------------------------------------------------------------------------------
// Announcements (chat, to everyone).
// ---------------------------------------------------------------------------------------------------------

void AJB_Votes_AnnounceStart(int warden, const char[] question)
{
	char name[MAX_NAME_LENGTH];
	GetClientName(warden, name, sizeof(name));

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", "Warden Vote Started", i, prefix, name, question);
	}
}

void AJB_Votes_AnnounceResult(const char[] winner, int votes, int total)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", "Warden Vote Result", i, prefix, winner, votes, total);
	}
}
