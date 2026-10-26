#!/bin/bash
# Pre-commit hook: lint the SwiftUI app with SwiftLint (config: app/.swiftlint.yml).
# Fails closed with an install hint when SwiftLint is missing.
set -euo pipefail

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "swiftlint not found. Install with: brew install swiftlint"
    exit 1
fi

cd "$(git rev-parse --show-toplevel)/app"
swiftlint lint --strict --quiet
