// =========================================================================================================
// Team balance — cap the guard team to sm_ajb_guard_ratio prisoners per guard
// =========================================================================================================
//
// TF2's stock auto-assign pushes fresh joiners onto whichever team is smaller. On a jailbreak map
// that is almost always the guards (BLU), producing the unnatural ~1:1 split. core_mode already sets
// mp_teams_unbalance_limit 0 so the engine never force-swaps players mid-round.
//
// The JB ratio is only enforced while the round is LIVE. During the pre-round (waiting + prep) players
// may freely pick either team; the balance is applied when prep ends (AJB_Balance_OnLiveRoundBegin),
// which bounces any excess guards down to the prisoners. Joins during the live round are capped too.

static ConVar g_cvBalanceEnforce;

void AJB_Balance_OnPluginStart()
{
	g_cvBalanceEnforce = CreateConVar("sm_ajb_balance_enforce", "1",
		"1 = cap guards to ~1 per sm_ajb_guard_ratio prisoners once the round is live (extra guards move to prisoners).",
		_, true, 0.0, true, 1.0);
}

// The ratio is only enforced once the round is live. Pre-round (waiting) and the prep window are a
// free-for-all so players can sort out their own teams before it locks in.
bool AJB_Balance_RoundLive()
{
	if (AJB_IsPrepActive())
	{
		return false;
	}

	switch (g_RoundState)
	{
		case AJBState_CellsLocked, AJBState_CellsOpen, AJBState_LRChoosing, AJBState_LRChosen, AJBState_SpecialDay:
		{
			return true;
		}
	}
	return false;
}

bool AJB_Balance_Active()
{
	if (!g_bModeActive || !g_cvBalanceEnforce.BoolValue || g_cvGuardRatio.IntValue <= 0)
	{
		return false;
	}

	return AJB_Balance_RoundLive();
}

void AJB_Balance_Notify(int client, int maxGuards)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
	{
		return;
	}

	char prefix[64];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	CPrintToChat(client, "%T", "Balance Guards Full", client, prefix, maxGuards);
}

// Move a bounced guard down to the prisoners. ChangeClientTeam kills a live player, and prisoners get
// no respawn wave mid-round — so without a forced respawn the moved player would sit dead (watching a
// corpse) until the round ends. Respawn them so they actually get to play the round as a reo.
void AJB_Balance_MoveToPrisoners(int client, int maxGuards)
{
	if (!IsClientInGame(client))
	{
		return;
	}

	ChangeClientTeam(client, AJB_GetPrisonersTeam());
	TF2_RespawnPlayer(client);
	AJB_Balance_Notify(client, maxGuards);
}

// Called from Event_PlayerTeam (post) once a client has landed on a team.
void AJB_Balance_OnPlayerTeam(int client, int team)
{
	if (!AJB_Balance_Active())
	{
		return;
	}

	if (team != AJB_GetGuardsTeam())
	{
		return;
	}

	if (AJB_CountOnTeam(AJB_GetGuardsTeam()) <= AJB_MaxGuards())
	{
		return;
	}

	// This joiner pushed guards over the cap. Bounce next frame — switching teams inside the
	// team-change event itself is unsafe and would re-enter this handler.
	RequestFrame(AJB_Balance_BounceFrame, GetClientUserId(client));
}

void AJB_Balance_BounceFrame(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client <= 0 || !IsClientInGame(client))
	{
		return;
	}

	if (!AJB_Balance_Active())
	{
		return;
	}

	// Re-check: a guard may have left in the interim, opening a legitimate slot.
	if (GetClientTeam(client) != AJB_GetGuardsTeam())
	{
		return;
	}

	if (AJB_CountOnTeam(AJB_GetGuardsTeam()) <= AJB_MaxGuards())
	{
		return;
	}

	AJB_Balance_MoveToPrisoners(client, AJB_MaxGuards());
}

// Prep just ended and the round is going live: enforce the ratio now that the pre-round free-for-all
// is over.
void AJB_Balance_OnLiveRoundBegin()
{
	if (!AJB_Balance_Active())
	{
		return;
	}

	AJB_Balance_ReconcileGuards();
}

// Move the excess guards down to the prisoners so the guard team fits the ratio. The warden is never
// bounced; the remaining excess is picked at random for fairness. Returns how many were moved. This
// does not gate on the round being live — callers own that (OnLiveRoundBegin / the admin command).
int AJB_Balance_ReconcileGuards()
{
	if (!g_bModeActive || !g_cvBalanceEnforce.BoolValue || g_cvGuardRatio.IntValue <= 0)
	{
		return 0;
	}

	int guardsTeam = AJB_GetGuardsTeam();
	int maxGuards = AJB_MaxGuards();

	int excess = AJB_CountOnTeam(guardsTeam) - maxGuards;
	if (excess <= 0)
	{
		return 0;
	}

	// Collect the non-warden guards as bounce candidates.
	int candidates[MAXPLAYERS];
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == guardsTeam && i != g_iWarden)
		{
			candidates[count++] = i;
		}
	}

	int moved = 0;
	while (excess > 0 && count > 0)
	{
		int idx = GetRandomInt(0, count - 1);
		int client = candidates[idx];
		candidates[idx] = candidates[--count];

		AJB_Balance_MoveToPrisoners(client, maxGuards);

		moved++;
		excess--;
	}

	return moved;
}

// Admin: force the JB balance right now (handy while testing, or to fix a lopsided live round).
Action Command_AjbBalance(int client, int args)
{
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}

	int moved = AJB_Balance_ReconcileGuards();

	char prefix[64];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	ReplyToCommand(client, "%T", "Balance Forced", AJB_TransTarget(client), prefix, moved, AJB_MaxGuards());
	return Plugin_Handled;
}
