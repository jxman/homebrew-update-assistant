#!/bin/bash

# Builds the Brew Updates app (Release) and installs it to /Applications, with an alias on
# the Desktop. Run again after app changes to update the installed copy.
#
# The version comes from MARKETING_VERSION in app/project.yml; the build number is the git
# commit count, so "1.0.0 (36)" identifies the commit. The app is signed with your Apple
# Development certificate when there is one (a stable identity, so macOS keeps permissions
# such as notifications across updates), otherwise ad hoc.
#
# Options:
#   --no-alias   Don't create the Desktop alias
#   --package    Make a signed zip in dist/ instead of installing (e.g. for another Mac)
#   -h, --help   Show this help

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

usage() {
    echo "Usage: $0 [--no-alias] [--package]"
}

make_alias=true
package=false
for arg in "$@"; do
    case "$arg" in
        --no-alias) make_alias=false ;;
        --package) package=true ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

for tool in xcodegen xcodebuild git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo -e "${RED}$tool not found${NC} (xcodegen: brew install xcodegen)" >&2
        exit 1
    fi
done

# Replacing the bundle under a running app can crash it, so ask to quit first
if [[ "$package" == false ]] && pgrep -f "$INSTALL_PATH/Contents/MacOS/" >/dev/null; then
    echo -e "${YELLOW}Brew Updates is running from /Applications. Quit it and run this again.${NC}" >&2
    exit 1
fi

build_number=$(git -C "$REPO_DIR" rev-list --count HEAD)
if [[ -n "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
    echo -e "${YELLOW}Note: uncommitted changes, so build $build_number also contains work after the last commit${NC}"
fi

echo "Building Release (build $build_number)…"
cd "$APP_DIR"
xcodegen generate --quiet
# Default DerivedData (~/Library): a build folder inside ~/Documents triggers permission prompts
xcodebuild -project BrewUpdates.xcodeproj -scheme BrewUpdates -configuration Release \
    -destination 'platform=macOS,arch=arm64' build -quiet CURRENT_PROJECT_VERSION="$build_number"
products_dir=$(xcodebuild -project BrewUpdates.xcodeproj -scheme BrewUpdates -configuration Release \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR = / { print $2; exit }')
built_app="$products_dir/$APP_NAME"
if [[ ! -d "$built_app" ]]; then
    echo -e "${RED}Build product not found at $built_app${NC}" >&2
    exit 1
fi

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$built_app/Contents/Info.plist")

# Sign a copy, leaving Xcode's build folder as it is
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
app="$work/$APP_NAME"
ditto "$built_app" "$app"
identity=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')
if [[ -n "$identity" ]]; then
    # The first time, macOS may ask to let codesign use the key: choose Always Allow
    codesign --force --sign "$identity" --timestamp=none "$app"
    echo -e "${GREEN}✓ Signed with $identity${NC}"
else
    codesign --force --sign - "$app"
    echo -e "${YELLOW}No Apple Development certificate found, signed ad hoc${NC}"
fi
codesign --verify --strict "$app"

if [[ "$package" == true ]]; then
    zip_path="$REPO_DIR/dist/Brew-Updates-$version-$build_number.zip"
    mkdir -p "$REPO_DIR/dist"
    # ditto keeps the bundle's signature and extended attributes intact, unlike zip
    ditto -c -k --keepParent "$app" "$zip_path"
    echo -e "${GREEN}✓ Packaged $zip_path${NC}"
    echo "On another Mac: run scripts/setup.sh, unzip into /Applications and open it once. It isn't"
    echo "notarized, so then allow it in System Settings > Privacy & Security > Open Anyway."
    exit 0
fi

# Copy next to the old version first, then swap, so a failed copy leaves the old app intact
staging="/Applications/.Brew Updates.app.installing"
rm -rf "$staging"
ditto "$app" "$staging"
rm -rf "$INSTALL_PATH"
mv "$staging" "$INSTALL_PATH"
# A new modification date makes Finder and the Dock pick up a changed icon
touch "$INSTALL_PATH"
echo -e "${GREEN}✓ Installed $INSTALL_PATH${NC} (version $version, build $build_number)"

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
