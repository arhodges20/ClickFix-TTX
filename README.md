# TTX Lab — ClickFix → Splashtop Streamer Deployment

One-command ClickFix training scenario. Victim pastes a command from a
fake CAPTCHA page → stage1 drops rmm.ps1 with logon persistence →
downloads the Splashtop Streamer MSI → visible install wizard →
user approves org access → machine joins the operator's Splashtop
Business console.

## Requirements
- Docker host (any Linux box, no inbound ports needed — tunnel is outbound-only)
- Splashtop Business account + a deployment download
- One victim Windows host (ideally WITHOUT the Splashtop Business app installed)

## Setup (one-time)

### Step 1: Clone the repo
    git clone https://github.com/arhodges20/ClickFix-TTX.git
    cd ClickFix-TTX

### Step 2: Get the Streamer MSI and place it in the repo

The Streamer MSI is team-bound to your Splashtop deployment and is NEVER
committed to git — it must be placed manually after cloning.

1. Download the Streamer MSI from your Splashtop console
   (my.splashtop.com → Add/deploy remote computer → deploy by 12-digit code
   → Streamer MSI download). It arrives as a .zip — extract the .msi.
2. Copy it into the repo folder so it sits at:

       ttx/rmm/streamer.msi

   the file must be named exactly `streamer.msi`, because that's the
   name the victim-side payload (`rmm.ps1`) downloads.

Verifying placement (expected output shown):

    $ ls -lh ttx/rmm/
    -rw-r--r-- 1 user user 68M Mar 1 10:00 streamer.msi

The `ttx/rmm/` folder on the server is bind-mounted into the container,
so the MSI is picked up automatically — no rebuild required. If you ever
swap in a different deployment's MSI, just replace the file and restart
(`docker compose restart`).

You can launch without the MSI (lure page, clipboard copy, and beacons
all work — see "Partial testing" below), but the full victim flow will
fail at the MSI download step until one is in place.

## Launch
    docker compose up -d --build

    # Wait ~15 seconds for the tunnel to come up, then get the victim URL:
    docker logs ttx-lab | grep "Send victims"

    # Watch the attack chain:
    docker logs -f ttx-lab

## Verify the MSI is being served

Before handing the URL to a victim, confirm the container can serve the MSI:

    # Get your current tunnel URL
    URL=$(docker logs ttx-lab | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1)

    curl -I $URL/ttx/rmm/streamer.msi

Expected: `HTTP/2 200` with `Content-Length` around 71,000,000 (your MSI's
exact size). A `404` means the MSI isn't in `ttx/rmm/` on the host — recheck
Step 2. A `200` in the docker logs (`streamer.msi 200 <size>`) confirms
each victim download.

## Partial testing (no MSI, no victim needed)

You can test everything up to (but not including) the actual payload run
without placing an MSI or using a victim machine:

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
3. Downloads run (~3-5 min for the MSI), then the install wizard appears
4. User clicks through wizard + approves the org connection
5. Machine appears in your Splashtop Business console → connect

## Beacon sequence (in docker logs)
stage1-start → dropped → first-exec → persist → done →
streamer.msi 200 71369216 → splashtop-wizard-launch → splashtop-installed

(If you see `rmm-download-failed` instead of the streamer.msi 200 line,
the MSI is missing on the server — see "Verify the MSI is being served".)

## Session lifecycle
- New URL every launch: `docker compose down && docker compose up -d --build`
- No ports published; cloudflared quick tunnel (URLs rotate per run)
- The MSI persists on the host across rebuilds — you only place it once per
  deployment (not once per session)
- Reused victims: run cleanup-victim.ps1 first (kills persistence task,
  uninstalls streamer, clears Public files) — proven to produce a
  working re-run.
