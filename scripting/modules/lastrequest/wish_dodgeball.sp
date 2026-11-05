// =========================================================================================================
// Last Request - Dodgeball
// All players become Pyros with flamethrowers; a homing critical rocket bounces between teams.
// Each airblast reflect changes the rocket's target to the opposite team and increases speed.
// =========================================================================================================

#define DB_CFG_DIR "configs/ajb/dodgeball"
#define DB_STOCK_FLAMETHROWER 21

// Arena boundary visuals: dual rings + vertical posts so the safe radius is readable in 3D.
#define DB_ZONE_REDRAW      0.50
#define DB_ZONE_RING_LIFE   0.55
#define DB_ZONE_RING_WIDTH  10.0
#define DB_ZONE_POST_COUNT  12
#define DB_ZONE_POST_HEIGHT 2048.0
#define DB_ZONE_POST_WIDTH  5.0

bool g_bDB1v1Mode;
float g_fDBArenaRadiusSq;
bool g_bDBRedSet;
bool g_bDBBluSet;
bool g_bDBRocketSet;
bool g_bDBCenterSet;

// Precomputed arena post geometry (12 posts × bottom/top/mid) so the 0.5s redraw
// never recomputes sine/cosine — only the TE setup + send remains per tick.
float g_fDBPostBottom[DB_ZONE_POST_COUNT][3];
float g_fDBPostTop[DB_ZONE_POST_COUNT][3];
float g_fDBPostMid[DB_ZONE_POST_COUNT][3];
bool g_bDBZoneCached;

// Out-of-bounds chat spam guard: warn at most once per 2s per player.
float g_fDBLastWarn[MAXPLAYERS + 1];

void AJB_LR_DB_CacheZoneGeometry()
{
	g_bDBZoneCached = false;
	if (g_fDBArenaRadius <= 1.0)
	{
		return;
	}

	for (int i = 0; i < DB_ZONE_POST_COUNT; i++)
	{
		float angle = (float(i) / float(DB_ZONE_POST_COUNT)) * (FLOAT_PI * 2.0);
		float cosA = Cosine(angle);
		float sinA = Sine(angle);

		g_fDBPostBottom[i][0] = g_vecDBArenaCenter[0] + cosA * g_fDBArenaRadius;
		g_fDBPostBottom[i][1] = g_vecDBArenaCenter[1] + sinA * g_fDBArenaRadius;
		g_fDBPostBottom[i][2] = g_vecDBArenaCenter[2];

		g_fDBPostTop[i][0] = g_fDBPostBottom[i][0];
		g_fDBPostTop[i][1] = g_fDBPostBottom[i][1];
		g_fDBPostTop[i][2] = g_fDBPostBottom[i][2] + DB_ZONE_POST_HEIGHT;

		g_fDBPostMid[i][0] = g_fDBPostBottom[i][0];
		g_fDBPostMid[i][1] = g_fDBPostBottom[i][1];
		g_fDBPostMid[i][2] = g_fDBPostBottom[i][2] + (DB_ZONE_POST_HEIGHT / 2.0);
	}

	g_bDBZoneCached = true;
}

void AJB_LR_KillDBTimers()
{
	if (g_hDBBarrierTimer != null)
	{
		delete g_hDBBarrierTimer;
		g_hDBBarrierTimer = null;
	}
	if (g_hDBRocketThinkTimer != null)
	{
		delete g_hDBRocketThinkTimer;
		g_hDBRocketThinkTimer = null;
	}
	if (g_hDBZoneTimer != null)
	{
		delete g_hDBZoneTimer;
		g_hDBZoneTimer = null;
	}
	if (g_hDBAmmoTimer != null)
	{
		delete g_hDBAmmoTimer;
		g_hDBAmmoTimer = null;
	}
	if (g_iDBRocketEnt != -1 && IsValidEntity(g_iDBRocketEnt))
	{
		AcceptEntityInput(g_iDBRocketEnt, "Kill");
	}
	g_iDBRocketEnt = -1;

	// Stop 1v1 music if it was playing
	if (g_bDB1v1Mode)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				StopSound(i, SNDCHAN_STATIC, "ui/gamestartup1.mp3");
			}
		}
		g_bDB1v1Mode = false;
	}
}

// ---------------------------------------------------------------------------------------------------------
// Arena zone visualization
// ---------------------------------------------------------------------------------------------------------

void AJB_LR_DB_PrecacheVisuals()
{
	g_iDBBeam = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iDBHalo = PrecacheModel("materials/sprites/halo01.vmt");
	if (g_iDBBeam <= 0)
	{
		g_iDBBeam = PrecacheModel("sprites/laserbeam.spr");
	}
}

void AJB_LR_DB_StartZoneVisual()
{
	if (g_hDBZoneTimer != null)
	{
		delete g_hDBZoneTimer;
		g_hDBZoneTimer = null;
	}

	// Cache the post geometry once — the arena does not move mid-round.
	AJB_LR_DB_CacheZoneGeometry();

	// Draw immediately so the boundary is visible before the first rocket spawns.
	AJB_LR_DB_DrawZone();
	g_hDBZoneTimer = CreateTimer(DB_ZONE_REDRAW, Timer_DBZoneVisual, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_DBZoneVisual(Handle timer)
{
	if (!g_bDodgeball)
	{
		g_hDBZoneTimer = null;
		return Plugin_Stop;
	}

	AJB_LR_DB_DrawZone();
	return Plugin_Continue;
}

void AJB_LR_DB_DrawZone(int client = 0)
{
	if (g_iDBBeam <= 0 || !g_bDBZoneCached)
	{
		return;
	}

	// Amber boundary — reads as "do not cross" without clashing with team colors.
	int color[4] = { 255, 160, 40, 230 };
	int halo = (g_iDBHalo > 0) ? g_iDBHalo : g_iDBBeam;

	// Vertical posts and horizontal connecting beams around the circle (geometry cached).
	for (int i = 0; i < DB_ZONE_POST_COUNT; i++)
	{
		// Vertical post
		TE_SetupBeamPoints(
			g_fDBPostBottom[i],
			g_fDBPostTop[i],
			g_iDBBeam,
			halo,
			0, 10,
			DB_ZONE_RING_LIFE,
			DB_ZONE_POST_WIDTH,
			DB_ZONE_POST_WIDTH,
			1,
			0.0,
			color,
			10);
		if (client > 0) TE_SendToClient(client);
		else TE_SendToAll();

		// Horizontal bottom beam
		TE_SetupBeamPoints(
			g_fDBPostBottom[i],
			g_fDBPostBottom[(i + 1) % DB_ZONE_POST_COUNT],
			g_iDBBeam,
			halo,
			0, 10,
			DB_ZONE_RING_LIFE,
			DB_ZONE_RING_WIDTH,
			DB_ZONE_RING_WIDTH,
			1,
			0.0,
			color,
			10);
		if (client > 0) TE_SendToClient(client);
		else TE_SendToAll();

		// Horizontal middle beam
		TE_SetupBeamPoints(
			g_fDBPostMid[i],
			g_fDBPostMid[(i + 1) % DB_ZONE_POST_COUNT],
			g_iDBBeam,
			halo,
			0, 10,
			DB_ZONE_RING_LIFE,
			DB_ZONE_RING_WIDTH,
			DB_ZONE_RING_WIDTH,
			1,
			0.0,
			color,
			10);
		if (client > 0) TE_SendToClient(client);
		else TE_SendToAll();

		// Horizontal top beam
		TE_SetupBeamPoints(
			g_fDBPostTop[i],
			g_fDBPostTop[(i + 1) % DB_ZONE_POST_COUNT],
			g_iDBBeam,
			halo,
			0, 10,
			DB_ZONE_RING_LIFE,
			DB_ZONE_RING_WIDTH,
			DB_ZONE_RING_WIDTH,
			1,
			0.0,
			color,
			10);
		if (client > 0) TE_SendToClient(client);
		else TE_SendToAll();
	}
}

// ---------------------------------------------------------------------------------------------------------
// Map Configuration
// ---------------------------------------------------------------------------------------------------------

public Action Cmd_SetDBSpawn(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "In-game only.");
		return Plugin_Handled;
	}

	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_ajb_db_setspawn <red|blu|rocket|center> [radius]");
		return Plugin_Handled;
	}

	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	for (int i = 0; arg[i] != '\0'; i++) arg[i] = CharToLower(arg[i]);
	if (!StrEqual(arg, "red") && !StrEqual(arg, "blu") && !StrEqual(arg, "rocket") && !StrEqual(arg, "center"))
	{
		ReplyToCommand(client, "Invalid type. Use red, blu, rocket, or center.");
		return Plugin_Handled;
	}

	float radius = -1.0;
	if (StrEqual(arg, "center") && args >= 2)
	{
		char radArg[32];
		GetCmdArg(2, radArg, sizeof(radArg));
		if (StringToFloatEx(radArg, radius) != strlen(radArg) || !AJB_DB_IsRadiusValid(radius))
		{
			AJB_Chat(client, "DB Invalid Radius");
			return Plugin_Handled;
		}
	}

	float origin[3];
	GetClientAbsOrigin(client, origin);
	if (StrEqual(arg, "rocket")) GetClientEyePosition(client, origin);
	AJB_LR_DB_SavePoint(client, arg, origin, radius);
	return Plugin_Handled;
}

bool AJB_LR_DB_SavePoint(int client, const char[] key, const float origin[3], float radius = -1.0)
{
	if (g_bDodgeball)
	{
		AJB_Chat(client, "DB Round Active");
		return false;
	}
	if (!StrEqual(key, "radius") && !IsPlayerAlive(client))
	{
		AJB_Chat(client, "DB Alive Required");
		return false;
	}
	if (StrEqual(key, "rocket") && !AJB_LR_DB_RocketSpaceClear(origin))
	{
		AJB_Chat(client, "DB Rocket Blocked");
		return false;
	}

	char map[64], path[PLATFORM_MAX_PATH], dir[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	BuildPath(Path_SM, path, sizeof(path), "%s/%s.cfg", DB_CFG_DIR, map);
	BuildPath(Path_SM, dir, sizeof(dir), "%s", DB_CFG_DIR);
	KeyValues kv = new KeyValues("DodgeballMap");
	if (FileExists(path) && !kv.ImportFromFile(path))
	{
		LogError("[AJB-LR] Refusing to overwrite unreadable Dodgeball config: %s", path);
		delete kv;
		AJB_Chat(client, "DB Save Failed");
		return false;
	}

	if (!StrEqual(key, "radius")) kv.SetVector(key, origin);
	if (radius >= 0.0) kv.SetFloat("radius", radius);

	// Replace only after a complete export so a write failure leaves the old config intact.
	char temporary[PLATFORM_MAX_PATH];
	Format(temporary, sizeof(temporary), "%s.tmp", path);
	bool saved = (DirExists(dir) || CreateDirectory(dir, 511))
		&& kv.ExportToFile(temporary) && RenameFile(path, temporary);
	delete kv;
	if (!saved)
	{
		LogError("[AJB-LR] Failed to save Dodgeball config: %s", path);
		AJB_Chat(client, "DB Save Failed");
		return false;
	}

	AJB_LR_DB_LoadConfig();
	AJB_Chat(client, "DB Saved");
	LogAction(client, -1, "\"%L\" updated Dodgeball %s on %s (%.1f %.1f %.1f, radius %.1f)",
		client, key, map, origin[0], origin[1], origin[2], g_fDBArenaRadius);
	return true;
}

void AJB_LR_DB_LoadConfig()
{
	g_bDBMapReady = false;
	g_bDBRedSet = false;
	g_bDBBluSet = false;
	g_bDBRocketSet = false;
	g_bDBCenterSet = false;
	g_vecDBRedSpawn = NULL_VECTOR;
	g_vecDBBluSpawn = NULL_VECTOR;
	g_vecDBRocketSpawn = NULL_VECTOR;
	g_vecDBArenaCenter = NULL_VECTOR;
	g_fDBArenaRadius = DB_RADIUS_DEFAULT;
	g_fDBArenaRadiusSq = g_fDBArenaRadius * g_fDBArenaRadius;
	g_bDBZoneCached = false;

	char map[64];
	GetCurrentMap(map, sizeof(map));

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "%s/%s.cfg", DB_CFG_DIR, map);

	if (!FileExists(path))
	{
		return;
	}

	KeyValues kv = new KeyValues("DodgeballMap");
	if (kv.ImportFromFile(path))
	{
		g_bDBRedSet = kv.GetDataType("red") != KvData_None;
		g_bDBBluSet = kv.GetDataType("blu") != KvData_None;
		g_bDBRocketSet = kv.GetDataType("rocket") != KvData_None;
		g_bDBCenterSet = kv.GetDataType("center") != KvData_None;
		kv.GetVector("red", g_vecDBRedSpawn);
		kv.GetVector("blu", g_vecDBBluSpawn);
		kv.GetVector("rocket", g_vecDBRocketSpawn);
		kv.GetVector("center", g_vecDBArenaCenter, g_vecDBRocketSpawn); // default to rocket spawn if unset
		g_fDBArenaRadius = kv.GetFloat("radius", DB_RADIUS_DEFAULT);
		if (!AJB_DB_IsRadiusValid(g_fDBArenaRadius))
		{
			LogError("[AJB-LR] Invalid Dodgeball radius in %s; using default.", path);
			g_fDBArenaRadius = DB_RADIUS_DEFAULT;
		}
		g_fDBArenaRadiusSq = g_fDBArenaRadius * g_fDBArenaRadius;

		// The map origin is a valid spawn; missing keys, not zero vectors, mean incomplete setup.
		g_bDBMapReady = g_bDBRedSet && g_bDBBluSet && g_bDBRocketSet;
		if (g_bDBCenterSet || g_bDBRocketSet) AJB_LR_DB_CacheZoneGeometry();
	}
	else
	{
		LogError("[AJB-LR] Failed to read Dodgeball config: %s", path);
	}
	delete kv;
}

// ---------------------------------------------------------------------------------------------------------
// Game Logic
// ---------------------------------------------------------------------------------------------------------

void AJB_LR_DoDodgeball(int prisoner)
{
	if (!g_bDBMapReady)
	{
		// No config for this map — gracefully fall back to refusing and reopen menu.
		char prefix[32];
		AJB_GetPrefix(prisoner, prefix, sizeof(prefix));
		CPrintToChat(prisoner, "%T", "LR DB No Config", prisoner, prefix);
		
		AJB_LR_ShowWishMenu(prisoner);
		return;
	}
	AJB_LR_QueueWish(prisoner, LRWish_Dodgeball, "LR Chose Dodgeball");
}

void AJB_LR_ApplyDodgeball(const char[] chooser)
{
	g_bDodgeball = true;

	if (g_bHasCore)
	{
		// Combat day also cancels queued JB ratio bounces before they can respawn players at cells.
		AJB_BeginCombatDay();
		AJB_SetupSpecialDay();
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			RequestFrame(Frame_DBPreparePlayer, GetClientUserId(i));
		}
	}

	g_bDB1v1Mode = false;

	for (int i = 1; i <= MaxClients; i++)
	{
		g_fDBLastWarn[i] = 0.0;
	}

	// Ammo top-up is separate from the homing think (which must stay fast).
	if (g_hDBAmmoTimer != null)
	{
		delete g_hDBAmmoTimer;
		g_hDBAmmoTimer = null;
	}
	g_hDBAmmoTimer = CreateTimer(0.5, Timer_DBAmmo, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	g_hDBBarrierTimer = CreateTimer(0.5, Timer_DBBarrierCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	AJB_LR_DB_StartZoneVisual();

	// Give players 3 seconds to settle before the first rocket.
	CreateTimer(3.0, Timer_DBSpawnRocket, _, TIMER_FLAG_NO_MAPCHANGE);

	AJB_LR_ChatAllQueuedApplied(chooser, "LR Applied Dodgeball");
}

void Frame_DBPreparePlayer(int userid)
{
	if (!g_bDodgeball || !AJB_LR_CanRun())
	{
		return;
	}

	int client = GetClientOfUserId(userid);
	if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) < AJB_TEAM_RED)
	{
		return;
	}

	TF2_SetPlayerClass(client, TFClass_Pyro);
	TF2_RegeneratePlayer(client);

	// Regeneration and respawns must finish before the arena teleport.
	float noVel[3];
	if (AJB_IsGuard(client))
	{
		TeleportEntity(client, g_vecDBBluSpawn, NULL_VECTOR, noVel);
	}
	else
	{
		TeleportEntity(client, g_vecDBRedSpawn, NULL_VECTOR, noVel);
	}

	int primary = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	int defIndex = primary != -1 ? GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex") : -1;
	// Phlog and Dragon's Fury cannot airblast; a missing primary needs the same fallback.
	if (primary == -1 || defIndex == 594 || defIndex == 1178)
	{
		TF2_RemoveWeaponSlot(client, TFWeaponSlot_Primary);
		primary = AJB_GiveStockWeapon(client, "tf_weapon_flamethrower", DB_STOCK_FLAMETHROWER);
	}

	// Verify the fallback really equipped before stripping the player's remaining weapons.
	if (primary == -1 || GetPlayerWeaponSlot(client, TFWeaponSlot_Primary) != primary)
	{
		LogError("[AJB-LR] Dodgeball primary equip failed for client %d.", client);
		return;
	}

	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Secondary);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
	SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", primary);
	SetEntProp(client, Prop_Send, "m_iAmmo", 200, _, 1);
}

// ---------------------------------------------------------------------------------------------------------
// Barrier enforcement
// ---------------------------------------------------------------------------------------------------------

Action Timer_DBBarrierCheck(Handle timer)
{
	if (!g_bDodgeball)
	{
		g_hDBBarrierTimer = null;
		return Plugin_Stop;
	}
	if (g_fDBArenaRadius <= 1.0) return Plugin_Continue;

	float dmg = g_cvDBBarrierDamage.FloatValue;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		float origin[3];
		GetClientAbsOrigin(i, origin);

		if (AJB_DB_IsOutsideArena(origin, g_vecDBArenaCenter, g_fDBArenaRadiusSq))
		{
			// Warn at most every 2s so an AFK player does not spam chat every tick.
			if (GetGameTime() - g_fDBLastWarn[i] > 2.0)
			{
				g_fDBLastWarn[i] = GetGameTime();
				char prefix[32];
				AJB_GetPrefix(i, prefix, sizeof(prefix));
				CPrintToChat(i, "%T", "LR DB Out Of Bounds", i, prefix);
			}
			SDKHooks_TakeDamage(i, 0, 0, dmg, DMG_SHOCK, -1, NULL_VECTOR, g_vecDBArenaCenter);
		}
	}
	return Plugin_Continue;
}

// ---------------------------------------------------------------------------------------------------------
// Rocket spawning
// ---------------------------------------------------------------------------------------------------------

Action Timer_DBSpawnRocket(Handle timer)
{
	if (!g_bDodgeball)
	{
		return Plugin_Stop;
	}

	// Only spawn if both sides still have living players.
	if (!AJB_LR_DB_BothSidesAlive())
	{
		AJB_LR_DB_CheckRoundEnd();
		return Plugin_Stop;
	}

	AJB_LR_DB_SpawnRocket();
	return Plugin_Stop;
}

void AJB_LR_DB_SpawnRocket()
{
	if (g_iDBRocketEnt != -1 && IsValidEntity(g_iDBRocketEnt))
	{
		AcceptEntityInput(g_iDBRocketEnt, "Kill");
		g_iDBRocketEnt = -1;
	}

	g_iDBRocketEnt = CreateEntityByName("tf_projectile_rocket");
	if (g_iDBRocketEnt == -1)
	{
		return;
	}

	// Classic dodgeball alternates the targeted side: each new rocket flips the team of
	// the previous one (red → blue → red...), and the target is always the opposite team.
	// Only the very first rocket of a round coin-flips its starting team.
	if (g_iDBRocketTeam != 2 && g_iDBRocketTeam != 3)
	{
		g_iDBRocketTeam = GetRandomInt(2, 3);
	}
	else
	{
		g_iDBRocketTeam = (g_iDBRocketTeam == 2) ? 3 : 2;
	}
	AJB_LR_DB_SetTarget(AJB_LR_DB_GetRandomTarget(g_iDBRocketTeam == 2 ? 3 : 2));
	g_fDBRocketSpeed = g_cvDBBaseSpeed.FloatValue;

	SetEntPropEnt(g_iDBRocketEnt, Prop_Send, "m_hOwnerEntity", 0);
	SetEntProp(g_iDBRocketEnt, Prop_Send, "m_iTeamNum", g_iDBRocketTeam);
	SetEntProp(g_iDBRocketEnt, Prop_Send, "m_bCritical", 1);
	SetEntProp(g_iDBRocketEnt, Prop_Send, "m_iDeflected", 1);

	float vAngles[3];
	float initialVel[3], fDirection[3];

	if (g_iDBRocketTarget > 0 && IsClientInGame(g_iDBRocketTarget) && IsPlayerAlive(g_iDBRocketTarget))
	{
		float targetPos[3];
		GetClientAbsOrigin(g_iDBRocketTarget, targetPos);
		targetPos[2] += 40.0; // aim at chest height
		MakeVectorFromPoints(g_vecDBRocketSpawn, targetPos, fDirection);
		NormalizeVector(fDirection, fDirection);
		GetVectorAngles(fDirection, vAngles);
	}
	else
	{
		vAngles[0] = 0.0;
		vAngles[1] = 0.0;
		vAngles[2] = 0.0;
		GetAngleVectors(vAngles, fDirection, NULL_VECTOR, NULL_VECTOR);
	}
	initialVel[0] = fDirection[0] * g_fDBRocketSpeed;
	initialVel[1] = fDirection[1] * g_fDBRocketSpeed;
	initialVel[2] = fDirection[2] * g_fDBRocketSpeed;

	TeleportEntity(g_iDBRocketEnt, g_vecDBRocketSpawn, vAngles, initialVel);
	DispatchSpawn(g_iDBRocketEnt);

	// Default base damage (90, crits for 270) is enough to kill a 175 HP Pyro.
	// We do not set m_flDamage because the property doesn't exist on tf_projectile_rocket.

	SDKHook(g_iDBRocketEnt, SDKHook_Touch, DB_RocketTouch);

	if (g_hDBRocketThinkTimer != null)
	{
		delete g_hDBRocketThinkTimer;
	}
	g_hDBRocketThinkTimer = CreateTimer(0.1, Timer_DBRocketThink, EntIndexToEntRef(g_iDBRocketEnt), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

// ---------------------------------------------------------------------------------------------------------
// Target helpers
// ---------------------------------------------------------------------------------------------------------

int AJB_LR_DB_GetRandomTarget(int team)
{
	int targets[MAXPLAYERS];
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == team)
		{
			targets[count++] = i;
		}
	}
	if (count == 0)
	{
		return -1;
	}
	return targets[GetRandomInt(0, count - 1)];
}

void AJB_LR_DB_SetTarget(int newTarget)
{
	if (newTarget > 0 && newTarget != g_iDBRocketTarget && IsClientInGame(newTarget))
	{
		EmitSoundToClient(newTarget, "weapons/sentry_spot.wav");
		PrintCenterText(newTarget, "ROCKET TARGETING YOU!");
	}
	g_iDBRocketTarget = newTarget;
}

// One alive-per-team count, shared by the both-sides gate and the round-end check.
void AJB_LR_DB_CountAliveByTeam(int &red, int &blu)
{
	red = 0;
	blu = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}
		int team = GetClientTeam(i);
		if (team == 2) red++;
		else if (team == 3) blu++;
	}
}

bool AJB_LR_DB_BothSidesAlive()
{
	int red;
	int blu;
	AJB_LR_DB_CountAliveByTeam(red, blu);
	return red > 0 && blu > 0;
}

void AJB_LR_DB_CheckRoundEnd()
{
	if (!g_bDodgeball)
	{
		return;
	}

	int redAlive;
	int bluAlive;
	AJB_LR_DB_CountAliveByTeam(redAlive, bluAlive);

	if (redAlive == 0 || bluAlive == 0)
	{
		// Announce winner team via generic cleanup — the round-end event will clean up.
		if (redAlive == 0 && bluAlive > 0)
		{
			AJB_ChatAll("LR DB Blu Wins");
		}
		else if (redAlive > 0 && bluAlive == 0)
		{
			AJB_ChatAll("LR DB Red Wins");
		}
		// Cleanup without an extra "aborted" message since this is a natural end.
		g_bDodgeball = false;
		AJB_LR_KillDBTimers();
		return;
	}

	// 1v1 Mode Check
	if (!g_bDB1v1Mode && redAlive == 1 && bluAlive == 1)
	{
		g_bDB1v1Mode = true;
		g_fDBRocketSpeed += 400.0; // Sudden speed boost
		
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				EmitSoundToClient(i, "ui/gamestartup1.mp3", SOUND_FROM_PLAYER, SNDCHAN_STATIC);
				PrintCenterText(i, "1 VS 1 - SUDDEN DEATH");
			}
			// Give the final two players 1800 health (approx 3 crit rocket lives)
			if (IsClientInGame(i) && IsPlayerAlive(i))
			{
				SetEntityHealth(i, 1800);
			}
		}
	}
}

// ---------------------------------------------------------------------------------------------------------
// Rocket touch / death
// ---------------------------------------------------------------------------------------------------------

Action DB_RocketTouch(int entity, int other)
{
	if (!g_bDodgeball)
	{
		g_iDBRocketEnt = -1;
		if (g_hDBRocketThinkTimer != null)
		{
			delete g_hDBRocketThinkTimer;
			g_hDBRocketThinkTimer = null;
		}
		return Plugin_Continue;
	}

	// Player hit — explode, deal damage, schedule next rocket.
	if (other >= 1 && other <= MaxClients && IsClientInGame(other) && IsPlayerAlive(other))
	{
		g_iDBRocketEnt = -1;
		if (g_hDBRocketThinkTimer != null)
		{
			delete g_hDBRocketThinkTimer;
			g_hDBRocketThinkTimer = null;
		}

		int attacker = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if (attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker))
		{
			attacker = 0;
		}
		SDKHooks_TakeDamage(other, entity, attacker, 270.0, DMG_BLAST | DMG_ALWAYSGIB);

		CreateTimer(1.0, Timer_DBSpawnRocket, _, TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Continue;
	}

	// World/brush hit — bounce the rocket instead of exploding.
	float rocketPos[3], velocity[3];
	GetEntPropVector(entity, Prop_Data, "m_vecOrigin", rocketPos);
	GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", velocity);

	// Trace a short ray in the direction of travel to find the surface normal.
	float endPos[3];
	float dir[3];
	dir = velocity;
	NormalizeVector(dir, dir);
	endPos[0] = rocketPos[0] + dir[0] * 64.0;
	endPos[1] = rocketPos[1] + dir[1] * 64.0;
	endPos[2] = rocketPos[2] + dir[2] * 64.0;

	Handle trace = TR_TraceRayFilterEx(rocketPos, endPos, MASK_SOLID, RayType_EndPoint, DB_TraceFilter_NoPlayers, entity);

	float normal[3];
	if (TR_DidHit(trace))
	{
		TR_GetPlaneNormal(trace, normal);
	}
	else
	{
		// Fallback: assume floor bounce (straight up).
		normal[0] = 0.0;
		normal[1] = 0.0;
		normal[2] = 1.0;
	}
	delete trace;

	// Reflect: v' = v - 2(v·n)n
	float dot = GetVectorDotProduct(velocity, normal);
	float reflected[3];
	reflected[0] = velocity[0] - 2.0 * dot * normal[0];
	reflected[1] = velocity[1] - 2.0 * dot * normal[1];
	reflected[2] = velocity[2] - 2.0 * dot * normal[2];

	// Nudge the rocket slightly off the surface so it doesn't re-trigger Touch.
	float nudge[3];
	nudge[0] = rocketPos[0] + normal[0] * 2.0;
	nudge[1] = rocketPos[1] + normal[1] * 2.0;
	nudge[2] = rocketPos[2] + normal[2] * 2.0;

	float angles[3];
	GetVectorAngles(reflected, angles);
	NormalizeVector(reflected, reflected);
	ScaleVector(reflected, g_fDBRocketSpeed);

	TeleportEntity(entity, nudge, angles, reflected);

	return Plugin_Handled;
}

bool DB_TraceFilter_NoPlayers(int entity, int contentsMask, any data)
{
	// Skip players and the rocket itself.
	if (entity >= 1 && entity <= MaxClients)
	{
		return false;
	}
	if (entity == data)
	{
		return false;
	}
	return true;
}

// Called via RequestFrame after a player death so the death state is settled.
void Frame_DBCheckRoundEnd(any data)
{
	AJB_LR_DB_CheckRoundEnd();
}

// ---------------------------------------------------------------------------------------------------------
// Homing think — runs every 0.1 s per rocket
// ---------------------------------------------------------------------------------------------------------

// =========================================================================================================
// Ammo maintenance — every 0.5s (the homing think at 0.1s must stay light).
// =========================================================================================================

Action Timer_DBAmmo(Handle timer)
{
	if (!g_bDodgeball)
	{
		g_hDBAmmoTimer = null;
		return Plugin_Stop;
	}

	// Give all living players infinite primary ammo natively.
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			if (GetEntProp(i, Prop_Send, "m_iAmmo", _, 1) < 100)
			{
				SetEntProp(i, Prop_Send, "m_iAmmo", 200, _, 1);
			}
		}
	}

	return Plugin_Continue;
}

// =========================================================================================================
// Homing think — runs every 0.1 s per rocket
// =========================================================================================================

Action Timer_DBRocketThink(Handle timer, int ref)
{
	if (!g_bDodgeball)
	{
		g_hDBRocketThinkTimer = null;
		return Plugin_Stop;
	}

	int ent = EntRefToEntIndex(ref);
	if (ent == INVALID_ENT_REFERENCE)
	{
		g_hDBRocketThinkTimer = null;
		g_iDBRocketEnt = -1;
		return Plugin_Stop;
	}

	// Detect airblast reflect: m_hOwnerEntity changes to the deflecting player.
	int owner = GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity");
	if (owner > 0 && owner <= MaxClients && IsClientInGame(owner))
	{
		int ownerTeam = GetClientTeam(owner);
		if (ownerTeam != g_iDBRocketTeam)
		{
			// Reflected — swap allegiance, increase speed, pick new target on opposite side.
			g_iDBRocketTeam = ownerTeam;
			SetEntProp(ent, Prop_Send, "m_iTeamNum", g_iDBRocketTeam);
			g_fDBRocketSpeed += g_cvDBSpeedInc.FloatValue;
			AJB_LR_DB_SetTarget(AJB_LR_DB_GetRandomTarget(g_iDBRocketTeam == 2 ? 3 : 2));
		}
	}

	// Revalidate target each tick in case the current target died.
	if (g_iDBRocketTarget <= 0 || !IsClientInGame(g_iDBRocketTarget) || !IsPlayerAlive(g_iDBRocketTarget))
	{
		AJB_LR_DB_SetTarget(AJB_LR_DB_GetRandomTarget(g_iDBRocketTeam == 2 ? 3 : 2));
	}

	if (g_iDBRocketTarget <= 0)
	{
		// No valid target — the opposing team may be dead; let the touch handler sort it out.
		return Plugin_Continue;
	}

	float rocketPos[3], targetPos[3], desiredDir[3], rocketAng[3];
	GetEntPropVector(ent, Prop_Data, "m_vecOrigin", rocketPos);
	GetClientAbsOrigin(g_iDBRocketTarget, targetPos);
	targetPos[2] += 40.0; // aim at chest height

	// Direction vector from rocket to target.
	MakeVectorFromPoints(rocketPos, targetPos, desiredDir);
	NormalizeVector(desiredDir, desiredDir);

	// Blend current direction with desired direction using turn rate (0–1 range per tick).
	// turn rate 0.08 at 0.1 s intervals gives smooth but responsive steering.
	float turnRate = g_cvDBTurnRate.FloatValue;
	float currentVel[3];
	GetEntPropVector(ent, Prop_Data, "m_vecAbsVelocity", currentVel);
	float currentSpeed = GetVectorLength(currentVel);

	float blendDir[3];
	if (currentSpeed > 1.0)
	{
		// Normalise current velocity for blending.
		float normCurrent[3];
		normCurrent = currentVel;
		NormalizeVector(normCurrent, normCurrent);

		// Linear interpolation: blendDir = normCurrent * (1 - rate) + desiredDir * rate
		blendDir[0] = normCurrent[0] * (1.0 - turnRate) + desiredDir[0] * turnRate;
		blendDir[1] = normCurrent[1] * (1.0 - turnRate) + desiredDir[1] * turnRate;
		blendDir[2] = normCurrent[2] * (1.0 - turnRate) + desiredDir[2] * turnRate;
		NormalizeVector(blendDir, blendDir);
	}
	else
	{
		blendDir = desiredDir;
	}

	GetVectorAngles(blendDir, rocketAng);
	ScaleVector(blendDir, g_fDBRocketSpeed);

	SetEntPropVector(ent, Prop_Data, "m_vecAbsVelocity", blendDir);
	SetEntPropVector(ent, Prop_Send, "m_angRotation", rocketAng);

	return Plugin_Continue;
}
