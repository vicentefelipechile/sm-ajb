// =========================================================================================================
// Mass freekill detection — block crit splash that would wipe a cluster of prisoners in one frame
// =========================================================================================================
//
// New TF2 guards sometimes abuse the mode-given crits to crit-rocket a stack of prisoners and wipe them
// all in a single frame. This predicts that: when a crit splash hit from a guard lands on a cluster of
// prisoners, the projectile is removed and its damage blocked before anyone dies. The living warden — or,
// if the warden is the culprit, any admin — then judges the event: a false positive slides, a confirmed
// freekill slays the attacker. Kicks and bans stay with the staff on duty.

#define AJB_FK_JUDGE_ACCESS   "sm_ajb_freekill_punish"

static ConVar g_cvFKDetect;
static ConVar g_cvFKMinVictims;
static ConVar g_cvFKRadius;
static ConVar g_cvFKDecideTime;

// One verdict is cached per inflictor per tick so every victim of the same rocket reuses it instead of
// re-scanning the blast area on each OnTakeDamage call.
static int g_iFKJudgeInflictor = INVALID_ENT_REFERENCE;
static int g_iFKJudgeTick = -1;
static bool g_bFKJudgeBlock;

// Open decision (0 = none). The culprit is stored as a userid so it survives client-slot churn.
static int g_iFKPendingCulprit;
static int g_iFKPendingVictims;
static Handle g_hFKDecideTimer;

// =========================================================================================================
// Setup
// =========================================================================================================

void AJB_Freekill_OnPluginStart()
{
	g_cvFKDetect = CreateConVar("sm_ajb_freekill_detect", "1", "1 = detect and block crit splash that would wipe a cluster of prisoners in one frame.", _, true, 0.0, true, 1.0);
	g_cvFKMinVictims = CreateConVar("sm_ajb_freekill_min_victims", "3", "Prisoners inside the blast that flag a crit splash hit as a mass-freekill attempt.", _, true, 2.0, true, 32.0);
	g_cvFKRadius = CreateConVar("sm_ajb_freekill_radius", "160.0", "Radius (HU) scanned around the victim to count endangered prisoners.", _, true, 32.0);
	g_cvFKDecideTime = CreateConVar("sm_ajb_freekill_decide_time", "25", "Seconds the warden/admins have to punish a flagged event before it auto-dismisses (0 = until round end).", _, true, 0.0, true, 120.0);
}

void AJB_Freekill_RegisterCommands()
{
	RegConsoleCmd("sm_ajb_freekill_punish", Command_FreekillPunish, "Warden/admin: slay the flagged mass-freekill culprit.");
	RegConsoleCmd("sm_ajb_freekill_dismiss", Command_FreekillDismiss, "Warden/admin: dismiss the flagged mass-freekill event (false positive).");
	RegConsoleCmd("sm_ajb_freekill", Command_FreekillMenu, "Reopen the pending mass-freekill decision menu.");
}

// =========================================================================================================
// Detection (called from AJB_OnTakeDamage for guard -> prisoner hits)
// =========================================================================================================

Action AJB_Freekill_FilterDamage(int victim, int attacker, int inflictor, int damagetype)
{
	if (!g_cvFKDetect.BoolValue)
	{
		return Plugin_Continue;
	}

	// Free-fire modes are legitimate mass combat — never flag them.
	if (AJB_IsCombatDay() || AJB_IsLRPhase(g_RoundState) || g_RoundState == AJBState_SpecialDay)
	{
		return Plugin_Continue;
	}

	// Only a mode-given crit into a splash weapon can wipe a pile in one frame.
	if (!(damagetype & DMG_CRIT) || !AJB_Freekill_IsSplashInflictor(inflictor))
	{
		return Plugin_Continue;
	}

	// Reuse this tick's verdict for the same projectile so the scan runs once, not per victim.
	int tick = GetGameTickCount();
	int infRef = EntIndexToEntRef(inflictor);
	if (g_iFKJudgeTick == tick && g_iFKJudgeInflictor == infRef)
	{
		return g_bFKJudgeBlock ? Plugin_Handled : Plugin_Continue;
	}

	int endangered = AJB_Freekill_CountPrisonersNear(victim);
	bool block = (endangered >= g_cvFKMinVictims.IntValue);

	g_iFKJudgeTick = tick;
	g_iFKJudgeInflictor = infRef;
	g_bFKJudgeBlock = block;

	if (!block)
	{
		return Plugin_Continue;
	}

	AJB_Freekill_RemoveInflictor(inflictor);
	AJB_Freekill_Trigger(attacker, endangered);
	return Plugin_Handled;
}

bool AJB_Freekill_IsSplashInflictor(int inflictor)
{
	if (inflictor <= MaxClients || !IsValidEntity(inflictor))
	{
		return false;
	}

	char cls[64];
	GetEntityClassname(inflictor, cls, sizeof(cls));
	// Rockets, pipes and stickies are the projectiles that clear a cluster with one crit blast.
	return StrContains(cls, "tf_projectile_rocket") == 0
		|| StrContains(cls, "tf_projectile_pipe") == 0;
}

// Epicenter is the victim's own origin, not damagePosition — the latter is often a zero vector for
// explosions, and any pile member is by definition inside the blast.
int AJB_Freekill_CountPrisonersNear(int centerClient)
{
	float origin[3];
	GetClientAbsOrigin(centerClient, origin);

	int prisonersTeam = AJB_GetPrisonersTeam();
	float radius = g_cvFKRadius.FloatValue;
	int count = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != prisonersTeam)
		{
			continue;
		}

		float pos[3];
		GetClientAbsOrigin(i, pos);
		if (GetVectorDistance(origin, pos) <= radius)
		{
			count++;
		}
	}

	return count;
}

void AJB_Freekill_RemoveInflictor(int inflictor)
{
	if (inflictor <= MaxClients || !IsValidEntity(inflictor))
	{
		return;
	}

	// Defer: the projectile is mid-detonation right now; kill it on the next frame.
	RequestFrame(Frame_FreekillRemove, EntIndexToEntRef(inflictor));
}

void Frame_FreekillRemove(int ref)
{
	int ent = EntRefToEntIndex(ref);
	if (ent != -1 && IsValidEntity(ent))
	{
		AcceptEntityInput(ent, "Kill");
	}
}

// =========================================================================================================
// Decision flow
// =========================================================================================================

void AJB_Freekill_Trigger(int attacker, int victims)
{
	if (!AJB_IsValidClient(attacker))
	{
		return;
	}

	int culprit = GetClientUserId(attacker);

	// Fold repeat blasts from the same attacker into the open event instead of stacking prompts.
	if (g_iFKPendingCulprit == culprit)
	{
		if (victims > g_iFKPendingVictims)
		{
			g_iFKPendingVictims = victims;
		}
		return;
	}

	// A different attacker while one is still pending: keep the first open, just log the second.
	if (g_iFKPendingCulprit != 0)
	{
		LogMessage("[AJB-Freekill] second event by %L ignored while one is pending.", attacker);
		return;
	}

	g_iFKPendingCulprit = culprit;
	g_iFKPendingVictims = victims;
	LogMessage("[AJB-Freekill] blocked crit splash by %L endangering %d prisoners.", attacker, victims);

	AJB_Freekill_Announce(attacker, victims);
	AJB_Freekill_OpenDecision();

	AJB_Freekill_KillDecideTimer();
	float decide = g_cvFKDecideTime.FloatValue;
	if (decide > 0.0)
	{
		g_hFKDecideTimer = CreateTimer(decide, Timer_FreekillDecide, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

// The culprit can never judge their own event; the warden judges unless they are the culprit, otherwise
// only admins.
bool AJB_Freekill_CanJudge(int client)
{
	if (!AJB_IsValidClient(client))
	{
		return false;
	}

	if (GetClientUserId(client) == g_iFKPendingCulprit)
	{
		return false;
	}

	if (AJB_IsWarden(client))
	{
		return true;
	}

	return CheckCommandAccess(client, AJB_FK_JUDGE_ACCESS, ADMFLAG_GENERIC);
}

void AJB_Freekill_Announce(int attacker, int victims)
{
	char name[MAX_NAME_LENGTH];
	GetClientName(attacker, name, sizeof(name));

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !AJB_Freekill_CanJudge(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", "Freekill Detected", i, prefix, name, victims);
	}
}

void AJB_Freekill_OpenDecision()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && AJB_Freekill_CanJudge(i))
		{
			AJB_Freekill_ShowMenu(i);
		}
	}
}

void AJB_Freekill_ShowMenu(int client)
{
	if (g_iFKPendingCulprit == 0 || !AJB_Freekill_CanJudge(client))
	{
		return;
	}

	char name[MAX_NAME_LENGTH];
	int culprit = GetClientOfUserId(g_iFKPendingCulprit);
	if (culprit > 0)
	{
		GetClientName(culprit, name, sizeof(name));
	}
	else
	{
		strcopy(name, sizeof(name), "?");
	}

	char title[128];
	char line[64];
	Format(title, sizeof(title), "%T", "Freekill Menu Title", client, name, g_iFKPendingVictims);

	Menu menu = new Menu(MenuHandler_Freekill);
	menu.SetTitle(title);

	Format(line, sizeof(line), "%T", "Freekill Menu Punish", client);
	menu.AddItem("punish", line);

	Format(line, sizeof(line), "%T", "Freekill Menu Dismiss", client);
	menu.AddItem("dismiss", line);

	menu.ExitButton = true;
	menu.Display(client, 0);
}

public int MenuHandler_Freekill(Menu menu, MenuAction action, int param1, int param2)
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
	if (g_iFKPendingCulprit == 0 || !AJB_Freekill_CanJudge(client))
	{
		return 0;
	}

	char info[16];
	menu.GetItem(param2, info, sizeof(info));
	AJB_Freekill_Resolve(client, StrEqual(info, "punish"));
	return 0;
}

void AJB_Freekill_Resolve(int judge, bool punish)
{
	if (g_iFKPendingCulprit == 0)
	{
		return;
	}

	char culpritName[MAX_NAME_LENGTH];
	int culprit = GetClientOfUserId(g_iFKPendingCulprit);
	if (culprit > 0)
	{
		GetClientName(culprit, culpritName, sizeof(culpritName));
	}
	else
	{
		strcopy(culpritName, sizeof(culpritName), "?");
	}

	char judgeName[MAX_NAME_LENGTH];
	if (AJB_IsValidClient(judge))
	{
		GetClientName(judge, judgeName, sizeof(judgeName));
	}
	else
	{
		strcopy(judgeName, sizeof(judgeName), "CONSOLE");
	}

	AJB_Freekill_Clear();

	if (punish && culprit > 0 && IsPlayerAlive(culprit))
	{
		ForcePlayerSuicide(culprit);
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		char prefix[32];
		AJB_GetPrefix(i, prefix, sizeof(prefix));
		CPrintToChat(i, "%T", punish ? "Freekill Punished" : "Freekill Dismissed", i, prefix, culpritName, judgeName);
	}

	LogMessage("[AJB-Freekill] %s by %s (culprit %s).", punish ? "PUNISHED" : "dismissed", judgeName, culpritName);
}

Action Timer_FreekillDecide(Handle timer)
{
	g_hFKDecideTimer = null;
	if (g_iFKPendingCulprit == 0)
	{
		return Plugin_Stop;
	}

	// No decision in time — assume a false positive and let it slide (never auto-slay).
	AJB_ChatAll("Freekill Expired");
	AJB_Freekill_Clear();
	return Plugin_Stop;
}

// =========================================================================================================
// State teardown
// =========================================================================================================

void AJB_Freekill_KillDecideTimer()
{
	if (g_hFKDecideTimer != null)
	{
		delete g_hFKDecideTimer;
		g_hFKDecideTimer = null;
	}
}

void AJB_Freekill_Clear()
{
	g_iFKPendingCulprit = 0;
	g_iFKPendingVictims = 0;
	AJB_Freekill_KillDecideTimer();
}

// Round transitions and plugin cleanup drop any open event and the per-tick verdict cache.
void AJB_Freekill_Reset()
{
	AJB_Freekill_Clear();
	g_iFKJudgeInflictor = INVALID_ENT_REFERENCE;
	g_iFKJudgeTick = -1;
	g_bFKJudgeBlock = false;
}

void AJB_Freekill_OnClientDisconnect(int client)
{
	if (g_iFKPendingCulprit != 0 && GetClientOfUserId(g_iFKPendingCulprit) == client)
	{
		AJB_ChatAll("Freekill Culprit Left");
		AJB_Freekill_Clear();
	}
}

// =========================================================================================================
// Commands
// =========================================================================================================

Action Command_FreekillPunish(int client, int args)
{
	return AJB_Freekill_JudgeCommand(client, true);
}

Action Command_FreekillDismiss(int client, int args)
{
	return AJB_Freekill_JudgeCommand(client, false);
}

Action AJB_Freekill_JudgeCommand(int client, bool punish)
{
	if (!g_bModeActive)
	{
		AJB_Reply(client, "Mode Inactive");
		return Plugin_Handled;
	}

	if (g_iFKPendingCulprit == 0)
	{
		AJB_Reply(client, "Freekill None Pending");
		return Plugin_Handled;
	}

	if (client != 0 && !AJB_Freekill_CanJudge(client))
	{
		AJB_Reply(client, "Freekill No Access");
		return Plugin_Handled;
	}

	AJB_Freekill_Resolve(client, punish);
	return Plugin_Handled;
}

Action Command_FreekillMenu(int client, int args)
{
	if (!g_bModeActive || client == 0)
	{
		return Plugin_Handled;
	}

	if (g_iFKPendingCulprit == 0)
	{
		AJB_Reply(client, "Freekill None Pending");
		return Plugin_Handled;
	}

	if (!AJB_Freekill_CanJudge(client))
	{
		AJB_Reply(client, "Freekill No Access");
		return Plugin_Handled;
	}

	AJB_Freekill_ShowMenu(client);
	return Plugin_Handled;
}
