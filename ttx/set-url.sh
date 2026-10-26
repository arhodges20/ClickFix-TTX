#!/bin/bash
ROOT=/var/www/html/ttx
URLFILE=$ROOT/.current-url
[ -z "$1" ] && { echo "Usage: ./set-url.sh https://xxxx.trycloudflare.com"; exit 1; }
NEW="$1"
OLD=$(cat "$URLFILE" 2>/dev/null || echo "http://YOUR-HOST:8000")
for f in index.html stage1.ps1 rmm.ps1; do
  # legacy placeholder swap
  sed -i "s|http://YOUR-HOST:8000|$NEW|g" "$ROOT/$f"
  # previous session's URL (tracked in .current-url)
  sed -i "s|$OLD|$NEW|g" "$ROOT/$f"
  # catch-all: rewrite ANY quick-tunnel host still baked into the files,
  # so a stale URL committed to the repo can never survive a rebuild
  sed -i -E "s|https://[a-z0-9-]+\.trycloudflare\.com|$NEW|g" "$ROOT/$f"
done
echo "$NEW" > "$URLFILE"
echo "All payload files now point at: $NEW"
