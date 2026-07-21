// =========================================================================================================
// Mode enable / map prefix detection
// =========================================================================================================

void AJB_RefreshModeActive()
{
	if (g_cvEnabled == null || !g_cvEnabled.BoolValue)
	{
		g_bModeActive = false;
		return;
	}

	if (g_cvForce != null && g_cvForce.BoolValue)
	{
		g_bModeActive = true;
		return;
	}

	char prefix[AJB_MAX_MAP_PREFIX_LEN];
	g_cvMapPrefix.GetString(prefix, sizeof(prefix));
	if (prefix[0] == '\0')
	{
		g_bModeActive = false;
		return;
	}

	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));

	g_bModeActive = (StrContains(map, prefix, false) == 0);
}

int AJB_GetGuardsTeam()
{
	return g_cvGuardsTeam.IntValue;
}

int AJB_GetPrisonersTeam()
{
	return g_cvPrisonersTeam.IntValue;
}
