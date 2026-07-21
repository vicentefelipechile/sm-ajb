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

$Scripting = Join-Path $SmRoot "scripting"
$Spcomp = Join-Path $Scripting "spcomp.exe"
if (-not (Test-Path $Spcomp)) {
    $Spcomp = Join-Path $Scripting "spcomp64.exe"
}
if (-not (Test-Path $Spcomp)) {
    throw "spcomp not found under $Scripting"
}

$ProjScripting = Join-Path $AjbRoot "scripting"
$ProjInclude = Join-Path $ProjScripting "include"
$SmInclude = Join-Path $Scripting "include"
$ProjPlugins = Join-Path $AjbRoot "plugins"
$LivePlugins = Join-Path $SmRoot "plugins"
$TransDir = Join-Path $SmRoot "translations"
$CfgMaps = Join-Path $SmRoot "configs\ajb\maps"
$CfgAjb = Join-Path $SmRoot "configs\ajb"

New-Item -ItemType Directory -Force -Path $ProjPlugins, $LivePlugins, $CfgMaps, $CfgAjb | Out-Null

function Invoke-Compile {
    param(
        [string]$Source,
        [string]$OutSmx
    )

    $compileArgs = @(
        $Source,
        "-i$SmInclude",
        "-i$ProjInclude",
        "-o$OutSmx"
    )

    Write-Host "  spcomp $(Split-Path $Source -Leaf) -> projects\ajb\plugins\$(Split-Path $OutSmx -Leaf)"
    & $Spcomp @compileArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Compile failed: $Source (exit $LASTEXITCODE)"
    }
    if (-not (Test-Path $OutSmx)) {
        throw "Expected output missing: $OutSmx"
    }
}

function Sync-Assets {
    Write-Host "Syncing translations..."
    Copy-Item -Force (Join-Path $AjbRoot "translations\*.phrases.txt") $TransDir

    Write-Host "Syncing map configs..."
    Copy-Item -Force (Join-Path $AjbRoot "configs\maps\*") $CfgMaps

    Write-Host "Syncing AJB configs (prisoner_loadout, …)..."
    $projCfg = Join-Path $AjbRoot "configs"
    Get-ChildItem -Path $projCfg -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -Force $_.FullName (Join-Path $CfgAjb $_.Name)
    }
}

function Deploy-To-Live {
    Write-Host "Copying plugins -> $LivePlugins\*.smx"
    Copy-Item -Force (Join-Path $ProjPlugins "ajb.smx") (Join-Path $LivePlugins "ajb.smx")
    Copy-Item -Force (Join-Path $ProjPlugins "ajb_*.smx") $LivePlugins
}

Write-Host "AJB project : $AjbRoot"
Write-Host "SourceMod   : $SmRoot"
Write-Host "Compiler    : $Spcomp"
Write-Host "Project out : $ProjPlugins\*.smx"

if (-not $SyncOnly) {
    Write-Host "Compiling into projects/ajb/plugins/..."

    Invoke-Compile `
        -Source (Join-Path $ProjScripting "ajb.sp") `
        -OutSmx (Join-Path $ProjPlugins "ajb.smx")

    Get-ChildItem (Join-Path $ProjScripting "modules\*.sp") | ForEach-Object {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        Invoke-Compile -Source $_.FullName -OutSmx (Join-Path $ProjPlugins "$name.smx")
    }
}

if (-not $CompileOnly) {
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
