// =========================================================================================================
// Another Jailbreak — Dummy module (Phase 2 API smoke test)
// Proves late-load / unload against library "ajb" without gameplay side effects.
// =========================================================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#undef REQUIRE_PLUGIN
#include <ajb/ajb>
#define REQUIRE_PLUGIN

#define PLUGIN_VERSION "1.0.0"

public Plugin myinfo =
{
	name        = "Another Jailbreak - Dummy",
	author      = "SummerTYT",
	description = "Another Jailbreak — API attach/detach smoke test module.",
	version     = PLUGIN_VERSION,
	url         = ""
};

bool g_bHasCore;

public void OnPluginStart()
{
	CreateConVar("sm_ajb_dummy_version", PLUGIN_VERSION, "AJB Dummy module version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	g_bHasCore = LibraryExists(AJB_LIBRARY);
	if (g_bHasCore)
	{
		LogMessage("[AJB-Dummy] attached | enabled=%d state=%d warden=%d",
			AJB_IsEnabled(),
			view_as<int>(AJB_GetRoundState()),
			AJB_GetWarden());
	}
	else
	{
		LogMessage("[AJB-Dummy] core missing at load (will attach on OnLibraryAdded).");
	}
}

public void OnPluginEnd()
{
	LogMessage("[AJB-Dummy] unload clean.");
}

public void OnLibraryAdded(const char[] name)
{
	if (!StrEqual(name, AJB_LIBRARY))
	{
		return;
	}

	g_bHasCore = true;
	LogMessage("[AJB-Dummy] core late-attached | enabled=%d", AJB_IsEnabled());
}

public void OnLibraryRemoved(const char[] name)
{
	if (!StrEqual(name, AJB_LIBRARY))
	{
		return;
	}

	g_bHasCore = false;
	LogMessage("[AJB-Dummy] core removed — module stays loaded, natives avoided.");
}

public void AJB_OnRoundStateChange(AJBRoundState oldState, AJBRoundState newState)
{
	LogMessage("[AJB-Dummy] state %d -> %d", view_as<int>(oldState), view_as<int>(newState));
}

public void AJB_OnWardenChanged(int oldWarden, int newWarden)
{
	LogMessage("[AJB-Dummy] warden %d -> %d", oldWarden, newWarden);
}
