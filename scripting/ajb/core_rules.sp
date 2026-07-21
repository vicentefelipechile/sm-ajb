// =========================================================================================================
// Damage rules, rebel flags, building block
// =========================================================================================================

void AJB_HookClient(int client)
{
	if (!IsClientInGame(client) || g_bSDKHooked[client])
	{
		return;
	}

	if (!g_bModeActive)
	{
		return;
	}

	SDKHook(client, SDKHook_OnTakeDamage, AJB_OnTakeDamage);
	g_bSDKHooked[client] = true;
}

void AJB_UnhookClient(int client)
{
	if (!g_bSDKHooked[client])
	{
		return;
	}

	if (IsClientInGame(client))
	{
		SDKUnhook(client, SDKHook_OnTakeDamage, AJB_OnTakeDamage);
	}

	g_bSDKHooked[client] = false;
}

void AJB_HookAllClients()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			AJB_HookClient(i);
		}
	}
}

void AJB_UnhookAllClients()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		AJB_UnhookClient(i);
	}
}

void AJB_SetRebelInternal(int client, bool rebel, bool announce)
{
	if (!AJB_IsValidClient(client))
	{
		return;
	}

	if (g_bRebel[client] == rebel)
	{
		return;
	}

	g_bRebel[client] = rebel;

	Call_StartForward(g_hFwdRebel);
	Call_PushCell(client);
	Call_PushCell(rebel);
	Call_Finish();

	if (announce)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}

			char prefix[32];
			AJB_GetPrefix(i, prefix, sizeof(prefix));
			CPrintToChat(i, "%T", rebel ? "Player Rebel" : "Player Unrebel", i, prefix, client);
		}
	}
}

// Individual wish → next round only. Never clears rebel this round.
void AJB_QueueFreeday(int client, bool freeday)
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	g_bFreedayPending[client] = freeday;

	// Cancel also drops a stale current-round flag.
	if (!freeday)
	{
		g_bFreeday[client] = false;
	}
}

// Current-round only (server-wide Freeday day). Does not clear rebel.
void AJB_ApplyFreedayNow(int client, bool freeday)
{
	if (!AJB_IsValidClient(client))
	{
		return;
	}

	g_bFreeday[client] = freeday;
}

Action AJB_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (!g_bModeActive || damage <= 0.0)
	{
		return Plugin_Continue;
	}

	if (!AJB_IsValidClient(victim) || !AJB_IsValidClient(attacker))
	{
		return Plugin_Continue;
	}

	if (victim == attacker)
	{
		return Plugin_Continue;
	}

	if (AJB_IsPrepActive())
	{
		damage = 0.0;
		return Plugin_Changed;
	}

	bool victimPrisoner = AJB_ClientIsPrisoner(victim);
	bool victimGuard = AJB_ClientIsGuard(victim);
	bool attackerPrisoner = AJB_ClientIsPrisoner(attacker);
	bool attackerGuard = AJB_ClientIsGuard(attacker);

	if (attackerPrisoner && victimGuard)
	{
		if (g_RoundState == AJBState_LastRequest || g_RoundState == AJBState_SpecialDay)
		{
			return Plugin_Continue;
		}

		if (g_cvRebelOnDamage.BoolValue && !g_bRebel[attacker])
		{
			AJB_SetRebelInternal(attacker, true, true);
		}

		if (g_cvBlockPrisonerDamage.BoolValue && !g_bRebel[attacker])
		{
			damage = 0.0;
			return Plugin_Changed;
		}
	}

	if (attackerPrisoner && victimPrisoner && g_RoundState == AJBState_CellsLocked)
	{
		damage = 0.0;
		return Plugin_Changed;
	}

	if (attackerGuard && victimGuard)
	{
		return Plugin_Continue;
	}

	return Plugin_Continue;
}

Action Event_PlayerBuiltObject(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bModeActive || !g_cvBlockBuildings.BoolValue)
	{
		return Plugin_Continue;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!AJB_IsValidClient(client))
	{
		return Plugin_Continue;
	}

	int ent = event.GetInt("index");
	if (ent > MaxClients && IsValidEntity(ent))
	{
		AcceptEntityInput(ent, "Kill");
	}

	AJB_Chat(client, "Buildings Blocked");
	return Plugin_Handled;
}
