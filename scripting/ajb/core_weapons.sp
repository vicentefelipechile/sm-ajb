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
	TF2_RegeneratePlayer(client);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Primary);

	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if (melee != -1)
	{
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", melee);
	}
}
