// =========================================================================================================
// Teammate push / collisions
// - "El empuje entre compañeros" = TF2's teammate avoidance push (tf_avoidteammates_pushaway).
//   Teammates are never solid to each other; the engine just nudges overlapping teammates apart.
// - Default OFF every new round (AJB_Collisions_ResetForRound from Event_RoundStart).
// - The warden can toggle it live from the first page of the warden menu.
// =========================================================================================================

ConVar g_cvCollisionsControl;      // gate: warden may toggle push from the menu
ConVar g_cvEngineAvoidPushaway;    // tf_avoidteammates_pushaway (replicated → clients follow)

bool g_bTeamPush;                  // current runtime state (false = push disabled)

void AJB_Collisions_OnPluginStart()
{
	g_cvCollisionsControl = CreateConVar(
		"sm_ajb_warden_collisions",
		"1",
		"1 = warden can toggle teammate push (collisions) from the warden menu.",
		_, true, 0.0, true, 1.0);

	g_cvEngineAvoidPushaway = FindConVar("tf_avoidteammates_pushaway");
	if (g_cvEngineAvoidPushaway == null)
	{
		LogError("[AJB] tf_avoidteammates_pushaway not found — teammate push control disabled.");
	}
}

// Restore TF2's stock teammate push on unload so we don't leave a global cvar forced.
void AJB_Collisions_OnPluginEnd()
{
	if (g_cvEngineAvoidPushaway != null)
	{
		g_cvEngineAvoidPushaway.SetInt(1);
	}
}

// Push is off by default at the start of every round.
void AJB_Collisions_ResetForRound()
{
	g_bTeamPush = false;
	AJB_Collisions_Apply();
}

// Push the runtime state onto the engine cvar (replicated to clients).
void AJB_Collisions_Apply()
{
	if (g_cvEngineAvoidPushaway == null)
	{
		return;
	}

	g_cvEngineAvoidPushaway.SetInt(g_bTeamPush ? 1 : 0);
}

// Warden toggle from the menu: flip, apply, announce to everyone.
void AJB_Collisions_Toggle()
{
	if (g_cvCollisionsControl == null || !g_cvCollisionsControl.BoolValue)
	{
		return;
	}

	g_bTeamPush = !g_bTeamPush;
	AJB_Collisions_Apply();

	AJB_ChatAll(g_bTeamPush ? "Collisions Enabled" : "Collisions Disabled");
}
