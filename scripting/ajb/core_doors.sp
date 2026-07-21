// =========================================================================================================
// Cell door open/close via per-map config + common name fallbacks + optional name scan
// =========================================================================================================

void AJB_LoadMapDoors()
{
	g_iDoorNameCount = 0;

	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));

	// workshop/123/jb_map.cfg is useless; use the trailing map name.
	char fileMap[PLATFORM_MAX_PATH];
	strcopy(fileMap, sizeof(fileMap), map);
	int slash = FindCharInString(fileMap, '/', true);
	if (slash != -1)
	{
		strcopy(fileMap, sizeof(fileMap), fileMap[slash + 1]);
	}

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "%s/%s.cfg", AJB_MAP_CONFIG_DIR, fileMap);

	if (FileExists(path))
	{
		KeyValues kv = new KeyValues("AJBDoors");
		if (kv.ImportFromFile(path))
		{
			if (kv.JumpToKey("doors"))
			{
				if (kv.GotoFirstSubKey(false))
				{
					do
					{
						char name[AJB_MAX_DOOR_NAME_LEN];
						kv.GetSectionName(name, sizeof(name));
						char val[AJB_MAX_DOOR_NAME_LEN];
						kv.GetString(NULL_STRING, val, sizeof(val), name);
						if (val[0] == '\0')
						{
							strcopy(val, sizeof(val), name);
						}
						AJB_AddDoorName(val);
					}
					while (kv.GotoNextKey(false));
				}
				kv.GoBack();
			}

			if (kv.JumpToKey("targets"))
			{
				if (kv.GotoFirstSubKey(false))
				{
					do
					{
						char val[AJB_MAX_DOOR_NAME_LEN];
						kv.GetString(NULL_STRING, val, sizeof(val), "");
						if (val[0] != '\0')
						{
							AJB_AddDoorName(val);
						}
					}
					while (kv.GotoNextKey(false));
				}
			}

			if (kv.GetNum("nofallback", 0) != 0 && g_iDoorNameCount > 0)
			{
				LogMessage("[AJB] Loaded %d door target(s) from %s (nofallback).", g_iDoorNameCount, path);
				delete kv;
				return;
			}
		}
		delete kv;
	}

	if (g_iDoorNameCount == 0)
	{
		AJB_AddDoorName("cells");
		AJB_AddDoorName("cell_doors");
		AJB_AddDoorName("cell_door");
		AJB_AddDoorName("doors_cells");
		AJB_AddDoorName("jail_cells");
		AJB_AddDoorName("prison_doors");
		AJB_AddDoorName("celldoors");
		AJB_AddDoorName("cell_door_1");
		AJB_AddDoorName("doors");
		AJB_AddDoorName("jail_door");
	}

	AJB_ScanDoorTargetnames();

	LogMessage("[AJB] Found %d doors.", g_iDoorNameCount);
}

void AJB_ScanDoorTargetnames()
{
	char classname[64];
	char name[128];
	int maxEdicts = GetMaxEntities();

	for (int ent = MaxClients + 1; ent < maxEdicts; ent++)
	{
		if (!IsValidEntity(ent))
		{
			continue;
		}

		GetEntityClassname(ent, classname, sizeof(classname));
		if (!AJB_IsDoorLikeClass(classname))
		{
			continue;
		}

		if (!HasEntProp(ent, Prop_Data, "m_iName"))
		{
			continue;
		}

		GetEntPropString(ent, Prop_Data, "m_iName", name, sizeof(name));
		if (name[0] == '\0')
		{
			continue;
		}

		if (StrContains(name, "cell", false) != -1
			|| StrContains(name, "jail", false) != -1
			|| StrContains(name, "prison", false) != -1
			|| StrContains(name, "cage", false) != -1)
		{
			AJB_AddDoorName(name);
		}
	}
}

bool AJB_IsDoorLikeClass(const char[] classname)
{
	if (StrContains(classname, "door", false) != -1)
	{
		return true;
	}
	if (StrContains(classname, "movelinear", false) != -1)
	{
		return true;
	}
	if (StrContains(classname, "button", false) != -1)
	{
		return true;
	}
	if (StrEqual(classname, "logic_relay", false)
		|| StrEqual(classname, "func_brush", false)
		|| StrEqual(classname, "func_wall_toggle", false)
		|| StrEqual(classname, "trigger_teleport", false))
	{
		return true;
	}
	return false;
}

void AJB_AddDoorName(const char[] name)
{
	if (name[0] == '\0' || g_iDoorNameCount >= AJB_MAX_DOOR_NAMES)
	{
		return;
	}

	for (int i = 0; i < g_iDoorNameCount; i++)
	{
		if (StrEqual(g_sDoorNames[i], name, false))
		{
			return;
		}
	}

	strcopy(g_sDoorNames[g_iDoorNameCount], AJB_MAX_DOOR_NAME_LEN, name);
	g_iDoorNameCount++;
}

// Bring cell targets back to closed/locked. After force_map_reset this is mostly a no-op;
// after a soft engine win (no map regen) this is what stops open cages from carrying over.
void AJB_ResetCellsForRound()
{
	// Named cell targets from config / scan.
	AJB_FireDoorInput("Unlock");
	AJB_FireDoorInput("Close");
	AJB_FireDoorInput("Lock");

	// Also every door-like entity whose targetname looks like a cell (covers soft resets
	// where the config list is incomplete after entity index reshuffle).
	AJB_FireAllCellLikeDoors("Unlock");
	AJB_FireAllCellLikeDoors("Close");
	AJB_FireAllCellLikeDoors("Lock");

	CreateTimer(0.15, Timer_CellsResetRetry, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(0.50, Timer_CellsResetRetry, _, TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_CellsResetRetry(Handle timer)
{
	if (!g_bModeActive)
	{
		return Plugin_Stop;
	}

	AJB_FireDoorInput("Close");
	AJB_FireDoorInput("Lock");
	AJB_FireAllCellLikeDoors("Close");
	AJB_FireAllCellLikeDoors("Lock");
	return Plugin_Stop;
}

void AJB_FireAllCellLikeDoors(const char[] input)
{
	int maxEdicts = GetMaxEntities();
	char classname[64];
	char name[128];

	for (int ent = MaxClients + 1; ent < maxEdicts; ent++)
	{
		if (!IsValidEntity(ent))
		{
			continue;
		}

		GetEntityClassname(ent, classname, sizeof(classname));
		if (!AJB_IsDoorLikeClass(classname))
		{
			continue;
		}

		if (!HasEntProp(ent, Prop_Data, "m_iName"))
		{
			continue;
		}

		GetEntPropString(ent, Prop_Data, "m_iName", name, sizeof(name));
		if (name[0] == '\0')
		{
			continue;
		}

		if (StrContains(name, "cell", false) == -1
			&& StrContains(name, "jail", false) == -1
			&& StrContains(name, "prison", false) == -1
			&& StrContains(name, "cage", false) == -1)
		{
			continue;
		}

		AcceptEntityInput(ent, input);
	}
}

bool AJB_OpenCellsInternal(bool announce)
{
	// Locked doors ignore Open — Unlock first. A delayed Open covers engines that
	// only process Open on the next tick after Unlock (avoids needing two menu presses).
	AJB_FireDoorInput("Unlock");
	AJB_FireDoorInput("Open");
	CreateTimer(0.05, Timer_CellsOpenRetry, _, TIMER_FLAG_NO_MAPCHANGE);

	if (g_RoundState == AJBState_CellsLocked || g_RoundState == AJBState_Waiting)
	{
		AJB_SetRoundState(AJBState_CellsOpen);
	}

	AJB_KillCellsAutoTimer();
	// Keep the round HUD clock running — do not hide/reset it when cells open.

	Call_StartForward(g_hFwdCellsOpened);
	Call_Finish();

	if (announce)
	{
		AJB_ChatAll("Cells Opened");
	}

	return true;
}

Action Timer_CellsOpenRetry(Handle timer)
{
	if (!g_bModeActive)
	{
		return Plugin_Stop;
	}

	AJB_FireDoorInput("Unlock");
	AJB_FireDoorInput("Open");
	return Plugin_Stop;
}

bool AJB_CloseCellsInternal(bool announce)
{
	// Close first, then Lock so a re-open path always needs Unlock (handled in Open).
	AJB_FireDoorInput("Close");
	AJB_FireDoorInput("Lock");
	CreateTimer(0.05, Timer_CellsCloseRetry, _, TIMER_FLAG_NO_MAPCHANGE);

	if (g_RoundState == AJBState_CellsOpen)
	{
		AJB_SetRoundState(AJBState_CellsLocked);
	}

	Call_StartForward(g_hFwdCellsClosed);
	Call_Finish();

	if (announce)
	{
		AJB_ChatAll("Cells Closed");
	}

	return true;
}

Action Timer_CellsCloseRetry(Handle timer)
{
	if (!g_bModeActive)
	{
		return Plugin_Stop;
	}

	AJB_FireDoorInput("Close");
	AJB_FireDoorInput("Lock");
	return Plugin_Stop;
}

int AJB_FireDoorInput(const char[] input)
{
	int touched = 0;

	for (int i = 0; i < g_iDoorNameCount; i++)
	{
		int ent = -1;
		while ((ent = AJB_FindEntityByTargetname(ent, g_sDoorNames[i])) != -1)
		{
			AcceptEntityInput(ent, input);
			touched++;
		}
	}

	return touched;
}

int AJB_FindEntityByTargetname(int startEnt, const char[] targetname)
{
	char classname[64];
	char name[128];

	int maxEdicts = GetMaxEntities();
	for (int ent = startEnt + 1; ent < maxEdicts; ent++)
	{
		if (!IsValidEntity(ent))
		{
			continue;
		}

		GetEntityClassname(ent, classname, sizeof(classname));
		if (!AJB_IsDoorLikeClass(classname))
		{
			continue;
		}

		if (!HasEntProp(ent, Prop_Data, "m_iName"))
		{
			continue;
		}

		GetEntPropString(ent, Prop_Data, "m_iName", name, sizeof(name));
		if (StrEqual(name, targetname, false))
		{
			return ent;
		}
	}

	return -1;
}
