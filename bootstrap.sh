#!/bin/bash
# bootstrap.sh — kyleturner/dotfiles
# curl -fsSL https://raw.githubusercontent.com/kyleturner/dotfiles/main/bootstrap.sh | bash
#
# Full architecture and reasoning: macos-dev-workstation-ARCHIVE.md
# Step-by-step runbook: macos-dev-workstation-RUNBOOK.md
#
# This script does the minimum needed to get chezmoi installed and running — chezmoi
# then orchestrates everything else via .chezmoiscripts/. See ARCHIVE.md Section 9 for
# why chezmoi (not this script) owns the real bootstrap logic.

set -euo pipefail

GITHUB_USER="kyleturner"
DOTFILES_REPO="git@github.com:${GITHUB_USER}/dotfiles.git"

echo "=================================================="
echo " macOS Developer Workstation Bootstrap"
echo " ${GITHUB_USER}/dotfiles"
echo "=================================================="
echo ""

# ------------------------------------------------------------
# PRE-FLIGHT: verify Apple Silicon
# ------------------------------------------------------------
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "❌ This stack targets Apple Silicon (arm64) only. Detected: $(uname -m)"
  echo "   See ARCHIVE.md — Rosetta / Intel paths are explicitly not supported."
  exit 1
fi
echo "✓ Apple Silicon confirmed"

# ------------------------------------------------------------
# PRE-FLIGHT: verify macOS version (Tahoe 26+)
# ------------------------------------------------------------
OS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$OS_VERSION" -lt 26 ]]; then
  echo "⚠️  This stack is verified for macOS 26 (Tahoe) or later. Current: $(sw_vers -productVersion)"
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
else
  echo "✓ macOS $(sw_vers -productVersion) (Tahoe or later)"
fi

# ------------------------------------------------------------
# PRE-FLIGHT: human gates — cannot be automated, see ARCHIVE.md Section 3
# ------------------------------------------------------------
echo ""
echo "Before continuing, confirm each of these is done:"
echo ""
echo "  1. Signed into the App Store (Apple ID)"
echo "  2. 1Password installed, signed in, Touch ID unlock enabled"
echo "  3. 1Password SSH Agent enabled:"
echo "     1Password → Settings → Developer → \"Use the SSH Agent\" (toggle ON)"
echo "     Your GitHub SSH key must already exist in 1Password's vault for this to work."
echo "  4. Terminal granted 'App Management' permission:"
echo "     System Settings → Privacy & Security → App Management"
echo ""
echo "  (Xcode is intentionally NOT gated here — it's a separate manual step."
echo "   See RUNBOOK.md Section 3. mas is unreliable for Xcode specifically —"
echo "   see ARCHIVE.md Section 4.12. Start the Xcode download now, in parallel,"
echo "   from https://developer.apple.com/download/applications)"
echo ""
read -p "Press Enter once all four are done, or Ctrl-C to stop and do them now... "

# ------------------------------------------------------------
# Pre-seed ~/.ssh/config so `chezmoi init` can clone over SSH via the 1Password agent.
# chezmoi's own dot_config/ssh (or equivalent) will confirm/overwrite this identically
# once applied — this is only needed to break the chicken-and-egg: chezmoi needs SSH
# working to clone the repo that would otherwise configure SSH.
# ------------------------------------------------------------
mkdir -p ~/.ssh
if ! grep -q "1password" ~/.ssh/config 2>/dev/null; then
  echo "→ Pre-seeding ~/.ssh/config for the 1Password SSH agent..."
  cat >> ~/.ssh/config << 'EOF'
Host *
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
EOF
  chmod 600 ~/.ssh/config
fi

# ------------------------------------------------------------
# sudo keepalive — prevents timeout mid-run (needed for mas, defaults, etc.)
# ------------------------------------------------------------
echo ""
echo "→ Caching sudo credentials..."
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

# ------------------------------------------------------------
# PRE-FLIGHT: Spotlight enabled on /Applications (required for mas)
# ------------------------------------------------------------
if mdutil -s /Applications 2>/dev/null | grep -qi "enabled"; then
  echo "✓ Spotlight enabled on /Applications"
else
  echo "⚠️  Spotlight is not enabled on /Applications — mas may silently fail to detect"
  echo "   installed apps. Enable it in System Settings → Siri & Spotlight → Spotlight."
fi

# ------------------------------------------------------------
# PHASE 1: Homebrew + bootstrap dependencies
# ------------------------------------------------------------
echo ""
echo "→ [Phase 1] Installing Homebrew..."
if ! command -v brew &> /dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  echo "✓ Homebrew already installed"
fi

echo "→ Installing bootstrap dependencies (git, chezmoi, mas, 1password-cli)..."
brew install git chezmoi mas 1password-cli

# ------------------------------------------------------------
# PHASE 2: chezmoi init — this is where the real work happens.
# Everything from here is orchestrated by .chezmoiscripts/ in the dotfiles repo.
# See ARCHIVE.md Section 9 for the full execution order (10 → 50).
# ------------------------------------------------------------
echo ""
echo "→ [Phase 2] Running chezmoi init --apply ${DOTFILES_REPO}..."
echo "   You'll be prompted for: name, email, profile (personal/work) — asked once, cached."
echo ""

chezmoi init --apply "${DOTFILES_REPO}"

# ------------------------------------------------------------
# DONE
# ------------------------------------------------------------
echo ""
echo "=================================================="
echo " ✅ Bootstrap complete."
echo "=================================================="
echo ""
echo "Remaining manual steps (see RUNBOOK.md Section 3):"
echo "  - Xcode: install directly from developer.apple.com if not already done"
echo "  - Cursor: sign in with GitHub (Settings Sync)"
echo "  - Arc / Chrome / Firefox: sign into accounts"
echo "  - Linear / Slack / Notion: sign in"
echo "  - Claude Code sandbox: run '/sandbox' inside a Claude Code session"
echo "  - Dock layout, Control Center, battery %, Night Shift, display arrangement"
echo ""
echo "Verify everything worked:"
echo "  brew bundle check --file=~/.config/homebrew/Brewfile"
echo "  mise doctor"
echo "  chezmoi doctor"
echo ""
echo "  (or just run the 'stackcheck' function, defined in dot_config/zsh/functions.zsh)"
echo ""
echo "⚠️  Some macOS settings (key repeat rate, three-finger drag, Mission Control"
echo "   spaces) require a LOGOUT to fully apply. Log out and back in when convenient."
echo ""
