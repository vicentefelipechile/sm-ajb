# Another Jailbreak (AJB)

TF2 jailbreak gamemode for SourceMod: warden, prisoners, rebels, Last Requests and boosts.

## Installation

Requires TF2 and SourceMod. Extract the release ZIP into `tf/`, preserving existing configs.
The FF2 Boss wish additionally requires [Freak Fortress 2: Rewrite](https://github.com/Batfoxkid/Freak-Fortress-2-Rewrite/releases).
Install [TF2Attributes](https://github.com/FlaminSarge/tf2attributes) for Dodgeball airblasts without ammo cost or player pushback.

To build and deploy from `addons/sourcemod`:

```powershell
.\projects\ajb\deploy.ps1
```

Requires `scripting/spcomp.exe` or `spcomp64.exe`. Use `-CompileOnly` to compile without deploying,
or `-SyncOnly` to copy configuration, translations and gamedata without compiling.

## Commands

| Command | Purpose |
| --- | --- |
| `!w` | Claim warden / open warden menu |
| `!firewarden`, `!firew` | Prisoner: add a passive vote to dismiss the current warden |
| `!ajb` | Admin menu |
| `!ajb_mutes` | Warden voice menu: player → mute / unmute |
| `!ajb_lr` | Warden: grant a Last Request |
| `!lastrequest` | Everyone: browse wishes and toggle a saved preferred wish marked `[X]` |
| `!reopenlr` | Reopen your Last Request menu |
| `!boosts` | Boosts menu |

The preferred wish is selected when you receive Last Request; extra options still use their
normal submenus. Preferences use SourceMod's Client Preferences cookies (`clientprefs` required).

**Dodgeball:** `!ajb` → **Dodgeball**. Set team spawns, rocket position and arena range with a
private preview. Changes save automatically. Requires admin + config access; live rounds are read-only.

**Teleports:** `!ajb` → **Teleports**. Save or remove the current map's Freeday and combat
RED/BLU destinations. Saving uses your position and facing direction; you must be alive.

**Settings:** `!ajb` → **Configuration**. Adjust rounds, teams, warden, Freeday, wishes and
boosts. Both editors require admin + config access and save changes automatically.

**Doors:** `!ajb` → **Doors**. Select a door by aiming or from the entity list, then include,
exclude or restore automatic detection. **Show markers** uses private TF2 tutorial callouts
for detected doors, or the selected entity in its submenu. Changes save per map; named
selections cover all entities sharing that name, with Hammer ID used for unnamed entities.

## Configuration

Paths relative to `addons/sourcemod`:

- `configs/ajb/ajb_setting.cfg` — mode settings.
- `configs/ajb/warden_menu.cfg` — warden menu layout.
- `configs/ajb/prisoner_loadout.cfg` — prisoner loadouts.
- `configs/ajb/maps/` — map doors and teleports.
- `configs/ajb/dodgeball/` — Dodgeball arenas.

ConVars are saved under `tf/cfg/sourcemod/ajb*.cfg`.

The point bank persists by SteamID64 using `configs/databases.cfg` entry `ajb` (fallback:
`storage-local`). In `tf/cfg/sourcemod/ajb_boosts.cfg`, `sm_ajb_boosts_bank_max_points "30"`
sets its deposit limit; excess is discarded when full. Savings refill available points at
the next round start, without replacing unspent points. Unspent points move into the bank on
map changes, disconnects and module unloads, subject to its configured limit.

**Escape from the Yeti (Freeze Tag)** is included in the Last Request menu. Configure it with
`sm_ajb_lr_yeti_*` in `tf/cfg/sourcemod/ajb_lastrequest.cfg` (default: 300-second round, 20 seconds to hide).

Passive warden dismissal is configured in `tf/cfg/sourcemod/ajb.cfg`:

```cfg
sm_ajb_firewarden_ratio "0.75"
sm_ajb_firewarden_cooldown "60"
```

The ratio is a fraction (`1` = 100%) of human prisoners, alive or dead, rounded up.
The cooldown starts only after a successful dismissal, not after individual votes.

Zombie Mode ambience is configured in `tf/cfg/sourcemod/ajb_lastrequest.cfg`:

```cfg
sm_ajb_lr_zm_fog_enabled "1"
sm_ajb_lr_zm_fog_color "22 48 18"
sm_ajb_lr_zm_fog_start "48"
sm_ajb_lr_zm_fog_end "1300"
sm_ajb_lr_zm_fog_density "0.88"
sm_ajb_lr_zm_music ""
```

An empty music path disables playback. To use music, set a path relative to `tf/sound/`,
for example `"ajb/zombies.mp3"`, and install that MP3/WAV on the server and FastDL.
Change the map or reconnect players after adding custom audio so they can download it.
Music plays once per round; looping WAV files can use their embedded loop points.

Author: **SummerTYT**

Yeti wish author: **Winewald**
