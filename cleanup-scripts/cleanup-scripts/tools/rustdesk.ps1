# rustdesk cleanup - removes a silent RustDesk host install.
# Dot-sourced by cleanup-victim.ps1 (Did/Skip/Warn helpers are in scope).
#
# RustDesk is sticky: `rustdesk.exe --uninstall` is asynchronous, sometimes
# silently no-ops, and leaves data behind (rustdesk/rustdesk#11960). This
# script does NOT trust it - it removes RustDesk DETERMINISTICALLY, kill-first:
#   1. kill every rustdesk process (a dead process accepts no connections)
#   2. stop + delete every rustdesk service (waited + verified)
#   3. MSI uninstall fallback (for MSI-based installs)
#   4. delete every folder, incl. the service config that stores the
#      permanent password (a surviving agent cannot accept the old password)
#   5. registry product key, autoruns, firewall rules, payload file
#   6. VERIFY the end state; anything left is reported [STILL ON]

# ---- 1. kill every rustdesk process FIRST --------------------------------
$wasRunning = [bool](Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue)
if ($wasRunning) {
  for ($i = 0; $i -lt 5; $i++) {
    taskkill.exe /F /T /IM rustdesk.exe | Out-Null
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue)) { break }
  }
  if (Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue) {
    Warn 'rustdesk process(es) still running after 5 kill attempts'
  } else {
    Did 'rustdesk process(es) force-killed'
  }
} else {
  Skip 'rustdesk process(es)'
}

# ---- 2. stop + delete every rustdesk service (waited + verified) ----------
$svcs = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*rustdesk*' -or ($_.PathName -and $_.PathName -like '*rustdesk*') }
if ($svcs) {
  foreach ($svc in $svcs) {
    sc.exe stop $svc.Name | Out-Null
    for ($i = 0; $i -lt 10; $i++) {
      $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
      if (-not $s -or $s.Status -eq 'Stopped') { break }
      Start-Sleep -Seconds 2
    }
    sc.exe delete $svc.Name | Out-Null
    if (Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $svc.Name }) {
      Warn "service '$($svc.Name)' (may need a reboot to finish deleting)"
    } else {
      Did "service '$($svc.Name)' stopped + deleted"
    }
  }
} else {
  Skip 'rustdesk service(s)'
}

# ---- 3. MSI uninstall fallback -------------------------------------------
$keys = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$prod = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'RustDesk*' } |
        Select-Object -First 1
if ($prod -and $prod.UninstallString -match 'msiexec' -and $prod.ProductCode) {
  $p = Start-Process msiexec.exe -ArgumentList "/x $($prod.ProductCode) /qn" -Wait -PassThru
  Did "MSI uninstall ran for '$($prod.DisplayName)' (exit $($p.ExitCode))"
} else {
  Skip 'RustDesk MSI registry entry'
}

# ---- 4. delete folders (retry locked deletions) ---------------------------
# the service config under ServiceProfiles stores the permanent password -
# deleting it means even a surviving agent cannot accept the old one
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
    for ($i = 0; $i -lt 3; $i++) {
      Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
      if (-not (Test-Path $d)) { break }
      Start-Sleep -Seconds 2
    }
    if (Test-Path $d) { Warn $d } else { Did $d }
  } else {
    Skip $d
  }
}

# ---- 5. registry key, autoruns, firewall rules, payload -------------------
# leftover registry Uninstall key - only once the install dir is gone
if (-not (Test-Path "$env:ProgramFiles\RustDesk") -and -not (Test-Path "${env:ProgramFiles(x86)}\RustDesk")) {
  $prodKeys = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
              Where-Object { $_.DisplayName -like 'RustDesk*' }
  foreach ($pk in $prodKeys) {
    Remove-Item $pk.PSPath -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $pk.PSPath) { Warn "registry key $($pk.PSPath)" } else { Did "registry key: $($pk.DisplayName)" }
  }
}

# autorun entries pointing at rustdesk
foreach ($rk in @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
  'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
)) {
  $item = Get-ItemProperty $rk -ErrorAction SilentlyContinue
  if ($item) {
    $item.PSObject.Properties |
      Where-Object { $_.Value -like '*rustdesk*' } |
      ForEach-Object {
        Remove-ItemProperty -Path $rk -Name $_.Name -Force -ErrorAction SilentlyContinue
        Did "autorun removed: $rk -> $($_.Name)"
      }
  }
}

# firewall rules
$fw = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*rustdesk*' }
if ($fw) {
  $fw | Remove-NetFirewallRule -ErrorAction SilentlyContinue
  if (Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*rustdesk*' }) {
    Warn 'rustdesk firewall rule(s)'
  } else {
    Did 'rustdesk firewall rule(s)'
  }
} else {
  Skip 'rustdesk firewall rule(s)'
}

# payload leftover from the victim-side install script
$f = "$env:PUBLIC\rustdesk-host.exe"
if (Test-Path $f) {
  Remove-Item $f -Force
  if (Test-Path $f) { Warn $f } else { Did $f }
} else {
  Skip $f
}

# ---- 6. VERIFY (never trust, always check) -------------------------------
Start-Sleep -Seconds 2
$bad = @()
if (Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue) { $bad += 'a rustdesk process is still running' }
if (Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*rustdesk*' -or ($_.PathName -and $_.PathName -like '*rustdesk*') }) {
  $bad += 'a rustdesk service is still registered'
}
if ((Test-Path "$env:ProgramFiles\RustDesk") -or (Test-Path "${env:ProgramFiles(x86)}\RustDesk")) {
  $bad += 'the RustDesk install folder still exists'
}
if (Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'RustDesk*' }) {
  $bad += 'a RustDesk entry is still in Add/Remove Programs'
}
if ($bad) {
  foreach ($b in $bad) { Warn $b }
  Warn 'connectivity may persist - reboot the victim and re-run this script'
} else {
  Did 'verified: no rustdesk process, service, install folder, registry entry, or data folders remain'
}

