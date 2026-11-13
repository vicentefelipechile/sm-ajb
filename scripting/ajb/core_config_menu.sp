// =========================================================================================================
// Persistent admin configuration and per-map teleport placement
// =========================================================================================================

#define AJB_CONFIG_COMMAND "sm_ajb_config_menu"
#define AJB_TELEPORT_COMMAND "sm_ajb_teleports"

int g_iConfigMapSerial;

enum AJBConfigGroup
{
	Config_Round,
	Config_Warden,
	Config_Freeday,
	Config_Wishes,
	Config_Boosts,
	Config_WishGeneral,
	Config_HideSeek,
	Config_HungerGames,
	Config_Zombies,
	Config_CellWars,
	Config_Sniper,
	Config_Dodgeball,
	Config_Yeti
};

enum struct AJBConfigSetting
{
	AJBConfigGroup group;
	char name[48];
	float step;
}

static const char g_sConfigGroups[][] =
{
	"Config Round", "Config Warden", "Config Freeday", "Config Wishes", "Config Boosts",
	"Config General", "Config HideSeek", "Config HungerGames", "Config Zombies",
	"Config CellWars", "Config Sniper", "DB Editor", "Config Yeti"
};

// Zero steps are toggles and negative steps are named binary choices; bounds remain native.
static const AJBConfigSetting g_ConfigSettings[] =
{
	{Config_Round, "sm_ajb_prep_time", 1.0},
	{Config_Round, "sm_ajb_round_time", 30.0},
	{Config_Round, "sm_ajb_cells_auto_open", 5.0},
	{Config_Round, "sm_ajb_guard_ratio", 1.0},
	{Config_Round, "sm_ajb_balance_enforce", 0.0},
	{Config_Warden, "sm_ajb_warden_auto", 0.0},
	{Config_Warden, "sm_ajb_warden_auto_delay", 1.0},
	{Config_Warden, "sm_ajb_warden_auto_mode", -1.0},
	{Config_Warden, "sm_ajb_firewarden_ratio", 0.05},
	{Config_Warden, "sm_ajb_firewarden_cooldown", 5.0},
	{Config_WishGeneral, "sm_ajb_lr_enabled", 0.0},
	{Config_WishGeneral, "sm_ajb_lr_menu_time", 5.0},
	{Config_WishGeneral, "sm_ajb_lr_suicide_delay", 1.0},
	{Config_WishGeneral, "sm_ajb_lr_hot_damage", 1.0},
	{Config_WishGeneral, "sm_ajb_lr_low_gravity", 50.0},
	{Config_HideSeek, "sm_ajb_lr_hs_hide_time", 5.0},
	{Config_HideSeek, "sm_ajb_lr_hs_round_time", 30.0},
	{Config_HungerGames, "sm_ajb_lr_hg_grace_time", 5.0},
	{Config_HungerGames, "sm_ajb_lr_hg_round_time", 30.0},
	{Config_Zombies, "sm_ajb_lr_zm_infect_delay", 1.0},
	{Config_Zombies, "sm_ajb_lr_zm_hits", 1.0},
	{Config_Zombies, "sm_ajb_lr_zm_respawn", 1.0},
	{Config_Zombies, "sm_ajb_lr_zm_spawn_protect", 1.0},
	{Config_Zombies, "sm_ajb_lr_zm_round_time", 30.0},
	{Config_Zombies, "sm_ajb_lr_zm_fog_enabled", 0.0},
	{Config_Zombies, "sm_ajb_lr_zm_fog_start", 50.0},
	{Config_Zombies, "sm_ajb_lr_zm_fog_end", 50.0},
	{Config_Zombies, "sm_ajb_lr_zm_fog_density", 0.05},
	{Config_CellWars, "sm_ajb_lr_cw_round_time", 30.0},
	{Config_CellWars, "sm_ajb_lr_cw_teleport_delay", 0.5},
	{Config_CellWars, "sm_ajb_lr_cw_camp_time", 1.0},
	{Config_CellWars, "sm_ajb_lr_cw_camp_damage", 1.0},
	{Config_CellWars, "sm_ajb_lr_cw_teleport_heal", 1.0},
	{Config_Sniper, "sm_ajb_lr_sniper_min", 1.0},
	{Config_Sniper, "sm_ajb_lr_sniper_max", 1.0},
	{Config_Sniper, "sm_ajb_lr_sniper_force", 100.0},
	{Config_Sniper, "sm_ajb_lr_sniper_hit_chance", 5.0},
	{Config_Sniper, "sm_ajb_lr_sniper_duck_time", 0.1},
	{Config_Sniper, "sm_ajb_lr_sniper_body_damage", 5.0},
	{Config_Dodgeball, "sm_ajb_lr_db_speed_base", 50.0},
	{Config_Dodgeball, "sm_ajb_lr_db_speed_inc", 10.0},
	{Config_Dodgeball, "sm_ajb_lr_db_turn_rate", 0.05},
	{Config_Dodgeball, "sm_ajb_lr_db_barrier_dmg", 1.0},
	{Config_Yeti, "sm_ajb_lr_yeti_round_time", 30.0},
	{Config_Yeti, "sm_ajb_lr_yeti_hide_time", 1.0},
	{Config_Yeti, "sm_ajb_lr_yeti_pick", -1.0},
	{Config_Yeti, "sm_ajb_lr_yeti_speed", 10.0},
	{Config_Yeti, "sm_ajb_lr_yeti_thaw_time", 1.0},
	{Config_Yeti, "sm_ajb_lr_yeti_thaw_radius", 10.0},
	{Config_Yeti, "sm_ajb_lr_yeti_slow_time", 0.5},
	{Config_Yeti, "sm_ajb_lr_yeti_slow_factor", 0.05},
	{Config_Yeti, "sm_ajb_lr_yeti_slow_immune", 1.0},
	{Config_Yeti, "sm_ajb_lr_yeti_rage_per_sec", 0.5},
	{Config_Yeti, "sm_ajb_lr_yeti_rage_per_freeze", 5.0},
	{Config_Yeti, "sm_ajb_lr_yeti_roar_radius", 100.0},
	{Config_Yeti, "sm_ajb_lr_yeti_roar_reveal", 1.0},
	{Config_Yeti, "sm_ajb_lr_yeti_charge_cooldown", 1.0},
	{Config_Yeti, "sm_ajb_lr_yeti_charge_force", 100.0},
	{Config_Yeti, "sm_ajb_lr_yeti_climb", 0.0},
	{Config_Yeti, "sm_ajb_lr_yeti_climb_force", 100.0},
	{Config_Yeti, "sm_ajb_lr_yeti_growl_min", 5.0},
	{Config_Yeti, "sm_ajb_lr_yeti_growl_max", 5.0},
	{Config_Yeti, "sm_ajb_lr_yeti_heart_radius", 100.0},
	{Config_Yeti, "sm_ajb_lr_yeti_wind_volume", 0.05},
	{Config_Yeti, "sm_ajb_lr_yeti_wind_length", 1.0},
	{Config_Boosts, "sm_ajb_boosts_enabled", 0.0},
	{Config_Boosts, "sm_ajb_boosts_max_points", 1.0},
	{Config_Boosts, "sm_ajb_boosts_bank_max_points", 1.0},
	{Config_Boosts, "sm_ajb_boosts_blu_every", 1.0},
	{Config_Boosts, "sm_ajb_boosts_cost_iron_neck", 1.0},
	{Config_Boosts, "sm_ajb_boosts_cost_revive", 1.0},
	{Config_Boosts, "sm_ajb_boosts_cost_visibility", 1.0},
	{Config_Boosts, "sm_ajb_boosts_cost_second_wind", 1.0},
	{Config_Boosts, "sm_ajb_boosts_cost_mad_milk", 1.0},
	{Config_Boosts, "sm_ajb_boosts_cost_melee_crit", 1.0},
	{Config_Boosts, "sm_ajb_boosts_cost_jarate", 1.0},
	{Config_Boosts, "sm_ajb_boosts_cost_regen", 1.0},
	{Config_Boosts, "sm_ajb_boosts_second_wind_hp", 5.0},
	{Config_Boosts, "sm_ajb_boosts_regen_instant_hp", 5.0},
	{Config_Boosts, "sm_ajb_boosts_regen_duration", 1.0},
	{Config_Boosts, "sm_ajb_boosts_regen_per_tick", 1.0}
};

static const char g_sTeleportPhrases[][] = {"Config Freeday", "Teleport Combat Red", "Teleport Combat Blu"};
static const char g_sFreedayKeys[][] = {"freeday_trail", "freeday_warden_only_damage"};

// =========================================================================================================
// Access and persistent settings
// =========================================================================================================

bool AJB_Config_CanEdit(int client, const char[] command = AJB_CONFIG_COMMAND)
{
	return g_bModeActive && AJB_IsValidClient(client)
		&& CheckCommandAccess(client, "sm_ajb", ADMFLAG_GENERIC)
		&& CheckCommandAccess(client, command, ADMFLAG_CONFIG);
}

bool AJB_Config_GroupAvailable(AJBConfigGroup group)
{
	if (group == Config_Boosts) return LibraryExists("ajb_boosts");
	if (group == Config_Wishes || group >= Config_WishGeneral) return LibraryExists("ajb_lastrequest");
	return true;
}

void AJB_Config_FormatValue(int client, int setting, float value, char[] buffer, int maxlen)
{
	if (g_ConfigSettings[setting].step == 0.0)
		Format(buffer, maxlen, "%T", value != 0.0 ? "Config On" : "Config Off", client);
	else if (StrEqual(g_ConfigSettings[setting].name, "sm_ajb_warden_auto_mode"))
		Format(buffer, maxlen, "%T", value == 0.0 ? "Config Random" : "Config Weighted", client);
	else if (StrEqual(g_ConfigSettings[setting].name, "sm_ajb_lr_yeti_pick"))
		Format(buffer, maxlen, "%T", value == 0.0 ? "Config Random Guard" : "Config LR Chooser", client);
	else
	{
		Format(buffer, maxlen, "%.2f", value);
		int end = strlen(buffer) - 1;
		while (end > 0 && buffer[end] == '0') buffer[end--] = '\0';
		if (buffer[end] == '.') buffer[end] = '\0';
	}
}

bool AJB_Config_SaveSetting(int client, int setting, float value)
{
	AJBConfigGroup group = g_ConfigSettings[setting].group;
	if (!AJB_Config_GroupAvailable(group)) return false;
	ConVar cvar = FindConVar(g_ConfigSettings[setting].name);
	if (cvar == null) return false;
	float lower = 0.0, upper;
	cvar.GetBounds(ConVarBound_Lower, lower);
	if (value < lower) value = lower;
	if (cvar.GetBounds(ConVarBound_Upper, upper) && value > upper) value = upper;
	if (StrEqual(g_ConfigSettings[setting].name, "sm_ajb_lr_db_turn_rate") && value > 1.0) value = 1.0;
	if (StrEqual(g_ConfigSettings[setting].name, "sm_ajb_lr_zm_fog_start"))
	{
		if (value >= FindConVar("sm_ajb_lr_zm_fog_end").FloatValue) return false;
	}
	else if (StrEqual(g_ConfigSettings[setting].name, "sm_ajb_lr_zm_fog_end"))
	{
		if (value <= FindConVar("sm_ajb_lr_zm_fog_start").FloatValue) return false;
	}

	char path[PLATFORM_MAX_PATH], number[32];
	BuildPath(Path_SM, path, sizeof(path), "../../cfg/sourcemod/%s.cfg",
		group == Config_Boosts ? "ajb_boosts" : (group >= Config_WishGeneral ? "ajb_lastrequest" : "ajb"));
	Format(number, sizeof(number), "%.2f", value);
	if (!AJB_Config_WriteConVar(path, g_ConfigSettings[setting].name, number)) return false;
	cvar.SetString(number);
	LogAction(client, -1, "\"%L\" set %s to %s", client, g_ConfigSettings[setting].name, number);
	return true;
}

bool AJB_Config_SaveFreeday(int client, int option)
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), AJB_SETTINGS_FILE);
	KeyValues kv = AJB_Config_Read(path, "Settings");
	if (kv == null) return false;
	bool enabled = !(option == 0 ? g_bFreedayTrail : g_bFreedayWardenOnlyDamage);
	kv.SetNum(g_sFreedayKeys[option], enabled ? 1 : 0);
	bool saved = AJB_Config_Write(kv, path);
	delete kv;
	if (saved)
	{
		AJB_Settings_Load();
		AJB_PlayerFx_EnsureTimer();
		LogAction(client, -1, "\"%L\" set %s to %d", client, g_sFreedayKeys[option], enabled);
	}
	return saved;
}

// =========================================================================================================
// Configuration menus
// =========================================================================================================

void AJB_Config_ShowGroups(int client, bool wishes = false)
{
	if (!AJB_Config_CanEdit(client)) return;
	Menu menu = new Menu(MenuHandler_ConfigGroups);
	menu.SetTitle("%T", wishes ? "Config Wishes" : "Config Title", client);
	char info[8], label[96];
	int first = wishes ? view_as<int>(Config_WishGeneral) : view_as<int>(Config_Round);
	int last = wishes ? view_as<int>(Config_Yeti) : view_as<int>(Config_Boosts);
	for (int group = first; group <= last; group++)
	{
		IntToString(group, info, sizeof(info));
		Format(label, sizeof(label), "%T", g_sConfigGroups[group], client);
		menu.AddItem(info, label, AJB_Config_GroupAvailable(view_as<AJBConfigGroup>(group)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ConfigGroups(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End) delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && AJB_Config_CanEdit(client))
	{
		char info[8];
		menu.GetItem(0, info, sizeof(info));
		if (StringToInt(info) == view_as<int>(Config_WishGeneral)) AJB_Config_ShowGroups(client);
		else FakeClientCommand(client, "sm_ajb");
	}
	else if (action == MenuAction_Select && AJB_Config_CanEdit(client))
	{
		char info[8];
		menu.GetItem(item, info, sizeof(info));
		AJBConfigGroup group = view_as<AJBConfigGroup>(StringToInt(info));
		if (group == Config_Wishes) AJB_Config_ShowGroups(client, true);
		else AJB_Config_ShowGroup(client, group);
	}
	return 0;
}

void AJB_Config_ShowGroup(int client, AJBConfigGroup group, int position = 0)
{
	if (!AJB_Config_CanEdit(client) || !AJB_Config_GroupAvailable(group)) return;
	Menu menu = new Menu(MenuHandler_ConfigGroup);
	menu.SetTitle("%T", g_sConfigGroups[group], client);
	char info[16], label[192], value[64];
	if (group == Config_Freeday)
	{
		for (int option = 0; option < sizeof(g_sFreedayKeys); option++)
		{
			Format(info, sizeof(info), "fd:%d", option);
			bool enabled = option == 0 ? g_bFreedayTrail : g_bFreedayWardenOnlyDamage;
			Format(value, sizeof(value), "%T", enabled ? "Config On" : "Config Off", client);
			Format(label, sizeof(label), "%T: %s", g_sFreedayKeys[option], client, value);
			menu.AddItem(info, label);
		}
	}
	for (int setting = 0; setting < sizeof(g_ConfigSettings); setting++)
	{
		if (g_ConfigSettings[setting].group != group) continue;
		ConVar cvar = FindConVar(g_ConfigSettings[setting].name);
		if (cvar == null) continue;
		IntToString(setting, info, sizeof(info));
		AJB_Config_FormatValue(client, setting, cvar.FloatValue, value, sizeof(value));
		Format(label, sizeof(label), "%T: %s", g_ConfigSettings[setting].name, client, value);
		menu.AddItem(info, label);
	}
	menu.ExitBackButton = true;
	menu.DisplayAt(client, position, MENU_TIME_FOREVER);
}

public int MenuHandler_ConfigGroup(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End) delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && AJB_Config_CanEdit(client))
	{
		char info[16];
		menu.GetItem(0, info, sizeof(info));
		bool wishes = StrContains(info, "fd:") != 0
			&& g_ConfigSettings[StringToInt(info)].group >= Config_WishGeneral;
		AJB_Config_ShowGroups(client, wishes);
	}
	else if (action == MenuAction_Select && AJB_Config_CanEdit(client))
	{
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		if (StrContains(info, "fd:") == 0)
		{
			AJB_Chat(client, AJB_Config_SaveFreeday(client, StringToInt(info[3])) ? "Config Saved" : "Config Save Failed");
			AJB_Config_ShowGroup(client, Config_Freeday);
		}
		else AJB_Config_ShowValue(client, StringToInt(info));
	}
	return 0;
}

void AJB_Config_ShowValue(int client, int setting)
{
	if (!AJB_Config_CanEdit(client) || !AJB_Config_GroupAvailable(g_ConfigSettings[setting].group)) return;
	ConVar cvar = FindConVar(g_ConfigSettings[setting].name);
	if (cvar == null) return;
	Menu menu = new Menu(MenuHandler_ConfigValue);
	char label[192], value[64], info[16];
	AJB_Config_FormatValue(client, setting, cvar.FloatValue, value, sizeof(value));
	Format(label, sizeof(label), "%T", g_ConfigSettings[setting].name, client);
	menu.SetTitle("%s: %s", label, value);
	float step = g_ConfigSettings[setting].step;
	for (int option = 0; option < 3; option++)
	{
		Format(info, sizeof(info), "%d:%d", setting, option);
		if (option == 2) Format(label, sizeof(label), "%T", "Config Default", client);
		else if (step < 0.0) AJB_Config_FormatValue(client, setting, float(option), label, sizeof(label));
		else if (step == 0.0) Format(label, sizeof(label), "%T", option == 0 ? "Config On" : "Config Off", client);
		else Format(label, sizeof(label), "%T (%.2f)", option == 0 ? "Config Increase" : "Config Decrease", client, step);
		menu.AddItem(info, label);
	}
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ConfigValue(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}
	if (action != MenuAction_Select && action != MenuAction_Cancel) return 0;
	if (!AJB_Config_CanEdit(client)) return 0;
	char info[16], parts[2][12];
	menu.GetItem(action == MenuAction_Select ? item : 0, info, sizeof(info));
	if (ExplodeString(info, ":", parts, sizeof(parts), sizeof(parts[])) != 2) return 0;
	int setting = StringToInt(parts[0]);
	AJBConfigGroup group = g_ConfigSettings[setting].group;
	if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
	{
		int position;
		for (int index = 0; index < setting; index++)
			if (g_ConfigSettings[index].group == group) position++;
		AJB_Config_ShowGroup(client, group, position / 7 * 7);
	}
	else if (action == MenuAction_Select && AJB_Config_GroupAvailable(group))
	{
		ConVar cvar = FindConVar(g_ConfigSettings[setting].name);
		if (cvar == null) return 0;
		int option = StringToInt(parts[1]);
		float value, step = g_ConfigSettings[setting].step;
		if (option == 2)
		{
			char defaultValue[32];
			cvar.GetDefault(defaultValue, sizeof(defaultValue));
			value = StringToFloat(defaultValue);
		}
		else if (step < 0.0) value = float(option);
		else if (step == 0.0) value = option == 0 ? 1.0 : 0.0;
		else value = cvar.FloatValue + (option == 0 ? step : -step);
		AJB_Chat(client, AJB_Config_SaveSetting(client, setting, value) ? "Config Saved" : "Config Save Failed");
		AJB_Config_ShowValue(client, setting);
	}
	return 0;
}

Action Command_ConfigMenu(int client, int args)
{
	if (AJB_Config_CanEdit(client)) AJB_Config_ShowGroups(client);
	return Plugin_Handled;
}

// =========================================================================================================
// Teleports: only change the selected destination, keeping door configuration intact
// =========================================================================================================

bool AJB_Config_SaveTeleport(int client, int destination, bool remove)
{
	if (!remove && !IsPlayerAlive(client))
	{
		AJB_Chat(client, "Teleport Alive Required");
		return false;
	}
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	AJB_GetShortMapName(map, sizeof(map));
	BuildPath(Path_SM, path, sizeof(path), "%s/%s.cfg", AJB_MAP_CONFIG_DIR, map);
	KeyValues kv = AJB_Config_Read(path, "AJB");
	if (kv == null) return false;
	kv.JumpToKey("teleports", true);
	if (remove) kv.DeleteKey(g_sTeleportKeys[destination]);
	else
	{
		float origin[3], angles[3];
		GetClientAbsOrigin(client, origin);
		GetClientEyeAngles(client, angles);
		kv.JumpToKey(g_sTeleportKeys[destination], true);
		kv.SetVector("origin", origin);
		kv.SetVector("angles", angles);
	}
	bool saved = AJB_Config_Write(kv, path);
	if (saved)
	{
		AJB_Settings_ClearTeleports();
		AJB_Settings_LoadTeleportsFromKv(kv);
		LogAction(client, -1, "\"%L\" %s teleport %s on %s", client, remove ? "removed" : "saved", g_sTeleportKeys[destination], map);
	}
	delete kv;
	return saved;
}

void AJB_Config_ShowTeleports(int client, int destination = -1)
{
	if (!AJB_Config_CanEdit(client, AJB_TELEPORT_COMMAND)) return;
	Menu menu = new Menu(MenuHandler_Teleports);
	char info[32], label[128], state[32];
	if (destination < 0)
	{
		char map[PLATFORM_MAX_PATH];
		AJB_GetShortMapName(map, sizeof(map));
		menu.SetTitle("%T\n%s", "Teleport Title", client, map);
		for (int index = 0; index < sizeof(g_sTeleportKeys); index++)
		{
			bool configured = index == 0 ? g_bTpFreeday : (index == 1 ? g_bTpCombatRed : g_bTpCombatBlu);
			Format(state, sizeof(state), "%T", configured ? "DB Configured" : "DB Missing", client);
			Format(label, sizeof(label), "%T: %s", g_sTeleportPhrases[index], client, state);
			Format(info, sizeof(info), "%d:%d:open", g_iConfigMapSerial, index);
			menu.AddItem(info, label);
		}
	}
	else
	{
		menu.SetTitle("%T", g_sTeleportPhrases[destination], client);
		Format(info, sizeof(info), "%d:%d:save", g_iConfigMapSerial, destination);
		Format(label, sizeof(label), "%T", "Teleport Save Here", client);
		menu.AddItem(info, label, IsPlayerAlive(client) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
		Format(info, sizeof(info), "%d:%d:remove", g_iConfigMapSerial, destination);
		Format(label, sizeof(label), "%T", "Teleport Remove", client);
		menu.AddItem(info, label);
	}
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Teleports(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}
	if (action != MenuAction_Select && action != MenuAction_Cancel) return 0;
	if (!AJB_Config_CanEdit(client, AJB_TELEPORT_COMMAND)) return 0;
	char info[32], parts[3][12];
	menu.GetItem(action == MenuAction_Select ? item : 0, info, sizeof(info));
	if (ExplodeString(info, ":", parts, sizeof(parts), sizeof(parts[])) != 3) return 0;
	if (StringToInt(parts[0]) != g_iConfigMapSerial) return 0;
	int destination = StringToInt(parts[1]);
	if (action == MenuAction_Cancel)
	{
		if (item == MenuCancel_ExitBack)
		{
			if (StrEqual(parts[2], "open")) FakeClientCommand(client, "sm_ajb");
			else AJB_Config_ShowTeleports(client);
		}
	}
	else if (StrEqual(parts[2], "open")) AJB_Config_ShowTeleports(client, destination);
	else
	{
		AJB_Chat(client, AJB_Config_SaveTeleport(client, destination, StrEqual(parts[2], "remove")) ? "Config Saved" : "Config Save Failed");
		AJB_Config_ShowTeleports(client, destination);
	}
	return 0;
}

Action Command_Teleports(int client, int args)
{
	if (AJB_Config_CanEdit(client, AJB_TELEPORT_COMMAND)) AJB_Config_ShowTeleports(client);
	return Plugin_Handled;
}

void AJB_ConfigMenu_OnPluginStart()
{
	LoadTranslations("ajb_admin.phrases");
	RegAdminCmd(AJB_CONFIG_COMMAND, Command_ConfigMenu, ADMFLAG_CONFIG, "Open persistent AJB settings.");
	RegAdminCmd(AJB_TELEPORT_COMMAND, Command_Teleports, ADMFLAG_CONFIG, "Configure per-map Freeday and combat teleports.");
	char directory[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, directory, sizeof(directory), AJB_CONFIG_DIR);
	if (!DirExists(directory) && !CreateDirectory(directory, 511)) LogError("[AJB] Could not create %s", directory);
	BuildPath(Path_SM, directory, sizeof(directory), AJB_MAP_CONFIG_DIR);
	if (!DirExists(directory) && !CreateDirectory(directory, 511)) LogError("[AJB] Could not create %s", directory);
}
