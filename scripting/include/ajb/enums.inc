// =========================================================================================================
// Another Jailbreak — Shared enums (core + modules)
// =========================================================================================================

#if defined _ajb_enums_included
 #endinput
#endif
#define _ajb_enums_included

// =========================================================================================================
// Round state machine
// =========================================================================================================

enum AJBRoundState
{
	AJBState_Disabled = 0,
	AJBState_Waiting,
	AJBState_CellsLocked,
	AJBState_CellsOpen,
	// Last Request phases (both count as "LR phase" for rules/weapons/mutes).
	AJBState_LRChoosing, // prisoner has the wish menu / typing custom
	AJBState_LRChosen,   // wish locked in (queued for next live round, or suicide)
	AJBState_SpecialDay,
	AJBState_RoundEnd
};

// True while a Last Request is open or already locked this round.
stock bool AJB_IsLRPhase(AJBRoundState state)
{
	return state == AJBState_LRChoosing || state == AJBState_LRChosen;
}
