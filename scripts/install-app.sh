#!/bin/bash

# Builds the Brew Updates app (Release) and installs it to /Applications, with an alias on
# the Desktop. Run again after app changes to update the installed copy.
#
# Options:
#   --no-alias   Don't create the Desktop alias

set -euo pipefail

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR
readonly APP_DIR="$REPO_DIR/app"
readonly APP_NAME="Brew Updates.app"
readonly INSTALL_PATH="/Applications/$APP_NAME"
readonly ALIAS_PATH="$HOME/Desktop/Brew Updates"

make_alias=true
if [[ "${1:-}" == "--no-alias" ]]; then
    make_alias=false
elif [[ -n "${1:-}" ]]; then
    echo "Usage: $0 [--no-alias]" >&2
    exit 1
fi

for tool in xcodegen xcodebuild; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo -e "${RED}$tool not found${NC} (xcodegen: brew install xcodegen)" >&2
        exit 1
    fi
done

# Replacing the bundle under a running app can crash it, so ask to quit first
if pgrep -f "$INSTALL_PATH/Contents/MacOS/" >/dev/null; then
    echo -e "${YELLOW}Brew Updates is running from /Applications. Quit it and run this again.${NC}" >&2
    exit 1
fi

echo "Building Release…"
cd "$APP_DIR"
xcodegen generate --quiet
# Default DerivedData (~/Library): a build folder inside ~/Documents triggers permission prompts
xcodebuild -project BrewUpdates.xcodeproj -scheme BrewUpdates -configuration Release \
    -destination 'platform=macOS,arch=arm64' build -quiet
products_dir=$(xcodebuild -project BrewUpdates.xcodeproj -scheme BrewUpdates -configuration Release \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR = / { print $2; exit }')
built_app="$products_dir/$APP_NAME"
if [[ ! -d "$built_app" ]]; then
    echo -e "${RED}Build product not found at $built_app${NC}" >&2
    exit 1
fi

# Copy next to the old version first, then swap, so a failed copy leaves the old app intact
staging="/Applications/.Brew Updates.app.installing"
rm -rf "$staging"
ditto "$built_app" "$staging"
rm -rf "$INSTALL_PATH"
mv "$staging" "$INSTALL_PATH"
# A new modification date makes Finder and the Dock pick up a changed icon
touch "$INSTALL_PATH"
echo -e "${GREEN}✓ Installed $INSTALL_PATH${NC}"

if [[ "$make_alias" == true ]]; then
    if [[ -e "$ALIAS_PATH" || -L "$ALIAS_PATH" ]]; then
        echo "  Desktop alias already exists"
    elif osascript -e "tell application \"Finder\" to make alias file to POSIX file \"$INSTALL_PATH\" at desktop with properties {name:\"Brew Updates\"}" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Added a Desktop alias${NC}"
    else
        # Finder automation was refused; a symlink behaves the same when double-clicked
        ln -s "$INSTALL_PATH" "$ALIAS_PATH"
        echo -e "${GREEN}✓ Added a Desktop link${NC} (Finder alias not allowed, used a symlink)"
    fi
fi

echo "Open it from Launchpad, Spotlight, or the Desktop."
