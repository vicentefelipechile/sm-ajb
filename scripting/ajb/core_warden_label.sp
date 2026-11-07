// =========================================================================================================
// Warden overhead label
// - A persistent TF2 world annotation that floats above the warden's head reading "Warden".
// - Hidden from the warden so their own offscreen annotation does not clutter their HUD.
// - Uses the same show_annotation / hide_annotation game events as the "Come here!" marker
//   (core_warden_marker.sp), but with follow_entindex so the callout tracks the warden entity.
// The warden is always alive while holding the role (death / team switch / disconnect all clear it),
// so claim/clear, cloak and disguise condition changes own its visibility. A long lifetime keeps it up
// until explicitly hidden, without a per-tick refresh.
// =========================================================================================================

// Fixed, distinct id so hide_annotation never collides with the marker's small incrementing ids.
#define AJB_LABEL_ANN_ID    1000000
// Long enough to outlast any single wardenship; hidden explicitly on clear, never left to expire.
#define AJB_LABEL_LIFETIME  3600.0

ConVar g_cvLabelEnabled;

bool g_bLabelShown;

void AJB_Label_OnPluginStart()
{
	g_cvLabelEnabled = CreateConVar(
		"sm_ajb_warden_label",
		"1",
		"1 = show other players a floating 'Warden' label above the warden's head while they hold the role.",
		_, true, 0.0, true, 1.0);
}

// Called on warden assignment, decloak and disguise removal. Client is a living guard warden.
void AJB_Label_Show(int client)
{
	if (g_cvLabelEnabled == null || !g_cvLabelEnabled.BoolValue)
	{
		return;
	}

	if (!AJB_IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	// Replace any label still up (e.g. a fast warden hand-off) before raising the new one.
	AJB_Label_Hide();
	if (TF2_IsPlayerInCondition(client, TFCond_Cloaked) || TF2_IsPlayerInCondition(client, TFCond_Disguised))
	{
		return;
	}

	char text[64];
	Format(text, sizeof(text), "%T", "Warden Label Text", LANG_SERVER);

	float pos[3];
	GetClientAbsOrigin(client, pos);

	Event ev = CreateEvent("show_annotation", true);
	if (ev == null)
	{
		return;
	}

	// worldPos is a fallback; follow_entindex makes the callout ride the warden's entity.
	ev.SetFloat("worldPosX", pos[0]);
	ev.SetFloat("worldPosY", pos[1]);
	ev.SetFloat("worldPosZ", pos[2]);
	ev.SetInt("follow_entindex", client);
	ev.SetInt("id", AJB_LABEL_ANN_ID);
	ev.SetString("text", text);
	ev.SetFloat("lifetime", AJB_LABEL_LIFETIME);
	ev.SetInt("visibilityBitfield", 0);
	ev.SetString("play_sound", "");            // silent: no ping each time it (re)appears
	// Send individually rather than using a 32-bit visibility mask on servers with more client slots.
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i != client && IsClientInGame(i) && !IsFakeClient(i))
		{
			ev.FireToClient(i);
		}
	}
	ev.Cancel();

	g_bLabelShown = true;
}

// Role cleanup, cloak and disguise hide the label without restoring stale wardenships.
void AJB_Label_Hide()
{
	if (!g_bLabelShown)
	{
		return;
	}

	Event ev = CreateEvent("hide_annotation", true);
	if (ev != null)
	{
		ev.SetInt("id", AJB_LABEL_ANN_ID);
		ev.Fire();
	}

	g_bLabelShown = false;
}
