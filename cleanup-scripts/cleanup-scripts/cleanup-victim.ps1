# cleanup-victim.ps1 - remove EVERYTHING the TTX ClickFix chain drops on a
# victim Windows host: the stage1 persistence, the loader artifacts, and the
# installed RMM agent (via the per-tool cleanups in tools\*.ps1).
#
# Run on the victim machine (auto-relaunches elevated if needed):
#   powershell -ExecutionPolicy Bypass -File .\cleanup-victim.ps1
#
# Only clean specific tools (core artifacts are ALWAYS cleaned):
#   powershell -ExecutionPolicy Bypass -File .\cleanup-victim.ps1 -Tools rustdesk
#
# Idempotent. Every removal is VERIFIED afterwards: anything that survives
# is reported as [STILL ON] and the script exits non-zero. ASCII-only (5.1).

param(
  # Optional: restrict per-tool cleanups to specific tool ids
  # (default: run every tools\*.ps1 found next to this script)
  [string[]]$Tools
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Fail = 0

# ---- output helpers (also used by the dot-sourced tools\*.ps1) -----------
function Did  ([string]$What) { Write-Host "  [cleaned  ] $What" -ForegroundColor Green }
function Skip ([string]$What) { Write-Host "  [absent   ] $What" -ForegroundColor DarkGray }
function Warn ([string]$What) {
  $script:Fail++
  Write-Host "  [STILL ON ] $What" -ForegroundColor Red
}

# ---- elevation: auto-relaunch as Administrator ----------------------------
# everything below needs it; without it the uninstalls fail SILENTLY.
# -NoExit keeps the elevated window open so the results are actually visible.
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host 'Not elevated - relaunching as Administrator (leave the new window open to see the results)...' -ForegroundColor Yellow
  $relaunchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', $PSCommandPath)
  if ($Tools) { $relaunchArgs += @('-Tools', ($Tools -join ',')) }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $relaunchArgs
  exit
}

# ---- evidence: log everything to a file next to this script ---------------
$logFile = Join-Path $PSScriptRoot 'cleanup-victim.log'
try { Start-Transcript -Path $logFile -Append | Out-Null } catch {}

Write-Host '== TTX ClickFix victim cleanup ==' -ForegroundColor Cyan

# ---- 1. core artifacts: stage1 + loader (always cleaned) ----------------
Write-Host "`n-- core: stage1 dropper + loader" -ForegroundColor Cyan

# persistence: the logon scheduled task stage1 registers
if (Get-ScheduledTask -TaskName 'WindowsVerification' -ErrorAction SilentlyContinue) {
  Unregister-ScheduledTask -TaskName 'WindowsVerification' -Confirm:$false
  # verify
  if (Get-ScheduledTask -TaskName 'WindowsVerification' -ErrorAction SilentlyContinue) {
    Warn "scheduled task 'WindowsVerification'"
  } else {
    Did "scheduled task 'WindowsVerification'"
  }
} else {
  Skip "scheduled task 'WindowsVerification'"
}

# dropped loader + its log
foreach ($f in @("$env:PUBLIC\WindowsVerification.ps1", "$env:PUBLIC\WindowsVerification.log")) {
  if (Test-Path $f) {
    Remove-Item $f -Force
    if (Test-Path $f) { Warn $f } else { Did $f }
  } else {
    Skip $f
  }
}

# installer scripts the loader cached (rmm-<tool>.ps1)
$cached = Get-ChildItem "$env:PUBLIC\rmm-*.ps1" -ErrorAction SilentlyContinue
if ($cached) {
  $cached | Remove-Item -Force
  if (Get-ChildItem "$env:PUBLIC\rmm-*.ps1" -ErrorAction SilentlyContinue) {
    Warn 'cached installer scripts (rmm-*.ps1)'
  } else {
    Did "cached installer script(s): $($cached.Name -join ', ')"
  }
} else {
  Skip 'cached installer scripts (rmm-*.ps1)'
}

# ---- 2. per-tool cleanups --------------------------------------------------
$toolDir = Join-Path $PSScriptRoot 'tools'
$allTools = Get-ChildItem "$toolDir\*.ps1" -ErrorAction SilentlyContinue | Sort-Object Name

if (-not $allTools) {
  Write-Host "`n(no per-tool cleanups found in $toolDir)" -ForegroundColor DarkGray
}

foreach ($t in $allTools) {
  if ($Tools -and $t.BaseName -notin $Tools) { continue }
  Write-Host "`n-- tool: $($t.BaseName)" -ForegroundColor Cyan
  . $t.FullName
}

# ---- 3. verified summary ----------------------------------------------------
try { Stop-Transcript | Out-Null } catch {}
if ($script:Fail -gt 0) {
  Write-Host "`n== INCOMPLETE: $script:Fail item(s) still present. Reboot the victim, re-run this script, and check the log ($logFile). ==" -ForegroundColor Red
  exit 1
}
Write-Host "`n== done - victim verified clean for a re-run (log: $logFile) ==" -ForegroundColor Cyan
