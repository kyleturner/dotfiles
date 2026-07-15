# macOS Dev Workstation — Setup Runbook

Follow this top to bottom on a fresh Mac. Every stack decision here was researched and validated — see `macos-dev-workstation-ARCHIVE.md` if you ever want the reasoning, citations, or rejected alternatives behind a choice. This file is just the steps.

**Target:** Apple Silicon Mac, macOS Tahoe 26+. ~30-45 min including account sign-ins.

---

## 0. Before You Touch The Terminal

Do these four things first — the script can't do them for you.

- [ ] **Sign into the App Store** (Apple ID, System Settings → your name → Media & Purchases)
- [ ] **Install 1Password from the App Store or directly**, sign in, enable Touch ID unlock
- [ ] **Enable 1Password's SSH Agent**: 1Password → Settings → Developer → "Use the SSH Agent" (toggle ON). Your GitHub SSH key must already be in 1Password's vault. `bootstrap.sh` clones your dotfiles repo over SSH — without this step done first, the clone will fail with `ssh: Could not resolve hostname` or hang waiting for a key.
- [ ] **Grant App Management to Terminal**: System Settings → Privacy & Security → App Management → enable for Terminal
- [ ] Know your **GitHub username** and have a **private `dotfiles` repo** ready (empty is fine — you'll populate it)

---

## 1. Run the Bootstrap Script

Open Terminal.app (just this once — Ghostty gets installed by the script) and run:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/dotfiles/main/bootstrap.sh | bash
```

This does everything below, in order, automatically. You'll see prompts along the way — answer them as they come.

1. Verifies Apple Silicon + macOS 26+, caches `sudo`
2. Installs Homebrew, then `git`, `chezmoi`, `mas`, `1password-cli`
3. Prompts for: **name**, **email**, **profile** (personal/work) — asked once, cached
4. `chezmoi init --apply` pulls your dotfiles repo and writes every config file
5. Runs `brew bundle` — installs the full Brewfile (Section 2 below)
6. Attempts Xcode via `mas` — **this step is unreliable, see the callout below, don't count on it**
7. Applies macOS defaults (Dock, Finder, keyboard, trackpad, screenshots)
8. Installs mise + all runtimes (Node, Bun, Python, Go, Rust, Java, Pitchfork)
9. Resolves secrets from 1Password into `~/.config/secrets/.env.global`
10. Prints a summary — ✅ or a short list of ⚠️ warnings

**If it stops and asks you to sign in somewhere** (App Store, 1Password), do that, then re-run the same command — it's idempotent, already-done steps are skipped.

**If `chezmoi init` fails after the repo has already cloned** (you'll see `Cloning into '/Users/.../.local/share/chezmoi'...` succeed, then an error after) — you don't need to re-run `bootstrap.sh` from scratch. The clone already happened; only `init`'s later steps (config decode, apply) failed. Pull the fix and retry directly:
```bash
cd ~/.local/share/chezmoi
git pull
chezmoi init --apply
```

> ⚠️ **Xcode via `mas` is not reliable — plan to install it manually.** Two real, documented failure modes: `brew bundle` uses `mas install`, which only works for apps already associated with your Apple ID — on a fresh Apple ID or fresh machine it fails outright with `Redownload Unavailable with this Apple Account`, even though you've never disabled anything. Separately, Xcode is large enough that the App Store install path frequently hangs or fails regardless of `mas`; Apple's own community consistently recommends downloading it directly instead. **Don't wait on step 6 to succeed.** Go to Section 3 and download Xcode directly from developer.apple.com while the rest of the bootstrap runs — it's a big download, so starting it early in parallel is the practical move anyway.

---

## 2. What Just Got Installed

You don't need to do anything here — this is just so you know what's on the machine.

**Terminal & shell:** Ghostty, zsh + Starship prompt, tmux + tmuxp, Pitchfork
**Editor:** Cursor
**Runtimes (via mise, not Homebrew):** Node 22, Bun, Python 3.12, Go, Rust, Java 21, Terraform, kubectl
**Containers:** OrbStack
**AI coding:** Claude Code (CLI), Claude Desktop, `codebase-memory-mcp` (installed automatically, indexed per-project)
**Local AI:** Ollama (local LLM inference — free experimentation, offline, client-data-safe)
**Secrets:** 1Password CLI, SSH via 1Password agent
**Productivity:** Raycast, 1Password, Arc + Chrome + Firefox (menu bar: use native macOS Tahoe Menu Bar Controls in System Settings — no third-party app needed)
**Work apps:** Linear, Slack, Notion, TablePlus, Proxyman, GitHub Desktop

See "Recommended Follow-Up Tools" near the end of this file for things worth adding later, not part of this bootstrap.

Full Brewfile is in the archive doc if you want to see every line.

---

## 3. Manual Steps (5 minutes, do these once)

The script can't do these — macOS blocks automation here or they're one-time account actions.

- [ ] **Xcode** → don't rely on step 6 of the bootstrap. Download directly from [developer.apple.com/download/applications](https://developer.apple.com/download/applications) (sign in with your Apple Developer account), or run `xcode-select --install` for just the Command Line Tools if you don't need the full IDE yet. This is a large download — start it early, in parallel with the bootstrap script, not after.
- [ ] **Cursor** → sign in with GitHub (Settings Sync)
- [ ] **Arc / Chrome / Firefox** → sign into your accounts as needed
- [ ] **Linear / Slack / Notion** → sign in
- [ ] **OrbStack** → sign in if using for commercial/client work (paid plan required)
- [ ] **Dock layout** → drag apps into your preferred order (Ghostty, Cursor, Arc, OrbStack, Linear) — automation for this isn't reliable on Tahoe yet
- [ ] **Control Center layout, battery %, Night Shift, display arrangement** → set manually in System Settings, these aren't scriptable reliably on Tahoe
- [ ] **GitHub SSH key** → confirm it's in GitHub: `op read op://Developer/GitHub-SSH-Key/public` and paste into GitHub → Settings → SSH Keys (or let the script's `op` step do it if your PAT is in 1Password)
- [ ] **Full Disk Access for Terminal/Ghostty and Proxyman** → System Settings → Privacy & Security → Full Disk Access. Also needed for `defaults write com.apple.Safari` to actually reach Safari's sandboxed preferences — without it, the bootstrap's Safari developer-menu step is skipped gracefully (not fatal) with a warning; grant this and re-run script 30 if you want it applied.
- [ ] **OrbStack's Rosetta prompt on first launch is expected** — accept it. OrbStack uses Rosetta to run x86/Intel Docker images at near-native speed; there's no Apple-Silicon-only build that skips this, and it's not a sign anything went wrong.
- [ ] **Enable Claude Code's sandbox** → open Claude Code in any project and run `/sandbox` once. This is a one-time, low-friction step that closes a real gap: without it, Bash commands Claude Code runs have full host access. Do this before your first real session, not after.

---

## 4. Verify Everything Worked

Run this block. Every line should return something sane — no errors.

```bash
brew bundle check                 # all Homebrew packages present
mise doctor                       # mise + all runtimes healthy
chezmoi doctor                    # dotfiles applied cleanly
claude --version                  # Claude Code installed
cursor --version                  # Cursor CLI on PATH
op whoami                         # 1Password CLI authenticated
xcode-select -p                   # confirms Xcode or CLT is installed and selected
ghostty +version                  # Ghostty installed
tmux -V                           # tmux installed
pitchfork --version               # Pitchfork installed
ollama --version                  # Ollama installed
```

If `mise doctor` or `brew bundle check` shows warnings, re-run the bootstrap script — it's safe.

---

## 5. Day-One Workflow — How This All Fits Together

The one rule that ties the whole stack together:

> **Every project command runs through `mise run <task>`.** Never type `bun run dev` or `pytest` directly — define it as a task in that project's `.mise.toml` and run it via `mise run`. Same for scripts, tmuxp layouts, and Pitchfork daemons — they all call `mise run`, never the tool directly.

### Claude Code sandboxing — know the two levels

- `/sandbox` (done once in Step 3 above) restricts **Bash commands only**. Good enough for everyday work.
- If a session is using `codebase-memory-mcp`, Entire, or any other MCP server/hook and you want *those* inside the boundary too, launch with `npx @anthropic-ai/sandbox-runtime claude` instead — wraps the whole process, not just Bash.
- If you're ever running Claude Code unattended (`--dangerously-skip-permissions` or auto mode), do it inside a devcontainer, not on the bare host — see the archive doc's Section 4.18 for the template.

### Starting a new project

```bash
mkdir ~/code/myapp && cd ~/code/myapp
mise use node@22 bun@latest        # or whatever the project needs — writes .mise.toml
```

Add tasks to `.mise.toml`:
```toml
[tools]
node = "22"
bun = "latest"

[env]
_.file = ".env.local"              # secrets — see step 6 below

[tasks.dev]
run = "bun run dev"

[tasks.test]
run = "bun test"
```

### Working on it day-to-day

```bash
tmuxp load myapp     # builds your layout: editor pane, dev server, test watcher, shell
                      # (or copy ~/.config/tmuxp/_template.yaml to get started)
```

Inside Claude Code or Cursor, working in this project: tell it to prefer `mise run <task>` for anything project-specific, and — if you've indexed the project with `codebase-memory-mcp` — to prefer the graph tools for structural questions ("what calls this function," "what's the blast radius of this change") over grep/read. For anything where you want the accuracy delta of a direct read instead of the graph, just ask directly — it always falls through.

### Secrets for a new project

```bash
# .env.local.tpl — commit this, it's just references, no secrets
cat > .env.local.tpl << 'EOF'
DATABASE_URL=op://Developer/myapp-db/url
EOF

# Before running op inject: confirm the item actually exists with this exact name
# and field. A reference to an item that doesn't exist yet fails with
# "could not find item ... in vault ..." — check first, don't guess:
op item get "myapp-db" --vault "Developer"

# For "API Credential" category items specifically, the secret field is named
# "credential", not "token" — this tripped up the original GitHub PAT setup.
# To create a new item that matches a reference like the one above:
#   op item create --category "API Credential" --title "myapp-db" \
#     --vault "Developer" --field "credential=<the actual secret value>"

op inject -i .env.local.tpl -o .env.local   # generates the real file, gitignored
echo ".env.local" >> .gitignore
```

### Persistent background services (DB, workers — things that should survive closing the terminal)

Add to `pitchfork.toml` in the project:
```toml
[daemons.db]
run = "mise run db:start"
auto = ["start", "stop"]
ready_output = "ready to accept connections"
```
Pitchfork starts/stops it as you `cd` in and out of the project.

### Want agent session history for this project?

```bash
entire enable   # prompted per-project, defaults to local-only (no auto-push)
```
Skip this for client repos unless you've deliberately decided the session history should live there.

### Want faster/cheaper Claude Code answers on a big codebase?

```bash
# say to Claude Code, inside the project:
"Index this project"
```
Then tell it to prefer graph queries for structural questions. First time indexing a big or freshly-refactored repo, sanity-check the result once (`get_architecture`) before trusting it blindly — see the archive doc's Section 4.17 if you hit something that looks wrong.

### Want a local model — for offline work, free experimentation, or client data that can't leave the machine?

```bash
brew services start ollama   # if not already running as a background service
ollama pull qwen3:8b         # solid general default; larger models need more RAM
ollama run qwen3:8b
```
Exposes an OpenAI-compatible API at `localhost:11434` — point any tool expecting that interface at it directly.

---

## 6. Ongoing Maintenance

One command, run whenever:

```bash
brew update && brew upgrade && brew upgrade --cask && brew upgrade --greedy orbstack && mise upgrade && chezmoi update
```

Add new Homebrew packages: edit `Brewfile` in your dotfiles repo → `chezmoi apply` (auto-runs `brew bundle`).
Rotate a secret: update it in 1Password → `op inject -i <file>.tpl -o <file>` to regenerate.
Full status check: `brew bundle check && mise doctor && chezmoi doctor`.

---

## 7. Recommended Follow-Up Tools (Not Part of Bootstrap)

These aren't installed by `bootstrap.sh` — they're worth knowing about and adding manually if/when they're actually useful to you, not day-one requirements.

**Entire CLI — agent session persistence.** Captures the full Claude Code/Cursor session (prompts, tool calls, files touched) behind each git commit, stored on a separate branch so your real commit history stays clean. Useful if you want to rewind or resume an agent session later. Skip this for client repos unless you've deliberately decided session history should live there — see the archive's Section 4.15 for the security reasoning.
```bash
brew tap entireio/tap
brew install --cask entire
# Then, per-project, when you want it:
entire enable
```

---

## Quick Reference — Common Commands

| I want to... | Command |
|---|---|
| Start a project session | `tmuxp load <project>` |
| Run a project task | `mise run <task>` |
| See what tasks exist | `mise tasks ls` |
| Add a runtime to a project | `mise use <tool>@<version>` |
| Regenerate secrets | `op inject -i <file>.tpl -o <file>` |
| Check everything's healthy | `brew bundle check && mise doctor && chezmoi doctor` |
| Update everything | see Section 6 above |
| Index a project for Claude Code | Say "index this project" in Claude Code |
| Start a background service | Add to `pitchfork.toml`, `pitchfork start <name>` |
| Sandbox Claude Code (Bash only) | `/sandbox` inside a Claude Code session |
| Sandbox Claude Code (full process) | `npx @anthropic-ai/sandbox-runtime claude` |
| Run a local model | `ollama run qwen3:8b` |

---

*For the "why" behind any decision in this runbook — tool comparisons, rejected alternatives, security audits, version-specific caveats — see `macos-dev-workstation-ARCHIVE.md`. This runbook is deliberately stripped of that; it only has what you need to execute.*
