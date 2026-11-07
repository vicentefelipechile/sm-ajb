// =========================================================================================================
// Another Jailbreak — Temporary equal-team balancing for combat events
// =========================================================================================================

#if defined _ajb_teams_included
	#endinput
#endif
#define _ajb_teams_included

#include <sourcemod>
#include <tf2_stocks>

#include <ajb/ajb>

stock int AJB_BalanceTeamsEqual(int redTeam, int bluTeam, int[] originalTeams)
{
	int redCount, bluCount;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i)) continue;
		int team = GetClientTeam(i);
		if (team == redTeam) redCount++;
		else if (team == bluTeam) bluCount++;
	}

	int difference = redCount - bluCount;
	if (difference >= -1 && difference <= 1)
	{
		return 0;
	}

	int source = difference > 0 ? redTeam : bluTeam;
	int target = difference > 0 ? bluTeam : redTeam;
	int moves = (difference > 0 ? difference : -difference) / 2;
	int candidates[MAXPLAYERS];
	int count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == source)
		{
			candidates[count++] = i;
		}
	}

	for (int i = 0; i < moves; i++)
	{
		int pick = GetRandomInt(0, count - 1);
		int client = candidates[pick];
		candidates[pick] = candidates[--count];
		originalTeams[client] = source;
		bool alive = IsPlayerAlive(client);
		AJB_ChangeTeamSafe(client, target);
		// Living participants need the new team's spawn; dead players must stay dead.
		if (alive) TF2_RespawnPlayer(client);
	}
	return moves;
}

stock void AJB_RestoreBalancedTeams(int[] originalTeams)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		int team = originalTeams[i];
		originalTeams[i] = 0;
		if (team < 2 || !IsClientInGame(i)) continue;
		int current = GetClientTeam(i);
		// A player who opted out into spectator must not be forced back into play.
		if (current < 2 || current == team) continue;

		bool alive = IsPlayerAlive(i);
		AJB_ChangeTeamSafe(i, team);
		if (alive) TF2_RespawnPlayer(i);
	}
}
