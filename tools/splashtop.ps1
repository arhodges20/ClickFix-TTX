# splashtop cleanup - removes a Splashtop Streamer wizard install.
# Dot-sourced by cleanup-victim.ps1 (Did/Skip/Warn helpers are in scope).
#
# Verify-don't-trust: every removal is checked afterwards and anything
# that survives is reported as [STILL ON]. Service matching is by display
# name / binary path so the operator-side "Splashtop Business" app is
# never touched.

# ---- 1. stop the Streamer service(s) + kill the process tree -------------
$svcs = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*Splashtop Streamer*' -or ($_.PathName -and $_.PathName -like '*Splashtop*Splashtop Streamer*') }
foreach ($svc in $svcs) {
  Did "service '$($svc.DisplayName)' stopping + deleting"
  Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
  sc.exe delete $svc.Name | Out-Null
}
if (-not $svcs) { Skip 'Splashtop Streamer service(s)' }

if (Get-Process -Name 'SRStream' -ErrorAction SilentlyContinue) {
  taskkill.exe /F /T /IM SRStream.exe | Out-Null
  Start-Sleep -Seconds 2
} else {
  Skip 'SRStream process(es)'
}

# ---- 2. uninstall the Streamer MSI (by display name -> ProductCode) ------
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

# ---- 3. leftover install dir + payload files ------------------------------
if (Test-Path "${env:ProgramFiles(x86)}\Splashtop\Splashtop Streamer") {
  Remove-Item "${env:ProgramFiles(x86)}\Splashtop\Splashtop Streamer" -Recurse -Force -ErrorAction SilentlyContinue
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

# ---- 4. VERIFY ------------------------------------------------------------
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

