// =========================================================================================================
// Another Jailbreak — Public API for modules (natives + forwards)
// =========================================================================================================
//
// Soft API freeze (Phase 2): prefer additive changes. Do not rename/remove natives or change
// forward signatures without a version bump and module changelog.
//
// Modules should:
//   #include <ajb/ajb>
//   #undef REQUIRE_PLUGIN before include if optional; check LibraryExists("ajb")
//   Deploy as plugins/ajb_*.smx (flat under plugins/)
//   Expose sm_ajb_<module>_version (SourceMod convention)
//

#if defined _ajb_included
 #endinput
#endif
#define _ajb_included

#include <ajb/enums>
#include <ajb/constants>

// =========================================================================================================
// Forwards (implemented by core, consumed by modules)
// =========================================================================================================

/**
 * Round state changed. Fired after internal state is updated.
 */
forward void AJB_OnRoundStateChange(AJBRoundState oldState, AJBRoundState newState);

/**
 * Warden slot changed. client index or 0 if cleared.
 */
forward void AJB_OnWardenChanged(int oldWarden, int newWarden);

/**
 * Prisoner rebel flag toggled.
 */
forward void AJB_OnRebel(int client, bool isRebel);

/**
 * Cells were opened (manual, auto-timer, or native).
 */
forward void AJB_OnCellsOpened();

/**
 * Cells were closed.
 */
forward void AJB_OnCellsClosed();

/**
 * Exactly one living prisoner remains (LR hook point).
 */
forward void AJB_OnLastPrisoner(int client);

// =========================================================================================================
// Natives
// =========================================================================================================

/**
 * Whether AJB mode is active on this map / session.
 */
native bool AJB_IsEnabled();

/**
 * Current round state machine value.
 */
native AJBRoundState AJB_GetRoundState();

/**
 * Current warden client index, or 0.
 */
native int AJB_GetWarden();

/**
 * Clear the warden slot (admin / modules).
 */
native void AJB_ClearWarden();

native bool AJB_IsPrisoner(int client);
native bool AJB_IsGuard(int client);
native bool AJB_IsRebel(int client);
native bool AJB_IsFreeday(int client);

/**
 * True if the client has an individual freeday wish queued for the next round.
 */
native bool AJB_IsFreedayPending(int client);

native void AJB_SetRebel(int client, bool rebel);

/**
 * Queue (or cancel) an individual freeday wish for the NEXT round.
 * Does not clear rebel or change the current round.
 */
native void AJB_SetPlayerFreeday(int client, bool freeday);

/**
 * Apply / clear freeday on the CURRENT round only (server-wide Freeday day).
 * Does not clear rebel. Not for individual end-of-round wishes.
 */
native void AJB_GiveFreedayNow(int client, bool freeday);

native bool AJB_OpenCells();
native bool AJB_CloseCells();

/**
 * Drive phase countdown through team_round_timer when possible.
 * Pass 0.0 to clear/disable the AJB-managed countdown.
 */
native void AJB_SetPhaseTimer(float seconds);

/**
 * Request a round-state transition (modules: Last Request, Special Day).
 * Core may reject illegal transitions later; currently applies directly when mode is active.
 *
 * @return  true if state was applied (or already equal).
 */
native bool AJB_SetRoundState(AJBRoundState state);

/**
 * End the TF2 round for a team (2 = RED, 3 = BLU by default).
 */
native void AJB_ForceTeamWin(int team);

// =========================================================================================================
// Optional shared plugin marker
// =========================================================================================================

public SharedPlugin __pl_ajb =
{
	name = AJB_LIBRARY,
	file = "ajb.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_ajb_SetNTVOptional()
{
	MarkNativeAsOptional("AJB_IsEnabled");
	MarkNativeAsOptional("AJB_GetRoundState");
	MarkNativeAsOptional("AJB_GetWarden");
	MarkNativeAsOptional("AJB_ClearWarden");
	MarkNativeAsOptional("AJB_IsPrisoner");
	MarkNativeAsOptional("AJB_IsGuard");
	MarkNativeAsOptional("AJB_IsRebel");
	MarkNativeAsOptional("AJB_IsFreeday");
	MarkNativeAsOptional("AJB_IsFreedayPending");
	MarkNativeAsOptional("AJB_SetRebel");
	MarkNativeAsOptional("AJB_SetPlayerFreeday");
	MarkNativeAsOptional("AJB_GiveFreedayNow");
	MarkNativeAsOptional("AJB_OpenCells");
	MarkNativeAsOptional("AJB_CloseCells");
	MarkNativeAsOptional("AJB_SetPhaseTimer");
	MarkNativeAsOptional("AJB_SetRoundState");
	MarkNativeAsOptional("AJB_ForceTeamWin");
}
#endif
