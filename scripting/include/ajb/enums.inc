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
	AJBState_LastRequest,
	AJBState_SpecialDay,
	AJBState_RoundEnd
};
