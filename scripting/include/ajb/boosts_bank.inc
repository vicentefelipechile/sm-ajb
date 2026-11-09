// =========================================================================================================
// Another Jailbreak — Persistent boost-point bank
// =========================================================================================================

#if defined _ajb_boosts_bank_included
 #endinput
#endif
#define _ajb_boosts_bank_included

#include <sourcemod>

Database g_hBoostBankDB;
bool g_bBoostBankConnecting;
bool g_bBoostBankLoaded[MAXPLAYERS + 1];
int g_iBoostBank[MAXPLAYERS + 1];
char g_sBoostBankSteamID[MAXPLAYERS + 1][32];

void AJB_Boosts_BankConnect()
{
	if (g_hBoostBankDB != null || g_bBoostBankConnecting)
	{
		return;
	}

	char config[32] = "ajb";
	if (!SQL_CheckConfig(config))
	{
		strcopy(config, sizeof(config), "storage-local");
	}
	if (!SQL_CheckConfig(config))
	{
		LogError("[AJB-Boosts] No 'ajb' or 'storage-local' database configuration; bank unavailable.");
		return;
	}

	g_bBoostBankConnecting = true;
	Database.Connect(AJB_Boosts_OnBankConnected, config);
}

public void AJB_Boosts_OnBankConnected(Database db, const char[] error, any data)
{
	g_bBoostBankConnecting = false;
	if (db == null)
	{
		LogError("[AJB-Boosts] Bank connection failed: %s", error);
		return;
	}

	if (!SQL_FastQuery(db, "CREATE TABLE IF NOT EXISTS ajb_boost_bank (steamid VARCHAR(32) NOT NULL PRIMARY KEY, points INT NOT NULL DEFAULT 0);"))
	{
		char queryError[256];
		SQL_GetError(db, queryError, sizeof(queryError));
		LogError("[AJB-Boosts] Bank table creation failed: %s", queryError);
		delete db;
		return;
	}
	g_hBoostBankDB = db;

	for (int i = 1; i <= MaxClients; i++)
	{
		AJB_Boosts_BankLoad(i);
	}
}

void AJB_Boosts_BankReset(int client)
{
	g_bBoostBankLoaded[client] = false;
	g_iBoostBank[client] = 0;
	g_sBoostBankSteamID[client][0] = '\0';
}

bool AJB_Boosts_BankLoad(int client)
{
	if (g_bBoostBankLoaded[client])
	{
		return true;
	}
	if (g_hBoostBankDB == null || !IsClientInGame(client) || IsFakeClient(client)
		|| !GetClientAuthId(client, AuthId_SteamID64, g_sBoostBankSteamID[client], sizeof(g_sBoostBankSteamID[])))
	{
		return false;
	}

	char query[160];
	Format(query, sizeof(query), "SELECT points FROM ajb_boost_bank WHERE steamid = '%s';", g_sBoostBankSteamID[client]);
	DBResultSet results = SQL_Query(g_hBoostBankDB, query);
	if (results == null)
	{
		char error[256];
		SQL_GetError(g_hBoostBankDB, error, sizeof(error));
		LogError("[AJB-Boosts] Bank load failed for %s: %s", g_sBoostBankSteamID[client], error);
		return false;
	}

	g_iBoostBank[client] = results.FetchRow() ? results.FetchInt(0) : 0;
	delete results;
	if (g_iBoostBank[client] < 0)
	{
		g_iBoostBank[client] = 0;
	}
	g_bBoostBankLoaded[client] = true;
	return true;
}

bool AJB_Boosts_BankSave(int client, int points)
{
	if (!AJB_Boosts_BankLoad(client))
	{
		return false;
	}
	if (points == g_iBoostBank[client])
	{
		return true;
	}

	char query[192];
	Format(query, sizeof(query), "REPLACE INTO ajb_boost_bank (steamid, points) VALUES ('%s', %d);", g_sBoostBankSteamID[client], points);
	// Commit before changing available points so a failed withdrawal cannot duplicate them.
	if (!SQL_FastQuery(g_hBoostBankDB, query))
	{
		char error[256];
		SQL_GetError(g_hBoostBankDB, error, sizeof(error));
		LogError("[AJB-Boosts] Bank save failed for %s: %s", g_sBoostBankSteamID[client], error);
		return false;
	}

	g_iBoostBank[client] = points;
	return true;
}

bool AJB_Boosts_BankDeposit(int client, int amount, int limit)
{
	if (!AJB_Boosts_BankLoad(client))
	{
		return false;
	}

	int room = limit - g_iBoostBank[client];
	if (room <= 0)
	{
		return true;
	}
	if (amount > room)
	{
		amount = room;
	}
	return AJB_Boosts_BankSave(client, g_iBoostBank[client] + amount);
}

int AJB_Boosts_BankWithdraw(int client, int amount)
{
	if (!AJB_Boosts_BankLoad(client) || amount <= 0)
	{
		return 0;
	}
	if (amount > g_iBoostBank[client])
	{
		amount = g_iBoostBank[client];
	}
	return AJB_Boosts_BankSave(client, g_iBoostBank[client] - amount) ? amount : 0;
}
