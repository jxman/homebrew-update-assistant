#!/bin/bash

# Smoke test for the installed app: clicking its icon while it is already running must open
# the main window, even when the script started it in the background.
#
# The script starts the app with `open -g --env BREW_UPDATES_BACKGROUND_LAUNCH=1` to show a
# notification, which keeps the main window closed (`.defaultLaunchBehavior(.suppressed)`).
# SwiftUI applies that to reopening too, so without `AppDelegate.applicationShouldHandleReopen`
# a later click on the Dock/Desktop icon shows nothing. Unit tests can't catch this, so run
# this after install-app.sh whenever app launch, window or menu bar code changes.
#
# Steps: start the installed app the way the script does, check no window opens, open it
# again the way a Desktop/Finder click does, check the main window appears. The app is left
# running with its window open.
#
# Options:
#   -h, --help   Show this help
#
# Exit codes: 0 pass, 1 fail, 2 can't run (app already running, not installed, run in progress)

set -euo pipefail

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

readonly APP_NAME="Brew Updates"
readonly INSTALL_PATH="/Applications/$APP_NAME.app"
readonly LOCK_DIR="$HOME/.brew_logs/.brew-updates.lock"
readonly WAIT_SECONDS=10

usage() {
    sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
}

pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}" >&2; exit 1; }
cannot_run() { echo -e "${RED}$1${NC}" >&2; exit 2; }

# Number of normal (layer 0) on-screen windows the app has. CGWindowList works without the
# Accessibility permission that System Events would need.
window_count() {
    swift - <<EOF 2>/dev/null || echo 0
import CoreGraphics
let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
print(all.filter { (\$0["kCGWindowOwnerName"] as? String) == "$APP_NAME" && (\$0["kCGWindowLayer"] as? Int) == 0 }.count)
EOF
}

# Waits until the app has at least one window, up to WAIT_SECONDS
wait_for_window() {
    local i
    for ((i = 0; i < WAIT_SECONDS; i++)); do
        [[ "$(window_count)" -gt 0 ]] && return 0
        sleep 1
    done
    return 1
}

main() {
    case "${1:-}" in
        -h | --help) usage; exit 0 ;;
        "") ;;
        *) usage >&2; exit 2 ;;
    esac

    [[ -d "$INSTALL_PATH" ]] || cannot_run "$INSTALL_PATH not found. Run scripts/install-app.sh first."
    if pgrep -f "$INSTALL_PATH/Contents/MacOS/" >/dev/null; then
        cannot_run "$APP_NAME is running. Quit it first (the test has to start it in the background)."
    fi
    [[ -d "$LOCK_DIR" ]] && cannot_run "An update run is in progress. Try again when it has finished."

    echo "Starting $APP_NAME in the background, like the script does…"
    open -g --env BREW_UPDATES_BACKGROUND_LAUNCH=1 "$INSTALL_PATH"
    # Give it time to launch; a window appearing here would also be a bug
    sleep 4
    pgrep -f "$INSTALL_PATH/Contents/MacOS/" >/dev/null || fail "The app didn't start"
    [[ "$(window_count)" -eq 0 ]] || fail "A window opened on a background launch (should be suppressed)"
    pass "Background launch: no window"

    echo "Opening the app again, like clicking its Desktop or Dock icon…"
    open "$INSTALL_PATH"
    wait_for_window || fail "No window after clicking the icon (applicationShouldHandleReopen)"
    pass "Reopen: main window shown"
}

main "$@"
