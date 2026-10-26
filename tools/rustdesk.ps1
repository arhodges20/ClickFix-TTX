# rustdesk cleanup - removes a silent RustDesk host install.
# Dot-sourced by cleanup-victim.ps1 (Did/Skip/Warn helpers are in scope).
#
# `rustdesk.exe --uninstall` is ASYNCHRONOUS and quietly fails in several
# setups (rustdesk/rustdesk#11960), so this script does NOT trust it:
#   1. run the official uninstaller, wait for it to settle
#   2. force-stop whatever survived (all rustdesk services + processes)
#   3. sweep every folder, INCLUDING the service config that stores the
#      permanent password - so even a surviving agent cannot accept the
#      old password
#   4. VERIFY the end state and report [STILL ON] on anything left

# ---- 1. official uninstaller (asynchronous - wait it out) ---------------
$RdExe = @("$env:ProgramFiles\RustDesk\rustdesk.exe", "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe") |
         Where-Object { Test-Path $_ } | Select-Object -First 1

if ($RdExe) {
  Did "official uninstaller launched ($RdExe --uninstall)"
  Start-Process $RdExe -ArgumentList '--uninstall' -WindowStyle Hidden
  # it works in the background - wait for service + exe to disappear
  for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 2
    $svcAlive = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -like '*rustdesk*' }
    if (-not (Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue) -and -not $svcAlive) { break }
  }
} else {
  Skip 'installed rustdesk.exe (no Program Files install found)'
}

# ---- 2. force-stop whatever survived --------------------------------------
# every RustDesk service, matched by name OR binary path (catches variants)
$svcs = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*rustdesk*' -or ($_.PathName -and $_.PathName -like '*rustdesk*') }
foreach ($svc in $svcs) {
  Did "service '$($svc.Name)' stopping + deleting"
  Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
  sc.exe delete $svc.Name | Out-Null
}
if (-not $svcs) { Skip 'rustdesk service(s)' }

# every rustdesk process, tree-killed
if (Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue) {
  taskkill.exe /F /T /IM rustdesk.exe | Out-Null
  Start-Sleep -Seconds 2
} else {
  Skip 'rustdesk process(es)'
}

# registry fallback for MSI-based installs
$keys = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$prod = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'RustDesk*' } |
        Select-Object -First 1
if ($prod -and $prod.UninstallString -match 'msiexec' -and $prod.ProductCode) {
  Start-Process msiexec.exe -ArgumentList "/x $($prod.ProductCode) /qn" -Wait
  Did "MSI-uninstalled '$($prod.DisplayName)'"
} else {
  Skip 'RustDesk MSI registry entry'
}

# ---- 3. remove folders (incl. the config that stores the password) ------
# the service config under ServiceProfiles holds the permanent password -
# deleting it means a surviving agent can no longer accept the old one
$leftovers = @(
  "$env:ProgramFiles\RustDesk",
  "${env:ProgramFiles(x86)}\RustDesk",
  "$env:ProgramData\RustDesk",
  "$env:LOCALAPPDATA\RustDesk",
  "$env:APPDATA\RustDesk",
  'C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk'
)
# per-user copies under every profile on the box
$leftovers += Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  "$($_.FullName)\AppData\Local\RustDesk"
  "$($_.FullName)\AppData\Roaming\RustDesk"
}
foreach ($d in $leftovers | Select-Object -Unique) {
  if (Test-Path $d) {
    Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $d) { Warn $d } else { Did $d }
  } else {
    Skip $d
  }
}

# ---- 4. payload leftover ---------------------------------------------------
$f = "$env:PUBLIC\rustdesk-host.exe"
if (Test-Path $f) {
  Remove-Item $f -Force
  if (Test-Path $f) { Warn $f } else { Did $f }
} else {
  Skip $f
}

# ---- 5. VERIFY (never trust the uninstaller) -----------------------------
Start-Sleep -Seconds 2
$bad = @()
if (Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*rustdesk*' -or ($_.PathName -and $_.PathName -like '*rustdesk*') }) {
  $bad += 'a rustdesk service is still registered'
}
if (Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue) {
  $bad += 'a rustdesk process is still running'
}
if ((Test-Path "$env:ProgramFiles\RustDesk") -or (Test-Path "${env:ProgramFiles(x86)}\RustDesk")) {
  $bad += 'the RustDesk install folder still exists'
}
if ($bad) {
  foreach ($b in $bad) { Warn $b }
  Warn 'connectivity may persist - reboot the victim and re-run this script'
} else {
  Did 'verified: no rustdesk service, process, install folder, or data folders remain'
}

