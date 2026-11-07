# AGENTS.md — Another Jailbreak (AJB)

TF2-native jailbreak gamemode for SourceMod (SourcePawn). TF2 only — the core refuses to
load on any other engine (`AskPluginLoad2` checks `Engine_TF2`).

This file is the entry point for coding agents. The git repo root is `projects/ajb/`,
which lives inside a full SourceMod tree at `addons/sourcemod/`.

Keep `README.md` limited to installation, main commands and configuration. Internal
architecture, release procedures, gameplay edge cases and maintenance references belong here.

Limit validation work to compilation.

## Layout

```
projects/ajb/
├── README.md                  # short user-facing guide
├── build.ps1                  # compile / build release ZIP
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
├── configs/                   # settings, warden menu, prisoner loadout, per-map configs
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

### Plugin roles

| Plugin | Role |
| --- | --- |
| `plugins/ajb.smx` | Core mode |
| `plugins/ajb_hud.smx` | HUD extras |
| `plugins/ajb_mutes.smx` | Warden mutes + living/dead voice channels |
| `plugins/ajb_lastrequest.smx` | Last Request wishes, including Freeday-all / War Day |
| `plugins/ajb_admin.smx` | Admin menu and guard bans |
| `plugins/ajb_boosts.smx` | Round points + boosts |
| `plugins/ajb_ff2.smx` | Optional FF2 Boss wish; requires Freak Fortress 2 on the server |
| `plugins/ajb_dummy.smx` | Optional, read-only API diagnostics |

## Build & deploy

Requires `scripting/spcomp.exe` (or `spcomp64.exe`) in the SourceMod tree. Include dirs:
`scripting/include` and `projects/ajb/scripting/include`.

```powershell
# from addons/sourcemod
.\projects\ajb\deploy.ps1               # compile all → project plugins/ → live plugins/ + sync assets
.\projects\ajb\deploy.ps1 -CompileOnly  # compile into projects/ajb/plugins/ only
.\projects\ajb\deploy.ps1 -SyncOnly     # sync translations/configs/gamedata, no compile
```

Deploy syncs translations, per-map/dodgeball configs, prisoner_loadout/ajb_setting and
`gamedata/ajb.games.txt`; it prints a per-plugin SHA256 so a stale live `.smx` is obvious.
`deploy.ps1` delegates compilation to `build.ps1`, also used by CI. Project output stays in
`projects/ajb/plugins/`; the server loads the copies in `addons/sourcemod/plugins/`.

Global settings live in `configs/ajb/ajb_setting.cfg`. Deploy preserves existing settings.
When upgrading from a ZIP, preserve server configuration instead of replacing it with defaults.

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

### CI and GitHub releases

GitHub Actions compiles the core and every standalone module with the latest SourceMod 1.12.x
on pushes to `master`, PRs targeting it, and tags. A new tag publishes a GitHub release only
after compilation succeeds and its commit is verified as reachable from `master`. The workflow
must exist in the tagged commit. It uses the built-in `GITHUB_TOKEN`; an existing release has
its `ajb.zip` asset uploaded or replaced.

`build.ps1 -Package` downloads current `morecolors.inc` and `tf2attributes.inc` compile includes,
builds in a temporary directory, and creates `dist/ajb.zip` containing fresh plugins,
translations, gamedata and `configs/ajb/`. For a standalone checkout, pass
`-ScriptingPath C:/sourcemod-sdk/addons/sourcemod/scripting`. Extract the ZIP into `tf/`,
preserving local configs. Runtime dependencies are installed separately.

Release example, only when the user requests publication and the workflow is already on `master`:

```sh
git tag -a v1.2.4 -m "Release v1.2.4"
git push origin v1.2.4
```

## Conventions

- **English** for all code, comments, identifiers, log strings. Chat/translation strings
  may be Spanish/other via `translations/*.phrases.txt`.
- **Menu text is not chat text.** Keep interface labels brief, put shared context once in
  the title, and use names in player lists with short actions in submenus. Chat notices may
  contain full explanations; do not shorten them as part of a menu cleanup. When a phrase
  serves both, give the menu its own phrase instead of changing the chat output.
- Author: **SummerTYT**. Version ConVars: `sm_ajb_*_version`. Shared phrase helpers pass the
  `Prefix` key as `{1}`. Boosts are gameplay effects, not a store, shop or cosmetics system.
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

## Visibility boost and special-day cells

Guards can buy **Visibility** for 2 points (`sm_ajb_boosts_cost_visibility`). For 10 seconds,
living RED players have TF2's native X-ray outline (`m_bGlowEnabled`), visible to everyone.
Team changes and respawns refresh during the effect; overlapping purchases are refused.
Round/map boundaries, disable and unload remove outlines owned by the boost, preserving
outlines that were already enabled when it reached a player.

Boost purchases and ongoing effects are disabled for
Zombie Mode, Hunger Games, Cell Wars, Hide and Seek, Dodgeball, War Day, Class Warfare,
and FF2. The module blocks `SpecialDay`/combat rounds; stale menus cannot bypass the block.
Stored points stay intact, and boosts resume next normal round. Normal-round modifiers
(including Sniper) and freedays keep boosts enabled.

At special-round end, living participants or members of the winning team earn +1 boost point,
once per player/round, respecting `sm_ajb_boosts_max_points`. Dead winners qualify in team
events; Hunger Games and Cell Wars reward only survivors, not eliminated nominal teammates.
The win hook runs before round cleanup so temporary event teams and FF2 survivors are still
intact. Bots and spectators earn nothing. Purchases remain blocked until the next normal round.
Normal rounds retain +1 for survivors and the periodic guard bonus; special rounds do not
advance that bonus counter or grant an extra guard bonus. Disabled boosts/AJB grant no rewards.

Ten seconds after live-round wishes apply, the core checks special days/freeday-all that
requested open cells. It reads physical door state and reopens only doors that are not fully
open, without changing the round state, repeating chat or pressing map buttons/relays.
Explicit close requests (including Cell Wars) opt out. Verification supports `func_door`,
`func_door_rotating`, `prop_door_rotating` and `func_movelinear`; custom brush/relay-only
setups need identifiable physical door targets for verification.

## Database

`ajb_admin` (guard bans) uses SQL via `configs/databases.cfg`. The entry name comes from
`sm_ajb_admin_db` (default `ajb`); the repo ships an `ajb` SQLite entry. If that entry is
missing, `AJB_DB_Connect` falls back to the stock `storage-local` SQLite entry. The table
(`ajb_guardbans`) is created portably for SQLite or MySQL.

## Dodgeball visual setup

Dodgeball applies `airblast cost decreased 0` and `airblast_pushback_disabled 1` to each
prepared flamethrower through optional TF2Attributes. Rocket deflection is unchanged;
previous runtime attributes are restored on respawn, disconnect and wish cleanup.
Without TF2Attributes, it logs the missing dependency and retains the ammo refill timer.

During Dodgeball, the shared player damage hook blocks player-sourced flame and afterburn
damage without requiring TF2Attributes. Airblast, rocket damage, arena barrier damage and
map hazards keep their existing behavior; other wishes are unaffected.

Open `!ajb` → **Dodgeball**, or `sm_ajb_db_menu`. Requires admin + config access and the
Last Request module; no wish needs to be running. The editor lives in
`modules/lastrequest/wish_dodgeball_editor.sp`, included by `ajb_lastrequest.sp`.

- RED/BLU spawns are placed at the admin's feet. Rocket placement opens **Ceiling** / **Eyes**.
- **Arena** contains center/bottom placement and **Increase range** / **Decrease range**
  buttons (128 units per press). Enabled menu sizes stay within 128–8192 units.
- **No barriers** disables boundary visuals and damage. Increasing restores the default
  1500-unit radius. Shared radius rules live in `include/ajb/dodgeball.inc`.
- Colored spawn markers and the actual amber arena geometry are sent only to the editing
  admin throughout the Dodgeball menus. Back, Exit, another menu, disconnect, map end and
  module unload stop the preview; short-lived effects expire without leaving entities behind.
- Every action saves to `configs/ajb/dodgeball/<map>.cfg`; incomplete setups show missing
  spawns. Existing configs remain compatible, including spawn coordinates `0 0 0`.
  Missing keys, not zero-length vectors, mean an incomplete setup.
- Without an explicit center, the rocket position remains the legacy center/bottom fallback.
- Ceiling placement sweeps an 8-unit half-size hull upward to the first obstruction,
  including grates, glass, props and moving brushes. It backs off 24 units and checks free
  space again; an obstructed placement is refused rather than traced through to another roof.
- During a live Dodgeball round the editor is preview-only. Saves are also rejected
  server-side, including selections from menus opened before the round became live.

`sm_ajb_db_setspawn <red|blu|rocket|center> [radius]` remains available. Rocket placement uses
eye position; center without a radius preserves the existing range. Radius `0` means no barriers.
Exports use a temporary file before replacing the config; unreadable configs are not overwritten.

## Equal teams for combat events

War Day, Class Warfare and Dodgeball balance connected RED/BLU participants (including bots)
once at live-round start, before applying event classes, loadouts and teleports. Random players
from the larger team move until the difference is at most one (e.g. 10 RED / 5 BLU → 8 / 7).
There is no mid-round rebalancing for deaths, departures or late joins, and no balance ConVar.
Other wishes, including Zombies, FF2, Hide and Seek and free-for-all modes, retain their roles.

`AJB_LR_UsesEqualTeams` in `include/ajb/lrwish.inc` owns the wish list. Shared utilities in
`include/ajb/teams.inc` use safe spectator transit and respawn only previously living players.
Dead players remain dead; spectators are excluded. Cleanup restores moved participants' original
teams on round end/restart, map end, disable, core removal or LR unload; players who opted into
spectator are not forced back. Disconnect clears the saved team so client slot reuse is safe.
Guard bans remain stored but are suspended for these three wishes, then enforced normally again.

## Watch out! Sniper crouch rules

Sniper remains a normal-round modifier: it does not change cells, teams or boost availability.
Every `sm_ajb_lr_sniper_min`–`sm_ajb_lr_sniper_max` seconds it selects one living human from
either team. Standing targets have `sm_ajb_lr_sniper_hit_chance` percent chance of a critical
bullet hit; crouched targets always dodge. Headshots use 50 base damage with TF2's native 3x
critical multiplier (150 before defenses), not forced lethal damage. Overheal, Dead Ringer,
invulnerability, resistances and damage hooks can allow survival. Misses still play the gunshot
and announce the miss; hit notices do not claim the target died.

After `sm_ajb_lr_sniper_duck_time` continuous seconds crouched, actually standing up triggers
one non-critical body shot for `sm_ajb_lr_sniper_body_damage` base damage, independent of the
random shot timer/chance. Short ducks do not trigger it. Physical crouch state is checked
after movement commands, so releasing duck under a low ceiling does not count as standing.
Death, spawn, disconnect and wish cleanup clear the stored crouch time.

## Zombie Mode team changes

After the infection grace period, losing the last connected zombie automatically infects a
random living RED human. Dead BLU zombies waiting to respawn still count, so killing one does
not infect an extra human. Joining BLU gives the zombie loadout and normal zombie respawn.
During grace, its end must not infect another human if a zombie already exists.

Player-caused infections of living humans send a client-only `player_death` notice with
the infecting zombie as attacker and the fists icon. This adds a killfeed entry without
server death hooks or real kill/death statistics. Lethal hits retain their existing death
notice; patient zero and automatic replacements do not generate fake kills.

AJB guard bans remain stored but do not block the zombie role; enforcement resumes when the
wish ends or Last Request unloads. With no living humans, zombies win instead of attempting
to select from an empty list.

### Zombie ambience

`modules/lastrequest/wish_zombie_ambience.sp` owns temporary per-player fog and optional
music. Fog starts during grace, is reapplied after spawn and to late spectators, and restores
the saved map controller on end, abort, disable, map change or unload. It does not replace
the map's master controller or overwrite another controller that the map selected meanwhile.
Fog ConVar changes apply immediately; RGB components must be 0–255 and fog end must exceed start.

Music has only `sm_ajb_lr_zm_music`: an MP3/WAV path relative to `tf/sound/`; empty means
silence and immediately stops current playback. Missing/invalid files are logged and skipped.
Preparation runs after AutoExecConfig so the saved path is registered for download and precached.
Owners supply the audio and FastDL; new assets need reconnect/map change for client downloads.
Each client hears the track once per round, without restarting on respawn; WAV loop points can
provide native looping. No duration parser, unsafe `GetSoundDuration`, music timer, volume ConVar
or duration ConVar is used. Cleanup stops the sound and preserves the infection killfeed and Dodgeball fixes.

## Cell Wars movement and camping

Jumping teleports a living RED player to a different spawn occupied by another living human
RED player. Dead/BLU/bot occupants, empty destinations and the current cell are excluded.
With no eligible destination, jumping does not teleport, heal or reset the camping clock.
This filters jump teleports, not TF2's initial spawn placement.

`sm_ajb_lr_cw_teleport_delay`, `sm_ajb_lr_cw_teleport_heal`, `sm_ajb_lr_cw_camp_time` and
`sm_ajb_lr_cw_camp_damage` are persisted in `cfg/sourcemod/ajb_lastrequest.cfg`; defaults and
bounds are in the ConVar reference below. Delay `0` removes the cooldown; heal `0` disables
healing; camp time `0` disables camping damage. Healing is capped at class maximum HP.

Cells are approximated by the nearest RED spawn within 300 units, not physical cell bounds.
Walking beyond that range does not suspend camping damage. Maps with several spawns per
cell can treat those spawns as different cells and need map-specific bounds for exact detection.

## Voice channels and warden mutes

Open **Voice** from the warden menu or use `sm_ajb_mutes`. The list shows player names;
selecting one opens **Mute** / **Unmute**, with status and round scope in the title. Only the
current, living warden may change the decision. For dead players, it applies on revival.
Admin targets remain selectable so the warden receives an explicit exemption message.

Voice policy lives in `include/ajb/voice.inc`. While AJB and `sm_ajb_mute_enabled 1` are active:

| Speaker | Living listener | Dead/spectator listener | Admin listener (`b` or root) |
| --- | --- | --- | --- |
| Living, not warden-muted | Heard | Heard | Heard |
| Living, warden-muted | Not heard | Not heard | Heard |
| Dead or spectating, regardless of stored warden mute | Not heard | Heard, across teams | Heard |
| Admin (`b` or root), alive or dead | Heard | Heard | Heard |

The admin exemption is mandatory, not a ConVar or command override, and applies to both
speech and hearing. BaseComm and personal mutes still take precedence, even for admins.
AJB uses listener overrides and never changes or removes BaseComm mute state.

Freeday, rebel, team and LR changes do not alter warden decisions. Death suspends the mute;
revival restores it. Normal spawns refresh routing after 0.1 seconds; revives without spawn
events and admin-flag changes are detected within approximately 1.1 seconds. Dead Ringer
is not death.

Warden death, resignation or replacement does not erase decisions; the new warden can change
them. Round boundaries, map changes, disconnects and mode/module disable clear them.
Postround retains the living/dead split; waiting/disabled AJB and module unload restore
normal game routing. A stale submenu must not apply a decision after a round restart.

The former `sm_ajb_mute_prisoners`, `sm_ajb_mute_unmute_freeday`, `sm_ajb_mute_unmute_lr`,
`sm_ajb_mute_deadtalk`, `sm_ajb_mute_deadtalk_crossteam` and `sm_ajb_mute_bypass_flags`
ConVars are retired. Remove them from older `cfg/sourcemod/ajb_mutes.cfg` files; only
`sm_ajb_mute_enabled` remains.

## Cloak and role visuals

The overhead Warden label is sent only to other human players, never to the warden;
TF2 otherwise renders their own label as an offscreen arrow at the edge of their HUD.

While `TFCond_Cloaked` is active (including Dead Ringer), the overhead Warden label and
orange rebel glow are hidden. Condition callbacks hide them immediately and restore them
on decloak only if the living player still holds the role. Claiming warden or marking a
rebel during cloak cannot reveal them; the rebel FX timer also respects cloak. This follows
the full cloak duration, not the shorter Dead Ringer damage-resistance condition.

The Warden label also stays hidden while `TFCond_Disguised` is active. Removing one condition
does not reveal it while the other is still active; disguise does not hide the rebel glow.

Living guard Spies with the Dead Ringer (item 59) recharge at twice their native rate.
A post-think hook mirrors positive cloak-meter gains, capped at 100, without changing cloak
drain or other watches. The bonus stops for prisoners, death or disabled AJB and needs no
TF2Attributes dependency. Resupply still fills the meter normally.

Prisoners hitting guard Spies actively disguised as the prisoners' team are not automatically
marked rebel and may damage them without a rebel mark, including hits that trigger Dead Ringer.
Guards disguised as their own team, undisguised guards and incomplete disguises retain the
normal rebel-on-hit policy. Existing rebel marks are never cleared by this exemption, and
prep damage protection remains intact. `AJB_ClientDisguisedAsPrisoner` in `core_teams.sp` owns
the disguise check; the damage hook snapshots it through `player_hurt` so fatal hits that
remove a disguise cannot retroactively mark the attacker. The snapshot clears after damage.

## Spectator cameras

While AJB is active, the core sets `mp_forcecamera 0` so dead players can follow either
team. The previous value is restored when AJB is disabled, the map ends or the core unloads.

## Friendly fire and locked cells

After prep, enabling `mp_friendlyfire` allows prisoner-versus-prisoner damage even while the
round remains `CellsLocked`; closed-cell protection must not override the warden's toggle.
Prep still blocks player-versus-player damage. Guard-versus-guard protection remains controlled
by `sm_ajb_ff_protect_guards`, independent of friendly fire.

## Guard sentries and Wrangler

With `sm_ajb_sentry_rebels_only 1`, automatic guard sentries only target and damage rebel
prisoners. A disguise matching the sentry's team prevents acquiring a new target, but does
not break an existing lock; another player becoming rebel must not clear that lock either.
Invisibility breaks tracking, including Dead Ringer cloak and spell stealth conditions.
This only blocks automatic targeting, not incidental damage from shots already fired.
Wrangler control uses native aiming and can damage non-rebel prisoners, subject
to the normal AJB damage rules (including prep, personal freedays and freekill protection).
`AJB_Sentry_IsReady` leaves native `FindTarget` running when the builder equips
`tf_weapon_laser_pointer`, during manual control and throughout the native shield recovery
delay. Rebel changes must not interrupt these states. Sentry rockets snapshot manual control
at spawn, so holstering the Wrangler before impact does not change their damage policy.
Snapshots store entity references to prevent stale entries after entity slot reuse.

## Auto-warden

At preround end (`AJB_ScheduleAutoWarden`), if `sm_ajb_warden_auto 1` and no warden is set,
one is picked after `sm_ajb_warden_auto_delay` seconds (0–10). `sm_ajb_warden_auto_mode`
selects the picker: `0` = uniform random (`AJB_PickRandomAliveOnTeam`), `1` = weighted by
anti-repetition (`AJB_PickWeightedWardenGuard`), favoring guards who have not been warden
recently. `g_iWardenRoundSerial` ticks per round; `g_iWardenLastRound[client]` is stamped in
`AJB_SetWarden` and reset in `OnClientPutInServer`.

## Passive warden dismissal

`sm_firewarden` / `sm_firew` record one passive vote per human prisoner (alive or dead).
No vote menu is opened; reaching `ceil(human prisoners * sm_ajb_firewarden_ratio)` clears
the current warden through `AJB_ClearWarden`. Another guard can claim the empty slot normally.
The fired warden cannot be assigned or claim again until the next round.

Votes reset on warden changes, round/map boundaries, disconnect and team changes. Population
and threshold are counted on each command (without duplicating votes); departures alone never fire the warden.
`sm_ajb_firewarden_cooldown` starts only on success and survives warden changes and new rounds;
map changes and core reloads reset it. Ratio bounds are 0.01–1; cooldown 0 disables the wait.
Dismissal locks follow the client session; reconnecting clears them.

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
| `ff2r` library (`freak_fortress_2.smx`) | **Blocked** | Module loads; menu item disabled (label "Unavailable"). Nothing else changes. |
| Bosses precached (`FF2R_GetGamemodeType() < 1`) | **Blocked** | FF2 loaded but no charset/boss pack (e.g. `characters.cfg` missing or a map entry with `enable -1`); item disabled. |
| Ability subplugins (`plugins/freaks/`) | **Degraded** | Boss spawns with model/weapons/health/sounds/HUD but **no rage/abilities** (they live in `ff2r_*_abilities.smx`). Chat warning on apply. |
| TF2Items / TF2Attributes / TF2Utils | **Degraded** | FF2 falls back internally (fewer weapon attributes, no ability lag comp). |

`morecolors.inc` is a compile-time include used by the shared phrase helpers, not a separate plugin.

Server install (owner side, FF2 not shipped by AJB): New Install Package from
`Batfoxkid/Freak-Fortress-2-Rewrite` releases → `freak_fortress_2.smx` in `plugins/`, the
`ff2r_*.smx` ability plugins in `plugins/freaks/` (FF2 renames them to `.ff2` while idle),
plus `translations`, `gamedata/ff2.txt`, `data/freak_fortress_2/`, `configs/freak_fortress_2/`
and `custom/ff2r_defaults` → `tf/custom/`. FF2's `data/.../maps.cfg` ships `"*" { "enable" "0" }`,
so on jailbreak maps bosses are precached but FF2 never runs the gamemode — exactly what the
loader needs. Only bosses of the active pack (`ff2_current` / pack vote) appear in the picker.

Owner installation reference:

1. Download the **New Install Package** from
   [Freak-Fortress-2-Rewrite releases](https://github.com/Batfoxkid/Freak-Fortress-2-Rewrite/releases).
2. Install the plugin, ability subplugins, translations, gamedata, data, configs and custom
   assets at the paths above. Optional DLCs include Epic-Scout, Gray-Mann and Blitzkrieg.
3. Restart the server, or load the plugin and change the map. `sm plugins list` and `ff2`
   expose its state; `ff2` should show `Status: Ready` on jailbreak maps.
4. `sm_ajb_ff2_status` prints AJB's dependency diagnosis. Missing ability subplugins leave
   the boss without rage/abilities rather than preventing it from spawning.

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
| `sm_firewarden`, `sm_firew` | console | Prisoner: passively vote to dismiss the current warden |
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

**Core — `ajb/core_warden_menu.sp`** (configurable warden menu)

| Command | Access | Purpose |
| --- | --- | --- |
| `sm_ajb_menu_reload` | CONFIG | Reload `configs/ajb/warden_menu.cfg` (also reloads each map start) |
| `sm_ajb_marker` | console | Warden/admin: place the 'come here' marker at the crosshair |
| `sm_ajb_collisions` | console | Warden/admin: toggle teammate push |
| `sm_ajb_friendlyfire` | console | Warden/admin: toggle friendly fire |
| `sm_ajb_vote_yesno` | console | Warden: start a Yes/No vote |
| `sm_ajb_vote_multi` | console | Warden: start a multiple-choice vote |
| `sm_ajb_warden_markrebel` | console | Warden: mark a prisoner as rebel (pick list) |
| `sm_ajb_warden_pardonrebel` | console | Warden: pardon a rebel (pick list) |
| `sm_ajb_menu_next` / `sm_ajb_menu_prev` | console | Warden: warden menu page navigation |

The warden menu layout is data-driven from `configs/ajb/warden_menu.cfg`
(KeyValues, synced by deploy.ps1; missing file → built-in two-page menu, identical
layout to the shipped default). First-level keys are pages (shown as `── name ──`
headers); each entry is `"label" "command"`. Empty command value = un-numbered text
line (free slot); `phrase:` label prefix = translation lookup; a page holds at most
8 numbered actions (Panel keys 1–8, extra dropped with a log); exit is always key 0/10.
Key 9 is reserved for next-page navigation and cycles from the last page to the first;
with only one page, key 9 is unused. Configured `sm_ajb_menu_next`/`sm_ajb_menu_prev`
entries are ignored so they cannot move or duplicate the fixed navigation button.
Both commands remain available for binds; `sm_ajb_menu_next` also cycles at the last page.
Items whose feature ConVar is off are hidden (marker/collisions/friendlyfire/votes/
rebel control). On select the command runs as the warden via `FakeClientCommandEx`
and the menu reopens, except for the screen-owning commands (`sm_ajb_lr` → fires the
`AJB_OnWardenGiveLR` forward, `sm_ajb_uw`, votes, rebel picks, page nav). Dead warden
may only run `sm_ajb_uw`/`sm_ajb_collisions`/`sm_ajb_friendlyfire`/page nav.

**Core — `ajb/core_freekill.sp`**

| Command | Access | Purpose |
| --- | --- | --- |
| `sm_ajb_freekill_punish` | console | Warden/admin: slay the flagged mass-freekill culprit |
| `sm_ajb_freekill_dismiss` | console | Warden/admin: dismiss the flagged event (false positive) |
| `sm_ajb_freekill` | console | Reopen the pending mass-freekill decision menu |

**Core — `ajb/core_settings.sp` / `ajb/core_weapons.sp`**

| Command | Access | Purpose |
| --- | --- | --- |
| `sm_ajb_settings_reload` | CONFIG | Reload `configs/ajb/ajb_setting.cfg` |
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
| `sm_ajb_db_menu` | CONFIG | Open the private visual Dodgeball map editor |
| `sm_ajb_db_setspawn <red\|blu\|rocket\|center> [radius]` | CONFIG | Save a Dodgeball point; radius `0` disables barriers |

**Module — `ajb_mutes.sp`**

| Command | Access | Purpose |
| --- | --- | --- |
| `sm_ajb_mutes` | console | Living warden: manage round-scoped player mutes; admins (`b`/root) are always exempt |

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
| `sm_ajb_firewarden_ratio` | `0.75` | Fraction of human prisoners needed to dismiss the warden (0.01–1, rounded up; living/dead) |
| `sm_ajb_firewarden_cooldown` | `60` | Seconds after a successful dismissal before votes are accepted again (0 = no wait) |
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
| `sm_ajb_sentry_rebels_only` | `1` | `core_sentry.sp` | 1 = automatic guard sentries only lock/damage rebel prisoners; Wrangler allows manual enemy damage |
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
| `sm_ajb_boosts_cost_visibility` | `2` | Guard boost: native X-ray outlines on living RED players for 10 seconds |

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
| `sm_ajb_lr_zm_fog_enabled` | `1` | Zombie Mode: enable temporary fog |
| `sm_ajb_lr_zm_fog_color` | `22 48 18` | Zombie Mode: fog RGB color, each component 0–255 |
| `sm_ajb_lr_zm_fog_start` | `48` | Zombie Mode: fog start distance in units (≥0) |
| `sm_ajb_lr_zm_fog_end` | `1300` | Zombie Mode: fog end distance in units, must exceed start |
| `sm_ajb_lr_zm_fog_density` | `0.88` | Zombie Mode: maximum fog density (0–1) |
| `sm_ajb_lr_zm_music` | empty | Zombie Mode: MP3/WAV path relative to sound/, empty disables music |
| `sm_ajb_lr_sniper_min` | `10.0` | Sniper: minimum seconds between random shots (2–300) |
| `sm_ajb_lr_sniper_max` | `25.0` | Sniper: maximum seconds between random shots (5–600, clamped to minimum at runtime) |
| `sm_ajb_lr_sniper_force` | `800.0` | Sniper: impact/ragdoll force (100–3000) |
| `sm_ajb_lr_sniper_hit_chance` | `50.0` | Sniper: critical hit chance (%) for the selected standing target; crouching always dodges (0–100) |
| `sm_ajb_lr_sniper_duck_time` | `3.0` | Sniper: continuous crouch seconds before standing triggers a body shot (0.1–30) |
| `sm_ajb_lr_sniper_body_damage` | `50.0` | Sniper: non-critical body shot base damage after a prolonged crouch (1–500) |
| `sm_ajb_lr_cw_round_time` | `300` | Cell Wars: total round duration in seconds, survivors win on timeout (60–900) |
| `sm_ajb_lr_cw_teleport_delay` | `4.0` | Cell Wars: seconds between jump teleports (0 = no cooldown) (0–30) |
| `sm_ajb_lr_cw_camp_time` | `20` | Cell Wars: seconds in the same cell before camping damage starts (0 = disabled, ≤120) |
| `sm_ajb_lr_cw_camp_damage` | `20` | Cell Wars: camping damage per second while in the same cell past camp_time (1–100) |
| `sm_ajb_lr_cw_teleport_heal` | `10` | Cell Wars: HP restored on every jump teleport, capped at class max (0 = disabled) (0–100) |

**Module — `ajb_mutes.sp`**

| ConVar | Default | Purpose |
| --- | --- | --- |
| `sm_ajb_mute_enabled` | `1` | Enable warden mutes and fixed living/dead voice channels |

See **Voice channels and warden mutes** above for the channel matrix, admin exemption,
round-scoped decisions, BaseComm precedence and retired ConVars.

**Module — `ajb_ff2.sp`** (persisted to `cfg/sourcemod/ajb_ff2.cfg`)

| ConVar | Default | Purpose |
| --- | --- | --- |
| `sm_ajb_ff2_enabled` | `1` | Enable the FF2 Boss Last Request wish |
| `sm_ajb_ff2_boss_team` | `3` | Team the boss fights for (2 = RED, 3 = BLU) |

**Module — `ajb_hud.sp`**

| ConVar | Default | Purpose |
| --- | --- | --- |
| `sm_ajb_hud_enabled` | `1` | Enable AJB HUD extras |
