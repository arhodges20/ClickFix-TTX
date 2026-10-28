# simplebeacon cleanup - kills the Beaconator PowerShell C2 beacon.
# Dot-sourced by cleanup-victim.ps1 (Did/Skip helpers are in scope).

# 1. stop the hidden beacon process (any powershell running SimpleBeacon.ps1)
$procs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
         Where-Object { $_.CommandLine -like '*SimpleBeacon.ps1*' }
if ($procs) {
  $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 2
  $left = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
          Where-Object { $_.CommandLine -like '*SimpleBeacon.ps1*' }
  if ($left) {
    Warn 'beacon powershell process'
  } else {
    Did ("beacon process stopped ({0} instance(s))" -f @($procs).Count)
  }
} else {
  Skip 'beacon powershell process'
}

# 2. payload file the victim-side install script downloaded
$f = "$env:PUBLIC\SimpleBeacon.ps1"
if (Test-Path $f) {
  Remove-Item $f -Force
  if (Test-Path $f) { Warn $f } else { Did $f }
} else {
  Skip $f
}
