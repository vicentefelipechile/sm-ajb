// =========================================================================================================
// Last Request - Dodgeball visual map editor (private, non-interactive spawn markers)
// =========================================================================================================

#define DB_ROCKET_CLEARANCE 8.0
#define DB_CEILING_OFFSET   24.0
#define DB_CEILING_DISTANCE 16384.0
#define DB_MARKER_HEIGHT   72.0

Handle g_hDBPreviewTimer[MAXPLAYERS + 1];
Handle g_hDBPreviewHud;
int g_iDBEditorPage[MAXPLAYERS + 1];

// =========================================================================================================
// Placement validation
// =========================================================================================================

bool AJB_LR_DB_RocketSpaceClear(const float origin[3])
{
	float position[3];
	position = origin;
	if (TR_PointOutsideWorld(position)) return false;
	float mins[3], maxs[3];
	for (int axis = 0; axis < 3; axis++)
	{
		mins[axis] = -DB_ROCKET_CLEARANCE;
		maxs[axis] = DB_ROCKET_CLEARANCE;
	}
	Handle trace = TR_TraceHullFilterEx(position, position, mins, maxs, MASK_SHOT_HULL, DB_TraceFilter_NoPlayers, -1);
	bool clear = !TR_StartSolid(trace) && !TR_AllSolid(trace) && !TR_DidHit(trace);
	delete trace;
	return clear;
}

bool AJB_LR_DB_FindCeiling(int client, float origin[3])
{
	float eyes[3], end[3], mins[3], maxs[3];
	GetClientEyePosition(client, eyes);
	end = eyes;
	end[2] += DB_CEILING_DISTANCE;
	for (int axis = 0; axis < 3; axis++)
	{
		mins[axis] = -DB_ROCKET_CLEARANCE;
		maxs[axis] = DB_ROCKET_CLEARANCE;
	}
	// Sweep a volume, not a sight ray: include grates, glass, props and moving brushes.
	Handle trace = TR_TraceHullFilterEx(eyes, end, mins, maxs, MASK_SHOT_HULL, DB_TraceFilter_NoPlayers, -1);
	bool found = TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
	if (found)
	{
		TR_GetEndPosition(origin, trace);
		origin[2] -= DB_CEILING_OFFSET;
	}
	delete trace;
	return found && origin[2] > eyes[2] && AJB_LR_DB_RocketSpaceClear(origin);
}

bool AJB_LR_DB_CanEdit(int client)
{
	return client > 0 && IsClientInGame(client)
		&& CheckCommandAccess(client, "sm_ajb", ADMFLAG_GENERIC)
		&& CheckCommandAccess(client, "sm_ajb_db_menu", ADMFLAG_CONFIG)
		&& CheckCommandAccess(client, "sm_ajb_db_setspawn", ADMFLAG_CONFIG);
}

// =========================================================================================================
// Private preview (the same arena geometry used by the wish)
// =========================================================================================================

void AJB_LR_DB_StopPreview(int client)
{
	delete g_hDBPreviewTimer[client];
	g_hDBPreviewTimer[client] = null;
	if (g_hDBPreviewHud != null && IsClientInGame(client)) ClearSyncHud(client, g_hDBPreviewHud);
}

void AJB_LR_DB_StopAllPreviews()
{
	for (int client = 1; client <= MaxClients; client++) AJB_LR_DB_StopPreview(client);
	delete g_hDBPreviewHud;
	g_hDBPreviewHud = null;
}

void AJB_LR_DB_DrawMarker(int client, const float origin[3], int color[4], float height)
{
	float bottom[3], top[3];
	bottom = origin;
	bottom[2] += 2.0;
	top = bottom;
	top[2] += height;
	TE_SetupBeamRingPoint(bottom, 30.0, 32.0, g_iDBBeam, g_iDBHalo, 0, 0,
		DB_ZONE_RING_LIFE, 3.0, 0.0, color, 0, 0);
	TE_SendToClient(client);
	TE_SetupBeamPoints(bottom, top, g_iDBBeam, g_iDBHalo, 0, 0,
		DB_ZONE_RING_LIFE, 3.0, 3.0, 0, 0.0, color, 0);
	TE_SendToClient(client);
}

void AJB_LR_DB_DrawPreview(int client)
{
	if (g_iDBBeam <= 0) return;
	int red[4] = {255, 50, 50, 255};
	int blu[4] = {60, 140, 255, 255};
	int rocket[4] = {255, 255, 80, 255};
	int center[4] = {80, 255, 100, 255};
	if (g_bDBRedSet) AJB_LR_DB_DrawMarker(client, g_vecDBRedSpawn, red, DB_MARKER_HEIGHT);
	if (g_bDBBluSet) AJB_LR_DB_DrawMarker(client, g_vecDBBluSpawn, blu, DB_MARKER_HEIGHT);
	if (g_bDBRocketSet) AJB_LR_DB_DrawMarker(client, g_vecDBRocketSpawn, rocket, 16.0);
	if (g_bDBCenterSet || g_bDBRocketSet) AJB_LR_DB_DrawMarker(client, g_vecDBArenaCenter, center, 16.0);
	if (!g_bDodgeball) AJB_LR_DB_DrawZone(client);
	SetHudTextParams(0.02, 0.65, DB_ZONE_RING_LIFE, 255, 255, 255, 255);
	ShowSyncHudText(client, g_hDBPreviewHud, "%T", "DB Preview Legend", client);
}

Action Timer_DBEditorPreview(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!AJB_LR_DB_CanEdit(client))
	{
		if (client > 0)
		{
			g_hDBPreviewTimer[client] = null;
			if (g_hDBPreviewHud != null) ClearSyncHud(client, g_hDBPreviewHud);
		}
		return Plugin_Stop;
	}
	AJB_LR_DB_DrawPreview(client);
	return Plugin_Continue;
}

// =========================================================================================================
// Menu: walk to a point, press a button, see the saved result immediately
// =========================================================================================================

public Action Cmd_DBEditor(int client, int args)
{
	if (AJB_LR_DB_CanEdit(client)) AJB_LR_DB_ShowEditor(client);
	else ReplyToCommand(client, "In-game administrators with config access only.");
	return Plugin_Handled;
}

void AJB_LR_DB_ShowEditor(int client, int page = 0)
{
	if (!AJB_LR_DB_CanEdit(client)) return;
	g_iDBEditorPage[client] = page;
	Menu menu = new Menu(MenuHandler_DBEditor, MENU_ACTIONS_DEFAULT | MenuAction_Display);
	char line[256];
	int style = g_bDodgeball ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;
	if (page == 0)
	{
		char red[32], blu[32], rocket[32];
		Format(red, sizeof(red), "%T", g_bDBRedSet ? "DB Configured" : "DB Missing", client);
		Format(blu, sizeof(blu), "%T", g_bDBBluSet ? "DB Configured" : "DB Missing", client);
		Format(rocket, sizeof(rocket), "%T", g_bDBRocketSet ? "DB Configured" : "DB Missing", client);
		menu.SetTitle("%T", "DB Editor Title", client, red, blu, rocket);
		Format(line, sizeof(line), "%T", "DB Set Red", client);
		menu.AddItem("red", line, style);
		Format(line, sizeof(line), "%T", "DB Set Blu", client);
		menu.AddItem("blu", line, style);
		Format(line, sizeof(line), "%T", "DB Set Rocket", client);
		menu.AddItem("rocket", line, style);
		Format(line, sizeof(line), "%T", "DB Arena", client);
		menu.AddItem("arena", line);
	}
	else if (page == 1)
	{
		menu.SetTitle("%T", "DB Rocket Title", client);
		Format(line, sizeof(line), "%T", "DB Rocket Ceiling", client);
		menu.AddItem("ceiling", line, style);
		Format(line, sizeof(line), "%T", "DB Rocket Eyes", client);
		menu.AddItem("eyes", line, style);
	}
	else
	{
		if (g_fDBArenaRadius <= 1.0) Format(line, sizeof(line), "%T", "DB No Barriers", client);
		else Format(line, sizeof(line), "%T", "DB Radius", client, g_fDBArenaRadius);
		menu.SetTitle("%T\n%s", "DB Arena", client, line);
		Format(line, sizeof(line), "%T", "DB Set Center", client);
		menu.AddItem("center", line, style);
		Format(line, sizeof(line), "%T", "DB Increase", client);
		menu.AddItem("increase", line, g_fDBArenaRadius >= DB_RADIUS_MAX ? ITEMDRAW_DISABLED : style);
		Format(line, sizeof(line), "%T", "DB Decrease", client);
		menu.AddItem("decrease", line, g_fDBArenaRadius <= DB_RADIUS_MIN ? ITEMDRAW_DISABLED : style);
		Format(line, sizeof(line), "%T", "DB No Barriers", client);
		menu.AddItem("unlimited", line, style);
	}
	if (g_bDodgeball)
	{
		Format(line, sizeof(line), "%T", "DB Read Only", client);
		menu.AddItem("", line, ITEMDRAW_DISABLED);
	}
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_DBEditor(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}
	if (action == MenuAction_Display)
	{
		AJB_LR_DB_StopPreview(client);
		if (g_hDBPreviewHud == null) g_hDBPreviewHud = CreateHudSynchronizer();
		AJB_LR_DB_DrawPreview(client);
		g_hDBPreviewTimer[client] = CreateTimer(DB_ZONE_REDRAW, Timer_DBEditorPreview,
			GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		return 0;
	}
	if (action != MenuAction_Select && action != MenuAction_Cancel) return 0;
	AJB_LR_DB_StopPreview(client);
	if (!AJB_LR_DB_CanEdit(client)) return 0;
	if (action == MenuAction_Cancel)
	{
		if (item == MenuCancel_ExitBack)
		{
			if (g_iDBEditorPage[client] != 0) AJB_LR_DB_ShowEditor(client);
			else FakeClientCommand(client, "sm_ajb");
		}
		return 0;
	}

	char key[16];
	menu.GetItem(item, key, sizeof(key));
	if (StrEqual(key, "rocket")) AJB_LR_DB_ShowEditor(client, 1);
	else if (StrEqual(key, "arena")) AJB_LR_DB_ShowEditor(client, 2);
	else
	{
		float origin[3];
		if (StrEqual(key, "increase") || StrEqual(key, "decrease") || StrEqual(key, "unlimited"))
		{
			float radius = StrEqual(key, "unlimited") ? 0.0 : AJB_DB_AdjustRadius(g_fDBArenaRadius, StrEqual(key, "increase"));
			AJB_LR_DB_SavePoint(client, "radius", g_vecDBArenaCenter, radius);
		}
		else if (!IsPlayerAlive(client)) AJB_Chat(client, "DB Alive Required");
		else if (StrEqual(key, "ceiling"))
		{
			if (AJB_LR_DB_FindCeiling(client, origin)) AJB_LR_DB_SavePoint(client, "rocket", origin);
			else AJB_Chat(client, "DB No Ceiling");
		}
		else if (StrEqual(key, "eyes"))
		{
			GetClientEyePosition(client, origin);
			AJB_LR_DB_SavePoint(client, "rocket", origin);
		}
		else if (StrEqual(key, "red") || StrEqual(key, "blu") || StrEqual(key, "center"))
		{
			GetClientAbsOrigin(client, origin);
			AJB_LR_DB_SavePoint(client, key, origin);
		}
		AJB_LR_DB_ShowEditor(client, g_iDBEditorPage[client]);
	}
	return 0;
}
