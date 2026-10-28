#!/bin/bash
# Pre-commit hook: scan staged changes for secrets with GitGuardian's ggshield.
# Uses the Homebrew ggshield, which can read the API key saved by `ggshield auth login`
# (pre-commit's own copy can't). Fails closed with an install hint when it is missing.
set -euo pipefail

if ! command -v ggshield >/dev/null 2>&1; then
    echo "ggshield not found. Install with: brew install ggshield (then: ggshield auth login)"
    exit 1
fi

ggshield secret scan pre-commit
