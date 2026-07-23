// =========================================================================================================
// Guard sentries — only target/damage rebel prisoners
//
// Targeting:
//   Supercede CObjectSentrygun::FindTarget while rebels-only is on.
//   SDK Attack() only runs when m_iState == SENTRY_STATE_ATTACKING. Stock FindTarget calls
//   FoundTarget() which sets ATTACKING; if we only set m_hEnemy + return true, SentryRotate
//   exits early and the gun stares without ever calling Fire(). We must set m_iState too.
//
// Damage: zero sentry/rocket damage to non-rebel prisoners (body-block / splash).
// Build: sm_ajb_allow_sentry lets guards place sentries when block_buildings is on.
// =========================================================================================================

#define AJB_SENTRY_RANGE_DEFAULT  1100.0

// CObjectSentrygun::m_iState (tf_obj_sentrygun.h)
#define AJB_SENTRY_STATE_INACTIVE   0
#define AJB_SENTRY_STATE_SEARCHING  1
#define AJB_SENTRY_STATE_ATTACKING  2
#define AJB_SENTRY_STATE_UPGRADING  3

ConVar g_cvAllowSentry;
ConVar g_cvSentryRebelsOnly;

DynamicDetour g_hDetourSentryFindTarget;

void AJB_Sentry_OnPluginStart()
{
	g_cvAllowSentry = CreateConVar(
		"sm_ajb_allow_sentry",
		"1",
		"1 = guards may build sentries even when sm_ajb_block_buildings is 1 (dispenser/tele still blocked).",
		_, true, 0.0, true, 1.0);

	g_cvSentryRebelsOnly = CreateConVar(
		"sm_ajb_sentry_rebels_only",
		"1",
		"1 = guard sentries only lock/damage rebel prisoners.",
		_, true, 0.0, true, 1.0);

	GameData gd = new GameData(AJB_GAMEDATA_FILE);
	if (gd == null)
	{
		LogError("[AJB] Missing gamedata %s.txt — sentry rebel FindTarget disabled (damage filter still works).", AJB_GAMEDATA_FILE);
		return;
	}

	g_hDetourSentryFindTarget = DynamicDetour.FromConf(gd, "CObjectSentrygun::FindTarget");
	delete gd;

	if (g_hDetourSentryFindTarget == null)
	{
		LogError("[AJB] Failed to create detour CObjectSentrygun::FindTarget.");
		return;
	}

	// PRE Supercede only — we fully replace the search, no POST needed.
	if (!g_hDetourSentryFindTarget.Enable(Hook_Pre, Detour_AJB_SentryFindTarget_Pre))
	{
		LogError("[AJB] Failed to enable FindTarget PRE detour.");
		delete g_hDetourSentryFindTarget;
		g_hDetourSentryFindTarget = null;
		return;
	}

	LogMessage("[AJB] CObjectSentrygun::FindTarget supercede armed (rebels only).");
}

void AJB_Sentry_OnPluginEnd()
{
	if (g_hDetourSentryFindTarget != null)
	{
		g_hDetourSentryFindTarget.Disable(Hook_Pre, Detour_AJB_SentryFindTarget_Pre);
		delete g_hDetourSentryFindTarget;
		g_hDetourSentryFindTarget = null;
	}
}

bool AJB_Sentry_IsRebelOnly()
{
	// War Day / Class Warfare: stock sentry AI (all teams shoot enemies).
	if (AJB_IsCombatDay())
	{
		return false;
	}

	return g_bModeActive && g_cvSentryRebelsOnly != null && g_cvSentryRebelsOnly.BoolValue;
}

bool AJB_Sentry_IsValidRebelTarget(int client)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return false;
	}

	// Must be on prisoners team and flagged rebel this round.
	if (!AJB_ClientIsPrisoner(client) || !AJB_FlagGet(client, AJB_PF_REBEL))
	{
		return false;
	}

	// Don't feed the sentry targets it cannot hurt (uber / ghost, etc.).
	if (TF2_IsPlayerInCondition(client, TFCond_Ubercharged)
		|| TF2_IsPlayerInCondition(client, TFCond_UberchargedHidden)
		|| TF2_IsPlayerInCondition(client, TFCond_Bonked)
		|| TF2_IsPlayerInCondition(client, TFCond_HalloweenGhostMode))
	{
		return false;
	}

	return true;
}

void AJB_Sentry_ClearEnemy(int sentry)
{
	if (sentry > MaxClients && IsValidEntity(sentry) && HasEntProp(sentry, Prop_Send, "m_hEnemy"))
	{
		SetEntPropEnt(sentry, Prop_Send, "m_hEnemy", -1);
	}
}

void AJB_Sentry_SetEnemy(int sentry, int client)
{
	if (sentry > MaxClients && IsValidEntity(sentry) && HasEntProp(sentry, Prop_Send, "m_hEnemy"))
	{
		SetEntPropEnt(sentry, Prop_Send, "m_hEnemy", client);
	}
}

// Force every guard sentry to reconsider targets (call when someone becomes rebel).
void AJB_Sentry_OnRebelChanged(int client, bool rebel)
{
	if (!rebel || !AJB_Sentry_IsRebelOnly())
	{
		return;
	}

	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	int sentry = -1;
	while ((sentry = FindEntityByClassname(sentry, "obj_sentrygun")) != -1)
	{
		if (!IsValidEntity(sentry))
		{
			continue;
		}
		if (GetEntProp(sentry, Prop_Send, "m_iTeamNum") != AJB_GetGuardsTeam())
		{
			continue;
		}

		// Drop lock so next think re-acquires via FindTarget (sets ATTACKING + Fire).
		AJB_Sentry_ClearEnemy(sentry);
		if (HasEntProp(sentry, Prop_Send, "m_iState")
			&& GetEntProp(sentry, Prop_Send, "m_iState") == AJB_SENTRY_STATE_ATTACKING)
		{
			SetEntProp(sentry, Prop_Send, "m_iState", AJB_SENTRY_STATE_SEARCHING);
		}
	}
}

int AJB_Sentry_FromInflictor(int inflictor)
{
	if (inflictor <= MaxClients || !IsValidEntity(inflictor))
	{
		return -1;
	}

	char class[64];
	GetEntityClassname(inflictor, class, sizeof(class));

	if (StrEqual(class, "obj_sentrygun"))
	{
		return inflictor;
	}

	if (StrEqual(class, "tf_projectile_sentryrocket"))
	{
		if (HasEntProp(inflictor, Prop_Send, "m_hOwnerEntity"))
		{
			int owner = GetEntPropEnt(inflictor, Prop_Send, "m_hOwnerEntity");
			if (owner > MaxClients && IsValidEntity(owner))
			{
				return owner;
			}
		}
	}

	return -1;
}

bool AJB_Sentry_IsReady(int sentry)
{
	if (sentry <= MaxClients || !IsValidEntity(sentry))
	{
		return false;
	}

	// Still constructing / carried / disabled → no acquire.
	if (HasEntProp(sentry, Prop_Send, "m_bBuilding") && GetEntProp(sentry, Prop_Send, "m_bBuilding"))
	{
		return false;
	}
	if (HasEntProp(sentry, Prop_Send, "m_bCarried") && GetEntProp(sentry, Prop_Send, "m_bCarried"))
	{
		return false;
	}
	if (HasEntProp(sentry, Prop_Send, "m_bPlacing") && GetEntProp(sentry, Prop_Send, "m_bPlacing"))
	{
		return false;
	}
	if (HasEntProp(sentry, Prop_Send, "m_bDisabled") && GetEntProp(sentry, Prop_Send, "m_bDisabled"))
	{
		return false;
	}
	// Wrangler: owner is controlling — leave stock alone (we Supercede only when not controlled).
	if (HasEntProp(sentry, Prop_Send, "m_bPlayerControlled") && GetEntProp(sentry, Prop_Send, "m_bPlayerControlled"))
	{
		return false;
	}

	return true;
}

float AJB_Sentry_GetRangeSqr(int sentry)
{
	float range = AJB_SENTRY_RANGE_DEFAULT;

	// Mini sentries are shorter range in stock TF2 (~0.75 of normal is a common approx).
	if (HasEntProp(sentry, Prop_Send, "m_bMiniBuilding") && GetEntProp(sentry, Prop_Send, "m_bMiniBuilding"))
	{
		range *= 0.75;
	}

	return range * range;
}

void AJB_Sentry_GetEye(int sentry, float eye[3])
{
	GetEntPropVector(sentry, Prop_Send, "m_vecOrigin", eye);
	// Approximate muzzle height by level (L1 short, L2/L3 taller).
	int level = 1;
	if (HasEntProp(sentry, Prop_Send, "m_iUpgradeLevel"))
	{
		level = GetEntProp(sentry, Prop_Send, "m_iUpgradeLevel");
	}
	eye[2] += (level >= 2) ? 50.0 : 35.0;
}

bool TraceFilter_SentryLos(int entity, int contentsMask, int sentry)
{
	if (entity == sentry)
	{
		return false;
	}
	// Players never block LOS for this check (stock also aims past teammates sometimes).
	if (entity > 0 && entity <= MaxClients)
	{
		return false;
	}
	return true;
}

// eye + rangeSqr are constant across a single FindTarget scan, so the caller computes
// them once and passes them in rather than recomputing per candidate.
bool AJB_Sentry_CanSee(int sentry, int client, const float eye[3], float rangeSqr)
{
	float target[3];
	GetClientEyePosition(client, target);

	float dx = target[0] - eye[0];
	float dy = target[1] - eye[1];
	float dz = target[2] - eye[2];
	float d2 = dx * dx + dy * dy + dz * dz;
	if (d2 > rangeSqr)
	{
		return false;
	}

	Handle tr = TR_TraceRayFilterEx(eye, target, MASK_SHOT, RayType_EndPoint, TraceFilter_SentryLos, sentry);
	bool blocked = TR_DidHit(tr) && TR_GetEntityIndex(tr) != client;
	delete tr;

	if (blocked)
	{
		// Retry center-mass (crouching / props at head height).
		GetClientAbsOrigin(client, target);
		target[2] += 40.0;
		tr = TR_TraceRayFilterEx(eye, target, MASK_SHOT, RayType_EndPoint, TraceFilter_SentryLos, sentry);
		blocked = TR_DidHit(tr) && TR_GetEntityIndex(tr) != client;
		delete tr;
	}

	return !blocked;
}

int AJB_Sentry_FindNearestRebel(int sentry)
{
	int sentryTeam = GetEntProp(sentry, Prop_Send, "m_iTeamNum");

	// Sentry eye + range are fixed for this scan — compute once, not per candidate.
	float eye[3];
	AJB_Sentry_GetEye(sentry, eye);
	float rangeSqr = AJB_Sentry_GetRangeSqr(sentry);

	float bestDist = rangeSqr;
	int best = -1;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!AJB_Sentry_IsValidRebelTarget(client))
		{
			continue;
		}
		if (GetClientTeam(client) == sentryTeam)
		{
			continue;
		}
		if (!AJB_Sentry_CanSee(sentry, client, eye, rangeSqr))
		{
			continue;
		}

		float pos[3];
		GetClientAbsOrigin(client, pos);
		float dx = pos[0] - eye[0];
		float dy = pos[1] - eye[1];
		float dz = pos[2] - eye[2];
		float d2 = dx * dx + dy * dy + dz * dz;
		if (d2 < bestDist)
		{
			bestDist = d2;
			best = client;
		}
	}

	return best;
}

// ---------------------------------------------------------------------------------------------------------
// FindTarget — full supercede
// ---------------------------------------------------------------------------------------------------------

public MRESReturn Detour_AJB_SentryFindTarget_Pre(int sentry, DHookReturn hReturn)
{
	if (!AJB_Sentry_IsRebelOnly())
	{
		return MRES_Ignored;
	}

	if (sentry <= MaxClients || !IsValidEntity(sentry))
	{
		return MRES_Ignored;
	}

	// Only rewrite guard-team sentries.
	if (GetEntProp(sentry, Prop_Send, "m_iTeamNum") != AJB_GetGuardsTeam())
	{
		return MRES_Ignored;
	}

	// Wrangler / not ready: leave stock.
	if (!AJB_Sentry_IsReady(sentry))
	{
		return MRES_Ignored;
	}

	// Prep / between rounds: do not acquire anyone.
	if (AJB_IsPrepActive()
		|| g_RoundState == AJBState_RoundEnd
		|| g_RoundState == AJBState_Waiting
		|| g_RoundState == AJBState_Disabled)
	{
		AJB_Sentry_ClearEnemy(sentry);
		hReturn.Value = false;
		return MRES_Supercede;
	}

	int rebel = AJB_Sentry_FindNearestRebel(sentry);
	if (rebel > 0)
	{
		AJB_Sentry_SetEnemy(sentry, rebel);

		// FoundTarget() does this — without ATTACKING, SentryThink stays in SEARCHING and never Fire()s.
		if (HasEntProp(sentry, Prop_Send, "m_iState"))
		{
			int state = GetEntProp(sentry, Prop_Send, "m_iState");
			if (state != AJB_SENTRY_STATE_ATTACKING && state != AJB_SENTRY_STATE_UPGRADING)
			{
				SetEntProp(sentry, Prop_Send, "m_iState", AJB_SENTRY_STATE_ATTACKING);
			}
		}

		hReturn.Value = true;
		return MRES_Supercede;
	}

	// No rebel: drop lock and return to idle search (same as Attack() losing target).
	AJB_Sentry_ClearEnemy(sentry);
	if (HasEntProp(sentry, Prop_Send, "m_iState"))
	{
		int state = GetEntProp(sentry, Prop_Send, "m_iState");
		if (state == AJB_SENTRY_STATE_ATTACKING)
		{
			SetEntProp(sentry, Prop_Send, "m_iState", AJB_SENTRY_STATE_SEARCHING);
		}
	}

	hReturn.Value = false;
	return MRES_Supercede;
}

// ---------------------------------------------------------------------------------------------------------
// Damage belt
// ---------------------------------------------------------------------------------------------------------

Action AJB_Sentry_FilterDamage(int victim, int inflictor, float &damage)
{
	if (!AJB_Sentry_IsRebelOnly() || damage <= 0.0)
	{
		return Plugin_Continue;
	}

	if (!AJB_IsValidClient(victim) || !AJB_ClientIsPrisoner(victim))
	{
		return Plugin_Continue;
	}

	// Rebels take full sentry damage.
	if (AJB_FlagGet(victim, AJB_PF_REBEL))
	{
		return Plugin_Continue;
	}

	int sentry = AJB_Sentry_FromInflictor(inflictor);
	if (sentry <= 0)
	{
		return Plugin_Continue;
	}

	if (GetEntProp(sentry, Prop_Send, "m_iTeamNum") != AJB_GetGuardsTeam())
	{
		return Plugin_Continue;
	}

	damage = 0.0;
	return Plugin_Changed;
}

// ---------------------------------------------------------------------------------------------------------
// Building placement
// ---------------------------------------------------------------------------------------------------------

int AJB_Sentry_ResolveObjectType(int building, int eventObjectType)
{
	if (eventObjectType == AJB_OBJ_DISPENSER
		|| eventObjectType == AJB_OBJ_TELEPORTER
		|| eventObjectType == AJB_OBJ_SENTRYGUN)
	{
		return eventObjectType;
	}

	if (building > MaxClients && IsValidEntity(building))
	{
		if (HasEntProp(building, Prop_Send, "m_iObjectType"))
		{
			int t = GetEntProp(building, Prop_Send, "m_iObjectType");
			if (t == AJB_OBJ_DISPENSER || t == AJB_OBJ_TELEPORTER || t == AJB_OBJ_SENTRYGUN)
			{
				return t;
			}
		}

		char cls[64];
		GetEntityClassname(building, cls, sizeof(cls));
		if (StrEqual(cls, "obj_sentrygun"))
		{
			return AJB_OBJ_SENTRYGUN;
		}
		if (StrEqual(cls, "obj_dispenser"))
		{
			return AJB_OBJ_DISPENSER;
		}
		if (StrEqual(cls, "obj_teleporter"))
		{
			return AJB_OBJ_TELEPORTER;
		}
	}

	return -1;
}

bool AJB_Sentry_ShouldBlockBuild(int builder, int building, int eventObjectType = -1)
{
	if (!g_bModeActive || g_cvBlockBuildings == null || !g_cvBlockBuildings.BoolValue)
	{
		return false;
	}

	int objType = AJB_Sentry_ResolveObjectType(building, eventObjectType);

	if (objType == AJB_OBJ_SENTRYGUN
		&& g_cvAllowSentry != null
		&& g_cvAllowSentry.BoolValue
		&& AJB_ClientIsGuard(builder))
	{
		// Prep / between rounds: CleanUpMap or short phase wastes the build — block with a clear message.
		if (AJB_IsPrepActive()
			|| g_RoundState == AJBState_RoundEnd
			|| g_RoundState == AJBState_Waiting
			|| g_RoundState == AJBState_Disabled)
		{
			return true;
		}

		return false;
	}

	return true;
}

// Phrase key for a blocked sentry (prep / waiting / round end).
void AJB_Sentry_ReplyBuildBlocked(int client, int objType)
{
	if (objType == AJB_OBJ_SENTRYGUN && AJB_ClientIsGuard(client))
	{
		// Prep or not live yet — same user-facing advice.
		if (AJB_IsPrepActive()
			|| g_RoundState == AJBState_RoundEnd
			|| g_RoundState == AJBState_Waiting
			|| g_RoundState == AJBState_Disabled)
		{
			AJB_Chat(client, "Sentry Wait Round");
			return;
		}
	}

	AJB_Chat(client, "Buildings Blocked");
}

// player_builtobject fires AFTER metal is taken. Refund stock build costs (cap 200).
// TF2 ammo index for metal is 3.
#define AJB_TF_AMMO_METAL     3
#define AJB_TF_METAL_MAX      200
#define AJB_METAL_COST_SENTRY 130
#define AJB_METAL_COST_DISP   100
#define AJB_METAL_COST_TELE   50

int AJB_Sentry_BuildMetalCost(int objType)
{
	if (objType == AJB_OBJ_DISPENSER)
	{
		return AJB_METAL_COST_DISP;
	}
	if (objType == AJB_OBJ_TELEPORTER)
	{
		return AJB_METAL_COST_TELE;
	}
	if (objType == AJB_OBJ_SENTRYGUN)
	{
		return AJB_METAL_COST_SENTRY;
	}
	return 0;
}

void AJB_Sentry_RefundBuildMetal(int client, int objType)
{
	if (!AJB_IsValidClient(client) || !IsPlayerAlive(client))
	{
		return;
	}

	int cost = AJB_Sentry_BuildMetalCost(objType);
	if (cost <= 0)
	{
		return;
	}

	int metal = GetEntProp(client, Prop_Send, "m_iAmmo", _, AJB_TF_AMMO_METAL);
	metal += cost;
	if (metal > AJB_TF_METAL_MAX)
	{
		metal = AJB_TF_METAL_MAX;
	}

	SetEntProp(client, Prop_Send, "m_iAmmo", metal, _, AJB_TF_AMMO_METAL);
}

// Kill a blocked build without leaving a metal pack the player can double-dip.
void AJB_Sentry_RemoveBlockedBuilding(int building)
{
	if (building <= MaxClients || !IsValidEntity(building))
	{
		return;
	}

	// Zero health + silent remove: Avoid Detonate-style metal gibs when possible.
	if (HasEntProp(building, Prop_Send, "m_iHealth"))
	{
		SetEntProp(building, Prop_Send, "m_iHealth", 0);
	}
	if (HasEntProp(building, Prop_Data, "m_iHealth"))
	{
		SetEntProp(building, Prop_Data, "m_iHealth", 0);
	}

	RemoveEntity(building);
}
