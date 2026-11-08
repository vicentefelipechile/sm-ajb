// =========================================================================================================
// Escape from the Yeti - snow fog, wind, growls and proximity heartbeat
// Author: Winewald
// =========================================================================================================

#define LR_YETI_WIND "ambient/windwinter.wav"
#define LR_YETI_HEARTBEAT "player/heartbeat1.wav"
#define LR_YETI_FOG_COLOR "215 225 235"
#define LR_YETI_FOG_START 250.0
#define LR_YETI_FOG_END 2600.0
#define LR_YETI_FOG_DENSITY 0.55
#define LR_YETI_BEAT_LENGTH 0.3

static const char g_sYetiGrowls[][] = {
	"ambient/lair/yeti_statue_growl1.wav",
	"ambient/lair/yeti_statue_growl2.wav",
	"ambient/lair/yeti_statue_growl3.wav",
	"ambient/lair/yeti_statue_growl4.wav",
	"ambient/lair/yeti_statue_growl5.wav",
	"ambient/lair/yeti_statue_growl6.wav"
};

ConVar g_cvYetiGrowlMin;
ConVar g_cvYetiGrowlMax;
ConVar g_cvYetiHeartRadius;
ConVar g_cvYetiWindVolume;
ConVar g_cvYetiWindLength;
int g_iYetiFogRef = INVALID_ENT_REFERENCE;
int g_iYetiOldFog[MAXPLAYERS + 1];
bool g_bYetiFogSaved[MAXPLAYERS + 1];
bool g_bYetiWindOn[MAXPLAYERS + 1];
float g_fYetiNextBeat[MAXPLAYERS + 1];
float g_fYetiStopBeat[MAXPLAYERS + 1];
float g_fYetiNextGrowl;
float g_fYetiNextWind;

void AJB_LR_Yeti_InitAmbience()
{
	g_cvYetiGrowlMin = CreateConVar("sm_ajb_lr_yeti_growl_min", "25", "Yeti: minimum seconds between ambient growls.", _, true, 5.0, true, 300.0);
	g_cvYetiGrowlMax = CreateConVar("sm_ajb_lr_yeti_growl_max", "45", "Yeti: maximum seconds between ambient growls, clamped to minimum.", _, true, 5.0, true, 300.0);
	g_cvYetiHeartRadius = CreateConVar("sm_ajb_lr_yeti_heart_radius", "1000", "Yeti: proximity heartbeat radius.", _, true, 100.0, true, 4000.0);
	g_cvYetiWindVolume = CreateConVar("sm_ajb_lr_yeti_wind_volume", "0.45", "Yeti: wind volume (0 = silent).", _, true, 0.0, true, 1.0);
	g_cvYetiWindLength = CreateConVar("sm_ajb_lr_yeti_wind_length", "16", "Yeti: seconds between wind samples.", _, true, 2.0, true, 120.0);
}

void AJB_LR_Yeti_PrecacheAmbience()
{
	PrecacheSound(LR_YETI_WIND, true);
	PrecacheSound(LR_YETI_HEARTBEAT, true);
	for (int i = 0; i < sizeof(g_sYetiGrowls); i++) PrecacheSound(g_sYetiGrowls[i], true);
}

void AJB_LR_Yeti_ResetAmbienceClient(int client)
{
	g_bYetiFogSaved[client] = false;
	g_iYetiOldFog[client] = INVALID_ENT_REFERENCE;
	g_bYetiWindOn[client] = false;
	g_fYetiNextBeat[client] = 0.0;
	g_fYetiStopBeat[client] = 0.0;
}

void AJB_LR_Yeti_PlayWind(int client)
{
	if (g_bYetiWindOn[client]) StopSound(client, SNDCHAN_STATIC, LR_YETI_WIND);
	g_bYetiWindOn[client] = g_cvYetiWindVolume.FloatValue > 0.0;
	if (g_bYetiWindOn[client]) EmitSoundToClient(client, LR_YETI_WIND, SOUND_FROM_PLAYER, SNDCHAN_STATIC,
		SNDLEVEL_NONE, SND_NOFLAGS, g_cvYetiWindVolume.FloatValue);
}

void AJB_LR_Yeti_ApplyAmbience(int client)
{
	if (!g_bYeti || g_bYetiEnding || !IsClientInGame(client) || IsFakeClient(client)) return;
	AJB_ApplyClientFog(client, g_iYetiFogRef, g_bYetiFogSaved[client], g_iYetiOldFog[client]);
	if (!g_bYetiWindOn[client]) AJB_LR_Yeti_PlayWind(client);
}

void Frame_YetiAmbience(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0) AJB_LR_Yeti_ApplyAmbience(client);
}

void AJB_LR_Yeti_ScheduleGrowl(float now)
{
	float min = g_cvYetiGrowlMin.FloatValue;
	float max = g_cvYetiGrowlMax.FloatValue;
	if (max < min) max = min;
	g_fYetiNextGrowl = now + GetRandomFloat(min, max);
}

void AJB_LR_Yeti_Growl(bool roar)
{
	if (g_iYeti == 0 || !IsClientInGame(g_iYeti) || !IsPlayerAlive(g_iYeti)) return;
	int first = GetRandomInt(0, sizeof(g_sYetiGrowls) - 1);
	int layers = roar ? 3 : 1;
	for (int i = 0; i < layers; i++)
	{
		EmitSoundToAll(g_sYetiGrowls[(first + i * 2) % sizeof(g_sYetiGrowls)], g_iYeti, SNDCHAN_AUTO,
			roar ? SNDLEVEL_GUNFIRE : SNDLEVEL_RAIDSIREN, SND_NOFLAGS, 1.0, roar ? 55 + i * 15 : SNDPITCH_NORMAL);
	}
}

void AJB_LR_Yeti_StartAmbience()
{
	g_iYetiFogRef = AJB_CreateFog("ajb_yeti_fog", LR_YETI_FOG_COLOR, LR_YETI_FOG_START, LR_YETI_FOG_END, LR_YETI_FOG_DENSITY);
	AJB_LR_Yeti_ScheduleGrowl(GetGameTime());
	g_fYetiNextWind = GetGameTime() + g_cvYetiWindLength.FloatValue;
	for (int i = 1; i <= MaxClients; i++) AJB_LR_Yeti_ApplyAmbience(i);
}

void AJB_LR_Yeti_ThinkAmbience(float now)
{
	if (!g_bYetiHiding && now >= g_fYetiNextGrowl)
	{
		AJB_LR_Yeti_Growl(false);
		AJB_LR_Yeti_ScheduleGrowl(now);
	}
	bool wind = now >= g_fYetiNextWind;
	if (wind) g_fYetiNextWind = now + g_cvYetiWindLength.FloatValue;
	float origin[3], position[3];
	GetClientAbsOrigin(g_iYeti, origin);
	float radius = g_cvYetiHeartRadius.FloatValue;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;
		if (wind) AJB_LR_Yeti_PlayWind(i);
		// The heartbeat sample loops; stop each beat without scheduling a timer per listener.
		if (g_fYetiStopBeat[i] > 0.0 && now >= g_fYetiStopBeat[i])
		{
			StopSound(i, SNDCHAN_BODY, LR_YETI_HEARTBEAT);
			g_fYetiStopBeat[i] = 0.0;
		}
		if (g_bYetiHiding || !IsPlayerAlive(g_iYeti) || !AJB_LR_Yeti_IsFreeHuman(i) || now < g_fYetiNextBeat[i]) continue;
		GetClientAbsOrigin(i, position);
		float distance = GetVectorDistance(origin, position);
		if (distance > radius) continue;
		float ratio = distance / radius;
		g_fYetiNextBeat[i] = now + 0.35 + 0.85 * ratio;
		g_fYetiStopBeat[i] = now + LR_YETI_BEAT_LENGTH;
		EmitSoundToClient(i, LR_YETI_HEARTBEAT, SOUND_FROM_PLAYER, SNDCHAN_BODY, SNDLEVEL_NONE, SND_NOFLAGS, 1.0 - 0.6 * ratio);
	}
}

void AJB_LR_Yeti_StopAmbience()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		AJB_RestoreClientFog(i, g_iYetiFogRef, g_bYetiFogSaved[i], g_iYetiOldFog[i]);
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			if (g_bYetiWindOn[i]) StopSound(i, SNDCHAN_STATIC, LR_YETI_WIND);
			if (g_fYetiStopBeat[i] > 0.0) StopSound(i, SNDCHAN_BODY, LR_YETI_HEARTBEAT);
		}
		AJB_LR_Yeti_ResetAmbienceClient(i);
	}
	int fog = EntRefToEntIndex(g_iYetiFogRef);
	if (fog != INVALID_ENT_REFERENCE) RemoveEntity(fog);
	g_iYetiFogRef = INVALID_ENT_REFERENCE;
}
