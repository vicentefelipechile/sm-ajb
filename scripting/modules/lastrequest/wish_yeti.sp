// =========================================================================================================
// Last Request - Escape from the Yeti (Freeze Tag)
// Author: Winewald
// =========================================================================================================

#define LR_YETI_TICK 0.1
#define LR_YETI_RAGE_MAX 100.0
#define LR_YETI_FISTS 5
#define LR_YETI_MILK 222
#define LR_YETI_JARATE 58
#define LR_YETI_CHARGE_LIFT 280.0
#define LR_YETI_CHARGE_DURATION 0.8
#define LR_YETI_ROAR_STUN_TIME 5.0
#define LR_YETI_ROAR_SLOWDOWN 0.75
#define LR_YETI_MILK_RECHARGE_MULTIPLIER 2.0
#define LR_YETI_CLIMB_REACH 100.0
#define LR_YETI_HUD_REFRESH 0.5
#define LR_YETI_THAW_DECAY 0.2
#define LR_YETI_FREEZE_SOUND "physics/glass/glass_impact_bullet1.wav"
#define LR_YETI_THAW_SOUND "physics/glass/glass_cup_break1.wav"
#define LR_YETI_APPEAR_SOUND "player/taunt_yeti_appear_snow.wav"

static const int g_iYetiCosmetics[] = {1187, 1189, 1188};
static const char g_sYetiModels[][] = {
	"models/player/items/heavy/yeti_head.mdl",
	"models/player/items/heavy/yeti_arms.mdl",
	"models/player/items/heavy/yeti_legs.mdl"
};

ConVar g_cvYetiRoundTime;
ConVar g_cvYetiHideTime;
ConVar g_cvYetiPick;
ConVar g_cvYetiSpeed;
ConVar g_cvYetiThawTime;
ConVar g_cvYetiThawRadius;
ConVar g_cvYetiSlowTime;
ConVar g_cvYetiSlowFactor;
ConVar g_cvYetiSlowImmune;
ConVar g_cvYetiRagePerSecond;
ConVar g_cvYetiRagePerFreeze;
ConVar g_cvYetiRoarRadius;
ConVar g_cvYetiRoarReveal;
ConVar g_cvYetiChargeCooldown;
ConVar g_cvYetiChargeForce;
ConVar g_cvYetiClimb;
ConVar g_cvYetiClimbForce;
ConVar g_cvYetiIgnoreWins;
int g_iYetiSavedIgnoreWins = -1;

bool g_bYetiHiding;
int g_iYetiOriginalTeam[MAXPLAYERS + 1];
TFClassType g_YetiOriginalClass;
int g_iYetiLastButtons;
float g_fYetiRage;
float g_fYetiNextCharge;
float g_fYetiChargeUntil;
float g_fYetiSlowUntil;
float g_fYetiImmuneUntil;
float g_fYetiReleaseAt;
float g_fYetiLastTick;
float g_fYetiNextHud;
float g_fYetiRevealUntil[MAXPLAYERS + 1];
float g_fYetiRoarStunUntil[MAXPLAYERS + 1];
bool g_bYetiOwnGlow[MAXPLAYERS + 1];
bool g_bYetiFrozen[MAXPLAYERS + 1];
float g_fYetiThaw[MAXPLAYERS + 1];
MoveType g_YetiOldMove[MAXPLAYERS + 1];
float g_fYetiOldAttack[MAXPLAYERS + 1];
ArrayList g_hYetiTint[MAXPLAYERS + 1];
int g_iYetiWearables[3] = {INVALID_ENT_REFERENCE, ...};
Handle g_hYetiTickTimer;
Handle g_hYetiEndTimer;

// =========================================================================================================
// Setup and loadouts
// =========================================================================================================

void AJB_LR_Yeti_Init()
{
	g_cvYetiRoundTime = CreateConVar("sm_ajb_lr_yeti_round_time", "300", "Yeti: total round seconds; free humans win on timeout.", _, true, 60.0, true, 900.0);
	g_cvYetiHideTime = CreateConVar("sm_ajb_lr_yeti_hide_time", "20", "Yeti: hiding seconds before release (0 = immediate).", _, true, 0.0, true, 60.0);
	g_cvYetiPick = CreateConVar("sm_ajb_lr_yeti_pick", "0", "Yeti: 0 = random guard, 1 = LR chooser; falls back to a random participant.", _, true, 0.0, true, 1.0);
	g_cvYetiSpeed = CreateConVar("sm_ajb_lr_yeti_speed", "340", "Yeti: movement speed.", _, true, 150.0, true, 520.0);
	g_cvYetiThawTime = CreateConVar("sm_ajb_lr_yeti_thaw_time", "5", "Yeti: seconds for one human to thaw a teammate; helpers stack.", _, true, 1.0, true, 30.0);
	g_cvYetiThawRadius = CreateConVar("sm_ajb_lr_yeti_thaw_radius", "160", "Yeti: teammate thaw radius in units.", _, true, 50.0, true, 500.0);
	g_cvYetiSlowTime = CreateConVar("sm_ajb_lr_yeti_slow_time", "3", "Yeti: Jarate/Mad Milk slow duration.", _, true, 0.5, true, 10.0);
	g_cvYetiSlowFactor = CreateConVar("sm_ajb_lr_yeti_slow_factor", "0.45", "Yeti: speed multiplier while slowed.", _, true, 0.1, true, 1.0);
	g_cvYetiSlowImmune = CreateConVar("sm_ajb_lr_yeti_slow_immune", "4", "Yeti: slow immunity seconds after a slow ends.", _, true, 0.0, true, 30.0);
	g_cvYetiRagePerSecond = CreateConVar("sm_ajb_lr_yeti_rage_per_sec", "1.5", "Yeti: rage gained per hunting second.", _, true, 0.0, true, 50.0);
	g_cvYetiRagePerFreeze = CreateConVar("sm_ajb_lr_yeti_rage_per_freeze", "20", "Yeti: rage gained per frozen human.", _, true, 0.0, true, 100.0);
	g_cvYetiRoarRadius = CreateConVar("sm_ajb_lr_yeti_roar_radius", "1500", "Yeti: roar reveal radius.", _, true, 200.0, true, 5000.0);
	g_cvYetiRoarReveal = CreateConVar("sm_ajb_lr_yeti_roar_reveal", "3", "Yeti: roar outline duration.", _, true, 1.0, true, 10.0);
	g_cvYetiChargeCooldown = CreateConVar("sm_ajb_lr_yeti_charge_cooldown", "10", "Yeti: seconds between charges.", _, true, 1.0, true, 60.0);
	g_cvYetiChargeForce = CreateConVar("sm_ajb_lr_yeti_charge_force", "1100", "Yeti: horizontal charge impulse.", _, true, 300.0, true, 3000.0);
	g_cvYetiClimb = CreateConVar("sm_ajb_lr_yeti_climb", "1", "Yeti: fist swings against walls allow climbing.", _, true, 0.0, true, 1.0);
	g_cvYetiClimbForce = CreateConVar("sm_ajb_lr_yeti_climb_force", "600", "Yeti: upward wall-climb impulse.", _, true, 100.0, true, 1500.0);
	AJB_LR_Yeti_InitAmbience();
	g_cvYetiIgnoreWins = FindConVar("mp_ignore_round_win_conditions");
	g_hYetiHud = CreateHudSynchronizer();

	GameData data = new GameData("sm-tf2.games");
	if (data != null)
	{
		int offset = data.GetOffset("RemoveWearable");
		if (offset > 0)
		{
			// EquipWearable immediately precedes RemoveWearable in TF2's player vtable.
			StartPrepSDKCall(SDKCall_Player);
			PrepSDKCall_SetVirtual(offset - 1);
			PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
			g_hYetiEquipWearable = EndPrepSDKCall();
		}
		delete data;
	}
	if (g_hYetiEquipWearable == null) LogError("[AJB-LR] Yeti cosmetics unavailable: could not prepare EquipWearable.");
}

void AJB_LR_Yeti_Precache()
{
	PrecacheSound(LR_YETI_FREEZE_SOUND, true);
	PrecacheSound(LR_YETI_THAW_SOUND, true);
	PrecacheSound(LR_YETI_APPEAR_SOUND, true);
	for (int i = 0; i < sizeof(g_sYetiModels); i++) PrecacheModel(g_sYetiModels[i], true);
	AJB_LR_Yeti_PrecacheAmbience();
}

void AJB_LR_DoYeti(int prisoner)
{
	AJB_LR_QueueWish(prisoner, LRWish_Yeti, "LR Chose Yeti");
	g_iPendingYetiChooser = GetClientUserId(prisoner);
}

bool AJB_LR_Yeti_IsFreeHuman(int client)
{
	return IsClientInGame(client) && client != g_iYeti && IsPlayerAlive(client)
		&& !g_bYetiFrozen[client] && AJB_IsPrisoner(client);
}

int AJB_LR_Yeti_Pick(int chooserUserid)
{
	int players[MAXPLAYERS], guards[MAXPLAYERS];
	int count, guardCount;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || GetClientTeam(i) < 2) continue;
		players[count++] = i;
		if (AJB_IsGuard(i)) guards[guardCount++] = i;
	}
	if (count < 2) return 0;
	int chooser = GetClientOfUserId(chooserUserid);
	if (g_cvYetiPick.BoolValue && chooser > 0 && IsClientInGame(chooser) && GetClientTeam(chooser) > 1) return chooser;
	return guardCount > 0 ? guards[GetRandomInt(0, guardCount - 1)] : players[GetRandomInt(0, count - 1)];
}

void AJB_LR_ApplyYeti(const char[] chooser, int chooserUserid)
{
	int yeti = AJB_LR_Yeti_Pick(chooserUserid);
	if (yeti == 0)
	{
		g_ActiveWish = LRWish_None;
		AJB_ChatAll("LR Yeti Not Enough Players");
		return;
	}
	g_bYeti = true;
	g_bYetiApplying = true;
	g_bYetiEnding = false;
	g_iYeti = yeti;
	g_YetiOriginalClass = TF2_GetPlayerClass(yeti);
	g_fYetiRage = 0.0;
	g_fYetiNextCharge = 0.0;
	g_fYetiChargeUntil = 0.0;
	g_fYetiSlowUntil = 0.0;
	g_fYetiImmuneUntil = 0.0;
	g_iYetiLastButtons = 0;
	float hide = g_cvYetiHideTime.FloatValue;
	g_bYetiHiding = hide > 0.0;
	g_fYetiLastTick = GetGameTime();
	g_fYetiReleaseAt = g_fYetiLastTick + hide;
	g_fYetiNextHud = 0.0;
	// The x86-only SetWinningTeam hook cannot guard empty-team wins on x64 servers.
	if (g_cvYetiIgnoreWins != null)
	{
		g_iYetiSavedIgnoreWins = g_cvYetiIgnoreWins.IntValue;
		g_cvYetiIgnoreWins.SetInt(1);
	}
	AJB_BeginCombatDay();
	AJB_SetupSpecialDay();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || GetClientTeam(i) < 2) continue;
		g_iYetiOriginalTeam[i] = GetClientTeam(i);
		int team = i == yeti ? AJB_GetGuardsTeam() : AJB_GetPrisonersTeam();
		if (GetClientTeam(i) != team) AJB_ChangeTeamSafe(i, team);
		if (i == yeti) TF2_SetPlayerClass(i, TFClass_Heavy, false, true);
		if (!IsPlayerAlive(i) || i == yeti) TF2_RespawnPlayer(i);
	}
	RequestFrame(Frame_YetiSetup);
	float duration = g_cvYetiRoundTime.FloatValue;
	AJB_SetPhaseTimer(duration);
	g_hYetiEndTimer = CreateTimer(duration, Timer_YetiEnd, _, TIMER_FLAG_NO_MAPCHANGE);
	g_hYetiTickTimer = CreateTimer(LR_YETI_TICK, Timer_YetiTick, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	AJB_LR_Yeti_StartAmbience();
	AJB_LR_ChatAllQueuedApplied(chooser, "LR Applied Yeti");
	AJB_ChatAll2N("LR Yeti Is", yeti, RoundToFloor(hide));
	AJB_ChatAll("LR Yeti Tip");
}

void Frame_YetiSetup(any data)
{
	if (!g_bYeti) return;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i)) Frame_YetiPrepareClient(GetClientUserId(i));
	}
	g_bYetiApplying = false;
	if (!g_bYetiHiding) AJB_LR_Yeti_Release();
}

void Event_YetiInventory(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bYeti && !g_bYetiApplying && !g_bYetiEnding)
	{
		RequestFrame(Frame_YetiPrepareClient, event.GetInt("userid"));
	}
}

void Event_YetiPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bYeti || g_bYetiApplying || g_bYetiEnding || event.GetBool("disconnect")) return;
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client == 0) return;
	AJB_LR_Yeti_Thaw(client);
	if (client != g_iYeti && event.GetInt("team") == AJB_GetGuardsTeam())
	{
		RequestFrame(Frame_YetiNormalizeTeam, GetClientUserId(client));
	}
}

void Frame_YetiNormalizeTeam(int userid)
{
	int client = GetClientOfUserId(userid);
	if (!g_bYeti || g_bYetiEnding || client == 0 || client == g_iYeti || !AJB_IsGuard(client)) return;
	if (g_iYetiOriginalTeam[client] == 0) g_iYetiOriginalTeam[client] = GetClientTeam(client);
	bool alive = IsPlayerAlive(client);
	AJB_ChangeTeamSafe(client, AJB_GetPrisonersTeam());
	if (alive) TF2_RespawnPlayer(client);
}

void Frame_YetiPrepareClient(int userid)
{
	int client = GetClientOfUserId(userid);
	if (!g_bYeti || g_bYetiEnding || client == 0 || !IsPlayerAlive(client) || GetClientTeam(client) < 2) return;
	if (client != g_iYeti && AJB_IsGuard(client))
	{
		Frame_YetiNormalizeTeam(userid);
		return;
	}
	if (g_iYetiOriginalTeam[client] == 0) g_iYetiOriginalTeam[client] = GetClientTeam(client);
	if (client == g_iYeti)
	{
		if (TF2_GetPlayerClass(client) != TFClass_Heavy)
		{
			TF2_SetPlayerClass(client, TFClass_Heavy, false, true);
			TF2_RespawnPlayer(client);
			return;
		}
		AJB_StripEventWeapons(client, false);
		AJB_GiveStockWeapon(client, "tf_weapon_fists", LR_YETI_FISTS);
		AJB_LR_Yeti_Dress(client);
		SDKUnhook(client, SDKHook_PreThinkPost, Hook_YetiThink);
		SDKHook(client, SDKHook_PreThinkPost, Hook_YetiThink);
		SDKUnhook(client, SDKHook_Touch, Hook_YetiChargeTouch);
		SDKHook(client, SDKHook_Touch, Hook_YetiChargeTouch);
		g_fYetiChargeUntil = 0.0;
		if (g_bYetiHiding) SetEntityMoveType(client, MOVETYPE_NONE);
	}
	else
	{
		TFClassType cls = TF2_GetPlayerClass(client);
		bool jars = cls == TFClass_Scout || cls == TFClass_Sniper;
		AJB_StripEventWeapons(client, true, jars);
		if (jars && GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary) == -1)
		{
			int jar = AJB_GiveStockWeapon(client, cls == TFClass_Scout ? "tf_weapon_jar_milk" : "tf_weapon_jar",
				cls == TFClass_Scout ? LR_YETI_MILK : LR_YETI_JARATE);
			if (jar != -1)
			{
				int ammo = GetEntProp(jar, Prop_Send, "m_iPrimaryAmmoType");
				if (ammo >= 0) SetEntProp(client, Prop_Send, "m_iAmmo", 1, _, ammo);
			}
		}
	}
	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if (melee > MaxClients) SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", melee);
	AJB_LR_Yeti_ApplyAmbience(client);
}

void AJB_LR_Yeti_RemoveWearables()
{
	for (int i = 0; i < sizeof(g_iYetiWearables); i++)
	{
		int entity = EntRefToEntIndex(g_iYetiWearables[i]);
		if (entity != INVALID_ENT_REFERENCE)
		{
			int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
			if (owner > 0 && owner <= MaxClients && IsClientInGame(owner)) TF2_RemoveWearable(owner, entity);
			else RemoveEntity(entity);
		}
		g_iYetiWearables[i] = INVALID_ENT_REFERENCE;
	}
}

void AJB_LR_Yeti_Dress(int client)
{
	AJB_LR_Yeti_RemoveWearables();
	if (g_hYetiEquipWearable == null) return;
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "tf_wearable")) != -1)
	{
		if (GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client) TF2_RemoveWearable(client, entity);
	}
	for (int i = 0; i < sizeof(g_iYetiCosmetics); i++)
	{
		int wearable = CreateEntityByName("tf_wearable");
		if (wearable == -1)
		{
			LogError("[AJB-LR] Could not create Yeti cosmetic %d.", g_iYetiCosmetics[i]);
			continue;
		}
		SetEntProp(wearable, Prop_Send, "m_iItemDefinitionIndex", g_iYetiCosmetics[i]);
		SetEntProp(wearable, Prop_Send, "m_bInitialized", 1);
		SetEntProp(wearable, Prop_Send, "m_iEntityQuality", 6);
		SetEntProp(wearable, Prop_Send, "m_iEntityLevel", 1);
		SetEntProp(wearable, Prop_Send, "m_bValidatedAttachedEntity", 1);
		if (!DispatchSpawn(wearable))
		{
			LogError("[AJB-LR] Could not spawn Yeti cosmetic %d.", g_iYetiCosmetics[i]);
			RemoveEntity(wearable);
			continue;
		}
		SDKCall(g_hYetiEquipWearable, client, wearable);
		g_iYetiWearables[i] = EntIndexToEntRef(wearable);
	}
}

// =========================================================================================================
// Freeze, thaw and abilities
// =========================================================================================================

void Hook_YetiThink(int client)
{
	if (!g_bYeti || g_bYetiEnding || client != g_iYeti || !IsPlayerAlive(client)) return;
	float speed = g_cvYetiSpeed.FloatValue;
	if (GetGameTime() < g_fYetiSlowUntil) speed *= g_cvYetiSlowFactor.FloatValue;
	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", speed);
}

Action Hook_YetiChargeTouch(int client, int other)
{
	if (!g_bYeti || g_bYetiEnding || g_bYetiApplying || g_bYetiHiding || client != g_iYeti
		|| !IsPlayerAlive(client) || GetGameTime() >= g_fYetiChargeUntil
		|| other < 1 || other > MaxClients || !AJB_LR_Yeti_IsFreeHuman(other)) return Plugin_Continue;
	AJB_LR_Yeti_Freeze(other);
	return Plugin_Continue;
}

Action AJB_LR_Yeti_OnTakeDamage(int victim, int attacker, int weapon, float &damage)
{
	if (g_bYetiEnding) return Plugin_Continue;
	if (victim == g_iYeti || g_bYetiFrozen[victim])
	{
		damage = 0.0;
		return Plugin_Handled;
	}
	if (attacker == g_iYeti && attacker > 0)
	{
		if (!g_bYetiHiding && !g_bYetiApplying && damage > 0.0 && AJB_IsPrisoner(victim)
			&& weapon == GetPlayerWeaponSlot(attacker, TFWeaponSlot_Melee)) AJB_LR_Yeti_Freeze(victim);
		damage = 0.0;
		return Plugin_Handled;
	}
	if (attacker > 0 && attacker <= MaxClients && attacker != victim && IsClientInGame(attacker))
	{
		damage = 0.0;
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

void AJB_LR_Yeti_Freeze(int client)
{
	if (g_bYetiFrozen[client] || !IsPlayerAlive(client)) return;
	g_bYetiFrozen[client] = true;
	g_fYetiThaw[client] = 0.0;
	g_YetiOldMove[client] = GetEntityMoveType(client);
	g_fYetiOldAttack[client] = GetEntPropFloat(client, Prop_Send, "m_flNextAttack");
	TF2_RemoveCondition(client, TFCond_Taunting);
	TF2_RemoveCondition(client, TFCond_Cloaked);
	TF2_RemovePlayerDisguise(client);
	float velocity[3];
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
	SetEntityMoveType(client, MOVETYPE_NONE);
	SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + g_cvYetiRoundTime.FloatValue);
	g_hYetiTint[client] = AJB_TintPlayer(client, 30, 90, 255);
	EmitSoundToAll(LR_YETI_FREEZE_SOUND, client);
	AJB_ChatAll1N("LR Yeti Frozen", client);
	AJB_Chat(client, "LR Yeti Frozen Help");
	g_fYetiRage += g_cvYetiRagePerFreeze.FloatValue;
	if (g_fYetiRage > LR_YETI_RAGE_MAX) g_fYetiRage = LR_YETI_RAGE_MAX;
}

void AJB_LR_Yeti_Thaw(int client)
{
	if (client == g_iYeti) g_fYetiChargeUntil = 0.0;
	if (g_fYetiRoarStunUntil[client] > GetGameTime() && IsClientInGame(client))
	{
		TF2_RemoveCondition(client, TFCond_Dazed);
	}
	g_fYetiRoarStunUntil[client] = 0.0;
	if (!g_bYetiFrozen[client]) return;
	g_bYetiFrozen[client] = false;
	g_fYetiThaw[client] = 0.0;
	AJB_RestoreTint(g_hYetiTint[client]);
	if (!IsClientInGame(client)) return;
	SetEntPropFloat(client, Prop_Send, "m_flNextAttack", g_fYetiOldAttack[client]);
	if (IsPlayerAlive(client)) SetEntityMoveType(client, g_YetiOldMove[client]);
}

public void TF2_OnConditionAdded(int client, TFCond condition)
{
	if (!g_bYeti || g_bYetiEnding || client != g_iYeti
		|| (condition != TFCond_Jarated && condition != TFCond_Milked)) return;
	float now = GetGameTime();
	if (now < g_fYetiImmuneUntil) return;
	g_fYetiSlowUntil = now + g_cvYetiSlowTime.FloatValue;
	g_fYetiImmuneUntil = g_fYetiSlowUntil + g_cvYetiSlowImmune.FloatValue;
	AJB_ChatAll("LR Yeti Slowed");
}

Action Listener_YetiTaunt(int client, const char[] command, int argc)
{
	return g_bYeti && !g_bYetiEnding && client > 0 && (g_bYetiFrozen[client] || (client == g_iYeti && g_bYetiHiding))
		? Plugin_Handled : Plugin_Continue;
}

Action Listener_YetiVoice(int client, const char[] command, int argc)
{
	if (!g_bYeti || g_bYetiEnding || g_bYetiHiding || client != g_iYeti || argc < 2 || !IsPlayerAlive(client)) return Plugin_Continue;
	char menu[8], item[8];
	GetCmdArg(1, menu, sizeof(menu));
	GetCmdArg(2, item, sizeof(item));
	if (!StrEqual(menu, "0") || !StrEqual(item, "0")) return Plugin_Continue;
	if (g_fYetiRage < LR_YETI_RAGE_MAX) return Plugin_Handled;
	g_fYetiRage = 0.0;
	AJB_LR_Yeti_Growl(true);
	float origin[3], position[3];
	GetClientAbsOrigin(client, origin);
	float radius = g_cvYetiRoarRadius.FloatValue;
	float until = GetGameTime() + g_cvYetiRoarReveal.FloatValue;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!AJB_LR_Yeti_IsFreeHuman(i)) continue;
		GetClientAbsOrigin(i, position);
		if (AJB_GetDistanceSqr(origin, position) > radius * radius) continue;
		if (!TF2_IsPlayerInCondition(i, TFCond_Dazed) || g_fYetiRoarStunUntil[i] > GetGameTime())
		{
			g_fYetiRoarStunUntil[i] = GetGameTime() + LR_YETI_ROAR_STUN_TIME;
		}
		TF2_StunPlayer(i, LR_YETI_ROAR_STUN_TIME, LR_YETI_ROAR_SLOWDOWN,
			TF_STUNFLAGS_GHOSTSCARE | TF_STUNFLAG_SLOWDOWN, client);
		if (!GetEntProp(i, Prop_Send, "m_bGlowEnabled"))
		{
			g_bYetiOwnGlow[i] = true;
			SetEntProp(i, Prop_Send, "m_bGlowEnabled", 1);
		}
		g_fYetiRevealUntil[i] = until;
	}
	AJB_ChatAll("LR Yeti Roared");
	return Plugin_Handled;
}

Action AJB_LR_Yeti_OnRunCmd(int client, int &buttons)
{
	if (g_bYetiEnding) return Plugin_Continue;
	if (g_bYetiFrozen[client] || (client == g_iYeti && g_bYetiHiding))
	{
		buttons = 0;
		return Plugin_Changed;
	}
	if (client != g_iYeti || !IsPlayerAlive(client)) return Plugin_Continue;
	bool pressed = (buttons & IN_ATTACK2) && !(g_iYetiLastButtons & IN_ATTACK2);
	g_iYetiLastButtons = buttons;
	float now = GetGameTime();
	if (!pressed || now < g_fYetiNextCharge || now < g_fYetiSlowUntil) return Plugin_Continue;
	g_fYetiNextCharge = now + g_cvYetiChargeCooldown.FloatValue;
	g_fYetiChargeUntil = now + LR_YETI_CHARGE_DURATION;
	float angles[3], velocity[3];
	GetClientEyeAngles(client, angles);
	angles[0] = 0.0;
	GetAngleVectors(angles, velocity, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(velocity, g_cvYetiChargeForce.FloatValue);
	velocity[2] = LR_YETI_CHARGE_LIFT;
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
	AJB_LR_Yeti_Growl(false);
	return Plugin_Continue;
}

public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] weaponname, bool &result)
{
	if (!g_bYeti || g_bYetiEnding || g_bYetiHiding || client != g_iYeti || !g_cvYetiClimb.BoolValue
		|| !IsPlayerAlive(client) || GetPlayerWeaponSlot(client, TFWeaponSlot_Melee) != weapon) return Plugin_Continue;
	float origin[3], angles[3], end[3], normal[3];
	GetClientEyePosition(client, origin);
	GetClientEyeAngles(client, angles);
	if (angles[0] > 60.0) return Plugin_Continue;
	GetAngleVectors(angles, end, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(end, LR_YETI_CLIMB_REACH);
	AddVectors(origin, end, end);
	Handle trace = TR_TraceRayFilterEx(origin, end, MASK_PLAYERSOLID, RayType_EndPoint, Trace_YetiWall);
	bool wall = TR_DidHit(trace);
	if (wall) TR_GetPlaneNormal(trace, normal);
	delete trace;
	if (wall && FloatAbs(normal[2]) < 0.7)
	{
		float velocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
		velocity[2] = g_cvYetiClimbForce.FloatValue;
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
	}
	return Plugin_Continue;
}

bool Trace_YetiWall(int entity, int contentsMask)
{
	return entity == 0 || entity > MaxClients;
}

// =========================================================================================================
// Round tick, victory and cleanup
// =========================================================================================================

void AJB_LR_Yeti_Release()
{
	g_bYetiHiding = false;
	if (g_iYeti > 0 && IsClientInGame(g_iYeti) && IsPlayerAlive(g_iYeti))
	{
		SetEntityMoveType(g_iYeti, MOVETYPE_WALK);
		EmitSoundToAll(LR_YETI_APPEAR_SOUND, g_iYeti);
		AJB_Chat(g_iYeti, "LR Yeti Controls");
	}
	AJB_LR_Yeti_Growl(true);
	AJB_ChatAll("LR Yeti Released");
}

Action Timer_YetiTick(Handle timer)
{
	if (!g_bYeti)
	{
		g_hYetiTickTimer = null;
		return Plugin_Stop;
	}
	if (g_bYetiEnding || g_bYetiApplying) return Plugin_Continue;
	if (g_iYeti == 0 || !IsClientInGame(g_iYeti) || !AJB_IsGuard(g_iYeti))
	{
		AJB_LR_Yeti_End(true);
		return Plugin_Continue;
	}
	float now = GetGameTime();
	float elapsed = now - g_fYetiLastTick;
	g_fYetiLastTick = now;
	if (g_bYetiHiding && now >= g_fYetiReleaseAt) AJB_LR_Yeti_Release();
	if (!g_bYetiHiding) g_fYetiRage += elapsed * g_cvYetiRagePerSecond.FloatValue;
	if (g_fYetiRage > LR_YETI_RAGE_MAX) g_fYetiRage = LR_YETI_RAGE_MAX;
	float positions[MAXPLAYERS + 1][3];
	bool free[MAXPLAYERS + 1];
	int freeCount, frozenCount;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bYetiOwnGlow[i] && now >= g_fYetiRevealUntil[i])
		{
			if (IsClientInGame(i)) SetEntProp(i, Prop_Send, "m_bGlowEnabled", 0);
			g_bYetiOwnGlow[i] = false;
		}
		free[i] = AJB_LR_Yeti_IsFreeHuman(i);
		if (free[i]) freeCount++;
		if (IsClientInGame(i) && IsPlayerAlive(i) && AJB_IsPrisoner(i))
		{
			GetClientAbsOrigin(i, positions[i]);
			if (g_bYetiFrozen[i]) frozenCount++;
			if (TF2_GetPlayerClass(i) == TFClass_Scout)
			{
				int milk = GetPlayerWeaponSlot(i, TFWeaponSlot_Secondary);
				if (milk > MaxClients)
				{
					char classname[32];
					GetEntityClassname(milk, classname, sizeof(classname));
					if (StrEqual(classname, "tf_weapon_jar_milk"))
						AJB_ScaleEffectBarRecharge(milk, elapsed, LR_YETI_MILK_RECHARGE_MULTIPLIER);
				}
			}
		}
	}
	// Check the same snapshot used for thawing so an all-frozen team cannot rescue itself.
	if (freeCount == 0)
	{
		AJB_LR_Yeti_End(false);
		return Plugin_Continue;
	}
	float radius = g_cvYetiThawRadius.FloatValue;
	bool hud = now >= g_fYetiNextHud;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bYetiFrozen[i] || !IsClientInGame(i) || !IsPlayerAlive(i) || !AJB_IsPrisoner(i)) continue;
		int helpers, helper;
		for (int j = 1; j <= MaxClients; j++)
		{
			if (free[j] && AJB_GetDistanceSqr(positions[i], positions[j]) <= radius * radius)
			{
				helpers++;
				helper = j;
			}
		}
		g_fYetiThaw[i] += elapsed * (helpers > 0 ? float(helpers) / g_cvYetiThawTime.FloatValue : -LR_YETI_THAW_DECAY);
		if (g_fYetiThaw[i] < 0.0) g_fYetiThaw[i] = 0.0;
		if (g_fYetiThaw[i] >= 1.0)
		{
			AJB_LR_Yeti_Thaw(i);
			EmitSoundToAll(LR_YETI_THAW_SOUND, i);
			AJB_ChatAll2N("LR Yeti Thawed", helper, i);
		}
		else if (hud && helpers > 0)
		{
			PrintHintText(i, "%T", "LR Yeti Thaw Progress", i, RoundToFloor(g_fYetiThaw[i] * 100.0), helpers);
			for (int j = 1; j <= MaxClients; j++)
			{
				if (free[j] && AJB_GetDistanceSqr(positions[i], positions[j]) <= radius * radius)
					PrintHintText(j, "%T", "LR Yeti Thaw Other", j, i, RoundToFloor(g_fYetiThaw[i] * 100.0));
			}
		}
	}
	AJB_LR_Yeti_ThinkAmbience(now);
	if (hud)
	{
		g_fYetiNextHud = now + LR_YETI_HUD_REFRESH;
		SetHudTextParams(-1.0, 0.82, LR_YETI_HUD_REFRESH + LR_YETI_TICK, 150, 220, 255, 255);
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i)) continue;
			if (i == g_iYeti)
			{
				int charge = now < g_fYetiNextCharge ? RoundToCeil(g_fYetiNextCharge - now) : 0;
				ShowSyncHudText(i, g_hYetiHud, "%T", "LR Yeti Ability HUD", i, RoundToFloor(g_fYetiRage), charge, freeCount, frozenCount);
			}
			else ShowSyncHudText(i, g_hYetiHud, "%T", "LR Yeti Human HUD", i, freeCount, frozenCount);
		}
	}
	return Plugin_Continue;
}

Action Timer_YetiEnd(Handle timer)
{
	g_hYetiEndTimer = null;
	if (g_bYeti && !g_bYetiEnding)
	{
		bool free;
		for (int i = 1; i <= MaxClients; i++)
		{
			if (AJB_LR_Yeti_IsFreeHuman(i)) { free = true; break; }
		}
		AJB_LR_Yeti_End(free);
	}
	return Plugin_Stop;
}

Action Timer_YetiRespawn(Handle timer, int userid)
{
	g_hYetiRespawnTimer = null;
	int client = GetClientOfUserId(userid);
	if (g_bYeti && !g_bYetiEnding && client > 0 && client == g_iYeti && AJB_IsGuard(client) && !IsPlayerAlive(client)) TF2_RespawnPlayer(client);
	return Plugin_Stop;
}

void AJB_LR_Yeti_End(bool humansWin)
{
	if (g_bYetiEnding || !g_bHasCore) return;
	g_bYetiEnding = true;
	if (g_iYetiSavedIgnoreWins >= 0) g_cvYetiIgnoreWins.SetInt(g_iYetiSavedIgnoreWins);
	AJB_ChatAll(humansWin ? "LR Yeti Humans Win" : "LR Yeti Wins");
	AJB_ForceTeamWin(humansWin ? AJB_GetPrisonersTeam() : AJB_GetGuardsTeam());
}

void AJB_LR_Yeti_KillTimers()
{
	delete g_hYetiTickTimer;
	delete g_hYetiEndTimer;
	delete g_hYetiRespawnTimer;
}

void AJB_LR_Yeti_ResetClient(int client)
{
	AJB_LR_Yeti_Thaw(client);
	g_iYetiOriginalTeam[client] = 0;
	g_fYetiRevealUntil[client] = 0.0;
	g_bYetiOwnGlow[client] = false;
	AJB_LR_Yeti_ResetAmbienceClient(client);
}

void AJB_LR_Yeti_Cleanup()
{
	if (!g_bYeti) return;
	g_bYeti = false;
	g_bYetiApplying = false;
	g_bYetiEnding = false;
	g_bYetiHiding = false;
	AJB_LR_Yeti_KillTimers();
	AJB_LR_Yeti_StopAmbience();
	AJB_LR_Yeti_RemoveWearables();
	for (int i = 1; i <= MaxClients; i++)
	{
		AJB_LR_Yeti_Thaw(i);
		if (!IsClientInGame(i)) continue;
		if (g_bYetiOwnGlow[i]) SetEntProp(i, Prop_Send, "m_bGlowEnabled", 0);
		g_bYetiOwnGlow[i] = false;
		g_fYetiRevealUntil[i] = 0.0;
		ClearSyncHud(i, g_hYetiHud);
		if (i == g_iYeti)
		{
			SDKUnhook(i, SDKHook_PreThinkPost, Hook_YetiThink);
			SDKUnhook(i, SDKHook_Touch, Hook_YetiChargeTouch);
			if (IsPlayerAlive(i)) SetEntityMoveType(i, MOVETYPE_WALK);
			if (g_YetiOriginalClass != TFClass_Unknown) TF2_SetPlayerClass(i, g_YetiOriginalClass, false, true);
		}
		if (g_iYetiOriginalTeam[i] > 1 && IsPlayerAlive(i)) TF2_RegeneratePlayer(i);
	}
	// The shared restore preserves spectator opt-outs and revives only living participants.
	AJB_RestoreBalancedTeams(g_iYetiOriginalTeam);
	g_iYeti = 0;
	if (g_iYetiSavedIgnoreWins >= 0)
	{
		g_cvYetiIgnoreWins.SetInt(g_iYetiSavedIgnoreWins);
		g_iYetiSavedIgnoreWins = -1;
	}
}
