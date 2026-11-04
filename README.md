# Another Jailbreak (AJB)

TF2-native jailbreak mode for SourceMod.  
**All project sources live here** under `addons/sourcemod/projects/ajb/`.

## Layout

```
projects/ajb/
├── README.md
├── build.ps1
├── deploy.ps1
├── plugins/                   # Compiled .smx (project output)
├── scripting/
│   ├── ajb.sp
│   ├── ajb/
│   ├── modules/
│   └── include/ajb/
├── translations/
└── configs/maps/
```

## Build output vs live server

| Path | Role |
|------|------|
| `projects/ajb/plugins/*.smx` | Compile output (kept in the project) |
| `addons/sourcemod/plugins/*.smx` | Live install (deploy copies here so the server loads them) |
| `translations/`, `configs/ajb/maps/` | Synced from the project on deploy |

## Build / deploy

From `addons/sourcemod`:

```powershell
# Compile → projects/ajb/plugins/ + copy to live plugins/ + sync assets
.\projects\ajb\deploy.ps1

# Compile only into projects/ajb/plugins/
.\projects\ajb\deploy.ps1 -CompileOnly

# Only sync translations/configs (no compile)
.\projects\ajb\deploy.ps1 -SyncOnly
```

Requires `scripting/spcomp.exe` (or `spcomp64.exe`) in this SourceMod tree.
`deploy.ps1` delegates compilation to `build.ps1`, also used by CI.

Global settings live in `configs/ajb/ajb_setting.cfg`. Deploy preserves existing settings.
When upgrading from a ZIP, preserve your server configuration instead of replacing it with defaults.

## Testing / GitHub releases

GitHub Actions compiles the core and every standalone module with the latest SourceMod 1.12.x
on pushes to `master`, PRs targeting it, and tags. A new tag publishes a GitHub release
only after compilation succeeds and its commit is verified as reachable from `master`.
The workflow must exist in the tagged commit. It uses the built-in `GITHUB_TOKEN`.
If the release already exists, the release Action uploads or replaces `ajb.zip` there.

`build.ps1 -Package` downloads current compile includes, builds into a temporary directory,
and creates `dist/ajb.zip` with fresh plugins, translations, gamedata and `configs/ajb/`.
For a standalone checkout, pass `-ScriptingPath C:/sourcemod-sdk/addons/sourcemod/scripting`.
Extract the ZIP into `tf/`; preserve local configs when upgrading. Runtime dependencies
are installed separately. To publish after pushing the workflow to `master`:

```sh
git tag -a v1.2.4 -m "Release v1.2.4"
git push origin v1.2.4
```

### SourceMod testing references

- [Compilation](https://wiki.alliedmods.net/Compiling_SourceMod_Plugins) checks SourcePawn;
  it does not test gameplay.
- [SourcePawn's regression suite](https://github.com/alliedmodders/sourcepawn#testing)
  tests the compiler/VM, not AJB.
- [SourceMod's mock tests](https://github.com/alliedmodders/sourcemod/blob/master/.github/workflows/mocktest.yml)
  use `hl2sdk-mock`; AJB requires the real TF2 engine for integration tests.
- [Official installation checks](https://wiki.alliedmods.net/Managing_your_SourceMod_installation#How_to_test_if_your_plugin_is_installed_correctly):
  run `sm plugins list`, `sm plugins info ajb` and `sm exts list` on a test server;
  inspect `logs/errors_*.log`. Use `sm_ajb_dummy_status` for the existing API smoke test,
  then exercise prep/live transitions, doors, LR, round cleanup and map changes in TF2.

## Modules

| Plugin | Role |
|--------|------|
| `plugins/ajb.smx` | Core mode |
| `plugins/ajb_hud.smx` | HUD extras |
| `plugins/ajb_mutes.smx` | Warden mutes + living/dead voice channels |
| `plugins/ajb_lastrequest.smx` | Last Request (incl. Freeday-all / War Day wishes) |
| `plugins/ajb_admin.smx` | Admin menu |
| `plugins/ajb_boosts.smx` | Round points + boosts |
| `plugins/ajb_ff2.smx` | FF2 Boss wish (optional; needs Freak Fortress 2 installed on the server) |
| `plugins/ajb_dummy.smx` | API smoke test (optional) |

## Voice channels and warden mutes

Open **Voice / mutes** from the warden menu or use `sm_ajb_mutes`. Only the current,
living warden can change a player's round-scoped mute. Selecting a dead player sets
the mute they will have on revival. Admin targets remain selectable so the warden
receives an explicit exemption message instead of silently failing.

Voice rules while AJB and `sm_ajb_mute_enabled 1` are active:

| Speaker | Living listener | Dead/spectator listener | Admin listener (`b` or root) |
| --- | --- | --- | --- |
| Living, not warden-muted | Heard | Heard | Heard |
| Living, warden-muted | Not heard | Not heard | Heard |
| Dead or spectating, regardless of stored warden mute | Not heard | Heard, across teams | Heard |
| Admin (`b` or root), alive or dead | Heard | Heard | Heard |

The admin exemption is mandatory, not a ConVar or command override. It applies to
both speech and hearing. Freeday, rebel, team and LR status never change mutes.
Death suspends the warden mute; revival restores it. Normal spawns refresh routing
after 0.1 seconds; revives without a spawn event and admin-flag changes are detected
within approximately 1.1 seconds, including after map changes. Dead Ringer is not death.

Warden death/resignation/replacement does not erase their mute decisions; the new
warden can change them. Round end/start, map changes, disconnects and mode/module
disable clear those decisions. Dead/living channels remain separate during postround.
Waiting/disabled AJB and module unload restore the game's normal voice routing.

AJB uses listener overrides, not BaseComm mutes. Administrative sanctions and players'
personal voice blocks take precedence, even for admins; AJB never removes them.
The former `sm_ajb_mute_prisoners`, `sm_ajb_mute_unmute_freeday`,
`sm_ajb_mute_unmute_lr`, `sm_ajb_mute_deadtalk`, `sm_ajb_mute_deadtalk_crossteam`
and `sm_ajb_mute_bypass_flags` settings are retired. Remove them from older
`cfg/sourcemod/ajb_mutes.cfg` files; only `sm_ajb_mute_enabled` remains.

Regression self-check: compile `scripting/tests/voice_policy.sp` with the same include
paths as the modules and load its output on a SourceMod test server. It checks all 32
voice-policy combinations and mandatory admin flags. In TF2, also verify death/revive,
warden replacement, round end/restart, slot reuse, map change, core unload/reload and
that a BaseComm mute survives all of those transitions. An old submenu must not apply
a decision after a round restart. These engine transitions require live testing.

## Cell Wars movement and camping

Jumping teleports a living RED player to a different spawn occupied by another living
human RED player. Empty destinations and the current cell are excluded; with no eligible
destination, jumping does not teleport, heal or reset the camping clock. This filters jump
teleports, not TF2's initial spawn placement.

| ConVar | Default | Effect |
| --- | --- | --- |
| `sm_ajb_lr_cw_teleport_delay` | `4.0` | Seconds between successful teleports; `0` removes the cooldown. |
| `sm_ajb_lr_cw_teleport_heal` | `10.0` | HP gained per successful teleport, capped at maximum health; `0` disables healing. |
| `sm_ajb_lr_cw_camp_time` | `20.0` | Seconds in one cell before camping damage; `0` disables it at mode start. |
| `sm_ajb_lr_cw_camp_damage` | `20.0` | Camping damage applied every second after the limit. |

These settings are persisted in `cfg/sourcemod/ajb_lastrequest.cfg`. Cells are approximated
by the nearest RED spawn within 300 units, not physical cell bounds. Walking beyond that
range does not suspend camping damage. Maps with several spawns per cell can still treat
those spawns as different cells and need map-specific bounds for exact detection.

Regression self-check: compile `scripting/tests/cellwars_destinations.sp` with the module
include paths and load it on a SourceMod test server. It checks all 80 occupancy/current-cell
combinations and an empty spawn list. In TF2, verify dead/BLU/bot exclusion, cooldown, capped
healing, no eligible destination, camping outside spawn range and round cleanup.

## FF2 Boss wish (`ajb_ff2`) — server requirements

`ajb_ff2` adds a "FF2 Boss" Last Request wish that runs the next live round as a Freak
Fortress 2 boss fight. It **requires Freak Fortress 2: Rewrite** to be installed on the
server; without it the wish appears disabled and nothing else changes. Install steps:

1. Download the **New Install Package** from
   [Freak-Fortress-2-Rewrite releases](https://github.com/Batfoxkid/Freak-Fortress-2-Rewrite/releases).
2. `freak_fortress_2.smx` → `addons/sourcemod/plugins/`; the `ff2r_*.smx` ability plugins →
   `addons/sourcemod/plugins/freaks/`.
3. Copy `translations/`, `gamedata/ff2.txt`, `data/freak_fortress_2/`,
   `configs/freak_fortress_2/` from the package, and `custom/ff2r_defaults` → `tf/custom/`
   (optional DLCs: Epic-Scout / Gray-Mann / Blitzkrieg).
4. Restart the server (or load the plugin + map change), then verify with `sm plugins list`
   and the `ff2` console command (should show `Status: Ready` on jailbreak maps).
5. In-game: `sm_ajb_ff2_status` prints the dependency diagnosis.

FF2's `maps.cfg` ships `"*" { "enable" "0" }`, so on jailbreak maps bosses are loaded but FF2
never takes over the round — that is what the wish relies on. Only bosses from the active
pack (`ff2_current`) appear in the picker. Missing ability subplugins degrade the boss
(spawns without rage/abilities); see `AGENTS.md` for the full dependency matrix.

## Conventions

- Author: **SummerTYT**
- Version ConVars: `sm_ajb_*_version`
- Phrases: shared `Prefix` key (`{1}`)
- Boosts ≠ store/shop/cosmetics
