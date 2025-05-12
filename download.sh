#!/usr/bin/env zsh

# Check if a URL was provided as an argument
if [ -z "$1" ]; then
  echo "Error: Please provide a URL as an argument." >&2
  exit 1
fi

# Get the URL using curl and grep
URL=$(curl -f -s "$1" 2>/dev/null | grep -o '"url": "[^"]*\.gif"' | head -1 | cut -d'"' -f4)

#check if URL is empty, and if it is then provide helpful error and exit.
if [ -z "$URL" ]; then
    echo "Error: Could not find a .gif URL in the provided page, or curl failed." >&2
    echo "Please check the URL and try again." >&2
    exit 1
fi

# Temp file setup
TEMP_NAME=$(mktemp); EXTENTION="${URL##*.}"; TEMP_FILE="${TEMP_NAME}.${EXTENTION}"

# Check if mktemp was successful.
if [ -z "$TEMP_FILE" ]; then
    echo "Error: Could not create temporary file." >&2
    exit 1
fi

# Crucially, set a trap to remove the file on exit
#trap 'rm -f "$TEMP_FILE"' EXIT HUP INT QUIT TERM

# Download the GIF to the temp file
if ! curl --fail --location --silent "$URL" --output "$TEMP_FILE"; then
echo "Error: $TEMP_FILE" >&2
  echo "Error: Failed to download the GIF from: $URL" >&2
  exit 1
fi

# Copy the path to the temp file to the clipboard using osascript
osascript -e "
on alfred_script(q)
    set thePath to q
    set the clipboard to POSIX file thePath
end alfred_script

alfred_script(\"$TEMP_FILE\")
"

echo "GIF downloaded and file path copied to clipboard: $TEMP_FILE"

exit 0
