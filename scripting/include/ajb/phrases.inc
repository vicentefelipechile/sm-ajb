// =========================================================================================================
// Another Jailbreak — Phrase helpers (Prefix pattern, same idea as tf_building_attributes)
// Each plugin must LoadTranslations its own file containing a "Prefix" phrase.
// =========================================================================================================

#if defined _ajb_phrases_included
 #endinput
#endif
#define _ajb_phrases_included

// %T needs a client id; console/server replies use LANG_SERVER.
stock int AJB_TransTarget(int client)
{
	return (client > 0 && client <= MaxClients) ? client : LANG_SERVER;
}

stock void AJB_GetPrefix(int client, char[] buffer, int maxlength)
{
	Format(buffer, maxlength, "%T", "Prefix", AJB_TransTarget(client));
}

// Reply with prefix only (phrase body has no extra args).
stock void AJB_Reply(int client, const char[] phrase)
{
	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	ReplyToCommand(client, "%T", phrase, AJB_TransTarget(client), prefix);
}

// PrintToChat one client, prefix only.
stock void AJB_Chat(int client, const char[] phrase)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}

	char prefix[32];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	PrintToChat(client, "%T", phrase, client, prefix);
}

// Broadcast: each client gets their language's Prefix.
stock void AJB_ChatAll(const char[] phrase)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		PrintToChat(i, "%T", phrase, i, prefix);
	}
}
