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

bool g_bFriendlyFire;          // current runtime state (false = FF disabled)

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

	g_cvEngineSvTags = FindConVar("sv_tags");
}

// Friendly fire is off by default at the start of every round.
void AJB_FF_ResetForRound()
{
	g_bFriendlyFire = false;
	AJB_FF_Apply();
}

// Push the runtime state onto the engine cvar.
// mp_friendlyfire is FCVAR_NOTIFY: changing it spams "server cvar changed" to every
// client and re-tags sv_tags. Strip NOTIFY from both around the write, then restore.
void AJB_FF_Apply()
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

	g_cvEngineFriendlyFire.SetInt(g_bFriendlyFire ? 1 : 0);

	g_cvEngineFriendlyFire.Flags = ffFlags;
	if (g_cvEngineSvTags != null)
	{
		g_cvEngineSvTags.Flags = tagFlags;
	}
}

// Warden toggle from the menu: flip, apply, announce to everyone.
void AJB_FF_Toggle()
{
	if (g_cvFFControl == null || !g_cvFFControl.BoolValue)
	{
		return;
	}

	g_bFriendlyFire = !g_bFriendlyFire;
	AJB_FF_Apply();

	AJB_ChatAll(g_bFriendlyFire ? "FriendlyFire Enabled" : "FriendlyFire Disabled");
}

// Restore stock friendly fire on unload so we don't leave the global cvar forced.
void AJB_FF_OnPluginEnd()
{
	if (g_cvEngineFriendlyFire != null)
	{
		g_cvEngineFriendlyFire.SetInt(0);
	}
}
