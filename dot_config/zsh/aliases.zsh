# ~/.config/zsh/aliases.zsh
# RULE (runbook-guide.md Section 4.3): only project-independent,
# generic-tool aliases go here. Anything whose behavior depends on a specific project's
# toolchain belongs in that project's .mise.toml [tasks], invoked via `mise run`.

# --- Modern CLI replacements ---
alias ls='eza --icons'
alias ll='eza -la --icons --git'
alias lt='eza --tree --icons --level=2'
alias cat='bat'
alias grep='rg'
alias find='fd'

# --- Git shortcuts (generic, not project-specific) ---
alias gs='git status'
alias gp='git pull'
alias gf='git fetch'
alias gm='git pull origin main'
alias gc='git commit'
alias gco='git checkout'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'

# --- General ---
alias c='clear'
alias history='history 1 | less'

# --- Navigation ---
alias ..='cd ..'
alias ...='cd ../..'
alias proj='cd ~/Projects'

# --- mise shortcuts ---
alias mr='mise run'
alias mt='mise tasks ls'

# --- tmux / tmuxp ---
alias tl='tmuxp load'
alias ta='tmux attach -t'
alias tls='tmux ls'
# Force the current window to fill the terminal (undoes shrink from a smaller attached client)
alias resize='tmux resize-window -A'
alias rs='tmux resize-window -A'

# --- workmux (git worktrees + tmux) ---
alias wm='workmux'
alias wma='~/.config/workmux/bin/workmux-activate'

# --- Homebrew maintenance ---
alias brewup='brew update && brew upgrade && brew upgrade --cask && brew upgrade --greedy orbstack'

# --- macOS system ---
# Set the Mac login screen message. Usage: motivation "Your Message Here"
alias motivation='sudo defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText'

# --- Claude Code / sandboxing (see Section 4.18) ---
alias claude-sandboxed='npx @anthropic-ai/sandbox-runtime claude'

# --- Shell / terminal config reload ---
alias reload='source ~/.zshrc && pkill -USR2 -x Ghostty'
