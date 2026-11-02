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

## Testing / GitHub releases

GitHub Actions compiles the core and every standalone module with SourceMod 1.12.0.7260
on pushes to `master`, PRs targeting it, and tags. A new tag publishes a GitHub release
only after compilation succeeds and its commit is verified as reachable from `master`.
The workflow must exist in the tagged commit. It uses the built-in `GITHUB_TOKEN`.

`build.ps1 -Package` downloads pinned compile includes, builds into a temporary directory,
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
| `plugins/ajb_mutes.smx` | Prisoner mute rules |
| `plugins/ajb_lastrequest.smx` | Last Request (incl. Freeday-all / War Day wishes) |
| `plugins/ajb_admin.smx` | Admin menu |
| `plugins/ajb_boosts.smx` | Round points + boosts |
| `plugins/ajb_ff2.smx` | FF2 Boss wish (optional; needs Freak Fortress 2 installed on the server) |
| `plugins/ajb_dummy.smx` | API smoke test (optional) |

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
