# cleanup-victim.ps1 - remove EVERYTHING the TTX ClickFix chain drops on a
# victim Windows host: the stage1 persistence, the loader artifacts, and the
# installed RMM agent (via the per-tool cleanups in tools\*.ps1).
#
# Run ELEVATED on the victim machine:
#   powershell -ExecutionPolicy Bypass -File .\cleanup-victim.ps1
#
# Only clean specific tools (core artifacts are ALWAYS cleaned):
#   powershell -ExecutionPolicy Bypass -File .\cleanup-victim.ps1 -Tools rustdesk
#
# Idempotent - safe to run repeatedly. ASCII-only on purpose (PS 5.1).

param(
  # Optional: restrict per-tool cleanups to specific tool ids
  # (default: run every tools\*.ps1 found next to this script)
  [string[]]$Tools
)

$ErrorActionPreference = 'SilentlyContinue'

# ---- output helpers (also used by the dot-sourced tools\*.ps1) -----------
function Did  ([string]$What) { Write-Host "  [cleaned] $What" -ForegroundColor Green }
function Skip ([string]$What) { Write-Host "  [absent ] $What" -ForegroundColor DarkGray }

Write-Host '== TTX ClickFix victim cleanup ==' -ForegroundColor Cyan

# ---- elevation check ------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Warning 'Not running elevated - uninstalls will likely fail. Re-run as Administrator.'
}

# ---- 1. core artifacts: stage1 + loader (always cleaned) -----------------
Write-Host "`n-- core: stage1 dropper + loader" -ForegroundColor Cyan

# persistence: the logon scheduled task stage1 registers
if (Get-ScheduledTask -TaskName 'WindowsVerification' -ErrorAction SilentlyContinue) {
  Unregister-ScheduledTask -TaskName 'WindowsVerification' -Confirm:$false
  Did "scheduled task 'WindowsVerification'"
} else {
  Skip "scheduled task 'WindowsVerification'"
}

# dropped loader + its log
foreach ($f in @("$env:PUBLIC\WindowsVerification.ps1", "$env:PUBLIC\WindowsVerification.log")) {
  if (Test-Path $f) { Remove-Item $f -Force; Did $f } else { Skip $f }
}

# installer scripts the loader cached (rmm-<tool>.ps1)
$cached = Get-ChildItem "$env:PUBLIC\rmm-*.ps1" -ErrorAction SilentlyContinue
if ($cached) {
  $cached | Remove-Item -Force
  Did "cached installer script(s): $($cached.Name -join ', ')"
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

Write-Host "`n== done - victim is clean for a re-run ==" -ForegroundColor Cyan
