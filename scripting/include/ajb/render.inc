// =========================================================================================================
// Another Jailbreak - reversible player, weapon and wearable tint
// =========================================================================================================

#if defined _ajb_render_included
	#endinput
#endif
#define _ajb_render_included

#include <sdktools>

#define AJB_RENDER_FIELDS 6

stock void AJB_TintEntity(int entity, int red, int green, int blue, ArrayList saved)
{
	int state[AJB_RENDER_FIELDS];
	state[0] = EntIndexToEntRef(entity);
	state[1] = view_as<int>(GetEntityRenderMode(entity));
	GetEntityRenderColor(entity, state[2], state[3], state[4], state[5]);
	saved.PushArray(state);
	SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
	SetEntityRenderColor(entity, red, green, blue, state[5]);
}

stock ArrayList AJB_TintPlayer(int client, int red, int green, int blue)
{
	ArrayList saved = new ArrayList(AJB_RENDER_FIELDS);
	AJB_TintEntity(client, red, green, blue, saved);
	for (int slot = 0; slot <= 7; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (weapon > MaxClients) AJB_TintEntity(weapon, red, green, blue, saved);
	}
	static const char wearables[][] = {"tf_wearable", "tf_wearable_demoshield", "tf_wearable_razorback", "tf_powerup_bottle"};
	for (int i = 0; i < sizeof(wearables); i++)
	{
		int entity = -1;
		while ((entity = FindEntityByClassname(entity, wearables[i])) != -1)
		{
			if (GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
			{
				AJB_TintEntity(entity, red, green, blue, saved);
			}
		}
	}
	return saved;
}

stock void AJB_RestoreTint(ArrayList &saved)
{
	if (saved == null) return;
	int state[AJB_RENDER_FIELDS];
	for (int i = 0; i < saved.Length; i++)
	{
		saved.GetArray(i, state, sizeof(state));
		int entity = EntRefToEntIndex(state[0]);
		if (entity == INVALID_ENT_REFERENCE) continue;
		SetEntityRenderMode(entity, view_as<RenderMode>(state[1]));
		SetEntityRenderColor(entity, state[2], state[3], state[4], state[5]);
	}
	delete saved;
}
