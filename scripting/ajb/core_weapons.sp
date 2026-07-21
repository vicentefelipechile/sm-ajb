// =========================================================================================================
// Prisoner loadout strip (melee only)
// =========================================================================================================

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

	// Freeday keeps soft loadout (strip still applies for gun free-roam baseline).
	// Only LR / War Day (SpecialDay) skip the jail strip entirely.
	if (g_RoundState == AJBState_LastRequest || g_RoundState == AJBState_SpecialDay)
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

	// Spy: knife + sapper is base Jailbreak loadout (sapper stays available).
	// Other classes: melee only.
	if (TF2_GetPlayerClass(client) == TFClass_Spy)
	{
		AJB_StripSpyKeepSapper(client);
		return;
	}

	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Primary);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Secondary);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Grenade);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Building);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_PDA);

	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if (melee != -1)
	{
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", melee);
	}
}

void AJB_StripSpyKeepSapper(int client)
{
	// Regenerate restores class weapons, then drop the revolver only.
	// Secondary sapper (and knife/watch/disguise kit) remain usable.
	TF2_RegeneratePlayer(client);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Primary);

	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if (melee != -1)
	{
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", melee);
	}
}
