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
| Beaconator beacon process + `%PUBLIC%\SimpleBeacon.ps1` | `ttx/rmm/simplebeacon/install.ps1` | `tools/simplebeacon.ps1` |

## Usage

On the victim machine (auto-relaunches itself elevated if needed):

    powershell -ExecutionPolicy Bypass -File .\cleanup-victim.ps1

Only clean specific tools (core artifacts are always cleaned):

    powershell -ExecutionPolicy Bypass -File .\cleanup-victim.ps1 -Tools rustdesk

## Output legend

Every removal is **verified after the fact** — the script never trusts an
uninstaller's exit code:

- `[cleaned  ]` — removed AND verified gone
- `[absent   ]` — wasn't there to begin with
- `[STILL ON]` — removal FAILED, item survived (also makes the script
  exit non-zero)

If any `[STILL ON]` appears, reboot the victim and re-run the script to
confirm — some agents only fully release files/services after a reboot.

## How the tool cleanups work (verify-don't-trust)

RMM agents are sticky: `rustdesk.exe --uninstall` is asynchronous and
known to fail silently or leave data behind (rustdesk/rustdesk#11960), and
MSI uninstalls can wedge. Each tool cleanup therefore runs:

1. the official uninstaller (with a wait/poll for it to settle)
2. a force phase — stop + delete every matching service (matched by name
   AND binary path, so name variants are caught), tree-kill processes
   (`taskkill /F /T`), registry uninstall fallback
3. a folder sweep including the configs that store access credentials
   (e.g. RustDesk's permanent password lives under the LocalService
   profile — deleting it means even a surviving agent can't accept the
   old password)
4. a final verification pass — service, process, install folder, and
   registry product must all be gone, or it's reported `[STILL ON]`

The Splashtop cleanup matches on `Splashtop Streamer` specifically, so
the operator-side **Splashtop Business** app is never touched.

## Adding a cleanup for a new RMM tool

Mirror the payload-module pattern from `ttx/rmm/`:

1. Create `tools/<newtool>.ps1` (copy an existing one as a template).
2. Use the `Did` / `Skip` / `Warn` helpers (they are in scope — the main
   script dot-sources your file) and clean, in order: the agent process,
   the installed program (registry uninstall entry), its data folders, and
   the payload file the victim-side `install.ps1` downloads.
3. End with a verification pass that checks everything is really gone.
4. Done — `cleanup-victim.ps1` auto-discovers every `tools\*.ps1`.
