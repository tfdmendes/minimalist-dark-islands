#!/usr/bin/env bash

set -euo pipefail

# Minimalist Dark Islands Bootstrap Installer
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/tfdmendes/minimalist-dark-islands/main/bootstrap.sh | bash

REPO_URL="${MINIMALIST_DARK_ISLANDS_REPO:-https://github.com/tfdmendes/minimalist-dark-islands.git}"
BRANCH="${MINIMALIST_DARK_ISLANDS_BRANCH:-main}"
INSTALL_DIR="${TMPDIR:-/tmp}/minimalist-dark-islands-temp"

echo "Minimalist Dark Islands Bootstrap Installer"
echo "==========================================="
echo ""

if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required to download the installer."
    exit 1
fi

echo "Step 1: Downloading Minimalist Dark Islands..."
echo "Repository: $REPO_URL"

rm -rf "$INSTALL_DIR"

if ! git clone "$REPO_URL" "$INSTALL_DIR" --quiet --branch "$BRANCH"; then
    echo "Error: failed to download Minimalist Dark Islands."
    exit 1
fi

echo "Downloaded successfully."
echo ""

echo "Step 2: Running installer..."
echo ""

cd "$INSTALL_DIR"
bash install-minimalist.sh

echo ""
echo "Step 3: Cleaning up..."
read -r -p "Remove temporary files? [y/N] " REMOVE_TEMP
case "$REMOVE_TEMP" in
    y|Y|yes|YES)
        rm -rf "$INSTALL_DIR"
        echo "Temporary files removed."
        ;;
    *)
        echo "Files kept at: $INSTALL_DIR"
        ;;
esac

echo ""
echo "Done. Enjoy Minimalist Dark Islands."
