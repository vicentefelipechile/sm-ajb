// =========================================================================================================
// Another Jailbreak — Stock weapon creation without TF2Items
// =========================================================================================================

#if defined _ajb_weapons_included
 #endinput
#endif
#define _ajb_weapons_included

#include <sdktools>
#include <tf2_stocks>

// Event loadouts must not inherit the normal prisoner's configurable weapon allowlist.
stock void AJB_StripEventWeapons(int client, bool keepMelee, bool keepJars = false)
{
	for (int slot = 0; slot <= 7; slot++)
	{
		if (keepMelee && slot == TFWeaponSlot_Melee) continue;
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (weapon <= MaxClients) continue;
		char classname[64];
		GetEntityClassname(weapon, classname, sizeof(classname));
		if (keepJars && (StrEqual(classname, "tf_weapon_jar") || StrEqual(classname, "tf_weapon_jar_milk"))) continue;
		TF2_RemoveWeaponSlot(client, slot);
	}

	static const char wearables[][] = {"tf_wearable_demoshield", "tf_wearable_razorback"};
	for (int i = 0; i < sizeof(wearables); i++)
	{
		int entity = -1;
		while ((entity = FindEntityByClassname(entity, wearables[i])) != -1)
		{
			if (GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
			{
				TF2_RemoveWearable(client, entity);
			}
		}
	}
}

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

// Advance the native meter more slowly without changing weapon attributes or its HUD scale.
stock void AJB_ScaleEffectBarRecharge(int weapon, float elapsed, float multiplier)
{
	if (elapsed <= 0.0 || multiplier <= 0.0) return;
	float deadline = GetEntPropFloat(weapon, Prop_Send, "m_flEffectBarRegenTime");
	if (deadline > GetGameTime())
	{
		SetEntPropFloat(weapon, Prop_Send, "m_flEffectBarRegenTime", deadline + elapsed * (1.0 - 1.0 / multiplier));
	}
}
