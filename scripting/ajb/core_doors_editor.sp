// =========================================================================================================
// In-game cell door selection and private TF2 tutorial annotations
// =========================================================================================================

#define AJB_DOOR_EDITOR_COMMAND "sm_ajb_doors_menu"
#define AJB_DOOR_ANNOTATION_BASE 2000000
#define AJB_DOOR_PREVIEW_INTERVAL 1.0
#define AJB_DOOR_PREVIEW_LIFETIME 1.5

bool g_bDoorEditorMarks[MAXPLAYERS + 1];
Handle g_hDoorEditorTimer[MAXPLAYERS + 1];
ArrayList g_hDoorEditorAnnotations[MAXPLAYERS + 1];
int g_iDoorEditorTarget[MAXPLAYERS + 1];

enum AJBDoorEditorPage
{
	DoorEditor_Main,
	DoorEditor_List,
	DoorEditor_Detail
};

// =========================================================================================================
// Selection and persistence
// =========================================================================================================

bool AJB_DoorEditor_IsCandidate(int ent)
{
	if (ent <= MaxClients || !IsValidEntity(ent)) return false;
	char classname[64];
	GetEntityClassname(ent, classname, sizeof(classname));
	return AJB_IsDoorLikeClass(classname);
}

void AJB_DoorEditor_Label(int ent, char[] buffer, int maxlen)
{
	char name[128];
	if (HasEntProp(ent, Prop_Data, "m_iName")) GetEntPropString(ent, Prop_Data, "m_iName", name, sizeof(name));
	if (name[0] == '\0') GetEntityClassname(ent, name, sizeof(name));
	int hammerId = HasEntProp(ent, Prop_Data, "m_iHammerID") ? GetEntProp(ent, Prop_Data, "m_iHammerID") : 0;
	Format(buffer, maxlen, "[%s] %s (#%d)", AJB_IsCellDoorEntity(ent) ? "X" : " ", name, hammerId);
}

bool AJB_DoorEditor_Save(int client, int ent, int state)
{
	if (!AJB_Config_CanEdit(client, AJB_DOOR_EDITOR_COMMAND) || !AJB_DoorEditor_IsCandidate(ent)) return false;
	char nameKey[AJB_MAX_DOOR_NAME_LEN + 16], hammerKey[32];
	AJB_DoorOverrideKeys(ent, nameKey, sizeof(nameKey), hammerKey, sizeof(hammerKey));
	if (nameKey[0] == '\0' && hammerKey[0] == '\0') return false;
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	AJB_GetShortMapName(map, sizeof(map));
	BuildPath(Path_SM, path, sizeof(path), "%s/%s.cfg", AJB_MAP_CONFIG_DIR, map);
	KeyValues kv = AJB_Config_Read(path, "AJB");
	if (kv == null) return false;
	// Legacy flat configs remain flat, so existing target selectors keep loading.
	kv.JumpToKey("doors");
	if (!kv.JumpToKey("overrides", true))
	{
		LogError("[AJB] Could not create door overrides in %s", path);
		delete kv;
		return false;
	}
	if (nameKey[0] != '\0') kv.DeleteKey(nameKey);
	if (hammerKey[0] != '\0') kv.DeleteKey(hammerKey);
	if (state >= 0) kv.SetNum(nameKey[0] != '\0' ? nameKey : hammerKey, state);
	bool saved = AJB_Config_Write(kv, path);
	delete kv;
	if (saved)
	{
		AJB_LoadMapDoors();
		LogAction(client, -1, "\"%L\" set door %s to %d on %s", client,
			nameKey[0] != '\0' ? nameKey : hammerKey, state, map);
	}
	return saved;
}

int AJB_DoorEditor_AimedEntity(int client)
{
	float eyes[3], angles[3];
	GetClientEyePosition(client, eyes);
	GetClientEyeAngles(client, angles);
	Handle trace = TR_TraceRayFilterEx(eyes, angles, MASK_SHOT, RayType_Infinite, TraceFilter_MarkerWorld, client);
	int ent = TR_DidHit(trace) ? TR_GetEntityIndex(trace) : -1;
	delete trace;
	return AJB_DoorEditor_IsCandidate(ent) ? ent : -1;
}

// =========================================================================================================
// Native markers, sent only to the editing administrator
// =========================================================================================================

void AJB_DoorEditor_StopPreview(int client, bool clearChoice = false)
{
	delete g_hDoorEditorTimer[client];
	g_hDoorEditorTimer[client] = null;
	if (g_hDoorEditorAnnotations[client] != null)
	{
		if (AJB_IsValidClient(client))
		{
			for (int i = 0; i < g_hDoorEditorAnnotations[client].Length; i++)
				AJB_Marker_HideAnnotation(g_hDoorEditorAnnotations[client].Get(i), client);
		}
		delete g_hDoorEditorAnnotations[client];
		g_hDoorEditorAnnotations[client] = null;
	}
	if (clearChoice) g_bDoorEditorMarks[client] = false;
}

void AJB_DoorEditor_StopAllPreviews()
{
	for (int client = 1; client <= MaxClients; client++) AJB_DoorEditor_StopPreview(client, true);
}

void AJB_DoorEditor_DrawPreview(int client)
{
	for (int c = 0; c < g_iDoorCacheCount; c++)
	{
		int ent = EntRefToEntIndex(g_iDoorCache[c]);
		if (!AJB_DoorEditor_IsCandidate(ent)) continue;
		if (g_iDoorEditorTarget[client] != INVALID_ENT_REFERENCE)
		{
			if (g_iDoorCache[c] != g_iDoorEditorTarget[client]) continue;
		}
		else if (!AJB_IsCellDoorEntity(ent)) continue;
		Event event = CreateEvent("show_annotation", true);
		if (event == null)
		{
			LogError("[AJB] Could not create door annotation event.");
			return;
		}
		float center[3];
		char label[192];
		AJB_GetEntityWorldCenter(ent, center);
		AJB_DoorEditor_Label(ent, label, sizeof(label));
		int id = AJB_DOOR_ANNOTATION_BASE + ent;
		event.SetInt("id", id);
		event.SetString("text", label);
		event.SetFloat("worldPosX", center[0]);
		event.SetFloat("worldPosY", center[1]);
		event.SetFloat("worldPosZ", center[2]);
		event.SetFloat("lifetime", AJB_DOOR_PREVIEW_LIFETIME);
		event.SetInt("visibilityBitfield", 0);
		event.SetString("play_sound", "");
		event.SetBool("show_distance", true);
		event.FireToClient(client);
		event.Cancel();
		if (g_hDoorEditorAnnotations[client].FindValue(id) == -1) g_hDoorEditorAnnotations[client].Push(id);
	}
}

Action Timer_DoorEditorPreview(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!AJB_Config_CanEdit(client, AJB_DOOR_EDITOR_COMMAND))
	{
		if (client > 0)
		{
			g_hDoorEditorTimer[client] = null;
			AJB_DoorEditor_StopPreview(client, true);
		}
		return Plugin_Stop;
	}
	AJB_DoorEditor_DrawPreview(client);
	return Plugin_Continue;
}

// =========================================================================================================
// One menu handler retains the map serial and entity reference in every item
// =========================================================================================================

void AJB_DoorEditor_AddItem(Menu menu, int client, AJBDoorEditorPage page, int ref,
	const char[] action, const char[] phrase, int style = ITEMDRAW_DEFAULT)
{
	char info[80], label[128];
	Format(info, sizeof(info), "%d:%d:%d:%s", g_iConfigMapSerial, page, ref, action);
	Format(label, sizeof(label), "%T", phrase, client);
	menu.AddItem(info, label, style);
}

void AJB_DoorEditor_Show(int client, AJBDoorEditorPage page = DoorEditor_Main, int ref = INVALID_ENT_REFERENCE)
{
	if (!AJB_Config_CanEdit(client, AJB_DOOR_EDITOR_COMMAND)) return;
	int ent = EntRefToEntIndex(ref);
	if (page == DoorEditor_Detail && !AJB_DoorEditor_IsCandidate(ent))
	{
		AJB_Chat(client, "Door Editor Missing");
		page = DoorEditor_Main;
		ref = INVALID_ENT_REFERENCE;
	}
	Menu menu = new Menu(MenuHandler_DoorEditor, MENU_ACTIONS_DEFAULT | MenuAction_Display);
	int position;
	if (page == DoorEditor_Main)
	{
		menu.SetTitle("%T", "Admin Cat Doors", client);
		AJB_DoorEditor_AddItem(menu, client, page, ref, "aim", "Door Editor Aim");
		AJB_DoorEditor_AddItem(menu, client, page, ref, "list", "Door Editor List");
		AJB_DoorEditor_AddItem(menu, client, page, ref, "marks", g_bDoorEditorMarks[client] ? "Door Editor Hide" : "Door Editor Mark");
		AJB_DoorEditor_AddItem(menu, client, page, ref, "reload", "Admin Menu Reload Doors");
		AJB_DoorEditor_AddItem(menu, client, page, ref, "print", "Admin Menu List Doors");
	}
	else if (page == DoorEditor_List)
	{
		menu.SetTitle("%T", "Door Editor List", client);
		for (int c = 0; c < g_iDoorCacheCount; c++)
		{
			int candidate = EntRefToEntIndex(g_iDoorCache[c]);
			if (!AJB_DoorEditor_IsCandidate(candidate)) continue;
			char info[80], label[192];
			Format(info, sizeof(info), "%d:%d:%d:select", g_iConfigMapSerial, page, g_iDoorCache[c]);
			AJB_DoorEditor_Label(candidate, label, sizeof(label));
			if (g_iDoorCache[c] == ref) position = menu.ItemCount;
			menu.AddItem(info, label);
		}
		if (menu.ItemCount == 0) AJB_DoorEditor_AddItem(menu, client, page, ref, "none", "Door Editor Empty", ITEMDRAW_DISABLED);
	}
	else
	{
		char label[192], nameKey[AJB_MAX_DOOR_NAME_LEN + 16], hammerKey[32];
		AJB_DoorEditor_Label(ent, label, sizeof(label));
		AJB_DoorOverrideKeys(ent, nameKey, sizeof(nameKey), hammerKey, sizeof(hammerKey));
		menu.SetTitle("%s", label);
		int style = nameKey[0] != '\0' || hammerKey[0] != '\0' ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED;
		AJB_DoorEditor_AddItem(menu, client, page, ref, "enable", "Door Editor Include", style);
		AJB_DoorEditor_AddItem(menu, client, page, ref, "disable", "Door Editor Exclude", style);
		AJB_DoorEditor_AddItem(menu, client, page, ref, "auto", "Door Editor Automatic", style);
		AJB_DoorEditor_AddItem(menu, client, page, ref, "marks", g_bDoorEditorMarks[client] ? "Door Editor Hide" : "Door Editor Mark");
	}
	menu.ExitBackButton = true;
	menu.DisplayAt(client, position / 7 * 7, MENU_TIME_FOREVER);
}

public int MenuHandler_DoorEditor(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}
	if (action != MenuAction_Select && action != MenuAction_Cancel && action != MenuAction_Display) return 0;
	if (action != MenuAction_Display) AJB_DoorEditor_StopPreview(client);
	if (!AJB_Config_CanEdit(client, AJB_DOOR_EDITOR_COMMAND)) return 0;
	char info[80], parts[4][20];
	menu.GetItem(action == MenuAction_Select ? item : 0, info, sizeof(info));
	if (ExplodeString(info, ":", parts, sizeof(parts), sizeof(parts[])) != 4) return 0;
	if (StringToInt(parts[0]) != g_iConfigMapSerial) return 0;
	AJBDoorEditorPage page = view_as<AJBDoorEditorPage>(StringToInt(parts[1]));
	int ref = StringToInt(parts[2]);
	if (action == MenuAction_Display)
	{
		AJB_DoorEditor_StopPreview(client);
		g_iDoorEditorTarget[client] = page == DoorEditor_Detail ? ref : INVALID_ENT_REFERENCE;
		if (g_bDoorEditorMarks[client])
		{
			g_hDoorEditorAnnotations[client] = new ArrayList();
			AJB_DoorEditor_DrawPreview(client);
			g_hDoorEditorTimer[client] = CreateTimer(AJB_DOOR_PREVIEW_INTERVAL, Timer_DoorEditorPreview,
				GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		}
		return 0;
	}
	if (action == MenuAction_Cancel)
	{
		if (item == MenuCancel_ExitBack)
		{
			if (page == DoorEditor_Main)
			{
				g_bDoorEditorMarks[client] = false;
				FakeClientCommand(client, "sm_ajb");
			}
			else AJB_DoorEditor_Show(client, page == DoorEditor_Detail ? DoorEditor_List : DoorEditor_Main, ref);
		}
		else g_bDoorEditorMarks[client] = false;
		return 0;
	}
	if (StrEqual(parts[3], "aim"))
	{
		int ent = AJB_DoorEditor_AimedEntity(client);
		if (ent != -1) AJB_DoorEditor_Show(client, DoorEditor_Detail, EntIndexToEntRef(ent));
		else
		{
			AJB_Chat(client, "Door Editor No Aim");
			AJB_DoorEditor_Show(client);
		}
	}
	else if (StrEqual(parts[3], "list")) AJB_DoorEditor_Show(client, DoorEditor_List);
	else if (StrEqual(parts[3], "select")) AJB_DoorEditor_Show(client, DoorEditor_Detail, ref);
	else
	{
		if (StrEqual(parts[3], "marks")) g_bDoorEditorMarks[client] = !g_bDoorEditorMarks[client];
		else if (StrEqual(parts[3], "reload")) AJB_LoadMapDoors();
		else if (StrEqual(parts[3], "print")) FakeClientCommand(client, "sm_ajb_doors_list");
		else if (page == DoorEditor_Detail)
		{
			int state = StrEqual(parts[3], "auto") ? -1 : (StrEqual(parts[3], "enable") ? 1 : 0);
			AJB_Chat(client, AJB_DoorEditor_Save(client, EntRefToEntIndex(ref), state) ? "Config Saved" : "Config Save Failed");
		}
		AJB_DoorEditor_Show(client, page, ref);
	}
	return 0;
}

Action Command_DoorEditor(int client, int args)
{
	if (AJB_Config_CanEdit(client, AJB_DOOR_EDITOR_COMMAND))
	{
		AJB_DoorEditor_StopPreview(client, true);
		AJB_LoadMapDoors();
		AJB_DoorEditor_Show(client);
	}
	return Plugin_Handled;
}

void AJB_DoorEditor_OnPluginStart()
{
	RegAdminCmd(AJB_DOOR_EDITOR_COMMAND, Command_DoorEditor, ADMFLAG_CONFIG, "Configure cell doors and private tutorial markers.");
}
