// =========================================================================================================
// Last Request - War Day
// =========================================================================================================

void AJB_LR_DoWarDay(int prisoner)
{
	// NEXT round: full combat day (makes sense with full teams).
	AJB_LR_QueueWish(prisoner, LRWish_WarDay, "LR Chose WarDay");
}

