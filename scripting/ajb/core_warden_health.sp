// =========================================================================================================
// Warden enemy-health vision
// - Always: silent center HUD (ShowSyncHudText only — never PrintHintText, it beeps).
// - Bonus: stamp TF2 attr "mod see enemy health" when tf2attributes is loaded (native client bar).
// =========================================================================================================

#define AJB_ATTR_SEE_ENEMY_HEALTH "mod see enemy health"
#define AJB_ATTR_SEE_ENEMY_DEFIDX 269
#define AJB_HEALTH_TICK           0.15
#define AJB_HEALTH_TRACE_RANGE    8192.0

ConVar g_cvWardenSeeHealth;
bool g_bTf2Attribs;

Handle g_hWardenHealthHud;
Handle g_hWardenHealthTimer;

// Avoid rewriting HUD every tick when nothing changed (and no flicker).
int g_iHudLastTarget;
int g_iHudLastHp;
int g_iHudLastMax;

void AJB_WardenHealth_OnPluginStart()
{
	g_cvWardenSeeHealth = CreateConVar(
		"sm_ajb_warden_see_health",
		"1",
		"1 = warden sees prisoner HP under crosshair (silent HUD). Also tries native see_enemy_health attr if tf2attributes is loaded.",
		_, true, 0.0, true, 1.0);

	g_cvWardenSeeHealth.AddChangeHook(OnWardenSeeHealthCvar);

	HookEvent("player_spawn", Event_WardenHealth_Spawn, EventHookMode_Post);
	HookEvent("post_inventory_application", Event_WardenHealth_Resupply, EventHookMode_Post);

	g_hWardenHealthHud = CreateHudSynchronizer();
	g_bTf2Attribs = LibraryExists("tf2attributes");
	g_iHudLastTarget = 0;
	g_iHudLastHp = -1;
	g_iHudLastMax = -1;
}

void AJB_WardenHealth_OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "tf2attributes"))
	{
		g_bTf2Attribs = true;
		if (g_iWarden > 0 && g_cvWardenSeeHealth.BoolValue)
		{
			AJB_WardenHealth_Apply(g_iWarden);
		}
	}
}

void AJB_WardenHealth_OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "tf2attributes"))
	{
		g_bTf2Attribs = false;
	}
}

void OnWardenSeeHealthCvar(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (g_iWarden <= 0 || !IsClientInGame(g_iWarden))
	{
		if (!g_cvWardenSeeHealth.BoolValue)
		{
			AJB_WardenHealth_StopTimer();
		}
		return;
	}

	if (g_cvWardenSeeHealth.BoolValue)
	{
		AJB_WardenHealth_Apply(g_iWarden);
	}
	else
	{
		AJB_WardenHealth_Remove(g_iWarden);
	}
}

void Event_WardenHealth_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client == g_iWarden)
	{
		CreateTimer(0.15, Timer_WardenHealthApply, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

void Event_WardenHealth_Resupply(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client == g_iWarden)
	{
		CreateTimer(0.05, Timer_WardenHealthApply, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action Timer_WardenHealthApply(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0 && client == g_iWarden && g_cvWardenSeeHealth.BoolValue)
	{
		AJB_WardenHealth_Apply(client);
	}
	return Plugin_Stop;
}

bool AJB_WardenHealth_NativeReady()
{
	if (!g_bTf2Attribs)
	{
		return false;
	}

	if (GetFeatureStatus(FeatureType_Native, "TF2Attrib_IsReady") == FeatureStatus_Available)
	{
		return TF2Attrib_IsReady();
	}

	return true;
}

void AJB_WardenHealth_Apply(int client)
{
	if (!AJB_IsValidClient(client) || !g_cvWardenSeeHealth.BoolValue)
	{
		return;
	}

	// Best-effort native client bar (works well on some classes/weapons; not guaranteed on Scout).
	if (AJB_WardenHealth_NativeReady())
	{
		AJB_WardenHealth_ApplyNative(client);
	}

	// Silent HUD is the guaranteed channel for any class (including Scout).
	AJB_WardenHealth_StartTimer();
}

void AJB_WardenHealth_Remove(int client)
{
	if (AJB_IsValidClient(client) && g_bTf2Attribs)
	{
		AJB_WardenHealth_RemoveNative(client);
	}

	AJB_WardenHealth_StopTimer();
	AJB_WardenHealth_ClearHud(client);
}

void AJB_WardenHealth_ClearHud(int client)
{
	g_iHudLastTarget = 0;
	g_iHudLastHp = -1;
	g_iHudLastMax = -1;

	if (AJB_IsValidClient(client) && g_hWardenHealthHud != null)
	{
		ClearSyncHud(client, g_hWardenHealthHud);
	}
}

// ---------------------------------------------------------------------------------------------------------
// Native path — tells the *warden's client* to draw enemy HP like Solemn Vow
// (m_iHealth is already networked; this only unlocks the stock draw path when the client honors the attr.)
// ---------------------------------------------------------------------------------------------------------

void AJB_WardenHealth_ApplyNative(int client)
{
	if (GetFeatureStatus(FeatureType_Native, "TF2Attrib_AddCustomPlayerAttribute") == FeatureStatus_Available)
	{
		TF2Attrib_AddCustomPlayerAttribute(client, AJB_ATTR_SEE_ENEMY_HEALTH, 1.0, -1.0);
	}

	AJB_WardenHealth_StampWeapons(client, true);

	// Active weapon gets an extra stamp — client often only evaluates the held item.
	int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (active > MaxClients && IsValidEntity(active))
	{
		if (GetFeatureStatus(FeatureType_Native, "TF2Attrib_SetByDefIndex") == FeatureStatus_Available)
		{
			TF2Attrib_SetByDefIndex(active, AJB_ATTR_SEE_ENEMY_DEFIDX, 1.0);
		}
		else
		{
			TF2Attrib_SetByName(active, AJB_ATTR_SEE_ENEMY_HEALTH, 1.0);
		}

		if (GetFeatureStatus(FeatureType_Native, "TF2Attrib_ClearCache") == FeatureStatus_Available)
		{
			TF2Attrib_ClearCache(active);
		}
	}

	if (GetFeatureStatus(FeatureType_Native, "TF2Attrib_ClearCache") == FeatureStatus_Available)
	{
		TF2Attrib_ClearCache(client);
	}
}

void AJB_WardenHealth_RemoveNative(int client)
{
	if (GetFeatureStatus(FeatureType_Native, "TF2Attrib_RemoveCustomPlayerAttribute") == FeatureStatus_Available)
	{
		TF2Attrib_RemoveCustomPlayerAttribute(client, AJB_ATTR_SEE_ENEMY_HEALTH);
	}

	AJB_WardenHealth_StampWeapons(client, false);

	if (GetFeatureStatus(FeatureType_Native, "TF2Attrib_ClearCache") == FeatureStatus_Available)
	{
		TF2Attrib_ClearCache(client);
	}
}

void AJB_WardenHealth_StampWeapons(int client, bool enable)
{
	if (!IsClientInGame(client) || !g_bTf2Attribs)
	{
		return;
	}

	for (int slot = 0; slot <= 5; slot++)
	{
		int wep = GetPlayerWeaponSlot(client, slot);
		if (wep <= MaxClients || !IsValidEntity(wep))
		{
			continue;
		}

		if (enable)
		{
			TF2Attrib_SetByName(wep, AJB_ATTR_SEE_ENEMY_HEALTH, 1.0);
			if (GetFeatureStatus(FeatureType_Native, "TF2Attrib_SetByDefIndex") == FeatureStatus_Available)
			{
				TF2Attrib_SetByDefIndex(wep, AJB_ATTR_SEE_ENEMY_DEFIDX, 1.0);
			}
		}
		else
		{
			TF2Attrib_RemoveByName(wep, AJB_ATTR_SEE_ENEMY_HEALTH);
			if (GetFeatureStatus(FeatureType_Native, "TF2Attrib_RemoveByDefIndex") == FeatureStatus_Available)
			{
				TF2Attrib_RemoveByDefIndex(wep, AJB_ATTR_SEE_ENEMY_DEFIDX);
			}
		}
	}
}

// ---------------------------------------------------------------------------------------------------------
// Silent HUD path (ShowSyncHudText only)
// ---------------------------------------------------------------------------------------------------------

void AJB_WardenHealth_StartTimer()
{
	if (!g_cvWardenSeeHealth.BoolValue || g_iWarden <= 0)
	{
		AJB_WardenHealth_StopTimer();
		return;
	}

	if (g_hWardenHealthTimer != null)
	{
		return;
	}

	g_hWardenHealthTimer = CreateTimer(
		AJB_HEALTH_TICK,
		Timer_WardenHealthTick,
		_,
		TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void AJB_WardenHealth_StopTimer()
{
	if (g_hWardenHealthTimer != null)
	{
		delete g_hWardenHealthTimer;
		g_hWardenHealthTimer = null;
	}
}

Action Timer_WardenHealthTick(Handle timer)
{
	if (!g_cvWardenSeeHealth.BoolValue || !g_bModeActive)
	{
		g_hWardenHealthTimer = null;
		return Plugin_Stop;
	}

	int warden = g_iWarden;
	if (warden <= 0 || !IsClientInGame(warden) || IsFakeClient(warden) || !IsPlayerAlive(warden))
	{
		if (warden > 0 && IsClientInGame(warden))
		{
			AJB_WardenHealth_ClearHud(warden);
		}
		return Plugin_Continue;
	}

	// Keep native attr on the currently held weapon (resupply/switch).
	if (AJB_WardenHealth_NativeReady())
	{
		int active = GetEntPropEnt(warden, Prop_Send, "m_hActiveWeapon");
		if (active > MaxClients && IsValidEntity(active))
		{
			TF2Attrib_SetByName(active, AJB_ATTR_SEE_ENEMY_HEALTH, 1.0);
		}
	}

	int target = AJB_WardenHealth_TraceTarget(warden);
	if (target <= 0)
	{
		if (g_iHudLastTarget != 0)
		{
			AJB_WardenHealth_ClearHud(warden);
		}
		return Plugin_Continue;
	}

	int hp = GetClientHealth(target);
	int maxHp = AJB_WardenHealth_GetMaxHealth(target);
	if (maxHp < 1)
	{
		maxHp = hp;
	}

	// Only push a new HUD message when the readout actually changes.
	if (target == g_iHudLastTarget && hp == g_iHudLastHp && maxHp == g_iHudLastMax)
	{
		return Plugin_Continue;
	}

	g_iHudLastTarget = target;
	g_iHudLastHp = hp;
	g_iHudLastMax = maxHp;

	char name[64];
	GetClientName(target, name, sizeof(name));

	int r = 255, gCol = 255, b = 80;
	float ratio = float(hp) / float(maxHp);
	if (ratio > 0.66)
	{
		r = 80; gCol = 255; b = 80;
	}
	else if (ratio < 0.33)
	{
		r = 255; gCol = 80; b = 80;
	}

	// Hold long enough that we don't need to re-send every tick for the same target.
	SetHudTextParams(-1.0, 0.42, 2.0, r, gCol, b, 255, 0, 0.0, 0.0, 0.0);
	ShowSyncHudText(warden, g_hWardenHealthHud, "%s\n%d / %d HP", name, hp, maxHp);

	return Plugin_Continue;
}

int AJB_WardenHealth_TraceTarget(int warden)
{
	float eye[3];
	float ang[3];
	float end[3];

	GetClientEyePosition(warden, eye);
	GetClientEyeAngles(warden, ang);

	GetAngleVectors(ang, end, NULL_VECTOR, NULL_VECTOR);
	end[0] = eye[0] + end[0] * AJB_HEALTH_TRACE_RANGE;
	end[1] = eye[1] + end[1] * AJB_HEALTH_TRACE_RANGE;
	end[2] = eye[2] + end[2] * AJB_HEALTH_TRACE_RANGE;

	TR_TraceRayFilter(eye, end, MASK_SHOT, RayType_EndPoint, TraceFilter_WardenHealth, warden);

	if (!TR_DidHit())
	{
		return 0;
	}

	int ent = TR_GetEntityIndex();
	if (ent < 1 || ent > MaxClients || !IsClientInGame(ent) || !IsPlayerAlive(ent))
	{
		return 0;
	}

	if (!AJB_ClientIsPrisoner(ent))
	{
		return 0;
	}

	return ent;
}

bool TraceFilter_WardenHealth(int entity, int contentsMask, int warden)
{
	return entity != warden;
}

int AJB_WardenHealth_GetMaxHealth(int client)
{
	if (HasEntProp(client, Prop_Data, "m_iMaxHealth"))
	{
		int maxHp = GetEntProp(client, Prop_Data, "m_iMaxHealth");
		if (maxHp > 0)
		{
			return maxHp;
		}
	}

	int res = GetPlayerResourceEntity();
	if (res != -1 && HasEntProp(res, Prop_Send, "m_iMaxHealth"))
	{
		int maxHp = GetEntProp(res, Prop_Send, "m_iMaxHealth", _, client);
		if (maxHp > 0)
		{
			return maxHp;
		}
	}

	return GetClientHealth(client);
}
