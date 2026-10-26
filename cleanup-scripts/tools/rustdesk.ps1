# rustdesk cleanup - removes a silent RustDesk host install.
# Dot-sourced by cleanup-victim.ps1 (Did/Skip helpers are in scope).
#
# The official uninstaller trigger is `rustdesk.exe --uninstall`, but it is
# KNOWN to leave data folders behind (rustdesk/rustdesk GitHub issue #11960),
# so this script sweeps them all afterwards.

# 1. run the official uninstaller (removes the service + Program Files copy)
$rdExe = @("$env:ProgramFiles\RustDesk\rustdesk.exe", "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe") |
         Where-Object { Test-Path $_ } | Select-Object -First 1
if ($rdExe) {
  Start-Process $rdExe -ArgumentList '--uninstall' -Wait
  Start-Sleep -Seconds 3
  Did "ran '$rdExe --uninstall'"
} else {
  Skip 'installed rustdesk.exe'
}

# registry fallback: run the UninstallString if the product is still registered
$keys = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$prod = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'RustDesk*' } |
        Select-Object -First 1
if ($prod -and -not $rdExe) {
  if ($prod.UninstallString -match 'msiexec' -and $prod.ProductCode) {
    Start-Process msiexec.exe -ArgumentList "/x $($prod.ProductCode) /qn" -Wait
  } else {
    Start-Process cmd.exe -ArgumentList '/c', $prod.UninstallString -WindowStyle Hidden -Wait
  }
  Did "ran registry uninstaller for '$($prod.DisplayName)'"
} elseif ($prod -and $rdExe) {
  Did "registry still lists '$($prod.DisplayName)' - leftover folders swept below"
} else {
  Skip 'RustDesk registry entry'
}

# 2. kill anything still running
if (Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue) {
  Stop-Service -Name 'RustDesk' -Force -ErrorAction SilentlyContinue
  sc.exe delete RustDesk | Out-Null
  Did "service 'RustDesk' stopped + deleted"
} else {
  Skip "service 'RustDesk'"
}
if (Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue) {
  Stop-Process -Name 'rustdesk' -Force -ErrorAction SilentlyContinue
  Did 'rustdesk process stopped'
} else {
  Skip 'rustdesk process'
}

# 3. folders the uninstaller leaves behind (per rustdesk issue #11960)
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
  if (Test-Path $d) { Remove-Item $d -Recurse -Force; Did $d } else { Skip $d }
}

# 4. payload leftover the victim-side install script downloaded
if (Test-Path "$env:PUBLIC\rustdesk-host.exe") {
  Remove-Item "$env:PUBLIC\rustdesk-host.exe" -Force
  Did "$env:PUBLIC\rustdesk-host.exe"
} else {
  Skip "$env:PUBLIC\rustdesk-host.exe"
}
