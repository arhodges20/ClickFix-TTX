# splashtop cleanup - removes a Splashtop Streamer wizard install.
# Dot-sourced by cleanup-victim.ps1 (Did/Skip helpers are in scope).

# 1. stop the streamer (MSI uninstall is more reliable with it not running)
if (Get-Process -Name 'SRStream' -ErrorAction SilentlyContinue) {
  Stop-Process -Name 'SRStream' -Force -ErrorAction SilentlyContinue
  Did 'SRStream process stopped'
} else {
  Skip 'SRStream process'
}

# 2. uninstall the Streamer MSI (locate by display name, uninstall by ProductCode)
$keys = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$prod = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Splashtop Streamer*' } |
        Select-Object -First 1

if ($prod -and $prod.ProductCode) {
  $p = Start-Process msiexec.exe -ArgumentList "/x $($prod.ProductCode) /qn" -Wait -PassThru
  Did "uninstalled '$($prod.DisplayName)' (exit $($p.ExitCode))"
} elseif ($prod) {
  Did "found '$($prod.DisplayName)' but no ProductCode - uninstall it manually"
} else {
  Skip 'Splashtop Streamer install'
}

# 3. leftover install dir (normally removed by the MSI, belt-and-braces)
if (Test-Path "${env:ProgramFiles(x86)}\Splashtop\Splashtop Streamer") {
  Remove-Item "${env:ProgramFiles(x86)}\Splashtop\Splashtop Streamer" -Recurse -Force
  Did "${env:ProgramFiles(x86)}\Splashtop\Splashtop Streamer"
} else {
  Skip 'Splashtop Streamer install dir'
}

# 4. payload leftovers the victim-side install script downloaded/aliased
foreach ($f in @("$env:PUBLIC\streamer.msi", "$env:PUBLIC\setup.msi")) {
  if (Test-Path $f) { Remove-Item $f -Force; Did $f } else { Skip $f }
}
