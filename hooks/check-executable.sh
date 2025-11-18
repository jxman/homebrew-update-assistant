#!/bin/bash
# Pre-commit hook to ensure scripts are executable
# This prevents non-executable scripts from being committed

exit_code=0

for file in "$@"; do
    if [[ -f "$file" ]]; then
        if [[ ! -x "$file" ]]; then
            echo "❌ File is not executable: $file"
            echo "   Fix with: chmod +x $file"
            exit_code=1
        fi
    fi
done

exit $exit_code
