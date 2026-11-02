# =========================================================================================================
# Another Jailbreak — compile + deploy
# =========================================================================================================
# Usage (from addons/sourcemod):
#   .\projects\ajb\deploy.ps1
#   .\projects\ajb\deploy.ps1 -CompileOnly
#   .\projects\ajb\deploy.ps1 -SyncOnly
#
# Compile output:  projects/ajb/plugins/*.smx
# Live install:    addons/sourcemod/plugins/*.smx  (copy from project plugins/)
# =========================================================================================================

param(
    [switch]$CompileOnly,
    [switch]$SyncOnly
)

$ErrorActionPreference = "Stop"

# deploy.ps1 lives at projects/ajb/deploy.ps1
$AjbRoot = $PSScriptRoot
$SmRoot = Split-Path -Parent (Split-Path -Parent $AjbRoot)

$ProjPlugins = Join-Path $AjbRoot "plugins"
$LivePlugins = Join-Path $SmRoot "plugins"
$TransDir = Join-Path $SmRoot "translations"
$CfgMaps = Join-Path $SmRoot "configs\ajb\maps"
$CfgAjb = Join-Path $SmRoot "configs\ajb"
$CfgDb = Join-Path $CfgAjb "dodgeball"
$GamedataDir = Join-Path $SmRoot "gamedata"

function Sync-Assets {
    Write-Host "Syncing translations..."
    Copy-Item -Force (Join-Path $AjbRoot "translations\*.phrases.txt") $TransDir

    Write-Host "Syncing map configs..."
    Copy-Item -Force (Join-Path $AjbRoot "configs\maps\*") $CfgMaps

    Write-Host "Syncing dodgeball configs..."
    if (Test-Path (Join-Path $AjbRoot "configs\dodgeball")) {
        Copy-Item -Force (Join-Path $AjbRoot "configs\dodgeball\*") $CfgDb
    }

    Write-Host "Syncing AJB configs (prisoner_loadout, …)..."
    $projCfg = Join-Path $AjbRoot "configs"
    Get-ChildItem -Path $projCfg -File -ErrorAction SilentlyContinue | ForEach-Object {
        $destination = Join-Path $CfgAjb $_.Name
        # Do not replace customized server settings with bundled defaults.
        if ($_.Name -eq "ajb_setting.cfg" -and ((Test-Path $destination) -or (Test-Path (Join-Path $CfgAjb "settings.cfg")))) {
            Write-Host "Keeping existing AJB settings."
        } else {
            Copy-Item -Force $_.FullName $destination
        }
    }

    Write-Host "Syncing gamedata..."
    $projGamedata = Join-Path $AjbRoot "gamedata\ajb.games.txt"
    if (Test-Path $projGamedata) {
        Copy-Item -Force $projGamedata (Join-Path $GamedataDir "ajb.games.txt")
    }
}

function Deploy-To-Live {
    Write-Host "Copying plugins -> $LivePlugins\*.smx"
    Copy-Item -Force (Join-Path $ProjPlugins "ajb.smx") (Join-Path $LivePlugins "ajb.smx")
    Copy-Item -Force (Join-Path $ProjPlugins "ajb_*.smx") $LivePlugins

    # Sanity: per-plugin hash so a stale live binary is obvious in the output.
    Get-ChildItem (Join-Path $ProjPlugins "ajb*.smx") | ForEach-Object {
        $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.Substring(0, 12)
        $dest = Join-Path $LivePlugins $_.Name
        $same = (Test-Path $dest) -and ((Get-FileHash $dest -Algorithm SHA256).Hash.Substring(0, 12) -eq $hash)
        $state = if ($same) { "live ok" } else { "MISMATCH" }
        Write-Host ("  {0,-24} {1}  {2}" -f $_.Name, $hash, $state)
    }
}

Write-Host "AJB project : $AjbRoot"
Write-Host "SourceMod   : $SmRoot"
Write-Host "Project out : $ProjPlugins\*.smx"

if (-not $SyncOnly) {
    & (Join-Path $AjbRoot "build.ps1")
}

if (-not $CompileOnly) {
    New-Item -ItemType Directory -Force -Path $LivePlugins, $TransDir, $CfgMaps, $CfgAjb, $CfgDb, $GamedataDir | Out-Null
    if (-not $SyncOnly) {
        Deploy-To-Live
    }
    Sync-Assets
}

Write-Host "Done."
if (-not $CompileOnly -and -not $SyncOnly) {
    Write-Host "Project: projects\ajb\plugins\*.smx"
    Write-Host "Live:    plugins\*.smx"
}
