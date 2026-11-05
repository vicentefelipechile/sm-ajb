// =========================================================================================================
// Another Jailbreak — Last Request public API (optional module)
// =========================================================================================================

#if defined _ajb_lastrequest_included
 #endinput
#endif
#define _ajb_lastrequest_included

#define AJB_LASTREQUEST_LIBRARY "ajb_lastrequest"

// BLU represents zombies, not guards, for the duration of this wish.
native bool AJB_LR_IsZombieMode();

public SharedPlugin __pl_ajb_lastrequest =
{
	name = AJB_LASTREQUEST_LIBRARY,
	file = "ajb_lastrequest.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_ajb_lastrequest_SetNTVOptional()
{
	MarkNativeAsOptional("AJB_LR_IsZombieMode");
}
#endif
