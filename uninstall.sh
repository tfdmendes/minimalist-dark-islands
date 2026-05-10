#!/usr/bin/env bash

set -euo pipefail

echo "Minimalist Dark Islands Uninstaller for macOS/Linux"
echo "===================================================="
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ "$OSTYPE" == "darwin"* ]]; then
    SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
else
    SETTINGS_DIR="$HOME/.config/Code/User"
fi

SETTINGS_FILE="$SETTINGS_DIR/settings.json"
PRE_DARK_ISLANDS_BACKUP="$SETTINGS_FILE.pre-dark-islands"
LEGACY_PRE_ISLANDS_BACKUP="$SETTINGS_FILE.pre-islands-dark"
THEME_EXT_DIR="$HOME/.vscode/extensions/tfdmendes.minimalist-dark-islands-0.1.0"
UPSTREAM_EXT_DIR="$HOME/.vscode/extensions/bwya77.islands-dark-1.0.0"
STATE_DIR="$HOME/.vscode/minimalist-dark-islands"
ANIMATIONS_DIR="$STATE_DIR"
APPEARANCE_STATE_FILE="$STATE_DIR/pre-dark-islands-appearance.json"

echo "Step 1: Restore Previous VS Code settings"
ORIGINAL_BACKUP=""
RESTORE_LABEL=""
SETTINGS_RESTORED="false"
if [[ -f "$PRE_DARK_ISLANDS_BACKUP" ]]; then
    ORIGINAL_BACKUP="$PRE_DARK_ISLANDS_BACKUP"
    RESTORE_LABEL="pre-dark-islands original settings"
elif [[ -f "$LEGACY_PRE_ISLANDS_BACKUP" ]]; then
    ORIGINAL_BACKUP="$LEGACY_PRE_ISLANDS_BACKUP"
    RESTORE_LABEL="legacy pre-islands-dark original settings"
fi

LATEST_BACKUP=""
if ls "$SETTINGS_FILE".backup-* >/dev/null 2>&1; then
    LATEST_BACKUP="$(ls -t "$SETTINGS_FILE".backup-* 2>/dev/null | head -n 1)"
fi

if [[ -n "$ORIGINAL_BACKUP" ]]; then
    echo "Found $RESTORE_LABEL:"
    echo "$ORIGINAL_BACKUP"
    read -r -p "Restore original pre-dark-islands settings now? [y/N] " RESTORE_BACKUP
    case "$RESTORE_BACKUP" in
        y|Y|yes|YES)
            mkdir -p "$SETTINGS_DIR"
            cp "$ORIGINAL_BACKUP" "$SETTINGS_FILE"
            echo -e "${GREEN}Original settings restored.${NC}"
            SETTINGS_RESTORED="true"
            ;;
        *)
            echo "Full settings restore skipped."
            ;;
    esac
elif [[ -n "$LATEST_BACKUP" ]]; then
    echo -e "${YELLOW}No pre-dark-islands baseline backup found.${NC}"
    echo "Latest timestamped backup is:"
    echo "$LATEST_BACKUP"
    read -r -p "Restore this latest backup instead? [y/N] " RESTORE_BACKUP
    case "$RESTORE_BACKUP" in
        y|Y|yes|YES)
            mkdir -p "$SETTINGS_DIR"
            cp "$LATEST_BACKUP" "$SETTINGS_FILE"
            echo -e "${GREEN}Settings restored from latest backup.${NC}"
            SETTINGS_RESTORED="true"
            ;;
        *)
            echo "Timestamped backup restore skipped."
            ;;
    esac
else
    echo -e "${YELLOW}No settings backup found.${NC}"
fi

if [[ "$SETTINGS_RESTORED" == "false" && -f "$APPEARANCE_STATE_FILE" ]]; then
    echo ""
    echo "Theme/appearance restore state found:"
    echo "$APPEARANCE_STATE_FILE"
    read -r -p "Restore only previous theme/icon/custom UI appearance settings? [y/N] " RESTORE_APPEARANCE
    case "$RESTORE_APPEARANCE" in
        y|Y|yes|YES)
            if command -v python3 >/dev/null 2>&1; then
                mkdir -p "$SETTINGS_DIR"
                python3 - "$SETTINGS_FILE" "$APPEARANCE_STATE_FILE" <<'PYEOF'
import json
import os
import re
import sys

settings_path, state_path = sys.argv[1], sys.argv[2]

def read_jsonc(path):
    if not os.path.exists(path):
        return {}
    text = open(path, "r", encoding="utf-8").read()
    if not text.strip():
        return {}
    text = re.sub(r"(?m)^(\s*//.*)$", "", text)
    text = re.sub(r"/\*[\s\S]*?\*/", "", text)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return json.loads(text) if text.strip() else {}

settings = read_jsonc(settings_path)
state = json.load(open(state_path, "r", encoding="utf-8"))
theme_settings = state.get("themeRelatedSettings", {})

for key, record in theme_settings.items():
    if record.get("present"):
        settings[key] = record.get("value")
    else:
        settings.pop(key, None)

clean = {
    k: v for k, v in settings.items()
    if not (isinstance(k, str) and k.startswith("//"))
}

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(clean, f, indent=4, ensure_ascii=False)
    f.write("\n")
PYEOF
                echo -e "${GREEN}Previous theme/appearance settings restored.${NC}"
                SETTINGS_RESTORED="true"
            else
                echo -e "${YELLOW}python3 not found; could not restore appearance state.${NC}"
            fi
            ;;
        *)
            echo "Theme/appearance settings left unchanged."
            ;;
    esac
elif [[ "$SETTINGS_RESTORED" == "false" ]]; then
    echo "Settings left unchanged."
fi

echo ""
echo "Step 2: Remove local extension files"
REMOVED_ANY="false"
for dir in "$THEME_EXT_DIR" "$UPSTREAM_EXT_DIR"; do
    if [[ -d "$dir" || -L "$dir" ]]; then
        rm -rf "$dir"
        echo -e "${GREEN}Removed:${NC} $dir"
        REMOVED_ANY="true"
    fi
done
if [[ "$REMOVED_ANY" == "false" ]]; then
    echo "No local theme extension directories found."
fi

echo ""
echo "Step 3: Remove animation assets"
if [[ -d "$ANIMATIONS_DIR" ]]; then
    rm -rf "$ANIMATIONS_DIR"
    echo -e "${GREEN}Removed:${NC} $ANIMATIONS_DIR"
else
    echo "No animation asset directory found."
fi

echo ""
echo "Step 4: Unregister local extension metadata"
if command -v node >/dev/null 2>&1; then
    node <<'UNREGISTER_SCRIPT'
const fs = require('fs');
const path = require('path');

const extJsonPath = path.join(process.env.HOME, '.vscode', 'extensions', 'extensions.json');
const idsToRemove = new Set([
  'tfdmendes.minimalist-dark-islands',
  'bwya77.islands-dark',
  'your-publisher-name.islands-dark',
]);

if (fs.existsSync(extJsonPath)) {
  try {
    const raw = fs.readFileSync(extJsonPath, 'utf8');
    let extensions = JSON.parse(raw);
    const before = extensions.length;
    extensions = extensions.filter(entry => !idsToRemove.has(entry.identifier?.id));
    if (extensions.length < before) {
      fs.writeFileSync(extJsonPath, JSON.stringify(extensions, null, 2));
      console.log('Extension metadata updated');
    } else {
      console.log('No matching extension metadata found');
    }
  } catch {
    console.log('Could not update extensions.json');
  }
}
UNREGISTER_SCRIPT
else
    echo "Node not found; skipped extensions.json cleanup."
fi

echo ""
echo "Step 5: Disable Custom UI Style"
echo -e "${YELLOW}Disable/reload Custom UI Style manually to remove injected CSS:${NC}"
echo "1. Open Command Palette (Cmd+Shift+P / Ctrl+Shift+P)"
echo "2. Run 'Custom UI Style: Disable'"
echo "3. Reload VS Code"

echo ""
echo -e "${GREEN}Minimalist Dark Islands uninstall cleanup complete.${NC}"
