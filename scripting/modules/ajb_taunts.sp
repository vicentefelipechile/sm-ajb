#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <ajb/ajb>

public Plugin myinfo = 
{
	name = "AJB - Taunts",
	author = "Antigravity",
	description = "Victory Lap and Zoomin' Broom taunt commands",
	version = "1.0.0",
	url = ""
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_vl", Command_VictoryLap, "Play the Victory Lap taunt");
	RegConsoleCmd("sm_victorylap", Command_VictoryLap, "Play the Victory Lap taunt");
	
	RegConsoleCmd("sm_zb", Command_ZoominBroom, "Play the Zoomin' Broom taunt");
	RegConsoleCmd("sm_zoominbroom", Command_ZoominBroom, "Play the Zoomin' Broom taunt");
	
	RegConsoleCmd("sm_rps", Command_RockPaperScissors, "Play the Rock Paper Scissors taunt");
	RegConsoleCmd("sm_rockpaperscissors", Command_RockPaperScissors, "Play the Rock Paper Scissors taunt");
}

public Action Command_VictoryLap(int client, int args)
{
	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
	{
		ForceTaunt(client, 1172); // 1172 is Victory Lap
	}
	return Plugin_Handled;
}

public Action Command_ZoominBroom(int client, int args)
{
	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
	{
		ForceTaunt(client, 30672); // 30672 is Zoomin' Broom
	}
	return Plugin_Handled;
}

public Action Command_RockPaperScissors(int client, int args)
{
	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
	{
		ForceTaunt(client, 1110); // 1110 is Rock Paper Scissors
	}
	return Plugin_Handled;
}

void ForceTaunt(int client, int taunt_id)
{
	int ent = CreateEntityByName("tf_weapon_bat");
	if (ent != -1)
	{
		DispatchSpawn(ent);
		SetEntProp(ent, Prop_Send, "m_iItemDefinitionIndex", taunt_id);
		SetEntProp(ent, Prop_Send, "m_bInitialized", 1);
		
		int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", ent);
		
		FakeClientCommand(client, "taunt");
		
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", active);
		AcceptEntityInput(ent, "Kill");
	}
}
