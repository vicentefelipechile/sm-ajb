// =========================================================================================================
// Damage rules, rebel flags, building block
// =========================================================================================================

void AJB_HookClient(int client)
{
	if (!IsClientInGame(client) || g_bSDKHooked[client])
	{
		return;
	}

	// Always hook while connected — mode is checked inside the callbacks.
	// (If we skip when mode is off, a late-enable can leave clients unhooked.)
	SDKHook(client, SDKHook_OnTakeDamage, AJB_OnTakeDamage);
	SDKHook(client, SDKHook_TraceAttack, AJB_OnTraceAttack);
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
		SDKUnhook(client, SDKHook_TraceAttack, AJB_OnTraceAttack);
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

// source = who marked/pardoned (warden/admin). 0 = system (e.g. damage auto-rebel).
void AJB_SetRebelInternal(int client, bool rebel, bool announce, int source = 0)
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

	// Rebel and personal freeday are mutually exclusive.
	if (rebel && g_bFreeday[client])
	{
		g_bFreeday[client] = false;
		AJB_Freeday_OnApplied(client, false);
	}

	// Sentry AI: clear residual cloak + drop non-rebel locks so they re-acquire this frame.
	AJB_Sentry_OnRebelChanged(client, rebel);

	Call_StartForward(g_hFwdRebel);
	Call_PushCell(client);
	Call_PushCell(rebel);
	Call_Finish();

	if (!announce)
	{
		return;
	}

	bool hasSource = (source > 0 && source <= MaxClients && IsClientInGame(source));

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));

		if (hasSource)
		{
			// {1}=prefix, {2}=warden/admin who acted, {3}=target prisoner
			CPrintToChat(i, "%T", rebel ? "Player Rebel" : "Player Unrebel", i, prefix, source, client);
		}
		else
		{
			// Auto (damage, native, etc.): no actor name.
			CPrintToChat(i, "%T", rebel ? "Player Rebel Auto" : "Player Unrebel Auto", i, prefix, client);
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

// Current-round personal freeday. Clears rebel. Trail + optional teleport.
void AJB_ApplyFreedayNow(int client, bool freeday)
{
	if (!AJB_IsValidClient(client))
	{
		return;
	}

	g_bFreeday[client] = freeday;

	if (freeday)
	{
		g_bRebel[client] = false;
		AJB_Freeday_OnApplied(client, true);
	}
	else
	{
		AJB_Freeday_OnApplied(client, false);
	}
}

// Prisoner hit a guard → become rebel (damage auto). Safe to call often.
// Also ends personal freeday (armed/aggressive freerun).
void AJB_TryRebelFromAttack(int attacker, int victim)
{
	if (!g_bModeActive || !g_cvRebelOnDamage.BoolValue || !g_bRebelOnHit)
	{
		return;
	}

	if (!AJB_IsValidClient(attacker) || !AJB_IsValidClient(victim) || attacker == victim)
	{
		return;
	}

	// Combat days act like normal rounds for rebel; only pure LR menu phase skips.
	if (AJB_IsLRPhase(g_RoundState) && !AJB_IsCombatDay())
	{
		return;
	}

	if (!AJB_ClientIsPrisoner(attacker) || !AJB_ClientIsGuard(victim))
	{
		return;
	}

	if (g_bRebel[attacker])
	{
		return;
	}

	AJB_SetRebelInternal(attacker, true, true, 0);
}

// Fires on hit registration (even when later hooks zero damage).
Action AJB_OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	if (!g_bModeActive)
	{
		return Plugin_Continue;
	}

	AJB_TryRebelFromAttack(attacker, victim);
	return Plugin_Continue;
}

Action AJB_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (!g_bModeActive)
	{
		return Plugin_Continue;
	}

	// Mark rebel BEFORE the damage <= 0 early-out. Other plugins (or our own block)
	// may have zeroed damage already — the hit still counts as rebelling.
	AJB_TryRebelFromAttack(attacker, victim);

	if (damage <= 0.0)
	{
		return Plugin_Continue;
	}

	// Sentry / rocket vs non-rebel prisoners: always zero (body-block protection).
	// Runs before the living-attacker checks — sentry builder may be valid, but inflictor is the gun.
	Action sentryAct = AJB_Sentry_FilterDamage(victim, inflictor, damage);
	if (sentryAct != Plugin_Continue)
	{
		return sentryAct;
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
	bool attackerPrisoner = AJB_ClientIsPrisoner(attacker);
	bool victimGuard = AJB_ClientIsGuard(victim);
	bool attackerGuard = AJB_ClientIsGuard(attacker);

	// Personal freeday: only the warden (or world/non-player) may damage them.
	if (victimPrisoner && g_bFreeday[victim] && !g_bRebel[victim]
		&& g_bFreedayWardenOnlyDamage
		&& !AJB_IsCombatDay())
	{
		if (attackerGuard && !AJB_IsWarden(attacker))
		{
			damage = 0.0;
			return Plugin_Changed;
		}
	}

	if (attackerPrisoner && victimGuard)
	{
		// Combat day / hot reds special handling above rebel; war day allows free fire.
		if (AJB_IsCombatDay())
		{
			return Plugin_Continue;
		}

		if (AJB_IsLRPhase(g_RoundState))
		{
			return Plugin_Continue;
		}

		// Non-rebels cannot hurt guards. Rebel mark already attempted above, so a
		// successful auto-rebel allows this same hit to deal damage.
		if (g_cvBlockPrisonerDamage.BoolValue && !g_bRebel[attacker])
		{
			damage = 0.0;
			return Plugin_Changed;
		}
	}

	if (attackerPrisoner && victimPrisoner && g_RoundState == AJBState_CellsLocked && !AJB_IsCombatDay())
	{
		damage = 0.0;
		return Plugin_Changed;
	}

	// A guard's crit splash landing on a cluster of prisoners is a mass-freekill candidate.
	if (attackerGuard && victimPrisoner)
	{
		Action fkAct = AJB_Freekill_FilterDamage(victim, attacker, inflictor, damagetype);
		if (fkAct != Plugin_Continue)
		{
			return fkAct;
		}
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

	// TF2: "object" = type (0 disp, 1 tele, 2 sentry), "index" = entity index.
	int objType = event.GetInt("object");
	int ent = event.GetInt("index");

	if (!AJB_Sentry_ShouldBlockBuild(client, ent, objType))
	{
		// Guard sentry allowed (sm_ajb_allow_sentry) during live round.
		return Plugin_Continue;
	}

	// player_builtobject is AFTER metal is spent — remove building + refund cost so it is not a tax.
	AJB_Sentry_RemoveBlockedBuilding(ent);
	AJB_Sentry_RefundBuildMetal(client, objType);
	AJB_Sentry_ReplyBuildBlocked(client, objType);
	return Plugin_Handled;
}
