// =========================================================================================================
// Phrase helpers — require a "Prefix" key in each plugin's translations file ({1} = prefix)
// =========================================================================================================

#if defined _ajb_phrases_included
 #endinput
#endif
#define _ajb_phrases_included

// morecolors uses legacy syntax; keep it isolated from newdecls required.
#pragma newdecls optional
#include <morecolors>
#pragma newdecls required

// %T needs a client; console uses LANG_SERVER.
stock int AJB_TransTarget(int client)
{
	return (client > 0 && client <= MaxClients) ? client : LANG_SERVER;
}

stock void AJB_GetPrefix(int client, char[] buffer, int maxlength)
{
	Format(buffer, maxlength, "%T", "Prefix", AJB_TransTarget(client));
}

stock void AJB_Reply(int client, const char[] phrase)
{
	char prefix[64];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	ReplyToCommand(client, "%T", phrase, AJB_TransTarget(client), prefix);
}

stock void AJB_Chat(int client, const char[] phrase)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}

	char prefix[64];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	CPrintToChat(client, "%T", phrase, client, prefix);
}

stock void AJB_ChatAll(const char[] phrase)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[64];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", phrase, i, prefix);
	}
}
