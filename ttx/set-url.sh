#!/bin/bash
ROOT=/var/www/html/ttx
URLFILE=$ROOT/.current-url
[ -z "$1" ] && { echo "Usage: ./set-url.sh https://xxxx.trycloudflare.com"; exit 1; }
NEW="$1"
OLD=$(cat "$URLFILE" 2>/dev/null || echo "http://YOUR-HOST:8000")
for f in index.html stage1.ps1 rmm.ps1; do
  sed -i "s|http://YOUR-HOST:8000|$NEW|g" "$ROOT/$f"
  sed -i "s|$OLD|$NEW|g" "$ROOT/$f"
done
echo "$NEW" > "$URLFILE"
echo "All payload files now point at: $NEW"
