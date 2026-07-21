// =========================================================================================================
// Warden enemy-health vision
// Prefer native TF2 attr "mod see enemy health" when tf2attributes is loaded.
// Otherwise fall back to a crosshair HUD readout (no extra deps).
// =========================================================================================================

#define AJB_ATTR_SEE_ENEMY_HEALTH "mod see enemy health"
#define AJB_HEALTH_FALLBACK_TICK  0.1
#define AJB_HEALTH_TRACE_RANGE    8192.0

ConVar g_cvWardenSeeHealth;
bool g_bTf2Attribs;

Handle g_hWardenHealthHud;
Handle g_hWardenHealthFallbackTimer;

void AJB_WardenHealth_OnPluginStart()
{
	g_cvWardenSeeHealth = CreateConVar(
		"sm_ajb_warden_see_health",
		"1",
		"1 = warden sees target HP. Uses native TF2 attr if tf2attributes is loaded; otherwise HUD fallback.",
		_, true, 0.0, true, 1.0);

	g_cvWardenSeeHealth.AddChangeHook(OnWardenSeeHealthCvar);

	HookEvent("player_spawn", Event_WardenHealth_Spawn, EventHookMode_Post);
	HookEvent("post_inventory_application", Event_WardenHealth_Resupply, EventHookMode_Post);

	g_hWardenHealthHud = CreateHudSynchronizer();
	g_bTf2Attribs = LibraryExists("tf2attributes");
}

void AJB_WardenHealth_OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "tf2attributes"))
	{
		g_bTf2Attribs = true;
		// Prefer native path when the dependency appears mid-session.
		AJB_WardenHealth_StopFallback();
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
		// Drop to HUD readout if vision is still wanted.
		if (g_iWarden > 0 && g_cvWardenSeeHealth.BoolValue)
		{
			AJB_WardenHealth_StartFallback();
		}
	}
}

void OnWardenSeeHealthCvar(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (g_iWarden <= 0 || !IsClientInGame(g_iWarden))
	{
		if (!g_cvWardenSeeHealth.BoolValue)
		{
			AJB_WardenHealth_StopFallback();
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

// True when we can stamp the Solemn Vow-style attribute.
bool AJB_WardenHealth_NativeReady()
{
	if (!g_bTf2Attribs || !g_cvWardenSeeHealth.BoolValue)
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

	if (AJB_WardenHealth_NativeReady())
	{
		AJB_WardenHealth_StopFallback();
		AJB_WardenHealth_ApplyNative(client);
		return;
	}

	// No tf2attributes (or not ready) → crosshair HUD.
	AJB_WardenHealth_StartFallback();
}

void AJB_WardenHealth_Remove(int client)
{
	if (AJB_IsValidClient(client) && g_bTf2Attribs)
	{
		AJB_WardenHealth_RemoveNative(client);
	}

	AJB_WardenHealth_StopFallback();

	if (AJB_IsValidClient(client) && g_hWardenHealthHud != null)
	{
		ClearSyncHud(client, g_hWardenHealthHud);
	}
}

// ---------------------------------------------------------------------------------------------------------
// Native path (tf2attributes)
// ---------------------------------------------------------------------------------------------------------

void AJB_WardenHealth_ApplyNative(int client)
{
	if (GetFeatureStatus(FeatureType_Native, "TF2Attrib_AddCustomPlayerAttribute") == FeatureStatus_Available)
	{
		TF2Attrib_AddCustomPlayerAttribute(client, AJB_ATTR_SEE_ENEMY_HEALTH, 1.0, -1.0);
	}

	AJB_WardenHealth_StampWeapons(client, true);

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
		}
		else
		{
			TF2Attrib_RemoveByName(wep, AJB_ATTR_SEE_ENEMY_HEALTH);
		}
	}

	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "tf_wearable*")) != -1)
	{
		if (!IsValidEntity(ent) || !HasEntProp(ent, Prop_Send, "m_hOwnerEntity"))
		{
			continue;
		}

		if (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") != client)
		{
			continue;
		}

		if (enable)
		{
			TF2Attrib_SetByName(ent, AJB_ATTR_SEE_ENEMY_HEALTH, 1.0);
		}
		else
		{
			TF2Attrib_RemoveByName(ent, AJB_ATTR_SEE_ENEMY_HEALTH);
		}
	}
}

// ---------------------------------------------------------------------------------------------------------
// Fallback path (HUD + eye trace) — no external plugins
// ---------------------------------------------------------------------------------------------------------

void AJB_WardenHealth_StartFallback()
{
	if (!g_cvWardenSeeHealth.BoolValue || g_iWarden <= 0)
	{
		AJB_WardenHealth_StopFallback();
		return;
	}

	// Native path already covers this client — do not double-draw.
	if (AJB_WardenHealth_NativeReady())
	{
		AJB_WardenHealth_StopFallback();
		return;
	}

	if (g_hWardenHealthFallbackTimer != null)
	{
		return;
	}

	g_hWardenHealthFallbackTimer = CreateTimer(
		AJB_HEALTH_FALLBACK_TICK,
		Timer_WardenHealthFallback,
		_,
		TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void AJB_WardenHealth_StopFallback()
{
	if (g_hWardenHealthFallbackTimer != null)
	{
		delete g_hWardenHealthFallbackTimer;
		g_hWardenHealthFallbackTimer = null;
	}
}

Action Timer_WardenHealthFallback(Handle timer)
{
	if (!g_cvWardenSeeHealth.BoolValue || !g_bModeActive)
	{
		g_hWardenHealthFallbackTimer = null;
		return Plugin_Stop;
	}

	// Dependency came online — hand off to native attr.
	if (AJB_WardenHealth_NativeReady())
	{
		if (g_iWarden > 0)
		{
			AJB_WardenHealth_ApplyNative(g_iWarden);
		}
		g_hWardenHealthFallbackTimer = null;
		return Plugin_Stop;
	}

	int warden = g_iWarden;
	if (warden <= 0 || !IsClientInGame(warden) || IsFakeClient(warden) || !IsPlayerAlive(warden))
	{
		if (warden > 0 && IsClientInGame(warden) && g_hWardenHealthHud != null)
		{
			ClearSyncHud(warden, g_hWardenHealthHud);
		}
		return Plugin_Continue;
	}

	int target = AJB_WardenHealth_TraceTarget(warden);
	if (target <= 0)
	{
		ClearSyncHud(warden, g_hWardenHealthHud);
		return Plugin_Continue;
	}

	int hp = GetClientHealth(target);
	int maxHp = AJB_WardenHealth_GetMaxHealth(target);
	if (maxHp < 1)
	{
		maxHp = hp;
	}

	char name[64];
	GetClientName(target, name, sizeof(name));

	// Color by fill ratio (green → yellow → red).
	int r = 255, g = 255, b = 80;
	float ratio = float(hp) / float(maxHp);
	if (ratio > 0.66)
	{
		r = 80; g = 255; b = 80;
	}
	else if (ratio < 0.33)
	{
		r = 255; g = 80; b = 80;
	}

	SetHudTextParams(-1.0, 0.38, AJB_HEALTH_FALLBACK_TICK + 0.05, r, g, b, 255, 0, 0.0, 0.0, 0.0);
	ShowSyncHudText(warden, g_hWardenHealthHud, "%s\n%d / %d", name, hp, maxHp);

	return Plugin_Continue;
}

int AJB_WardenHealth_TraceTarget(int warden)
{
	float eye[3];
	float ang[3];
	float fwd[3];
	float end[3];

	GetClientEyePosition(warden, eye);
	GetClientEyeAngles(warden, ang);
	GetAngleVectors(ang, fwd, NULL_VECTOR, NULL_VECTOR);

	end[0] = eye[0] + fwd[0] * AJB_HEALTH_TRACE_RANGE;
	end[1] = eye[1] + fwd[1] * AJB_HEALTH_TRACE_RANGE;
	end[2] = eye[2] + fwd[2] * AJB_HEALTH_TRACE_RANGE;

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

	// Jailbreak: only care about living prisoners (RED) under the crosshair.
	if (!AJB_ClientIsPrisoner(ent))
	{
		return 0;
	}

	return ent;
}

bool TraceFilter_WardenHealth(int entity, int contentsMask, int warden)
{
	if (entity == warden)
	{
		return false;
	}

	// Hit world + players; skip other junk (projectiles, etc.).
	if (entity > 0 && entity <= MaxClients)
	{
		return true;
	}

	// Solid world / props still block the ray.
	return entity == 0 || !IsValidEntity(entity) || entity > MaxClients;
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

	// TF player resource array is indexed by client.
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
