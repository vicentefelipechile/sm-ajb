// =========================================================================================================
// Last Request - Dodgeball
// All players become Pyros with flamethrowers; a homing critical rocket bounces between teams.
// Each airblast reflect changes the rocket's target to the opposite team and increases speed.
// =========================================================================================================

#define DB_CFG_DIR "configs/ajb/dodgeball"

// Arena boundary visuals: dual rings + vertical posts so the safe radius is readable in 3D.
#define DB_ZONE_REDRAW      0.50
#define DB_ZONE_RING_LIFE   0.55
#define DB_ZONE_RING_WIDTH  10.0
#define DB_ZONE_POST_COUNT  12
#define DB_ZONE_POST_HEIGHT 96.0
#define DB_ZONE_POST_WIDTH  5.0

bool g_bDB1v1Mode;
float g_fDBArenaRadiusSq;

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

void AJB_LR_DB_DrawZone()
{
	if (g_iDBBeam <= 0 || g_fDBArenaRadius <= 1.0)
	{
		return;
	}

	// Amber boundary — reads as "do not cross" without clashing with team colors.
	int color[4] = { 255, 160, 40, 230 };
	int halo = (g_iDBHalo > 0) ? g_iDBHalo : g_iDBBeam;
	float radius = g_fDBArenaRadius;
	float center[3];
	center[0] = g_vecDBArenaCenter[0];
	center[1] = g_vecDBArenaCenter[1];
	center[2] = g_vecDBArenaCenter[2];

	// Near-static rings (start ≈ end) mark the damage radius at ground and head height.
	TE_SetupBeamRingPoint(
		center,
		radius - 1.0,
		radius,
		g_iDBBeam,
		halo,
		0, 10,
		DB_ZONE_RING_LIFE,
		DB_ZONE_RING_WIDTH,
		0.0,
		color,
		10,
		0);
	TE_SendToAll();

	float high[3];
	high[0] = center[0];
	high[1] = center[1];
	high[2] = center[2] + DB_ZONE_POST_HEIGHT;
	TE_SetupBeamRingPoint(
		high,
		radius - 1.0,
		radius,
		g_iDBBeam,
		halo,
		0, 10,
		DB_ZONE_RING_LIFE,
		DB_ZONE_RING_WIDTH,
		0.0,
		color,
		10,
		0);
	TE_SendToAll();

	// Vertical posts around the circle so the wall is obvious from inside the arena.
	for (int i = 0; i < DB_ZONE_POST_COUNT; i++)
	{
		float angle = (float(i) / float(DB_ZONE_POST_COUNT)) * (FLOAT_PI * 2.0);
		float bottom[3];
		float top[3];
		bottom[0] = center[0] + Cosine(angle) * radius;
		bottom[1] = center[1] + Sine(angle) * radius;
		bottom[2] = center[2];
		top[0] = bottom[0];
		top[1] = bottom[1];
		top[2] = bottom[2] + DB_ZONE_POST_HEIGHT;

		TE_SetupBeamPoints(
			bottom,
			top,
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
		TE_SendToAll();
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

	float origin[3];
	GetClientAbsOrigin(client, origin);

	char map[64];
	GetCurrentMap(map, sizeof(map));

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "%s/%s.cfg", DB_CFG_DIR, map);

	KeyValues kv = new KeyValues("DodgeballMap");
	if (FileExists(path))
	{
		kv.ImportFromFile(path);
	}

	if (StrEqual(arg, "red", false))
	{
		kv.SetVector("red", origin);
		g_vecDBRedSpawn = origin;
		ReplyToCommand(client, "Set RED Dodgeball spawn to %.1f %.1f %.1f", origin[0], origin[1], origin[2]);
	}
	else if (StrEqual(arg, "blu", false))
	{
		kv.SetVector("blu", origin);
		g_vecDBBluSpawn = origin;
		ReplyToCommand(client, "Set BLU Dodgeball spawn to %.1f %.1f %.1f", origin[0], origin[1], origin[2]);
	}
	else if (StrEqual(arg, "rocket", false))
	{
		kv.SetVector("rocket", origin);
		g_vecDBRocketSpawn = origin;
		ReplyToCommand(client, "Set Rocket spawn to %.1f %.1f %.1f", origin[0], origin[1], origin[2]);
	}
	else if (StrEqual(arg, "center", false))
	{
		float radius = 1000.0;
		if (args >= 2)
		{
			char radArg[32];
			GetCmdArg(2, radArg, sizeof(radArg));
			radius = StringToFloat(radArg);
		}
		kv.SetVector("center", origin);
		kv.SetFloat("radius", radius);
		g_vecDBArenaCenter = origin;
		g_fDBArenaRadius = radius;
		g_fDBArenaRadiusSq = radius * radius;
		ReplyToCommand(client, "Set Arena Center to %.1f %.1f %.1f with Radius %.1f", origin[0], origin[1], origin[2], radius);
	}
	else
	{
		ReplyToCommand(client, "Invalid type. Use red, blu, rocket, or center.");
		delete kv;
		return Plugin_Handled;
	}

	char dir[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, dir, sizeof(dir), "%s", DB_CFG_DIR);
	if (!DirExists(dir))
	{
		CreateDirectory(dir, 511);
	}

	kv.Rewind();
	kv.ExportToFile(path);
	delete kv;

	AJB_LR_DB_LoadConfig();
	return Plugin_Handled;
}

void AJB_LR_DB_LoadConfig()
{
	g_bDBMapReady = false;

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
		kv.GetVector("red", g_vecDBRedSpawn);
		kv.GetVector("blu", g_vecDBBluSpawn);
		kv.GetVector("rocket", g_vecDBRocketSpawn);
		kv.GetVector("center", g_vecDBArenaCenter, g_vecDBRocketSpawn); // default to rocket spawn if unset
		g_fDBArenaRadius = kv.GetFloat("radius", 1500.0);
		g_fDBArenaRadiusSq = g_fDBArenaRadius * g_fDBArenaRadius;

		// Require all three spawn vectors to be non-zero.
		if (GetVectorLength(g_vecDBRedSpawn) > 0.0 && GetVectorLength(g_vecDBBluSpawn) > 0.0 && GetVectorLength(g_vecDBRocketSpawn) > 0.0)
		{
			g_bDBMapReady = true;
		}
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
	AJB_OpenCells();

	if (g_bHasCore)
	{
		AJB_SetRoundState(AJBState_SpecialDay);
		AJB_ClearWarden();
	}

	float noVel[3];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		// Teleport each player to their team's side.
		if (AJB_IsGuard(i))
		{
			TeleportEntity(i, g_vecDBBluSpawn, NULL_VECTOR, noVel);
		}
		else
		{
			TeleportEntity(i, g_vecDBRedSpawn, NULL_VECTOR, noVel);
		}

		TF2_SetPlayerClass(i, TFClass_Pyro);
		TF2_RegeneratePlayer(i);

		// Phlog (594) and Dragon's Fury (1178) cannot airblast — replace with stock.
		int primary = GetPlayerWeaponSlot(i, 0);
		if (primary != -1)
		{
			int defIdx = GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex");
			if (defIdx == 594 || defIdx == 1178)
			{
				TF2_RemoveWeaponSlot(i, 0);
				primary = GivePlayerItem(i, "tf_weapon_flamethrower");
			}
		}

		TF2_RemoveWeaponSlot(i, 1); // Remove Secondary
		TF2_RemoveWeaponSlot(i, 2); // Remove Melee

		primary = GetPlayerWeaponSlot(i, 0);
		if (primary != -1)
		{
			SetEntPropEnt(i, Prop_Send, "m_hActiveWeapon", primary);
		}
	}

	g_bDB1v1Mode = false;

	g_hDBBarrierTimer = CreateTimer(0.5, Timer_DBBarrierCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	AJB_LR_DB_StartZoneVisual();

	// Give players 3 seconds to settle before the first rocket.
	CreateTimer(3.0, Timer_DBSpawnRocket, _, TIMER_FLAG_NO_MAPCHANGE);

	AJB_LR_ChatAllQueuedApplied(chooser, "LR Applied Dodgeball");
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

	float dmg = g_cvDBBarrierDamage.FloatValue;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		float origin[3];
		GetClientAbsOrigin(i, origin);

		// 2D (XY) distance — the visual ring is horizontal, so ignore Z.
		float dx = origin[0] - g_vecDBArenaCenter[0];
		float dy = origin[1] - g_vecDBArenaCenter[1];
		float distSq = dx * dx + dy * dy;

		if (distSq > g_fDBArenaRadiusSq)
		{
			char prefix[32];
			AJB_GetPrefix(i, prefix, sizeof(prefix));
			CPrintToChat(i, "%T", "LR DB Out Of Bounds", i, prefix);
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

	// Pick a random starting team; rocket targets the opposite side.
	g_iDBRocketTeam = GetRandomInt(2, 3);
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

bool AJB_LR_DB_BothSidesAlive()
{
	bool redAlive = false;
	bool bluAlive = false;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}
		int team = GetClientTeam(i);
		if (team == 2) redAlive = true;
		else if (team == 3) bluAlive = true;
	}
	return redAlive && bluAlive;
}

void AJB_LR_DB_CheckRoundEnd()
{
	if (!g_bDodgeball)
	{
		return;
	}

	int redAlive = 0;
	int bluAlive = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			int t = GetClientTeam(i);
			if (t == 2) redAlive++;
			else if (t == 3) bluAlive++;
		}
	}

	if (redAlive == 0 || bluAlive == 0)
	{
		// Announce winner team via generic cleanup — the round-end event will clean up.
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				char prefix[32];
				AJB_GetPrefix(i, prefix, sizeof(prefix));
				if (redAlive == 0 && bluAlive > 0)
				{
					CPrintToChat(i, "%T", "LR DB Blu Wins", i, prefix);
				}
				else if (redAlive > 0 && bluAlive == 0)
				{
					CPrintToChat(i, "%T", "LR DB Red Wins", i, prefix);
				}
			}
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

Action Timer_DBRocketThink(Handle timer, int ref)
{
	if (!g_bDodgeball)
	{
		g_hDBRocketThinkTimer = null;
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
