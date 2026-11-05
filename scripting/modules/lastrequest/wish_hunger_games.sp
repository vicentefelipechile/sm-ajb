// =========================================================================================================
// Last Request - Hunger Games
// =========================================================================================================

void AJB_LR_HG_OnPlayerDeath(int victim)
{
	if (!g_bHungerGames || g_bHGEnding)
	{
		return;
	}

	if (victim > 0 && victim <= MaxClients && g_bHGOriginalBlu[victim])
	{
		RequestFrame(Frame_HGRestoreBluTeam, GetClientUserId(victim));
	}

	if (!g_bHGCheckQueued)
	{
		g_bHGCheckQueued = true;
		RequestFrame(Frame_HGCheckWinner);
	}
}

void Frame_HGRestoreBluTeam(int userid)
{
	AJB_LR_RestoreBluOriginal(userid, g_bHGOriginalBlu);
}

// =========================================================================================================
// Hunger Games - config menu (class + weapons) then queue for next live round
// =========================================================================================================

void AJB_LR_StartHungerGamesConfig(int prisoner)
{
	// Defaults: any class, full loadout. Chooser can change before confirm.
	g_bHGDraftMelee = false;
	g_bHGDraftClassRandom = false;
	g_HGDraftClass = TFClass_Unknown;
	g_bMenuOpen = true;
	AJB_LR_ShowHungerGamesMenu(prisoner);
	AJB_LR_StartMenuTimers(prisoner);
}

void AJB_LR_ShowHungerGamesMenu(int prisoner)
{
	if (prisoner < 1 || !IsClientInGame(prisoner))
	{
		return;
	}

	Menu menu = new Menu(MenuHandler_HungerGames);
	char title[64];
	char line[96];
	char classLabel[32];
	AJB_LR_HG_ClassOptionLabel(prisoner, classLabel, sizeof(classLabel));

	Format(title, sizeof(title), "%T", "LR HG Menu Title", prisoner);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", "LR HG Opt Class", prisoner, classLabel);
	menu.AddItem("class", line);

	Format(line, sizeof(line), "%T",
		g_bHGDraftMelee ? "LR HG Opt Melee On" : "LR HG Opt Melee Off", prisoner);
	menu.AddItem("melee", line);

	Format(line, sizeof(line), "%T", "LR HG Opt Confirm", prisoner);
	menu.AddItem("confirm", line);

	Format(line, sizeof(line), "%T", "LR HG Opt Back", prisoner);
	menu.AddItem("back", line);

	menu.ExitButton = false;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));
}

void AJB_LR_HG_ClassOptionLabel(int client, char[] buffer, int maxlen)
{
	if (g_bHGDraftClassRandom)
	{
		Format(buffer, maxlen, "%T", "LR HG Menu Class Random", client);
		return;
	}

	if (g_HGDraftClass == TFClass_Unknown)
	{
		Format(buffer, maxlen, "%T", "LR HG Menu Class Any", client);
		return;
	}

	char name[32];
	AJB_TFClassName(g_HGDraftClass, name, sizeof(name));
	strcopy(buffer, maxlen, name);
}

public int MenuHandler_HungerGames(Menu menu, MenuAction action, int param1, int param2)
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
	if (!AJB_LR_IsMenuAllowed(client))
	{
		return 0;
	}

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "class"))
	{
		AJB_LR_ShowHungerGamesClassMenu(client);
		return 0;
	}

	if (StrEqual(info, "melee"))
	{
		g_bHGDraftMelee = !g_bHGDraftMelee;
		AJB_LR_ShowHungerGamesMenu(client);
		return 0;
	}

	if (StrEqual(info, "back"))
	{
		AJB_LR_ShowWishMenu(client);
		return 0;
	}

	if (StrEqual(info, "confirm"))
	{
		AJB_LR_KillMenuTimer();
		g_bMenuOpen = false;

		AJB_LR_ClearPendingWish();
		g_PendingWish = LRWish_HungerGames;
		g_PendingHGMeleeOnly = g_bHGDraftMelee;
		g_PendingHGClassRandom = g_bHGDraftClassRandom;
		g_PendingHGClass = g_HGDraftClass;
		AJB_LR_RememberChooser(client);
		AJB_LR_ChatAllHungerGamesChose(client, g_bHGDraftMelee, g_bHGDraftClassRandom, g_HGDraftClass);
		AJB_LR_CloseMenuState();
		AJB_LR_MarkWishChosen();
	}

	return 0;
}

void AJB_LR_ShowHungerGamesClassMenu(int prisoner)
{
	Menu menu = new Menu(MenuHandler_HungerGamesClass);
	char title[64];
	char line[64];
	Format(title, sizeof(title), "%T", "LR HG Class Title", prisoner);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", "LR HG Menu Class Any", prisoner);
	menu.AddItem("any", line);
	Format(line, sizeof(line), "%T", "LR HG Menu Class Random", prisoner);
	menu.AddItem("random", line);

	static const TFClassType kClasses[] = {
		TFClass_Scout, TFClass_Soldier, TFClass_Pyro, TFClass_DemoMan,
		TFClass_Heavy, TFClass_Engineer, TFClass_Medic, TFClass_Sniper, TFClass_Spy
	};

	for (int i = 0; i < sizeof(kClasses); i++)
	{
		char info[8];
		IntToString(view_as<int>(kClasses[i]), info, sizeof(info));
		AJB_TFClassName(kClasses[i], line, sizeof(line));
		menu.AddItem(info, line);
	}

	menu.ExitButton = false;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));
}

public int MenuHandler_HungerGamesClass(Menu menu, MenuAction action, int param1, int param2)
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
	if (!AJB_LR_IsMenuAllowed(client))
	{
		return 0;
	}

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "any"))
	{
		g_bHGDraftClassRandom = false;
		g_HGDraftClass = TFClass_Unknown;
	}
	else if (StrEqual(info, "random"))
	{
		g_bHGDraftClassRandom = true;
		g_HGDraftClass = TFClass_Unknown;
	}
	else
	{
		g_bHGDraftClassRandom = false;
		g_HGDraftClass = view_as<TFClassType>(StringToInt(info));
	}

	AJB_LR_ShowHungerGamesMenu(client);
	return 0;
}

// Shared per-client label builders for the HG/CW chat lines (localized, so they must
// run inside the per-client loop — but only once each, not duplicated per function).
void AJB_LR_HG_WeaponsLabel(int client, bool meleeOnly, char[] out, int maxlen)
{
	Format(out, maxlen, "%T", meleeOnly ? "LR HG Weapons Melee" : "LR HG Weapons Full", client);
}

// mode: 0 = any class, 1 = random class, 2 = fixed class (cls).
void AJB_LR_HG_ClassLabel(int client, int mode, TFClassType cls, char[] out, int maxlen)
{
	switch (mode)
	{
		case 0:
		{
			Format(out, maxlen, "%T", "LR HG Class Any", client);
		}
		case 1:
		{
			Format(out, maxlen, "%T", "LR HG Class Random", client);
		}
		default:
		{
			char fixed[32];
			AJB_TFClassName(cls, fixed, sizeof(fixed));
			strcopy(out, maxlen, fixed);
		}
	}
}

void AJB_LR_ChatAllHungerGamesChose(int chooser, bool meleeOnly, bool classRandom, TFClassType cls)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));

		char locClass[32];
		char locWeapons[32];
		AJB_LR_HG_ClassLabel(i, classRandom ? 1 : (cls == TFClass_Unknown ? 0 : 2), cls, locClass, sizeof(locClass));
		AJB_LR_HG_WeaponsLabel(i, meleeOnly, locWeapons, sizeof(locWeapons));

		CPrintToChat(i, "%T", "LR Chose HungerGames", i, prefix, chooser, locClass, locWeapons);
	}
}

// =========================================================================================================
// Hunger Games - live round
// =========================================================================================================

void AJB_LR_ApplyHungerGames(const char[] chooser, bool meleeOnly, bool classRandom, TFClassType cls)
{
	g_bHungerGames = true;
	g_bHGGrace = true;
	g_bHGEnding = false;
	g_bHGMeleeOnly = meleeOnly;
	g_bHGClassLock = false;
	g_HGClass = TFClass_Unknown;

	if (classRandom)
	{
		g_bHGClassLock = true;
		g_HGClass = view_as<TFClassType>(GetRandomInt(view_as<int>(TFClass_Scout), view_as<int>(TFClass_Engineer)));
	}
	else if (cls != TFClass_Unknown)
	{
		g_bHGClassLock = true;
		g_HGClass = cls;
	}

	// Combat day: full loadouts allowed, no warden claim, freekill rules relaxed,
	// cells opened and state moved to SpecialDay (no further state calls after this).
	AJB_BeginCombatDay();
	AJB_SetupSpecialDay();

	// Friendly fire stays off for the grace window (same-team damage blocked by engine).
	AJB_LR_HG_SetFriendlyFire(false);

	// Core jail clock still awards guards on expire - HG owns the end (last standing / timeout).

	// Move guards to RED without killing them: route through Spectator first.
	// TF2_ChangeClientTeam from BLU->RED kills a live player and fires player_death,
	// which would trigger Frame_HGRestoreBluTeam and move them back to BLU.
	int redTeam = AJB_GetPrisonersTeam();
	int blueTeam = AJB_GetGuardsTeam();
	AJB_LR_FoldAllToRed(redTeam, blueTeam, g_bHGOriginalBlu);

	RequestFrame(Frame_HGArmAll);

	// Per-client arm dedupe: respawns during apply queue a spawn-arm too, which runs in
	// the same frame as ArmAll — the flag lets ArmAll skip whoever was already armed.
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bHGArmedThisFrame[i] = false;
	}

	float grace = g_cvHGGraceTime.FloatValue;
	if (grace < 5.0)
	{
		grace = LR_HG_GRACE_DEFAULT;
	}

	float roundTime = g_cvHGRoundTime.FloatValue;
	if (roundTime < 60.0)
	{
		roundTime = LR_HG_ROUND_DEFAULT;
	}

	// HUD only - authoritative end is g_hHGEndTimer / last-standing (not core guards-win expire).
	AJB_SetPhaseTimer(roundTime);
	AJB_LR_KillHGTimers();
	g_hHGGraceTimer = CreateTimer(grace, Timer_HGGraceEnd, _, TIMER_FLAG_NO_MAPCHANGE);
	g_hHGEndTimer = CreateTimer(roundTime, Timer_HGEnd, _, TIMER_FLAG_NO_MAPCHANGE);

	AJB_LR_ChatAllHungerGamesApplied(chooser, meleeOnly, g_bHGClassLock, g_HGClass, grace);
}

void Frame_HGArmAll(any data)
{
	if (!g_bHungerGames)
	{
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && AJB_IsPrisoner(i))
		{
			if (!g_bHGArmedThisFrame[i])
			{
				AJB_LR_HG_ArmPlayer(i);
				g_bHGArmedThisFrame[i] = true;
			}
		}
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		g_bHGArmedThisFrame[i] = false;
	}
}

void AJB_LR_HG_OnPlayerSpawn(int client)
{
	if (!g_bHungerGames || !IsClientInGame(client) || IsFakeClient(client))
	{
		return;
	}

	int team = GetClientTeam(client);
	if (team < 2)
	{
		return;
	}

	// Mark as queued so the apply-frame ArmAll skips this client (spawn-arm runs first).
	g_bHGArmedThisFrame[client] = true;
	RequestFrame(Frame_HGArmClient, GetClientUserId(client));
}

void Frame_HGArmClient(int userid)
{
	if (!g_bHungerGames)
	{
		return;
	}

	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && AJB_IsPrisoner(client))
	{
		AJB_LR_HG_ArmPlayer(client);
	}
}

void AJB_LR_HG_ArmPlayer(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	if (g_bHGClassLock && g_HGClass != TFClass_Unknown)
	{
		if (TF2_GetPlayerClass(client) != g_HGClass)
		{
			TF2_SetPlayerClass(client, g_HGClass, false, true);
		}
	}

	// Full unrestricted stock loadout (combat day already cleared rebel/freeday flags).
	TF2_RegeneratePlayer(client);

	if (g_bHGMeleeOnly)
	{
		AJB_StripToMelee(client);
	}
}

Action Timer_HGGraceEnd(Handle timer)
{
	g_hHGGraceTimer = null;

	if (!g_bHungerGames)
	{
		return Plugin_Stop;
	}

	g_bHGGrace = false;
	AJB_LR_HG_SetFriendlyFire(true);
	AJB_ChatAll("LR HG Grace End");
	return Plugin_Stop;
}

Action Timer_HGEnd(Handle timer)
{
	g_hHGEndTimer = null;

	if (!g_bHungerGames || !g_bHasCore || g_bHGEnding)
	{
		return Plugin_Stop;
	}

	g_bHGEnding = true;
	AJB_ChatAll("LR HG TimeUp");
	AJB_ForceTeamWin(AJB_GetPrisonersTeam());
	return Plugin_Stop;
}

void Frame_HGCheckWinner(any data)
{
	g_bHGCheckQueued = false;

	if (!g_bHungerGames || g_bHGEnding || !g_bHasCore)
	{
		return;
	}

	// Grace is loot/scatter time - do not end on deaths during the window.
	if (g_bHGGrace)
	{
		return;
	}

	int alive = 0;
	int last = 0;
	int redTeam = AJB_GetPrisonersTeam();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i) && GetClientTeam(i) == redTeam)
		{
			alive++;
			last = i;
		}
	}

	if (alive == 1 && last > 0)
	{
		g_bHGEnding = true;
		AJB_ChatAll1N("LR HG Winner", last);
		AJB_ForceTeamWin(GetClientTeam(last));
	}
	else if (alive <= 0)
	{
		g_bHGEnding = true;
		AJB_ChatAll("LR HG NoWinner");
		AJB_ForceTeamWin(AJB_GetPrisonersTeam());
	}
}

void AJB_LR_KillHGTimers()
{
	if (g_hHGGraceTimer != null)
	{
		delete g_hHGGraceTimer;
		g_hHGGraceTimer = null;
	}
	if (g_hHGEndTimer != null)
	{
		delete g_hHGEndTimer;
		g_hHGEndTimer = null;
	}
}

void AJB_LR_ChatAllHungerGamesApplied(const char[] chooserName, bool meleeOnly, bool classLock, TFClassType cls, float grace)
{
	int graceSec = RoundToFloor(grace);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));

		char locClass[32];
		char locWeapons[32];
		AJB_LR_HG_ClassLabel(i, classLock ? 2 : 0, cls, locClass, sizeof(locClass));
		AJB_LR_HG_WeaponsLabel(i, meleeOnly, locWeapons, sizeof(locWeapons));

		CPrintToChat(i, "%T", "LR Applied HungerGames", i, prefix,
			chooserName[0] != '\0' ? chooserName : "LR", locClass, locWeapons, graceSec);
	}
}

