#!/usr/bin/env bash
# Minimalist Dark Islands - Interactive Installer (p10k-style)
# Each question lives on its own cleared screen, with a header that shows
# progress and a brief description of what the option does. At the end a
# summary screen lists everything that will happen and asks for one final
# confirmation before any change is applied.
#
# Designed for users who already have a customized User settings.json
# (own color theme, font preferences, etc.) and only want to layer the
# glass-islands CSS on top without losing their settings.

set -e
set -u

# Resolve the directory this script lives in (works on macOS and Linux).
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ---------------------------------------------------------------------------
# Colors and printable symbols. Pure ASCII glyphs only (no emojis).
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

CHECK_MARK="${GREEN}[x]${NC}"
EMPTY_BOX="[ ]"
ARROW="${BLUE}>${NC}"

# ---------------------------------------------------------------------------
# State variables. Each step toggles its own flag.
# Defaults reflect the most common case for this fork:
#   - install all the visual pieces
#   - keep the user's existing color theme
#   - DO NOT enable the icon glow by default (most users find it noisy)
# ---------------------------------------------------------------------------
DO_INSTALL_CUSTOM_UI_STYLE="false"
DO_INSTALL_THEME_EXTENSION="false"
DO_SET_COLOR_THEME="false"
DO_INSTALL_BEAR_FONTS="false"
DO_INSTALL_SETI_ICONS="false"
DO_SET_ICON_THEME="false"
DO_MERGE_CSS="false"
DO_APPLY_MINIMAL_SETTINGS="false"
DO_ENABLE_ANIMATIONS="false"
DO_ENABLE_ICON_GLOW="false"

# Activity bar position. One of: default, top, bottom, hidden. Written to
# the user's settings.json (workbench.activityBar.location) and used by
# the Python merge to pick the matching CSS variant for the activity bar.
ACTIVITY_BAR_LOCATION="default"

# ---------------------------------------------------------------------------
# Step counter for the progress indicator. Incremented every time
# step_header() is called.
# ---------------------------------------------------------------------------
CURRENT_STEP=0
TOTAL_STEPS=11

# ---------------------------------------------------------------------------
# Generic helpers
# ---------------------------------------------------------------------------

# Clear the visible terminal area. Falls back to ANSI escapes when
# tput / clear are missing (e.g. minimal containers).
clear_screen() {
    if command -v tput >/dev/null 2>&1; then
        tput clear 2>/dev/null || printf '\033[2J\033[H'
    elif command -v clear >/dev/null 2>&1; then
        clear
    else
        printf '\033[2J\033[H'
    fi
}

# Render the banner shown at the top of every question screen. Includes
# the global step counter so the user can see how far along they are.
step_header() {
    local title="$1"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    clear_screen
    printf "\n"
    printf "  %b============================================================%b\n" "$CYAN" "$NC"
    printf "  %b  Minimalist Dark Islands  -  step %d of %d%b\n" "$BOLD" "$CURRENT_STEP" "$TOTAL_STEPS" "$NC"
    printf "  %b============================================================%b\n\n" "$CYAN" "$NC"
    printf "  %b%s%b\n\n" "$BOLD" "$title" "$NC"
}

# Plain section banner used for the welcome / summary / execute screens
# (no step counter).
banner() {
    local title="$1"
    clear_screen
    printf "\n"
    printf "  %b============================================================%b\n" "$CYAN" "$NC"
    printf "  %b  %s%b\n" "$BOLD" "$title" "$NC"
    printf "  %b============================================================%b\n\n" "$CYAN" "$NC"
}

# Print a paragraph of body text indented to match the header.
body() {
    while [[ $# -gt 0 ]]; do
        printf "  %s\n" "$1"
        shift
    done
}

# Same as body() but in dim/gray color, for hint / description text.
hint() {
    while [[ $# -gt 0 ]]; do
        printf "  %b%s%b\n" "$GRAY" "$1" "$NC"
        shift
    done
}

# Wait for the user to press Enter. Used after auto-detected steps
# where there is no question to answer but we still want them to read
# the status before the screen clears.
press_enter() {
    printf "\n  %bPress Enter to continue...%b" "$DIM" "$NC"
    read -r _ignored
}

# Yes / no prompt. $1 prompt text, $2 default ("y" or "n"), $3 var name.
ask_yn() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local hint_text
    if [[ "$default" == "y" ]]; then
        hint_text="[Y/n]"
    else
        hint_text="[y/N]"
    fi
    local answer
    read -r -p "$(printf '\n  %b %s %s ' "$ARROW" "$prompt" "$hint_text")" answer
    answer="${answer:-$default}"
    case "$answer" in
        y|Y|yes|YES) eval "$var_name=true" ;;
        *)           eval "$var_name=false" ;;
    esac
}

# Multi-choice prompt. Caller passes a default index (1-based) and a list
# of option labels. The selected number (1-based) is stored in the named
# variable. Pressing Enter accepts the default.
#
# Usage:
#   ask_choice "Question?" CHOICE_VAR 1 "Option A" "Option B" "Option C"
ask_choice() {
    local prompt="$1"
    local var_name="$2"
    local default_idx="$3"
    shift 3
    local labels=("$@")

    printf "\n"
    local i=1
    for label in "${labels[@]}"; do
        if [[ "$i" -eq "$default_idx" ]]; then
            printf "    %b%d) %s%b  %b(default)%b\n" "$BOLD" "$i" "$label" "$NC" "$DIM" "$NC"
        else
            printf "    %d) %s\n" "$i" "$label"
        fi
        i=$((i+1))
    done

    local choice
    read -r -p "$(printf '\n  %b %s [1-%d]: ' "$ARROW" "$prompt" "${#labels[@]}")" choice
    choice="${choice:-$default_idx}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#labels[@]}" ]]; then
        eval "$var_name=\$choice"
    else
        eval "$var_name=\$default_idx"
    fi
}

# Render one row of the final checklist.
print_choice() {
    if [[ "$1" == "true" ]]; then
        printf "    %b %s\n" "$CHECK_MARK" "$2"
    else
        printf "    %s %s\n" "$EMPTY_BOX" "$2"
    fi
}

# Abort with an error message.
die() {
    printf "\n  %bError:%b %s\n\n" "$RED" "$NC" "$1" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if [[ ! -f "$SCRIPT_DIR/settings.json" ]]; then
    die "settings.json not found in $SCRIPT_DIR. Run this script from the repo root."
fi

if [[ ! -f "$SCRIPT_DIR/animations.css" ]]; then
    die "animations.css not found in $SCRIPT_DIR. Run this script from the repo root."
fi

if ! command -v python3 >/dev/null 2>&1; then
    die "python3 is required for the JSON merge step. Install it and try again."
fi

HAS_CODE_CLI="true"
if ! command -v code >/dev/null 2>&1; then
    HAS_CODE_CLI="false"
fi

# Detect the OS-specific font directory. Used both for the font copy
# step and for showing the path in the prompt.
if [[ "$OSTYPE" == "darwin"* ]]; then
    FONT_DIR="$HOME/Library/Fonts"
    SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
else
    FONT_DIR="$HOME/.local/share/fonts"
    SETTINGS_DIR="$HOME/.config/Code/User"
fi

SETTINGS_FILE="$SETTINGS_DIR/settings.json"
PRE_DARK_ISLANDS_BACKUP="$SETTINGS_FILE.pre-dark-islands"
THEME_EXT_ID="tfdmendes.minimalist-dark-islands"
THEME_EXT_VERSION="0.1.0"
THEME_EXT_DIR="$HOME/.vscode/extensions/$THEME_EXT_ID-$THEME_EXT_VERSION"
STATE_DIR="$HOME/.vscode/minimalist-dark-islands"
ANIMATIONS_INSTALL_DIR="$STATE_DIR"
ANIMATIONS_FILE="$ANIMATIONS_INSTALL_DIR/animations.css"
ANIMATIONS_IMPORT="file://$ANIMATIONS_FILE"
APPEARANCE_STATE_FILE="$STATE_DIR/pre-dark-islands-appearance.json"
EXTENSIONS_METADATA_FILE="$HOME/.vscode/extensions/extensions.json"
EXTENSIONS_METADATA_BACKUP="$STATE_DIR/extensions.json.pre-dark-islands"

CURRENT_ACTIVITY_BAR_LOCATION="default"
if [[ -f "$SETTINGS_FILE" ]]; then
    CURRENT_ACTIVITY_BAR_LOCATION="$(python3 - "$SETTINGS_FILE" <<'PYEOF' 2>/dev/null || printf "default"
import json
import re
import sys

path = sys.argv[1]
try:
    text = open(path, "r", encoding="utf-8").read()
    text = re.sub(r"(?m)^(\s*//.*)$", "", text)
    text = re.sub(r"/\*[\s\S]*?\*/", "", text)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    data = json.loads(text) if text.strip() else {}
    value = data.get("workbench.activityBar.location", "default")
    print(value if value in ("default", "top", "bottom", "hidden") else "default")
except Exception:
    print("default")
PYEOF
)"
fi

# ---------------------------------------------------------------------------
# Welcome screen
# ---------------------------------------------------------------------------
banner "Minimalist Dark Islands  -  Installer"
body "This installer will walk you through, one screen at a time, every"
body "optional piece of the theme. Each step shows a short description"
body "and asks one yes/no question."
printf "\n"
body "Nothing on your machine changes until the final summary screen,"
body "where you confirm everything before it runs. Your User settings.json"
body "is backed up automatically before any merge."
printf "\n"
if [[ "$HAS_CODE_CLI" == "false" ]]; then
    hint "Note: 'code' CLI is not in your PATH. Extension-install steps"
    hint "      will be skipped. To enable, open VS Code -> Cmd+Shift+P ->"
    hint "      'Shell Command: Install code command in PATH'."
    printf "\n"
fi
press_enter

# ---------------------------------------------------------------------------
# Step 1: Minimalist Dark Islands color theme extension
# ---------------------------------------------------------------------------
step_header "Minimalist Dark Islands color theme"
body "Optional. This installs the fork as a local VS Code color theme,"
body "matching the upstream installer behavior, but it does not force"
body "you to use it. You can keep One Dark Pro Mix or any other theme."
printf "\n"
hint "Local extension path: $THEME_EXT_DIR"

THEME_INSTALLED="false"
if [[ -d "$THEME_EXT_DIR" ]]; then
    THEME_INSTALLED="true"
    printf "\n  %b Already installed - nothing to do.\n" "$CHECK_MARK"
    press_enter
elif [[ ! -f "$SCRIPT_DIR/package.json" ]]; then
    printf "\n  %bSkipped: package.json missing in this repo.%b\n" "$YELLOW" "$NC"
    press_enter
else
    ask_yn "Install the local Minimalist Dark Islands theme extension?" "n" DO_INSTALL_THEME_EXTENSION
fi

# ---------------------------------------------------------------------------
# Step 2: Set Minimalist Dark Islands as the active color theme
# ---------------------------------------------------------------------------
step_header "Set color theme"
body "Optional. If you confirm, this writes:"
body ""
body "    workbench.colorTheme = Minimalist Dark Islands"
body ""
body "Skip this if you want to keep your current color theme; the CSS"
body "islands can still run on top of One Dark Pro Mix or another theme."

if [[ "$THEME_INSTALLED" == "true" || "$DO_INSTALL_THEME_EXTENSION" == "true" ]]; then
    ask_yn "Set Minimalist Dark Islands as the active color theme?" "n" DO_SET_COLOR_THEME
else
    printf "\n  %bTheme extension is not installed and will not be installed.%b\n" "$GRAY" "$NC"
    body "Nothing to set."
    DO_SET_COLOR_THEME="false"
    press_enter
fi

# ---------------------------------------------------------------------------
# Step 3: Custom UI Style extension
# ---------------------------------------------------------------------------
step_header "Custom UI Style extension"
hint "subframe7536.custom-ui-style"
printf "\n"
body "This is the extension that injects the glass-islands CSS into"
body "VS Code's workbench at startup. It is required for any of the"
body "visual styling to actually show up."

CUSTOM_UI_INSTALLED="false"
if [[ "$HAS_CODE_CLI" == "true" ]] && \
   code --list-extensions 2>/dev/null | grep -qi "subframe7536.custom-ui-style"; then
    CUSTOM_UI_INSTALLED="true"
    printf "\n  %b Already installed - nothing to do.\n" "$CHECK_MARK"
    press_enter
elif [[ "$HAS_CODE_CLI" == "false" ]]; then
    printf "\n  %bSkipped: 'code' CLI not in PATH.%b\n" "$YELLOW" "$NC"
    press_enter
else
    ask_yn "Install Custom UI Style now?" "y" DO_INSTALL_CUSTOM_UI_STYLE
fi

# ---------------------------------------------------------------------------
# Step 4: Bear Sans UI fonts
# ---------------------------------------------------------------------------
step_header "Bear Sans UI fonts"
body "The CSS uses Bear Sans UI for the sidebar, tabs, command center,"
body "and status bar. Without it those areas fall back to the system"
body "font and lose a bit of the polish."
printf "\n"
hint "Will be copied to: $FONT_DIR"

BEAR_INSTALLED="false"
if ls "$FONT_DIR"/BearSansUI*.otf >/dev/null 2>&1; then
    BEAR_INSTALLED="true"
    printf "\n  %b Already present in %s.\n" "$CHECK_MARK" "$FONT_DIR"
    press_enter
else
    ask_yn "Copy fonts to $FONT_DIR ?" "y" DO_INSTALL_BEAR_FONTS
fi

# ---------------------------------------------------------------------------
# Step 5: Seti Folder icon theme
# ---------------------------------------------------------------------------
step_header "Seti Folder icon theme"
hint "l-igh-t.vscode-theme-seti-folder"
printf "\n"
body "Optional. Pairs nicely with this theme: distinct, color-coded"
body "folder and file icons. Independent from the glow effect (asked"
body "later); you can have the icon set without the glow."

SETI_INSTALLED="false"
if [[ "$HAS_CODE_CLI" == "true" ]] && \
   code --list-extensions 2>/dev/null | grep -qi "l-igh-t.vscode-theme-seti-folder"; then
    SETI_INSTALLED="true"
    printf "\n  %b Already installed.\n" "$CHECK_MARK"
    press_enter
elif [[ "$HAS_CODE_CLI" == "false" ]]; then
    printf "\n  %bSkipped: 'code' CLI not in PATH.%b\n" "$YELLOW" "$NC"
    press_enter
else
    ask_yn "Install Seti Folder?" "y" DO_INSTALL_SETI_ICONS
fi

# ---------------------------------------------------------------------------
# Step 6: Set Seti Folder as the active icon theme
# Only relevant if Seti is installed (or about to be).
# ---------------------------------------------------------------------------
step_header "Set Seti Folder as your icon theme"
body "If you confirm, this writes:"
body ""
body "    workbench.iconTheme = vs-seti-folder"
body ""
body "to your User settings.json. Skip this if you already prefer a"
body "different icon theme; the rest of the installer still works."

if [[ "$SETI_INSTALLED" == "true" || "$DO_INSTALL_SETI_ICONS" == "true" ]]; then
    ask_yn "Set Seti Folder as the active icon theme?" "y" DO_SET_ICON_THEME
else
    printf "\n  %bSeti Folder is not installed and will not be installed.%b\n" "$GRAY" "$NC"
    body "Nothing to set."
    DO_SET_ICON_THEME="false"
    press_enter
fi

# ---------------------------------------------------------------------------
# Step 7: Merge custom-ui-style.stylesheet into User settings
# ---------------------------------------------------------------------------
step_header "Merge the glass-islands CSS"
body "This is the heart of the install: it copies the entire"
body "'custom-ui-style.stylesheet' block from this repo into your"
body "User settings.json. Without this step, even with the extension"
body "installed, you will see no visual change."
printf "\n"
body "Your existing User settings (color theme, font, language settings,"
body "everything else) are preserved. On the first confirmed run, a"
body "baseline backup is created and never overwritten:"
hint "  $PRE_DARK_ISLANDS_BACKUP"
printf "\n"
body "A timestamped backup is also saved before every settings write:"
hint "  $SETTINGS_FILE.backup-YYYYMMDD-HHMMSS"
printf "\n"
hint "Warning: JSONC line comments (// ...) in your settings.json are"
hint "         lost in the merge. Restore from backup if you need them."

ask_yn "Merge the CSS into your settings.json now?" "y" DO_MERGE_CSS

# ---------------------------------------------------------------------------
# Step 8: Apply minimalist top bar settings
# ---------------------------------------------------------------------------
step_header "Apply minimalist top bar settings"
body "Sets these keys in your User settings.json:"
body ""
body "    window.commandCenter            = false"
body "    workbench.layoutControl.enabled = false"
body "    workbench.editor.empty.hint     = hidden"
body "    workbench.startupEditor         = none"
body "    workbench.tree.indent           = 6"
body "    workbench.tree.renderIndentGuides = always"
body "    workbench.colorCustomizations   = One Dark surface palette"
printf "\n"
hint "Activity bar position is asked separately in the next step."

ask_yn "Apply these minimalist settings?" "y" DO_APPLY_MINIMAL_SETTINGS

# ---------------------------------------------------------------------------
# Step 9: Activity bar position
# Each location uses its own CSS variant so the glass effect renders
# correctly regardless of where the icons live.
# ---------------------------------------------------------------------------
step_header "Activity bar position"
body "Choose where the activity bar (the row of icons for Explorer,"
body "Search, Source Control, Extensions, etc.) should live. The"
body "matching CSS variant is applied so the glass / floating-panel"
body "look stays intact in any of these positions."
printf "\n"
hint "This sets workbench.activityBar.location and rewrites the"
hint "activity-bar / composite-bar rules in your custom-ui-style.stylesheet."
hint "Current detected value: $CURRENT_ACTIVITY_BAR_LOCATION"

_AB_CHOICE=1
case "$CURRENT_ACTIVITY_BAR_LOCATION" in
    top) _AB_DEFAULT=2 ;;
    bottom) _AB_DEFAULT=3 ;;
    hidden) _AB_DEFAULT=4 ;;
    *) _AB_DEFAULT=1 ;;
esac
ask_choice "Pick a position:" _AB_CHOICE "$_AB_DEFAULT" \
    "Default - vertical pill on the left (upstream design)" \
    "Top - horizontal pill above the sidebar" \
    "Bottom - horizontal pill below the sidebar" \
    "Hidden - no activity bar at all"

case "$_AB_CHOICE" in
    1) ACTIVITY_BAR_LOCATION="default" ;;
    2) ACTIVITY_BAR_LOCATION="top" ;;
    3) ACTIVITY_BAR_LOCATION="bottom" ;;
    4) ACTIVITY_BAR_LOCATION="hidden" ;;
esac

# ---------------------------------------------------------------------------
# Step 10: Living Glass animations
# ---------------------------------------------------------------------------
step_header "Living Glass animations"
body "Optional. Installs animations.css to a stable local path and"
body "registers it via custom-ui-style.external.imports. This enables"
body "the animated aurora border, activity icon morph, and widget"
body "entrance animations."
printf "\n"
hint "Installed CSS file: $ANIMATIONS_FILE"
hint "Custom UI Style only loads external files after Reload/Enable."

ask_yn "Enable Living Glass animations?" "y" DO_ENABLE_ANIMATIONS

# ---------------------------------------------------------------------------
# Step 11: File icon glow
# ---------------------------------------------------------------------------
step_header "File icon glow effect"
body "The upstream theme adds a soft colored drop-shadow under every"
body "file icon (matches the icon's tint). Some users like the soft"
body "glow, others find it noisy and prefer the flat icons."
printf "\n"
hint "CSS rule: .monaco-icon-label.file-icon::before { filter: drop-shadow(...) }"
printf "\n"
body "If you say 'no', the rule is stripped from your settings after"
body "the merge, leaving the rest of the theme intact."

ask_yn "Enable the file icon glow?" "n" DO_ENABLE_ICON_GLOW

# ---------------------------------------------------------------------------
# Summary screen
# ---------------------------------------------------------------------------
banner "Summary"
body "Review the actions below. Nothing has been changed yet."
printf "\n"
print_choice "$DO_INSTALL_THEME_EXTENSION" "Install local Minimalist Dark Islands color theme"
print_choice "$DO_SET_COLOR_THEME"         "Set Minimalist Dark Islands as color theme"
print_choice "$DO_INSTALL_CUSTOM_UI_STYLE" "Install Custom UI Style extension"
print_choice "$DO_INSTALL_BEAR_FONTS"      "Install Bear Sans UI fonts to $FONT_DIR"
print_choice "$DO_INSTALL_SETI_ICONS"      "Install Seti Folder icon theme"
print_choice "$DO_SET_ICON_THEME"          "Set Seti Folder as icon theme"
print_choice "$DO_MERGE_CSS"               "Merge glass-islands CSS into User settings.json"
print_choice "$DO_APPLY_MINIMAL_SETTINGS"  "Apply minimalist top bar settings"
printf "    %b->%b Activity bar position: %b%s%b\n" "$BLUE" "$NC" "$BOLD" "$ACTIVITY_BAR_LOCATION" "$NC"
print_choice "$DO_ENABLE_ANIMATIONS"       "Enable Living Glass animations"
print_choice "$DO_ENABLE_ICON_GLOW"        "Enable file icon glow effect"
printf "\n"

# Detect whether anything is selected. The script is built around the
# idea that every run is authoritative: if the user gets to the summary
# and confirms, we write their preferences (including the activity bar
# location and the icon-glow toggle) to settings.json. The only true
# no-op is when the user said no to every install AND every settings
# action AND kept the activity bar at "default".
ANY_SELECTED="false"
for v in \
    "$DO_INSTALL_THEME_EXTENSION" \
    "$DO_SET_COLOR_THEME" \
    "$DO_INSTALL_CUSTOM_UI_STYLE" \
    "$DO_INSTALL_BEAR_FONTS" \
    "$DO_INSTALL_SETI_ICONS" \
    "$DO_SET_ICON_THEME" \
    "$DO_MERGE_CSS" \
    "$DO_APPLY_MINIMAL_SETTINGS" \
    "$DO_ENABLE_ANIMATIONS"
do
    if [[ "$v" == "true" ]]; then
        ANY_SELECTED="true"
    fi
done
if [[ "$DO_ENABLE_ANIMATIONS" == "false" ]]; then
    ANY_SELECTED="true"
fi
if [[ "$DO_ENABLE_ICON_GLOW" == "false" ]]; then
    ANY_SELECTED="true"
fi
# Any non-default activity bar choice counts as a settings write.
if [[ "$ACTIVITY_BAR_LOCATION" != "default" ]]; then
    ANY_SELECTED="true"
fi

if [[ "$ANY_SELECTED" == "false" ]]; then
    body "Nothing to do. Exiting without changes."
    printf "\n"
    exit 0
fi

CONFIRM=""
read -r -p "$(printf '  %b Proceed? [Y/n] ' "$ARROW")" CONFIRM
CONFIRM="${CONFIRM:-y}"
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    printf "\n  %bAborted. No changes were made.%b\n\n" "$RED" "$NC"
    exit 0
fi

# ---------------------------------------------------------------------------
# Execution screen
# ---------------------------------------------------------------------------
banner "Executing"

# 1) Local color theme extension
if [[ "$DO_INSTALL_THEME_EXTENSION" == "true" ]]; then
    printf "  %b Installing local Minimalist Dark Islands theme...\n" "$ARROW"
    mkdir -p "$STATE_DIR"
    if [[ -f "$EXTENSIONS_METADATA_FILE" && ! -f "$EXTENSIONS_METADATA_BACKUP" ]]; then
        cp "$EXTENSIONS_METADATA_FILE" "$EXTENSIONS_METADATA_BACKUP"
        printf "  %b Extension metadata backup saved: %s\n" "$CHECK_MARK" "$EXTENSIONS_METADATA_BACKUP"
    fi
    rm -rf "$THEME_EXT_DIR"
    mkdir -p "$THEME_EXT_DIR"
    cp "$SCRIPT_DIR/package.json" "$THEME_EXT_DIR/"
    cp -r "$SCRIPT_DIR/themes" "$THEME_EXT_DIR/"
    printf "  %b Theme extension installed at %s.\n\n" "$CHECK_MARK" "$THEME_EXT_DIR"
fi

# 2) Custom UI Style extension
if [[ "$DO_INSTALL_CUSTOM_UI_STYLE" == "true" ]]; then
    printf "  %b Installing Custom UI Style...\n" "$ARROW"
    code --install-extension subframe7536.custom-ui-style --force
    printf "  %b Custom UI Style installed.\n\n" "$CHECK_MARK"
fi

# 3) Bear Sans UI fonts
if [[ "$DO_INSTALL_BEAR_FONTS" == "true" ]]; then
    printf "  %b Installing Bear Sans UI fonts to %s...\n" "$ARROW" "$FONT_DIR"
    mkdir -p "$FONT_DIR"
    cp "$SCRIPT_DIR/fonts/"*.otf "$FONT_DIR/"
    if [[ "$OSTYPE" != "darwin"* ]] && command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f >/dev/null 2>&1 || true
    fi
    printf "  %b Fonts installed.\n\n" "$CHECK_MARK"
fi

# 4) Seti Folder
if [[ "$DO_INSTALL_SETI_ICONS" == "true" ]]; then
    printf "  %b Installing Seti Folder icon theme...\n" "$ARROW"
    code --install-extension l-igh-t.vscode-theme-seti-folder --force
    printf "  %b Seti Folder installed.\n\n" "$CHECK_MARK"
fi

# 5) Living Glass animations CSS file
if [[ "$DO_ENABLE_ANIMATIONS" == "true" ]]; then
    printf "  %b Installing Living Glass animations CSS...\n" "$ARROW"
    mkdir -p "$ANIMATIONS_INSTALL_DIR"
    cp "$SCRIPT_DIR/animations.css" "$ANIMATIONS_FILE"
    printf "  %b Animations CSS installed at %s.\n\n" "$CHECK_MARK" "$ANIMATIONS_FILE"
fi

# 6) Settings merge (covers DO_MERGE_CSS, DO_APPLY_MINIMAL_SETTINGS,
#    DO_SET_ICON_THEME, DO_SET_COLOR_THEME, animations, the icon-glow
#    toggle when off, and any activity-bar choice).
SETTINGS_UPDATE_NEEDED="false"
for v in \
    "$DO_MERGE_CSS" \
    "$DO_APPLY_MINIMAL_SETTINGS" \
    "$DO_SET_ICON_THEME" \
    "$DO_SET_COLOR_THEME" \
    "$DO_ENABLE_ANIMATIONS"
do
    if [[ "$v" == "true" ]]; then
        SETTINGS_UPDATE_NEEDED="true"
    fi
done
if [[ "$DO_ENABLE_ANIMATIONS" == "false" || "$DO_ENABLE_ICON_GLOW" == "false" || "$ACTIVITY_BAR_LOCATION" != "default" ]]; then
    SETTINGS_UPDATE_NEEDED="true"
fi

if [[ "$SETTINGS_UPDATE_NEEDED" == "true" ]]; then
    mkdir -p "$SETTINGS_DIR"

    # Preserve the user's original pre-theme settings once. This mirrors
    # the upstream "pre install" backup behavior, but uses this fork's
    # explicit name so uninstall can restore the real baseline later.
    if [[ ! -f "$PRE_DARK_ISLANDS_BACKUP" ]]; then
        if [[ -f "$SETTINGS_FILE" ]]; then
            cp "$SETTINGS_FILE" "$PRE_DARK_ISLANDS_BACKUP"
        else
            printf "{\n}\n" > "$PRE_DARK_ISLANDS_BACKUP"
        fi
        printf "  %b Original settings backup saved: %s\n" "$CHECK_MARK" "$PRE_DARK_ISLANDS_BACKUP"
    else
        printf "  %b Original settings backup already exists: %s\n" "$CHECK_MARK" "$PRE_DARK_ISLANDS_BACKUP"
    fi

    # Save a structured appearance/theme snapshot once. This gives
    # uninstall a narrower restore path for users who only want theme
    # choices and theme-related customizations put back exactly as they
    # were, without replacing unrelated settings changed later.
    mkdir -p "$STATE_DIR"
    if [[ ! -f "$APPEARANCE_STATE_FILE" ]]; then
        python3 - "$SETTINGS_FILE" "$APPEARANCE_STATE_FILE" <<'PYEOF'
import datetime
import json
import os
import re
import sys

settings_path, state_path = sys.argv[1], sys.argv[2]

theme_related_keys = [
    "workbench.colorTheme",
    "workbench.preferredDarkColorTheme",
    "workbench.preferredLightColorTheme",
    "workbench.preferredHighContrastColorTheme",
    "workbench.preferredHighContrastLightColorTheme",
    "window.autoDetectColorScheme",
    "workbench.iconTheme",
    "workbench.productIconTheme",
    "workbench.colorCustomizations",
    "editor.tokenColorCustomizations",
    "editor.semanticTokenColorCustomizations",
    "custom-ui-style.stylesheet",
    "custom-ui-style.external.imports",
    "custom-ui-style.external.loadStrategy",
    "workbench.activityBar.location",
]

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
snapshot = {
    "schema": 1,
    "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "settingsPath": settings_path,
    "themeRelatedSettings": {
        key: {
            "present": key in settings,
            "value": settings.get(key),
        }
        for key in theme_related_keys
    },
}

with open(state_path, "w", encoding="utf-8") as f:
    json.dump(snapshot, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
        printf "  %b Theme/appearance state saved: %s\n" "$CHECK_MARK" "$APPEARANCE_STATE_FILE"
    else
        printf "  %b Theme/appearance state already exists: %s\n" "$CHECK_MARK" "$APPEARANCE_STATE_FILE"
    fi

    # Always back up before touching the file.
    if [[ -f "$SETTINGS_FILE" ]]; then
        TS="$(date +%Y%m%d-%H%M%S)"
        BACKUP="$SETTINGS_FILE.backup-$TS"
        cp "$SETTINGS_FILE" "$BACKUP"
        printf "  %b Backup saved: %s\n" "$CHECK_MARK" "$BACKUP"
    fi

    REPO_SETTINGS="$SCRIPT_DIR/settings.json"

    # Run the Python merge. Args:
    # 1=user settings path, 2=repo settings path,
    # 3=do_merge_css, 4=do_apply_minimal_settings, 5=do_set_icon_theme,
    # 6=do_enable_icon_glow, 7=activity_bar_location,
    # 8=do_set_color_theme, 9=do_enable_animations, 10=animations_import
    python3 - \
        "$SETTINGS_FILE" \
        "$REPO_SETTINGS" \
        "$DO_MERGE_CSS" \
        "$DO_APPLY_MINIMAL_SETTINGS" \
        "$DO_SET_ICON_THEME" \
        "$DO_ENABLE_ICON_GLOW" \
        "$ACTIVITY_BAR_LOCATION" \
        "$DO_SET_COLOR_THEME" \
        "$DO_ENABLE_ANIMATIONS" \
        "$ANIMATIONS_IMPORT" <<'PYEOF'
import sys
import json
import os
import re

user_path, repo_path  = sys.argv[1], sys.argv[2]
do_merge_css          = sys.argv[3] == "true"
do_apply_settings     = sys.argv[4] == "true"
do_set_icon           = sys.argv[5] == "true"
do_enable_icon_glow   = sys.argv[6] == "true"
activity_bar_location = sys.argv[7]  # "default" | "top" | "bottom" | "hidden"
do_set_color_theme    = sys.argv[8] == "true"
do_enable_animations  = sys.argv[9] == "true"
animations_import     = sys.argv[10]

# Selector for the icon glow CSS rule. Used to remove it cleanly when
# the user opts out of the glow effect.
ICON_GLOW_SELECTOR = ".monaco-icon-label.file-icon::before"
COLOR_THEME_LABEL = "Minimalist Dark Islands"
ANIMATIONS_IMPORT_SUFFIX = "/.vscode/minimalist-dark-islands/animations.css"

# All known selectors for the activity-bar block. We delete every match
# before applying a new variant so we never have leftover rules from a
# previous run.
ACTIVITY_BAR_SELECTOR_PREFIX = ".part.activitybar"

# Layout-override selectors are extra rules we add for top/bottom/hidden
# variants to force the floating glass effect on the sidebar / editor /
# auxiliary bar. VS Code hides `.part.activitybar` in top/bottom mode
# and moves the icons into `.pane-composite-part > .header-or-footer`,
# so those selectors are treated as part of the activity-bar variant.
PANEL_GLASS_OVERRIDE_SELECTORS = [
    ".monaco-workbench .part.sidebar",
    ".monaco-workbench .part.editor",
    ".monaco-workbench .part.auxiliarybar",
    ".monaco-workbench > .monaco-grid-view",
    ".monaco-workbench .part.sidebar .content",
    ".monaco-workbench .part.sidebar .monaco-pane-view",
    ".monaco-workbench .part.sidebar .split-view-container",
    ".monaco-workbench .part.sidebar .split-view-view",
    ".monaco-workbench .part.sidebar .pane",
    ".monaco-workbench .part.sidebar .pane-body",
    ".monaco-workbench .part.sidebar .monaco-list",
    ".monaco-workbench .part.sidebar .monaco-list-rows",
    ".monaco-workbench .part.sidebar .monaco-tree",
    ".monaco-workbench .part.sidebar .monaco-scrollable-element",
    ".monaco-workbench .part.sidebar .explorer-folders-view",
]

PANE_COMPOSITE_ACTIVITY_SELECTORS = [
    ".monaco-workbench .pane-composite-part > .header-or-footer.header",
    ".monaco-workbench .pane-composite-part > .header-or-footer.footer",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .actions-container",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.icon",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item .action-label",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item .action-label.codicon",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item .action-label.codicon::before",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item .action-label:not(.codicon)",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item .active-item-indicator",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.icon.checked",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.icon.active",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.checked .action-label",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.active .action-label",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.icon.checked .action-label.codicon:not(.codicon-more)",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.icon.active .action-label.codicon:not(.codicon-more)",
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .badge",
]

# Old selectors from the first top/bottom implementation. Keep these in
# the strip list so re-running the installer cleans the dark Explorer
# rectangle caused by forcing canvas backgrounds inside sidebar internals.
LEGACY_LAYOUT_OVERRIDE_SELECTORS = [
    ".monaco-workbench .monaco-grid-view",
    ".monaco-workbench .monaco-grid-branch-node",
    ".monaco-workbench .monaco-pane-view",
    ".monaco-workbench .split-view-container",
]

FLOATING_EDITOR_FIXES = {
    ".monaco-workbench:has(> .part.editor):not(:has(> .part.sidebar)):not(:has(> .part.activitybar)):not(:has(> .part.panel))": {
        "--islands-floating-editor-width": "min(78vw, 1040px)",
        "--islands-floating-editor-height": "min(68vh, 720px)",
        "display": "flex !important",
        "flex-direction": "column !important",
        "align-items": "center !important",
        "justify-content": "center !important",
        "gap": "0 !important",
        "padding": "24px !important",
        "box-sizing": "border-box !important",
    },
    ".monaco-workbench.auxiliary-window .part.titlebar, .monaco-workbench.auxiliary .part.titlebar, .monaco-workbench:has(.part.titlebar):has(.part.editor):not(:has(.part.sidebar)):not(:has(.part.activitybar)):not(:has(.part.panel)) .part.titlebar": {
        "width": "var(--islands-floating-editor-width) !important",
        "max-width": "calc(100vw - 48px) !important",
        "align-self": "center !important",
        "flex": "0 0 34px !important",
        "height": "34px !important",
        "min-height": "34px !important",
        "padding-top": "2px !important",
        "box-sizing": "border-box !important",
        "overflow": "visible !important",
        "z-index": "40 !important",
    },
    ".monaco-workbench.auxiliary-window .part.titlebar .window-title, .monaco-workbench.auxiliary .part.titlebar .window-title, .monaco-workbench:has(.part.titlebar):has(.part.editor):not(:has(.part.sidebar)):not(:has(.part.activitybar)):not(:has(.part.panel)) .part.titlebar .window-title": {
        "height": "32px !important",
        "line-height": "32px !important",
        "display": "flex !important",
        "align-items": "center !important",
        "justify-content": "center !important",
        "padding-top": "0 !important",
        "box-sizing": "border-box !important",
        "transform": "none !important",
    },
    ".monaco-workbench.auxiliary-window .part.editor, .monaco-workbench.auxiliary .part.editor, .monaco-workbench:has(.part.titlebar):has(.part.editor):not(:has(.part.sidebar)):not(:has(.part.activitybar)):not(:has(.part.panel)) .part.editor": {
        "width": "var(--islands-floating-editor-width) !important",
        "height": "var(--islands-floating-editor-height) !important",
        "max-width": "calc(100vw - 48px) !important",
        "max-height": "calc(100vh - 118px) !important",
        "min-width": "min(680px, calc(100vw - 48px)) !important",
        "min-height": "min(420px, calc(100vh - 118px)) !important",
        "flex": "0 1 var(--islands-floating-editor-height) !important",
        "align-self": "center !important",
        "margin": "0 auto var(--islands-panel-gap) auto !important",
        "border-radius": "var(--islands-panel-radius) !important",
        "overflow": "hidden !important",
        "box-sizing": "border-box !important",
        "position": "relative !important",
        "background-color": "var(--islands-bg-surface) !important",
        "border-top": "1px solid rgba(255,255,255,0.12) !important",
        "border-left": "1px solid rgba(255,255,255,0.08) !important",
        "border-bottom": "1px solid rgba(255,255,255,0.03) !important",
        "border-right": "1px solid rgba(255,255,255,0.03) !important",
        "box-shadow": "0 2px 8px 0 rgba(0,0,0,0.3) !important",
    },
    ".monaco-workbench.auxiliary-window .part.editor > .content, .monaco-workbench.auxiliary .part.editor > .content, .monaco-workbench:has(.part.titlebar):has(.part.editor):not(:has(.part.sidebar)):not(:has(.part.activitybar)):not(:has(.part.panel)) .part.editor > .content": {
        "width": "100% !important",
        "height": "100% !important",
        "padding-top": "0 !important",
        "overflow": "hidden !important",
    },
    ".monaco-workbench.auxiliary-window .part.editor > .content .editor-group-container > .title, .monaco-workbench.auxiliary .part.editor > .content .editor-group-container > .title, .monaco-workbench:has(.part.titlebar):has(.part.editor):not(:has(.part.sidebar)):not(:has(.part.activitybar)):not(:has(.part.panel)) .part.editor > .content .editor-group-container > .title": {
        "padding-top": "3px !important",
        "box-sizing": "border-box !important",
        "overflow": "visible !important",
    },
    ".monaco-workbench.auxiliary-window .part.statusbar, .monaco-workbench.auxiliary .part.statusbar, .monaco-workbench:has(.part.titlebar):has(.part.editor):not(:has(.part.sidebar)):not(:has(.part.activitybar)):not(:has(.part.panel)) .part.statusbar": {
        "width": "var(--islands-floating-editor-width) !important",
        "max-width": "calc(100vw - 48px) !important",
        "align-self": "center !important",
        "flex": "0 0 auto !important",
    },
}

EDITOR_PART_EDGE_CLEANUP_SELECTORS = (
    ".part.editor",
    ".monaco-workbench .part.editor",
)

# CSS that the top/bottom variants apply on top of the activity-bar
# rules. These are higher-specificity copies of the floating-panel
# styling, plus a canvas background on the top-level grid so the
# margins between the panels reveal the right color. Sidebar internals
# are painted with the sidebar token so empty space matches file rows.
PANEL_GLASS_OVERRIDES = {
    ".monaco-workbench .part.sidebar": {
        "margin": "var(--islands-panel-top) var(--islands-panel-gap) var(--islands-panel-gap) var(--islands-panel-gap) !important",
        "border-radius": "var(--islands-panel-radius) !important",
        "overflow": "hidden !important",
        "box-sizing": "border-box !important",
        "position": "relative !important",
        "z-index": "1 !important",
        "isolation": "isolate !important",
        "background-color": "var(--islands-bg-sidebar) !important",
        "max-height": "calc(100% - var(--islands-panel-top) - var(--islands-panel-gap) - 2px) !important",
        "border-top": "1px solid rgba(255,255,255,0.1) !important",
        "border-left": "1px solid rgba(255,255,255,0.06) !important",
        "border-bottom": "1px solid rgba(255,255,255,0.02) !important",
        "border-right": "1px solid rgba(255,255,255,0.02) !important",
        "box-shadow": "0 2px 8px 0 rgba(0,0,0,0.3) !important",
    },
    ".monaco-workbench .part.editor": {
        "margin": "var(--islands-panel-top) var(--islands-panel-gap) var(--islands-panel-gap) var(--islands-panel-gap) !important",
        "border-radius": "var(--islands-panel-radius) !important",
        "overflow": "hidden !important",
        "box-sizing": "border-box !important",
        "background-color": "var(--islands-bg-surface) !important",
        "max-height": "calc(100% - var(--islands-panel-top) - var(--islands-panel-gap) - 2px) !important",
        "border-top": "1px solid rgba(255,255,255,0.12) !important",
        "border-left": "1px solid rgba(255,255,255,0.08) !important",
        "border-bottom": "1px solid rgba(255,255,255,0.03) !important",
        "border-right": "1px solid rgba(255,255,255,0.03) !important",
        "box-shadow": "0 2px 8px 0 rgba(0,0,0,0.3) !important",
    },
    ".monaco-workbench .part.auxiliarybar": {
        "margin": "var(--islands-panel-top) var(--islands-panel-gap) var(--islands-panel-gap) var(--islands-panel-gap) !important",
        "border-radius": "var(--islands-panel-radius) !important",
        "overflow": "hidden !important",
        "box-sizing": "border-box !important",
        "position": "relative !important",
        "z-index": "1 !important",
        "isolation": "isolate !important",
        "background-color": "var(--islands-bg-surface) !important",
        "max-height": "calc(100% - var(--islands-panel-top) - var(--islands-panel-gap) - 2px) !important",
        "border-top": "1px solid rgba(255,255,255,0.1) !important",
        "border-left": "1px solid rgba(255,255,255,0.06) !important",
        "border-bottom": "1px solid rgba(255,255,255,0.02) !important",
        "border-right": "1px solid rgba(255,255,255,0.02) !important",
        "box-shadow": "0 2px 8px 0 rgba(0,0,0,0.3) !important",
    },
    ".monaco-workbench > .monaco-grid-view": {
        "background-color": "var(--islands-bg-canvas) !important",
    },
    ".monaco-workbench .part.sidebar .content": {
        "background-color": "var(--islands-bg-sidebar) !important",
    },
    ".monaco-workbench .part.sidebar .monaco-pane-view": {
        "background-color": "var(--islands-bg-sidebar) !important",
    },
    ".monaco-workbench .part.sidebar .split-view-container": {
        "background-color": "var(--islands-bg-sidebar) !important",
    },
    ".monaco-workbench .part.sidebar .split-view-view": {
        "background-color": "var(--islands-bg-sidebar) !important",
    },
    ".monaco-workbench .part.sidebar .pane": {
        "background-color": "var(--islands-bg-sidebar) !important",
    },
    ".monaco-workbench .part.sidebar .pane-body": {
        "background-color": "var(--islands-bg-sidebar) !important",
    },
    ".monaco-workbench .part.sidebar .monaco-list": {
        "background-color": "var(--islands-bg-sidebar) !important",
    },
    ".monaco-workbench .part.sidebar .monaco-list-rows": {
        "background-color": "var(--islands-bg-sidebar) !important",
    },
    ".monaco-workbench .part.sidebar .monaco-tree": {
        "background-color": "var(--islands-bg-sidebar) !important",
    },
    ".monaco-workbench .part.sidebar .monaco-scrollable-element": {
        "background-color": "var(--islands-bg-sidebar) !important",
    },
    ".monaco-workbench .part.sidebar .explorer-folders-view": {
        "background-color": "var(--islands-bg-sidebar) !important",
    },
}

PANE_COMPOSITE_ACTIVITY_SHARED = {
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container": {
        "display": "flex !important",
        "align-items": "center !important",
        "justify-content": "flex-start !important",
        "width": "100% !important",
        "height": "auto !important",
        "background": "transparent !important",
        "overflow": "visible !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar": {
        "background": "color-mix(in srgb, var(--islands-bg-canvas), var(--islands-bg-sidebar) 55%) !important",
        "border-radius": "9999px !important",
        "overflow": "visible !important",
        "padding": "3px 8px !important",
        "box-sizing": "border-box !important",
        "display": "flex !important",
        "align-items": "center !important",
        "width": "fit-content !important",
        "max-width": "calc(100% - 8px) !important",
        "height": "auto !important",
        "margin": "0 !important",
        "border-top": "1px solid rgba(255,255,255,0.12) !important",
        "border-left": "1px solid rgba(255,255,255,0.08) !important",
        "border-bottom": "1px solid rgba(255,255,255,0.03) !important",
        "border-right": "1px solid rgba(255,255,255,0.05) !important",
        "box-shadow": "inset 0 1px 3px 0 rgba(255,255,255,0.06), 0 1px 4px 0 rgba(0,0,0,0.3) !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar": {
        "line-height": "26px !important",
        "width": "auto !important",
        "height": "auto !important",
        "background": "transparent !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .actions-container": {
        "display": "flex !important",
        "flex-direction": "row !important",
        "align-items": "center !important",
        "justify-content": "center !important",
        "width": "auto !important",
        "height": "auto !important",
        "overflow": "visible !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item": {
        "display": "flex !important",
        "align-items": "center !important",
        "justify-content": "center !important",
        "width": "auto !important",
        "height": "auto !important",
        "padding": "0 1px !important",
        "overflow": "visible !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.icon": {
        "height": "auto !important",
        "padding": "0 1px !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item .action-label": {
        "font-size": "16px !important",
        "width": "26px !important",
        "height": "26px !important",
        "line-height": "26px !important",
        "display": "flex !important",
        "align-items": "center !important",
        "justify-content": "center !important",
        "overflow": "visible !important",
        "border-radius": "50% !important",
        "box-sizing": "border-box !important",
        "padding": "0 !important",
        "position": "relative !important",
        "outline": "none !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item .action-label.codicon": {
        "font-size": "16px !important",
        "padding": "0 !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item .action-label.codicon::before": {
        "position": "static !important",
        "left": "auto !important",
        "width": "auto !important",
        "height": "auto !important",
        "line-height": "1 !important",
        "margin": "0 !important",
        "display": "block !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item .action-label:not(.codicon)": {
        "width": "26px !important",
        "height": "26px !important",
        "padding": "0 !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item .active-item-indicator": {
        "display": "none !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.icon.checked": {
        "background": "transparent !important",
        "background-color": "transparent !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.icon.active": {
        "background": "transparent !important",
        "background-color": "transparent !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.checked .action-label": {
        "background": "linear-gradient(180deg, rgba(55,56,62,0.9), rgba(40,41,46,0.7)) !important",
        "border-radius": "50% !important",
        "width": "26px !important",
        "height": "26px !important",
        "display": "flex !important",
        "align-items": "center !important",
        "justify-content": "center !important",
        "padding": "0 !important",
        "box-shadow": "inset 0 1px 0 0 rgba(255,255,255,0.12), inset 1px 0 0 0 rgba(255,255,255,0.06), inset 0 -1px 0 0 rgba(255,255,255,0.02), inset -1px 0 0 0 rgba(255,255,255,0.02), inset 0 1px 2px 0 rgba(255,255,255,0.05), 0 1px 3px 0 rgba(0,0,0,0.3) !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.active .action-label": {
        "background": "linear-gradient(180deg, rgba(55,56,62,0.9), rgba(40,41,46,0.7)) !important",
        "border-radius": "50% !important",
        "width": "26px !important",
        "height": "26px !important",
        "display": "flex !important",
        "align-items": "center !important",
        "justify-content": "center !important",
        "padding": "0 !important",
        "box-shadow": "inset 0 1px 0 0 rgba(255,255,255,0.12), inset 1px 0 0 0 rgba(255,255,255,0.06), inset 0 -1px 0 0 rgba(255,255,255,0.02), inset -1px 0 0 0 rgba(255,255,255,0.02), inset 0 1px 2px 0 rgba(255,255,255,0.05), 0 1px 3px 0 rgba(0,0,0,0.3) !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.icon.checked .action-label.codicon:not(.codicon-more)": {
        "background": "linear-gradient(180deg, rgba(55,56,62,0.9), rgba(40,41,46,0.7)) !important",
        "border-radius": "50% !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .action-item.icon.active .action-label.codicon:not(.codicon-more)": {
        "background": "linear-gradient(180deg, rgba(55,56,62,0.9), rgba(40,41,46,0.7)) !important",
        "border-radius": "50% !important",
    },
    ".monaco-workbench .pane-composite-part > .header-or-footer > .composite-bar-container > .composite-bar > .monaco-action-bar .badge": {
        "z-index": "10 !important",
        "overflow": "visible !important",
        "transform": "scale(0.75) !important",
        "transform-origin": "top right !important",
    },
}

# CSS variants for the activity bar. The "default" variant is whatever
# the repo's settings.json ships with (vertical pill on the left); we
# rebuild it from the repo merge result. The other variants override.
ACTIVITY_BAR_VARIANTS = {
    "top": {
        ".monaco-workbench .pane-composite-part > .header-or-footer.header": {
            "background": "transparent !important",
            "padding": "var(--islands-panel-gap) calc(var(--islands-panel-gap) * 2) 0 calc(var(--islands-panel-gap) * 2) !important",
            "box-sizing": "border-box !important",
            "border-bottom": "none !important",
            "min-height": "38px !important",
            "position": "relative !important",
            "z-index": "2 !important",
            "overflow": "visible !important",
        },
        **PANE_COMPOSITE_ACTIVITY_SHARED,
    },
    "bottom": {
        ".monaco-workbench .pane-composite-part > .header-or-footer.footer": {
            "background": "transparent !important",
            "padding": "0 calc(var(--islands-panel-gap) * 2) var(--islands-panel-gap) calc(var(--islands-panel-gap) * 2) !important",
            "box-sizing": "border-box !important",
            "border-top": "none !important",
            "min-height": "38px !important",
            "position": "relative !important",
            "z-index": "2 !important",
            "overflow": "visible !important",
        },
        **PANE_COMPOSITE_ACTIVITY_SHARED,
    },
    "hidden": {
        ".part.activitybar": {
            "display": "none !important",
        },
    },
}

def read_jsonc(path):
    """Read a JSONC file, stripping line/block comments and trailing commas."""
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    if not text.strip():
        return {}
    # Strip // line comments. Best-effort: doesn't account for // inside strings.
    text = re.sub(r"(?m)^(\s*//.*)$", "", text)
    # Strip /* ... */ block comments.
    text = re.sub(r"/\*[\s\S]*?\*/", "", text)
    # Strip trailing commas before } or ].
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return json.loads(text)

user = read_jsonc(user_path)
repo = read_jsonc(repo_path)

if do_merge_css:
    user["custom-ui-style.stylesheet"] = repo["custom-ui-style.stylesheet"]
    print("    - merged custom-ui-style.stylesheet ({} rules)".format(
        len(repo["custom-ui-style.stylesheet"])
    ))
else:
    css_dependent_choice = activity_bar_location != "default" or do_enable_animations
    if css_dependent_choice and not isinstance(user.get("custom-ui-style.stylesheet"), dict):
        user["custom-ui-style.stylesheet"] = repo["custom-ui-style.stylesheet"]
        print("    - installed base custom-ui-style.stylesheet because this selection needs CSS")

if do_apply_settings:
    keys_to_copy = [
        "window.commandCenter",
        "workbench.activityBar.location",
        "workbench.layoutControl.enabled",
        "workbench.editor.empty.hint",
        "workbench.startupEditor",
        "workbench.tree.indent",
        "workbench.tree.renderIndentGuides",
    ]
    for key in keys_to_copy:
        if key in repo:
            user[key] = repo[key]
            print("    - set {} = {}".format(key, json.dumps(repo[key])))

    if isinstance(repo.get("workbench.colorCustomizations"), dict):
        existing_colors = user.get("workbench.colorCustomizations")
        if not isinstance(existing_colors, dict):
            existing_colors = {}
        existing_colors.update(repo["workbench.colorCustomizations"])
        user["workbench.colorCustomizations"] = existing_colors
        print("    - merged workbench.colorCustomizations surface palette")

if do_set_icon:
    user["workbench.iconTheme"] = "vs-seti-folder"
    print("    - set workbench.iconTheme = \"vs-seti-folder\"")

if do_set_color_theme:
    user["workbench.colorTheme"] = COLOR_THEME_LABEL
    print("    - set workbench.colorTheme = \"{}\"".format(COLOR_THEME_LABEL))

# Activity bar location. Always written so the user's choice in this
# run is authoritative. "hidden" maps to VS Code's "hidden" value which
# completely removes the bar.
user["workbench.activityBar.location"] = activity_bar_location
print("    - set workbench.activityBar.location = \"{}\"".format(activity_bar_location))

# Activity bar CSS variant. We rewrite the activity-bar/composite-bar
# rules in the stylesheet to match the user's chosen location, so the
# layout always matches what they picked even when they re-run the script.
#
# The "default" variant is read from the repo's settings.json so we do
# not duplicate the upstream design here. The top/bottom/hidden variants
# are defined above in ACTIVITY_BAR_VARIANTS.
#
# For top/bottom/hidden we additionally inject PANEL_GLASS_OVERRIDES,
# which are higher-specificity copies of the floating-panel rules. Top
# and bottom also style VS Code's header/footer composite bar because
# `.part.activitybar` is hidden in those modes.
stylesheet = user.get("custom-ui-style.stylesheet")
if isinstance(stylesheet, dict):
    if activity_bar_location == "default":
        repo_ss = repo.get("custom-ui-style.stylesheet", {})
        variant = {
            k: v for k, v in repo_ss.items()
            if isinstance(k, str) and k.startswith(ACTIVITY_BAR_SELECTOR_PREFIX)
        }
    else:
        variant = dict(ACTIVITY_BAR_VARIANTS[activity_bar_location])

    # Strip every previous activity-bar rule and every layout override
    # so a re-run with a different choice fully replaces the layout.
    override_strip_selectors = set(
        PANEL_GLASS_OVERRIDE_SELECTORS
        + PANE_COMPOSITE_ACTIVITY_SELECTORS
        + LEGACY_LAYOUT_OVERRIDE_SELECTORS
    )
    removed = 0
    for sel in list(stylesheet.keys()):
        if not isinstance(sel, str):
            continue
        if sel.startswith(ACTIVITY_BAR_SELECTOR_PREFIX) or sel in override_strip_selectors:
            del stylesheet[sel]
            removed += 1
    if removed:
        print("    - removed {} previous activity-bar / layout-override rules".format(removed))

    if variant:
        stylesheet.update(variant)
        print("    - applied activity-bar variant '{}' ({} rules)".format(
            activity_bar_location, len(variant)
        ))

    # The default variant relies on the upstream `.part.sidebar` and
    # `.part.editor` rules already present in the merged stylesheet,
    # so it does NOT need the higher-specificity overrides. Top, bottom
    # and hidden all need them because the DOM rearrangement breaks the
    # original selectors.
    if activity_bar_location in ("top", "bottom", "hidden"):
        stylesheet.update(PANEL_GLASS_OVERRIDES)
        print("    - applied {} layout-glass overrides".format(
            len(PANEL_GLASS_OVERRIDES)
        ))

# Apply icon-glow preference. Acts on the merged stylesheet inside the
# user dict (whether it was just merged or was already present from a
# previous run). When glow is disabled, the rule is removed entirely so
# the user keeps a clean settings.json without dead CSS.
stylesheet = user.get("custom-ui-style.stylesheet")
if isinstance(stylesheet, dict):
    if do_enable_icon_glow:
        if ICON_GLOW_SELECTOR in stylesheet:
            print("    - icon glow rule kept ({})".format(ICON_GLOW_SELECTOR))
    else:
        if ICON_GLOW_SELECTOR in stylesheet:
            del stylesheet[ICON_GLOW_SELECTOR]
            print("    - removed icon glow rule ({})".format(ICON_GLOW_SELECTOR))
        else:
            print("    - icon glow rule not present, nothing to remove")

# Keep the floating editor constrained on every settings write so
# existing installs get the fix without a full CSS re-merge.
stylesheet = user.get("custom-ui-style.stylesheet")
if isinstance(stylesheet, dict):
    stylesheet.update(FLOATING_EDITOR_FIXES)
    for selector in EDITOR_PART_EDGE_CLEANUP_SELECTORS:
        rule = stylesheet.get(selector)
        if isinstance(rule, dict):
            for prop in ("position", "z-index", "isolation"):
                rule.pop(prop, None)
    print("    - applied floating editor sizing fixes")
    print("    - cleaned editor-part stacking overrides")

# Apply animation preference. Animations live in animations.css because
# @property and @keyframes are more reliable as real CSS than as a JSON
# stylesheet object. We install/copy the file from Bash, then register it
# here as an external Custom UI Style import.
imports = user.get("custom-ui-style.external.imports")
if not isinstance(imports, list):
    imports = []

def is_our_animation_import(item):
    if isinstance(item, str):
        return item == animations_import or item.endswith(ANIMATIONS_IMPORT_SUFFIX)
    if isinstance(item, dict):
        url = item.get("url")
        return isinstance(url, str) and (url == animations_import or url.endswith(ANIMATIONS_IMPORT_SUFFIX))
    return False

imports = [item for item in imports if not is_our_animation_import(item)]
if do_enable_animations:
    imports.append(animations_import)
    user["custom-ui-style.external.imports"] = imports
    user["custom-ui-style.external.loadStrategy"] = "refetch"
    print("    - enabled Living Glass animations import ({})".format(animations_import))
else:
    if imports:
        user["custom-ui-style.external.imports"] = imports
    elif "custom-ui-style.external.imports" in user:
        del user["custom-ui-style.external.imports"]
    print("    - disabled Living Glass animations import")

# Drop the documentation-only "// ..." keys we use in the repo's settings.json.
clean = {
    k: v for k, v in user.items()
    if not (isinstance(k, str) and k.startswith("//"))
}

with open(user_path, "w", encoding="utf-8") as f:
    json.dump(clean, f, indent=4, ensure_ascii=False)
    f.write("\n")

print("    - wrote {}".format(user_path))
PYEOF

    printf "  %b Settings updated.\n\n" "$CHECK_MARK"
fi

# ---------------------------------------------------------------------------
# Final manual instructions
# ---------------------------------------------------------------------------
banner "Done"
printf "  %bIMPORTANT: the visual changes are not live yet.%b\n" "$YELLOW" "$NC"
body "Custom UI Style caches the CSS at injection time, so any change"
body "to settings.json (CSS merge, glow toggle, activity bar variant,"
body "etc.) only shows after the extension reloads."
printf "\n"
printf "  %bManual steps to finish:%b\n" "$BOLD" "$NC"
body ""
if [[ "$DO_INSTALL_CUSTOM_UI_STYLE" == "true" ]]; then
    printf "  %b1.%b Open the Command Palette: %bCmd+Shift+P%b (macOS) /\n" "$BOLD" "$NC" "$BOLD" "$NC"
    body "     Ctrl+Shift+P (Linux)."
    body ""
    printf "  %b2.%b Run %b'Custom UI Style: Enable'%b. VS Code will reload.\n" "$BOLD" "$NC" "$BOLD" "$NC"
    body ""
    body "  3. If you see a 'Your Code installation appears corrupt'"
    body "     warning, click the gear icon and choose 'Don't Show"
    body "     Again'. The warning is expected: the extension patches"
    body "     workbench.html, so VS Code's integrity check flags it."
else
    printf "  %b1.%b Open the Command Palette: %bCmd+Shift+P%b (macOS) /\n" "$BOLD" "$NC" "$BOLD" "$NC"
    body "     Ctrl+Shift+P (Linux)."
    body ""
    printf "  %b2.%b Run %b'Custom UI Style: Reload'%b. VS Code will reload.\n" "$BOLD" "$NC" "$BOLD" "$NC"
    body ""
    body "     If 'Reload' does nothing visible, run"
    body "     'Custom UI Style: Disable' -> reload window ->"
    body "     'Custom UI Style: Enable' for a clean re-inject."
fi
printf "\n"
body "Without the reload step, your settings.json is updated but the"
body "old CSS stays painted on screen, which makes it look like the"
body "script did nothing."
printf "\n"
body "Run this script again any time to change your selection."
printf "\n"
