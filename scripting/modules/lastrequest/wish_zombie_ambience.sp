// =========================================================================================================
// Zombie Mode - temporary fog and optional music
// =========================================================================================================

#define LR_ZM_FOG_COLOR "22 48 18"
#define LR_ZM_MUSIC_VOLUME 0.45

ConVar g_cvZMFogEnabled;
ConVar g_cvZMFogColor;
ConVar g_cvZMFogStart;
ConVar g_cvZMFogEnd;
ConVar g_cvZMFogDensity;
ConVar g_cvZMMusic;

int g_iZMFogRef = INVALID_ENT_REFERENCE;
int g_iZMOldFog[MAXPLAYERS + 1];
bool g_bZMFogSaved[MAXPLAYERS + 1];
bool g_bZMMusicHeard[MAXPLAYERS + 1];
char g_sZMMusic[PLATFORM_MAX_PATH];

void AJB_LR_ZM_InitAmbience()
{
	g_cvZMFogEnabled = CreateConVar("sm_ajb_lr_zm_fog_enabled", "1", "Zombie Mode: enable temporary fog.", _, true, 0.0, true, 1.0);
	g_cvZMFogColor = CreateConVar("sm_ajb_lr_zm_fog_color", LR_ZM_FOG_COLOR, "Zombie Mode: fog RGB color, three integers from 0 to 255.");
	g_cvZMFogStart = CreateConVar("sm_ajb_lr_zm_fog_start", "48", "Zombie Mode: fog start distance in units.", _, true, 0.0);
	g_cvZMFogEnd = CreateConVar("sm_ajb_lr_zm_fog_end", "1300", "Zombie Mode: fog end distance in units, must exceed fog_start.", _, true, 1.0);
	g_cvZMFogDensity = CreateConVar("sm_ajb_lr_zm_fog_density", "0.88", "Zombie Mode: maximum fog density.", _, true, 0.0, true, 1.0);
	g_cvZMMusic = CreateConVar("sm_ajb_lr_zm_music", "", "Zombie Mode: MP3/WAV path relative to sound/, empty = no music. Custom files need FastDL and reconnect/map change.");

	g_cvZMFogEnabled.AddChangeHook(OnZMFogChanged);
	g_cvZMFogColor.AddChangeHook(OnZMFogChanged);
	g_cvZMFogStart.AddChangeHook(OnZMFogChanged);
	g_cvZMFogEnd.AddChangeHook(OnZMFogChanged);
	g_cvZMFogDensity.AddChangeHook(OnZMFogChanged);
	g_cvZMMusic.AddChangeHook(OnZMMusicChanged);
}

void AJB_LR_ZM_PrepareMusic()
{
	AJB_LR_ZM_StopMusic();
	g_sZMMusic[0] = '\0';
	char path[PLATFORM_MAX_PATH];
	g_cvZMMusic.GetString(path, sizeof(path));
	TrimString(path);
	ReplaceString(path, sizeof(path), "\\", "/");
	if (path[0] == '\0')
	{
		return;
	}

	int extension = FindCharInString(path, '.', true);
	if (path[0] == '/' || StrContains(path, ":") != -1 || StrContains(path, "..") != -1
		|| extension == -1 || (!StrEqual(path[extension], ".mp3", false) && !StrEqual(path[extension], ".wav", false)))
	{
		LogError("[AJB-LR] Invalid Zombie Mode music path: %s. Use an MP3/WAV path relative to sound/.", path);
		return;
	}

	char download[PLATFORM_MAX_PATH];
	Format(download, sizeof(download), "sound/%s", path);
	if (!FileExists(download, true))
	{
		LogError("[AJB-LR] Zombie Mode music file not found: %s.", download);
		return;
	}

	char sample[PLATFORM_MAX_PATH];
	Format(sample, sizeof(sample), "#%s", path);
	if (!PrecacheSound(sample, true))
	{
		LogError("[AJB-LR] Could not precache Zombie Mode music: %s.", path);
		return;
	}
	AddFileToDownloadsTable(download);
	strcopy(g_sZMMusic, sizeof(g_sZMMusic), sample);
	for (int i = 1; i <= MaxClients; i++)
	{
		AJB_LR_ZM_ApplyAmbience(i);
	}
}

void AJB_LR_ZM_ResetAmbienceClient(int client)
{
	g_bZMFogSaved[client] = false;
	g_iZMOldFog[client] = INVALID_ENT_REFERENCE;
	g_bZMMusicHeard[client] = false;
}

void AJB_LR_ZM_StopMusic()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bZMMusicHeard[i] && g_sZMMusic[0] != '\0' && IsClientInGame(i))
		{
			StopSound(i, SNDCHAN_STATIC, g_sZMMusic);
		}
		g_bZMMusicHeard[i] = false;
	}
}

void AJB_LR_ZM_ApplyAmbience(int client)
{
	if (!g_bZombieMode || g_bZMEnding || !IsClientInGame(client) || IsFakeClient(client))
	{
		return;
	}

	int fog = EntRefToEntIndex(g_iZMFogRef);
	if (fog != INVALID_ENT_REFERENCE && HasEntProp(client, Prop_Send, "m_PlayerFog.m_hCtrl"))
	{
		if (!g_bZMFogSaved[client])
		{
			int old = GetEntPropEnt(client, Prop_Send, "m_PlayerFog.m_hCtrl");
			g_iZMOldFog[client] = old > MaxClients && old != fog ? EntIndexToEntRef(old) : INVALID_ENT_REFERENCE;
			g_bZMFogSaved[client] = true;
		}
		SetEntPropEnt(client, Prop_Send, "m_PlayerFog.m_hCtrl", fog);
	}

	if (g_sZMMusic[0] != '\0' && !g_bZMMusicHeard[client])
	{
		EmitSoundToClient(client, g_sZMMusic, SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, SND_NOFLAGS, LR_ZM_MUSIC_VOLUME);
		g_bZMMusicHeard[client] = true;
	}
}

void Frame_ZMAmbience(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0)
	{
		AJB_LR_ZM_ApplyAmbience(client);
	}
}

void AJB_LR_ZM_StopFog()
{
	int fog = EntRefToEntIndex(g_iZMFogRef);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bZMFogSaved[i] && IsClientInGame(i) && HasEntProp(i, Prop_Send, "m_PlayerFog.m_hCtrl")
			&& GetEntPropEnt(i, Prop_Send, "m_PlayerFog.m_hCtrl") == fog)
		{
			int old = EntRefToEntIndex(g_iZMOldFog[i]);
			SetEntPropEnt(i, Prop_Send, "m_PlayerFog.m_hCtrl", old > MaxClients ? old : -1);
		}
		g_bZMFogSaved[i] = false;
		g_iZMOldFog[i] = INVALID_ENT_REFERENCE;
	}

	if (fog != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(fog, "Kill");
	}
	g_iZMFogRef = INVALID_ENT_REFERENCE;
}

void AJB_LR_ZM_StartFog()
{
	AJB_LR_ZM_StopFog();
	if (!g_cvZMFogEnabled.BoolValue)
	{
		return;
	}

	float start = g_cvZMFogStart.FloatValue;
	float end = g_cvZMFogEnd.FloatValue;
	if (end <= start)
	{
		LogError("[AJB-LR] Zombie Mode fog_end must exceed fog_start; fog disabled for this setup.");
		return;
	}

	char color[64], parts[4][16];
	g_cvZMFogColor.GetString(color, sizeof(color));
	TrimString(color);
	bool valid = ExplodeString(color, " ", parts, sizeof(parts), sizeof(parts[])) == 3;
	for (int i = 0; valid && i < 3; i++)
	{
		int component;
		valid = parts[i][0] != '\0' && StringToIntEx(parts[i], component) == strlen(parts[i]) && component >= 0 && component <= 255;
	}
	if (!valid)
	{
		LogError("[AJB-LR] Invalid Zombie Mode fog color: %s. Using %s.", color, LR_ZM_FOG_COLOR);
		strcopy(color, sizeof(color), LR_ZM_FOG_COLOR);
	}

	int fog = CreateEntityByName("env_fog_controller");
	if (fog == -1)
	{
		LogError("[AJB-LR] Could not create Zombie Mode fog controller.");
		return;
	}
	DispatchKeyValue(fog, "targetname", "ajb_zm_fog");
	// Assign per player rather than replacing the map's master fog controller.
	DispatchKeyValue(fog, "spawnflags", "0");
	DispatchKeyValue(fog, "fogenable", "1");
	DispatchKeyValue(fog, "fogblend", "0");
	DispatchKeyValue(fog, "fogcolor", color);
	DispatchKeyValue(fog, "fogcolor2", color);
	DispatchKeyValueFloat(fog, "fogstart", start);
	DispatchKeyValueFloat(fog, "fogend", end);
	DispatchKeyValueFloat(fog, "fogmaxdensity", g_cvZMFogDensity.FloatValue);
	if (!DispatchSpawn(fog))
	{
		LogError("[AJB-LR] Could not spawn Zombie Mode fog controller.");
		AcceptEntityInput(fog, "Kill");
		return;
	}
	AcceptEntityInput(fog, "TurnOn");
	g_iZMFogRef = EntIndexToEntRef(fog);
}

void AJB_LR_ZM_StartAmbience()
{
	AJB_LR_ZM_StopMusic();
	AJB_LR_ZM_StartFog();
	for (int i = 1; i <= MaxClients; i++)
	{
		AJB_LR_ZM_ApplyAmbience(i);
	}
}

void AJB_LR_ZM_StopAmbience()
{
	AJB_LR_ZM_StopMusic();
	AJB_LR_ZM_StopFog();
}

void OnZMFogChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_bZombieMode || g_bZMEnding)
	{
		return;
	}
	AJB_LR_ZM_StartFog();
	for (int i = 1; i <= MaxClients; i++)
	{
		AJB_LR_ZM_ApplyAmbience(i);
	}
}

void OnZMMusicChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	AJB_LR_ZM_PrepareMusic();
}
