// =========================================================================================================
// Last Request - Low Gravity
// =========================================================================================================

void AJB_LR_DoLowGravity(int prisoner)
{
	// NEXT round low gravity.
	AJB_LR_QueueWish(prisoner, LRWish_LowGravity, "LR Chose LowGravity");
}

