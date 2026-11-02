# =======================================================================================================
# Compile AJB or build an installable release ZIP.
# =======================================================================================================

param(
    [string]$ScriptingPath = "$PSScriptRoot/../../scripting",
    [switch]$Package
)

$ErrorActionPreference = "Stop"
$Compiler = Join-Path $ScriptingPath "spcomp.exe"
$Sources = @(Get-Item "$PSScriptRoot/scripting/ajb.sp") + @(Get-ChildItem "$PSScriptRoot/scripting/modules/*.sp")
$Stage = Join-Path ([System.IO.Path]::GetTempPath()) "ajb-$([guid]::NewGuid())"
$Install = Join-Path $Stage "addons/sourcemod"
$OutputPath = if ($Package) { "$Install/plugins" } else { "$PSScriptRoot/plugins" }
$Includes = if ($Package) { "$Stage/include" } else { "$ScriptingPath/include" }
$MoreColors = "https://raw.githubusercontent.com/DoctorMcKay/sourcemod-plugins/master/scripting/include/morecolors.inc"
$TF2Attributes = "https://raw.githubusercontent.com/FlaminSarge/tf2attributes/master/scripting/include/tf2attributes.inc"

if (-not (Test-Path $Compiler)) {
    $Compiler = Join-Path $ScriptingPath "spcomp64.exe"
}
if (-not (Test-Path $Compiler)) {
    throw "spcomp not found under $ScriptingPath"
}

try {
    if ($Package) {
        New-Item -ItemType Directory -Path $Includes | Out-Null
        Invoke-WebRequest $MoreColors -OutFile "$Includes/morecolors.inc"
        Invoke-WebRequest $TF2Attributes -OutFile "$Includes/tf2attributes.inc"
    }
    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    foreach ($Source in $Sources) {
        $Output = Join-Path $OutputPath "$($Source.BaseName).smx"
        Write-Host "Compiling $($Source.Name)"
        & $Compiler $Source.FullName "-i$Includes" "-i$ScriptingPath/include" "-i$PSScriptRoot/scripting/include" "-o$Output"
        if ($LASTEXITCODE -ne 0) {
            throw "Compile failed: $($Source.Name) (exit $LASTEXITCODE)"
        }
        if (-not (Test-Path $Output) -or (Get-Item $Output).Length -eq 0) {
            throw "Expected output missing or empty: $Output"
        }
    }
    if ($Package) {
        New-Item -ItemType Directory -Path "$Install/configs" | Out-Null
        Copy-Item "$PSScriptRoot/configs" "$Install/configs/ajb" -Recurse
        Copy-Item "$PSScriptRoot/translations", "$PSScriptRoot/gamedata" $Install -Recurse
        New-Item -ItemType Directory -Force -Path "$PSScriptRoot/dist" | Out-Null
        Compress-Archive -Path "$Stage/addons" -DestinationPath "$PSScriptRoot/dist/ajb.zip" -Force
    }
} finally {
    if ($Package -and (Test-Path $Stage)) {
        Remove-Item $Stage -Recurse -Force
    }
}
