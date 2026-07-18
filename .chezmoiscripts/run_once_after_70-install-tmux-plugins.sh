#!/bin/bash
# Install TPM (Tmux Plugin Manager) and plugins if not already present.
set -euo pipefail

TPM_DIR="$HOME/.config/tmux/plugins/tpm"

if [ ! -d "$TPM_DIR" ]; then
    echo "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

# Install/update plugins headlessly (requires tmux server to not be running,
# or uses the batch install path which works without an active session).
if command -v tmux &>/dev/null && [ -f "$HOME/.config/tmux/tmux.conf" ]; then
    echo "Installing tmux plugins..."
    "$TPM_DIR/bin/install_plugins"
fi
