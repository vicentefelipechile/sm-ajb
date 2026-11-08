// =========================================================================================================
// Another Jailbreak - temporary per-player fog, without replacing the map's master controller
// =========================================================================================================

#if defined _ajb_fog_included
	#endinput
#endif
#define _ajb_fog_included

#include <sdktools>

stock int AJB_CreateFog(const char[] name, const char[] color, float start, float end, float density)
{
	int fog = CreateEntityByName("env_fog_controller");
	if (fog == -1)
	{
		LogError("[AJB] Could not create fog controller %s.", name);
		return INVALID_ENT_REFERENCE;
	}
	DispatchKeyValue(fog, "targetname", name);
	DispatchKeyValue(fog, "spawnflags", "0");
	DispatchKeyValue(fog, "fogenable", "1");
	DispatchKeyValue(fog, "fogblend", "0");
	DispatchKeyValue(fog, "fogcolor", color);
	DispatchKeyValue(fog, "fogcolor2", color);
	DispatchKeyValueFloat(fog, "fogstart", start);
	DispatchKeyValueFloat(fog, "fogend", end);
	DispatchKeyValueFloat(fog, "fogmaxdensity", density);
	if (!DispatchSpawn(fog))
	{
		LogError("[AJB] Could not spawn fog controller %s.", name);
		RemoveEntity(fog);
		return INVALID_ENT_REFERENCE;
	}
	AcceptEntityInput(fog, "TurnOn");
	return EntIndexToEntRef(fog);
}

stock void AJB_ApplyClientFog(int client, int fogRef, bool &saved, int &oldRef)
{
	int fog = EntRefToEntIndex(fogRef);
	if (fog == INVALID_ENT_REFERENCE || !HasEntProp(client, Prop_Send, "m_PlayerFog.m_hCtrl")) return;
	if (!saved)
	{
		int old = GetEntPropEnt(client, Prop_Send, "m_PlayerFog.m_hCtrl");
		oldRef = old > MaxClients && old != fog ? EntIndexToEntRef(old) : INVALID_ENT_REFERENCE;
		saved = true;
	}
	SetEntPropEnt(client, Prop_Send, "m_PlayerFog.m_hCtrl", fog);
}

stock void AJB_RestoreClientFog(int client, int fogRef, bool &saved, int &oldRef)
{
	int fog = EntRefToEntIndex(fogRef);
	if (saved && IsClientInGame(client) && HasEntProp(client, Prop_Send, "m_PlayerFog.m_hCtrl")
		&& GetEntPropEnt(client, Prop_Send, "m_PlayerFog.m_hCtrl") == fog)
	{
		int old = EntRefToEntIndex(oldRef);
		SetEntPropEnt(client, Prop_Send, "m_PlayerFog.m_hCtrl", old > MaxClients ? old : -1);
	}
	saved = false;
	oldRef = INVALID_ENT_REFERENCE;
}
