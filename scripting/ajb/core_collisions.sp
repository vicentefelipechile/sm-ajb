// =========================================================================================================
// Teammate push / collisions
// AJB keeps teammates non-solid and lets the warden toggle their avoidance push independently of damage.
// =========================================================================================================

ConVar g_cvCollisionsControl;      // gate: warden may toggle push from the menu
ConVar g_cvEngineAvoidPushaway;
ConVar g_cvEngineAvoidTeammates;
bool g_bCollisionsPolicyActive;
int g_iSavedAvoidPushaway;
int g_iSavedAvoidTeammates;

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
	else
	{
		g_cvEngineAvoidPushaway.AddChangeHook(AJB_Collisions_OnPushChanged);
	}

	g_cvEngineAvoidTeammates = FindConVar("tf_avoidteammates");
	if (g_cvEngineAvoidTeammates == null)
	{
		LogError("[AJB] tf_avoidteammates not found — teammate push control disabled.");
	}
	else
	{
		g_cvEngineAvoidTeammates.AddChangeHook(AJB_Collisions_OnAvoidChanged);
	}
}

void AJB_Collisions_ApplyPolicy()
{
	if (g_cvEngineAvoidPushaway == null || g_cvEngineAvoidTeammates == null
		|| g_bCollisionsPolicyActive == g_bModeActive)
	{
		return;
	}

	g_bCollisionsPolicyActive = g_bModeActive;
	if (g_bModeActive)
	{
		g_iSavedAvoidPushaway = g_cvEngineAvoidPushaway.IntValue;
		g_iSavedAvoidTeammates = g_cvEngineAvoidTeammates.IntValue;
		AJB_Collisions_ResetForRound();
	}
	else
	{
		g_cvEngineAvoidPushaway.SetInt(g_iSavedAvoidPushaway);
		g_cvEngineAvoidTeammates.SetInt(g_iSavedAvoidTeammates);
	}
}

void AJB_Collisions_ResetForRound()
{
	if (!g_bCollisionsPolicyActive)
	{
		return;
	}

	g_cvEngineAvoidTeammates.SetInt(1);
	g_cvEngineAvoidPushaway.SetInt(0);
}

void AJB_Collisions_OnAvoidChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	// Pushaway cannot control collisions if another config makes teammates solid.
	if (g_bModeActive && g_bCollisionsPolicyActive && !convar.BoolValue)
	{
		convar.SetInt(1);
	}
}

void AJB_Collisions_OnPushChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_bModeActive || (StringToInt(oldValue) != 0) == convar.BoolValue)
	{
		return;
	}

	AJB_FireTeamPushChanged(convar.BoolValue);
	AJB_WardenMenu_Refresh();
}

void AJB_Collisions_Toggle()
{
	if (!g_bCollisionsPolicyActive || g_cvCollisionsControl == null || !g_cvCollisionsControl.BoolValue)
	{
		return;
	}

	g_cvEngineAvoidPushaway.SetInt(g_cvEngineAvoidPushaway.BoolValue ? 0 : 1);
	AJB_ChatAll(g_cvEngineAvoidPushaway.BoolValue ? "Collisions Enabled" : "Collisions Disabled");
}
