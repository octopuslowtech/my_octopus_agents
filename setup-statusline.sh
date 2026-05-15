#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/statusline.sh"
TARGET_DIR="$HOME/.claude"
TARGET_FILE="$TARGET_DIR/statusline.sh"
SETTINGS_FILE="$TARGET_DIR/settings.json"

GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
RED=$(printf '\033[0;31m')
BLUE=$(printf '\033[0;34m')
NC=$(printf '\033[0m')

echo "${BLUE}Setting up Claudible statusline locally...${NC}"

if [ ! -f "$SOURCE_FILE" ]; then
    echo "${RED}Error: $SOURCE_FILE not found${NC}"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "${RED}Error: jq is required but not installed${NC}"
    echo "  Install: choco install jq  (Windows)  |  brew install jq  (macOS)  |  sudo apt-get install jq  (Linux)"
    exit 1
fi

mkdir -p "$TARGET_DIR"

if [ -f "$TARGET_FILE" ]; then
    cp "$TARGET_FILE" "${TARGET_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    echo "${YELLOW}  Backed up existing statusline.sh${NC}"
fi

cp "$SOURCE_FILE" "$TARGET_FILE"
chmod +x "$TARGET_FILE"
echo "${GREEN}  Copied statusline.sh to $TARGET_FILE${NC}"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup.$(date +%Y%m%d%H%M%S)"
echo "${YELLOW}  Backed up settings.json${NC}"

TMP_FILE=$(mktemp)
jq '.statusLine = {"type": "command", "command": "bash ~/.claude/statusline.sh"}' \
    "$SETTINGS_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$SETTINGS_FILE"

echo "${GREEN}  Updated settings.json with statusLine config${NC}"
echo ""
echo "${GREEN}Done. Restart Claude Code to see the statusline.${NC}"
