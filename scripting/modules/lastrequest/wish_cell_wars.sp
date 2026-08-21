// =========================================================================================================
// Last Request - Cell Wars
// =========================================================================================================

// =========================================================================================================
// Cell Wars
// =========================================================================================================

void AJB_LR_StartCellWarsConfig(int prisoner)
{
	g_bCWDraftMelee = false;
	g_bMenuOpen = true;
	AJB_LR_ShowCellWarsMenu(prisoner);
	AJB_LR_StartMenuTimers(prisoner);
}

void AJB_LR_ShowCellWarsMenu(int prisoner)
{
	if (prisoner < 1 || !IsClientInGame(prisoner)) return;

	Menu menu = new Menu(MenuHandler_CellWars);
	char title[64], line[96];

	Format(title, sizeof(title), "%T", "LR CW Menu Title", prisoner);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", g_bCWDraftMelee ? "LR HG Opt Melee On" : "LR HG Opt Melee Off", prisoner);
	menu.AddItem("melee", line);

	Format(line, sizeof(line), "%T", "LR CW Opt Confirm", prisoner);
	menu.AddItem("confirm", line);

	Format(line, sizeof(line), "%T", "LR HG Opt Back", prisoner);
	menu.AddItem("back", line);

	menu.ExitButton = false;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));
}

public int MenuHandler_CellWars(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}
	if (action != MenuAction_Select) return 0;

	int client = param1;
	if (!IsClientInGame(client) || !AJB_LR_IsMenuAllowed(client)) return 0;

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "melee"))
	{
		g_bCWDraftMelee = !g_bCWDraftMelee;
		AJB_LR_ShowCellWarsMenu(client);
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
		g_PendingWish = LRWish_CellWars;
		g_PendingCWMeleeOnly = g_bCWDraftMelee;
		AJB_LR_RememberChooser(client);
		AJB_LR_ChatAllCellWarsChose(client, g_bCWDraftMelee);
		AJB_LR_CloseMenuState();
		AJB_LR_MarkWishChosen();
	}
	return 0;
}

void AJB_LR_ChatAllCellWarsImpl(const char[] phrase, bool usePlayer, int chooser, const char[] chooserName, bool meleeOnly)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		char locWeapons[32];
		AJB_LR_HG_WeaponsLabel(i, meleeOnly, locWeapons, sizeof(locWeapons));
		if (usePlayer)
		{
			CPrintToChat(i, "%T", phrase, i, prefix, chooser, locWeapons);
		}
		else
		{
			CPrintToChat(i, "%T", phrase, i, prefix, chooserName[0] != '\0' ? chooserName : "LR", locWeapons);
		}
	}
}

void AJB_LR_ChatAllCellWarsChose(int chooser, bool meleeOnly)
{
	AJB_LR_ChatAllCellWarsImpl("LR Chose CellWars", true, chooser, "", meleeOnly);
}

int g_iCWRedTeam = 2;
float g_vecCWSpawns[64][3];
int g_iCWSpawnCount = 0;

void AJB_LR_ApplyCellWars(const char[] chooser, bool meleeOnly)
{
	g_bCellWars = true;
	g_bCWEnding = false;
	g_bCWMeleeOnly = meleeOnly;

	// The OnPlayerRunCmd jump detector was skipping writes outside Cell Wars, so the
	// last-button state may be stale; re-seed it so the first jump is not misread.
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iCWLastButtons[i] = 0;
		g_fCWLastTeleport[i] = 0.0;
		g_iCWLastCell[i] = -1;
		g_fCWCellSince[i] = GetGameTime();
		g_bCWWarned[i] = false;
	}

	// Cell Wars needs cells CLOSED; BeginCombatDay would force-open and announce them, so
	// build the day manually. CloseCells first, then the custom state (AGENTS.md order).
	AJB_SetupSpecialDay();

	AJB_LR_HG_SetFriendlyFire(true);

	// Cells must be closed for cell wars
	AJB_CloseCells();
	if (g_bHasCore)
	{
		AJB_SetRoundState(AJBState_SpecialDay);
	}

	g_iCWRedTeam = AJB_GetPrisonersTeam();
	int blueTeam = AJB_GetGuardsTeam();

	g_iCWSpawnCount = 0;
	int ent = -1;
	while (g_iCWSpawnCount < sizeof(g_vecCWSpawns) && (ent = FindEntityByClassname(ent, "info_player_teamspawn")) != -1)
	{
		if (HasEntProp(ent, Prop_Data, "m_iTeamNum") && GetEntProp(ent, Prop_Data, "m_iTeamNum") != g_iCWRedTeam)
		{
			continue;
		}
		GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_vecCWSpawns[g_iCWSpawnCount]);
		g_iCWSpawnCount++;
	}

	AJB_LR_FoldAllToRed(g_iCWRedTeam, blueTeam, g_bCWOriginalBlu);

	RequestFrame(Frame_CWArmAll);

	for (int i = 1; i <= MaxClients; i++)
	{
		g_bCWArmedThisFrame[i] = false;
	}

	float roundTime = g_cvCWRoundTime.FloatValue;
	if (roundTime < 60.0) roundTime = LR_HG_ROUND_DEFAULT;

	AJB_SetPhaseTimer(roundTime);
	AJB_LR_KillCWTimers();
	g_hCWEndTimer = CreateTimer(roundTime, Timer_CWEnd, _, TIMER_FLAG_NO_MAPCHANGE);

	// Camping check: only needs to run when the hazard is enabled.
	if (g_cvCWCampTime.FloatValue > 0.0)
	{
		g_hCWCellTimer = CreateTimer(1.0, Timer_CWCellCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}

	AJB_LR_ChatAllCellWarsApplied(chooser, meleeOnly);
}

void Frame_CWArmAll(any data)
{
	if (!g_bCellWars) return;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && AJB_IsPrisoner(i))
		{
			if (!g_bCWArmedThisFrame[i])
			{
				AJB_LR_CW_ArmPlayer(i);
				g_bCWArmedThisFrame[i] = true;
			}
		}
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bCWArmedThisFrame[i] = false;
	}
}

void AJB_LR_CW_OnPlayerSpawn(int client)
{
	if (!g_bCellWars || !IsClientInGame(client) || IsFakeClient(client)) return;
	if (GetClientTeam(client) < 2) return;
	g_iCWLastCell[client] = -1;
	g_fCWCellSince[client] = GetGameTime();
	g_bCWWarned[client] = false;
	g_bCWArmedThisFrame[client] = true;
	RequestFrame(Frame_CWArmClient, GetClientUserId(client));
}

void Frame_CWArmClient(int userid)
{
	if (!g_bCellWars) return;
	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && AJB_IsPrisoner(client))
	{
		AJB_LR_CW_ArmPlayer(client);
	}
}

void AJB_LR_CW_ArmPlayer(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client)) return;
	TF2_RegeneratePlayer(client);
	if (g_bCWMeleeOnly)
	{
		AJB_StripToMelee(client);
	}
}

Action Timer_CWEnd(Handle timer)
{
	g_hCWEndTimer = null;
	if (!g_bCellWars || !g_bHasCore || g_bCWEnding) return Plugin_Stop;

	g_bCWEnding = true;
	AJB_LR_KillCWCellTimer();
	AJB_ChatAll("LR CW TimeUp");
	AJB_ForceTeamWin(AJB_GetPrisonersTeam());
	return Plugin_Stop;
}

void AJB_LR_CW_OnPlayerDeath(int victim)
{
	if (!g_bCellWars || g_bCWEnding) return;
	if (victim > 0 && victim <= MaxClients && g_bCWOriginalBlu[victim])
	{
		RequestFrame(Frame_CWRestoreBluTeam, GetClientUserId(victim));
	}
	if (!g_bCWCheckQueued)
	{
		g_bCWCheckQueued = true;
		RequestFrame(Frame_CWCheckWinner);
	}
}

void Frame_CWRestoreBluTeam(int userid)
{
	AJB_LR_RestoreBluOriginal(userid, g_bCWOriginalBlu);
}

void Frame_CWCheckWinner(any data)
{
	g_bCWCheckQueued = false;

	if (!g_bCellWars || g_bCWEnding || !g_bHasCore) return;

	int alive = 0, last = 0;
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
		g_bCWEnding = true;
		AJB_ChatAll1N("LR CW Winner", last);
		AJB_ForceTeamWin(GetClientTeam(last));
	}
	else if (alive <= 0)
	{
		g_bCWEnding = true;
		AJB_ChatAll("LR CW NoWinner");
		AJB_ForceTeamWin(AJB_GetPrisonersTeam());
	}
}

void AJB_LR_KillCWCellTimer()
{
	if (g_hCWCellTimer != null)
	{
		delete g_hCWCellTimer;
		g_hCWCellTimer = null;
	}
}

void AJB_LR_KillCWTimers()
{
	AJB_LR_KillCWCellTimer();
	if (g_hCWEndTimer != null)
	{
		delete g_hCWEndTimer;
		g_hCWEndTimer = null;
	}
}

void AJB_LR_ChatAllCellWarsApplied(const char[] chooserName, bool meleeOnly)
{
	AJB_LR_ChatAllCellWarsImpl("LR Applied CellWars", false, 0, chooserName, meleeOnly);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	// Fast path: this callback runs for every user command of every player on the
	// server; only Cell Wars needs it (jump-to-random-spawn). Leave without touching
	// any state so the write is skipped on non-CW rounds.
	if (!g_bCellWars || g_bCWEnding)
	{
		return Plugin_Continue;
	}

	if (IsClientInGame(client) && IsPlayerAlive(client))
	{
		if (GetClientTeam(client) == g_iCWRedTeam)
		{
			if ((buttons & IN_JUMP) && !(g_iCWLastButtons[client] & IN_JUMP))
			{
				AJB_LR_CW_TeleportToRandomSpawn(client);
			}
		}
	}
	g_iCWLastButtons[client] = buttons;
	return Plugin_Continue;
}

void AJB_LR_CW_TeleportToRandomSpawn(int client)
{
	// Cooldown throttles jump-spam: each jump is a commitment, not a reroll.
	float delay = g_cvCWTeleportDelay.FloatValue;
	if (delay > 0.0)
	{
		float wait = g_fCWLastTeleport[client] + delay - GetGameTime();
		if (wait > 0.0)
		{
			char seconds[16];
			Format(seconds, sizeof(seconds), "%.1f", wait);
			PrintHintText(client, "%T", "LR CW Cooldown", client, seconds);
			return;
		}
	}

	if (g_iCWSpawnCount > 0)
	{
		int pick = GetRandomInt(0, g_iCWSpawnCount - 1);
		float noVel[3];
		TeleportEntity(client, g_vecCWSpawns[pick], NULL_VECTOR, noVel);
		// Landing on a fresh cell resets both the teleport cooldown and the camp clock.
		g_fCWLastTeleport[client] = GetGameTime();
		g_iCWLastCell[client] = pick;
		g_fCWCellSince[client] = GetGameTime();
		g_bCWWarned[client] = false;

		// Jump bonus: heal up to the class cap, so moving is rewarded, not just punished.
		float heal = g_cvCWTeleportHeal.FloatValue;
		if (heal > 0.0)
		{
			int hp = GetEntProp(client, Prop_Data, "m_iHealth");
			int max = GetEntProp(client, Prop_Data, "m_iMaxHealth");
			if (hp < max)
			{
				int gained = RoundToFloor(heal);
				SetEntProp(client, Prop_Data, "m_iHealth", hp + gained > max ? max : hp + gained);
				PrintHintText(client, "%T", "LR CW Teleport Heal", client, gained);
			}
		}
	}
}

// Nearest RED spawn within 300 HU is the player's cell (spawns sit inside cell centers).
int AJB_LR_CW_FindCell(int client)
{
	if (g_iCWSpawnCount <= 0) return -1;
	float origin[3];
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", origin);
	int best = -1;
	float bestDist = 300.0 * 300.0;
	for (int i = 0; i < g_iCWSpawnCount; i++)
	{
		float dist = AJB_GetDistanceSqr(origin, g_vecCWSpawns[i]);
		if (dist < bestDist)
		{
			bestDist = dist;
			best = i;
		}
	}
	return best;
}

Action Timer_CWCellCheck(Handle timer)
{
	if (!g_bCellWars || g_bCWEnding) return Plugin_Continue;

	float campTime = g_cvCWCampTime.FloatValue;
	if (campTime <= 0.0) return Plugin_Continue;
	float campDamage = g_cvCWCampDamage.FloatValue;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i)) continue;
		if (GetClientTeam(i) != g_iCWRedTeam) continue;

		int cell = AJB_LR_CW_FindCell(i);
		if (cell < 0)
		{
			// Roaming past spawn range on a big cell: keep the clock running so camping
			// at the far edge does not reset it; teleports always land on a spawn.
			continue;
		}
		if (cell != g_iCWLastCell[i])
		{
			g_iCWLastCell[i] = cell;
			g_fCWCellSince[i] = GetGameTime();
			g_bCWWarned[i] = false;
			continue;
		}
		if (GetGameTime() - g_fCWCellSince[i] < campTime) continue;

		if (!g_bCWWarned[i])
		{
			g_bCWWarned[i] = true;
			PrintHintText(i, "%T", "LR CW Camp Warn", i);
		}
		if (campDamage > 0.0)
		{
			// No attacker so the burn is never credited to another player.
			SDKHooks_TakeDamage(i, 0, 0, campDamage, DMG_BURN);
			PrintHintText(i, "%T", "LR CW Camp Damage", i);
		}
	}
	return Plugin_Continue;
}

