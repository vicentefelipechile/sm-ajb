// =========================================================================================================
// Last Request - Sniper
// =========================================================================================================

void AJB_LR_ScheduleSniperShot()
{
	float minTime = g_cvSniperMin.FloatValue;
	float maxTime = g_cvSniperMax.FloatValue;
	if (maxTime < minTime)
	{
		maxTime = minTime;
	}

	float nextInterval = GetRandomFloat(minTime, maxTime);
	g_hSniperTimer = CreateTimer(nextInterval, Timer_SniperShot, _, TIMER_FLAG_NO_MAPCHANGE);
}

void AJB_LR_SniperShoot(int victim, float damage, bool headshot = false)
{
	EmitSoundToAll("weapons/sniper_railgun_shot.wav", victim, SNDCHAN_WEAPON, SNDLEVEL_GUNFIRE);
	EmitSoundToAll("weapons/sniper_shoot.wav", victim, SNDCHAN_STATIC, SNDLEVEL_GUNFIRE);

	if (damage <= 0.0)
	{
		AJB_ChatAll1N("LR Sniper Miss", victim);
		return;
	}

	float vecForce[3];
	vecForce[0] = GetRandomFloat(-1.0, 1.0);
	vecForce[1] = GetRandomFloat(-1.0, 1.0);
	vecForce[2] = GetRandomFloat(0.3, 1.0);
	NormalizeVector(vecForce, vecForce);
	ScaleVector(vecForce, g_cvSniperForce.FloatValue);

	if (headshot)
	{
		AJB_ChatAll1N("LR Sniper Shot", victim);
	}
	else
	{
		AJB_ChatAll1N("LR Sniper Body Shot", victim);
	}

	SDKHooks_TakeDamage(victim, 0, 0, damage, DMG_BULLET | (headshot ? DMG_CRIT : 0), -1, vecForce, NULL_VECTOR, false);
	if (IsPlayerAlive(victim))
	{
		return;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(victim));
	pack.WriteFloat(vecForce[0]);
	pack.WriteFloat(vecForce[1]);
	pack.WriteFloat(vecForce[2]);
	RequestFrame(Frame_ApplyRagdollForce, pack);
}

void AJB_LR_DoSniper(int prisoner)
{
	AJB_LR_QueueWish(prisoner, LRWish_Sniper, "LR Chose Sniper");
}

void AJB_LR_ApplySniper(const char[] chooser)
{
	g_bSniper = true;
	AJB_LR_KillSniperTimer();
	AJB_LR_ScheduleSniperShot();

	AJB_LR_ChatAllQueuedApplied(chooser, "LR Applied Sniper");
	AJB_ChatAll("LR Sniper Rules");
}

Action Timer_SniperShot(Handle timer)
{
	g_hSniperTimer = null;

	if (!g_bSniper || !AJB_LR_CanRun())
	{
		return Plugin_Stop;
	}

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

		float damage = 0.0;
		float chance = g_cvSniperHitChance.FloatValue;
		if (!(GetEntityFlags(victim) & FL_DUCKING) && (chance >= 100.0 || GetRandomFloat(0.0, 100.0) < chance))
		{
			// TF2 applies the native 3x critical multiplier, then the victim's defenses.
			damage = LR_SNIPER_HEADSHOT_BASE_DAMAGE;
		}
		AJB_LR_SniperShoot(victim, damage, true);
	}

	// A lethal shot can end the round and clean up the wish synchronously.
	if (g_bSniper && AJB_LR_CanRun())
	{
		AJB_LR_ScheduleSniperShot();
	}
	return Plugin_Stop;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (!g_bSniper)
	{
		return;
	}
	if (!AJB_LR_CanRun() || !IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client))
	{
		g_fSniperDuckStart[client] = -1.0;
		return;
	}

	float now = GetGameTime();
	// Use physical crouch state: releasing duck under a low ceiling is not standing up.
	if (GetEntityFlags(client) & FL_DUCKING)
	{
		if (g_fSniperDuckStart[client] < 0.0)
		{
			g_fSniperDuckStart[client] = now;
		}
		return;
	}

	float started = g_fSniperDuckStart[client];
	g_fSniperDuckStart[client] = -1.0;
	if (started >= 0.0 && now - started >= g_cvSniperDuckTime.FloatValue)
	{
		AJB_LR_SniperShoot(client, g_cvSniperBodyDamage.FloatValue);
	}
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
	for (int i = 1; i <= MaxClients; i++)
	{
		g_fSniperDuckStart[i] = -1.0;
	}
}

