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

void AJB_LR_ChatAllCellWarsChose(int chooser, bool meleeOnly)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		char locWeapons[32];
		Format(locWeapons, sizeof(locWeapons), "%T", meleeOnly ? "LR HG Weapons Melee" : "LR HG Weapons Full", i);
		CPrintToChat(i, "%T", "LR Chose CellWars", i, prefix, chooser, locWeapons);
	}
}

void AJB_LR_ApplyCellWars(const char[] chooser, bool meleeOnly)
{
	g_bCellWars = true;
	g_bCWEnding = false;
	g_bCWMeleeOnly = meleeOnly;

	AJB_BeginCombatDay();
	AJB_ClearWarden();
	AJB_SetRebelOnHit(false);

	AJB_LR_HG_SetFriendlyFire(true);

	AJB_ClearPhaseTimer();

	// Cells must be closed for cell wars
	AJB_CloseCells();
	if (g_bHasCore)
	{
		AJB_SetRoundState(AJBState_SpecialDay);
	}

	int redTeam = AJB_LR_GetPrisonersTeam();
	int blueTeam = AJB_LR_GetGuardsTeam();
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bCWOriginalBlu[i] = false;
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			if (GetClientTeam(i) == blueTeam)
			{
				g_bCWOriginalBlu[i] = true;
				ChangeClientTeam(i, 1);
				ChangeClientTeam(i, redTeam);
			}

			if (!IsPlayerAlive(i) && GetClientTeam(i) == redTeam)
			{
				TF2_RespawnPlayer(i);
			}
		}
	}

	RequestFrame(Frame_CWArmAll);

	float roundTime = g_cvCWRoundTime.FloatValue;
	if (roundTime < 60.0) roundTime = LR_HG_ROUND_DEFAULT;

	AJB_SetPhaseTimer(roundTime);
	AJB_LR_KillCWTimers();
	g_hCWEndTimer = CreateTimer(roundTime, Timer_CWEnd, _, TIMER_FLAG_NO_MAPCHANGE);

	AJB_LR_ChatAllCellWarsApplied(chooser, meleeOnly);
}

void Frame_CWArmAll(any data)
{
	if (!g_bCellWars) return;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && AJB_IsPrisoner(i))
		{
			AJB_LR_CW_ArmPlayer(i);
		}
	}
}

void AJB_LR_CW_OnPlayerSpawn(int client)
{
	if (!g_bCellWars || !IsClientInGame(client) || IsFakeClient(client)) return;
	if (GetClientTeam(client) < 2) return;
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
		AJB_LR_HG_StripToMelee(client);
	}
}

Action Timer_CWEnd(Handle timer)
{
	g_hCWEndTimer = null;
	if (!g_bCellWars || !g_bHasCore || g_bCWEnding) return Plugin_Stop;

	g_bCWEnding = true;
	AJB_ChatAll("LR CW TimeUp");
	AJB_ForceTeamWin(AJB_LR_GetPrisonersTeam());
	return Plugin_Stop;
}

void AJB_LR_CW_OnPlayerDeath(int victim)
{
	if (!g_bCellWars || g_bCWEnding) return;
	if (victim > 0 && victim <= MaxClients && g_bCWOriginalBlu[victim])
	{
		RequestFrame(Frame_CWRestoreBluTeam, GetClientUserId(victim));
	}
	RequestFrame(Frame_CWCheckWinner);
}

void Frame_CWRestoreBluTeam(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client) && g_bCWOriginalBlu[client])
	{
		g_bCWOriginalBlu[client] = false;
		int blueTeam = AJB_LR_GetGuardsTeam();
		if (GetClientTeam(client) != blueTeam)
		{
			TF2_ChangeClientTeam(client, view_as<TFTeam>(blueTeam));
		}
	}
}

void Frame_CWCheckWinner(any data)
{
	if (!g_bCellWars || g_bCWEnding || !g_bHasCore) return;

	int alive = 0, last = 0;
	int redTeam = AJB_LR_GetPrisonersTeam();
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
		AJB_LR_ChatAll1N("LR CW Winner", last);
		AJB_ForceTeamWin(GetClientTeam(last));
	}
	else if (alive <= 0)
	{
		g_bCWEnding = true;
		AJB_ChatAll("LR CW NoWinner");
		AJB_ForceTeamWin(AJB_LR_GetPrisonersTeam());
	}
}

void AJB_LR_KillCWTimers()
{
	if (g_hCWEndTimer != null)
	{
		delete g_hCWEndTimer;
		g_hCWEndTimer = null;
	}
}

void AJB_LR_ChatAllCellWarsApplied(const char[] chooserName, bool meleeOnly)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		char locWeapons[32];
		Format(locWeapons, sizeof(locWeapons), "%T", meleeOnly ? "LR HG Weapons Melee" : "LR HG Weapons Full", i);
		CPrintToChat(i, "%T", "LR Applied CellWars", i, prefix, chooserName[0] != '\0' ? chooserName : "LR", locWeapons);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (g_bCellWars && !g_bCWEnding && IsClientInGame(client) && IsPlayerAlive(client))
	{
		if (GetClientTeam(client) == AJB_LR_GetPrisonersTeam())
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
	int count = 0;
	float spawns[64][3];
	int redTeam = AJB_LR_GetPrisonersTeam();
	int ent = -1;
	while (count < sizeof(spawns) && (ent = FindEntityByClassname(ent, "info_player_teamspawn")) != -1)
	{
		if (HasEntProp(ent, Prop_Data, "m_iTeamNum") && GetEntProp(ent, Prop_Data, "m_iTeamNum") != redTeam)
		{
			continue;
		}
		GetEntPropVector(ent, Prop_Data, "m_vecOrigin", spawns[count]);
		count++;
	}
	
	if (count > 0)
	{
		int pick = GetRandomInt(0, count - 1);
		float noVel[3];
		TeleportEntity(client, spawns[pick], NULL_VECTOR, noVel);
	}
}

