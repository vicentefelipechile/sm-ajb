# Another Jailbreak (AJB)

TF2-native jailbreak mode for SourceMod.  
**All project sources live here** under `addons/sourcemod/projects/ajb/`.

## Layout

```
projects/ajb/
├── README.md
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

## Modules

| Plugin | Role |
|--------|------|
| `plugins/ajb.smx` | Core mode |
| `plugins/ajb_hud.smx` | HUD extras |
| `plugins/ajb_mutes.smx` | Prisoner mute rules |
| `plugins/ajb_lastrequest.smx` | Last Request (incl. Freeday-all / War Day wishes) |
| `plugins/ajb_admin.smx` | Admin menu |
| `plugins/ajb_boosts.smx` | Round points + boosts |
| `plugins/ajb_dummy.smx` | API smoke test (optional) |

## Conventions

- Author: **SummerTYT**
- Version ConVars: `sm_ajb_*_version`
- Phrases: shared `Prefix` key (`{1}`)
- Boosts ≠ store/shop/cosmetics
