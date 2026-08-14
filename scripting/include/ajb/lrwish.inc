// =========================================================================================================
// Another Jailbreak - Last Request wish menu hooks
// Public extension points of ajb_lastrequest for standalone plugins that want to add their own wishes
// (e.g. ajb_ff2). The menu itself lives inside ajb_lastrequest; these forwards let external plugins
// append items (AJB_OnLRWishMenu) and claim them when picked (AJB_OnLRWishSelect).
// =========================================================================================================

#if defined _ajb_lrwish_included
	#endinput
#endif
#define _ajb_lrwish_included

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
