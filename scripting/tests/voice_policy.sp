// =========================================================================================================
// Another Jailbreak — Exhaustive voice policy self-check (load on a SourceMod test server)
// =========================================================================================================

#pragma semicolon 1
#pragma newdecls required

#include <ajb/voice>

public void OnPluginStart()
{
	if (AJB_Voice_IsAdmin(0) || AJB_Voice_IsAdmin(ADMFLAG_RESERVATION)
		|| !AJB_Voice_IsAdmin(ADMFLAG_GENERIC) || !AJB_Voice_IsAdmin(ADMFLAG_ROOT))
	{
		SetFailState("Mandatory admin exemption failed.");
	}

	// Cover all 32 combinations, including a muted admin and mute retention through death/revive.
	for (int bits = 0; bits < 32; bits++)
	{
		bool senderAlive = (bits & 1) != 0;
		bool receiverAlive = (bits & 2) != 0;
		bool muted = (bits & 4) != 0;
		bool senderAdmin = (bits & 8) != 0;
		bool receiverAdmin = (bits & 16) != 0;
		ListenOverride expected = Listen_Yes;
		if (!senderAdmin && !receiverAdmin)
		{
			if (senderAlive)
			{
				expected = muted ? Listen_No : Listen_Yes;
			}
			else
			{
				expected = receiverAlive ? Listen_No : Listen_Yes;
			}
		}
		if (AJB_Voice_GetOverride(senderAlive, receiverAlive, muted, senderAdmin, receiverAdmin) != expected)
		{
			SetFailState("Voice policy failed for combination %d.", bits);
		}
	}
	PrintToServer("[AJB] Voice policy: all 32 combinations and admin exemptions passed.");
}
