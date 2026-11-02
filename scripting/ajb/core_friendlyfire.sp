// =========================================================================================================
// Friendly fire
// - The warden can toggle mp_friendlyfire live from the first page of the warden menu.
// - Default OFF every new round (AJB_FF_ResetForRound from Event_RoundStart).
// - A separate cvar keeps guards from killing each other even while friendly fire is on;
//   that protection is enforced in AJB_OnTakeDamage (core_rules.sp).
// =========================================================================================================

ConVar g_cvFFControl;          // gate: warden may toggle friendly fire from the menu
ConVar g_cvFFProtectGuards;    // 1 = guards cannot damage each other even with FF on
ConVar g_cvEngineFriendlyFire; // mp_friendlyfire
ConVar g_cvEngineSvTags;       // sv_tags (re-tagged as a side effect of mp_friendlyfire)

bool g_bFFPolicyActive;
int g_iSavedFriendlyFire;

void AJB_FF_OnPluginStart()
{
	g_cvFFControl = CreateConVar(
		"sm_ajb_warden_friendlyfire",
		"1",
		"1 = warden can toggle friendly fire from the warden menu.",
		_, true, 0.0, true, 1.0);

	g_cvFFProtectGuards = CreateConVar(
		"sm_ajb_ff_protect_guards",
		"1",
		"1 = guards cannot damage each other even while friendly fire is enabled.",
		_, true, 0.0, true, 1.0);

	g_cvEngineFriendlyFire = FindConVar("mp_friendlyfire");
	if (g_cvEngineFriendlyFire == null)
	{
		LogError("[AJB] mp_friendlyfire not found — friendly fire control disabled.");
	}
	else
	{
		g_cvEngineFriendlyFire.AddChangeHook(AJB_FF_OnChanged);
	}

	g_cvEngineSvTags = FindConVar("sv_tags");
}

void AJB_FF_ApplyPolicy()
{
	if (g_cvEngineFriendlyFire == null || g_bFFPolicyActive == g_bModeActive)
	{
		return;
	}

	g_bFFPolicyActive = g_bModeActive;
	if (g_bModeActive)
	{
		g_iSavedFriendlyFire = g_cvEngineFriendlyFire.IntValue;
		AJB_FF_ResetForRound();
	}
	else
	{
		AJB_FF_Set(g_iSavedFriendlyFire);
	}
}

void AJB_FF_ResetForRound()
{
	if (g_bFFPolicyActive)
	{
		AJB_FF_Set(0);
	}
}

// Suppress the engine's cvar/tag announcements; AJB supplies its own translated toggle message.
void AJB_FF_Set(int value)
{
	if (g_cvEngineFriendlyFire == null)
	{
		return;
	}

	int ffFlags = g_cvEngineFriendlyFire.Flags;
	g_cvEngineFriendlyFire.Flags = ffFlags & ~FCVAR_NOTIFY;

	int tagFlags = 0;
	if (g_cvEngineSvTags != null)
	{
		tagFlags = g_cvEngineSvTags.Flags;
		g_cvEngineSvTags.Flags = tagFlags & ~FCVAR_NOTIFY;
	}

	g_cvEngineFriendlyFire.SetInt(value);

	g_cvEngineFriendlyFire.Flags = ffFlags;
	if (g_cvEngineSvTags != null)
	{
		g_cvEngineSvTags.Flags = tagFlags;
	}
}

void AJB_FF_OnChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_bModeActive || (StringToInt(oldValue) != 0) == convar.BoolValue)
	{
		return;
	}

	AJB_FireFriendlyFireChanged(convar.BoolValue);
	AJB_WardenMenu_Refresh();
}

void AJB_FF_Toggle()
{
	if (!g_bFFPolicyActive || g_cvFFControl == null || !g_cvFFControl.BoolValue)
	{
		return;
	}

	AJB_FF_Set(g_cvEngineFriendlyFire.BoolValue ? 0 : 1);
	AJB_ChatAll(g_cvEngineFriendlyFire.BoolValue ? "FriendlyFire Enabled" : "FriendlyFire Disabled");
}
