// =========================================================================================================
// Last Request - Set All Class
// =========================================================================================================

// =========================================================================================================
// Set All Class
// =========================================================================================================

void AJB_LR_StartSetAllClassConfig(int prisoner)
{
	g_DraftSetAllClassTarget = SetAllClass_All;
	g_DraftSetAllClassType = TFClass_Scout;
	g_bMenuOpen = true;
	AJB_LR_ShowSetAllClassMenu(prisoner);
	AJB_LR_StartMenuTimers(prisoner);
}

void AJB_LR_ShowSetAllClassMenu(int prisoner)
{
	if (prisoner < 1 || !IsClientInGame(prisoner))
	{
		return;
	}

	Menu menu = new Menu(MenuHandler_SetAllClass);
	char title[64];
	char line[96];
	char targetLabel[32];
	char classLabel[32];

	AJB_LR_SetAllClassTargetLabel(prisoner, g_DraftSetAllClassTarget, targetLabel, sizeof(targetLabel));
	AJB_LR_ClassName(g_DraftSetAllClassType, classLabel, sizeof(classLabel));

	Format(title, sizeof(title), "%T", "LR SetAllClass Menu Title", prisoner);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", "LR SetAllClass Opt Target", prisoner, targetLabel);
	menu.AddItem("target", line);

	Format(line, sizeof(line), "%T", "LR SetAllClass Opt Class", prisoner, classLabel);
	menu.AddItem("class", line);

	Format(line, sizeof(line), "%T", "LR SetAllClass Opt Confirm", prisoner);
	menu.AddItem("confirm", line);

	Format(line, sizeof(line), "%T", "LR SetAllClass Opt Back", prisoner);
	menu.AddItem("back", line);

	menu.ExitButton = false;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));
}

void AJB_LR_SetAllClassTargetLabel(int client, AJB_SetAllClassTarget target, char[] buffer, int maxlen)
{
	switch (target)
	{
		case SetAllClass_All:     Format(buffer, maxlen, "%T", "LR SetAllClass Target All", client);
		case SetAllClass_RedOnly: Format(buffer, maxlen, "%T", "LR SetAllClass Target Red", client);
		case SetAllClass_BluOnly: Format(buffer, maxlen, "%T", "LR SetAllClass Target Blu", client);
	}
}

public int MenuHandler_SetAllClass(Menu menu, MenuAction action, int param1, int param2)
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
	if (!AJB_LR_IsMenuAllowed(client))
	{
		return 0;
	}

	char info[16];
	menu.GetItem(param2, info, sizeof(info));

	if (StrEqual(info, "target"))
	{
		AJB_LR_ShowSetAllClassTargetMenu(client);
		return 0;
	}

	if (StrEqual(info, "class"))
	{
		AJB_LR_ShowSetAllClassTypeMenu(client);
		return 0;
	}

	if (StrEqual(info, "back"))
	{
		AJB_LR_ShowWishMenu(client);
		return 0;
	}

	if (StrEqual(info, "confirm"))
	{
		AJB_LR_KillMenuTimer();
		g_bMenuOpen = false;

		AJB_LR_ClearPendingWish();
		g_PendingWish = LRWish_SetAllClass;
		g_PendingSetAllClassTarget = g_DraftSetAllClassTarget;
		g_PendingSetAllClassType = g_DraftSetAllClassType;
		AJB_LR_RememberChooser(client);
		AJB_LR_ChatAllSetAllClassChose(client, g_DraftSetAllClassTarget, g_DraftSetAllClassType);
		AJB_LR_CloseMenuState();
		AJB_LR_MarkWishChosen();
	}

	return 0;
}

void AJB_LR_ShowSetAllClassTargetMenu(int prisoner)
{
	Menu menu = new Menu(MenuHandler_SetAllClassTarget);
	char title[64];
	char line[64];
	Format(title, sizeof(title), "%T", "LR SetAllClass Target Title", prisoner);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", "LR SetAllClass Target All", prisoner);
	menu.AddItem("0", line);
	Format(line, sizeof(line), "%T", "LR SetAllClass Target Red", prisoner);
	menu.AddItem("1", line);
	Format(line, sizeof(line), "%T", "LR SetAllClass Target Blu", prisoner);
	menu.AddItem("2", line);

	menu.ExitButton = false;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));
}

public int MenuHandler_SetAllClassTarget(Menu menu, MenuAction action, int param1, int param2)
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
	if (!AJB_LR_IsMenuAllowed(client))
	{
		return 0;
	}

	char info[16];
	menu.GetItem(param2, info, sizeof(info));
	g_DraftSetAllClassTarget = view_as<AJB_SetAllClassTarget>(StringToInt(info));

	AJB_LR_ShowSetAllClassMenu(client);
	return 0;
}

void AJB_LR_ShowSetAllClassTypeMenu(int prisoner)
{
	Menu menu = new Menu(MenuHandler_SetAllClassType);
	char title[64];
	char line[64];
	Format(title, sizeof(title), "%T", "LR SetAllClass Class Title", prisoner);
	menu.SetTitle(title);

	static const TFClassType kClasses[] = {
		TFClass_Scout, TFClass_Soldier, TFClass_Pyro, TFClass_DemoMan,
		TFClass_Heavy, TFClass_Engineer, TFClass_Medic, TFClass_Sniper, TFClass_Spy
	};

	for (int i = 0; i < sizeof(kClasses); i++)
	{
		char info[8];
		IntToString(view_as<int>(kClasses[i]), info, sizeof(info));
		AJB_LR_ClassName(kClasses[i], line, sizeof(line));
		menu.AddItem(info, line);
	}

	menu.ExitButton = false;
	menu.Display(prisoner, RoundToFloor(g_cvMenuTime.FloatValue));
}

public int MenuHandler_SetAllClassType(Menu menu, MenuAction action, int param1, int param2)
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
	if (!AJB_LR_IsMenuAllowed(client))
	{
		return 0;
	}

	char info[16];
	menu.GetItem(param2, info, sizeof(info));
	g_DraftSetAllClassType = view_as<TFClassType>(StringToInt(info));

	AJB_LR_ShowSetAllClassMenu(client);
	return 0;
}

void AJB_LR_ApplySetAllClass(const char[] chooserName, AJB_SetAllClassTarget target, TFClassType cls)
{
	g_bSetAllClassActive = true;
	g_SetAllClassTarget = target;
	g_SetAllClassType = cls;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		if (AJB_LR_IsSetAllClassTarget(i, target))
		{
			TF2_SetPlayerClass(i, cls, false, true);
			TF2_RegeneratePlayer(i);
		}
	}

	AJB_LR_ChatAllSetAllClassApplied(chooserName, target, cls);
}

bool AJB_LR_IsSetAllClassTarget(int client, AJB_SetAllClassTarget target)
{
	if (!g_bHasCore)
	{
		return false;
	}

	switch (target)
	{
		case SetAllClass_All:     return AJB_IsPrisoner(client) || AJB_IsGuard(client);
		case SetAllClass_RedOnly: return AJB_IsPrisoner(client);
		case SetAllClass_BluOnly: return AJB_IsGuard(client);
	}
	return false;
}

void AJB_LR_ForceSetAllClass(int client)
{
	if (!g_bSetAllClassActive || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	if (!AJB_LR_IsSetAllClassTarget(client, g_SetAllClassTarget))
	{
		return;
	}

	if (TF2_GetPlayerClass(client) == g_SetAllClassType)
	{
		return;
	}

	TF2_SetPlayerClass(client, g_SetAllClassType, false, true);
	TF2_RegeneratePlayer(client);
}

void AJB_LR_ChatAllSetAllClassChose(int chooser, AJB_SetAllClassTarget target, TFClassType cls)
{
	char className[32];
	AJB_LR_ClassName(cls, className, sizeof(className));

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		char targetLabel[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		AJB_LR_SetAllClassTargetLabel(i, target, targetLabel, sizeof(targetLabel));

		CPrintToChat(i, "%T", "LR Chose SetAllClass", i, prefix, chooser, targetLabel, className);
	}
}

void AJB_LR_ChatAllSetAllClassApplied(const char[] chooserName, AJB_SetAllClassTarget target, TFClassType cls)
{
	char className[32];
	AJB_LR_ClassName(cls, className, sizeof(className));

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		char targetLabel[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		AJB_LR_SetAllClassTargetLabel(i, target, targetLabel, sizeof(targetLabel));

		CPrintToChat(i, "%T", "LR Applied SetAllClass", i, prefix, chooserName[0] != '\0' ? chooserName : "LR", targetLabel, className);
	}
}

