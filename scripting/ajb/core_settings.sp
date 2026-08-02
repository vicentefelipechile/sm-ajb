// =========================================================================================================
// configs/ajb/settings.cfg — teleports + freeday policy
// =========================================================================================================

#define AJB_SETTINGS_FILE  "configs/ajb/settings.cfg"

#define AJB_MAX_MAP_PREFIXES  16

bool g_bFreedayWardenOnlyDamage = true;
bool g_bFreedayTrail = true;

// Map name prefixes that enable AJB (empty list = never by prefix; sm_ajb_force still overrides).
char g_szMapPrefixes[AJB_MAX_MAP_PREFIXES][AJB_MAX_MAP_PREFIX_LEN];
int g_iMapPrefixCount;

// Combat day = War Day / Class Warfare (stock sentries, full guns, death ammo, no warden).
bool g_bCombatDay;
// Cosmetic “freeday for all”: open cells, no warden, no personal invuln.
bool g_bFreedayAllCosmetic;

float g_flTpFreedayOrigin[3];
float g_flTpFreedayAngles[3];
bool g_bTpFreeday;

float g_flTpCombatRedOrigin[3];
float g_flTpCombatRedAngles[3];
bool g_bTpCombatRed;

float g_flTpCombatBluOrigin[3];
float g_flTpCombatBluAngles[3];
bool g_bTpCombatBlu;

int g_iFreedayBeamSprite = -1;
Handle g_hPlayerFxTimer;

// Per-player visual FX: freeday trail + glow (green) and rebel glow (orange).
// Trail anchor is world-space (NOT parented) so the owner sees it in 3rd person.
// Glow sprites are parented to the player so Source moves them every frame (no timer jitter).
// One contiguous struct per client (cache locality) that also caches the last anchored position,
// so a still player skips the per-tick TeleportEntity call on the trail anchor.
enum struct PlayerFx
{
	int anchor;       // info_target the beam-follow rides (freeday trail)
	int glow;         // env_sprite freeday marker (green)
	int rebelGlow;    // env_sprite rebel marker (orange)
	float lastMid[3]; // last position the anchor was teleported to
	bool hasMid;      // lastMid is valid (entities have been placed at least once)
}

PlayerFx g_PlayerFx[MAXPLAYERS + 1];

// Squared move threshold: below this the anchor is already close enough, skip the teleport.
#define AJB_FREEDAY_MOVE_SQR  4.0

void AJB_Settings_OnPluginStart()
{
	RegAdminCmd("sm_ajb_settings_reload", Command_SettingsReload, ADMFLAG_CONFIG, "Reload configs/ajb/settings.cfg");
	AJB_Settings_Load();
}

void AJB_Settings_OnMapStart()
{
	g_hPlayerFxTimer = null;
	g_iFreedayBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	PrecacheModel("materials/sprites/glow01.vmt", true);
	AJB_Settings_Load();
	AJB_Settings_ClearRoundModes();
}

void AJB_Settings_ClearRoundModes()
{
	g_bCombatDay = false;
	g_bFreedayAllCosmetic = false;
	AJB_PlayerFx_StopTimer();
	for (int i = 1; i <= MaxClients; i++)
	{
		AJB_Freeday_KillTrailFx(i);
		AJB_Rebel_KillGlow(i);
	}
}

Action Command_SettingsReload(int client, int args)
{
	AJB_Settings_Load();
	AJB_RefreshModeActive();
	AJB_Reply(client, "Settings Reloaded");
	return Plugin_Handled;
}

void AJB_Settings_ClearTeleports()
{
	g_bTpFreeday = false;
	g_bTpCombatRed = false;
	g_bTpCombatBlu = false;
	ZeroVector(g_flTpFreedayOrigin);
	ZeroVector(g_flTpFreedayAngles);
	ZeroVector(g_flTpCombatRedOrigin);
	ZeroVector(g_flTpCombatRedAngles);
	ZeroVector(g_flTpCombatBluOrigin);
	ZeroVector(g_flTpCombatBluAngles);
}

// Global policy only (not map teleports). Teleports: configs/ajb/maps/<map>.cfg
void AJB_Settings_Load()
{
	g_bFreedayWardenOnlyDamage = true;
	g_bFreedayTrail = true;
	AJB_Settings_SetDefaultPrefixes();

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), AJB_SETTINGS_FILE);

	if (!FileExists(path))
	{
		LogMessage("[AJB] %s missing — using defaults.", AJB_SETTINGS_FILE);
		return;
	}

	KeyValues kv = new KeyValues("Settings");
	if (!kv.ImportFromFile(path))
	{
		LogError("[AJB] Failed to parse %s.", path);
		delete kv;
		return;
	}

	g_bFreedayWardenOnlyDamage = kv.GetNum("freeday_warden_only_damage", 1) != 0;
	g_bFreedayTrail = kv.GetNum("freeday_trail", 1) != 0;
	AJB_Settings_LoadMapPrefixes(kv);
	delete kv;

	LogMessage("[AJB] settings.cfg: warden_only_dmg=%d trail=%d prefixes=%d (teleports are per-map).",
		g_bFreedayWardenOnlyDamage, g_bFreedayTrail, g_iMapPrefixCount);
}

void AJB_Settings_SetDefaultPrefixes()
{
	g_iMapPrefixCount = 1;
	strcopy(g_szMapPrefixes[0], AJB_MAX_MAP_PREFIX_LEN, "jb_");
}

// A missing key keeps the default; a present-but-empty value disables prefix matching (force still overrides).
void AJB_Settings_LoadMapPrefixes(KeyValues kv)
{
	char raw[AJB_MAX_MAP_PREFIX_LEN * AJB_MAX_MAP_PREFIXES];
	// KvGetDataType tells absent (defaults) apart from empty (disable).
	if (kv.GetDataType("map_prefixes") == KvData_None)
	{
		return;
	}
	kv.GetString("map_prefixes", raw, sizeof(raw), "");

	g_iMapPrefixCount = 0;

	char parts[AJB_MAX_MAP_PREFIXES][AJB_MAX_MAP_PREFIX_LEN];
	int n = ExplodeString(raw, " ", parts, AJB_MAX_MAP_PREFIXES, AJB_MAX_MAP_PREFIX_LEN);
	for (int i = 0; i < n; i++)
	{
		TrimString(parts[i]);
		if (parts[i][0] == '\0')
		{
			continue;
		}

		strcopy(g_szMapPrefixes[g_iMapPrefixCount], AJB_MAX_MAP_PREFIX_LEN, parts[i]);
		g_iMapPrefixCount++;
	}
}

bool AJB_MapMatchesPrefix(const char[] map)
{
	char shortMap[PLATFORM_MAX_PATH];
	strcopy(shortMap, sizeof(shortMap), map);

	int slash = FindCharInString(shortMap, '/', true);
	if (slash != -1)
	{
		strcopy(shortMap, sizeof(shortMap), shortMap[slash + 1]);
	}

	for (int i = 0; i < g_iMapPrefixCount; i++)
	{
		if (g_szMapPrefixes[i][0] != '\0' && StrContains(shortMap, g_szMapPrefixes[i], false) == 0)
		{
			return true;
		}
	}
	return false;
}

// Called from map cfg load (configs/ajb/maps/<map>.cfg → "teleports").
void AJB_Settings_LoadTeleportsFromKv(KeyValues kv)
{
	if (kv == null)
	{
		return;
	}

	if (!kv.JumpToKey("teleports"))
	{
		return;
	}

	AJB_Settings_ReadTeleport(kv, "freeday", g_flTpFreedayOrigin, g_flTpFreedayAngles, g_bTpFreeday);
	AJB_Settings_ReadTeleport(kv, "combat_red", g_flTpCombatRedOrigin, g_flTpCombatRedAngles, g_bTpCombatRed);
	AJB_Settings_ReadTeleport(kv, "combat_blu", g_flTpCombatBluOrigin, g_flTpCombatBluAngles, g_bTpCombatBlu);
	kv.GoBack();

	LogMessage("[AJB] map teleports: tp_fd=%d tp_red=%d tp_blu=%d",
		g_bTpFreeday, g_bTpCombatRed, g_bTpCombatBlu);
}

void AJB_Settings_ReadTeleport(KeyValues kv, const char[] key, float origin[3], float angles[3], bool &enabled)
{
	// NEVER invent coordinates. No origin key / empty / unparseable → no teleport.
	enabled = false;
	ZeroVector(origin);
	ZeroVector(angles);

	if (!kv.JumpToKey(key))
	{
		return;
	}

	char oStr[64];
	char aStr[64];
	// Empty default — do NOT default to "0 0 0" (that would be a fake origin).
	kv.GetString("origin", oStr, sizeof(oStr), "");
	kv.GetString("angles", aStr, sizeof(aStr), "");
	kv.GoBack();

	TrimString(oStr);
	if (oStr[0] == '\0')
	{
		return;
	}

	float o[3];
	if (!AJB_Settings_ParseVector(oStr, o))
	{
		LogError("[AJB] map teleports.%s.origin invalid (need \"x y z\"): \"%s\"", key, oStr);
		return;
	}

	// Angles are facing only (optional). Missing/invalid → 0 0 0 look, still no invented position.
	float a[3];
	TrimString(aStr);
	if (aStr[0] == '\0' || !AJB_Settings_ParseVector(aStr, a))
	{
		a[0] = 0.0;
		a[1] = 0.0;
		a[2] = 0.0;
	}

	origin[0] = o[0];
	origin[1] = o[1];
	origin[2] = o[2];
	angles[0] = a[0];
	angles[1] = a[1];
	angles[2] = a[2];
	enabled = true;
}

bool AJB_Settings_ParseVector(const char[] str, float vec[3])
{
	char parts[3][24];
	int n = ExplodeString(str, " ", parts, 3, 24);
	if (n < 3)
	{
		return false;
	}

	// Require each component to look numeric (reject empty tokens).
	for (int i = 0; i < 3; i++)
	{
		TrimString(parts[i]);
		if (parts[i][0] == '\0')
		{
			return false;
		}
	}

	vec[0] = StringToFloat(parts[0]);
	vec[1] = StringToFloat(parts[1]);
	vec[2] = StringToFloat(parts[2]);
	return true;
}

void ZeroVector(float v[3])
{
	v[0] = 0.0;
	v[1] = 0.0;
	v[2] = 0.0;
}

bool AJB_IsCombatDay()
{
	return g_bCombatDay;
}

bool AJB_IsFreedayAllCosmetic()
{
	return g_bFreedayAllCosmetic;
}

bool AJB_NoWardenClaim()
{
	return g_bCombatDay || g_bFreedayAllCosmetic;
}

void AJB_BeginCombatDay()
{
	// Next-round war/class: no prep freeze — live combat immediately.
	AJB_Prep_Stop();
	g_bCombatDay = true;
	g_bFreedayAllCosmetic = false;
	AJB_OpenCellsInternal(true);
	AJB_SetRoundState(AJBState_SpecialDay);
	AJB_CombatDay_ArmAndTeleport();
	AJB_FireCombatDayStart();
}

void AJB_BeginFreedayAllCosmetic()
{
	AJB_Prep_Stop();
	g_bFreedayAllCosmetic = true;
	g_bCombatDay = false;
	AJB_OpenCellsInternal(true);
	AJB_SetRoundState(AJBState_CellsOpen);
	AJB_FireFreedayAllStart();
}

void AJB_CombatDay_ArmAndTeleport()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		if (!AJB_ClientIsPrisoner(i) && !AJB_ClientIsGuard(i))
		{
			continue;
		}

		// Full unrestricted loadout.
		TF2_RegeneratePlayer(i);
		AJB_FlagSet(i, AJB_PF_REBEL, false);
		AJB_FlagSet(i, AJB_PF_FREEDAY, false);

		if (AJB_ClientIsPrisoner(i) && g_bTpCombatRed)
		{
			TeleportEntity(i, g_flTpCombatRedOrigin, g_flTpCombatRedAngles, NULL_VECTOR);
		}
		else if (AJB_ClientIsGuard(i) && g_bTpCombatBlu)
		{
			TeleportEntity(i, g_flTpCombatBluOrigin, g_flTpCombatBluAngles, NULL_VECTOR);
		}
	}
}

void AJB_TeleportFreedayPlayer(int client)
{
	if (!g_bTpFreeday || !AJB_IsValidClient(client, true))
	{
		return;
	}

	TeleportEntity(client, g_flTpFreedayOrigin, g_flTpFreedayAngles, NULL_VECTOR);
}

// =========================================================================================================
// Freeday trail + glow (mid-body world anchors — visible to everyone including the owner in 3rd person)
// =========================================================================================================

void AJB_Freeday_OnApplied(int client, bool freeday)
{
	if (!freeday)
	{
		AJB_Freeday_KillTrailFx(client);
		return;
	}

	AJB_TeleportFreedayPlayer(client);
	if (g_bFreedayTrail)
	{
		AJB_Freeday_EnsureTrailFx(client);
		AJB_Freeday_EnsureTrailTimer();
	}
}

void AJB_Freeday_GetMidBody(int client, float mid[3])
{
	float origin[3];
	float eyes[3];
	GetClientAbsOrigin(client, origin);
	GetClientEyePosition(client, eyes);
	// Midpoint between feet and eyes (torso center).
	mid[0] = (origin[0] + eyes[0]) * 0.5;
	mid[1] = (origin[1] + eyes[1]) * 0.5;
	mid[2] = (origin[2] + eyes[2]) * 0.5;
}

void AJB_Freeday_KillTrailFx(int client)
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	int ent = g_PlayerFx[client].anchor;
	g_PlayerFx[client].anchor = 0;
	if (ent > MaxClients && IsValidEntity(ent))
	{
		AcceptEntityInput(ent, "Kill");
	}

	ent = g_PlayerFx[client].glow;
	g_PlayerFx[client].glow = 0;
	if (ent > MaxClients && IsValidEntity(ent))
	{
		AcceptEntityInput(ent, "Kill");
	}

	g_PlayerFx[client].hasMid = false;

}

// Parented beams often do not render for the local player, so the trail anchor stays world-space.
// The glow sprite IS parented to the player so Source moves it every rendered frame (no jitter).
void AJB_Freeday_EnsureTrailFx(int client)
{
	if (!AJB_IsValidClient(client, true))
	{
		return;
	}

	float mid[3];
	AJB_Freeday_GetMidBody(client, mid);

	// BeamFollow anchor (world-space, repositioned by the timer)
	bool anchorCreated = false;
	int anchor = g_PlayerFx[client].anchor;
	if (anchor <= MaxClients || !IsValidEntity(anchor))
	{
		anchor = CreateEntityByName("info_target");
		if (anchor != -1)
		{
			DispatchSpawn(anchor);
			g_PlayerFx[client].anchor = anchor;
			anchorCreated = true;
		}
	}

	// Constant green glow sprite — world space.
	int glow = g_PlayerFx[client].glow;
	if (glow <= MaxClients || !IsValidEntity(glow))
	{
		glow = AJB_CreateGlow("50 255 50");
		if (glow != -1)
		{
			g_PlayerFx[client].glow = glow;
			anchorCreated = true;
		}
	}

	// Only the anchor needs timer-based teleports; skip when barely moved.
	if (!anchorCreated && g_PlayerFx[client].hasMid)
	{
		float dx = mid[0] - g_PlayerFx[client].lastMid[0];
		float dy = mid[1] - g_PlayerFx[client].lastMid[1];
		float dz = mid[2] - g_PlayerFx[client].lastMid[2];
		if (dx * dx + dy * dy + dz * dz < AJB_FREEDAY_MOVE_SQR)
		{
			return;
		}
	}

	if (anchor > MaxClients && IsValidEntity(anchor))
	{
		TeleportEntity(anchor, mid, NULL_VECTOR, NULL_VECTOR);
	}
	if (glow > MaxClients && IsValidEntity(glow))
	{
		TeleportEntity(glow, mid, NULL_VECTOR, NULL_VECTOR);
	}

	g_PlayerFx[client].lastMid = mid;
	g_PlayerFx[client].hasMid = true;
}

// =========================================================================================================
// Rebel glow (orange, parented to player — same pattern as freeday glow)
// =========================================================================================================

void AJB_Rebel_OnChanged(int client, bool rebel)
{
	if (rebel)
	{
		AJB_Rebel_EnsureGlow(client);
		AJB_PlayerFx_EnsureTimer();
	}
	else
	{
		AJB_Rebel_KillGlow(client);
	}
}

void AJB_Rebel_EnsureGlow(int client)
{
	if (!AJB_IsValidClient(client, true))
	{
		return;
	}

	float mid[3];
	AJB_Freeday_GetMidBody(client, mid);

	bool created = false;
	int glow = g_PlayerFx[client].rebelGlow;
	if (glow <= MaxClients || !IsValidEntity(glow))
	{
		glow = AJB_CreateGlow("255 150 0");
		if (glow != -1)
		{
			g_PlayerFx[client].rebelGlow = glow;
			created = true;
		}
	}

	if (!created && g_PlayerFx[client].hasMid)
	{
		float dx = mid[0] - g_PlayerFx[client].lastMid[0];
		float dy = mid[1] - g_PlayerFx[client].lastMid[1];
		float dz = mid[2] - g_PlayerFx[client].lastMid[2];
		if (dx * dx + dy * dy + dz * dz < AJB_FREEDAY_MOVE_SQR)
		{
			return;
		}
	}

	if (glow > MaxClients && IsValidEntity(glow))
	{
		TeleportEntity(glow, mid, NULL_VECTOR, NULL_VECTOR);
	}

	g_PlayerFx[client].lastMid = mid;
	g_PlayerFx[client].hasMid = true;
}

void AJB_Rebel_KillGlow(int client)
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	int ent = g_PlayerFx[client].rebelGlow;
	g_PlayerFx[client].rebelGlow = 0;
	if (ent > MaxClients && IsValidEntity(ent))
	{
		AcceptEntityInput(ent, "Kill");
	}

}

// =========================================================================================================
// Shared: create a parented env_sprite glow at mid-body height
// =========================================================================================================

int AJB_CreateGlow(const char[] color)
{
	int glow = CreateEntityByName("env_sprite");
	if (glow == -1)
	{
		return -1;
	}

	DispatchKeyValue(glow, "model", "materials/sprites/glow01.vmt");
	DispatchKeyValue(glow, "classname", "env_sprite");
	DispatchKeyValue(glow, "spawnflags", "1");
	DispatchKeyValue(glow, "scale", "0.85");
	DispatchKeyValue(glow, "rendermode", "5");
	DispatchKeyValue(glow, "renderamt", "255");
	DispatchKeyValue(glow, "rendercolor", color);
	DispatchKeyValue(glow, "GlowProxySize", "12.0");
	DispatchSpawn(glow);
	AcceptEntityInput(glow, "ShowSprite");

	return glow;
}

// =========================================================================================================
// Shared FX timer (freeday trails + rebel/freeday glow lifecycle)
// =========================================================================================================

void AJB_PlayerFx_EnsureTimer()
{
	if (g_hPlayerFxTimer == null)
	{
		g_hPlayerFxTimer = CreateTimer(0.15, Timer_PlayerFx, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

void AJB_Freeday_EnsureTrailTimer()
{
	if (!g_bFreedayTrail)
	{
		return;
	}

	AJB_PlayerFx_EnsureTimer();
}

void AJB_PlayerFx_StopTimer()
{
	if (g_hPlayerFxTimer != null)
	{
		delete g_hPlayerFxTimer;
		g_hPlayerFxTimer = null;
	}
}

Action Timer_PlayerFx(Handle timer)
{
	if (!g_bModeActive)
	{
		g_hPlayerFxTimer = null;
		return Plugin_Stop;
	}

	bool any = false;
	static const int trailColor[4] = { 50, 255, 50, 255 };

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			AJB_Freeday_KillTrailFx(i);
			AJB_Rebel_KillGlow(i);
			continue;
		}

		bool isRebel = AJB_FlagGet(i, AJB_PF_REBEL);
		bool isFreeday = AJB_FlagGet(i, AJB_PF_FREEDAY) && !isRebel;

		// Freeday trail + glow
		if (isFreeday && g_bFreedayTrail)
		{
			AJB_Freeday_EnsureTrailFx(i);

			int anchor = g_PlayerFx[i].anchor;
			if (g_iFreedayBeamSprite != -1 && anchor > MaxClients && IsValidEntity(anchor))
			{
				TE_SetupBeamFollow(anchor, g_iFreedayBeamSprite, 0, 3.5, 18.0, 12.0, 8, trailColor);
				TE_SendToAll();
			}
			any = true;
		}
		else
		{
			AJB_Freeday_KillTrailFx(i);
		}

		// Rebel glow
		if (isRebel)
		{
			AJB_Rebel_EnsureGlow(i);
			any = true;
		}
		else
		{
			AJB_Rebel_KillGlow(i);
		}
	}

	if (!any)
	{
		g_hPlayerFxTimer = null;
		return Plugin_Stop;
	}

	return Plugin_Continue;
}
