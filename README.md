# TTX Lab — ClickFix → Modular RMM Deployment

One-command ClickFix training scenario. Victim pastes a command from a
fake CAPTCHA page → stage1 drops rmm.ps1 with logon persistence → the
loader fetches the selected tool's installer → the RMM agent lands and the
machine joins your RMM console.

Which RMM tool victims get is chosen interactively at setup time
(`./setup.sh`) from whatever tool modules exist in `ttx/rmm/`.
Ships with **Splashtop Streamer** (visible install wizard) and
**RustDesk** (silent install); see **EXTENDING.md** for a full
fork-and-customize guide (adding tools, changing the lure, conventions).

## Requirements
- Docker host (any Linux box, no inbound ports needed — tunnel is outbound-only)
- An account/download for whichever RMM tool you select
- One victim Windows host (ideally WITHOUT that RMM agent already installed)

## Quick start — first-time bring-up

Everything below runs on the Docker host, from the repo root. Do the steps
in order and run the verify command in each before moving to the next.

### Step 1 — Clone the repo and confirm Docker works

    git clone https://github.com/arhodges20/ClickFix-TTX.git
    cd ClickFix-TTX
    docker compose version

If `docker compose version` errors out, install Docker (with the compose
plugin) first and come back.

### Step 2 — Place the payload binary for the tool you'll use

Each tool module lives in `ttx/rmm/<tool>/` and needs its payload binary
sitting **directly in that folder**, named **exactly** what the tool's
manifest says (Linux is case-sensitive). Pick ONE of:

**Option A — RustDesk (silent install, no wizard):**

    # Download the Windows host exe straight onto the box (~25 MB):
    wget -O ttx/rmm/rustdesk/rustdesk-host.exe \
      https://github.com/rustdesk/rustdesk/releases/download/1.5.0/rustdesk-1.5.0-x86_64.exe

(For a newer release, grab the `rustdesk-<version>-x86_64.exe` link from
github.com/rustdesk/rustdesk/releases and use that URL instead.)

**Option B — Splashtop (interactive MSI wizard):**

1. On a machine with console access, download the Streamer MSI:
   my.splashtop.com → Add/deploy remote computer → deploy by 12-digit code
   → Streamer MSI download. It arrives as a .zip — extract it.
2. Copy the extracted .msi onto the Docker host:

       # run this from wherever the extracted .msi is:
       scp streamer.msi <user>@<docker-host>:~/ClickFix/ClickFix-TTX/ttx/rmm/splashtop/streamer.msi

**Verify (whichever you picked):**

    ls -lh ttx/rmm/rustdesk/rustdesk-host.exe      # or .../splashtop/streamer.msi
    file ttx/rmm/rustdesk/rustdesk-host.exe        # must say "PE32+ executable"

If `file` says zip/HTML instead of PE32+ executable, the download failed —
redo the step. Two classic mistakes to avoid:

- the file must NOT be in a nested path like
  `ttx/rmm/rustdesk/ttx/rmm/rustdesk/rustdesk-host.exe` (this happens when
  a whole folder gets copied instead of just the file) — flat, one level;
- the name must match the manifest exactly — check with
  `grep PAYLOAD_FILE ttx/rmm/<tool>/manifest`.

You CAN launch without any payload (lure page, clipboard copy, and beacons
all work), but the victim flow will fail at the payload download step until
one is in place.

### Step 3 — Pick your RMM tool

    chmod +x setup.sh
    ./setup.sh

It scans `ttx/rmm/*/manifest` and shows a numbered menu; the payload status
for each tool is checked live on every run:

    Which RMM tool should victims receive?

      1) Splashtop Streamer (MSI wizard)         [payload OK]
      2) RustDesk Host (silent)                   [payload OK]

    Selection (1-2): 2

If your tool still says `[PAYLOAD MISSING]`, go back and re-check Step 2 —
the menu is a live filesystem check, so it flips to OK the moment the file
is in the right place with the right name.

Your choice is written to `.env` (`RMM_TOOL=...`), which docker compose
reads automatically.

### Step 4 — Launch

    docker compose up -d --build

First run takes a minute or two (base image + cloudflared download).
Subsequent runs are fast. Give it ~15 seconds after the build finishes for
the outbound Cloudflare tunnel to come up.

### Step 5 — Confirm it's live and grab the victim URL

    docker logs ttx-lab | tail -20

You want to see this banner (the URL is new every launch):

    ==================================================
      TTX CLICKFIX LAB IS LIVE
      Active RMM:        rustdesk (RustDesk Host, silent)
      Send victims to:   https://<random>.trycloudflare.com/ttx/
      Watch beacons:     docker logs -f ttx-lab
      ...
    ==================================================

Troubleshooting at this stage:

- `ERROR: no tunnel URL` — wait 30 s and run the log command again; if it
  persists, check outbound internet from the host.
- `ERROR: unknown RMM_TOOL` — `.env` has a tool id with no matching module;
  re-run `./setup.sh` and pick from the list.

### Step 6 — Sanity-check that the payload is being served

Before handing the URL to a victim, confirm the container can actually
serve the selected tool's payload over the tunnel:

    URL=$(docker logs ttx-lab | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1)
    curl -I $URL/ttx/rmm/rustdesk/rustdesk-host.exe
    # (splashtop instead: curl -I $URL/ttx/rmm/splashtop/streamer.msi)

Expected: `HTTP/2 200` with a sane `Content-Length` (~25M for RustDesk,
~68M for Splashtop). A `404` means the payload isn't in
`ttx/rmm/<tool>/` on the host — recheck Step 2. Each victim download also
shows up as a `200` line in the docker logs.

### Step 7 — Run the exercise

- Hand the `https://<tunnel>.trycloudflare.com/ttx/` URL to your victims
  (they should paste the copied command into an elevated PowerShell)
- Follow along live:

      docker logs -f ttx-lab

- The facilitator console is on the lure page itself — press `F`
  (copy stats, event log, editable payload)
- When the `rmm-start-<tool>` → `<tool>-installed` beacons arrive, the
  machine is in your RMM console — connect and take over

### Day-to-day command cheat sheet

    ./setup.sh                                     # re-pick the RMM tool (menu)
    docker compose up -d --build                   # launch / apply tool change
    docker compose restart                          # re-run after swapping a payload file
    docker compose down && docker compose up -d --build   # new session URL
    docker logs -f ttx-lab                          # watch beacons live
    docker logs ttx-lab | tail -20                 # banner + victim URL

## Switching tools mid-course

Re-run the picker, then recreate the container (the tool choice is
container config, so a plain `restart` won't pick it up — that's why the
cheat sheet distinguishes `restart` from `down/up`):

    ./setup.sh
    docker compose down && docker compose up -d --build

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

## Connecting to a RustDesk victim

RustDesk (on the public servers) has no team console like Splashtop —
you connect peer-to-peer with the machine's **connection ID + permanent
password**. Both are handled by the dropper:

1. **Password** — the victim-side script sets the permanent unattended
   password from `$Password` in `ttx/rmm/rustdesk/install.ps1` right after
   install (default `ttx-lab` — CHANGE ME per deployment). You'll see the
   `rustdesk-password-set` beacon when it's done.
2. **ID** — the script then reads the machine's connection ID and beacons
   it home. Grab it from the logs:

       docker logs ttx-lab | grep rustdesk-id

       .../beacon?s=rustdesk-id-301549035&h=WIN-LAB1&u=Administrator

3. **Connect** — open your RustDesk client, enter the ID, enter the
   password. Your client must be on the same servers the victims use:
   the public RustDesk servers by default, or your self-hosted server if
   you set `$ConfigString` in `install.ps1` (machines with a Pro config
   string also show up in the RustDesk Server Pro web console).

## Beacon sequence (in docker logs)

Common (all tools):

    stage1-start → dropped → first-exec → persist → done →
    rmm-start-<tool> → <tool>-installed

Tool-specific extras: `splashtop-wizard-launch`, `splashtop-installed`,
`rustdesk-password-set`, `rustdesk-id-<ID>`, `rustdesk-installed`,
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

### Adding a new RMM tool (short version)

1. `mkdir ttx/rmm/<newtool>`
2. Write `ttx/rmm/<newtool>/manifest` (copy an existing one and edit)
3. Write `ttx/rmm/<newtool>/install.ps1` — copy an existing one as a
   template; keep the `$Base`-relative download URL, the `Beacon()` calls
   (prefix your beacon names with the tool id), and a process-name check
4. Add `cleanup-scripts/tools/<newtool>.ps1` so victims can be reset
5. Place the tool's payload binary and note where to get it in the
   manifest's README line

That's it — the menu, container validation, URL rewriting, and bind-mount
all pick it up automatically. No core-script edits. Full walkthrough with
field-by-field notes and testing steps: **EXTENDING.md**.

## Victim cleanup (reset a machine for a re-run)

`cleanup-scripts/cleanup-victim.ps1` removes everything this attack chain
drops on a victim: the `WindowsVerification` scheduled task, the dropped
loader + cached installer scripts, and the installed RMM agent (Splashtop
and RustDesk cleanups ship in `cleanup-scripts/tools/`). Run it elevated on
the victim:

    powershell -ExecutionPolicy Bypass -File cleanup-scripts\cleanup-victim.ps1

It is idempotent, auto-relaunches elevated if needed, and **verifies every
removal** — items that survive are flagged `[STILL ON]` and the script
exits non-zero (reboot the victim and re-run to confirm). See
`cleanup-scripts/README.md` for details and for adding cleanups for new tools.

## Session lifecycle
- New URL every launch: `docker compose down && docker compose up -d --build`
- No ports published; cloudflared quick tunnel (URLs rotate per run)
- Payloads persist on the host across rebuilds — you only place them once
  per deployment (not once per session)
- Reused victims: run `cleanup-scripts/cleanup-victim.ps1` first (kills the
  persistence task, uninstalls the RMM agent, clears Public files) — proven
  to produce a working re-run.

## Authorized use only

This project is a **training aid for cybersecurity education and tabletop
exercises** — a simulated ClickFix scenario for teaching and demonstration.
Run it only against systems you own or are explicitly authorized to test,
and hand the lure URL only to consenting participants. If you fork or
adapt it, you are responsible for complying with the policies of any
environment you run it in and with applicable law. The authors accept no
liability for misuse. See **EXTENDING.md** for guidance on making the lab
your own.
