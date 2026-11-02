// =========================================================================================================
// Another Jailbreak — Voice policy independent of team, freeday, rebel and LR status
// =========================================================================================================

#if defined _ajb_voice_included
	#endinput
#endif
#define _ajb_voice_included

#include <sourcemod>
#include <sdktools_voice>

stock bool AJB_Voice_IsAdmin(int flags)
{
	return (flags & (ADMFLAG_GENERIC | ADMFLAG_ROOT)) != 0;
}

stock ListenOverride AJB_Voice_GetOverride(bool senderAlive, bool receiverAlive, bool wardenMuted,
	bool senderAdmin, bool receiverAdmin)
{
	// AJB never restricts admin speech or hearing; external/personal mutes still take precedence.
	if (senderAdmin || receiverAdmin)
	{
		return Listen_Yes;
	}
	if (senderAlive && wardenMuted)
	{
		return Listen_No;
	}
	if (!senderAlive && receiverAlive)
	{
		return Listen_No;
	}
	return Listen_Yes;
}
