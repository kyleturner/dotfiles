#!/bin/bash
# Install tmux plugins headlessly via tpack (brew-installed, drop-in TPM replacement).
set -euo pipefail

# Remove any stale TPM git-clone from before the tpack migration.
TPM_DIR="$HOME/.config/tmux/plugins/tpm"
if [ -d "$TPM_DIR" ]; then
    echo "Removing stale TPM clone at $TPM_DIR..."
    rm -rf "$TPM_DIR"
fi

if command -v tpack &>/dev/null && [ -f "$HOME/.config/tmux/tmux.conf" ]; then
    echo "Installing tmux plugins via tpack..."
    tpack install
fi
