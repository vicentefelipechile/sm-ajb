// =========================================================================================================
// Another Jailbreak - FF2 Boss Wish (loader)
// A Last Request wish that turns the next live round into a Freak Fortress 2 boss fight.
//
// DEPENDENCIES (blocked vs degraded):
// - freak_fortress_2.smx ("ff2r" library)   -> BLOCKED: wish item disabled without it.
//   Bosses must also be loaded (FF2R_GetGamemodeType() >= 1); on jailbreak maps maps.cfg has
//   "*" { "enable" "0" }, so FF2 precaches bosses but never runs the gamemode - exactly what we
//   need to borrow one boss for a round.
// - Ability subplugins (plugins/freaks/)    -> DEGRADED: boss spawns with model/weapons/health/
//   sounds/HUD but no rage/special abilities (those live in ff2r_default_abilities etc.). FF2 loads
//   them automatically when a boss is created and renames them to .ff2 while idle.
// - morecolors.inc is compiled into AJB; no separate morecolors plugin is required.
// - TF2Items / TF2Attributes / TF2Utils     -> DEGRADED: FF2 falls back internally (weapons with
//   fewer attributes, no ability lag compensation).
// Run "sm_ajb_ff2_status" (any player) for a live diagnosis.
// =========================================================================================================

#pragma semicolon 1
#pragma newdecls required

// =========================================================================================================
// Imports
// =========================================================================================================

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>

// cfgmap.inc defines CFGMAP_FF2R, enabling the BossData/ConfigMap methodmaps in ff2r.inc.
#include <cfgmap>
#undef REQUIRE_PLUGIN
#include <ff2r>
#define REQUIRE_PLUGIN

#undef REQUIRE_PLUGIN
#include <ajb/ajb>
#define REQUIRE_PLUGIN

#include <ajb/lrwish>
#include <ajb/phrases>

// =========================================================================================================
// Constants
// =========================================================================================================

#define PLUGIN_VERSION "1.0.0"

// Menu token registered in the Last Request wish menu (see ajb/lrwish.inc).
#define FF2_WISH_TOKEN "ff2boss"

// FF2 renames idle ability subplugins to .ff2 (plugins/freaks/), so both suffixes count.
#define FF2_SUBPLUGIN_FOLDER "freaks"

// Ability subplugins shipped with FF2 Rewrite's New Install Package (plugins/freaks/).
// Only the two base plugins are required for a boss round; the rest are DLC extras.
static const char FF2_EXPECTED_SUBPLUGINS[][] = {
	"ff2r_default_abilities",
	"ff2r_menu_abilities"
};
#define FF2_EXPECTED_SUBPLUGIN_COUNT 2

int g_iSubpluginCount;           // .smx/.ff2 files found in the subplugin folder
char g_sSubpluginMissing[128];   // expected base plugins not found (comma list)

// =========================================================================================================
// Plugin info
// =========================================================================================================

public Plugin myinfo =
{
	name        = "Another Jailbreak - FF2 Boss Wish",
	author      = "SummerTYT",
	description = "Another Jailbreak - Last Request wish that runs a Freak Fortress 2 boss round.",
	version     = PLUGIN_VERSION,
	url         = ""
};

// =========================================================================================================
// ConVars / state
// =========================================================================================================

ConVar g_cvEnabled;
ConVar g_cvBossTeam;

// Core/FF2 presence (optional natives must never run without their library).
bool g_bHasCore;
bool g_bFF2Loaded;
bool g_bSubpluginsPresent;

// Wish queued for the NEXT live round (applied in AJB_OnLiveRoundBegin, like other LR wishes).
bool g_bWishPending;
int g_iPendingSpecial;
int g_iPendingPrisoner;          // userid of the chooser (first choice for boss player)

// Boss round active this live round.
bool g_bFF2Active;
int g_iFF2Boss;
int g_iFF2OriginalTeam[MAXPLAYERS + 1];

// Set while the boss is being set up: the RED chooser dies in the team transit, and that
// setup suicide must not be treated as a boss defeat (see FF2_ApplyRound).
bool g_bFF2Applying;

Action Timer_FF2EndApplying(Handle timer)
{
	g_bFF2Applying = false;
	return Plugin_Stop;
}

// sm_ajb_freekill_detect would flag the boss's AoE splash as a mass-freekill; parked during the round.
ConVar g_cvFreekill;
int g_iFreekillOld;

bool FF2_IsLibraryUp()
{
	return (LibraryExists("ff2r") || LibraryExists("freak_fortress_2"))
		&& GetFeatureStatus(FeatureType_Native, "FF2R_GetGamemodeType") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "FF2R_GetSpecialCount") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "FF2R_GetSpecialData") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "FF2R_GetBossData") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "FF2R_CreateBoss") == FeatureStatus_Available;
}

// =========================================================================================================
// Plugin lifecycle
// =========================================================================================================

public void OnPluginStart()
{
	CreateConVar("sm_ajb_ff2_version", PLUGIN_VERSION, "AJB FF2 Boss Wish module version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_ajb_ff2_enabled", "1", "Enable the FF2 Boss Last Request wish.", _, true, 0.0, true, 1.0);
	g_cvBossTeam = CreateConVar("sm_ajb_ff2_boss_team", "3", "Team the boss fights for (2 = RED, 3 = BLU).", _, true, 2.0, true, 3.0);

	RegConsoleCmd("sm_ajb_ff2_status", Cmd_Status, "Print the FF2 Boss wish dependency diagnosis.");

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

	AutoExecConfig(true, "ajb_ff2");
	LoadTranslations("ajb_ff2.phrases");

	g_bHasCore = LibraryExists(AJB_LIBRARY);
	g_bFF2Loaded = FF2_IsLibraryUp();
	g_cvFreekill = FindConVar("sm_ajb_freekill_detect");
	CheckSubplugins();

	LogMessage("[AJB-FF2] loaded (core %s, ff2r %s, %d bosses, subplugins %s).",
		g_bHasCore ? "present" : "missing",
		g_bFF2Loaded ? "present" : "missing",
		g_bFF2Loaded ? FF2R_GetSpecialCount() : 0,
		g_bSubpluginsPresent ? "ok" : "missing");
}

public void OnAllPluginsLoaded()
{
	g_bHasCore = LibraryExists(AJB_LIBRARY);
	g_bFF2Loaded = FF2_IsLibraryUp();
	CheckSubplugins();
}

public void OnMapStart()
{
	g_bFF2Loaded = FF2_IsLibraryUp();
	CheckSubplugins();
}

public void OnConfigsExecuted()
{
	g_bFF2Loaded = FF2_IsLibraryUp();
	CheckSubplugins();
}

public void OnMapEnd()
{
	FF2_RoundCleanup();
	FF2_ClearPending();
}

public void OnPluginEnd()
{
	FF2_RoundCleanup();
	FF2_ClearPending();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = true;
	}
	else if (StrEqual(name, "ff2r") || StrEqual(name, "freak_fortress_2"))
	{
		g_bFF2Loaded = FF2_IsLibraryUp();
		CheckSubplugins();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, AJB_LIBRARY))
	{
		g_bHasCore = false;
	}
	else if (StrEqual(name, "ff2r") || StrEqual(name, "freak_fortress_2"))
	{
		// FF2 unloaded mid-round: the boss is gone with it, finish the round on teams alone.
		g_bFF2Loaded = false;
		if (g_bFF2Active)
		{
			g_iFF2Boss = 0;
		}
	}
}

// =========================================================================================================
// Last Request wish menu hooks (ajb/lrwish.inc)
// =========================================================================================================

public void AJB_OnLRWishMenu(int client, Menu menu)
{
	if (!g_cvEnabled.BoolValue)
	{
		return;
	}

	g_bFF2Loaded = FF2_IsLibraryUp();
	char line[96];
	if (!g_bFF2Loaded)
	{
		// BLOCKED: FF2 not installed - show why, keep the item unselectable.
		Format(line, sizeof(line), "%T", "LR Wish FF2 Missing", client);
		menu.AddItem(FF2_WISH_TOKEN, line, ITEMDRAW_DISABLED);
		return;
	}

	Format(line, sizeof(line), "%T", "LR Wish FF2", client);
	// BLOCKED: FF2 up but no bosses precached (charset -1 / characters.cfg missing).
	if (FF2R_GetGamemodeType() < 1)
	{
		menu.AddItem(FF2_WISH_TOKEN, line, ITEMDRAW_DISABLED);
		return;
	}

	menu.AddItem(FF2_WISH_TOKEN, line);
}

public Action AJB_OnLRWishSelect(int client, const char[] token)
{
	if (!StrEqual(token, FF2_WISH_TOKEN))
	{
		return Plugin_Continue;
	}

	if (client < 1 || !IsClientInGame(client) || !g_cvEnabled.BoolValue || !g_bFF2Loaded || !g_bHasCore)
	{
		return Plugin_Continue;
	}
	if (FF2R_GetGamemodeType() < 1)
	{
		return Plugin_Continue;
	}

	ShowBossPicker(client);
	return Plugin_Handled;
}

// =========================================================================================================
// Boss picker submenu
// =========================================================================================================

void ShowBossPicker(int client)
{
	Menu menu = new Menu(MenuHandler_BossPick);
	char title[64];
	Format(title, sizeof(title), "%T", "FF2 Picker Title", client);
	menu.SetTitle(title);

	// Only bosses FF2 actually precached are selectable (pack = active charset).
	int count = FF2R_GetSpecialCount();
	char buffer[64], index[8];
	for (int i = 0; i < count; i++)
	{
		BossData cfg = FF2R_GetSpecialData(i);
		if (!cfg)
		{
			continue;
		}

		cfg.GetString("name", buffer, sizeof(buffer));
		if (!buffer[0])
		{
			cfg.GetString("name_en", buffer, sizeof(buffer));
		}
		if (!buffer[0])
		{
			Format(buffer, sizeof(buffer), "Boss #%d", i + 1);
		}

		IntToString(i, index, sizeof(index));
		menu.AddItem(index, buffer);
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_BossPick(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}
	if (action != MenuAction_Select)
	{
		return 0;
	}

	int client = param1;
	if (client < 1 || !IsClientInGame(client) || !g_bFF2Loaded)
	{
		return 0;
	}

	char index[8];
	menu.GetItem(param2, index, sizeof(index));
	int special = StringToInt(index);
	if (special < 0)
	{
		return 0;
	}

	BossData cfg = FF2R_GetSpecialData(special);
	if (!cfg)
	{
		return 0;
	}

	char bossName[64];
	cfg.GetString("name", bossName, sizeof(bossName));
	if (!bossName[0])
	{
		cfg.GetString("name_en", bossName, sizeof(bossName));
	}

	// Queue for the NEXT live round; applied in AJB_OnLiveRoundBegin.
	g_bWishPending = true;
	g_iPendingSpecial = special;
	g_iPendingPrisoner = GetClientUserId(client);

	FF2_ChatAll1N("LR Chose FF2", client, bossName);
	return 0;
}

// =========================================================================================================
// Wish application (next live round)
// =========================================================================================================

public void AJB_OnLiveRoundBegin()
{
	if (!g_bWishPending)
	{
		return;
	}

	int special = g_iPendingSpecial;
	int chooserUserid = g_iPendingPrisoner;
	FF2_ClearPending();

	if (!g_cvEnabled.BoolValue || !g_bHasCore || !AJB_IsEnabled())
	{
		return;
	}

	if (!g_bFF2Loaded)
	{
		// BLOCKED: FF2 went away after the wish was queued - announce and drop.
		FF2_ChatAllCancelled(chooserUserid);
		return;
	}

	BossData cfg = FF2R_GetSpecialData(special);
	if (!cfg)
	{
		// BLOCKED: boss no longer loaded (pack changed / charset reloaded) - announce and drop.
		FF2_ChatAllCancelled(chooserUserid);
		return;
	}

	FF2_ApplyRound(chooserUserid, cfg, special);
}

void FF2_ApplyRound(int chooserUserid, BossData cfg, int special)
{
	int boss = GetClientOfUserId(chooserUserid);
	if (!(boss > 0 && IsClientInGame(boss)))
	{
		boss = FF2_PickRandomMerc();
	}
	if (boss < 1)
	{
		FF2_ChatAllCancelled(chooserUserid);
		return;
	}

	char bossName[64];
	cfg.GetString("name", bossName, sizeof(bossName));
	if (!bossName[0])
	{
		cfg.GetString("name_en", bossName, sizeof(bossName));
	}

	g_bFF2Active = true;
	g_iFF2Boss = boss;

	int redTeam = AJB_GetPrisonersTeam();
	int bossTeam = g_cvBossTeam.IntValue;
	// The wish is boss-vs-mercenaries: a boss team equal to the mercenary team would
	// leave one side empty and the round could never end. Guard against bad config.
	if (bossTeam == redTeam)
	{
		bossTeam = AJB_GetGuardsTeam();
	}

	// Day-style round: full loadouts, no warden, no rebel rules, no jail clock.
	// BeginCombatDay opens the cells and moves the state to SpecialDay; no further
	// state-changing calls after it (AGENTS.md order).
	AJB_BeginCombatDay();
	AJB_SetupSpecialDay();

	// The boss's AoE splash would trip the mass-freekill detector; park it for the round.
	FF2_SetFreekillDetect(false);

	// Snapshot real sides, fold every non-boss player onto RED as mercenaries.
	// Only players actually on the boss team move (spectators stay out), and the move is
	// a single direct ChangeClientTeam: the BLU→SPEC→RED double-call in the same frame
	// is unreliable (the engine can drop the second call mid-suicide, leaving the player
	// on BLU dead — and Frame_ArmRedPlayers only revives RED players). Direct cross-team
	// changes kill, which is fine here: FF2 has no death-restore logic, and
	// Frame_ArmRedPlayers respawns everyone on RED next frame.
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}

		int team = GetClientTeam(i);
		if (team == redTeam || team == bossTeam)
		{
			g_iFF2OriginalTeam[i] = team;
		}

		if (i != boss && team == bossTeam)
		{
			ChangeClientTeam(i, redTeam);
		}
	}

	// Boss first: transit to the boss team so FF2's internal team set is a no-op, then create.
	// Bosses_CreateFromConfig assigns health by player count, hooks the player and readies the
	// loadout; the spawn below triggers Events_PlayerSpawn -> Bosses_Equip.
	//
	// The chooser is a RED prisoner, so the transit KILLS them (spec-transit suicide) and
	// fires player_death with victim == g_iFF2Boss — without the applying guard that would
	// broadcast a false "Boss Defeated" before the round even starts.
	g_bFF2Applying = true;
	AJB_ChangeTeamSafe(boss, bossTeam);
	FF2R_CreateBoss(boss, cfg, bossTeam);
	BossData bossCfg = FF2R_GetBossData(boss);
	if (bossCfg)
	{
		bossCfg.Special = special;
	}

	TF2_RespawnPlayer(boss);
	// Death events can land a frame late; keep suppressing through the setup window.
	CreateTimer(1.0, Timer_FF2EndApplying, _, TIMER_FLAG_NO_MAPCHANGE);
	RequestFrame(Frame_ArmRedPlayers);

	if (!g_bSubpluginsPresent)
	{
		// DEGRADED: boss has no rage/special abilities without the ff2r_* ability subplugins.
		FF2_ChatAllNoAbilities();
	}

	FF2_ChatAllQueued("FF2 Applied", bossName);
}

public void Frame_ArmRedPlayers(any data)
{
	if (!g_bFF2Active)
	{
		return;
	}

	int redTeam = AJB_GetPrisonersTeam();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || i == g_iFF2Boss)
		{
			continue;
		}
		if (GetClientTeam(i) != redTeam)
		{
			continue;
		}

		if (IsPlayerAlive(i))
		{
			TF2_RegeneratePlayer(i);
		}
		else
		{
			TF2_RespawnPlayer(i);
		}
	}
}

// =========================================================================================================
// Round end / cleanup
// =========================================================================================================

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bFF2Active || g_bFF2Applying)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim != g_iFF2Boss || !g_bFF2Loaded)
	{
		return;
	}

	// Boss defeated: the empty boss team makes the engine end the round; AJB_OnRoundWin cleans up.
	char bossName[64];
	BossData cfg = FF2R_GetBossData(victim);
	if (cfg)
	{
		cfg.GetString("name", bossName, sizeof(bossName));
	}
	if (!bossName[0])
	{
		strcopy(bossName, sizeof(bossName), "Boss");
	}

	FF2_ChatAll1N("FF2 Boss Defeated", victim, bossName);
}

public void AJB_OnRoundWin(int team)
{
	FF2_RoundCleanup();
}

void FF2_RoundCleanup()
{
	if (!g_bFF2Active)
	{
		return;
	}

	g_bFF2Active = false;
	g_bFF2Applying = false;

	// Remove the boss first so post-round deaths are not treated as boss events by FF2.
	if (g_iFF2Boss > 0 && g_bFF2Loaded)
	{
		FF2R_CreateBoss(g_iFF2Boss, null, 0);
	}
	g_iFF2Boss = 0;

	int redTeam = g_bHasCore ? AJB_GetPrisonersTeam() : 2;
	int blueTeam = g_bHasCore ? AJB_GetGuardsTeam() : 3;
	for (int i = 1; i <= MaxClients; i++)
	{
		int want = g_iFF2OriginalTeam[i];
		g_iFF2OriginalTeam[i] = 0;
		if (want != redTeam && want != blueTeam)
		{
			continue;
		}
		if (!IsClientInGame(i) || GetClientTeam(i) == want)
		{
			continue;
		}
		ChangeClientTeam(i, want);
	}

	if (g_bHasCore)
	{
		AJB_SetRebelOnHit(true);
	}
	FF2_SetFreekillDetect(true);
}

void FF2_ClearPending()
{
	g_bWishPending = false;
	g_iPendingSpecial = -1;
	g_iPendingPrisoner = 0;
}

// =========================================================================================================
// Helpers
// =========================================================================================================

int FF2_PickRandomMerc()
{
	int clients[MAXPLAYERS];
	int count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) > view_as<int>(TFTeam_Spectator))
		{
			clients[count++] = i;
		}
	}
	if (!count)
	{
		return 0;
	}
	return clients[GetURandomInt() % count];
}

void FF2_SetFreekillDetect(bool enabled)
{
	if (g_cvFreekill == null)
	{
		g_cvFreekill = FindConVar("sm_ajb_freekill_detect");
	}
	if (g_cvFreekill == null)
	{
		return;
	}

	if (!enabled)
	{
		g_iFreekillOld = g_cvFreekill.IntValue;
		g_cvFreekill.SetInt(0);
	}
	else
	{
		g_cvFreekill.SetInt(g_iFreekillOld);
	}
}

void CheckSubplugins()
{
	g_bSubpluginsPresent = false;
	g_iSubpluginCount = 0;
	g_sSubpluginMissing[0] = '\0';

	// Without FF2 loaded there is nothing to diagnose and no subplugin folder to scan.
	if (!g_bFF2Loaded)
	{
		return;
	}

	// FF2 loads ability subplugins from plugins/<ff2_plugin_subplugins>/ and renames them to
	// .ff2 while no boss exists - check both suffixes.
	ConVar cv = FindConVar("ff2_plugin_subplugins");
	char folder[64];
	if (cv != null)
	{
		cv.GetString(folder, sizeof(folder));
	}
	if (!folder[0])
	{
		strcopy(folder, sizeof(folder), FF2_SUBPLUGIN_FOLDER);
	}

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "plugins/%s", folder);

	// Which of the expected base plugins are present (matched by base name).
	bool found[FF2_EXPECTED_SUBPLUGIN_COUNT];
	DirectoryListing dir = OpenDirectory(path);
	if (dir)
	{
		char filename[PLATFORM_MAX_PATH];
		FileType type;
		while (dir.GetNext(filename, sizeof(filename), type))
		{
			if (type != FileType_File)
			{
				continue;
			}

			int pos = strlen(filename) - 4;
			if (pos <= 0 || (StrEqual(filename[pos], ".smx") == false && StrEqual(filename[pos], ".ff2") == false))
			{
				continue;
			}

			g_iSubpluginCount++;
			filename[pos] = '\0';

			for (int i = 0; i < FF2_EXPECTED_SUBPLUGIN_COUNT; i++)
			{
				if (!found[i] && StrEqual(filename, FF2_EXPECTED_SUBPLUGINS[i], false))
				{
					found[i] = true;
					break;
				}
			}
		}
		delete dir;
	}

	// Compose the missing list for the status command.
	int missingCount = 0;
	for (int i = 0; i < FF2_EXPECTED_SUBPLUGIN_COUNT; i++)
	{
		if (!found[i])
		{
			if (missingCount > 0)
			{
				StrCat(g_sSubpluginMissing, sizeof(g_sSubpluginMissing), ", ");
			}
			StrCat(g_sSubpluginMissing, sizeof(g_sSubpluginMissing), FF2_EXPECTED_SUBPLUGINS[i]);
			missingCount++;
		}
	}

	g_bSubpluginsPresent = (missingCount == 0);
}

void FF2_ChatAll1N(const char[] phrase, int player, const char[] bossName)
{
	AJB_ChatAll1N1S(phrase, player, bossName);
}

void FF2_ChatAllQueued(const char[] phrase, const char[] bossName)
{
	AJB_ChatAll1S(phrase, bossName);
}

void FF2_ChatAllCancelled(int chooserUserid)
{
	int chooser = GetClientOfUserId(chooserUserid);
	if (chooser > 0)
	{
		AJB_ChatAll1N("FF2 Cancelled", chooser);
	}
	else
	{
		AJB_ChatAll("FF2 Cancelled No Boss");
	}
}

void FF2_ChatAllNoAbilities()
{
	AJB_ChatAll("FF2 No Abilities");
}

// =========================================================================================================
// Status / diagnosis
// =========================================================================================================

public Action Cmd_Status(int client, int args)
{
	g_bFF2Loaded = FF2_IsLibraryUp();
	CheckSubplugins();
	ReplyToCommand(client, "[AJB-FF2] ff2r plugin: %s", g_bFF2Loaded ? "loaded" : "MISSING (wish disabled)");
	if (g_bFF2Loaded)
	{
		ReplyToCommand(client, "[AJB-FF2] gamemode type: %d (0 = no bosses loaded, 1 = bosses ready, 2 = ff2 running the round)", FF2R_GetGamemodeType());
		ReplyToCommand(client, "[AJB-FF2] bosses precached: %d", FF2R_GetSpecialCount());

		if (g_bSubpluginsPresent)
		{
			ReplyToCommand(client, "[AJB-FF2] ability subplugins: present (%d file(s) in plugins/%s/)", g_iSubpluginCount, FF2_SUBPLUGIN_FOLDER);
		}
		else
		{
			ReplyToCommand(client, "[AJB-FF2] ability subplugins: MISSING (boss spawns without rage/abilities)");
			if (g_sSubpluginMissing[0] != '\0')
			{
				ReplyToCommand(client, "[AJB-FF2]   expected but not found: %s", g_sSubpluginMissing);
			}
			ReplyToCommand(client, "[AJB-FF2]   fix: FF2 Rewrite -> addons/sourcemod/plugins/freaks/ff2r_*_abilities.smx");
		}
	}
	else
	{
		// FF2 itself is absent: subplugins are irrelevant, not a separate problem.
		ReplyToCommand(client, "[AJB-FF2] ability subplugins: N/A (ff2r not installed; they ship with FF2 Rewrite)");
	}
	ReplyToCommand(client, "[AJB-FF2] wish pending: %s | round active: %s",
		g_bWishPending ? "yes" : "no",
		g_bFF2Active ? "yes" : "no");
	return Plugin_Handled;
}
