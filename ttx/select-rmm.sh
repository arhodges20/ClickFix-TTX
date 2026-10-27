#!/bin/bash
# select-rmm.sh - validate + activate the operator's chosen RMM tool
# Usage: select-rmm.sh <tool-id>   (run inside the container by entrypoint.sh)
#
# - discovers available tools from ttx/rmm/*/manifest
# - fails fast if the requested tool is unknown (lists valid options)
# - injects the tool id into rmm.ps1 (__RMM_TOOL__ placeholder)
# - warns (but does not fail) if the tool's payload binary is missing, so
#   partial testing still works
set -e
ROOT=/var/www/html/ttx
TOOL="${1:-splashtop}"

# ---- discover available tool modules --------------------------------------
declare -a IDS NAMES FILES
while IFS= read -r m; do
  TOOL_ID=""; DISPLAY_NAME=""; PAYLOAD_FILE=""
  # shellcheck disable=SC1090
  . "$m"
  [ -n "$TOOL_ID" ] || { echo "ERROR: $m has no TOOL_ID"; exit 1; }
  IDS+=("$TOOL_ID"); NAMES+=("$DISPLAY_NAME"); FILES+=("$PAYLOAD_FILE")
done < <(find "$ROOT/rmm" -mindepth 2 -maxdepth 2 -name manifest | sort)

[ "${#IDS[@]}" -gt 0 ] || { echo "ERROR: no tool manifests found under rmm/*/manifest"; exit 1; }

# ---- locate the requested tool --------------------------------------------
FOUND=""
for i in "${!IDS[@]}"; do
  if [ "${IDS[$i]}" = "$TOOL" ]; then FOUND=$i; fi
done
if [ -z "$FOUND" ]; then
  echo "ERROR: unknown RMM_TOOL '$TOOL'. Valid options: ${IDS[*]}"
  exit 1
fi

NAME="${NAMES[$FOUND]}"
PAYLOAD="${FILES[$FOUND]}"
PAYLOAD_PATH="$ROOT/rmm/$TOOL/$PAYLOAD"

# ---- activate: inject the tool id into the loader (idempotent on restarts)
sed -i "s|__RMM_TOOL__|$TOOL|g" "$ROOT/rmm.ps1"

# ---- payload presence check (warn only - partial testing is allowed) ------
if [ -n "$PAYLOAD" ] && [ ! -f "$PAYLOAD_PATH" ]; then
  echo "WARNING: payload for '$TOOL' not found at rmm/$TOOL/$PAYLOAD -"
  echo "         lure + clipboard + beacons work, but the victim install"
  echo "         will fail at the payload download step."
fi

echo "$TOOL ($NAME)" > "$ROOT/.active-rmm"
echo "select-rmm: active tool = $TOOL ($NAME)"
