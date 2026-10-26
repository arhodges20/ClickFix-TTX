# splashtop cleanup - removes a Splashtop Streamer wizard install.
# Dot-sourced by cleanup-victim.ps1 (Did/Skip/Warn helpers are in scope).
#
# Kill-first, verify-don't-trust (same model as the rustdesk cleanup):
#   1. kill the SRStream process tree (a dead process accepts no connections)
#   2. stop + delete the Streamer service(s) (waited + verified)
#   3. MSI uninstall by ProductCode, verified afterwards
#   4. leftover install dir + payload files
#   5. VERIFY - anything left is reported [STILL ON]
#
# Service matching is by display name / binary path so the operator-side
# "Splashtop Business" app is never touched.

# ---- 1. kill the streamer process tree FIRST ------------------------------
if (Get-Process -Name 'SRStream' -ErrorAction SilentlyContinue) {
  for ($i = 0; $i -lt 5; $i++) {
    taskkill.exe /F /T /IM SRStream.exe | Out-Null
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name 'SRStream' -ErrorAction SilentlyContinue)) { break }
  }
  if (Get-Process -Name 'SRStream' -ErrorAction SilentlyContinue) {
    Warn 'SRStream process still running after 5 kill attempts'
  } else {
    Did 'SRStream process(es) force-killed'
  }
} else {
  Skip 'SRStream process(es)'
}

# ---- 2. stop + delete the Streamer service(s) (waited + verified) --------
$svcs = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*Splashtop Streamer*' -or ($_.PathName -and $_.PathName -like '*Splashtop*Splashtop Streamer*') }
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
      Warn "service '$($svc.DisplayName)' (may need a reboot to finish deleting)"
    } else {
      Did "service '$($svc.DisplayName)' stopped + deleted"
    }
  }
} else {
  Skip 'Splashtop Streamer service(s)'
}

# ---- 3. MSI uninstall by ProductCode (verified) ----------------------------
$keys = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$prod = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Splashtop Streamer*' } |
        Select-Object -First 1

if ($prod -and $prod.ProductCode) {
  $p = Start-Process msiexec.exe -ArgumentList "/x $($prod.ProductCode) /qn" -Wait -PassThru
  Did "MSI uninstall ran for '$($prod.DisplayName)' (exit $($p.ExitCode))"
} elseif ($prod) {
  Warn "found '$($prod.DisplayName)' but no ProductCode - uninstall it manually"
} else {
  Skip 'Splashtop Streamer install (registry)'
}

# ---- 4. leftover install dir + payload files (retry locked deletions) -----
if (Test-Path "${env:ProgramFiles(x86)}\Splashtop\Splashtop Streamer") {
  for ($i = 0; $i -lt 3; $i++) {
    Remove-Item "${env:ProgramFiles(x86)}\Splashtop\Splashtop Streamer" -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path "${env:ProgramFiles(x86)}\Splashtop\Splashtop Streamer")) { break }
    Start-Sleep -Seconds 2
  }
  if (Test-Path "${env:ProgramFiles(x86)}\Splashtop\Splashtop Streamer") {
    Warn "${env:ProgramFiles(x86)}\Splashtop\Splashtop Streamer"
  } else {
    Did "${env:ProgramFiles(x86)}\Splashtop\Splashtop Streamer"
  }
} else {
  Skip 'Splashtop Streamer install dir'
}

foreach ($f in @("$env:PUBLIC\streamer.msi", "$env:PUBLIC\setup.msi")) {
  if (Test-Path $f) {
    Remove-Item $f -Force
    if (Test-Path $f) { Warn $f } else { Did $f }
  } else {
    Skip $f
  }
}

# ---- 5. VERIFY ------------------------------------------------------------
Start-Sleep -Seconds 2
$bad = @()
$prod2 = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
         Where-Object { $_.DisplayName -like 'Splashtop Streamer*' } |
         Select-Object -First 1
if ($prod2) { $bad += "'$($prod2.DisplayName)' is still registered - reboot and retry the MSI uninstall" }
if (Get-Process -Name 'SRStream' -ErrorAction SilentlyContinue) { $bad += 'SRStream is still running' }
if (Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like '*Splashtop Streamer*' }) { $bad += 'a Splashtop Streamer service is still registered' }

if ($bad) {
  foreach ($b in $bad) { Warn $b }
} else {
  Did 'verified: no Splashtop Streamer product, process, or service remains'
}

