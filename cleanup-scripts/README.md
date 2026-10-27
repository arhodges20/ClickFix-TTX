# Victim cleanup scripts

Resets a victim Windows machine to a clean state so a TTX session can be
re-run on it. Removes **everything** the attack chain drops:

| Artifact | Where it comes from | Removed |
|---|---|---|
| Scheduled task `WindowsVerification` | `stage1.ps1` persistence | always |
| `%PUBLIC%\WindowsVerification.ps1` (+ `.log`) | dropped loader | always |
| `%PUBLIC%\rmm-*.ps1` | installer scripts the loader cached | always |
| Splashtop Streamer (MSI) + `SRStream` + `%PUBLIC%\streamer.msi` / `setup.msi` | `ttx/rmm/splashtop/install.ps1` | `tools/splashtop.ps1` |
| RustDesk host + service + all data folders + `%PUBLIC%\rustdesk-host.exe` | `ttx/rmm/rustdesk/install.ps1` | `tools/rustdesk.ps1` |

## Usage

On the victim machine, from an **elevated** PowerShell:

    powershell -ExecutionPolicy Bypass -File .\cleanup-victim.ps1

Only clean specific tools (core artifacts are always cleaned):

    powershell -ExecutionPolicy Bypass -File .\cleanup-victim.ps1 -Tools rustdesk

Output marks each item `[cleaned]` or `[absent ]` — it is idempotent and
safe to run repeatedly (the second run should show all `[absent ]`).

## Notes

- Run elevated — the task deletion, MSI uninstall, and RustDesk service
  removal all require administrator rights.
- The RustDesk uninstaller (`rustdesk.exe --uninstall`) is known to leave
  data folders behind (rustdesk/rustdesk#11960), so the script sweeps
  `%ProgramData%\RustDesk`, every user's `AppData\Local|Roaming\RustDesk`,
  and the LocalService profile folder afterwards.
- Kill any wedged `msiexec` by hand if the Splashtop uninstall hangs
  (the victim-side script already tries to prevent this).

## Adding a cleanup for a new RMM tool

Mirror the payload-module pattern from `ttx/rmm/`:

1. Create `tools/<newtool>.ps1` (copy an existing one as a template).
2. Use the `Did` / `Skip` helpers (they are in scope — the main script
   dot-sources your file) and clean, in order: the agent process, the
   installed program (registry uninstall entry), its data folders, and the
   payload file the victim-side `install.ps1` downloads.
3. Done — `cleanup-victim.ps1` auto-discovers every `tools\*.ps1`.
