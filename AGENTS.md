# AGENTS.md — Another Jailbreak (AJB)

TF2-native jailbreak gamemode for SourceMod (SourcePawn). TF2 only — the core refuses to
load on any other engine (`AskPluginLoad2` checks `Engine_TF2`).

This file is the entry point for coding agents. The git repo root is `projects/ajb/`,
which lives inside a full SourceMod tree at `addons/sourcemod/`.

## Layout

```
projects/ajb/
├── deploy.ps1                 # compile + deploy + asset sync
├── plugins/                   # compile output (.smx), committed
├── scripting/
│   ├── ajb.sp                 # core plugin entry (single compilation unit)
│   ├── ajb/core_*.sp          # core fragments #included by ajb.sp
│   ├── modules/ajb_*.sp       # standalone plugins that consume the core API
│   ├── modules/lastrequest/   # LR wish fragments #included by ajb_lastrequest.sp
│   └── include/ajb/*.inc      # shared api / enums / constants / phrases
│   └── include/ff2r.inc, cfgmap.inc   # vendored from the FF2 Rewrite project (compile only)
├── translations/*.phrases.txt
├── configs/                   # settings, prisoner loadout, per-map configs
└── gamedata/ajb.games.txt
```

The live server reads from `addons/sourcemod/` (`plugins/`, `translations/`,
`configs/ajb/`). Deploy copies the project output there — see below.

## Architecture

Two distinct patterns, do not confuse them:

- **Core (`ajb.smx`)** — `ajb.sp` `#include`s every `ajb/core_*.sp` fragment. They are one
  compilation unit and share the globals declared in `ajb.sp` (`g_bModeActive`,
  `g_RoundState`, `g_iWarden`, the `g_cv*` ConVars, forwards, etc.). Fragments call each
  other's functions directly; there are no per-fragment headers.
- **Modules (`ajb_*.smx`)** — separate plugins (admin, boosts, hud, lastrequest, mutes,
  dummy). They talk to the core only through the public API in
  `scripting/include/ajb/ajb.inc` (natives + forwards). Natives are marked optional so a
  module keeps loading if the core is absent.

The round lifecycle is the spine. `AJBRoundState` (in `enums.inc`): Disabled → Waiting →
CellsLocked → CellsOpen → LRChoosing/LRChosen → SpecialDay → RoundEnd. The **preround**
(prep window) is a free-for-all: guards move, prisoners frozen. `AJB_NotifyLiveRoundBegin`
(`core_rounds.sp`) is the single point where the preround ends and the round goes live —
team balance and auto-warden both fire from there. Never apply live-round rules during prep.

## Build & deploy

Requires `scripting/spcomp.exe` (or `spcomp64.exe`) in the SourceMod tree. Include dirs:
`scripting/include` and `projects/ajb/scripting/include`.

```powershell
# from addons/sourcemod
.\projects\ajb\deploy.ps1               # compile all → project plugins/ → live plugins/ + sync assets
.\projects\ajb\deploy.ps1 -CompileOnly  # compile into projects/ajb/plugins/ only
.\projects\ajb\deploy.ps1 -SyncOnly     # sync translations/configs/gamedata, no compile
```

Deploy syncs translations, per-map/dodgeball configs, prisoner_loadout/settings and
`gamedata/ajb.games.txt`; it prints a per-plugin SHA256 so a stale live `.smx` is obvious.

`ajb.sp` is compiled explicitly; every `modules/*.sp` is compiled to its own `.smx`. The
core fragments (`ajb/core_*.sp`) are **not** compiled directly — they are included by
`ajb.sp`. Same for Last Request: `modules/lastrequest/wish_*.sp` are included by
`ajb_lastrequest.sp` only (do not compile them on their own).

### Preferred: the `sourcemod` MCP tools

A live server bridge is exposed via the `sourcemod` MCP server. Use it — not RCON, not raw
PowerShell — for the compile/deploy/reload loop and for running server commands:

- `compile` (pass the `include` dir), `deploy`, `reload_plugin`
- `send_intent` (`console` action) to run server console commands
- `cfg_get_cvar` / `cfg_set_cvar`, `get_errors`, `bridge_status`

Typical change to a core fragment: `compile` `ajb.sp` → `deploy` → `reload_plugin ajb`.
Editing a `modules/*.sp` compiles/deploys/reloads that module by its own name.

If `bridge_status` reports disconnected (map change / server down), the deploy still lands
in `plugins/`; it loads on next server start or a later `reload_plugin`.

## Conventions

- **English** for all code, comments, identifiers, log strings. Chat/translation strings
  may be Spanish/other via `translations/*.phrases.txt`.
- Section separators are `//` + `=` to **105 columns** (see any existing file).
- Comments explain **why**, not what. Keep them to a single line; do not over-comment or
  narrate obvious code. One concise line beats a paragraph.
- `#pragma semicolon 1`, `#pragma newdecls required`.
- ConVars: `sm_ajb_*`, created in `OnPluginStart`, persisted via `AutoExecConfig(true, "ajb")`
  → `cfg/sourcemod/ajb.cfg`. A hot `reload_plugin` does **not** refresh a ConVar's help text
  or bounds (cosmetic only) — that needs a map change; behavior still updates.
- Prefer `TF2_RespawnPlayer` after `ChangeClientTeam` for players who must keep playing —
  `ChangeClientTeam` kills a live player and prisoners get no mid-round respawn wave. To safely swap teams without dying, transit through Spectator first (`ChangeClientTeam(client, 1)`).
- **Round state order matters**: Helpers like `AJB_OpenCells` implicitly change the round state (to `AJBState_CellsOpen`). When building LR modules or Special Days, always open cells *before* calling `AJB_SetRoundState` if you want your custom state (like `AJBState_SpecialDay`) to persist. Concretely:
  - `AJB_BeginCombatDay()` / `AJB_BeginFreedayAllCosmetic()` already open the cells **and** set the final state — never call `AJB_OpenCells()`/`AJB_SetRoundState()` after them (double "Cells Opened" announce + door refire).
  - Days that need cells **closed** (Cell Wars) must not use `BeginCombatDay`; set up manually and finish with `AJB_CloseCells()` → `AJB_SetRoundState(AJBState_SpecialDay)` (state call last).
  - Normal-round wishes (Low Gravity, Guard Melee, Set All Class, …) must **not touch cells at all** — the warden or `sm_ajb_cells_auto_open` owns them.
  - The cells auto-open timer only fires in `AJBState_CellsLocked` (core), so it can never reopen a Special Day's closed cells.
- Memory: no leaked Handles. Timers that fire once and return `Plugin_Stop` are freed
  automatically; stored Handles (`g_h*`) must be `delete`d. Prefer stack arrays over
  `ArrayList`/`StringMap` for short-lived per-player scans.
- **Shared utilities — check before writing**: Before adding a helper, loop, or validator
  inline, review the shared includes under `scripting/include/ajb/` and the core team helpers
  in `ajb/core_teams.sp`. Common utilities already exist there:
  - **Client validation**: `AJB_IsValidClient(client, aliveOnly)` → `core_teams.sp`
  - **Team queries**: `AJB_GetGuardsTeam()` / `AJB_GetPrisonersTeam()` → `core_mode.sp`
    (exposed as natives for modules via `ajb.inc`)
  - **Team helpers**: `AJB_ClientIsGuard`, `AJB_ClientIsPrisoner`, `AJB_PickRandomAliveOnTeam`,
    `AJB_MaxGuardsFromCounts(guards, prisoners)` (pass precomputed counts to avoid re-scans)
    → `core_teams.sp`
  - **Chat with prefix**: `AJB_GetPrefix`, `AJB_ChatAll`, `AJB_ChatAll1N/2N/1S/2S/3S/1N1S/1S1N/1S2N`
    → `phrases.inc` (the only broadcast loops in the project; do not re-implement them)
  - **State name**: `AJB_GetStateName(state, buf, maxlen)` → `enums.inc`
  - **Class name**: `AJB_TFClassName(cls, buf, maxlen)` → `constants.inc`
  - **Safe team swap**: `AJB_ChangeTeamSafe(client, team)` → `ajb.inc` (transit via Spectator)
  - **Distance squared**: `AJB_GetDistanceSqr(v1, v2)` → `constants.inc` (included by core + modules)
  - **Special-day setup**: `AJB_SetupSpecialDay()` (clear warden + rebel-on-hit off + clear phase
    timer) — native via `ajb.inc`, used by HG/ZM/CW/FF2
  - **LR folding**: `AJB_LR_FoldAllToRed` / `AJB_LR_RestoreBluOriginal` (HG/CW shared shape) and
    `AJB_LR_KillAllModeTimers()` → `ajb_lastrequest.sp`

  If a helper does not exist yet, add it to the appropriate shared include rather than
  writing it inline in a single module. This avoids the drift of duplicated functions.

## Database

`ajb_admin` (guard bans) uses SQL via `configs/databases.cfg`. The entry name comes from
`sm_ajb_admin_db` (default `ajb`); the repo ships an `ajb` SQLite entry. If that entry is
missing, `AJB_DB_Connect` falls back to the stock `storage-local` SQLite entry. The table
(`ajb_guardbans`) is created portably for SQLite or MySQL.

## Auto-warden

At preround end (`AJB_ScheduleAutoWarden`), if `sm_ajb_warden_auto 1` and no warden is set,
one is picked after `sm_ajb_warden_auto_delay` seconds (0–10). `sm_ajb_warden_auto_mode`
selects the picker: `0` = uniform random (`AJB_PickRandomAliveOnTeam`), `1` = weighted by
anti-repetition (`AJB_PickWeightedWardenGuard`), favoring guards who have not been warden
recently. `g_iWardenRoundSerial` ticks per round; `g_iWardenLastRound[client]` is stamped in
`AJB_SetWarden` and reset in `OnClientPutInServer`.

## FF2 Boss Wish (`ajb_ff2.sp`) — dependencies & degraded modes

`ajb_ff2` is a standalone module that turns the next live round into a Freak Fortress 2 boss
fight via the `ff2r` natives (`FF2R_GetSpecialData` / `FF2R_CreateBoss`). It injects its wish
into the Last Request menu through the external wish hooks in `include/ajb/lrwish.inc`
(`AJB_OnLRWishMenu` / `AJB_OnLRWishSelect`), fired by `ajb_lastrequest` for menu items at
index >= `LR_WISH_BUILTIN_COUNT`. The LR module does not know about the FF2 wish: it only
closes its own menu state when the external plugin returns `Plugin_Handled`.

Compile-time only: `include/ff2r.inc` + `include/cfgmap.inc` are vendored from the FF2
Rewrite project (`cfgmap.inc` is a pure SourcePawn parser — **no extension needed**; it
defines `CFGMAP_FF2R` so the `BossData`/`ConfigMap` methodmaps in `ff2r.inc` are available).

Dependency matrix — *blocked* means the wish cannot run; *degraded* means it runs with
features off. `sm_ajb_ff2_status` prints a live diagnosis.

| Dependency | If missing → | Behavior |
| --- | --- | --- |
| `ff2r` library (`freak_fortress_2.smx`) | **Blocked** | Module loads; menu item disabled (label "requires Freak Fortress 2"). Nothing else changes. |
| Bosses precached (`FF2R_GetGamemodeType() < 1`) | **Blocked** | FF2 loaded but no charset/boss pack (e.g. `characters.cfg` missing or a map entry with `enable -1`); item disabled. |
| Ability subplugins (`plugins/freaks/`) | **Degraded** | Boss spawns with model/weapons/health/sounds/HUD but **no rage/abilities** (they live in `ff2r_*_abilities.smx`). Chat warning on apply. |
| `morecolors` plugin | **Degraded** | Shared AJB dependency; chat/colors degrade everywhere, not just FF2. |
| TF2Items / TF2Attributes / TF2Utils | **Degraded** | FF2 falls back internally (fewer weapon attributes, no ability lag comp). |

Server install (owner side, FF2 not shipped by AJB): New Install Package from
`Batfoxkid/Freak-Fortress-2-Rewrite` releases → `freak_fortress_2.smx` in `plugins/`, the
`ff2r_*.smx` ability plugins in `plugins/freaks/` (FF2 renames them to `.ff2` while idle),
plus `translations`, `gamedata/ff2.txt`, `data/freak_fortress_2/`, `configs/freak_fortress_2/`
and `custom/ff2r_defaults` → `tf/custom/`. FF2's `data/.../maps.cfg` ships `"*" { "enable" "0" }`,
so on jailbreak maps bosses are precached but FF2 never runs the gamemode — exactly what the
loader needs. Only bosses of the active pack (`ff2_current` / pack vote) appear in the picker.

Boss round flow (modeled on the LR's Zombie Mode): applied in `AJB_OnLiveRoundBegin`;
`AJB_BeginCombatDay` + `AJB_ClearWarden` + `AJB_SetRebelOnHit(false)` + `AJB_ClearPhaseTimer`;
`sm_ajb_freekill_detect` parked (boss AoE would trip it); `AJB_OpenCells()` **before**
`AJB_SetRoundState(AJBState_SpecialDay)` (order per Conventions); boss player (the LR chooser,
else random) transits to the boss team, `FF2R_CreateBoss(boss, cfg, team)` then
`TF2_RespawnPlayer` (spawn applies the loadout); everyone else folded onto RED and armed in
`Frame_ArmRedPlayers`. Round ends via the engine (empty team); `AJB_OnRoundWin` removes the
boss (`FF2R_CreateBoss(client, null, 0)`), restores teams and cvars. Known limitation: the LR
module's `AJB_LR_IsGrantBlocked` does not see external pending wishes, so the warden could
still grant an LR while an FF2 wish is queued — accepted for now.

## Reference: commands & ConVars

Exhaustive list generated from the source. `*_version` ConVars (one per plugin/module,
`FCVAR_NOTIFY | FCVAR_DONTRECORD`) are omitted. Access column: *console* = any player,
*GENERIC* = `ADMFLAG_GENERIC`, *BAN* = `ADMFLAG_BAN`, *CONFIG* = `ADMFLAG_CONFIG`.

### Commands

**Core — `ajb.sp`**

| Command | Access | Purpose |
| --- | --- | --- |
| `sm_w`, `sm_ajb_w`, `sm_ajb_warden` | console | Claim warden / open warden menu |
| `sm_ajb_menu`, `sm_ajb_wm` | console | Open warden menu |
| `sm_ajb_uw`, `sm_ajb_unwarden` | console | Resign warden |
| `sm_ajb_open` | console | Open cell doors (warden or admin) |
| `sm_ajb_close` | console | Close cell doors (warden or admin) |
| `sm_markrebel`, `sm_ajb_markrebel` | console | Guard: Mark a prisoner as rebel (with cooldown) |
| `sm_ajb_balance` | GENERIC | Force JB team balance now (move excess guards to prisoners) |
| `sm_ajb_setwarden <#userid\|name>` | GENERIC | Set warden |
| `sm_ajb_rebel <#userid\|name> [0\|1]` | GENERIC | Mark/pardon rebel |
| `sm_ajb_doors_reload` | CONFIG | Reload per-map doors + teleports (`configs/ajb/maps/<map>.cfg`) |
| `sm_ajb_doors_list` | CONFIG | List configured door targetnames |
| `sm_ajb_gen_config` | CONFIG | (Re)generate the per-map config stub from live entities (overwrites) |

**Core — `ajb/core_freekill.sp`**

| Command | Access | Purpose |
| --- | --- | --- |
| `sm_ajb_freekill_punish` | console | Warden/admin: slay the flagged mass-freekill culprit |
| `sm_ajb_freekill_dismiss` | console | Warden/admin: dismiss the flagged event (false positive) |
| `sm_ajb_freekill` | console | Reopen the pending mass-freekill decision menu |

**Core — `ajb/core_settings.sp` / `ajb/core_weapons.sp`**

| Command | Access | Purpose |
| --- | --- | --- |
| `sm_ajb_settings_reload` | CONFIG | Reload `configs/ajb/settings.cfg` |
| `sm_ajb_prisoner_loadout_reload` | CONFIG | Reload `configs/ajb/prisoner_loadout.cfg` |

**Module — `ajb_admin.sp`**

| Command | Access | Purpose |
| --- | --- | --- |
| `sm_ajb`, `sm_ajb_admin` | GENERIC | Open AJB admin menu |
| `sm_ajb_status` | GENERIC | Print AJB live status |
| `sm_ajb_freeday <#userid\|name> [0\|1]` | GENERIC | Grant/revoke next-round freeday wish |
| `sm_ajb_clearwarden` | GENERIC | Clear the current warden |
| `sm_ajb_guardban <#userid\|name\|steamid64> [minutes] [reason]` | BAN | Guard-ban (0 min = permanent) |
| `sm_ajb_unguardban <#userid\|name\|steamid64>` | BAN | Remove guard ban |
| `sm_ajb_guardbans` | GENERIC | List active guard bans |

**Module — `ajb_boosts.sp`**

| Command | Access | Purpose |
| --- | --- | --- |
| `sm_boost`, `sm_boosts`, `sm_ajb_boosts` | console | Open the boosts menu |
| `sm_ajb_points` | console | Show your boost points |
| `sm_ajb_boosts_give <#userid\|name> <amount>` | GENERIC | Give boost points |

**Module — `ajb_lastrequest.sp`**

| Command | Access | Purpose |
| --- | --- | --- |
| `sm_ajb_lr` | console | Warden: grant Last Request to a prisoner |
| `sm_ajb_lr_force <#userid\|name>` | GENERIC | Force LR menu for a living prisoner |
| `sm_reopenlr`, `sm_ajb_reopenlr` | console | Prisoner: reopen your LR menu if a map vote / external menu closed it |

**Module — `ajb_ff2.sp`**

| Command | Access | Purpose |
| --- | --- | --- |
| `sm_ajb_ff2_status` | console | Print the FF2 wish dependency diagnosis (ff2r, bosses, subplugins) |

### ConVars

**Core — `ajb.sp`** (persisted to `cfg/sourcemod/ajb.cfg`)

| ConVar | Default | Purpose |
| --- | --- | --- |
| `sm_ajb_enabled` | `1` | Master switch for Another Jailbreak |
| `sm_ajb_force` | `0` | 1 = force AJB on even if map prefix does not match |
| `sm_ajb_guards_team` | `3` | Team index for guards (TF2 BLU = 3) |
| `sm_ajb_prisoners_team` | `2` | Team index for prisoners (TF2 RED = 2) |
| `sm_ajb_guard_ratio` | `2` | Prisoners per guard for balance cap (0 = disable) |
| `sm_ajb_cells_auto_open` | `0` | Seconds after round start before cells auto-open (0 = manual) |
| `sm_ajb_warden_auto` | `0` | 1 = auto-assign a random living guard as warden at preround end |
| `sm_ajb_warden_auto_delay` | `0` | Seconds to wait before auto-assigning warden (0–10) |
| `sm_ajb_warden_auto_mode` | `0` | 0 = uniform random, 1 = weighted anti-repetition |
| `sm_ajb_rebel_on_damage` | `1` | 1 = mark prisoner as rebel when they damage a BLU guard |
| `sm_ajb_rebel_on_warden_damage` | `1` | 1 = mark prisoner as rebel when they damage the warden (set this `1` + `sm_ajb_rebel_on_damage 0` to allow hitting BLU except the warden) |
| `sm_ajb_warden_rebel_control` | `1` | 1 = warden can mark/pardon RED rebels from menu |
| `sm_ajb_guard_mark_rebel_enabled` | `1` | 1 = allow guards to use /markrebel command to mark RED rebels |
| `sm_ajb_guard_mark_rebel_cooldown` | `30` | Cooldown in seconds between guard /markrebel uses |
| `sm_ajb_strip_prisoners` | `1` | 1 = strip prisoners to melee on spawn |
| `sm_ajb_block_buildings` | `0` | 1 = block Engineer buildings (see `sm_ajb_allow_sentry`) |
| `sm_ajb_block_prisoner_damage` | `1` | 1 = block non-rebel prisoner damage to guards |
| `sm_ajb_door_auto` | `1` | 1 = auto-detect door-like entities near RED spawn when config/name finds none |
| `sm_ajb_door_auto_radius` | `800` | Max distance (units) from a RED spawn for auto-door detection |
| `sm_ajb_gen_config_auto` | `1` | 1 = auto-generate `configs/ajb/maps/<map>.cfg` stub when none exists |
| `sm_ajb_prep_time` | `10` | Preparation seconds at round start (0 = off) |
| `sm_ajb_round_time` | `600` | Main round HUD duration in seconds (0 = no main clock) |

**Core fragments**

| ConVar | Default | File | Purpose |
| --- | --- | --- | --- |
| `sm_ajb_balance_enforce` | `1` | `core_balance.sp` | 1 = cap guards to ~1 per `sm_ajb_guard_ratio` prisoners once live |
| `sm_ajb_freekill_detect` | `1` | `core_freekill.sp` | 1 = detect/block crit splash wiping a cluster of prisoners in one frame |
| `sm_ajb_freekill_min_victims` | `3` | `core_freekill.sp` | Prisoners in blast that flag a mass-freekill attempt |
| `sm_ajb_freekill_radius` | `160.0` | `core_freekill.sp` | Radius (HU) scanned around victim to count endangered prisoners |
| `sm_ajb_freekill_decide_time` | `25` | `core_freekill.sp` | Seconds to punish a flagged event before auto-dismiss (0 = until round end) |
| `sm_ajb_allow_sentry` | `1` | `core_sentry.sp` | 1 = guards may build sentries even when buildings blocked |
| `sm_ajb_sentry_rebels_only` | `1` | `core_sentry.sp` | 1 = guard sentries only lock/damage rebel prisoners |
| `sm_ajb_ammo_arms_prisoners` | `1` | `core_weapons.sp` | 1 = map ammo packs arm melee-only prisoners (full class loadout) |
| `sm_ajb_block_death_ammo` | `1` | `core_weapons.sp` | 1 = delete player death ammo drops (`tf_ammo_pack`) |
| `sm_ajb_warden_see_health` | `1` | `core_warden_health.sp` | 1 = warden sees prisoner HP under crosshair |
| `sm_ajb_warden_marker` | `1` | `core_warden_marker.sp` | 1 = warden can place a 'Come here!' marker (beam ring + annotation) |
| `sm_ajb_warden_marker_time` | `8.0` | `core_warden_marker.sp` | Seconds a warden marker stays visible (2–30) |
| `sm_ajb_warden_vote` | `1` | `core_warden_votes.sp` | 1 = warden can start Yes/No and multiple-choice votes from the menu |
| `sm_ajb_warden_vote_time` | `20.0` | `core_warden_votes.sp` | Seconds a warden vote panel stays open (5–60) |
| `sm_ajb_warden_vote_audience` | `0` | `core_warden_votes.sp` | 0 = living prisoners (RED) only, 1 = all living players |
| `sm_ajb_warden_friendlyfire` | `1` | `core_friendlyfire.sp` | 1 = warden can toggle `mp_friendlyfire` from the warden menu (resets OFF each round) |
| `sm_ajb_ff_protect_guards` | `1` | `core_friendlyfire.sp` | 1 = guards cannot damage each other even while friendly fire is on |

**Module — `ajb_admin.sp`**

| ConVar | Default | Purpose |
| --- | --- | --- |
| `sm_ajb_admin_enabled` | `1` | Enable AJB admin menu |
| `sm_ajb_admin_db` | `ajb` | `databases.cfg` entry used to store guard bans |

**Module — `ajb_boosts.sp`**

| ConVar | Default | Purpose |
| --- | --- | --- |
| `sm_ajb_boosts_enabled` | `1` | Enable the boosts system |
| `sm_ajb_boosts_max_points` | `3` | Max points a player can earn-hold (0 = unlimited; admin grants ignore it) |
| `sm_ajb_boosts_blu_every` | `2` | BLU survivors get +1 extra every N finished rounds |

**Module — `ajb_lastrequest.sp`**

| ConVar | Default | Purpose |
| --- | --- | --- |
| `sm_ajb_lr_enabled` | `1` | Enable Last Request offers |
| `sm_ajb_lr_menu_time` | `30` | Seconds the prisoner has to pick an LR (5–90) |
| `sm_ajb_lr_suicide_delay` | `5` | Seconds before suicide LR kills the prisoner (1–30) |
| `sm_ajb_lr_hot_damage` | `8` | Damage per tick when Hot Reds touch a guard (1–100) |
| `sm_ajb_lr_low_gravity` | `200` | `sv_gravity` value for Low Gravity LR (stock 800) |
| `sm_ajb_lr_hs_hide_time` | `30` | Hide and Seek LR: seconds RED get to hide before frozen BLU seekers release (5–120) |
| `sm_ajb_lr_hs_round_time` | `300` | Hide and Seek LR: total round duration in seconds, hiders win on timeout (60–900) |
| `sm_ajb_lr_hg_grace_time` | `30` | Hunger Games: seconds after live round begin before friendly fire turns on (5–120) |
| `sm_ajb_lr_hg_round_time` | `300` | Hunger Games: total round duration in seconds, survivors win on timeout (60–900) |
| `sm_ajb_lr_zm_infect_delay` | `20` | Zombie Mode: seconds after live round begin before the first random zombie is chosen (5–60) |
| `sm_ajb_lr_zm_hits` | `2` | Zombie Mode: damaging hits from zombies required to infect a human (1–10) |
| `sm_ajb_lr_zm_respawn` | `5` | Zombie Mode: seconds before a dead zombie respawns (1–30) |
| `sm_ajb_lr_zm_spawn_protect` | `5` | Zombie Mode: invulnerability seconds after a zombie respawns (0–30) |
| `sm_ajb_lr_zm_round_time` | `300` | Zombie Mode: total round duration in seconds, humans win on timeout if any remain (60–900) |

**Module — `ajb_mutes.sp`**

| ConVar | Default | Purpose |
| --- | --- | --- |
| `sm_ajb_mute_enabled` | `1` | Enable AJB mute rules |
| `sm_ajb_mute_prisoners` | `1` | 1 = mute prisoners while jail round is active |
| `sm_ajb_mute_unmute_freeday` | `1` | 1 = do not mute freeday prisoners |
| `sm_ajb_mute_unmute_lr` | `1` | 1 = unmute when round enters Last Request |
| `sm_ajb_mute_deadtalk` | `1` | 1 = dead players heard only by each other, not the living |
| `sm_ajb_mute_deadtalk_crossteam` | `1` | 1 = all dead hear each other; 0 = only dead teammates |
| `sm_ajb_mute_bypass_flags` | `b` | Admin flag(s) that can always talk to/hear everyone (empty = nobody) |

**Module — `ajb_ff2.sp`** (persisted to `cfg/sourcemod/ajb_ff2.cfg`)

| ConVar | Default | Purpose |
| --- | --- | --- |
| `sm_ajb_ff2_enabled` | `1` | Enable the FF2 Boss Last Request wish |
| `sm_ajb_ff2_boss_team` | `3` | Team the boss fights for (2 = RED, 3 = BLU) |

**Module — `ajb_hud.sp`**

| ConVar | Default | Purpose |
| --- | --- | --- |
| `sm_ajb_hud_enabled` | `1` | Enable AJB HUD extras |
