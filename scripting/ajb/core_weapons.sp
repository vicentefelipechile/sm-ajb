// =========================================================================================================
// Prisoner loadout strip (melee only) + ammo pack arming
// =========================================================================================================
// Stock TF2 ammo packs only GiveAmmo() for weapons that use it. Prisoners stripped to melee
// therefore walk through packs with no effect and no game event. When they touch a pack we
// restore their class loadout first so the pack can actually refill (and they get guns).
// =========================================================================================================

// Set from OnPluginStart — when 1, map ammo packs arm stripped prisoners so pickup works.
ConVar g_cvAmmoArmsPrisoners;
// Death drops (tf_ammo_pack) arm RED instantly if left on the ground — strip them while AJB is on.
ConVar g_cvBlockDeathAmmo;

// Item definition indices from configs/ajb/prisoner_loadout.cfg (m_iItemDefinitionIndex).
StringMap g_hPrisonerDefIndexAllow;

#define AJB_PRISONER_LOADOUT_FILE  "configs/ajb/prisoner_loadout.cfg"

void AJB_Weapons_OnPluginStart()
{
	g_cvAmmoArmsPrisoners = CreateConVar(
		"sm_ajb_ammo_arms_prisoners",
		"1",
		"1 = map ammo packs arm melee-only prisoners (full class loadout) so they can take ammo/weapons.",
		_, true, 0.0, true, 1.0);

	g_cvBlockDeathAmmo = CreateConVar(
		"sm_ajb_block_death_ammo",
		"1",
		"1 = delete player death ammo drops (tf_ammo_pack). Map item_ammopack_* are kept.",
		_, true, 0.0, true, 1.0);

	g_hPrisonerDefIndexAllow = new StringMap();
	AJB_Weapons_LoadPrisonerLoadout();

	RegAdminCmd("sm_ajb_prisoner_loadout_reload", Command_ReloadPrisonerLoadout, ADMFLAG_CONFIG,
		"Reload configs/ajb/prisoner_loadout.cfg (allowed RED item definition IDs after strip).");
}

void AJB_Weapons_OnMapStartLoadout()
{
	AJB_Weapons_LoadPrisonerLoadout();
}

Action Command_ReloadPrisonerLoadout(int client, int args)
{
	int n = AJB_Weapons_LoadPrisonerLoadout();
	ReplyToCommand(client, "[AJB] Prisoner loadout reloaded (%d allowed item IDs).", n);
	return Plugin_Handled;
}

void AJB_Weapons_AllowDefIndex(int defIndex)
{
	if (defIndex <= 0 || g_hPrisonerDefIndexAllow == null)
	{
		return;
	}

	char key[16];
	IntToString(defIndex, key, sizeof(key));
	g_hPrisonerDefIndexAllow.SetValue(key, 1);
}

void AJB_Weapons_LoadBuiltinDefIndices()
{
	// Medic mediguns
	AJB_Weapons_AllowDefIndex(29);   // Medi Gun
	AJB_Weapons_AllowDefIndex(35);   // Kritzkrieg
	AJB_Weapons_AllowDefIndex(411);  // Quick-Fix
	AJB_Weapons_AllowDefIndex(998);  // Vaccinator
	// Mobility
	AJB_Weapons_AllowDefIndex(1179); // Thermal Thruster
	AJB_Weapons_AllowDefIndex(1101);  // B.A.S.E. Jumper
	// Demo shields
	AJB_Weapons_AllowDefIndex(131);  // Chargin' Targe
	AJB_Weapons_AllowDefIndex(406);   // Splendid Screen
	AJB_Weapons_AllowDefIndex(1099);  // Tide Turner
	AJB_Weapons_AllowDefIndex(1144);  // Festive Targe
	// Spy sappers
	AJB_Weapons_AllowDefIndex(735);
	AJB_Weapons_AllowDefIndex(736);
	AJB_Weapons_AllowDefIndex(810);
	AJB_Weapons_AllowDefIndex(831);
	AJB_Weapons_AllowDefIndex(933);
	AJB_Weapons_AllowDefIndex(1080);
	AJB_Weapons_AllowDefIndex(1102);
	// Soldier banners (team buff)
	AJB_Weapons_AllowDefIndex(129);  // Buff Banner
	AJB_Weapons_AllowDefIndex(226);  // Battalion's Backup
	AJB_Weapons_AllowDefIndex(354);  // Concheror
	// Sniper thrown (Jarate)
	AJB_Weapons_AllowDefIndex(58);   // Jarate
	AJB_Weapons_AllowDefIndex(1083); // Self-Aware Beauty Mark
	// Scout thrown (Mad Milk)
	AJB_Weapons_AllowDefIndex(222);  // Mad Milk
	AJB_Weapons_AllowDefIndex(1121); // Mutated Milk
}

// Returns number of item definition IDs loaded.
int AJB_Weapons_LoadPrisonerLoadout()
{
	if (g_hPrisonerDefIndexAllow == null)
	{
		g_hPrisonerDefIndexAllow = new StringMap();
	}
	g_hPrisonerDefIndexAllow.Clear();

	AJB_Weapons_LoadBuiltinDefIndices();

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), AJB_PRISONER_LOADOUT_FILE);

	if (!FileExists(path))
	{
		LogMessage("[AJB] %s missing — using built-in item ID allowlist (%d entries).",
			AJB_PRISONER_LOADOUT_FILE, g_hPrisonerDefIndexAllow.Size);
		return g_hPrisonerDefIndexAllow.Size;
	}

	KeyValues kv = new KeyValues("PrisonerLoadout");
	if (!kv.ImportFromFile(path))
	{
		LogError("[AJB] Failed to parse %s — keeping built-in item ID allowlist.", path);
		delete kv;
		return g_hPrisonerDefIndexAllow.Size;
	}

	// File replaces defaults when present.
	g_hPrisonerDefIndexAllow.Clear();

	if (kv.JumpToKey("weapons"))
	{
		if (kv.GotoFirstSubKey(false))
		{
			do
			{
				char idStr[16];
				kv.GetSectionName(idStr, sizeof(idStr));
				if (idStr[0] == '\0' || idStr[0] == '/')
				{
					continue;
				}

				int defIndex = StringToInt(idStr);
				if (defIndex > 0)
				{
					AJB_Weapons_AllowDefIndex(defIndex);
				}
			}
			while (kv.GotoNextKey(false));
			kv.GoBack();
		}
		kv.GoBack();
	}

	delete kv;

	LogMessage("[AJB] Prisoner loadout: %d allowed item definition IDs from %s.",
		g_hPrisonerDefIndexAllow.Size, AJB_PRISONER_LOADOUT_FILE);
	return g_hPrisonerDefIndexAllow.Size;
}

bool AJB_Weapons_IsDefIndexAllowed(int defIndex)
{
	if (g_hPrisonerDefIndexAllow == null || defIndex <= 0)
	{
		return false;
	}

	char key[16];
	IntToString(defIndex, key, sizeof(key));
	int dummy;
	return g_hPrisonerDefIndexAllow.GetValue(key, dummy);
}

bool AJB_Weapons_IsEntityAllowed(int ent)
{
	if (ent <= MaxClients || !IsValidEntity(ent))
	{
		return false;
	}

	if (!HasEntProp(ent, Prop_Send, "m_iItemDefinitionIndex"))
	{
		return false;
	}

	int defIndex = GetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex");
	return AJB_Weapons_IsDefIndexAllowed(defIndex);
}

void AJB_Weapons_OnMapStart()
{
	// Late hooks for map packs already in the world (and mid-round plugin reload).
	int maxEnts = GetMaxEntities();
	for (int ent = MaxClients + 1; ent < maxEnts; ent++)
	{
		if (!IsValidEntity(ent))
		{
			continue;
		}

		char classname[64];
		GetEntityClassname(ent, classname, sizeof(classname));

		// Purge any leftover death packs from a previous life / mid-reload.
		if (StrEqual(classname, "tf_ammo_pack"))
		{
			if (g_bModeActive && g_cvBlockDeathAmmo != null && g_cvBlockDeathAmmo.BoolValue)
			{
				AcceptEntityInput(ent, "Kill");
			}
			continue;
		}

		if (AJB_Weapons_IsMapAmmoPack(classname))
		{
			AJB_Weapons_HookAmmoPack(ent);
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// Death drop: remove while AJB is active (except combat days — stock ammo packs).
	if (StrEqual(classname, "tf_ammo_pack"))
	{
		if (g_bModeActive
			&& !AJB_IsCombatDay()
			&& g_cvBlockDeathAmmo != null
			&& g_cvBlockDeathAmmo.BoolValue)
		{
			RequestFrame(Frame_KillDeathAmmoPack, EntIndexToEntRef(entity));
		}
		return;
	}

	if (!AJB_Weapons_IsMapAmmoPack(classname))
	{
		return;
	}

	// Map-placed packs — arming hook next frame (spawn props not ready yet).
	RequestFrame(Frame_HookAmmoPack, EntIndexToEntRef(entity));
}

void Frame_KillDeathAmmoPack(int entRef)
{
	int entity = EntRefToEntIndex(entRef);
	if (entity > MaxClients && IsValidEntity(entity))
	{
		// Re-check: mode/cvar can flip mid-frame; only kill real death packs.
		char classname[32];
		GetEntityClassname(entity, classname, sizeof(classname));
		if (StrEqual(classname, "tf_ammo_pack")
			&& g_bModeActive
			&& !AJB_IsCombatDay()
			&& g_cvBlockDeathAmmo != null
			&& g_cvBlockDeathAmmo.BoolValue)
		{
			AcceptEntityInput(entity, "Kill");
		}
	}
}

void Frame_HookAmmoPack(int entRef)
{
	int entity = EntRefToEntIndex(entRef);
	if (entity > MaxClients && IsValidEntity(entity))
	{
		AJB_Weapons_HookAmmoPack(entity);
	}
}

// Map entities only (not player death drops).
bool AJB_Weapons_IsMapAmmoPack(const char[] classname)
{
	return StrEqual(classname, "item_ammopack_small")
		|| StrEqual(classname, "item_ammopack_medium")
		|| StrEqual(classname, "item_ammopack_full");
}

void AJB_Weapons_HookAmmoPack(int entity)
{
	// Avoid double-hook on map scan + OnEntityCreated.
	SDKUnhook(entity, SDKHook_Touch, AJB_Weapons_OnAmmoTouch);
	SDKHook(entity, SDKHook_Touch, AJB_Weapons_OnAmmoTouch);
}

Action AJB_Weapons_OnAmmoTouch(int entity, int other)
{
	if (!g_bModeActive || g_cvAmmoArmsPrisoners == null || !g_cvAmmoArmsPrisoners.BoolValue)
	{
		return Plugin_Continue;
	}

	if (other < 1 || other > MaxClients || !IsClientInGame(other) || !IsPlayerAlive(other))
	{
		return Plugin_Continue;
	}

	if (!AJB_ClientIsPrisoner(other))
	{
		return Plugin_Continue;
	}

	// Combat day: everyone already has full guns; stock ammo only.
	if (AJB_IsCombatDay())
	{
		return Plugin_Continue;
	}

	// Pure LR menu phase (not a resolved combat day).
	if (AJB_IsLRPhase(g_RoundState))
	{
		return Plugin_Continue;
	}

	// Already has a primary that can take ammo — let stock GiveAmmo run alone
	// (engine only consumes the pack when the player actually needs ammo).
	bool needsArm = (GetPlayerWeaponSlot(other, TFWeaponSlot_Primary) == -1);
	if (needsArm)
	{
		// Melee-only: restore class weapons, but EMPTY of ammo.
		// Then stock ItemTouch → GiveAmmo actually grants something and consumes the pack.
		// (If we left them full from Regenerate, the pack would never be taken.)
		TF2_RegeneratePlayer(other);
		AJB_Weapons_EmptyAllAmmo(other);
	}

	// Grabbing map ammo / arming = freerun with guns → rebel (ends personal freeday).
	if (!g_bRebel[other])
	{
		AJB_SetRebelInternal(other, true, true, 0);
	}

	return Plugin_Continue;
}

// Strip clips + reserve ammo so the next GiveAmmo (this same touch, if PRE) can fill and eat the pack.
void AJB_Weapons_EmptyAllAmmo(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	// Reserve ammo types (TF2 uses a fixed ammo array on the player).
	for (int i = 0; i < 32; i++)
	{
		SetEntProp(client, Prop_Send, "m_iAmmo", 0, _, i);
	}

	// Clips on equipped weapons (primary/secondary/melee/etc.).
	for (int slot = 0; slot <= 5; slot++)
	{
		int wep = GetPlayerWeaponSlot(client, slot);
		if (wep <= MaxClients || !IsValidEntity(wep))
		{
			continue;
		}

		if (HasEntProp(wep, Prop_Send, "m_iClip1"))
		{
			SetEntProp(wep, Prop_Send, "m_iClip1", 0);
		}
		if (HasEntProp(wep, Prop_Data, "m_iClip1"))
		{
			SetEntProp(wep, Prop_Data, "m_iClip1", 0);
		}
		if (HasEntProp(wep, Prop_Send, "m_iClip2"))
		{
			SetEntProp(wep, Prop_Send, "m_iClip2", 0);
		}
	}
}

Action Timer_StripPrisoner(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!g_bModeActive || !AJB_IsValidClient(client, true))
	{
		return Plugin_Stop;
	}

	if (!AJB_ClientIsPrisoner(client))
	{
		return Plugin_Stop;
	}

	if (AJB_IsLRPhase(g_RoundState) || g_RoundState == AJBState_SpecialDay || AJB_IsCombatDay())
	{
		return Plugin_Stop;
	}

	AJB_StripToMelee(client);
	return Plugin_Stop;
}

void AJB_StripToMelee(int client)
{
	if (!AJB_IsValidClient(client, true))
	{
		return;
	}

	// Strip every loadout slot except melee, unless m_iItemDefinitionIndex is allowlisted
	// (configs/ajb/prisoner_loadout.cfg — numeric item IDs).
	for (int slot = 0; slot <= 7; slot++)
	{
		if (slot == view_as<int>(TFWeaponSlot_Melee))
		{
			continue;
		}

		AJB_Weapons_StripSlotUnlessAllowed(client, slot);
	}

	// Weapon-like wearables (demo shield, etc.) — never strip hats (generic tf_wearable).
	AJB_Weapons_StripDisallowedWeaponWearables(client);

	if (TF2_GetPlayerClass(client) == TFClass_Spy)
	{
		AJB_Weapons_ClearSpyStealth(client);
	}

	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if (melee != -1)
	{
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", melee);
	}
}

void AJB_Weapons_StripSlotUnlessAllowed(int client, int slot)
{
	int wep = GetPlayerWeaponSlot(client, slot);
	if (wep <= MaxClients || !IsValidEntity(wep))
	{
		return;
	}

	if (AJB_Weapons_IsEntityAllowed(wep))
	{
		return;
	}

	// Remove only this weapon entity (do not TF2_RemoveWeaponSlot if we ever multi-item a slot).
	char classname[64];
	GetEntityClassname(wep, classname, sizeof(classname));

	if (HasEntProp(client, Prop_Send, "m_hActiveWeapon")
		&& GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") == wep)
	{
		int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
		if (melee != -1)
		{
			SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", melee);
		}
	}

	RemovePlayerItem(client, wep);
	AcceptEntityInput(wep, "Kill");
}

// Demo shields etc. are wearables owned by the player, not weapon slots.
void AJB_Weapons_StripDisallowedWeaponWearables(int client)
{
	static const char kWeaponWearables[][] = {
		"tf_wearable_demoshield",
		"tf_wearable_razorback"
	};

	int maxE = GetMaxEntities();
	for (int ent = MaxClients + 1; ent < maxE; ent++)
	{
		if (!IsValidEntity(ent))
		{
			continue;
		}

		if (!HasEntProp(ent, Prop_Send, "m_hOwnerEntity"))
		{
			continue;
		}

		if (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") != client)
		{
			continue;
		}

		char classname[64];
		GetEntityClassname(ent, classname, sizeof(classname));

		bool isWeaponWearable = false;
		for (int i = 0; i < sizeof(kWeaponWearables); i++)
		{
			if (StrEqual(classname, kWeaponWearables[i]))
			{
				isWeaponWearable = true;
				break;
			}
		}

		if (!isWeaponWearable)
		{
			continue;
		}

		if (AJB_Weapons_IsEntityAllowed(ent))
		{
			continue;
		}

		AcceptEntityInput(ent, "Kill");
	}
}

void AJB_Weapons_ClearSpyStealth(int client)
{
	if (TF2_IsPlayerInCondition(client, TFCond_Cloaked))
	{
		TF2_RemoveCondition(client, TFCond_Cloaked);
	}
	if (TF2_IsPlayerInCondition(client, TFCond_CloakFlicker))
	{
		TF2_RemoveCondition(client, TFCond_CloakFlicker);
	}
	if (TF2_IsPlayerInCondition(client, TFCond_Stealthed))
	{
		TF2_RemoveCondition(client, TFCond_Stealthed);
	}
	if (TF2_IsPlayerInCondition(client, TFCond_StealthedUserBuffFade))
	{
		TF2_RemoveCondition(client, TFCond_StealthedUserBuffFade);
	}
	if (TF2_IsPlayerInCondition(client, TFCond_Disguised))
	{
		TF2_RemoveCondition(client, TFCond_Disguised);
	}
	if (TF2_IsPlayerInCondition(client, TFCond_Disguising))
	{
		TF2_RemoveCondition(client, TFCond_Disguising);
	}
	if (TF2_IsPlayerInCondition(client, TFCond_DeadRingered))
	{
		TF2_RemoveCondition(client, TFCond_DeadRingered);
	}

	// Meter empty so even residual watch UI cannot cloak.
	if (HasEntProp(client, Prop_Send, "m_flCloakMeter"))
	{
		SetEntPropFloat(client, Prop_Send, "m_flCloakMeter", 0.0);
	}
}
