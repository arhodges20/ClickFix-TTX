#!/bin/bash
ROOT=/var/www/html/ttx
URLFILE=$ROOT/.current-url
[ -z "$1" ] && { echo "Usage: ./set-url.sh https://xxxx.trycloudflare.com"; exit 1; }
NEW="$1"
OLD=$(cat "$URLFILE" 2>/dev/null || echo "http://YOUR-HOST:8000")

# Core files + every RMM tool module's install.ps1 (glob - new tools are
# picked up automatically with no edits here)
FILES=("$ROOT/index.html" "$ROOT/stage1.ps1" "$ROOT/rmm.ps1" "$ROOT"/rmm/*/install.ps1)

for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  # legacy placeholder swap
  sed -i "s|http://YOUR-HOST:8000|$NEW|g" "$f"
  # previous session's URL (tracked in .current-url)
  sed -i "s|$OLD|$NEW|g" "$f"
  # catch-all: rewrite ANY quick-tunnel host still baked into the files,
  # so a stale URL committed to the repo can never survive a rebuild
  sed -i -E "s|https://[a-z0-9-]+\.trycloudflare\.com|$NEW|g" "$f"
done
echo "$NEW" > "$URLFILE"
echo "All payload files now point at: $NEW"
