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
		AJB_StripToMelee(client);
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
			AJB_StripToMelee(i);
		}
	}

	AJB_OpenCells();
	AJB_LR_ChatAllQueuedApplied(chooserName, "LR Applied GuardMelee");
}

