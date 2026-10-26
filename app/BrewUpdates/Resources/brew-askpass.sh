#!/bin/sh
# Password prompt for brew commands the app runs (uninstalls and restores).
#
# The app sets SUDO_ASKPASS to this file; brew then runs `sudo -A`, and sudo calls this
# script whenever it needs the administrator password (up to three tries). It shows the
# standard macOS password dialog and prints what was typed to stdout, which only sudo reads.
# Nothing is stored or logged. Cancel exits non-zero, so sudo (and the brew step) stops.
exec /usr/bin/osascript - "${1:-}" <<'APPLESCRIPT'
on run argv
    set message to "Homebrew needs your administrator password to install or remove system files for a package."
    set reply to display dialog message default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK" cancel button "Cancel" with title "Brew Updates" with icon caution
    return text returned of reply
end run
APPLESCRIPT
