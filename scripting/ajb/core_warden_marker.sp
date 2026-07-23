// =========================================================================================================
// Warden "Come here!" marker
// - A pulsing beam ring on the ground where the warden is aiming.
// - A native TF2 world annotation (the tutorial-style floating callout) via the show_annotation
//   game event, so it renders in TF2's own marker style.
// One marker at a time; a new one replaces the old. Cooldown-gated to avoid spam.
// =========================================================================================================

#define AJB_MARKER_RING_RADIUS   240.0
#define AJB_MARKER_RING_INNER     16.0
#define AJB_MARKER_RING_WIDTH      6.0
#define AJB_MARKER_REDRAW          0.70   // < ring life so the pulse looks continuous
#define AJB_MARKER_RING_LIFE       1.00
#define AJB_MARKER_TRACE_RANGE   8192.0
#define AJB_MARKER_SOUND         "items/spawn_item.wav"

ConVar g_cvMarkerEnabled;
ConVar g_cvMarkerTime;

int g_iMarkerBeam = -1;
int g_iMarkerHalo = -1;

Handle g_hMarkerTimer;
float g_fMarkerPos[3];
float g_fMarkerExpire;       // GameTime when the ring stops redrawing
int g_iMarkerAnnId;          // annotation id, bumped per marker so Hide targets the right one
int g_iMarkerAnnSerial;      // monotonic source for g_iMarkerAnnId so ids never collide

void AJB_Marker_OnPluginStart()
{
	g_cvMarkerEnabled = CreateConVar(
		"sm_ajb_warden_marker",
		"1",
		"1 = warden can place a 'Come here!' marker (beam ring + TF2 annotation) from the menu.",
		_, true, 0.0, true, 1.0);

	g_cvMarkerTime = CreateConVar(
		"sm_ajb_warden_marker_time",
		"8.0",
		"How long a warden marker stays visible, in seconds.",
		_, true, 2.0, true, 30.0);
}

void AJB_Marker_OnMapStart()
{
	// Standard beam sprites shipped with TF2.
	g_iMarkerBeam = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iMarkerHalo = PrecacheModel("materials/sprites/halo01.vmt");

	if (g_iMarkerBeam <= 0)
	{
		g_iMarkerBeam = PrecacheModel("sprites/laserbeam.spr");
	}

	PrecacheSound(AJB_MARKER_SOUND);

	AJB_Marker_Clear();
}

// Full teardown: stop the ring and hide any live annotation.
void AJB_Marker_Clear()
{
	if (g_hMarkerTimer != null)
	{
		delete g_hMarkerTimer;
		g_hMarkerTimer = null;
	}

	if (g_iMarkerAnnId > 0)
	{
		AJB_Marker_HideAnnotation(g_iMarkerAnnId);
		g_iMarkerAnnId = 0;
	}

	g_fMarkerExpire = 0.0;
}

// Called from the warden menu (page 0). Client is a living warden here.
void AJB_Warden_PlaceMarker(int client)
{
	if (g_cvMarkerEnabled == null || !g_cvMarkerEnabled.BoolValue)
	{
		AJB_Reply(client, "Warden Marker Disabled");
		return;
	}

	if (!AJB_IsValidClient(client) || !IsPlayerAlive(client))
	{
		return;
	}

	float pos[3];
	if (!AJB_Marker_TraceAim(client, pos))
	{
		AJB_Reply(client, "Warden Marker No Spot");
		return;
	}

	// Replace any existing marker before starting the new one.
	AJB_Marker_Clear();

	float life = g_cvMarkerTime.FloatValue;
	g_fMarkerPos = pos;
	g_fMarkerExpire = GetGameTime() + life;
	g_iMarkerAnnId = ++g_iMarkerAnnSerial;

	// Draw the first ring immediately, then keep pulsing until expiry.
	AJB_Marker_DrawRing();
	g_hMarkerTimer = CreateTimer(AJB_MARKER_REDRAW, Timer_MarkerPulse, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	AJB_Marker_ShowAnnotation(pos, life);
	EmitSoundToAll(AJB_MARKER_SOUND, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, _, _, _, _, pos);
}

Action Timer_MarkerPulse(Handle timer)
{
	if (!g_bModeActive || GetGameTime() >= g_fMarkerExpire)
	{
		g_hMarkerTimer = null;
		g_iMarkerAnnId = 0;
		g_fMarkerExpire = 0.0;
		return Plugin_Stop;
	}

	AJB_Marker_DrawRing();
	return Plugin_Continue;
}

void AJB_Marker_DrawRing()
{
	if (g_iMarkerBeam <= 0)
	{
		return;
	}

	int color[4] = { 40, 120, 255, 220 };  // warden blue
	int halo = (g_iMarkerHalo > 0) ? g_iMarkerHalo : g_iMarkerBeam;

	// Ring expands from a small inner radius outward each pulse (rally-ping look).
	TE_SetupBeamRingPoint(
		g_fMarkerPos,
		AJB_MARKER_RING_INNER,
		AJB_MARKER_RING_RADIUS,
		g_iMarkerBeam,
		halo,
		0, 15,
		AJB_MARKER_RING_LIFE,
		AJB_MARKER_RING_WIDTH,
		0.0,          // Amplitude
		color,
		5,            // Speed
		0);           // Flags
	TE_SendToAll();
}

// Trace from the warden's eyes to the world; marker sits at the hit point.
bool AJB_Marker_TraceAim(int client, float pos[3])
{
	float eye[3];
	float ang[3];
	float dir[3];
	float end[3];

	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, ang);
	GetAngleVectors(ang, dir, NULL_VECTOR, NULL_VECTOR);

	end[0] = eye[0] + dir[0] * AJB_MARKER_TRACE_RANGE;
	end[1] = eye[1] + dir[1] * AJB_MARKER_TRACE_RANGE;
	end[2] = eye[2] + dir[2] * AJB_MARKER_TRACE_RANGE;

	TR_TraceRayFilter(eye, end, MASK_SOLID, RayType_EndPoint, TraceFilter_MarkerWorld, client);
	if (!TR_DidHit())
	{
		return false;
	}

	TR_GetEndPosition(pos);
	// Nudge up off the surface so the ring is not z-fighting the floor.
	pos[2] += 4.0;
	return true;
}

bool TraceFilter_MarkerWorld(int entity, int contentsMask, int client)
{
	// Ignore players so the marker lands on geometry, not on a body in the way.
	return entity > MaxClients;
}

// ---------------------------------------------------------------------------------------------------------
// TF2 native world annotation — the tutorial-style floating callout.
// The show_annotation / hide_annotation game events drive CTFAnnotationsMgr on every client,
// so the marker renders in TF2's own marker style. visibilityBitfield 0 = shown to everyone.
// ---------------------------------------------------------------------------------------------------------

void AJB_Marker_ShowAnnotation(const float pos[3], float life)
{
	// A single shared event → one language for all; use the server's default language.
	char text[64];
	Format(text, sizeof(text), "%T", "Warden Marker Text", LANG_SERVER);

	Event ev = CreateEvent("show_annotation", true);
	if (ev == null)
	{
		return;
	}

	ev.SetFloat("worldPosX", pos[0]);
	ev.SetFloat("worldPosY", pos[1]);
	ev.SetFloat("worldPosZ", pos[2]);
	ev.SetInt("id", g_iMarkerAnnId);
	ev.SetString("text", text);
	ev.SetFloat("lifetime", life);
	ev.SetInt("visibilityBitfield", 0);   // 0 = visible to all players
	ev.Fire();
}

void AJB_Marker_HideAnnotation(int id)
{
	Event ev = CreateEvent("hide_annotation", true);
	if (ev == null)
	{
		return;
	}

	ev.SetInt("id", id);
	ev.Fire();
}
