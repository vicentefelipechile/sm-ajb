// =========================================================================================================
// Another Jailbreak — Stock weapon creation without TF2Items
// =========================================================================================================

#if defined _ajb_weapons_included
 #endinput
#endif
#define _ajb_weapons_included

#include <sdktools>

stock int AJB_GiveStockWeapon(int client, const char[] classname, int defIndex)
{
	int weapon = CreateEntityByName(classname);
	if (weapon == -1)
	{
		LogError("[AJB] Failed to create %s for client %d.", classname, client);
		return -1;
	}

	SetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex", defIndex);
	SetEntProp(weapon, Prop_Send, "m_iEntityLevel", 1);
	SetEntProp(weapon, Prop_Send, "m_iEntityQuality", 0);
	SetEntProp(weapon, Prop_Send, "m_bInitialized", 1);
	SetEntProp(weapon, Prop_Send, "m_bValidatedAttachedEntity", 1);
	if (!DispatchSpawn(weapon))
	{
		LogError("[AJB] Failed to spawn %s for client %d.", classname, client);
		RemoveEntity(weapon);
		return -1;
	}

	EquipPlayerWeapon(client, weapon);
	return weapon;
}
