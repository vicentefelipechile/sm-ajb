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

// The Prefix phrase is static per language, so a broadcast loop does not need to
// re-run a %T lookup for every recipient — cache the formatted result per language id.
#define AJB_PREFIX_CACHE_LANGS 10

static char g_sPrefixCache[AJB_PREFIX_CACHE_LANGS][64];
static int g_iPrefixCacheLang[AJB_PREFIX_CACHE_LANGS];
static int g_iPrefixCacheCount;

stock void AJB_GetPrefix(int client, char[] buffer, int maxlength)
{
	int lang = (client > 0 && client <= MaxClients) ? GetClientLanguage(client) : LANG_SERVER;

	for (int i = 0; i < g_iPrefixCacheCount; i++)
	{
		if (g_iPrefixCacheLang[i] == lang)
		{
			strcopy(buffer, maxlength, g_sPrefixCache[i]);
			return;
		}
	}

	if (g_iPrefixCacheCount < AJB_PREFIX_CACHE_LANGS)
	{
		int idx = g_iPrefixCacheCount++;
		g_iPrefixCacheLang[idx] = lang;
		Format(g_sPrefixCache[idx], sizeof(g_sPrefixCache[]), "%T", "Prefix", lang);
		strcopy(buffer, maxlength, g_sPrefixCache[idx]);
	}
	else
	{
		// Cache full (unusual mix of client languages) — fall back to a direct lookup.
		Format(buffer, maxlength, "%T", "Prefix", AJB_TransTarget(client));
	}
}

stock void AJB_Reply(int client, const char[] phrase)
{
	char prefix[64];
	AJB_GetPrefix(client, prefix, sizeof(prefix));
	// CReplyToCommand: chat gets morecolors tags; console gets stripped text.
	// ReplyToCommand would print literal "{green}[AJB]{default} ...".
	CReplyToCommand(client, "%T", phrase, AJB_TransTarget(client), prefix);
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

// ---------------------------------------------------------------------------------------------------------
// Broadcast shapes with arguments — every "announce to everyone" goes through these so no
// caller re-implements the in-game/prefix loop. {1}=prefix, {2}=recipient; the N/S params
// fill {3}.. onward in order.
// ---------------------------------------------------------------------------------------------------------

stock void AJB_ChatAll1N(const char[] phrase, int p1)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[64];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", phrase, i, prefix, p1);
	}
}

stock void AJB_ChatAll2N(const char[] phrase, int p1, int p2)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[64];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", phrase, i, prefix, p1, p2);
	}
}

stock void AJB_ChatAll1S(const char[] phrase, const char[] s1)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[64];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", phrase, i, prefix, s1);
	}
}

stock void AJB_ChatAll2S(const char[] phrase, const char[] s1, const char[] s2)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[64];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", phrase, i, prefix, s1, s2);
	}
}

stock void AJB_ChatAll3S(const char[] phrase, const char[] s1, const char[] s2, const char[] s3)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[64];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", phrase, i, prefix, s1, s2, s3);
	}
}

stock void AJB_ChatAll1N1S(const char[] phrase, int p1, const char[] s1)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[64];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", phrase, i, prefix, p1, s1);
	}
}

stock void AJB_ChatAll1S1N(const char[] phrase, const char[] s1, int p1)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[64];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", phrase, i, prefix, s1, p1);
	}
}

stock void AJB_ChatAll1S2N(const char[] phrase, const char[] s1, int p1, int p2)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[64];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", phrase, i, prefix, s1, p1, p2);
	}
}

stock void AJB_AdminBroadcast(int client, const char[] phrase, int target = -1)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[64];
		AJB_GetPrefix(i, prefix, sizeof(prefix));

		if (target == -1)
		{
			CPrintToChat(i, "%T", phrase, i, prefix, client);
		}
		else
		{
			CPrintToChat(i, "%T", phrase, i, prefix, client, target);
		}
	}
}
