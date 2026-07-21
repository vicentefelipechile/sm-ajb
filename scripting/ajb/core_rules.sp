// =========================================================================================================
// Damage rules, rebel flags, building block
// =========================================================================================================

void AJB_HookClient(int client)
{
	if (!IsClientInGame(client) || g_bSDKHooked[client])
	{
		return;
	}

	// Only attach damage hooks while the mode is active — idle cleanly otherwise.
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
			PrintToChat(i, "%T", rebel ? "Player Rebel" : "Player Unrebel", i, prefix, client);
		}
	}
}

/**
 * Queue an individual freeday wish for the NEXT round.
 * Does not touch current-round rebel or current freeday combat state.
 * (Applying freeday to a rebel mid-round and clearing rebel would be wrong.)
 */
void AJB_QueueFreeday(int client, bool freeday)
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	g_bFreedayPending[client] = freeday;

	// Explicit cancel: also drop a leftover active flag if they somehow have one.
	if (!freeday)
	{
		g_bFreeday[client] = false;
	}
}

/**
 * Apply freeday on the CURRENT round only (e.g. server-wide Freeday day).
 * Does not clear rebel — caller decides (War/Freeday day already reset or ignore rebel).
 */
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

	// No combat during preparation window.
	if (AJB_IsPrepActive())
	{
		damage = 0.0;
		return Plugin_Changed;
	}

	bool victimPrisoner = AJB_ClientIsPrisoner(victim);
	bool victimGuard = AJB_ClientIsGuard(victim);
	bool attackerPrisoner = AJB_ClientIsPrisoner(attacker);
	bool attackerGuard = AJB_ClientIsGuard(attacker);

	// Rebel is ONLY from prisoner → guard damage (or admin). Never from orders/cells/talk.
	// Freeday = free roam / soft rules, NOT free fire on guards — that would kill the rebel system.
	// Free combat without rebel only on Last Request or War Day (SpecialDay).
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

		// Non-rebels cannot hurt guards on a normal (or freeday) jail round.
		if (g_cvBlockPrisonerDamage.BoolValue && !g_bRebel[attacker])
		{
			damage = 0.0;
			return Plugin_Changed;
		}
	}

	// Optional: block friendly prisoner-on-prisoner freefight until cells open (keep simple for MVP).
	if (attackerPrisoner && victimPrisoner && g_RoundState == AJBState_CellsLocked)
	{
		damage = 0.0;
		return Plugin_Changed;
	}

	// Silence unused warning for guard/guard — allowed.
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
