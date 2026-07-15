# ~/.config/zsh/functions.zsh
# Same rule as aliases.zsh: project-independent only.

# Full stack health check — brew, mise, chezmoi in one shot.
# See macos-dev-workstation-RUNBOOK.md Section 6.
stackcheck() {
  echo "→ brew bundle check..."
  brew bundle check --file="$HOME/.config/homebrew/Brewfile" || echo "  (see 'brew bundle check --verbose' for details)"
  echo "→ mise doctor..."
  mise doctor
  echo "→ chezmoi doctor..."
  chezmoi doctor
}

# Quickly regenerate resolved secrets after rotating something in 1Password.
resecrets() {
  echo "→ Resolving global secrets..."
  op inject -i ~/.config/secrets/.env.global.tpl -o ~/.config/secrets/.env.global
  chmod 600 ~/.config/secrets/.env.global
  echo "✓ Done."
}

# Scaffold a new project directory under ~/Projects with a starting .mise.toml.
newproject() {
  if [ -z "$1" ]; then
    echo "Usage: newproject <name>"
    return 1
  fi
  local dir="$HOME/Projects/$1"
  mkdir -p "$dir"
  cd "$dir" || return 1
  cat > .mise.toml << 'EOF'
[tools]
node = "22"
bun = "latest"

[env]
_.file = ".env.local"

[tasks.dev]
run = "echo 'define me'"

[tasks.test]
run = "echo 'define me'"
EOF
  git init -q
  echo "✓ Created $dir with a starting .mise.toml"
}
