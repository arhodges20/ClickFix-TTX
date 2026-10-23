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
1. Download the Streamer MSI from your Splashtop console
   (my.splashtop.com → Add/deploy remote computer → deploy by 12-digit code
   → Streamer MSI download). It arrives as a .zip — extract the .msi.
2. Place it in the repo: `ttx/rmm/streamer.msi`
   (NOT committed to git — it's bound to your team)

## Launch
    docker compose up -d --build

    # Get the victim URL:
    docker logs ttx-lab | grep "Send victims"

    # Watch the attack chain:
    docker logs -f ttx-lab

## Victim flow
1. Victim opens https://<tunnel-url>/ttx/ (fake CAPTCHA lure)
2. Copies the command, pastes into PowerShell (elevated recommended)
3. Downloads run (~3-5 min for the MSI), then the install wizard appears
4. User clicks through wizard + approves the org connection
5. Machine appears in your Splashtop Business console → connect

## Beacon sequence (in docker logs)
stage1-start → dropped → first-exec → persist → done →
streamer.msi 200 71369216 → splashtop-wizard-launch → splashtop-installed

## Session lifecycle
- New URL every launch: `docker compose down && docker compose up -d --build`
- No ports published; cloudflared quick tunnel (URLs rotate per run)
- Reused victims: run cleanup-victim.ps1 first (kills persistence task,
  uninstalls streamer, clears Public files) — proven to produce a
  working re-run.

## Gotchas learned the hard way
- streamer.msi is team-bound and ~68MB — supply it per-deployment, never commit
- Victim hosts with the Splashtop Business app installed can produce wizard/
  binding weirdness — test on hosts without it
- /beacon returns 404 by design — query strings are logged (that's the console)
- Prior Splashtop installs on a victim can wedge MSI; cleanup-victim.ps1
  (or reboot the victim) clears it
