// =========================================================================================================
// Last Request - Guard Melee
// =========================================================================================================

void Frame_StripGuardToMelee(int userid)
{
	if (!g_bGuardMeleeActive)
	{
		return;
	}

	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && AJB_IsGuard(client))
	{
		AJB_LR_StripGuardToMelee(client);
	}
}

void AJB_LR_StripGuardToMelee(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	// Remove all weapon slots except Melee (slot 2)
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Primary);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Secondary);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Grenade);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Building);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_PDA);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Item1);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Item2);

	if (TF2_GetPlayerClass(client) == TFClass_Spy)
	{
		if (TF2_IsPlayerInCondition(client, TFCond_Stealthed))
		{
			TF2_RemoveCondition(client, TFCond_Stealthed);
		}
		if (TF2_IsPlayerInCondition(client, TFCond_Disguised))
		{
			TF2_RemoveCondition(client, TFCond_Disguised);
		}
	}

	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if (melee != -1 && IsValidEntity(melee))
	{
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", melee);
	}
}


// =========================================================================================================
// Guard Melee Only
// =========================================================================================================

void AJB_LR_DoGuardMelee(int prisoner)
{
	AJB_LR_QueueWish(prisoner, LRWish_GuardMelee, "LR Chose GuardMelee");
}

void AJB_LR_ApplyGuardMelee(const char[] chooserName)
{
	g_bGuardMeleeActive = true;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}
		if (g_bHasCore && AJB_IsGuard(i))
		{
			AJB_LR_StripGuardToMelee(i);
		}
	}

	AJB_OpenCells();
	AJB_LR_ChatAllQueuedApplied(chooserName, "LR Applied GuardMelee");
}

