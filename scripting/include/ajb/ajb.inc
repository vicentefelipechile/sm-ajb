// =========================================================================================================
// Another Jailbreak — Public API for modules
// =========================================================================================================
// Freeday:
//   AJB_SetPlayerFreeday → next round only (does not clear rebel)
//   AJB_GiveFreedayNow   → current round (server-wide Freeday day)
// =========================================================================================================

#if defined _ajb_included
 #endinput
#endif
#define _ajb_included

#include <ajb/enums>
#include <ajb/constants>

// =========================================================================================================
// Round / lifecycle
// =========================================================================================================

forward void AJB_OnRoundStateChange(AJBRoundState oldState, AJBRoundState newState);
// Live round begins: after prep ends, or right after round start if prep time is 0.
// LR wishes and similar must apply here — never during preround/prep.
forward void AJB_OnLiveRoundBegin();
// Engine round win (teamplay_round_win). team is TF2 team index (2=RED, 3=BLU).
forward void AJB_OnRoundWin(int team);
// Main jail clock hit zero (guards win path). Fires before AJB_ForceTeamWin.
forward void AJB_OnPhaseTimerExpired();
// Mode enable flipped (map prefix / sm_ajb_enabled / sm_ajb_force / unload).
forward void AJB_OnModeChanged(bool enabled);

// =========================================================================================================
// Prep window
// =========================================================================================================

forward void AJB_OnPrepStart(float duration);
// Fires whenever an active prep window is torn down (natural end, combat day, cleanup).
forward void AJB_OnPrepEnd();

// =========================================================================================================
// Warden / cells / last prisoner
// =========================================================================================================

forward void AJB_OnWardenChanged(int oldWarden, int newWarden);
// Warden picked "Give Last Request" in their menu — modules handle the picker/offer.
forward void AJB_OnWardenGiveLR(int warden);
forward void AJB_OnCellsOpened();
forward void AJB_OnCellsClosed();
forward void AJB_OnLastPrisoner(int client);
// Warden placed a "Come here!" ground marker.
forward void AJB_OnWardenMarkerPlaced(int warden);

// =========================================================================================================
// Player state
// =========================================================================================================

forward void AJB_OnRebel(int client, bool isRebel);
// freeday = new value. isPending = next-round queue (AJB_SetPlayerFreeday) vs current round.
forward void AJB_OnFreedayChanged(int client, bool freeday, bool isPending);
// Guard bounced to prisoners by the live-round ratio cap.
forward void AJB_OnGuardBounced(int client);

// =========================================================================================================
// Special days / warden tools
// =========================================================================================================

forward void AJB_OnCombatDayStart();
// Server-wide cosmetic freeday-all (cells open, no warden claim).
forward void AJB_OnFreedayAllStart();
forward void AJB_OnFriendlyFireChanged(bool enabled);
// Teammate push (tf_avoidteammates_pushaway) toggled by warden.
forward void AJB_OnTeamPushChanged(bool enabled);
// Crit splash freekill blocked; judges get the decision menu after this.
forward void AJB_OnFreekillDetected(int attacker, int victimCount);

native bool AJB_IsEnabled();
native AJBRoundState AJB_GetRoundState();
native int AJB_GetWarden();
native void AJB_ClearWarden();
native bool AJB_IsPrisoner(int client);
native bool AJB_IsGuard(int client);
native bool AJB_IsRebel(int client);
native bool AJB_IsFreeday(int client);
native bool AJB_IsFreedayPending(int client);
native void AJB_SetRebel(int client, bool rebel);
native void AJB_SetPlayerFreeday(int client, bool freeday);
native void AJB_GiveFreedayNow(int client, bool freeday);
native bool AJB_OpenCells();
native bool AJB_CloseCells();
native void AJB_SetPhaseTimer(float seconds);
// Stop the HUD clock apply + the core guards-win expire timer (special days that own their own end).
native void AJB_ClearPhaseTimer();
native bool AJB_SetRoundState(AJBRoundState state);
native void AJB_ForceTeamWin(int team);
// Reopen the stock warden menu (for submenu "Back" / post-action return).
native void AJB_ShowWardenMenu(int client);
// When false, damaging a guard never auto-marks rebel (LR Hot Reds, etc.).
native void AJB_SetRebelOnHit(bool enabled);
native bool AJB_GetRebelOnHit();

// Round modes (War Day / Class Warfare / Freeday-all cosmetic).
native void AJB_BeginCombatDay();
native void AJB_BeginFreedayAllCosmetic();
native bool AJB_IsCombatDay();
native bool AJB_IsFreedayAllCosmetic();
native int AJB_GetGuardsTeam();
native int AJB_GetPrisonersTeam();
native void AJB_StripToMelee(int client);

stock void AJB_ChangeTeamSafe(int client, int team)
{
	ChangeClientTeam(client, 1);
	ChangeClientTeam(client, team);
}

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
	MarkNativeAsOptional("AJB_ClearPhaseTimer");
	MarkNativeAsOptional("AJB_SetRoundState");
	MarkNativeAsOptional("AJB_ForceTeamWin");
	MarkNativeAsOptional("AJB_ShowWardenMenu");
	MarkNativeAsOptional("AJB_SetRebelOnHit");
	MarkNativeAsOptional("AJB_GetRebelOnHit");
	MarkNativeAsOptional("AJB_BeginCombatDay");
	MarkNativeAsOptional("AJB_BeginFreedayAllCosmetic");
	MarkNativeAsOptional("AJB_IsCombatDay");
	MarkNativeAsOptional("AJB_IsFreedayAllCosmetic");
	MarkNativeAsOptional("AJB_GetGuardsTeam");
	MarkNativeAsOptional("AJB_GetPrisonersTeam");
	MarkNativeAsOptional("AJB_StripToMelee");
}
#endif
