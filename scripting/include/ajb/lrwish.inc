// =========================================================================================================
// Another Jailbreak - Shared Last Request wish API and menu hooks
// Built-in wish state and extension points for standalone plugins that want to add their own wishes
// (e.g. ajb_ff2). The menu itself lives inside ajb_lastrequest; these forwards let external plugins
// append items (AJB_OnLRWishMenu) and claim them when picked (AJB_OnLRWishSelect).
// =========================================================================================================

#if defined _ajb_lrwish_included
	#endinput
#endif
#define _ajb_lrwish_included

#define AJB_LASTREQUEST_LIBRARY "ajb_lastrequest"

enum AJB_LRWish
{
	LRWish_None = 0,
	LRWish_FreedayMe,
	LRWish_FreedayOthers,
	LRWish_FreedayAll,
	LRWish_WarDay,
	LRWish_ClassWarfare,
	LRWish_Custom,
	LRWish_HotReds,
	LRWish_Suicide,
	LRWish_LowGravity,
	LRWish_HideSeek,
	LRWish_HungerGames,
	LRWish_Sniper,
	LRWish_SetAllClass,
	LRWish_GuardMelee,
	LRWish_ZombieMode,
	LRWish_CellWars,
	LRWish_Dodgeball
};

stock bool AJB_LR_UsesEqualTeams(AJB_LRWish wish)
{
	return wish == LRWish_WarDay || wish == LRWish_ClassWarfare || wish == LRWish_Dodgeball;
}

// Applied built-in round wish, not a pending or instant wish; None if absent or disabled.
native AJB_LRWish AJB_LR_GetActiveWish();

/**
 * Called when the Last Request wish menu is built, after all built-in wishes.
 *
 * Add your own items here with a unique token:
 *     menu.AddItem("ff2boss", label);
 * Use ITEMDRAW_DISABLED to show the wish but keep it unselectable.
 *
 * @param client	Prisoner the menu is being built for
 * @param menu		Menu handle (do not delete, do not display)
 *
 * @noreturn
 */
forward void AJB_OnLRWishMenu(int client, Menu menu);

/**
 * Called when the prisoner picks an item that no built-in wish claimed.
 *
 * @param client	Prisoner that picked the item
 * @param token		Item token that was passed to menu.AddItem
 *
 * @return		Plugin_Handled if this plugin consumed the pick (the Last Request
 *			module then closes its menu state and marks the wish as chosen),
 *			Plugin_Continue to ignore it
 */
forward Action AJB_OnLRWishSelect(int client, const char[] token);

// Menu-hook consumers may run without the Last Request module.
public SharedPlugin __pl_ajb_lastrequest =
{
	name = AJB_LASTREQUEST_LIBRARY,
	file = "ajb_lastrequest.smx",
	required = 0,
};

public void __pl_ajb_lastrequest_SetNTVOptional()
{
	MarkNativeAsOptional("AJB_LR_GetActiveWish");
}
