// =========================================================================================================
// Last Request - Sniper
// =========================================================================================================

void AJB_LR_DoSniper(int prisoner)
{
	// NEXT round Sniper wish.
	AJB_LR_QueueWish(prisoner, LRWish_Sniper, "LR Chose Sniper");
}

void AJB_LR_ApplySniper(const char[] chooser)
{
	g_bSniper = true;
	AJB_LR_KillSniperTimer();

	float minTime = g_cvSniperMin.FloatValue;
	float maxTime = g_cvSniperMax.FloatValue;
	if (maxTime < minTime)
	{
		maxTime = minTime;
	}

	float nextInterval = GetRandomFloat(minTime, maxTime);
	g_hSniperTimer = CreateTimer(nextInterval, Timer_SniperShot, _, TIMER_FLAG_NO_MAPCHANGE);

	AJB_LR_ChatAllQueuedApplied(chooser, "LR Applied Sniper");
}

Action Timer_SniperShot(Handle timer)
{
	g_hSniperTimer = null;

	if (!g_bSniper || !g_bHasCore || !AJB_IsEnabled())
	{
		return Plugin_Stop;
	}

	// Pick a random alive player (Prisoner or Guard)
	int candidates[MAXPLAYERS];
	int count = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i))
		{
			candidates[count++] = i;
		}
	}

	if (count > 0)
	{
		int victim = candidates[GetRandomInt(0, count - 1)];

		// Play sniper gunshot sound globally
		EmitSoundToAll("weapons/sniper_railgun_shot.wav", victim, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE);
		EmitSoundToAll("weapons/sniper_shoot.wav", victim, SNDCHAN_STATIC, SNDLEVEL_GUNFIRE);

		// Random 3D direction vector
		float forceMag = g_cvSniperForce.FloatValue;
		float vecForce[3];
		vecForce[0] = GetRandomFloat(-1.0, 1.0);
		vecForce[1] = GetRandomFloat(-1.0, 1.0);
		vecForce[2] = GetRandomFloat(0.3, 1.0); // slight upward bias for dramatic ragdoll launch
		NormalizeVector(vecForce, vecForce);
		ScaleVector(vecForce, forceMag);

		// Announce sniper hit
		char prefix[32];
		for (int j = 1; j <= MaxClients; j++)
		{
			if (IsClientInGame(j) && !IsFakeClient(j))
			{
				AJB_GetPrefix(j, prefix, sizeof(prefix));
				CPrintToChat(j, "%T", "LR Sniper Shot", j, prefix, victim);
			}
		}

		// Apply lethal damage with force
		SDKHooks_TakeDamage(victim, 0, 0, 5000.0, DMG_BULLET | DMG_CRIT, -1, vecForce);

		// Post-frame ragdoll force impulse boost for TF2 ragdolls
		DataPack pack = new DataPack();
		pack.WriteCell(GetClientUserId(victim));
		pack.WriteFloat(vecForce[0]);
		pack.WriteFloat(vecForce[1]);
		pack.WriteFloat(vecForce[2]);
		RequestFrame(Frame_ApplyRagdollForce, pack);
	}

	// Schedule next shot
	float nextMin = g_cvSniperMin.FloatValue;
	float nextMax = g_cvSniperMax.FloatValue;
	if (nextMax < nextMin)
	{
		nextMax = nextMin;
	}

	float nextInterval = GetRandomFloat(nextMin, nextMax);
	g_hSniperTimer = CreateTimer(nextInterval, Timer_SniperShot, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

void Frame_ApplyRagdollForce(DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	float force[3];
	force[0] = pack.ReadFloat();
	force[1] = pack.ReadFloat();
	force[2] = pack.ReadFloat();
	delete pack;

	int client = GetClientOfUserId(userid);
	if (client < 1 || !IsClientInGame(client))
	{
		return;
	}

	int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if (ragdoll > 0 && IsValidEntity(ragdoll))
	{
		TeleportEntity(ragdoll, NULL_VECTOR, NULL_VECTOR, force);
	}
}

void AJB_LR_KillSniperTimer()
{
	if (g_hSniperTimer != null)
	{
		delete g_hSniperTimer;
		g_hSniperTimer = null;
	}
}

