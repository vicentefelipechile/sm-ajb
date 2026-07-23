// =========================================================================================================
// Cell door open/close via per-map config + common name fallbacks + optional name scan
// =========================================================================================================

// Per-map cfg: configs/ajb/maps/<map>.cfg
// Doors + teleports (freeday / combat_red / combat_blu). Never invents coordinates.
void AJB_LoadMapDoors()
{
	g_iDoorNameCount = 0;
	g_iDoorHammerCount = 0;
	AJB_Settings_ClearTeleports();

	char fileMap[PLATFORM_MAX_PATH];
	AJB_GetShortMapName(fileMap, sizeof(fileMap));

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "%s/%s.cfg", AJB_MAP_CONFIG_DIR, fileMap);

	bool nofallback = false;

	if (FileExists(path))
	{
		// Root name may be "AJB" or legacy "AJBDoors".
		KeyValues kv = new KeyValues("AJB");
		if (kv.ImportFromFile(path))
		{
			// Teleports first (must be at root; door walks would leave wrong node).
			AJB_Settings_LoadTeleportsFromKv(kv);

			// New layout: "doors" { "nofallback" "targets" { ... } }
			if (kv.JumpToKey("doors"))
			{
				nofallback = kv.GetNum("nofallback", 0) != 0;
				AJB_LoadDoorTargetsFromKv(kv);
				kv.GoBack();
			}
			else
			{
				// Legacy: root "AJBDoors" with top-level "targets" / flat names.
				nofallback = kv.GetNum("nofallback", 0) != 0;
				AJB_LoadDoorTargetsFromKv(kv);
			}

			if (nofallback && g_iDoorNameCount > 0)
			{
				LogMessage("[AJB] Loaded %d door target(s) from %s (nofallback).", g_iDoorNameCount, path);
				delete kv;
				return;
			}
		}
		delete kv;
	}
	else
	{
		LogMessage("[AJB] No map cfg %s — door fallbacks only; generating a stub.", path);
		if (g_cvGenConfig != null && g_cvGenConfig.BoolValue)
		{
			AJB_GenerateMapConfigStub(fileMap, false);
		}
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

	// Last resort: nothing matched by config or name — detect by proximity to RED spawn.
	if (g_iDoorNameCount == 0)
	{
		AJB_AutoDetectCellDoors(fileMap);
	}

	LogMessage("[AJB] Found %d doors (+%d auto by map id).", g_iDoorNameCount, g_iDoorHammerCount);
}

// From current KV node: "targets" { "1" "name" } and/or flat string children (legacy).
void AJB_LoadDoorTargetsFromKv(KeyValues kv)
{
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
			kv.GoBack();
		}
		kv.GoBack();
	}

	// Legacy flat list under "doors" or root (section name or value = targetname).
	if (kv.GotoFirstSubKey(false))
	{
		do
		{
			char name[AJB_MAX_DOOR_NAME_LEN];
			kv.GetSectionName(name, sizeof(name));
			if (StrEqual(name, "targets", false) || StrEqual(name, "teleports", false)
				|| StrEqual(name, "nofallback", false) || StrEqual(name, "doors", false))
			{
				continue;
			}

			char val[AJB_MAX_DOOR_NAME_LEN];
			kv.GetString(NULL_STRING, val, sizeof(val), name);
			if (val[0] == '\0')
			{
				strcopy(val, sizeof(val), name);
			}
			// Skip pure numeric flags / empty junk.
			if (val[0] != '\0' && !StrEqual(val, "0", false) && !StrEqual(val, "1", false))
			{
				// Only add if it looks like a targetname (not a vector).
				if (FindCharInString(val, ' ') == -1)
				{
					AJB_AddDoorName(val);
				}
			}
		}
		while (kv.GotoNextKey(false));
		kv.GoBack();
	}
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

bool AJB_NameLooksCellish(const char[] name)
{
	return StrContains(name, "cell", false) != -1
		|| StrContains(name, "jail", false) != -1
		|| StrContains(name, "prison", false) != -1
		|| StrContains(name, "cage", false) != -1;
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

	// Auto-detected doors are addressed by stable map id (covers unnamed cell doors).
	touched += AJB_FireDoorHammerInput(input);
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

// =========================================================================================================
// Auto-detect cell doors by proximity to RED spawn (fallback)
// =========================================================================================================

void AJB_AutoDetectCellDoors(const char[] fileMap)
{
	if (g_cvDoorAuto == null || !g_cvDoorAuto.BoolValue)
	{
		return;
	}

	// Cached hammerids are stable per map; reuse them and skip the scan.
	if (AJB_LoadDoorHammerCache(fileMap))
	{
		LogMessage("[AJB] Auto-doors: loaded %d cached map id(s) for %s.", g_iDoorHammerCount, fileMap);
		return;
	}

	float spawns[MAXPLAYERS][3];
	int spawnCount = AJB_CollectRedSpawns(spawns, MAXPLAYERS);
	if (spawnCount == 0)
	{
		LogMessage("[AJB] Auto-doors: no RED spawns found; skipped.");
		return;
	}

	float radius = g_cvDoorAutoRadius.FloatValue;
	int maxEdicts = GetMaxEntities();
	char classname[64];

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

		if (!HasEntProp(ent, Prop_Data, "m_iHammerID"))
		{
			continue;
		}

		float center[3];
		AJB_GetEntityWorldCenter(ent, center);

		if (AJB_MinDistToSpawns(center, spawns, spawnCount) > radius)
		{
			continue;
		}

		AJB_AddDoorHammerId(GetEntProp(ent, Prop_Data, "m_iHammerID"));
	}

	if (g_iDoorHammerCount > 0)
	{
		AJB_WriteDoorHammerCache(fileMap);
		LogMessage("[AJB] Auto-doors: detected %d door(s) near RED spawn, cached for %s.", g_iDoorHammerCount, fileMap);
	}
	else
	{
		LogMessage("[AJB] Auto-doors: no door-like entities within %.0fu of RED spawn.", radius);
	}
}

int AJB_CollectRedSpawns(float spawns[][3], int maxSpawns)
{
	int count = 0;
	int prisoners = AJB_GetPrisonersTeam();

	int ent = -1;
	while (count < maxSpawns && (ent = FindEntityByClassname(ent, "info_player_teamspawn")) != -1)
	{
		if (HasEntProp(ent, Prop_Data, "m_iTeamNum")
			&& GetEntProp(ent, Prop_Data, "m_iTeamNum") != prisoners)
		{
			continue;
		}

		GetEntPropVector(ent, Prop_Data, "m_vecOrigin", spawns[count]);
		count++;
	}

	return count;
}

// Brush entities often report origin (0,0,0); use the collision AABB center when available.
void AJB_GetEntityWorldCenter(int ent, float out[3])
{
	float origin[3];
	GetEntPropVector(ent, Prop_Data, "m_vecOrigin", origin);

	if (HasEntProp(ent, Prop_Data, "m_vecMins") && HasEntProp(ent, Prop_Data, "m_vecMaxs"))
	{
		float mins[3];
		float maxs[3];
		GetEntPropVector(ent, Prop_Data, "m_vecMins", mins);
		GetEntPropVector(ent, Prop_Data, "m_vecMaxs", maxs);
		out[0] = origin[0] + (mins[0] + maxs[0]) * 0.5;
		out[1] = origin[1] + (mins[1] + maxs[1]) * 0.5;
		out[2] = origin[2] + (mins[2] + maxs[2]) * 0.5;
	}
	else
	{
		out = origin;
	}
}

float AJB_MinDistToSpawns(const float pos[3], const float spawns[][3], int count)
{
	float best = -1.0;
	for (int i = 0; i < count; i++)
	{
		float d = GetVectorDistance(pos, spawns[i]);
		if (best < 0.0 || d < best)
		{
			best = d;
		}
	}
	return best;
}

void AJB_AddDoorHammerId(int hid)
{
	if (hid == 0 || g_iDoorHammerCount >= AJB_MAX_DOOR_NAMES)
	{
		return;
	}

	for (int i = 0; i < g_iDoorHammerCount; i++)
	{
		if (g_iDoorHammerIds[i] == hid)
		{
			return;
		}
	}

	g_iDoorHammerIds[g_iDoorHammerCount++] = hid;
}

bool AJB_DoorHammerKnown(int hid)
{
	for (int i = 0; i < g_iDoorHammerCount; i++)
	{
		if (g_iDoorHammerIds[i] == hid)
		{
			return true;
		}
	}
	return false;
}

int AJB_FireDoorHammerInput(const char[] input)
{
	if (g_iDoorHammerCount == 0)
	{
		return 0;
	}

	int touched = 0;
	int maxEdicts = GetMaxEntities();
	char classname[64];

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

		if (!HasEntProp(ent, Prop_Data, "m_iHammerID"))
		{
			continue;
		}

		if (AJB_DoorHammerKnown(GetEntProp(ent, Prop_Data, "m_iHammerID")))
		{
			AcceptEntityInput(ent, input);
			touched++;
		}
	}

	return touched;
}

bool AJB_LoadDoorHammerCache(const char[] fileMap)
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "%s/%s.autodoors.txt", AJB_MAP_CONFIG_DIR, fileMap);
	if (!FileExists(path))
	{
		return false;
	}

	File f = OpenFile(path, "r");
	if (f == null)
	{
		return false;
	}

	char line[64];
	while (f.ReadLine(line, sizeof(line)))
	{
		TrimString(line);
		if (line[0] == '\0' || (line[0] == '/' && line[1] == '/'))
		{
			continue;
		}
		AJB_AddDoorHammerId(StringToInt(line));
	}

	delete f;
	return g_iDoorHammerCount > 0;
}

bool AJB_WriteDoorHammerCache(const char[] fileMap)
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "%s/%s.autodoors.txt", AJB_MAP_CONFIG_DIR, fileMap);

	File f = OpenFile(path, "w");
	if (f == null)
	{
		LogError("[AJB] Auto-doors: cannot write cache %s.", path);
		return false;
	}

	f.WriteLine("// AJB auto-detected cell doors (m_iHammerID). Generated — delete to re-scan.");
	for (int i = 0; i < g_iDoorHammerCount; i++)
	{
		f.WriteLine("%d", g_iDoorHammerIds[i]);
	}

	delete f;
	return true;
}

// =========================================================================================================
// Per-map config stub generation
// =========================================================================================================

void AJB_GetShortMapName(char[] out, int maxlen)
{
	GetCurrentMap(out, maxlen);
	// workshop/123/jb_map → keep the trailing map name only.
	int slash = FindCharInString(out, '/', true);
	if (slash != -1)
	{
		strcopy(out, maxlen, out[slash + 1]);
	}
}

// Collect every door-like entity that has a non-empty targetname (deduped).
int AJB_CollectDoorLikeNames(char[][] out, int maxNames)
{
	int count = 0;
	int maxEdicts = GetMaxEntities();
	char classname[64];
	char name[AJB_MAX_DOOR_NAME_LEN];

	for (int ent = MaxClients + 1; ent < maxEdicts && count < maxNames; ent++)
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

		bool dup = false;
		for (int i = 0; i < count; i++)
		{
			if (StrEqual(out[i], name, false))
			{
				dup = true;
				break;
			}
		}
		if (!dup)
		{
			strcopy(out[count], AJB_MAX_DOOR_NAME_LEN, name);
			count++;
		}
	}

	return count;
}

bool AJB_GenerateMapConfigStub(const char[] fileMap, bool overwrite)
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "%s/%s.cfg", AJB_MAP_CONFIG_DIR, fileMap);

	if (!overwrite && FileExists(path))
	{
		return false;
	}

	char names[AJB_MAX_DOOR_NAMES][AJB_MAX_DOOR_NAME_LEN];
	int count = AJB_CollectDoorLikeNames(names, AJB_MAX_DOOR_NAMES);

	File f = OpenFile(path, "w");
	if (f == null)
	{
		LogError("[AJB] Config stub: cannot write %s.", path);
		return false;
	}

	f.WriteLine("\"AJB\"");
	f.WriteLine("{");
	f.WriteLine("\t// Auto-generated stub for %s. Edit, then: sm_ajb_settings_reload + sm_ajb_doors_reload.", fileMap);
	f.WriteLine("\t// Teleports need REAL coords. Empty origin = disabled (AJB never invents coordinates).");
	f.WriteLine("");
	f.WriteLine("\t\"teleports\"");
	f.WriteLine("\t{");
	f.WriteLine("\t\t\"freeday\"    { \"origin\" \"\"  \"angles\" \"\" }");
	f.WriteLine("\t\t\"combat_red\" { \"origin\" \"\"  \"angles\" \"\" }");
	f.WriteLine("\t\t\"combat_blu\" { \"origin\" \"\"  \"angles\" \"\" }");
	f.WriteLine("\t}");
	f.WriteLine("");
	f.WriteLine("\t\"doors\"");
	f.WriteLine("\t{");
	f.WriteLine("\t\t// nofallback 1 = use ONLY the targets below (ignore name guessing + auto-detect).");
	f.WriteLine("\t\t\"nofallback\"  \"0\"");
	f.WriteLine("\t\t\"targets\"");
	f.WriteLine("\t\t{");

	int idx = 0;

	// Active: only names that look like cells (safe to fire Open/Close/Lock on).
	f.WriteLine("\t\t\t// Detected cell-like doors (active):");
	for (int i = 0; i < count; i++)
	{
		if (AJB_NameLooksCellish(names[i]))
		{
			f.WriteLine("\t\t\t\"%d\"  \"%s\"", ++idx, names[i]);
		}
	}
	if (idx == 0)
	{
		f.WriteLine("\t\t\t// (none matched cell/jail/prison/cage — unnamed cells rely on sm_ajb_door_auto).");
	}

	// Commented: every other door-like entity — admin uncomments any that are also cells.
	f.WriteLine("");
	f.WriteLine("\t\t\t// Other door-like entities — uncomment any that are also cells:");
	for (int i = 0; i < count; i++)
	{
		if (!AJB_NameLooksCellish(names[i]))
		{
			f.WriteLine("\t\t\t// \"%d\"  \"%s\"", ++idx, names[i]);
		}
	}

	f.WriteLine("\t\t}");
	f.WriteLine("\t}");
	f.WriteLine("}");

	delete f;
	LogMessage("[AJB] Config stub written: %s (%d door target(s)).", path, count);
	return true;
}
