// =========================================================================================================
// Another Jailbreak — Boosts public API (optional module)
// =========================================================================================================

#if defined _ajb_boosts_included
 #endinput
#endif
#define _ajb_boosts_included

#define AJB_BOOSTS_LIBRARY "ajb_boosts"

// Current boost points for a player (0 if invalid / module missing).
native int AJB_Boosts_GetPoints(int client);

// Add (positive) or remove (negative) points. Clamped by max/min. Returns new total.
native int AJB_Boosts_AddPointsEx(int client, int amount);

public SharedPlugin __pl_ajb_boosts =
{
	name = AJB_BOOSTS_LIBRARY,
	file = "ajb_boosts.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_ajb_boosts_SetNTVOptional()
{
	MarkNativeAsOptional("AJB_Boosts_GetPoints");
	MarkNativeAsOptional("AJB_Boosts_AddPointsEx");
}
#endif
