# Another Jailbreak (AJB)

TF2 jailbreak gamemode for SourceMod: warden, prisoners, rebels, Last Requests and boosts.

## Installation

Requires TF2 and SourceMod. Extract the release ZIP into `tf/`, preserving existing configs.
The FF2 Boss wish additionally requires [Freak Fortress 2: Rewrite](https://github.com/Batfoxkid/Freak-Fortress-2-Rewrite/releases).

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
| `!ajb` | Admin menu |
| `!ajb_mutes` | Warden voice menu: player → mute / unmute |
| `!ajb_lr` | Warden: grant a Last Request |
| `!reopenlr` | Reopen your Last Request menu |
| `!boosts` | Boosts menu |

**Dodgeball:** `!ajb` → **Dodgeball**. Set team spawns, rocket position and arena range with a
private preview. Changes save automatically. Requires admin + config access; live rounds are read-only.

## Configuration

Paths relative to `addons/sourcemod`:

- `configs/ajb/ajb_setting.cfg` — mode settings.
- `configs/ajb/warden_menu.cfg` — warden menu layout.
- `configs/ajb/prisoner_loadout.cfg` — prisoner loadouts.
- `configs/ajb/maps/` — map doors and teleports.
- `configs/ajb/dodgeball/` — Dodgeball arenas.

ConVars are saved under `tf/cfg/sourcemod/ajb*.cfg`.

Author: **SummerTYT**
