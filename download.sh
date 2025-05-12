#!/usr/bin/env zsh
set -euo pipefail

# usage check
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <URL>" >&2
  exit 1
fi

GIF_URL="$1"

# create a temp file base
if ! BASE=$(mktemp); then
  echo "Error: Unable to create temporary file." >&2
  exit 1
fi

EXTENSION="${GIF_URL##*.}"
TEMP_FILE="${BASE}.${EXTENSION}"

# download the GIF
if ! curl -fsSL --output "$TEMP_FILE" "$GIF_URL"; then
  echo "Error: Failed to download GIF from $GIF_URL" >&2
  exit 1
fi

# copy the path to clipboard 
open ./CopyFile.app --args $TEMP_FILE

echo "GIF downloaded and path copied to clipboard: $TEMP_FILE"
exit 0
