// =========================================================================================================
// Another Jailbreak — Cell Wars teleport destinations
// =========================================================================================================

#if defined _ajb_cellwars_included
	#endinput
#endif
#define _ajb_cellwars_included

stock int AJB_CW_GetTeleportCells(const bool[] occupied, int cellCount, int currentCell, int[] destinations)
{
	int count = 0;
	for (int cell = 0; cell < cellCount; cell++)
	{
		if (occupied[cell] && cell != currentCell)
		{
			destinations[count++] = cell;
		}
	}
	return count;
}
