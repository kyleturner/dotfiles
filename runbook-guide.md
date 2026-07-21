# macOS Developer Workstation — Research Archive (Reference Only, Not for Execution)
> ⚠️ This is the full research and decision-log archive. It contains every citation, every rejected alternative, every audit pass, and the reasoning behind each stack choice — kept for future reference when a decision needs revisiting or re-justifying.
>
> **This is not the runbook.** To actually set up a new machine, use `macos-dev-workstation-RUNBOOK.md` instead — it's the short, execute-top-to-bottom version distilled from everything below.
>
> Apple Silicon (M-series) · macOS Tahoe 26 · Prepared July 2026

---

## Table of Contents

1. [Design Principles](#1-design-principles)
2. [Bootstrap Architecture](#2-bootstrap-architecture)
3. [Pre-flight: Human Steps Required Before Script Runs](#3-pre-flight-human-steps-required-before-script-runs)
4. [Stack Decisions](#4-stack-decisions)
   - 4.1 Dotfiles Manager → chezmoi
   - 4.2 Terminal → Ghostty
   - 4.3 Shell → zsh + Starship
   - 4.4 Version Manager → mise
   - 4.5 JavaScript Runtime → Bun (new) + pnpm (existing)
   - 4.6 Container Runtime → OrbStack
   - 4.7 Code Editor → Cursor
   - 4.8 Secrets Management → 1Password CLI
   - 4.9 Menu Bar → Removed (native macOS Tahoe Menu Bar Controls sufficient)
   - 4.10 App Launcher & Window Management → Raycast (re-audited against native Tahoe overlap)
   - 4.11 SSH Key Management → 1Password SSH Agent
   - 4.12 App Store CLI → mas
   - 4.13 Dock Layout Automation → Manual step (not dockutil)
   - 4.14 Background Process Supervision → Pitchfork
   - 4.15 Agent Session Persistence → Entire CLI (recommended follow-up, not bootstrap-required)
   - 4.16 AI Coding Assistant Ecosystem → Claude Code + Claude Desktop
   - 4.17 Codebase Intelligence for Agents → codebase-memory-mcp (adopt with guardrails, install script automated in bootstrap)
   - 4.18 Claude Code Sandboxing → Enable by default + devcontainer for unattended work
   - 4.19 Local LLM Inference → Ollama
   - 4.20 LLM Observability & Cost Tracking → Langfuse (project-scoped)
5. [Homebrew Package List](#5-homebrew-package-list)
6. [macOS Defaults — Tahoe 26 Verified](#6-macos-defaults--tahoe-26-verified)
   - 6.1 Audit Methodology
   - 6.2 Confirmed Commands by Domain
   - 6.3 Explicitly Excluded Commands
   - 6.4 Commands Requiring Manual Setup
7. [macOS Tahoe 26 — What Changed](#7-macos-tahoe-26--what-changed)
8. [macOS Golden Gate 27 — Forward-Looking Audit](#8-macos-golden-gate-27--forward-looking-audit)
9. [chezmoi Architecture & Script Execution Order](#9-chezmoi-architecture--script-execution-order)
10. [File Structure Reference](#10-file-structure-reference)
11. [Ongoing Maintenance](#11-ongoing-maintenance)
12. [What Requires Manual Steps](#12-what-requires-manual-steps)
13. [Known Fragility & Future-Proofing Notes](#13-known-fragility--future-proofing-notes)
14. [Terminal Multi-Session & Per-Project Provisioning](#14-terminal-multi-session--per-project-provisioning)
15. [Audit Methodology & References](#15-audit-methodology--references)

---

## 1. Design Principles

Every decision in this document flows from these constraints, in priority order:

- **One command from zero → fully operational.** Day 1 on a bare Mac: `curl | bash`, then answer a few authentication prompts.
- **Idempotent.** Every script is safe to re-run at any time without side effects.
- **Secrets never touch git.** All credentials flow through 1Password CLI at runtime.
- **Config lives in a private GitHub repo.** chezmoi manages the dotfiles, scripts manage the rest.
- **Apple Silicon only.** M1/M2/M3/M4 — no Rosetta, no Intel paths.
- **Verified for macOS Tahoe 26.** Every `defaults write` command in this document has been cross-referenced against post-September 2025 Apple Community reports and developer forum posts. Nothing is copied from old blog posts without Tahoe verification.
- **Modular.** Each phase is independently re-runnable. A network failure mid-run doesn't corrupt the machine.
- **Forward-looking.** Architecture is designed with macOS Golden Gate 27 (September 2026) in mind.

---

## 2. Bootstrap Architecture

```
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/dotfiles/main/bootstrap.sh | bash
       │
       ├── PRE-FLIGHT (human gates — script pauses and instructs)
       │     ├── Verify Apple Silicon (fail fast if not)
       │     ├── Verify macOS 26+ (warn if older)
       │     ├── sudo keepalive loop (prevents mas timeout mid-run)
       │     ├── ⏸ PAUSE: "Sign into App Store, then press Enter"
       │     ├── ⏸ PAUSE: "Sign into 1Password + enable Touch ID, then press Enter"
       │     └── ⏸ PAUSE: "Grant App Management to Terminal in System Settings, then press Enter"
       │
       ├── PHASE 1 — Homebrew + bootstrap deps
       │     ├── Install Homebrew (idempotent)
       │     └── brew install git chezmoi mas (bootstrap deps only)
       │
       ├── PHASE 2 — chezmoi init (orchestrates everything else)
       │     ├── chezmoi init --apply git@github.com:USERNAME/dotfiles.git
       │     ├── Prompts: name, email, profile (personal/work — once, cached)
       │     ├── Writes all dotfiles to $HOME
       │     └── run_onchange_after_ scripts fire in order:
       │           ├── 10-install-packages.sh.tmpl  → brew bundle (full Brewfile)
       │           ├── 20-install-mas.sh.tmpl        → sudo mas install (other App Store apps —
       │           │                                    NOT Xcode, see Section 4.12 correction)
       │           ├── 30-macos-defaults.sh.tmpl     → defaults write (Tahoe-verified)
       │           ├── 40-mise-install.sh.tmpl        → mise install (all runtimes)
       │           ├── 50-resolve-secrets.sh.tmpl     → op inject → ~/.config/secrets/.env.global
       │           └── 60-install-codebase-memory-mcp.sh.tmpl → project's own install script
       │                                                 (no Homebrew formula exists — see 4.17)
       │
       ├── PHASE 3 — Post-install config (apps must exist first)
       │     ├── 1Password SSH agent config → ~/.ssh/config
       │     ├── GitHub SSH key setup (via op CLI)
       │     └── Ghostty + starship first run
       │     (Dock layout is a manual step — see Section 12. dockutil's
       │      compatibility with Tahoe's Dock changes is not confidently confirmed.)
       │
       └── VERIFICATION
             ├── brew bundle check
             ├── mise doctor
             ├── chezmoi verify
             └── Print summary: ✅ done / ⚠️ N warnings → ~/bootstrap.log
```

**Repository layout:** See Section 10 for the complete, authoritative file tree — this section covers execution order, not file structure, to avoid maintaining two copies of the same tree that can drift out of sync.

**Why chezmoi orchestrates Homebrew (not the other way around):**
chezmoi's `run_onchange_after_` prefix ensures scripts run *after* all managed dotfiles have been written to disk. This prevents the common bug where `brew bundle` runs before the Brewfile has been applied. Script order is controlled by numeric prefix (`10-`, `20-`, `30-`, `40-`). The `run_onchange_` prefix means brew only re-runs when the Brewfile content actually changes — not on every `chezmoi apply`.

---

## 3. Pre-flight: Human Steps Required Before Script Runs

These cannot be automated. The script pauses with instructions for each.

| Step | Why It Can't Be Automated | When |
|---|---|---|
| **Sign into App Store** | Apple auth wall; `mas account` detection broken since macOS 12+ | Before script starts |
| **Sign into 1Password + enable Touch ID** | Biometric setup requires GUI | Before script starts |
| **Grant App Management to Terminal** | Without this, `brew upgrade --cask` nukes Dock positions and app permissions on Tahoe | Before script starts |
| **Verify Spotlight enabled on /Applications** | `mas` uses Spotlight Metadata Service; disabled Spotlight = silent mas failures | Checked automatically in preflight |
| **Xcode install + license agreement** | `mas` is unreliable for Xcode specifically — see Section 4.12 correction. Download directly from developer.apple.com, then run `sudo xcodebuild -license accept` or accept the GUI EULA on first launch. | Before or during bootstrap — start the download early, it's large |
| **Cursor Settings Sync sign-in** | Requires Cursor account (GitHub login) | After install |
| **OrbStack license (commercial use)** | Payment required for commercial use | After install |
| **Linear / Slack / Notion sign-in** | Web auth | After install |

---

## 4. Stack Decisions

Each decision includes recommendation, rationale, evidence, and rejected alternatives.

---

### 4.1 Dotfiles Manager → **chezmoi**

**Decision:** chezmoi over dotbot, yadm, mackup, or bare git repo.

**Why:**
- Single binary, single branch, single command (`chezmoi apply`) works identically across machines
- Native 1Password CLI integration via Go templating — secrets never touch the repo
- `run_onchange_` scripts trigger Homebrew, mas, and macOS defaults only when those files change — no unnecessary re-runs
- One-liner bootstrap: `chezmoi init --apply <username>` (HTTPS, chezmoi expands it) or a full `git@github.com:...` URL for SSH — corrected from an earlier draft that used an invalid `gh:` prefix, which is not real chezmoi syntax and causes `ssh: Could not resolve hostname gh` (see Callout, Section 15 Pass 7)
- `dotfiles.github.io` community consensus pick for multi-machine setups

**Evidence:**
- chezmoi.io: "single source of truth, single command on every machine"
- DeployHQ (February 2026): "a fresh machine goes from zero to your full development environment in under a minute"
- Community migration pattern: chezmoi's Go templates replaced broken jinja2 dependencies in yadm; dotbot's symlink-only model has no parallel

**Rejected alternatives:**
- `dotbot` — symlink-only, no secrets management, no templating, no script ordering
- `yadm` — OS-specific file support fragile, external templating deps unmaintained
- `mackup` — syncs app settings but no secrets handling, Dropbox dependency
- `bare git repo` — zero features, manual management at scale

**chezmoi-specific gotcha (Tahoe-verified):**
Scripts placed in `.chezmoiscripts/` run *before* file changes unless prefixed `after_`. Always use `run_onchange_after_` for scripts that depend on managed files (like Brewfile) being written to disk first.

**chezmoi prompts at first run (kept minimal):**
```toml
# .chezmoi.toml.tmpl
{{- $name := promptStringOnce . "name" "Full name" -}}
{{- $email := promptStringOnce . "email" "Git email" -}}
{{- $profile := promptStringOnce . "profile" "Profile (personal/work)" -}}
[data]
  name    = {{ $name | quote }}
  email   = {{ $email | quote }}
  profile = {{ $profile | quote }}
```

**Do not use chezmoi's `age` encryption.** We use 1Password CLI (`op://` references) for all secrets. chezmoi's age encryption would add a key management problem — if you lose `key.txt`, every encrypted file is gone forever. 1Password handles key management better.

---

### 4.2 Terminal → **Ghostty**

**Decision:** Ghostty over iTerm2, Warp, Kitty, or Alacritty.

**Why:**
- GPU renderer written in Zig targeting Apple Metal directly — no intermediate rendering layers
- Independent benchmarks: ~3-4x throughput over iTerm2 on long log/build output, with the gap widening on Apple Silicon where Metal is most efficient [^1]
- ~45MB idle RAM vs iTerm2's ~120-185MB (sources vary on the iTerm2 baseline; Ghostty is consistently the smaller footprint by roughly 3-4x) [^2][^3]
- Free, open-source (MIT), no account required, no telemetry, no subscription
- **Current version: 1.3.1 (March 13, 2026)** — up from the 1.3.0 line referenced in earlier drafts of this document [^4]
- Created by Mitchell Hashimoto (HashiCorp founder) — production engineering pedigree
- Runs identically on Linux (GTK4) — consistent experience when SSH'd into remote boxes, though see the tmux/SSH terminfo caveat in Section 14.3
- **Tahoe-compatible:** Confirmed working on Tahoe 26 — uses Metal which is a first-class macOS API

**What's new in 1.3.0/1.3.1 (not in earlier drafts of this document):**
- Scrollback search (⌘F on macOS) — the most-requested feature in the project's history [^4]
- Native scrollbars, click-to-move-cursor in shell prompts (OSC 133 support), keybind chaining, richer clipboard behavior [^4]
- **AppleScript automation support, shipped as a preview feature** — Ghostty can now be scripted from AppleScript for window/tab/text-input automation, gated behind macOS TCC permissions. Explicitly marked unstable by the maintainers; expect breaking API changes in 1.4 [^5]
- 1.3.0 fixed a memory leak that had existed since the 1.0 release [^6]
- CVE-2026-26982 was patched in 1.3.0 — a control-character injection issue via paste/drag-and-drop that could execute arbitrary shell commands; relevant to note given this stack's security-conscious framing [^4]

**Evidence:**
- devtoolreviews.com (May 2026): Ghostty scores 9.5/10 for performance, described as "the fastest terminal emulator available on macOS in 2026" [^2]
- tech-insider.org (June 2026): community-run 100MB log-tail benchmark shows Ghostty completing in roughly one-third the time iTerm2 needed [^1]
- Fintech team (40 engineers) standardized on Ghostty in Q3 2025 after CPU saturation testing

**Why not Warp:** Requires account for full use, closed-source, higher idle RAM footprint, $20/month for AI features.
**Why not iTerm2:** CPU-rendered (not GPU-native), larger idle footprint, no Linux support. iTerm2 still wins on maturity — 15+ years of development, deeper session management, a much larger plugin ecosystem via its Python API, and native tmux control-mode integration that Ghostty does not have [^1][^2]. Keep iTerm2 installed as a fallback for AppleScript automation or tmux-control-mode workflows until Ghostty's AppleScript support matures past preview status.

**Tahoe note:** macOS 26 redesigned Terminal.app with 24-bit color and Powerline font support. This makes Apple's Terminal marginally better than before, but Ghostty still wins on every performance metric. Not a reason to reconsider.

---

### 4.3 Shell → **zsh + Starship + curated plugins**

**Decision:** Stay on zsh (macOS default), drop Oh My Zsh, use individual plugins and Starship.

**Why NOT Oh My Zsh:**
- Adds 200–400ms to shell startup by loading features you didn't ask for
- Monolithic update system can break configs
- The useful parts (plugins) are installable individually without the overhead

**Plugin stack:**
```
zsh                          ← macOS default, no change needed
starship                     ← cross-shell prompt, Rust-based, fast
zsh-autosuggestions          ← fish-style inline completion
fast-syntax-highlighting     ← faster than zsh-syntax-highlighting
zsh-completions              ← extended completion definitions
fzf                          ← fuzzy history, file, and process search
zoxide                       ← smart cd with frecency tracking
```

**Startup time target:** < 80ms. Achievable with this stack vs 400ms+ with Oh My Zsh.

**Config structure (managed by chezmoi):**
```
~/.zshrc                       ← sources all of the below
~/.config/zsh/aliases.zsh      ← all aliases
~/.config/zsh/functions.zsh    ← shell functions
~/.config/starship.toml        ← prompt config
```
(No `secrets.zsh` — see Section 4.8 for why. mise's `[env] _.file` mechanism replaced it.)

**Required in `.zshrc` — mise shell activation:**
```bash
eval "$(mise activate zsh)"
```
Without this line, mise is installed but not hooked into the shell — per-directory tool switching and `[env]` loading (including the secrets pattern in Section 4.8) silently do not happen. This must be one of the first lines in `.zshrc`, before Starship or any plugin sourcing, so that mise-managed tools are on `$PATH` before anything else in the shell tries to use them.

**The alias-vs-mise-task rule (hardened after an earlier draft violated it — see Section 9 for the full incident):**

> **Anything whose correct behavior depends on a project's toolchain, versions, or env vars is a mise task**, defined in that project's `.mise.toml`, invoked via `mise run <name>`.
> **Anything that is a generic, project-independent convenience** — a git shortcut, a `cd` helper, an `ls` replacement, an alias for a global CLI tool — **is a zsh alias or function**, global, in `aliases.zsh`.
> `aliases.zsh` must never hardcode a project-specific tool invocation (`bun run dev`, `pytest`, `cargo test`, `npm run build`). If a alias/function is doing that, it belongs in `.mise.toml [tasks]` instead, invoked with `mise run`.

**Example — correct split:**
```bash
# aliases.zsh — global, project-independent, always safe
alias gs='git status'
alias gp='git pull'
alias ll='eza -la'
alias cdd='cd ~/code'
```
```toml
# project's .mise.toml — project-specific, toolchain-dependent
[tasks.dev]
run = "bun run dev"
[tasks.test]
run = "bun test"
```
Calling `bun` (or any project tool) directly is only correct **inside** a `.mise.toml` task body — that's the floor of the abstraction, where mise hands off to the actual tool it's managing. It is incorrect everywhere else: not in `aliases.zsh`, not in a tmuxp layout, not in a chezmoi script, not in a Ghostty keybind. Anywhere else in the stack that needs to run a project command should call `mise run <task>`, never the underlying tool.

---

### 4.4 Version Manager → **mise**

**Decision:** mise over asdf, nvm, pyenv, rbenv, fnm.

**Current version: 2026.7.5 (July 9, 2026)** — mise ships on CalVer with releases roughly weekly; it is under very active development [^7][^8].

**Why:**
- Rust implementation: 10ms shell activation vs asdf's 120ms (shim-based)
- Single binary replaces: nvm + pyenv + rbenv + direnv + make task runner
- 7x faster tool installation than asdf-bash
- Reads `.tool-versions` (asdf-compatible), `.mise.toml`, and `.nvmrc` — no migration required on existing projects
- Built-in per-directory environment variable management (replaces direnv)
- Built-in task runner (`mise run dev`) replaces project Makefiles

**Evidence:**
- mac.install.guide/mise (2026): "7x faster installs, 10x lower shell overhead vs asdf-bash"
- pkgpulse.com (2026): "mise is the default pick for 2026"
- betterstack.com: mise wins on speed, security, DX, and lack of shim overhead

**Known cosmetic warning — `mise WARN gpg not found, skipping verification`.** mise optionally verifies some tool downloads (notably Node.js) with GPG signatures if `gpg` is available on `$PATH`; if it isn't, mise skips that check and continues rather than failing [^70]. This is confirmed as non-blocking by multiple independent reports showing the identical warning immediately followed by a successful `✓ installed` [^70]. `gpg` is intentionally not in this stack's Brewfile — nothing else in this document currently needs it — so this warning is expected on every fresh bootstrap, not a sign of a problem. If verified downloads become a priority later, `brew install gnupg` resolves it; there is also a `gpg_verify = false` mise setting to silence the warning without installing gpg, though leaving it as-is (warn-but-continue) is the current default and not something this stack overrides.

**Open item — `mise doctor` reported unspecified issues on first real bootstrap run.** The bootstrap log only showed a generic "⚠️ mise doctor reported issues. Run 'mise doctor' manually to inspect." without the actual output, so the specific issue(s) are not yet diagnosed as of this writing. This is flagged here as a known open item rather than resolved — see Section 15, Pass 17, for what's confirmed versus still pending.

**Global `~/.config/mise/config.toml`:**
```toml
[tools]
node    = "22"          # LTS — keeps existing pnpm projects working
bun     = "latest"      # new projects default
python  = "3.12"        # mise is the sole owner of Python — no brew python@X.Y needed
go      = "latest"
rust    = "stable"
java    = "temurin-21"  # iOS/Android tooling
terraform = "latest"
kubectl   = "latest"
pitchfork = "latest"    # background process supervision — see Section 4.14

[env]
_.file = "~/.config/secrets/.env.global"   # resolved secrets — see Section 4.8 for how this file is generated
EDITOR = "cursor"
MISE_NODE_DEFAULT_PACKAGES_FILE = "~/.default-node-packages"
CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE = "1"   # see Section 4.16
CBM_ALLOWED_ROOT = "~/code"   # see Section 4.17
```
The `_.file` line above is the full secrets story in outline — Section 4.8 covers why it's structured this way (not native mise/1Password integration, but `op inject` resolving a template into this file) and the corresponding per-project pattern.

**Why removing `brew python@3.12` is safe:** Homebrew formulae that need Python at build or runtime (awscli, cmake's optional Python bindings, etc.) either vendor their own isolated Python via `brew`'s dependency resolution or use their own bundled interpreter — they do not require a *system-visible* `python3` on `$PATH`. mise's `python` install becomes the only `python3` a shell session sees, which is the intended single-source-of-truth setup. If a specific formula is ever found to genuinely require a Homebrew-managed Python at the shell level, that's a signal to revisit — not a reason to pre-install it defensively.

**Per-project override (`.mise.toml` in project root):**
```toml
[tools]
node = "20.11.0"    # pinned for legacy project

[env]
DATABASE_URL = "postgresql://localhost/myapp_dev"
NODE_ENV     = "development"

[tasks.dev]
run = "bun run dev"

[tasks.test]
run = "bun test"
```
**Note on why calling `bun` directly here is correct, not a layering violation:** `.mise.toml` task bodies are the one place in the entire stack where calling the underlying tool directly is the right move — this is the floor of the abstraction, where mise hands off to the tool it manages. The rule (spelled out fully in Section 4.3) is that everywhere *else* in the stack — aliases, tmuxp layouts, chezmoi scripts, editor keybinds — should call `mise run dev`, never `bun run dev` directly. If this distinction ever looks blurry, the test is: "is this code defining what a task means, or consuming a task someone already defined?" Definition happens here, in `.mise.toml`. Everything else consumes.

> **📋 Callout #1 — mise now ships its own native bootstrap system, discovered during this audit.** As of roughly v2026.6.14 (late June 2026), mise added a first-party `mise bootstrap` command with `[bootstrap.packages]` (Homebrew formulae/casks/mas in one declarative block), `[bootstrap.repos]` (dotfile repo cloning), `[dotfiles]` (symlink management), `[bootstrap.macos.dock]` / `.finder` / `.keyboard` / `.trackpad` / `.defaults` (native macOS defaults management), and `[bootstrap.mise_shell_activate]` (shell rc wiring) [^9][^10][^11]. This is functionally adjacent to a large part of what chezmoi + our custom bootstrap.sh does in this document's architecture.
>
> **Re-scoped decision, corrected after review.** An earlier draft of this callout leaned on chezmoi's Go-template engine (per-machine config variation) and native encryption as the deciding advantages over `mise bootstrap`. On review, that overweighted a requirement that doesn't currently apply: this is a solo setup, one machine, no near-term plan to onboard other engineers or run this config across multiple workstations. On that basis:
> - **Templating:** chezmoi's `.tmpl` branches (`profile == personal/work`, etc.) only exist to handle variation across contexts. With one machine and one identity, every branch evaluates one way — the templating engine isn't doing real work right now. Client/project-specific variation for consulting work is better handled by mise's own per-project `.mise.toml` scoping (already part of this architecture) than by machine-level chezmoi templates, so this doesn't rescue the case either.
> - **Encryption:** moot — Section 4.8 already routes all secrets through 1Password CLI (`op inject`), not chezmoi's `age`/`gpg` support. That chezmoi feature exists but isn't in use here regardless of which tool owns dotfiles.
> - **What's actually left in chezmoi's favor:** `run_onchange_` (content-hash-triggered scripts, no clean mise-bootstrap equivalent for arbitrary files) and **maturity** — `mise bootstrap` is roughly 3-4 weeks old, under heavy active weekly development, with at least one live bug report on the exact `brew-cask` install path this Brewfile depends on [^12]. For a solo bootstrap with no second engineer to validate the path first, that maturity gap is the actual reason to hold, not the templating/encryption argument from the earlier draft.
>
> **Current guidance:** stay on the chezmoi-orchestrated architecture in this document for now. **Independently of this document, you're evaluating `mise bootstrap` yourself** — if that evaluation goes well and the brew-cask bug and `[bootstrap.macos.defaults]` prove solid against the Tahoe-specific caveats in Section 6 (autohide race condition, Control Center exclusions, etc.), the honest re-scoped case above says a solo, single-machine setup is exactly the situation where consolidating onto `mise bootstrap` and dropping chezmoi becomes reasonable — not a compromise, a legitimate simplification. This document will be updated to reflect that shift if and when you land on it.

**Note on the Usage spec (usage.jdx.dev) — evaluated, not adopted.** Usage is a schema/spec (KDL-based) for defining CLI argument parsers — closer to OpenAPI for CLIs than to a workstation tool [^25]. It's not something to install or configure here; it's infrastructure for *authoring* CLIs, and this stack is about *provisioning a machine*, not building one. Worth knowing it already runs invisibly underneath mise itself — `mise run <task> --help` and mise's typed task arguments are powered by the Usage spec [^25]. No Brewfile entry, no further action — only relevant again if you start building your own CLI tools for client work.

---

### 4.5 JavaScript Runtime → **Bun (new projects) + pnpm/Node (existing)**

**Decision:** Dual-track. Not a cold-turkey migration.

**Strategy:**

| Project Type | Runtime | Package Manager |
|---|---|---|
| New greenfield | Bun | `bun install` |
| Existing pnpm/Node project | Node 22 | pnpm (keep it) |
| High-throughput API | Bun | `bun install` |
| Native addons (node-gyp) | Node 22 | pnpm |
| CI/CD (any project) | Bun as package manager | `bun install` as drop-in for speed |

**Why Bun for new projects:**
- 35x faster installs than npm, 5x faster than pnpm
- Single binary: replaces node + npm/pnpm + ts-node + jest + esbuild + nodemon
- Native TypeScript execution, no compilation step
- Bun 1.3 passes 90%+ of Node.js test suite, 98% npm compatibility
- JavaScriptCore engine: 3–4x faster HTTP throughput than Node's V8 for APIs
- Anthropic acquired Bun in December 2025 and deploys it for Claude Code infrastructure

**Why keep pnpm for existing:**
- Zero migration risk for working codebases
- Strict dependency resolution prevents phantom dependency bugs
- pnpm is already 6–8x faster than npm

**Known Bun caution flags:**
- Long-running processes (72h+): Node's V8 GC is more battle-tested for memory management
- Native C++ addons: compatibility lower — test before committing
- `bun install --production` can crash without package cache — pin Bun version in CI

---

### 4.6 Container Runtime → **OrbStack**

**Decision:** OrbStack over Docker Desktop, Podman, Colima, and Apple Container (for now).

**Why:**
- Full Docker API compatibility: all existing `docker-compose.yml` and `Dockerfile` work unchanged, including current versions of Compose and buildx bundled and kept up to date automatically [^20]
- 3–5 second VM cold start vs Docker Desktop's ~60 seconds
- 200MB idle RAM vs Docker Desktop's 3–4GB
- VirtioFS caching: up to 10x less filesystem overhead than Docker Desktop
- `pnpm install` inside a container runs at 88% of native speed (Docker Desktop: 3–4x slower)
- Native Swift app, Mac-first UX — **recently redesigned into what OrbStack's own release notes describe as "a full-fledged container IDE"** [^20]
- **Confirmed unaffected by recent CVEs:** OrbStack's own docs state it was not affected by "Copy Fail" (CVE-2026-31431) or the recent io_uring ZCRX vulnerability — worth noting given this stack's security-conscious framing [^20]
- **Tahoe-compatible:** Confirmed working; uses Apple Virtualization.framework which is actively supported

**Evidence:**
- usedocker.com (June 2026): "Speed, on every axis that matters in interactive development"
- wpriders.com: "Up to 10x faster file I/O, 60% memory reduction"
- buildmvpfast.com: "pnpm install inside container: 88% of native speed on OrbStack"
- OrbStack's own release notes [^20]

**Migration from Docker Desktop:** Zero changes needed. OrbStack implements the full Docker Engine API. You keep `docker`, `docker compose`, all CLI muscle memory.

**Pricing:** Free for personal use. Commercial use requires paid subscription.

**Upgrade note:** OrbStack self-updates. Use `brew upgrade --greedy orbstack` (not plain `brew upgrade`) for manual upgrades via Homebrew.

**Rosetta prompt on first launch — expected, not a bug, no Apple-Silicon-only build exists.** OrbStack prompts to install Rosetta 2 on Apple Silicon by design: it uses Rosetta to run x86_64/amd64 Docker images and Intel Linux binaries at near-native speed, rather than falling back to slow QEMU-based emulation [^65]. This is confirmed, intentional behavior, not something specific to this stack's setup — one GitHub issue confirms OrbStack can even block entry to its own UI until Rosetta is installed on a system that doesn't have it [^66]. Accept the Rosetta install prompt; there is no way to skip it and still get x86 image support, and no separate "Apple Silicon only" OrbStack build exists that avoids this. If you never intend to run x86/amd64 images (all-ARM64 workloads only), Rosetta can reportedly be disabled in OrbStack's settings afterward, though official guidance is to leave it enabled since it also fixes Rosetta bugs that affect other apps [^65].

**Why not Apple Container (yet):**
Apple's own open-source Linux container tool (`apple/container`, Apache 2.0) hit v1.0 on June 9, 2026. It requires macOS 26 (Tahoe), is Apple Silicon only, and runs one lightweight VM per container. It is promising but not yet viable as a primary tool:
- No Docker Compose support (community workarounds are immature)
- No `docker` CLI compatibility — different command surface
- Small-file I/O slower than OrbStack (npm/node_modules penalty)
- No GUI

Watch for Docker Compose support landing. When it does, Apple Container becomes worth evaluating as a replacement.

---

### 4.7 Code Editor → **Cursor**

**Decision:** Cursor replaces VS Code entirely.

**Current status (mid-2026):** Cursor is used by 1M+ developers and ~360,000 paying customers, with $2B+ annualized revenue and adoption inside 64% of the Fortune 500 [^13]. Current release line is Cursor 3.5 (May 20, 2026), headlined by Cloud Agents running in isolated cloud VMs [^13].

**Why:**
- Cursor is a VS Code fork — settings, keybindings, and the general editing experience transfer directly
- `cursor` CLI works identically to `code`
- All existing `.vscode/` project configs continue working
- AI-native: context-aware completions across the entire codebase, not just the current file
- As of mid-2026, Cursor is the dominant AI-native editor choice for serious full-stack developers, though see the correction below and the note on Claude Code

> **📋 Callout #2 — correction to an earlier claim.** An earlier version of this document stated "all VS Code extensions work" in Cursor. **This is not accurate and has been corrected.** Cursor cannot access the official VS Code Marketplace — it uses the Open VSX registry plus its own workarounds. Roughly 90% of popular extensions work without modification (ESLint, Prettier, GitLens, Docker, Python community builds, Go, Rust Analyzer, Tailwind CSS) [^14][^15]. **Named, documented exceptions:**
> - **Pylance** (Microsoft's Python language server) — not available; Cursor ships Pyright (the open-source core) instead, which covers most but not all functionality
> - **C# Dev Kit** — not available; use the community C# extension instead
> - **Remote SSH** (official Microsoft extension) — actively checks for VS Code and refuses to run under Cursor; community forks exist but require manual setup
> - **Live Share** — Microsoft-only, no workaround exists
> - **C/C++ Extension** — versions after 1.17.62 are broken under Cursor; older versions still work [^14]
>
> For this stack's primary use cases (web/full-stack, native iOS/macOS via Xcode not Cursor, backend/systems, data/ML), these gaps are minor — the exceptions cluster around Microsoft-proprietary tooling and remote development workflows. If remote SSH development becomes a regular need, this is worth revisiting.

**Competitive context worth noting neutrally:** Multiple aggregated 2026 industry surveys (Stack Overflow, JetBrains AI Pulse, DORA, Pragmatic Engineer) report that by Q1 2026, Claude Code — Anthropic's own terminal-native coding agent — overtook both Cursor and GitHub Copilot in professional developer usage and satisfaction, while Cursor remains the leader specifically among IDE-integrated AI editors [^16]. This is included for completeness given Claude is the assistant producing this document; the stack recommendation of Cursor as primary editor stands, since Claude Code and Cursor serve different workflows (terminal-agent vs. IDE) and are not mutually exclusive — Claude Code can be used from inside a Cursor or Ghostty terminal pane regardless of editor choice.

**What to automate:**
- Install via `brew install --cask cursor`
- Extension list committed to dotfiles repo; installed via `cursor --install-extension <id>`
- Settings managed via chezmoi: `~/.config/cursor/User/settings.json`

**Settings Sync:** Cursor has built-in Settings Sync (linked to GitHub account) as a simpler alternative to chezmoi-managed settings. Either works. Using chezmoi is preferred because it's version-controlled alongside everything else.

---

### 4.8 Secrets Management → **1Password CLI (op) + mise-scoped env files**

**Decision:** 1Password CLI as the single source of truth for *storage*. mise's `[env] _.file` mechanism as the single source of truth for *loading* — at both global and per-project scope. No standalone `secrets.zsh`.

**Why this changed from an earlier draft:** An earlier version of this architecture routed all secrets through a global `~/.config/zsh/secrets.zsh`, loaded unconditionally by `.zshrc`. That created two competing systems for "how do env vars get into my shell" — the global secrets file, and mise's own per-project `[env]` block described in Section 4.4 — with no defined precedence between them. Since mise is already the established single source of truth for per-directory environment configuration, a second always-on global mechanism duplicates that responsibility and creates drift risk. This section replaces it with one mechanism, scoped consistently at both levels.

**Important correction on mise + 1Password:** mise does **not** have native, first-class 1Password integration. Checked directly against mise's own maintainer: mise's environment reloads on effectively every shell prompt, and remote secret calls (1Password, KMS, etc.) are too slow for that reload model to be a good fit — mise's maintainer stated this directly and shipped a separate tool (`fnox`) rather than building 1Password resolution into mise core. The `mise-env-1password` plugin exists but is an unofficial third-party plugin, not part of core mise, and inherits the same reload-performance caveat. **We do not use it.**

**The actual pattern — mise scopes, `op inject` resolves, once, on demand:**

mise loads env vars from a file via `_.file` in its `[env]` block — this part is core, stable, well-documented functionality. We point that file at something **already resolved**, generated by 1Password's own purpose-built tool for exactly this job (`op inject`), rather than asking mise to call `op` live on every reload.

**Global scope** (`~/.config/mise/config.toml`):
```toml
[env]
_.file = "~/.config/secrets/.env.global"   # gitignored, generated via op inject — see below
EDITOR = "cursor"
MISE_NODE_DEFAULT_PACKAGES_FILE = "~/.default-node-packages"
CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE = "1"   # Homebrew casks don't auto-update by default —
                                                  # see Section 4.16; this opts Claude Code itself
                                                  # into background updates despite the cask install
CBM_ALLOWED_ROOT = "~/code"   # restricts codebase-memory-mcp's index_repository to this
                                # directory tree — see Section 4.17; a real security guardrail
                                # given this machine's client/consulting repo access, not optional
```

```
# ~/.config/secrets/.env.global.tpl  (committed to dotfiles repo — references only, no secrets)
GITHUB_TOKEN=op://Developer/GitHub-PAT/credential
# ANTHROPIC_API_KEY intentionally omitted — see the note below and Pass 20
```

**`ANTHROPIC_API_KEY` removed from this stack entirely — a deliberate scope decision, not a bug.** An earlier version of this file included `ANTHROPIC_API_KEY=op://Developer/Claude API/credential` as a default example secret, alongside the GitHub PAT. When the user reached this step in a real bootstrap run, the referenced item didn't exist — the same class of "placeholder item never confirmed against the real vault" issue as the `GitHub-PAT` item in Pass 19 — but this time the correct fix was removal, not creation, on direct instruction: **this machine doesn't use the pay-per-token Anthropic API Platform at all.** Claude Code, Claude Desktop, and every other Claude surface listed in Section 4.16 authenticate through their own subscription-based login flow, not an API key — confirmed by re-checking Section 4.16 directly, which describes no dependency on `ANTHROPIC_API_KEY` anywhere. The API Platform is a genuinely separate product with per-token pricing and overage risk that the user explicitly does not want provisioned into this vault at this time. If that changes later — building something that calls the Anthropic API directly, for example — the pattern to follow is identical to `GITHUB_TOKEN`: create a real 1Password item first (`op item create --category "API Credential" --title "<name>" --vault "Developer" --field "credential=<key>"`), confirm it with `op item get`, then add one line to this template.

```bash
# Regenerate whenever secrets rotate or on a new machine (one command, human-run or chezmoi-scripted):
op inject -i ~/.config/secrets/.env.global.tpl -o ~/.config/secrets/.env.global
```

**A real bug found here on first execution: `op inject` does not treat `#` as a comment marker.** The actual `.tpl` file's first comment line originally read `# op:// REFERENCES ONLY — no actual secrets...`, meant purely as a human-readable description of the file's purpose. `op inject` scanned the entire file text for anything matching the `op://` pattern — including inside that `#` comment — and tried to parse `REFERENCES ONLY` as a real vault/item/field path, failing with `invalid secret reference 'op://REFERENCES ONLY': too few '/'`. Checked directly against real-world `op inject` template examples from multiple independent sources: none of them include explanatory comments describing the `op://` syntax using the literal string, which is consistent with `op inject` doing a straightforward text-scan rather than a real line-oriented parser that understands `#` as a comment marker [^71]. **Standing rule for any file that is ever passed as `-i` input to `op inject`: never write the literal `op` immediately followed by `://` in prose or comments, even to describe the syntax — split the string apart (e.g. `"op" followed by "://"`) if it needs to be mentioned at all.** This does not apply to files that merely mention `op inject` conceptually without being fed to it as input (chezmoi scripts, `.gitignore`, `.chezmoi.toml.tmpl` all safely reference the pattern in prose, since none of them are ever the file `op inject -i` reads).

**A second, more consequential bug found immediately after: `GITHUB_TOKEN`'s field name was wrong, and — more fundamentally — the item it referenced never existed in the user's real vault at all.** `op://Developer/GitHub-PAT/token` failed with `could not find item GitHub-PAT in vault ...`. Unlike every prior bug in this document, this was not a fixable syntax error — the item name `GitHub-PAT` was a placeholder invented when this architecture was first designed, never confirmed against the user's actual 1Password contents, because this document has no way to inspect someone's real vault. Creating the item was the correct fix, not editing the template. While fixing this, a second, real syntax bug was also caught: the field name `token` does not exist on 1Password's "API Credential" item category — confirmed directly against 1Password's own item-category documentation, which states plainly that API Credential items store their secret in a field literally named `credential`, and independently confirmed by a third-party guide stating explicitly that this is why `op://` references for this category end in `/credential`, not `/token` — a mistake common enough to be called out by name [^72]. `ANTHROPIC_API_KEY` in this same file already correctly used `/credential`; only `GITHUB_TOKEN` had the wrong field name, suggesting the two lines were written at different times with different levels of care rather than the same mistake made twice.

**To create the matching item, the correct command uses the API Credential category and the `credential` field explicitly:**
```bash
op item create \
  --category "API Credential" \
  --title "GitHub-PAT" \
  --vault "Developer" \
  --field "credential=ghp_YOUR_ACTUAL_TOKEN_HERE"
```

**A structural gap this exposed: nothing in this stack verifies that a template's referenced items actually exist before a real bootstrap run reaches them.** This document cannot see into anyone's actual 1Password vault, so any example item name it ships is necessarily a placeholder — but nothing flagged that clearly enough before the user hit it as a runtime failure. The corrective pattern going forward: any new `op://` reference added to `dot_env.global.tpl` or a per-project `.env.local.tpl` should be treated as unverified until the person adding it has confirmed, with `op item get <title> --vault <vault>`, that the item and field actually exist — a cheap, one-line check that would have caught this before it reached `op inject`.

**Per-project scope** (`.mise.toml` in project root — extends the pattern already shown in Section 4.4):
```toml
[env]
_.file = ".env.local"   # gitignored, project-specific, generated the same way

[tasks.dev]
run = "bun run dev"
```

```
# .env.local.tpl (committed to the project repo — references only)
DATABASE_URL=op://Developer/myapp-db/url
STRIPE_KEY=op://Developer/myapp-stripe/key
```

```bash
op inject -i .env.local.tpl -o .env.local
```

**Why this is correct, not just convenient:**
- **One loading mechanism, not two.** mise's `[env] _.file` is the only thing deciding what lands in your shell env, at every scope. There's no longer a question of "does `secrets.zsh` or `.mise.toml` win" — mise always wins, because it's the only one running.
- **`op inject` is 1Password's own recommended tool for this**, not a workaround — 1Password's official docs describe exactly this file-templating pattern as one of the three supported ways to resolve secret references at runtime.
- **Avoids the specific performance problem mise's maintainer flagged, and does so for a documented reason, not just by assertion.** The maintainer's complaint was about mise making *remote* calls (to a secrets backend) as part of its reload cycle. `_.file` is a local file read, not a remote call, so that specific failure mode doesn't apply here. Separately, mise's `hook-env` — the mechanism that runs on every shell prompt — has a built-in fast-path that skips full config/env recalculation entirely when the directory hasn't changed and no watched config file's mtime has changed; the `_.file` content is only actually re-read on `cd` into the project (or when the file changes), not on every prompt render while sitting still. If this ever needs to be faster still, mise's `env_cache = true` setting caches the fully computed environment (including `_.file` output) to disk, encrypted, invalidated only by `watch_files` mtime — available as a one-line addition to `~/.config/mise/config.toml` if it's ever warranted, though the fast-path alone should make it unnecessary for a file this small.
- **Same contract at global and project scope** — a future engineer onboarding to this stack learns the pattern once (`*.tpl` committed, `op inject` to resolve, mise loads the result) and it's identical whether the secret is personal or project-specific.

**GitHub Personal Access Token, GitHub SSH Key, Claude/Anthropic key, OpenAI key, AWS credentials** all live in the "Developer" 1Password vault as before — only the *loading* mechanism changed, not the storage.

**chezmoi's role is narrower now:** chezmoi still manages the `.tpl` files (they're just dotfiles — safe to commit, contain no secrets) and can run `op inject` as a `run_onchange_after_` script keyed to the `.tpl` file's hash, so secrets are freshly resolved whenever the template changes. chezmoi does **not** need `onepasswordRead` in `.chezmoi.toml.tmpl` for this anymore — that data-templating approach is still valid for one-off values chezmoi itself needs (like `git_email` for `.gitconfig`), but bulk secrets now flow through the mise/op inject pattern above, not through chezmoi's own templating.

**Do NOT use `security` CLI on Tahoe.** The `security find-generic-password` command hangs indefinitely on macOS Tahoe 26.x due to a SecurityAgent regression. This is a confirmed Tahoe bug. All secrets flow through `op` — never through `security`.

**Future-proofing note (per project standing decision):** If this contract needs to break later — for example, if `fnox` matures and becomes the better fit, or a future mise release ships native 1Password support — swapping the resolution mechanism only touches the `_.file` target and the regeneration command. The `.mise.toml [env]` contract and the "mise is the only loader" principle don't change.

---

### 4.9 Menu Bar → **Removed — native macOS Tahoe handles this**

**Decision:** No third-party menu bar manager. Removed entirely per direct user request, on the grounds that macOS Tahoe 26 replaced the need for it with a native capability. Checked directly rather than taken on faith, and the reasoning holds up.

**What macOS Tahoe actually provides natively:** A dedicated Menu Bar section in System Settings (System Settings → Menu Bar → Menu Bar Controls) covering per-app icon show/hide toggles, Command-drag reordering of icons, and menu bar auto-hide modes (always, desktop-only, full-screen-only, never) [^52][^53][^54]. Multiple independent sources confirm this is now sufficient for most users' needs — one reviewer wrote plainly that having this built-in option eliminated their need for a third-party menu bar manager entirely [^54].

**A second, forward-looking reason this decision holds up beyond Tahoe:** per one source tracking the beta cycle, macOS 27 Golden Gate is reported to add a native expand button for overflow menu bar icons — and to break Bartender, Ice, Thaw, and Hidden Bar in the process [^55]. If accurate, this isn't a temporary gap third-party tools are racing to fill — it's a trend of Apple absorbing this functionality natively across consecutive OS versions. Betting on a third-party menu bar manager here would mean re-litigating this decision again at the next major OS upgrade regardless.

**History, kept for context — this decision went through two prior states before landing here, each a real correction, not just iteration for its own sake:**
1. **Originally: Ice, believed confirmed working on Tahoe 26.** That claim did not hold up — checked again after a real bootstrap failure and found two independent bugs: the Homebrew cask token used (`cask "ice"`) had never existed (the real token is `jordanbaird-ice`), and Ice itself has documented Tahoe crash reports, both on 26.0 [^49] and as recently as 26.5 in June 2026 [^50].
2. **Corrected to: `jordanbaird-ice@beta`**, since a confirmed community fix for the exact crash was switching to Ice's beta channel [^51].
3. **Final: removed entirely.** Given native Tahoe controls are independently confirmed sufficient, and third-party menu bar managers are trending toward being broken by Apple's own roadmap rather than needed going forward, carrying a beta-channel dependency for functionality the OS now provides natively isn't worth the maintenance burden.

**No install step. No Brewfile entry.** If a genuine gap in native controls is found later (e.g., automation rules beyond simple show/hide), revisit — Hidden Bar (App Store, free, confirmed stable across all Tahoe betas and releases per one source [^55]) would be the narrower, lower-risk option to evaluate first, given it does one thing rather than the broader feature set Ice/Bartender attempt.

---

### 4.10 App Launcher & Window Management → **Raycast**

**Decision:** Raycast replaces Spotlight for launching and adds window management, clipboard history, and more — all in one tool. Re-audited directly against native Tahoe capability (Section 4.9's gap prompted a full pass across the rest of the stack) — this decision holds up, for reasons now documented explicitly rather than assumed.

**Why, re-verified against native Tahoe features specifically:**
- **Launcher role:** Tahoe removed Launchpad outright, replacing it with a Spotlight-integrated "Apps" view [^56][^57]. Multiple independent sources are explicit that this split is real, not just a preference: a grid-first launcher (what Launchpad was) and a keyboard-first launcher (what Raycast is) serve genuinely different workflows, and a search-based tool like Raycast is the correct fit for someone who already works keyboard-first — which this entire stack does (`mise run`, `tmuxp`, alias-driven shell workflow throughout) [^56]. This isn't a gap native Tahoe left for Raycast to fill by accident; it's a case where Raycast was already the better-suited tool for this stack's working style, independent of what Launchpad's removal changed.
- **Window management:** Tahoe's native tiling (drag-to-edge, System Settings → Desktop & Dock → "Tile by dragging windows to screen edges") is confirmed genuinely sufficient for basic snapping — one independent three-week comparison test states plainly that if you only tile windows once or twice a day, native tiling "probably does everything you need" [^58]. But Raycast's window management is not a separate tool layered on top of a gap — it's Raycast's own first-party built-in feature (the same free tier already in this stack for launching), confirmed to cover halves, quarters, thirds, centering, and multi-monitor moves [^59][^60]. There is no separate Rectangle/Magnet dependency to audit here; Raycast's window management was already the whole answer, and using Raycast for it (rather than defaulting to native tiling alone) is a legitimate choice given this stack already has Raycast running for other reasons — not redundant, since it's zero marginal cost.
- **Clipboard history:** Tahoe added a genuine native clipboard history in Spotlight (Command+Space, Command+4), confirmed across many independent sources [^61][^62][^63]. It is real and free, but every source examined agrees it is intentionally basic — capped retention (originally 8 hours, extended to a configurable 30 minutes/8 hours/7 days as of Tahoe 26.1), no pinning, no advanced search, Mac-only [^63][^64]. Raycast's clipboard history (already part of the same free tier) is explicitly the more capable option for anyone who needs longer retention or pinning [^64] — again, zero marginal cost since Raycast is already running.

**Net finding from this audit:** unlike Ice, nothing here was a wrong assumption. Raycast's role was already correctly scoped to complement rather than duplicate native Tahoe features, and the free-tier bundling (launcher + window management + clipboard history in one already-installed tool) means there was never a separate redundant dependency to remove. Documented explicitly now so this reasoning doesn't have to be re-derived if questioned again.

**Key extensions to install post-setup:**
- GitHub (search repos, PRs, issues)
- Linear (create/search issues)
- Clipboard History
- Window Management
- Color Picker
- Brew (search/install packages)

---

### 4.11 SSH Key Management → **1Password SSH Agent**

**Decision:** Use 1Password as your SSH agent. SSH private keys never live on disk.

**Why:**
- SSH keys stored in 1Password vault — never written to `~/.ssh/` in plaintext
- Touch ID authenticates each `git push`, `ssh`, and `scp`
- Survives machine migrations with zero key export/import
- Works with `git@github.com` and all SSH operations

**Config (`~/.ssh/config` — managed by chezmoi as `dot_ssh/config`):**
```
Host *
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

**Bootstrap ordering note (found in Pass 7, see Section 15):** `bootstrap.sh` clones the dotfiles repo via SSH *before* chezmoi has applied anything — including this very file. `bootstrap.sh` pre-seeds an identical copy of this config directly (idempotent, checks for existing content first) so the initial clone can succeed. Once `chezmoi apply` runs, `dot_ssh/config` becomes the source of truth going forward; the two are kept in sync by design, not by coincidence — if this file's content ever needs to change, update `dot_ssh/config` and mirror the change in `bootstrap.sh`'s pre-seed step.

**Required manual step (added to runbook pre-flight in Pass 7):** 1Password's SSH Agent must be manually enabled — Settings → Developer → "Use the SSH Agent" — before running `bootstrap.sh`. Without it, `git clone` over SSH fails or hangs waiting for a key that the default `ssh-agent` doesn't have.

---

### 4.12 App Store CLI → **mas, but NOT for Xcode — corrected after further verification**

**Decision:** mas (community-built, MIT licensed) remains in the stack for App Store apps generally. **Xcode is removed from the automated `mas` path and moved to a manual step.** This corrects an earlier version of this document that claimed Xcode installation was "handled" by the bootstrap script — that claim was not actually verified against real-world `mas`/Xcode behavior, and it doesn't hold up.

**Important clarifications:**
- mas is **not** an official Apple tool. It is open-source, community-maintained, written in Swift.
- Apple has no official CLI for the Mac App Store.

**Two real, sourced failure modes that make automated Xcode install via `mas` unreliable:**

1. **`brew bundle` uses `mas install`, not `mas get` — and `mas install` fails on fresh Apple IDs.** An open Homebrew issue (filed Feb 2026, unresolved) documents that `mas install` only re-downloads apps already associated with the Apple Account; on a fresh machine or an Apple ID that's never acquired the app before, it fails outright with `Redownload Unavailable with this Apple Account` — even for free apps like Xcode [^39]. `mas get` (alias `mas purchase`) is the command that actually works for first-time installs, but that's not what `brew bundle`'s `Brewfile` `mas` directive invokes, and this is a Homebrew bug, not something this stack's script can route around from the Brewfile alone.
2. **Xcode specifically is known to fail or hang via the App Store install path, independent of the tool used to trigger it**, due to its size. Multiple Apple Community threads describe App Store-path Xcode installs stalling or erroring, with Apple's own community consistently recommending direct download from developer.apple.com instead of the App Store for exactly this reason [^40].

**Corrected decision: Xcode is a manual step.** Direct download from developer.apple.com (requires free Apple Developer account sign-in) is both more reliable and, per the Apple Community sourcing above, the generally recommended path regardless of automation tooling. This is now reflected in the runbook as a Section 3 manual step, started early/in parallel with the bootstrap script since it's a large download.

**mas remains appropriate for smaller, previously-acquired App Store apps** where the "fresh Apple ID" failure mode is less likely to bite (an app already associated with your account from a previous machine) — but given this is explicitly a *new* machine with what may be a rarely-used or fresh App Store association, do not assume any `mas`-driven install in the Brewfile succeeds unattended. Treat `brew bundle check`'s output as the source of truth, not an assumption.

**Other known constraints (still accurate, unrelated to the Xcode finding):**
- Requires `sudo` for all install/update operations since CVE-2025-43411 fix
- `mas account` sign-in detection broken since macOS 12+ — replaced with a manual pause gate
- Spotlight must be enabled on `/Applications` for mas to detect installed apps
- The bootstrap script caches `sudo` at startup with a keepalive loop to prevent timeout mid-run

**Xcode is no longer in the Brewfile's `mas` block.** Removed:
```ruby
# REMOVED — see correction above. Xcode installed manually instead.
# mas "Xcode", id: 497799835
```

---

### 4.13 Dock Layout Automation → **Manual step (not dockutil)**

**Decision:** Do not automate Dock layout via dockutil. Configure manually post-install.

**Why:**
dockutil (`kcrawford/dockutil`, 1.6k GitHub stars) is an actively maintained project — commits and open PRs as recent as December 2025, and it was migrated to a SwiftPM package specifically to support Homebrew's packaging requirements. That's a genuine positive signal.

However, this research could not find explicit, dated confirmation that dockutil works correctly against **Tahoe's changed Dock architecture** — the same underlying `com.apple.dock.plist` structure that produced the auto-hide race condition and rendering bugs documented in Section 6 and Section 7. dockutil works by directly manipulating that plist. A tool with that level of coupling to internal Dock state is exactly the kind of dependency that's highest-risk during a redesign like Liquid Glass, and the absence of a clear "confirmed working on Tahoe" signal — in either direction — is not the same as confirmation.

Per the standing project requirement that compatibility must be confirmed rather than assumed, and that manual steps are an acceptable trade-off when automation confidence is low, Dock layout is a manual step. It takes under a minute per machine and removes a genuine unknown from the bootstrap.

**What to watch:** If a future dockutil release or changelog explicitly states Tahoe 26 compatibility, or if community reports confirm it cleanly, this is a one-line addition back to the Brewfile and a short script in Phase 3.

---

### 4.14 Background Process Supervision → **Pitchfork**

**Decision:** Add Pitchfork as the daemon/process-supervision layer beneath tmux/tmuxp (Section 14).

**Why:**
- Directory-aware process supervisor from jdx (mise's own author) — services auto-start when you `cd` into a project and auto-stop when you leave, via a shell hook [^21]
- Ready checks (`ready_http`, `ready_output`) — know when a service is *actually* ready, not just started, which neither tmuxp nor a raw shell background job can express [^21]
- Restart-on-failure with configurable retry — if `mise run dev` crashes at 2am, Pitchfork restarts it; nothing in the current tmuxp-only design does this [^21]
- Cron scheduling for periodic tasks, without needing `launchd` plists hand-written per task
- Native, documented mise integration: the mise-recommended pattern wraps daemon commands as `mise x --` or calls `mise run <task>` directly, matching the layering rule already established in Section 4.3 exactly — no new exception required [^22]
- **Built-in MCP server** — `pitchfork mcp` exposes `pitchfork_status`, `pitchfork_start`, `pitchfork_stop`, `pitchfork_restart`, `pitchfork_logs` as tools Claude Code, Cursor, or any MCP-compatible assistant can call directly [^23]. This means an agent working in a project can start/stop/inspect real dev services by name rather than guessing at shell state — directly relevant to the agentic-workflow considerations in Section 4.15.

**What it does NOT replace:**
- tmuxp still owns the interactive layout (editor pane, ad-hoc shell, anything you want to see and type into)
- mise still owns 100% of what a task actually does — Pitchfork only ever calls `mise run <task>`, never a project tool directly, per the standing rule in Section 4.3

**The division of labor:**

| Need | Tool |
|---|---|
| I want a full multi-pane layout right now, interactively | tmuxp |
| I want this service running whenever I'm in this project, restarted if it crashes, whether or not a terminal is open | Pitchfork |
| I want to know what a task actually does | mise (`.mise.toml`) — both of the above only ever call into this |

**Install:**
```bash
mise use -g pitchfork   # installed via mise itself — no new package-manager surface
```

**Example (`pitchfork.toml` in a project root):**
```toml
[daemons.db]
run = "mise run db:start"
auto = ["start", "stop"]        # follows you in/out of the project directory
ready_output = "ready to accept connections"

[daemons.api]
run = "mise run api:dev"
auto = ["start", "stop"]
ready_http = "http://localhost:3000/health"
retry = 3

[daemons.worker]
run = "mise run worker:dev"
auto = ["start", "stop"]
```

Corresponding `.mise.toml` tasks (`db:start`, `api:dev`, `worker:dev`) live exactly where every other task in this document lives — Pitchfork never defines *what* these commands do, only *when* they run and *how* they're supervised.

---

### 4.15 Agent Session Persistence → **Entire CLI (recommended follow-up, not a bootstrap requirement)**

**Decision, updated:** Entire CLI is no longer part of the bootstrap-required Brewfile. It moved from "install by default, activate per-project" to a **recommended follow-up tool** — something to add later, if/when session persistence becomes something you actually want, rather than something the bootstrap script installs and taps for on day one. The `entireio/tap` and `cask "entire"` lines have been removed from the Brewfile entirely. This is a scope reduction requested directly, not a technical finding — the tool itself is unchanged from the evaluation below, it's just no longer treated as a hard requirement for a working machine.

**What it is, concretely:** Entire CLI ("Checkpoints") is a real, shipping, MIT-licensed tool from Thomas Dohmke's (ex-GitHub CEO) company Entire — not the same thing as entire.io's forward-looking company vision, which describes a future platform this CLI is only the first piece of. The CLI itself is mature: 4.3k GitHub stars, 332 forks, 57 releases, v0.6.1 as of May 2026 [^24]. It hooks into `git commit` to capture the full agent session (prompts, tool calls, files touched) that produced each commit, storing that metadata on a separate `entire/checkpoints/v1` branch — your actual commit history and diffs stay untouched [^24].

**Why this fits the stack's philosophy, not just its architecture:**
- **It's the missing counterpart to Section 14's session persistence.** tmux persists your terminal session. Nothing in this document persists the *agent's reasoning* behind the commits made during that session — close a Claude Code session and the "why" behind the diff is gone unless you remember the conversation. Entire's checkpoint model fills exactly that gap, and stores it in git, which composes with everything else here rather than adding a new storage system.
- **`entire checkpoint rewind`** — non-destructive rewind to any point in an agent session without altering commit history
- **`entire session resume <branch>`** — pick up an agent session exactly where it left off, on any machine, because the session metadata travels with the branch — directly useful for a freelance/consulting workflow where you might step away from a client engagement and return to it later
- **Native hooks for Claude Code, Codex, Gemini, Cursor, OpenCode, and Copilot CLI** [^24] — not tied to a single agent, consistent with this document's own use of multiple tools (Claude Code, Cursor)
- **Layering-clean:** Entire only activates on the `git commit` boundary — it never calls project tools, never needs to route through `mise run`, and doesn't intersect the alias-vs-mise-task rule in Section 4.3 at all. It's orthogonal, not a new instance of the pattern.

**Why default OFF, prompted per-project — this is a deliberate security decision, not a hedge:**
Session data is written to `entire/checkpoints/v1` and **pushed to your git remote by default**. For solo personal projects, that's likely fine. For client/consulting repos — the primary use case for this specific machine — that means every prompt and agent tool call from your session becomes a permanent part of a client-owned repository unless explicitly configured otherwise. Two additional cautions from Entire's own documentation, taken at face value rather than assumed safe:
- Secret redaction before writing to the checkpoint branch is explicitly **best-effort**, not guaranteed [^24]
- If the repo is public, checkpoint branch contents are visible to anyone [^24]

None of this conflicts with the existing 1Password/`op inject` secrets architecture (Section 4.8) — no real secret should ever be in a shell prompt or file Entire would observe in the first place — but it's a second, independent reason (client confidentiality, not just secret leakage) to keep this opt-in rather than blanket-enabled.

**Implementation — the project-init prompt:**

This is not part of the machine-level bootstrap (`bootstrap.sh` / chezmoi). It belongs at the point where you start a *new project*, since the decision is per-repo. Add a `mise` task or a short project-init script that prompts:

```bash
#!/bin/bash
# project-init.sh — run once per new project, not part of machine bootstrap
read -p "Enable Entire agent session persistence for this project? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  entire enable
  # Default to NOT auto-pushing session data — opt in explicitly per project if desired
  entire configure --telemetry=false
  echo '{"strategy_options": {"push_sessions": false}}' > .entire/settings.local.json
  echo "✓ Entire enabled. Session data stays local (push_sessions=false) until you opt in."
else
  echo "○ Entire skipped for this project."
fi
```

The default inside that `y` branch is **still conservative**: `push_sessions = false` means checkpoints are captured locally but not auto-pushed to the remote, even once enabled. Pushing session history to a shared/client remote is a separate, explicit opt-in (`entire configure --checkpoint-remote ...` or flipping `push_sessions` back to `true`), not something either the machine bootstrap or the project-init prompt turns on by default.

**Install (manual, run this yourself when you want it — not part of `bootstrap.sh`):**
```bash
brew tap entireio/tap
brew install --cask entire
```
See RUNBOOK.md "Recommended Follow-Up Tools" for the short version of this.

---

### 4.16 AI Coding Assistant Ecosystem → **Claude Code + Claude Desktop, first-class stack citizens**

**Decision:** Claude Code and Claude Desktop are explicit, installed members of this stack — not just referenced in passing as a comparison point to Cursor. This section was added specifically to close a gap: earlier drafts of this document mentioned Claude Code repeatedly (Section 4.7's competitive note, Bun's Anthropic acquisition, Pitchfork's MCP tooling, Entire's agent hooks) without ever actually giving it a stack entry of its own, despite this document being produced by Claude and the person using Claude Code, Claude Desktop, Claude in Chrome, Claude in Excel/PowerPoint, and this chat interface across their daily workflow.

**What's actually installed, and why each one:**

| Tool | Install method | Role in this stack |
|---|---|---|
| **Claude Code** (CLI) | `brew install --cask claude-code` | Terminal-native agent — lives inside Ghostty/tmux panes (Section 14), reads/edits the whole repo, runs commands with approval. The primary "does the work" tool for this stack. |
| **Claude Desktop** | `brew install --cask claude` | GUI app — separate cask from Claude Code (`claude`, not `claude-code`) [^26]. Hosts general-purpose chat, and its Code tab runs the same underlying Claude Code tool with a graphical interface for people who want that instead of the terminal [^26]. Also the standard host for user-level MCP server configuration. |
| **Claude in Chrome / Excel / PowerPoint** | Browser extension / Office add-ins, not Homebrew-installable | Mentioned for completeness — these are installed per-application (Chrome Web Store, Office add-in store), not part of a machine bootstrap script. No Brewfile entry; noted here so the document doesn't silently omit them. |
| **claude.ai/code** (web) | No install — browser-based | Same underlying Claude Code tool, web-hosted. Config (CLAUDE.md, settings, MCP servers) is shared across CLI, Desktop's Code tab, and web [^26]. |

**Homebrew cask specifics, verified against Anthropic's own docs:**
- `claude-code` cask tracks the **stable** channel — roughly a week behind, deliberately skips releases with major regressions [^26]
- `claude-code@latest` cask tracks the **latest** channel — new versions as soon as they ship, higher regression risk
- **Homebrew casks do not auto-update by default** — this is a real gap relative to Anthropic's native installer, which does auto-update in the background [^26]. Set `CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1` to have Claude Code run its own upgrade in the background when a new version is available, restart-prompting on success — this targets only the Claude Code package, not other Homebrew-managed software [^26]
- The `claude` cask (Desktop) and `claude-code` cask (CLI) are genuinely separate casks — installing one does not install the other [^27]

**Recommendation for this stack:** `claude-code` (stable channel, not `@latest`) for the CLI, with `CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1` set, given this document's general preference for stability over bleeding-edge (consistent with the Ghostty/mise/OrbStack channel decisions elsewhere in Section 4). Plus `claude` for Desktop.

**Layering note — Claude Code already respects this document's rules without needing new ones.** Claude Code operates by reading and editing files and running shell commands you approve — it doesn't have its own competing task-runner concept to reconcile with mise. When Claude Code runs a project command, the same rule from Section 4.3 applies exactly as it does to a human at the keyboard: it should be invoking `mise run <task>`, not calling `bun`/`pytest`/etc. directly, and a project's `CLAUDE.md` is the right place to state that convention explicitly so Claude Code (this tool, in any session) follows it automatically.

**Install (Brewfile):**
```ruby
cask "claude-code"     # CLI — stable channel; set CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1 in shell env
cask "claude"          # Desktop app — separate cask, both installed
```

---

### 4.17 Codebase Intelligence for Agents → **codebase-memory-mcp, adopt with explicit guardrails**

**Decision, recalibrated after a deeper audit:** Add `codebase-memory-mcp`, but not as a blanket "plug and play" default. It's a legitimate, well-evidenced tool for the specific job of structural code questions — and it has real, documented failure modes that matter for exactly the accuracy-sensitive cases raised when evaluating this. This section replaces the earlier, more casually confident "evaluated and recommended" framing with a more precise one: recommended for a specific class of query, with explicit rules for when to bypass it.

**What it is:** An open-source (MIT), single static binary (C) that parses a codebase with tree-sitter (158 languages) plus a custom "Hybrid LSP" type-resolution layer into a persistent SQLite-backed knowledge graph, queryable by an agent via 14 MCP tools (structural search, call-graph tracing, git-diff impact analysis, dead-code detection, Cypher-subset queries) [^28]. No LLM embedded — it's a structural backend; the agent (Claude Code) remains the reasoning layer and translates natural-language questions into graph queries [^28].

**Why the token-efficiency case is real, not just marketing:**
- Backed by a dated academic preprint — *Codebase-Memory: Tree-Sitter-Based Knowledge Graphs for LLM Code Exploration via MCP*, arXiv:2603.27277 (submitted March 28, 2026), five named authors with academic affiliations (Charité – Universitätsmedizin Berlin, Humboldt University, Freie Universität Berlin, University Hospital Heidelberg) [^29]
- Evaluated across 31 real-world repositories: **10x fewer tokens, 2.1x fewer tool calls** versus file-by-file grep/read exploration [^29]
- Runs 100% locally, zero telemetry by default, code never leaves the machine [^28]

**The accuracy tradeoff, stated precisely (not the README's framing):** The paper's own number is 83% answer quality **versus 92% for a plain file-exploration agent** [^29] — a real, disclosed 9-point accuracy cost for the token/speed win, not a strict improvement on every axis.

---

**Three concrete failure modes found in this audit — not hypothetical, filed and documented by users:**

1. **Silent partial-index drops (Issue #411, confirmed, fixed in a later release but worth knowing the failure class exists).** `index_repository(mode="moderate")` silently dropped an entire subtree — 46% of nodes, 60% of edges — from a real repository, with **zero warning or error**. Both the moderate call and a subsequent `full` call reported `status: "indexed"` identically; only comparing node/edge counts revealed the gap [^31]. This is precisely the failure mode that should worry someone weighing "can I trust this over direct exploration" — a confidently-reported success that was quietly incomplete.

2. **Stale reads from unflushed database state (Issue #277, Windows-reported, architecture affects all platforms).** Under certain session-termination patterns, the SQLite WAL (write-ahead log) accumulates new symbol writes that never checkpoint into the main database — queries return correct-looking but **stale** results for anything added since the last clean checkpoint, and this survives even a full `delete_project` + reindex cycle. Fixing it required manually killing orphaned processes and deleting cache files by hand [^32].

3. **A real SQL/argument injection vulnerability existed and was patched.** A recent release changelog credits a contributor with a "critical SQL injection and argument injection security fix" [^33] — meaning the query surface had a genuine injection flaw at some point in this project's history. It's fixed now, but it's evidence the attack surface (a tool that parses arbitrary code and accepts structured queries) is real, not theoretical, and this is exactly the kind of thing to keep watching in future release notes rather than assume is a closed chapter.

**None of these are disqualifying — mature software has bugs, and all three are either fixed or have documented workarounds — but they directly inform the "when do I bypass this" question below.**

---

**When to use it vs. when to bypass it and go direct — concrete guidance, not just "use judgment":**

| Situation | Recommendation |
|---|---|
| "What calls this function," "what's the blast radius of this diff," "find dead code," general architecture orientation | **Use it.** This is the tool's actual design target, the accuracy tradeoff is acceptable, and the token savings are large. |
| First real use of a freshly indexed project, or right after a large refactor | **Verify the index once before trusting it.** Given Issue #411, spot-check `get_architecture` or `list_projects` node/edge counts against what you'd expect from the repo size before relying on results for anything consequential. This costs one extra tool call and catches the exact failure mode that was documented. |
| A question where the exact right answer matters more than speed — security-sensitive code paths, a client deliverable, debugging a subtle bug, anything you'd double-check by hand anyway | **Bypass it — tell Claude Code to use Grep/Read directly**, or verify the graph's answer against a direct file read. The paper's own 83-vs-92 number is the quantified version of this instinct: for the ~9% of cases where the graph is wrong, you want to be the one deciding when that risk is acceptable, not have it silently applied everywhere. |
| Long-running session where files have changed significantly since last index | **Re-index explicitly before trusting results**, given the stale-WAL failure mode in Issue #277. `list_projects` shows `indexed_at` — treat a large gap between that timestamp and your last edit as a signal to reindex, not just a formality. |
| Client/consulting repos specifically (this machine's primary use case) | **Set `CBM_ALLOWED_ROOT`** (see below) before ever pointing this at a client codebase, and treat the first index of any new client repo as unverified until spot-checked. |

**How to actually make bypassing easy, mechanically:** The tool's own skill file states plainly that Claude Code defaults to its built-in Grep/Glob/Read tools unless explicitly told to prefer graph queries for structural questions — meaning the safe default is already "off unless invoked," not "always intercepting." The `PreToolUse` hook it installs is structurally non-blocking and never intercepts `Read` [^28], so a direct "read this file" or "grep for X" always falls through to Claude Code's normal tools regardless of whether the MCP server is installed. Practically: you don't need a special flag to bypass it — just ask for a direct file read or grep, which was never intermediated in the first place. The thing worth being deliberate about is the *opposite* direction — explicitly asking Claude Code to prefer the graph tools for structural questions, since that's opt-in, not opt-out.

**A real security control worth using on this machine specifically:** `CBM_ALLOWED_ROOT` restricts `index_repository` to paths within a given directory — a `repo_path` that resolves (after symlink/`..` resolution) outside that root is refused; unset, there's no restriction at all [^28]. Documented by the maintainers as "useful when the server may be driven by an untrusted caller" — directly relevant here, since Claude Code (an agent with some autonomy over which tools it calls and with what arguments) is exactly that kind of caller. Given this machine handles client work, setting this to a scoped projects directory is a low-cost, high-value guardrail:
```bash
export CBM_ALLOWED_ROOT="$HOME/code"   # or wherever client/personal projects live
```
Without this set, a prompt-injection scenario (malicious content in a file the agent reads, engineered to influence its next tool call) could in principle direct `index_repository` at a path outside the intended project — `CBM_ALLOWED_ROOT` closes that off entirely rather than relying on the agent's judgment alone.

**Security posture, verified independently rather than only asserted:**
- Every release binary is VirusTotal-scanned (0/72 detections on latest checked release), SLSA Level 3 attested, Sigstore-signed, and SHA-256 checksummed [^28]
- One independent review site reports an OpenSSF Scorecard of 5.8/10 [^30] — a moderate, not top-tier, score included here for completeness rather than only repeating the project's stronger self-reported signals
- The local graph-visualization UI variant (`--ui`) binds an HTTP server to `localhost:9749` — the project's own changelog notes it was hardened in v0.8.1 to bind only `127.0.0.1` with strict HTTP/1.1 parsing and a hard request limit [^28][^33], meaning earlier versions may have had a looser binding; use the standard (non-UI) binary unless the visualization is actively wanted, since it's one fewer local network surface to reason about
- The install script writes to agent configuration files and installs a pre-tool hook — exactly what it says it does. Given the injection-fix history above, reviewing the install script once (`curl ... | bash` after inspecting, rather than blind-piping) is a reasonable one-time step on a machine with client-repo access, consistent with this document's general caution elsewhere (Entire CLI, Section 4.15)

**Install — corrected after a real first-run failure.** An earlier version of this document (and the Brewfile) listed `brew "codebase-memory-mcp"` as installable via Homebrew. That was never true — checked directly against the project's own GitHub issue tracker: issue #491, "brew installation for macos?", filed June 2026 by a user asking the maintainers for exactly this support, unresolved [^45]. There has never been a Homebrew formula for this tool, on any platform. This surfaced as a real `brew bundle` failure ("No available formula with the name 'codebase-memory-mcp'") during actual bootstrap execution, not a desk review.

**The fix — now fully automated, not a manual step.** Installation is handled by `.chezmoiscripts/run_onchange_after_60-install-codebase-memory-mcp.sh.tmpl`, which runs the project's own install script as part of the normal `chezmoi apply` bootstrap flow, after secrets resolution (script 50) so `CBM_ALLOWED_ROOT` is already set:
```bash
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash
```
This is the correct, only supported install path — not a workaround. No `brew "codebase-memory-mcp"` line exists anywhere in the Brewfile.

Per-project *activation* remains manual and per-repo, unchanged from the original design — say "index this project" inside Claude Code per-repo. Given the guidance above, **auto-index stays off** (`auto_index` defaults to off) rather than being turned on — an explicit "index this project" per repo is a natural moment to also decide whether `CBM_ALLOWED_ROOT` is set correctly for that context, which auto-indexing on session start would skip.

---

### 4.18 Claude Code Sandboxing → **Enable the built-in sandbox by default; devcontainer for unattended work**

**Decision:** Turn on Claude Code's native, built-in sandbox as a default. This is the single highest-leverage security addition available to this stack — it's free, first-party, requires no new dependency, and directly closes a risk that's been implicit since Section 4.17: `codebase-memory-mcp`, Entire CLI's git hooks, and any future MCP server all currently run with the same unrestricted host access as Claude Code itself.

**What Claude Code actually ships, verified against Anthropic's own docs [^34]:**

| Approach | What it isolates | Requires Docker | Setup |
|---|---|---|---|
| **Sandboxed Bash tool** | Bash commands and child processes only | No | `/sandbox` — minimal on macOS |
| **Sandbox runtime** | The whole process — file tools, MCP servers, hooks | No | Low — `npx @anthropic-ai/sandbox-runtime claude` |
| **Dev container** | Full development environment | Yes | Medium — Anthropic publishes a starting template |

**The distinction that matters for this stack specifically:** the sandboxed Bash tool (enabled with `/sandbox`) only restricts Bash — it does **not** restrict MCP servers or hooks. Since `codebase-memory-mcp` and Entire CLI both operate as MCP servers/hooks rather than Bash commands, `/sandbox` alone doesn't cover them. The **sandbox runtime** is the one that does — it wraps the entire Claude Code process (file tools, MCP servers, hooks included) in the same OS-level isolation (Seatbelt on macOS) [^34].

**Recommended default for this machine:**
```bash
/sandbox   # enable per-session, minimal friction, covers Bash — do this by default
```
For any session where `codebase-memory-mcp`, Entire, or another MCP server matters and you want them inside the boundary too:
```bash
npx @anthropic-ai/sandbox-runtime claude
```

**For unattended work (`--dangerously-skip-permissions` or auto mode) — devcontainer is the documented, non-optional path.** Anthropic's own guidance is direct: `--dangerously-skip-permissions` removes per-action review, so an isolation boundary is the only thing limiting what Claude can do — always run it inside a container, a VM, or the sandbox runtime [^34]. This stack currently has no devcontainer template; that's the gap.

**Devcontainer setup, when needed:** Anthropic publishes an example dev container with a default-deny iptables firewall as a starting point [^34]. Copy it into a project's `.devcontainer/` directory, adjust the firewall allowlist and base image, and it directly supports running with `--dangerously-skip-permissions` since unapproved network egress is blocked at the container boundary regardless of what Claude Code does inside it.

**What this does not solve — stated plainly per Anthropic's own warning:** sandbox isolation reduces the impact of a breach, it does not eliminate risk. Any approach allowing network egress can still leak data the agent can read; any approach mounting the project directory writable can still modify that code. Isolation also does not change what's sent to the model — prompts and files Claude reads are transmitted to the API with or without a sandbox [^34]. This is a containment control, not a privacy control.

---

### 4.19 Local LLM Inference → **Ollama**

**Decision:** Add Ollama for local model inference — a genuine capability gap, distinct from Claude Code, that this stack has had zero coverage of.

**Why this matters for this machine specifically:**
- **Free experimentation** — testing prompts, embeddings, or smaller-model workflows without spending API tokens
- **Offline capability** — works without a network connection, genuinely useful for a laptop
- **Client data policy compliance** — if a client's confidentiality terms prohibit sending their code or data to any third-party API, a local model is the only compliant option; directly relevant given this machine's consulting use case
- **Complements `codebase-memory-mcp`'s existing local embedding model** (Section 4.17's `semantic_query` tool already runs a bundled local embedding model) — Ollama is the natural local counterpart for generative (not just embedding) workloads

**Why Ollama over LM Studio or raw llama.cpp:** Ollama automatically detects Apple Silicon and uses Metal acceleration with zero configuration — no flags, no driver setup [^35]. It exposes an OpenAI-compatible API on `localhost:11434`, so any tool already expecting that interface (including this stack's own future LLM-calling code) drops in with just a URL change. It's the standard recommendation across independent sources for developers who want terminal-based workflows and API integration, versus LM Studio which targets non-technical/visual use [^35][^36]. As of Ollama 0.19+, it uses Apple's MLX backend under the hood on Apple Silicon, closing most of the performance gap that used to favor MLX-direct usage [^36].

**Install:**
```ruby
brew "ollama"
```
```bash
brew services start ollama   # runs as a background service, consistent with existing brew services usage
ollama pull qwen3:8b          # a solid general-purpose default for a 16GB+ machine
```

**Not machine-bootstrap-critical, but zero-cost to include.** This is genuinely optional in the sense that day-to-day Claude Code/Cursor work doesn't need it — but given it's a single Homebrew formula with no downstream configuration required elsewhere in the stack, there's no reason to leave it out.

---

### 4.20 LLM Observability & Cost Tracking → **Langfuse (project-scoped, not machine-bootstrap)**

**Decision:** Document Langfuse as the answer *when and if* a project calls LLM APIs directly as a feature (not when just using Claude Code as a coding tool) — not something to add to the Brewfile or bootstrap now.

**Why this is a real but narrowly-scoped gap:** Using Claude Code and Cursor to write code gives no visibility problem — Anthropic and Cursor's own billing handles that. The gap is different: if any personal or client project *builds a feature* that calls an LLM API directly (a chatbot, a summarization endpoint, an agent), this stack currently has no tooling for tracking that spend, tracing multi-step calls, or catching quality regressions. That's a real gap, but it's project-scoped — exactly like a database choice, it depends on what's being built, not something the machine needs pre-configured.

**Why Langfuse over the alternatives, with a relevant timing note:** Two LLM observability tools were acquired in early 2026 with different outcomes for their roadmaps. **Helicone was acquired by Mintlify in March 2026 and moved to maintenance mode** — the open-source proxy still ships security and bug fixes, but active feature development has stopped [^37]. **Langfuse was acquired by ClickHouse in January 2026 without a comparable roadmap freeze** [^37] — it remains the most commonly recommended starting point for solo developers, MIT-licensed at its core, self-hostable, with a generous free tier (50,000 units/month on the hosted Hobby tier) [^37][^38].

**When to actually reach for this:** The moment a project's `.mise.toml` includes a task that calls an LLM API directly (not through Claude Code/Cursor), that's the signal to add Langfuse — as a per-project dependency (`pip install langfuse` or the JS equivalent), following the same "vector DB, database, and other project-scoped choices live in `.mise.toml`, not the Brewfile" pattern already established in this document. No machine-level action needed until that moment arrives.

---

## 5. Homebrew Package List

**Install method decision:** Homebrew cask is the correct install path for everything listed here. Every cask either officially distributes through Homebrew, or the cask pulls from the vendor's own download URL and produces an identical result to downloading the DMG manually. App Store versions of developer tools are typically sandboxed and feature-limited — direct/cask installs are the preferred versions. See the installation audit in previous research for per-app verification.

**Upgrade note for OrbStack:** Use `brew upgrade --greedy orbstack` — OrbStack self-updates and Homebrew will skip it without `--greedy`.

**Xcode:** Installed via `mas`, not Homebrew. Apple distributes Xcode exclusively through the App Store and developer.apple.com. There is no Homebrew cask for Xcode.

**Entire CLI requires a third-party tap.** Unlike every other cask in this Brewfile, `entire` is not in Homebrew core — it ships from its own tap. The `brew bundle` script must run `brew tap entireio/tap` before `cask "entire"` will resolve. This is the only tap dependency in the entire stack; flagged explicitly since it's a deviation from every other line in this Brewfile.
```ruby
tap "entireio/tap"
```

### Formulae (CLI tools)
```ruby
# Bootstrap dependencies (installed before chezmoi runs)
brew "git"
brew "chezmoi"
brew "mas"
brew "1password-cli"         # op CLI for secrets

# GitHub
brew "gh"                    # GitHub CLI
brew "git-lfs"

# Shell experience
brew "starship"              # Prompt
brew "zsh-autosuggestions"
brew "fast-syntax-highlighting"
brew "zsh-completions"
brew "fzf"                   # Fuzzy finder
brew "zoxide"                # Smart cd

# Terminal multiplexing — session persistence + per-project layouts (see Section 14)
brew "tmux"                  # Session persistence — survives closed windows, crashes, SSH drops
brew "tmuxp"                 # Declarative per-project layouts — `tmuxp load <project>`
# NOTE: pitchfork is intentionally NOT installed via brew — it's a mise-managed tool.
# See Section 4.14. Installed via `mise use -g pitchfork` in the mise global config instead,
# consistent with mise owning all non-package-manager developer tooling.

# Modern CLI replacements
brew "bat"                   # Better cat (syntax highlighting)
brew "eza"                   # Better ls (exa successor, active fork)
brew "ripgrep"               # Better grep (rg)
brew "fd"                    # Better find
brew "delta"                 # Better git diff
brew "tldr"                  # Concise man pages
brew "jq"                    # JSON processing
brew "yq"                    # YAML processing
brew "tree"
brew "htop"
brew "wget"
brew "curl"

# Developer tools
brew "mise"                  # Version manager — owns ALL language runtimes: Node, Bun, Go, Rust, Python, Java, Terraform, kubectl
# NOTE: Do NOT add brew "bun", brew "go", brew "rust", or brew "python@X.Y" here.
# Every runtime is managed by mise (see ~/.config/mise/config.toml) — leaning into
# mise as the single source of truth for language versions, per project standard.
# If a Homebrew formula needs Python/etc as a build dependency, Homebrew vendors its
# own internal copy automatically — you do not need to install a system Python for this.
brew "pnpm"                  # Package manager for existing Node projects (not a runtime — Homebrew ownership is correct;
                              # mise config does not list pnpm)
brew "gcc"
brew "cmake"

# Cloud / infrastructure
brew "awscli"
brew "terraform"
brew "kubectl"
brew "helm"
brew "k9s"                   # Kubernetes TUI

# Agentic / AI coding tooling — see Section 4.17
brew "codebase-memory-mcp"   # Local code-intelligence MCP server for Claude Code — see Section
                              # 4.17. Binary install is machine-level; per-project activation
                              # is "index this project" said to Claude Code, same pattern as
                              # Entire CLI's per-project opt-in (Section 4.15).
brew "ollama"                # Local LLM inference — see Section 4.19. `brew services start ollama`
                              # to run as background service; OpenAI-compatible API on :11434.

# Utilities
brew "imagemagick"
brew "ffmpeg"
# NOTE: dockutil is intentionally excluded. Could not confirm clean compatibility
# with Tahoe's changed Dock/plist architecture (see Section 4.13). Dock layout is
# a manual setup step instead — see Section 12.
```

### Casks (GUI apps)
```ruby
# Terminal + editor
cask "ghostty"               # Terminal — Metal GPU, MIT, no account
cask "cursor"                # Code editor — VS Code fork, AI-native

# AI coding assistant ecosystem — see Section 4.16
cask "claude-code"           # Claude Code CLI — stable channel (not @latest); set
                              # CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1 in shell env since
                              # Homebrew casks don't auto-update by default
cask "claude"                # Claude Desktop — separate cask from claude-code; GUI app,
                              # hosts general chat + Code tab + user-level MCP config

# Containers
cask "orbstack"              # Docker replacement — 200MB RAM, full Docker API
# Note: Apple Container (apple/container v1.0) is on the watch list.
# Watch https://github.com/apple/container for Docker Compose support before switching.

# Secrets + auth
cask "1password"             # Password manager

# Productivity + launcher
cask "raycast"               # App launcher + window manager + clipboard history

# Development tools
cask "tableplus"             # Database GUI
cask "proxyman"              # HTTP proxy / API inspector (requires Full Disk Access)
cask "github"                # GitHub Desktop (optional — visual diffing and PR review)

# Browsers
cask "arc"                   # Primary browser
cask "google-chrome"         # Cross-browser testing
cask "firefox"               # Cross-browser testing

# Communication + project management
cask "linear"                 # Linear app
cask "slack"
cask "notion"

# System utilities
# Menu bar management: removed — native macOS Tahoe Menu Bar Controls sufficient,
# see Section 4.9
# cleanmymac removed per user request
# cask "logi-options-plus"   # Uncomment if using Logitech peripherals

# Agent session persistence — see Section 4.15
# Requires tap first: brew tap entireio/tap
# Installing the binary here is machine-level; ACTIVATION is per-project via
# `entire enable`, prompted at project-init time, default OFF. Installing the
# cask does not enable it anywhere — it just makes `entire` available on $PATH.
cask "entire"

# Fonts (Nerd Fonts for Ghostty + Starship icons)
cask "font-jetbrains-mono-nerd-font"
cask "font-fira-code-nerd-font"
```

### Mac App Store
```ruby
# Xcode is intentionally NOT here — see Section 4.12. `mas install` (which `brew bundle`
# uses) fails on fresh Apple IDs, and Xcode's size makes the App Store install path
# unreliable regardless. Install Xcode manually from developer.apple.com — see the
# runbook's Section 3 manual steps.
#
# Add other App Store apps here only if they're apps this Apple ID has acquired before —
# `mas install` will fail with "Redownload Unavailable" for anything genuinely new to
# this Apple Account on a fresh machine. Verify with `mas get <id>` first if unsure.
```

---

## 6. macOS Defaults — Tahoe 26 Verified

### 6.1 Audit Methodology

Every `defaults write` command in this section has been verified against macOS Tahoe 26 through:
- Cross-reference with macos-defaults.com (community-maintained reference)
- Cross-reference with Apple Community discussions dated post-September 2025
- Cross-reference with developer forum reports and Tahoe-era dotfile repositories

**Status key:** ✅ Confirmed working on Tahoe | ⚠️ Works with caveat | ❌ Broken/removed | 🔲 Unverified

macos-defaults.com tests commands through Sequoia but not yet Tahoe for most entries. Tahoe confirmation comes from the community, not Apple documentation — which is why every command here carries an inline note on its source.

---

### 6.2 Confirmed Commands by Domain

#### Dock

| Command | Status | Notes |
|---|---|---|
| `defaults write com.apple.dock "tilesize" -int 48` | ✅ | Working in 26.1+. Avoid tilesize < 28 — rendering bug in 26.0, fixed in 26.1 |
| `defaults write com.apple.dock "autohide" -bool true` | ⚠️ | Key works. Set to `true` (not false). autohide=false had a race condition in 26.0/26.0.1 causing the Dock to randomly disappear after screensaver. Fixed in 26.1 but `true` is more stable on Tahoe. |
| `defaults write com.apple.dock "autohide-delay" -float 0` | ✅ | Working |
| `defaults write com.apple.dock "autohide-time-modifier" -float 0.3` | ✅ | Working |
| `defaults write com.apple.dock "show-recents" -bool false` | ✅ | Working |
| `defaults write com.apple.dock "launchanim" -bool false` | ✅ | Working |
| `defaults write com.apple.dock "mineffect" -string "scale"` | ✅ | Working |
| `defaults write com.apple.dock "minimize-to-application" -bool true` | ✅ | Working |
| `defaults write com.apple.dock "orientation" -string "bottom"` | ✅ | Working |
| `defaults write com.apple.dock "show-process-indicators" -bool true` | ✅ | Working |
| `defaults write com.apple.dock "magnification" -bool false` | ✅ | Working |
| `killall Dock` | ✅ | Required after any dock write |

#### Finder

| Command | Status | Notes |
|---|---|---|
| `defaults write com.apple.finder "AppleShowAllFiles" -bool true` | ✅ | Community-verified post-Tahoe |
| `defaults write NSGlobalDomain "AppleShowAllExtensions" -bool true` | ✅ | Working |
| `defaults write com.apple.finder "ShowPathbar" -bool true` | ✅ | Confirmed via mac.install.guide 2026 |
| `defaults write com.apple.finder "ShowStatusBar" -bool true` | ✅ | Confirmed via mac.install.guide 2026 |
| `defaults write com.apple.finder "FXPreferredViewStyle" -string "Nlsv"` | ✅ | Working |
| `defaults write com.apple.finder "_FXSortFoldersFirst" -bool true` | ✅ | Note the underscore prefix |
| `defaults write com.apple.finder "FXDefaultSearchScope" -string "SCcf"` | ✅ | Working |
| `defaults write com.apple.finder "FXEnableExtensionChangeWarning" -bool false` | ✅ | Working |
| `defaults write com.apple.finder "NewWindowTarget" -string "PfLo"` | ✅ | Working |
| `defaults write com.apple.finder "NewWindowTargetPath" -string "file://${HOME}/"` | ✅ | Working |
| `defaults write com.apple.finder "_FXEnableColumnAutoSizing" -bool true` | ✅ | Referenced directly in Tahoe Finder bug community thread as working |
| `chflags nohidden ~/Library` | ✅ | Still works in Tahoe |
| `sudo chflags nohidden /Volumes` | ✅ | Still works |
| `killall Finder` | ✅ | Required after any Finder write |

#### Keyboard
*KeyRepeat and InitialKeyRepeat require full logout/login to take effect — not just a process restart.*

| Command | Status | Notes |
|---|---|---|
| `defaults write NSGlobalDomain "KeyRepeat" -int 1` | ✅ | Confirmed post-Tahoe Dec 2025/Jan 2026. 1 = 15ms (fastest). Default = 2 (30ms). |
| `defaults write NSGlobalDomain "InitialKeyRepeat" -int 14` | ✅ | 14 = 210ms delay before repeat starts. Do not set below 10 — causes unintended repeats on some hardware. |
| `defaults write NSGlobalDomain "ApplePressAndHoldEnabled" -bool false` | ✅ | Disables accent picker, enables key repeat in editors |
| `defaults write NSGlobalDomain "NSAutomaticQuoteSubstitutionEnabled" -bool false` | ✅ | Working |
| `defaults write NSGlobalDomain "NSAutomaticDashSubstitutionEnabled" -bool false` | ✅ | Working |
| `defaults write NSGlobalDomain "NSAutomaticSpellingCorrectionEnabled" -bool false` | ✅ | Working |
| `defaults write NSGlobalDomain "NSAutomaticCapitalizationEnabled" -bool false` | ✅ | Working |
| `defaults write NSGlobalDomain "NSAutomaticPeriodSubstitutionEnabled" -bool false` | ✅ | Working |

#### Trackpad
*Three-finger drag requires full logout/login to take effect.*

| Command | Status | Notes |
|---|---|---|
| `defaults write com.apple.AppleMultitouchTrackpad "Clicking" -bool true` | ✅ | All three tap-to-click writes are required |
| `defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad "Clicking" -bool true` | ✅ | Required for Bluetooth Magic Trackpad |
| `defaults -currentHost write NSGlobalDomain "com.apple.mouse.tapBehavior" -int 1` | ✅ | Third required write for tap-to-click to fully register |
| `defaults write NSGlobalDomain "com.apple.mouse.tapBehavior" -int 1` | ✅ | Fourth write — belt-and-suspenders |
| `defaults write NSGlobalDomain "com.apple.trackpad.scaling" -float 2.5` | ✅ | Fast but not max. Range 0–3. |
| `defaults write com.apple.AppleMultitouchTrackpad "TrackpadThreeFingerDrag" -bool true` | ✅ | Requires logout |
| `defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad "TrackpadThreeFingerDrag" -bool true` | ✅ | Also required for BT Magic Trackpad |

**Do not set pointer acceleration off.** In Tahoe 26.0, some users with Mighty Mouse disabled pointer acceleration to fix drag-and-drop failures. This was a 26.0 bug (not universal) and was fixed in subsequent updates. Do not set `com.apple.mouse.linear` — it's a workaround, not a preference.

#### Screenshots

| Command | Status | Notes |
|---|---|---|
| `defaults write com.apple.screencapture "type" -string "jpg"` | ✅ | Confirmed on Tahoe 26.0.1. JPG = smaller files, no Tahoe issues. PDF format has a known Tahoe bug when floating thumbnail is enabled. |
| `defaults write com.apple.screencapture "location" -string "${HOME}/Desktop"` | ✅ | Working. Desktop confirmed as the setting — screenshots are immediately visible and referenceable. |
| `defaults write com.apple.screencapture "disable-shadow" -bool true` | ✅ | Working |
| `defaults write com.apple.screencapture "show-thumbnail" -bool false` | ✅ | Working — also resolves the PDF format bug as a side effect |

#### Global UI / Dialogs

| Command | Status | Notes |
|---|---|---|
| `defaults write NSGlobalDomain "NSNavPanelExpandedStateForSaveMode" -bool true` | ✅ | Working — referenced in Tahoe-era dotfile setups |
| `defaults write NSGlobalDomain "NSNavPanelExpandedStateForSaveMode2" -bool true` | ✅ | Working |
| `defaults write NSGlobalDomain "PMPrintingExpandedStateForPrint" -bool true` | ✅ | Working |
| `defaults write NSGlobalDomain "PMPrintingExpandedStateForPrint2" -bool true` | ✅ | Working |
| `defaults write com.apple.LaunchServices "LSQuarantine" -bool false` | ✅ | Disables "app downloaded from internet" dialog. Confirmed working — listed in macos-defaults.com misc section. |
| `defaults write NSGlobalDomain "AppleShowScrollBars" -string "Always"` | ✅ | Working |

#### Mission Control

| Command | Status | Notes |
|---|---|---|
| `defaults write com.apple.dock "mru-spaces" -bool false` | ✅ | Prevents auto-rearranging Spaces. Requires logout. |
| `defaults write com.apple.spaces "spans-displays" -bool false` | ✅ | Separate Spaces per display. Requires logout. |

#### Safari (Developer Mode)

| Command | Status | Notes |
|---|---|---|
| `defaults write com.apple.Safari "IncludeDevelopMenu" -bool true` | ✅ | Working |
| `defaults write com.apple.Safari "WebKitDeveloperExtrasEnabledPreferenceKey" -bool true` | ✅ | Working |
| `defaults write NSGlobalDomain "WebKitDeveloperExtras" -bool true` | ✅ | Working |

#### Developer Tools (Xcode / TextEdit / Time Machine)

| Command | Status | Notes |
|---|---|---|
| `defaults write com.apple.dt.Xcode "ShowBuildOperationDuration" -bool true` | ✅ | Shows build time in toolbar |
| `defaults write com.apple.TextEdit "RichText" -int 0` | ✅ | Plain text default |
| `defaults write com.apple.TextEdit "SmartQuotes" -bool false` | ✅ | Working |
| `defaults write com.apple.TimeMachine "DoNotOfferNewDisksForBackup" -bool true` | ✅ | Working |

#### Spotlight Exclusions for Developer Folders
Using `.metadata_never_index` files instead of `mdutil -i off` — more reliable on Tahoe without requiring sudo on specific paths.
```bash
mkdir -p ~/Developer && touch ~/Developer/.metadata_never_index
mkdir -p ~/code && touch ~/code/.metadata_never_index
```

#### Global Git Config
```bash
git config --global core.excludesfile ~/.gitignore_global
git config --global pull.rebase false
git config --global init.defaultBranch main
echo ".DS_Store"  >> ~/.gitignore_global
echo "*.orig"     >> ~/.gitignore_global
echo ".DS_Store?" >> ~/.gitignore_global
```

---

### 6.3 Explicitly Excluded Commands

Commands that were in earlier drafts of this document but have been removed after Tahoe verification:

| Command | Reason Excluded |
|---|---|
| Any `launchpad-*` defaults keys | Launchpad permanently removed in Tahoe — replaced by Apps |
| `defaults write com.apple.dock "springboard-*"` | Gone with Launchpad |
| `defaults write com.apple.dock "static-only" -bool true` | No longer meaningful without Launchpad |
| `defaults write com.apple.controlcenter Bluetooth -int 18` | Control Center domain unreliable on Tahoe's Liquid Glass redesign |
| `defaults write com.apple.controlcenter Sound -int 18` | Same |
| `defaults write com.apple.controlcenter BatteryShowPercentage -bool true` | Same |
| `defaults write com.apple.finder "DisableAllAnimations" -bool true` | Unknown interaction with Liquid Glass animation system |
| `defaults write NSGlobalDomain "NSWindowResizeTime" -float 0.001` | Unverified for Tahoe Liquid Glass; could conflict |
| `security find-generic-password` | Hangs indefinitely on Tahoe 26.x (SecurityAgent regression — confirmed bug) |
| `defaults write com.apple.screencapture type pdf` | PDF format buggy in Tahoe when floating thumbnail enabled; using JPG |
| `sudo mdutil -i off /path` | Replaced by `.metadata_never_index` files — more reliable on Tahoe |
| `defaults write NSGlobalDomain "com.apple.springing.enabled" -bool true` | Spring-loading for directories. Listed on macos-defaults.com as tested through Sequoia only. Unverified for Tahoe Liquid Glass. Dropped rather than risking unknown interaction. |

---

### 6.4 Commands Requiring Manual Setup

These cannot be reliably automated on Tahoe. The script outputs clear instructions.

| Setting | Why Manual |
|---|---|
| Control Center layout | `com.apple.controlcenter` domain keys changed behavior with Liquid Glass redesign |
| Battery percentage in menu bar | Affected by same Tahoe redesign |
| Night Shift schedule | No reliable `defaults write` key — too display/hardware-specific |
| Display arrangement (multi-monitor) | Machine-specific, can't be scripted without knowing display topology |
| Menu bar icon order | Icon positions managed by the running system; changes mid-session don't persist reliably via defaults |

---

## 7. macOS Tahoe 26 — What Changed

Current stable: **macOS 26.5.2** (June 29, 2026). You are running this today.

**Key OS changes that affected our decisions:**

**Launchpad removed.** Replaced by "Apps" — an App Library-style grid accessible via Spotlight (⌘+Space → ⌘+1) or a Dock folder. The Dock now has an Apps button by default. All `launchpad-*` defaults keys are dead.

**Liquid Glass redesign.** Biggest macOS UI change since Big Sur in 2020. Dock, sidebars, toolbars, and menu bar are translucent. This made the `com.apple.controlcenter` defaults domain unreliable — Liquid Glass introduced new internal animation and rendering systems that broke keys that worked in Sequoia.

**Terminal.app redesigned.** Now supports 24-bit color and Powerline fonts natively. We're using Ghostty — this doesn't affect our stack but is worth knowing.

**Dock auto-hide race condition (26.0/26.0.1).** After waking from screensaver or sleep, the Dock would randomly enable auto-hide even when the setting was off. Fixed in 26.1. Workaround was `killall Dock` or toggling the setting. We set `autohide=true` in our script — more stable than `false` on Tahoe.

**Finder bugs in 26.0–26.2.** Drag-and-drop failures, context menu reduction, sidebar disappearing, column resize broken. All resolved by 26.3 which specifically targeted Liquid Glass Finder fixes.

**Bartender 5 broken.** Causes cursor glitches, UI instability, menu bar emptying. Bartender 6 exists but has had issues too. Community has moved to Ice.

**macOS Keychain CLI (`security`) broken.** `security find-generic-password` hangs indefinitely on Tahoe due to a SecurityAgent session handling regression. All our secrets go through `op` CLI — this bug doesn't affect us, but nothing in the script should ever use `security`.

**mas now requires sudo.** Following CVE-2025-43411 fix, all `mas install` and `mas upgrade` operations require root.

**OS now stable.** As of 26.5.2, Tahoe is considerably more stable than launch. The early-adopter bugs described above are resolved. A fresh setup on 26.5.2 today is a good experience.

---

## 8. macOS Golden Gate 27 — Forward-Looking Audit

**Status:** Developer Beta 3 available (July 6, 2026). Public beta expected July. Stable release expected September 2026.

**Apple's positioning:** Snow Leopard-style refinement release. No major UI redesign. Focus on stability, performance, and completing the Liquid Glass design with better controls.

---

### What Golden Gate Means for Our Stack

**Apple Silicon only — no impact on us.** macOS 27 drops all Intel Mac support. Our entire stack was designed for Apple Silicon from day one. This just confirms our decision.

**Rosetta 2 wind-down — no impact on us.** Golden Gate is the last version with full Rosetta 2. macOS 26.4+ warns users when they launch Intel apps. Everything in our Brewfile ships native arm64. The Rosetta sunset doesn't affect a single package in our setup.

**Liquid Glass slider added.** Users can now control Liquid Glass opacity/translucency in System Settings. This may stabilize the `com.apple.controlcenter` domain that was unreliable in Tahoe — worth re-auditing when Golden Gate ships.

**Window border shapes unified.** Golden Gate reverts the per-app window border variation from Tahoe. More consistent UI = fewer surprises in defaults behavior.

**Spotlight loses menu bar icon in beta 3.** Siri AI takes over as the primary system assistant. `⌘+Space` still works but opens Siri AI. Monitor whether this affects Raycast's integration with Spotlight.

**AFP removed.** Apple Filing Protocol removed. Time Machine to AirPort Time Capsule no longer works. Not in our stack.

---

### Apple Container — The Interesting Golden Gate Story

Apple's own open-source Linux container tool (`apple/container`) hit **v1.0 stable on June 9, 2026** — the day after WWDC. It is:
- Written in Swift, Apache 2.0 licensed
- Apple Silicon + macOS 26 (Tahoe) required
- Fully OCI-compatible — Docker images from Docker Hub work unchanged
- One lightweight VM per container (stronger isolation than Docker's shared-kernel model)
- Free, no subscription

**Why it's not our primary tool yet:**
- No Docker Compose support — the most active GitHub issue, no timeline from Apple
- Different CLI surface — `container run` not `docker run`; existing `docker` muscle memory doesn't transfer
- Small-file I/O slower than OrbStack (npm/node_modules penalty)
- No GUI
- Community tooling (Compose bridges, GUI clients) is immature

**Why OrbStack stays:**
OrbStack has Docker Compose, the `docker` CLI, a polished GUI, and years of production battle-testing. It runs circles around Docker Desktop on every metric and still outperforms Apple Container on day-to-day developer workflows.

**What to watch for:** When Apple Container gets native Docker Compose support, reassess. That's the one gap that would make it viable as a replacement. Track: `github.com/apple/container` issues.

---

### Golden Gate Preparation Checklist (for September 2026)

When Golden Gate ships, the following should be done before running bootstrap on a new machine:

- Update the macOS version check in `bootstrap.sh` to accept `27` as a valid version
- Re-audit `defaults write` commands — particularly `com.apple.controlcenter` domain, which may stabilize with the Liquid Glass slider
- Check whether any Brewfile casks have Golden Gate-specific issues (expect most to be fine; watch Proxyman and any deep-system-access tools)
- Evaluate Apple Container for Docker Compose support — if it landed, draft a migration plan for OrbStack → Apple Container
- No Rosetta-related changes needed — nothing in our stack uses it

---

## 9. chezmoi Architecture & Script Execution Order

### Why chezmoi Orchestrates Everything

The bootstrap flow has chezmoi as the central orchestrator, not just a dotfiles manager. This is because chezmoi's `run_onchange_after_` scripts:
- Run **after** all managed files are written to disk (critical — Brewfile must exist before `brew bundle` runs)
- Run **only when their content changes** — adding a new Brew package doesn't re-run a 5-minute Xcode install
- Are **SHA256-tracked** — re-running `chezmoi apply` is always safe

### Script Naming Convention
```
run_onchange_after_{order}-{name}.sh.tmpl
```
- `run_onchange_` — re-runs only when file content changes
- `after_` — runs after all dotfiles are written
- Numeric prefix controls order: `10-`, `20-`, `30-`, `40-`
- `.tmpl` suffix means chezmoi processes Go templates inside

### Script Contents Summary

**`run_onchange_after_10-install-packages.sh.tmpl`**
```bash
#!/bin/bash
# Hash of Brewfile triggers re-run: {{ include "Brewfile" | sha256sum }}

# HOMEBREW_BUNDLE_NO_LOCK=1: The --no-lock CLI flag was silently removed in a
# Homebrew update and broke many bootstrap scripts overnight. Use the env var
# instead — it is more stable across Homebrew versions than CLI flags.
HOMEBREW_BUNDLE_NO_LOCK=1 brew bundle --file={{ .chezmoi.homeDir }}/Brewfile

# OrbStack requires --greedy because it self-updates and Homebrew tracks a
# lower version after auto-updates, causing plain `brew upgrade` to attempt
# a downgrade. --greedy forces it to check the latest remote version instead.
brew upgrade --greedy orbstack

brew bundle check                # Verify all packages installed; exits non-zero if anything is missing
```

**`run_onchange_after_20-install-mas.sh.tmpl`**
```bash
#!/bin/bash
# sudo keepalive started in bootstrap.sh before this runs
#
# Xcode is intentionally NOT installed here — see Section 4.12's correction.
# `mas install` (this script's only mechanism) fails on fresh Apple IDs with
# "Redownload Unavailable", and Xcode's size makes the App Store path unreliable
# even when it doesn't. Xcode is a manual step — see the runbook, Section 3.
#
# This script is a placeholder for any OTHER App Store apps that this Apple ID
# has genuinely acquired before. Uncomment and add as needed:
# sudo mas install <id>  # only apps already associated with this Apple Account

echo "→ mas step: no automated App Store installs configured (Xcode is manual — see runbook)"
```

**Xcode license acceptance (manual, run once after installing Xcode directly):**
```bash
sudo xcodebuild -license accept
```
This is no longer chained to a `mas install` step — run it yourself right after Xcode finishes installing from developer.apple.com, or just launch Xcode once and accept the GUI prompt.

**`run_onchange_after_30-macos-defaults.sh.tmpl`**
Full content in Section 6.2 above. Runs all Tahoe-verified `defaults write` commands, restarts Dock and Finder, and prints logout reminder.

**`run_onchange_after_40-mise-install.sh.tmpl`**
```bash
#!/bin/bash
# Hash of mise config triggers re-run: {{ include ".config/mise/config.toml" | sha256sum }}
mise install
mise doctor
```

**`run_onchange_after_50-resolve-secrets.sh.tmpl`**
```bash
#!/bin/bash
# Hash of the global secrets template triggers re-run:
# {{ include "dot_config/secrets/dot_env.global.tpl" | sha256sum }}
# Requires: 1Password sign-in completed in preflight (Section 3)

mkdir -p ~/.config/secrets
TEMPLATE_PATH="{{ .chezmoi.homeDir }}/.config/secrets/.env.global.tpl"
if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "ERROR: Expected secrets template not found at $TEMPLATE_PATH — run"
  echo "  'chezmoi apply -v' and check its output before re-running this script."
  exit 1
fi
op inject -i "$TEMPLATE_PATH" -o ~/.config/secrets/.env.global
chmod 600 ~/.config/secrets/.env.global   # readable only by the current user

echo "✓ Global secrets resolved. Per-project secrets (.env.local) are resolved"
echo "  on-demand per project — see Section 4.8 — not part of this global bootstrap step."
```
This must run **after** mise is installed and activated (script 40), since it's the last piece needed before a shell can fully load `[env] _.file` on next prompt. It must also run **after** 1Password sign-in from the preflight gate — if that pause was skipped, `op inject` fails loudly with a clear auth error rather than hanging (see Section 7's note on `security` CLI hangs — `op` does not share that failure mode).

**A real path bug was found and fixed here (see Section 15, Pass 17).** chezmoi's `dot_` attribute is a literal transformation — `dot_foo` becomes `.foo`, the whole leading token gets a dot prepended, not just part of it. The source file `dot_config/secrets/dot_env.global.tpl` therefore becomes `~/.config/secrets/.env.global.tpl` (**with** a leading dot) when chezmoi applies it — not `env.global.tpl` as an earlier version of this script assumed. That wrong assumption caused a real `no such file or directory` failure the first time this script actually ran, since `op inject` was pointed at a path that never existed. The explicit `TEMPLATE_PATH` variable and existence check shown above were added specifically so a future recurrence of this class of bug fails with a clear, diagnosable message rather than a bare error from `op inject` itself.

**`run_onchange_after_60-install-codebase-memory-mcp.sh.tmpl`**
```bash
#!/bin/bash
# codebase-memory-mcp has no Homebrew formula — confirmed via the project's own open
# GitHub issue (DeusData/codebase-memory-mcp #491, unresolved). Installed via the
# project's own script instead. See Section 4.17.
set -euo pipefail

if command -v codebase-memory-mcp &> /dev/null; then
  echo "✓ codebase-memory-mcp already installed, skipping."
else
  curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash
fi
```
Runs after script 50 (secrets) so `CBM_ALLOWED_ROOT` — set in the mise global config, resolved via the secrets/mise pipeline — is already in place before this tool is ever invoked. Uses chezmoi's default `run_onchange_` behavior (hashing the script's own content, not an external include) since there's no external file this script needs to react to — see chezmoi's own docs: *"run_onchange_ scripts are only executed if their content has changed since the last time they were run successfully."* This was verified directly rather than assumed, given two earlier assumptions about chezmoi/Homebrew behavior in this same session turned out to be wrong.

### Guardrail for adding future chezmoi scripts

Before adding a new `run_onchange_after_` script, check every command inside it against the alias-vs-mise-task rule in Section 4.3: **any command whose behavior depends on a specific project's toolchain or env vars should be a mise task in that project's `.mise.toml`, invoked via `mise run`, not called directly from a chezmoi script.** chezmoi scripts operate at the machine level (installing tools, setting system config) — they should never reach into a specific project and assume its dependencies are already resolved. The six scripts above (10/20/30/40/50/60) all pass this check: none of them invoke a project-specific command bypassing mise. This check caught a real bug during this project's own tmuxp design (see Section 14) and should be applied to every new script going forward, including ones written by a future Claude session.

### `run_once_` vs `run_onchange_` decision

We use `run_onchange_` for everything. The distinction: `run_once_` only ever runs once per content hash — so if you change a setting back to a previous value, chezmoi won't re-apply it because it already ran a script with those exact contents before. `run_onchange_` re-runs whenever the file content changes, which is correct for macOS defaults (you want settings reapplied when you change them) and for Homebrew (you want packages installed when the Brewfile changes).

---

## 10. File Structure Reference

```
~
├── .config/
│   ├── ghostty/
│   │   └── config               ← terminal settings (theme, font, keybinds)
│   ├── mise/
│   │   └── config.toml          ← global runtime versions + [env] _.file pointing at secrets
│   ├── secrets/
│   │   ├── .env.global.tpl      ← op:// references, committed — safe, no secrets
│   │   └── .env.global          ← resolved via `op inject`, gitignored, never committed
│   ├── starship.toml            ← prompt config
│   ├── tmux/
│   │   └── tmux.conf            ← session persistence config (Ghostty-aware: true color, copy-mode)
│   ├── tmuxp/
│   │   └── *.yaml                ← per-project layout templates (see Section 14)
│   ├── cursor/
│   │   └── User/
│   │       ├── settings.json    ← editor settings
│   │       └── keybindings.json
│   └── zsh/
│       ├── aliases.zsh          ← all aliases — project-independent only, see Section 4.3 rule
│       └── functions.zsh        ← shell functions
│
├── .zshrc                       ← sources all ~/.config/zsh/*.zsh; activates mise; sources Starship
├── .gitconfig                   ← global git config (name, email, signing key)
├── .gitignore_global            ← .DS_Store, *.orig, etc.
├── .default-node-packages       ← npm globals auto-installed by mise
│
└── .ssh/
    └── config                   ← points to 1Password SSH agent socket

~/dotfiles/                      ← private GitHub repo (chezmoi source)
├── bootstrap.sh
├── Brewfile
├── .chezmoi.toml.tmpl
├── .chezmoiscripts/
│   ├── run_onchange_after_10-install-packages.sh.tmpl
│   ├── run_onchange_after_20-install-mas.sh.tmpl
│   ├── run_onchange_after_30-macos-defaults.sh.tmpl
│   ├── run_onchange_after_40-mise-install.sh.tmpl
│   └── run_onchange_after_50-resolve-secrets.sh.tmpl   ← runs `op inject` on .tpl files, see Section 4.8
│   └── run_onchange_after_60-install-codebase-memory-mcp.sh.tmpl ← no Homebrew formula exists, see 4.17
├── dot_zshrc.tmpl
├── dot_gitconfig.tmpl
└── dot_config/
    ├── ghostty/config
    ├── mise/config.toml
    ├── secrets/
    │   └── .env.global.tpl        ← op:// references, committed — safe, no secrets
    ├── starship.toml
    ├── tmux/tmux.conf
    ├── tmuxp/*.yaml                ← per-project layout templates, see Section 14
    └── zsh/
        ├── aliases.zsh
        └── functions.zsh
```

---

## 11. Ongoing Maintenance

```bash
# Update all CLI formulae
brew update && brew upgrade

# Update casks — WITHOUT --greedy.
# Self-updating casks (Cursor, Raycast, 1Password, Arc, Slack) set auto_updates=true
# in their cask definition. Plain `brew upgrade --cask` respects this and skips them,
# avoiding accidental downgrades after their built-in updaters have already run.
brew upgrade --cask

# OrbStack specifically requires --greedy because it self-updates but Homebrew
# still needs to track the version for integrity. Run this separately.
brew upgrade --greedy orbstack

# Sync dotfile changes from another machine
chezmoi update

# Sync runtime versions (Node, Bun, Python, Go, Rust, etc.)
mise upgrade

# Full update alias (add to aliases.zsh)
# Note: OrbStack --greedy is intentionally separate from the general cask upgrade.
alias update='brew update && brew upgrade && brew upgrade --cask && brew upgrade --greedy orbstack && mise upgrade && chezmoi update'

# Check dotfile drift (what would chezmoi apply change?)
chezmoi diff

# Add a new secret to bootstrap
op item create --vault "Developer" --category login \
  --title "New API Key" --field "credential[password]=VALUE"

# Add a new Homebrew package permanently
chezmoi cd         # enter dotfiles repo
# edit Brewfile
chezmoi apply      # runs brew bundle because Brewfile content changed

# Check mise-managed runtimes
mise list

# Run project tasks
mise run dev
mise run test
mise run build

# Start a full project session (see Section 14)
tmuxp load myapp
tmux attach -t myapp

# Regenerate resolved secrets after rotating something in 1Password
op inject -i ~/.config/secrets/.env.global.tpl -o ~/.config/secrets/.env.global
op inject -i .env.local.tpl -o .env.local   # run inside a project directory

# Diagnose chezmoi issues
chezmoi doctor
```

---

## 12. What Requires Manual Steps

The script pauses with clear instructions at each of these points.

| Action | When | Notes |
|---|---|---|
| **Sign into App Store** | Before script | Required for mas to work. `mas account` detection is broken — script gates manually. |
| **Sign into 1Password + enable Touch ID** | Before script | Required for `op` CLI and SSH agent to function. |
| **Grant App Management to Terminal** | Before script | Without this, `brew upgrade --cask` on Tahoe deletes Dock positions and app permissions. |
| **Xcode license agreement** | Auto after mas | Script runs `sudo xcodebuild -license accept` — still requires sudo entry. |
| **OrbStack license** | After install | Commercial use requires paid plan. |
| **Cursor Settings Sync sign-in** | After install | Sign in with GitHub account in Cursor. |
| **Linear / Slack / Notion / Arc sign-in** | After install | Web auth — open the app and sign in. |
| **1Password SSH key setup in GitHub** | Post-bootstrap | `op ssh-agent` generates the key; script can upload it if GH token is in 1Password. |
| **Dock layout (app order)** | After install | dockutil's compatibility with Tahoe's changed Dock/plist architecture is not confidently confirmed — no clear evidence either way. Drag apps into your preferred Dock order manually: Ghostty, Cursor, Arc, OrbStack, Linear. Takes under a minute. |
| **Control Center layout** | After install | Too unreliable to automate on Tahoe. Set manually. |
| **Battery percentage in menu bar** | After install | Affected by Tahoe Liquid Glass redesign of menu bar defaults. |
| **Night Shift schedule** | After install | No reliable `defaults write` key. |
| **Display arrangement** | After install | Machine-specific; can't be scripted. |
| **Entire agent session persistence (per project)** | Project-init, not machine bootstrap | Default OFF. Prompted per-project via the `project-init.sh` script in Section 4.15 — deliberately not part of the one-time machine bootstrap, since the decision (and its confidentiality implications for client repos) is per-repo, not per-machine. |

---

## 13. Known Fragility & Future-Proofing Notes

### The `defaults write` Problem

The `defaults write` system is not versioned by Apple. Keys silently change behavior, get renamed, or get removed across macOS releases without documentation. The approach here:

1. Only include commands confirmed on Tahoe 26
2. Exclude anything unverified or known-broken
3. Add a macOS version guard at the top of `30-macos-defaults.sh`
4. Comment every line — when a key breaks in Golden Gate 27, the comment tells you what it was trying to do
5. The script is idempotent — re-running after a failed key is safe

When Golden Gate ships in September 2026, **audit `defaults write` commands against the first wave of developer reports before running on a new machine.** Pay particular attention to the `com.apple.controlcenter` domain, which may stabilize with Golden Gate's Liquid Glass slider addition.

### Homebrew Cask Version Pinning

There is no lockfile for Homebrew casks. Two engineers running `brew bundle` a month apart get different GUI app versions. This is an accepted tradeoff: for a developer workstation stack of well-maintained tools, "latest stable" is the correct policy. The Brewfile defines *what* is installed, not *which exact version*. If version pinning ever matters for a specific tool, pin it in `.mise.toml` (for runtimes) or raise it as a separate concern.

### Self-Updating Casks

Cursor, Raycast, Arc, OrbStack, 1Password, and Slack all self-update independently. Homebrew tracks a lower version than what's installed after auto-updates, which is exactly why `--greedy` should **not** be used globally — `brew upgrade --cask --greedy` would force-recheck and potentially attempt to reconcile every self-updating cask against Homebrew's stale version record, risking the downgrade problem this section is warning about. The corrected commands in Section 11 avoid this: plain `brew upgrade --cask` (no `--greedy`) respects each cask's `auto_updates true` flag and skips self-updating casks entirely, while `brew upgrade --greedy orbstack` targets OrbStack specifically, by name, as the one deliberate exception.

### mas Is Not Official Apple Software

mas is community-built (MIT licensed), not from Apple. Apple has no official CLI for the App Store. mas may break without warning if Apple changes internal App Store APIs. It is the only tool for this job and worth the dependency, but its continued function is not guaranteed across major macOS releases. If mas breaks on Golden Gate, Xcode installation falls back to the developer.apple.com download or App Store GUI.

### Rosetta 2 Countdown

macOS 27 Golden Gate is the last version with full Rosetta 2. Nothing in our current stack uses Rosetta — all tools ship native arm64. However, if any future package or tool relies on an Intel binary, it will stop working after macOS 28. macOS 26.4 already shows warnings when Intel apps are launched. Keep native arm64 builds as a hard requirement when evaluating new tools.

### Apple Container Watch

Apple's `container` tool (v1.0, Apache 2.0, requires Tahoe 26+) is the long-term future of container tooling on macOS. OrbStack stays primary until Docker Compose support lands in `apple/container`. When it does:
1. Test the `container` CLI against your existing `docker-compose.yml` files
2. Evaluate performance on small-file I/O (npm install is the benchmark)
3. If acceptable, replace OrbStack with Apple Container in the Brewfile — one line change

### dockutil Watch

dockutil is actively maintained (commits/PRs through December 2025) but this research found no explicit confirmation of compatibility with Tahoe's changed Dock architecture. Excluded from automation per Section 4.13; Dock layout is a manual step. Revisit if:
1. A dockutil release or changelog explicitly states Tahoe 26 support, or
2. Multiple independent community reports confirm clean behavior on Tahoe

If confirmed, re-add `brew "dockutil"` to the Brewfile and restore the Phase 3 script shown in the git history of this document (see Section 4.13 for the intended commands).

---

## 14. Terminal Multi-Session & Per-Project Provisioning

This section documents the layer above Ghostty/zsh/Starship that provides session persistence, multi-window management, and one-command project provisioning — the capability gap identified when auditing what "maximized terminal" actually requires.

### 14.1 Why Ghostty + zsh + Starship alone isn't sufficient

Ghostty's native splits and tabs are real, but they are **not persistent** — panes and their running processes disappear when the Ghostty window closes, and Ghostty has no scripting API for declaring a multi-pane layout from a config file. Neither zsh nor Starship address this; they operate inside a single pane, not across a session's lifecycle. A layer is required for: surviving a closed window, named sessions you can return to, and one-command layout provisioning — that's tmux + tmuxp.

A second, related gap: even with tmuxp, a service running in a pane has no supervision — if it crashes, nothing restarts it; there's no way to know when it's actually *ready* versus just started; and it only runs while that specific tmux session exists. That's the gap Pitchfork fills (Section 4.14) — added to this document after auditing jdx's (mise's author) other tools.

### 14.2 The layered model

```
Ghostty  (outer shell — GPU rendering, tabs as project slots, native splits for quick one-offs)
   └── tmux  (session persistence — survives window close, crash, SSH drop; named sessions)
         └── tmuxp  (declarative layout — one command builds a full multi-pane project layout)
               ├── mise  (auto-loads project toolchain + env vars on cd; owns all task execution)
               │     └── Starship  (prompt — reflects git/mise/tmux state, unchanged from Section 4.3)
               └── Pitchfork  (background supervision — services that outlive any single tmux pane,
                                restarted on crash, started/stopped by directory, see Section 4.14)
                     └── mise  (Pitchfork calls `mise run <task>` exactly like tmuxp does — same rule)
```

Each layer does exactly one job and defers to the layer below it for anything outside that job. tmuxp never decides *what* a task does — mise owns that, per the rule in Section 4.3. tmux never decides *how* a layout is shaped — tmuxp owns that. Ghostty never tries to persist state — tmux owns that. Pitchfork sits alongside tmuxp, not beneath it — a Pitchfork daemon can be running whether or not any tmuxp session is open, which is the entire point of using it for things that should outlive a terminal window (see Section 4.14 for the tmuxp-vs-Pitchfork division of labor). Both tmuxp and Pitchfork terminate at the same floor: `mise run <task>`, never the underlying tool directly.

### 14.3 tmux configuration (Ghostty-aware)

`~/.config/tmux/tmux.conf` (managed by chezmoi, symlinked to `~/.tmux.conf`):
```bash
# True color passthrough — local Ghostty sessions
# Ghostty sets TERM=xterm-ghostty automatically and ships a real terminfo entry for it [^17]
set -g default-terminal "tmux-256color"
set -as terminal-overrides ",xterm-ghostty:Tc"

# Prefix: keep default (Ctrl-b) — no reason to relearn muscle memory without a specific complaint
# Mouse support — click to switch panes, drag to resize
set -g mouse on

# Start windows and panes at 1, not 0 — matches how you'd count them visually
set -g base-index 1
setw -g pane-base-index 1

# Increase scrollback — default 2000 is too small for build/dev server logs
set -g history-limit 50000

# Vi-style copy mode — matches terminal conventions most developers already know
setw -g mode-keys vi

# Don't let tmux rename windows automatically — tmuxp sets meaningful names
set -g allow-rename off

# Fast escape time — prevents input lag noticeable in Vim/Cursor's terminal panes
set -sg escape-time 10

# Reload config without restarting session
bind r source-file ~/.config/tmux/tmux.conf \; display "tmux config reloaded"
```

> **📋 Callout #3 — a real gap in the original design, found during this audit: local tmux works out of the box, but `ssh` + `tmux` to a remote host will break by default.** This is a very common, well-documented Ghostty issue, not a hypothetical edge case [^17][^18][^19]. Because `TERM=xterm-ghostty` is set automatically, and most remote systems' terminfo databases don't yet ship Ghostty's entry, starting tmux over SSH produces `missing or unsuitable terminal: xterm-ghostty` and tmux refuses to start. Given this stack is explicitly meant to support backend/systems work — SSH into servers is a normal workflow here — this needs a fix, not just a footnote:
>
> **Recommended fix — add to `~/.config/ghostty/config`:**
> ```
> shell-integration-features = ssh-env,ssh-terminfo
> ```
> This tells Ghostty to automatically set `TERM=xterm-256color` for SSH sessions to hosts without the terminfo entry (`ssh-env`), and to install Ghostty's terminfo on remote hosts you connect to when possible (`ssh-terminfo`) [^17]. This is Ghostty's own documented, maintainer-recommended fix — not a workaround. It should be added to the Ghostty config file when that file is actually authored (see Section 14.6's pre-registered risk note — this is now a second concrete requirement for that file, alongside the mise-task rule).
>
> **Fallback, if `shell-integration-features` isn't set or doesn't cover a specific host:** add a per-host override in `~/.ssh/config`:
> ```
> Host my-remote-server
>   SetEnv TERM=xterm-256color
> ```
> This is the manual version of what `ssh-env` automates. Worth knowing even with the Ghostty-side fix in place, since `ssh-env`'s automatic detection can miss unusual host configurations.

### 14.4 tmuxp project templates

Default 4-window shape, used as the starting point for every project (copy and adjust per project):

```yaml
# ~/.config/tmuxp/_template.yaml — copy to a project-specific file, e.g. myapp.yaml
session_name: myapp
start_directory: ~/code/myapp
windows:
  - window_name: editor
    panes:
      - cursor .
  - window_name: dev
    panes:
      - mise run dev
  - window_name: test
    panes:
      - mise run test:watch
  - window_name: shell
    panes:
      - git status
```

Corresponding `.mise.toml` in the project — this is the file that actually defines what each task does, per the rule in Section 4.3:
```toml
[tools]
node = "22"
bun  = "latest"

[env]
_.file = ".env.local"   # resolved via op inject, see Section 4.8

[tasks.dev]
run = "bun run dev"

[tasks."test:watch"]
run = "bun test --watch"

[tasks.build]
run = "bun run build"
```

**Usage:**
```bash
tmuxp load myapp          # builds the full layout: editor open, dev server running, test watcher running, clean shell
tmux attach -t myapp      # reattach after closing the window — dev server is still running
tmux kill-session -t myapp  # tear down when done
```

### 14.5 What this gets you, concretely

- **Ghostty tabs** = project switcher (⌘1, ⌘2, ⌘3...), one tab per active project's tmux session
- **tmux sessions** = persistence — closing Ghostty, sleeping the Mac, or a crash doesn't lose the dev server or shell state
- **tmuxp** = the "run a command, get the whole project provisioned" ask — one command builds the layout, and because every pane calls `mise run <task>` rather than the underlying tool, every pane also gets the correct toolchain version and env vars the instant it opens, with zero manual activation
- **mise** continues to own 100% of "what does this project's dev/test/build command actually do" — tmuxp only ever describes shape (how many windows, what they're named), never implementation

### 14.6 Requirements for when the Ghostty config file is actually authored

Two concrete, standing requirements for `~/.config/ghostty/config`, both surfaced during this audit rather than assumed:

1. **No project-specific commands.** Any keybind or startup command must be checked against the same rule as everything else in this section: if it would run a project-specific tool command, it must call `mise run <task>` (or launch `tmuxp load <project>`, which itself only calls `mise run` per Section 14.4) — never the underlying tool directly. This was flagged as a standing check so the same bypass bug caught in the original tmuxp draft doesn't reappear in a different file.
2. **`shell-integration-features = ssh-env,ssh-terminfo` must be set.** Per Section 14.3's Callout #3, without this line, `ssh` + `tmux` to any remote host lacking Ghostty's terminfo entry breaks by default. This is not optional for a stack that includes backend/systems SSH workflows.

### 14.7 Git worktrees + tmux — workmux

[workmux](https://github.com/raine/workmux) (`brew install raine/workmux/workmux`) layers parallel git-worktree + AI-agent workflows on top of the tmuxp sessions from Section 14.4, without replacing them. Global config lives at `~/.config/workmux/config.yaml` (chezmoi-managed, `dot_config/workmux/config.yaml`).

Two ways to use a worktree once it exists:

- **`wm add <branch>`** (alias for `workmux add <branch>`) — native workmux behavior. Creates the worktree and a new `wm-<branch>` tmux window running just an AI agent (`claude`), alongside — not replacing — the project's existing `ai`/`dev`/`supabase`/`test`/`shell` windows, which stay on the main checkout. Use this to have an agent work a branch in isolation while you keep using the main checkout normally.
- **`wma <branch>`** (`workmux-activate`, `dot_config/workmux/bin/executable_workmux-activate`) — a custom addition, not part of workmux itself. Retargets the *existing* windows of the current tmuxp session at the worktree: it reads the session's own `~/.config/tmuxp/<project>.yaml` to find each window's name and pane command, interrupts it, `cd`s into the worktree path, and re-runs that same command (`mise run dev:<project>`, `mise run supabase:start`, `cursor .`, etc.) from there. Use this when you actually want to run/test a specific worktree's code, not just have an agent working on it. `wma main` (or no argument) retargets everything back to the original checkout — this also runs automatically as workmux's `pre_remove` hook, so `wm remove`/`wm merge` never leaves a window cd'd into a deleted worktree.

Because `workmux-activate` derives window names and commands from the tmuxp yaml instead of hardcoding them, no per-project `.workmux.yaml` is required — one is only needed if a project wants to override a global default (agent, merge strategy, etc.).

---

## 15. Audit Methodology & References

This section documents two verification passes that produced the numbered citations `[^1]`–`[^25]` throughout this document. Every claim below was checked against a live source at the time of the relevant audit — not recalled from training data or an earlier, unverified pass. Where a figure varies across sources (e.g. iTerm2's exact idle RAM), that variance is noted rather than silently picking one number.

**Pass 1 scope (citations 1-20):** Ghostty, mise, Cursor, OrbStack, and the tmux/Ghostty SSH interaction — the tools with the highest rate of change since this document's stack decisions were first researched, and the areas most likely to contain stale specifics. Sections 6-8 (macOS Tahoe/Golden Gate `defaults write` audit) and the core layering rules (Sections 4.3/4.4/4.8/9/14) were re-read for internal consistency in the prior session's audit and were not re-verified against new external sources in this pass, since their claims are either about this document's own internal architecture (which doesn't go stale) or were already sourced against Apple Community/developer-forum reports specific to Tahoe.

**What changed as a direct result of Pass 1:** Ghostty section corrected (RAM figures, current version 1.3.1, new 1.3.0 features, CVE patch, AppleScript preview status); mise section updated with current version and a new callout on mise's native `mise bootstrap` system; Cursor section corrected for a factual error (extension compatibility was overstated) and updated with current market data; OrbStack section updated with its UI redesign and CVE-unaffected status; tmux config corrected (setting order) and a previously undocumented SSH/terminfo failure mode added with a sourced fix.

**Pass 2 scope (citations 21-25):** Three tools proposed by the user for evaluation — Pitchfork (jdx's background process supervisor), the Usage CLI spec (jdx's argument-parsing schema), and Entire CLI (agent session persistence, distinct from entire.io's forward-looking company vision document). All three were fetched and read directly from primary sources (official docs, GitHub repositories) rather than search snippets, given their technical specificity.

**What changed as a direct result of Pass 2:** New Section 4.14 (Pitchfork) added as a stack decision, wired into Section 14's layered model as a parallel supervision layer alongside tmuxp — both terminate at `mise run <task>`, no exception to the existing layering rule. New Section 4.15 (Entire CLI) added as a per-project, default-OFF tool for agent session persistence, with an explicit `push_sessions = false` safety default given this machine's client/consulting use case. Usage spec evaluated and explicitly *not* adopted as a stack tool — noted as already running invisibly inside mise, no further action.

**Pass 3 scope (citations 26-30):** Two items — closing a gap where Claude Code and Claude Desktop were referenced repeatedly throughout the document (competitive comparisons, MCP integrations, agent hooks) but never given their own stack entry despite being the tools this document's author (Claude) and its user actually run daily; and evaluating `codebase-memory-mcp`, a token-efficiency-focused MCP server proposed by the user. Claude Code install mechanics were verified directly against Anthropic's own documentation (code.claude.com) rather than third-party guides. codebase-memory-mcp's efficiency claims were traced to their source — a dated, named-author arXiv preprint — rather than accepted from the README's framing alone; the paper's own reported accuracy tradeoff (83% vs. a 92% file-exploration baseline) is stated explicitly in Section 4.17 rather than only the more flattering "83% answer quality" headline.

**What changed as a direct result of Pass 3:** New Section 4.16 (Claude Code + Claude Desktop) added as first-class stack citizens, with verified Homebrew cask names, channel behavior, and the auto-update env var wired into both mise global config examples for consistency. New Section 4.17 (codebase-memory-mcp) added with an explicit, sourced accuracy-tradeoff caveat and an independently-reported OpenSSF Scorecard figure included alongside the project's own security claims, rather than repeating only the self-reported security posture.

**Pass 4 scope (citations 31-33):** A deeper, specifically adversarial audit of `codebase-memory-mcp` — prompted by the user asking directly whether "plug and play" trust was warranted, rather than accepting Pass 3's more casual "recommended" framing. This pass went past the project's own README and searched its GitHub Issues tracker directly for reports of accuracy or data-integrity failures, and its Releases changelog for security-relevant history, rather than relying on the project's self-description. Two confirmed, filed bug reports were found describing a silent partial-index failure and a stale-read failure mode, plus changelog evidence of a prior SQL/argument injection vulnerability that was patched. All three are real findings from primary sources (the project's own issue tracker and release notes), not inferred or hypothetical risk.

**What changed as a direct result of Pass 4:** Section 4.17 rewritten from "evaluated and recommended" to "adopt with explicit guardrails" — a materially more calibrated recommendation. Added: a concrete when-to-use-vs-when-to-bypass table addressing the accuracy-tradeoff concern directly; documentation of the `CBM_ALLOWED_ROOT` environment variable as a path-restriction control, specifically relevant given this machine's client/consulting repo access; a note on the local UI variant's HTTP binding and its v0.8.1 hardening; and a revised recommendation to keep `auto_index` off (matching the tool's own default) rather than suggesting it be turned on, so that per-project activation remains a deliberate moment to also verify `CBM_ALLOWED_ROOT` is scoped correctly.

**Pass 5 scope (citations 34-38):** A broad gap analysis — the user asked directly what tools were missing from the stack, especially AI-development-related, rather than this document waiting to be asked about a specific tool. This pass surveyed the general 2026 AI/agentic developer tooling landscape (coding agent comparisons, local LLM inference, vector databases, LLM observability, agent sandboxing) and evaluated each category for actual relevance to this specific machine's context — solo/freelance development with Claude Code and Cursor already decided — rather than treating every category as an equal gap. Several categories surveyed were explicitly found *not* to be gaps (competing coding agents like Windsurf/Codex CLI/Antigravity — redundant with the already-decided Cursor + Claude Code pair) and are not reflected in new sections; only genuine gaps were added.

**What changed as a direct result of Pass 5:** Three new sections. Section 4.18 (Claude Code Sandboxing) — the most significant finding of this pass: Claude Code ships a native, first-party sandbox that this document had never mentioned despite three tools (codebase-memory-mcp, Entire CLI, Pitchfork's MCP server) already running with full host access; the distinction between the Bash-only `/sandbox` and the process-wide sandbox runtime is now explicit, along with the documented devcontainer path for unattended work. Section 4.19 (Ollama) — a local LLM inference gap, added as a low-cost Brewfile addition. Section 4.20 (Langfuse) — documented as a project-scoped answer for if/when a project calls LLM APIs directly, explicitly not added to the Brewfile, with a relevant timing note that a competing tool (Helicone) was acquired and moved to maintenance mode in March 2026 while Langfuse's acquisition did not freeze its roadmap. Vector databases were surveyed in this pass but explicitly excluded from the runbook per user direction — noted in the archive only, not treated as an actionable gap for this machine.

**Pass 6 scope (citations 39-40):** A correction, not an addition — prompted by the user directly questioning a claim that had gone unverified across five prior passes: that `mas` reliably automates Xcode installation as part of the bootstrap script. It did not. Checked directly rather than re-asserted: an open, unresolved Homebrew GitHub issue (filed Feb 2026) confirming `brew bundle`'s use of `mas install` (not `mas get`) fails on fresh Apple IDs with "Redownload Unavailable," and independent Apple Community reporting that Xcode's install is unreliable via the App Store path specifically, regardless of the tool used to trigger it. This is a reminder that a claim repeated across multiple document passes without direct verification is not the same as a verified claim — five earlier passes touched the mas/Xcode section (adding CVE-2025-43411 sudo requirements, the `mas account` detection bug, Spotlight dependency) without ever checking whether the core "mas installs Xcode successfully" premise held up.

**What changed as a direct result of Pass 6:** Section 4.12 rewritten to explicitly remove Xcode from the automated `mas` path and correct the record on why. Xcode removed from the Brewfile's Mac App Store block and from the `run_onchange_after_20-install-mas.sh.tmpl` script — both now carry a comment explaining the change rather than the app itself. The runbook's bootstrap step list, manual-steps table, and verify block were all updated so Xcode is a clearly-flagged, prominent manual step (direct download from developer.apple.com, started early since it's a large download) rather than an assumed-successful automated one.

**Pass 7 scope (citation 41):** A real execution failure, not a desk review — the user actually ran `bootstrap.sh` and hit `ssh: Could not resolve hostname gh: nodename nor servname provided, or not known` on `chezmoi init`. Root cause: `bootstrap.sh` and two mentions in this archive used `gh:USERNAME/dotfiles` as chezmoi's repo argument. That syntax does not exist — chezmoi's real shorthand is a bare `chezmoi init <username>`, which it expands internally to an HTTPS URL, or a full explicit URL (HTTPS or `git@github.com:...` for SSH) [^41]. The `gh:` prefix was never real syntax in any version of chezmoi; it appears to have been fabricated (possibly a false-memory blend with GitHub CLI's own `gh:` scheme used elsewhere, e.g. GitHub Actions) and was never verified against chezmoi's actual command reference before being written into either the script or the architecture doc — a direct instance of the same failure class Pass 6 named: repeated, confident mentions across a document are not the same as verification.

A second, related bug surfaced while fixing the first: this stack's own design requires SSH (via 1Password's SSH agent) to clone the dotfiles repo in `bootstrap.sh`, but the `~/.ssh/config` `IdentityAgent` line that makes that agent reachable was designed in Section 4.11 and never actually built as a chezmoi-managed file in the repo — meaning the exact mechanism needed to fix the clone was itself circular (chezmoi needs SSH working to write the file that makes SSH work). The runbook's pre-flight checklist also never listed "enable 1Password's SSH Agent" as a required manual step, despite the whole SSH design depending on it.

**What changed as a direct result of Pass 7:** `bootstrap.sh`'s `DOTFILES_REPO` variable corrected to the user's real SSH URL (`git@github.com:kyleturner/dotfiles.git`), replacing the invalid `gh:` syntax. A pre-seed step added to `bootstrap.sh`, before the sudo keepalive, that writes a minimal `~/.ssh/config` with the 1Password `IdentityAgent` line if not already present — breaking the chicken-and-egg so `chezmoi init` can actually clone over SSH. The proper chezmoi-managed `dot_ssh/config` file was created (previously only ever described in prose in Section 4.11, never built), matching the pre-seed content exactly so the two never drift once chezmoi applies. The runbook's Section 0 pre-flight checklist now explicitly lists enabling 1Password's SSH Agent as a required step, with the exact failure mode named so it's recognizable if hit again. Both stale `gh:` mentions elsewhere in this archive corrected.

**Pass 8 scope (citation 42):** A third real execution failure, immediately following Pass 7's fix — the repo cloned successfully, but `chezmoi init` then failed with `decoding failed due to the following error(s): 'vault' expected a map or struct, got "string"`. Root cause: `.chezmoi.toml.tmpl`'s `[data]` table defined a custom field named `vault = "Developer"` (the 1Password vault name, set in an earlier session per the user's correction from "Developer Secrets" to "Developer"). `vault` is not an arbitrary available name — it is a reserved top-level key in chezmoi's own config schema, used for HashiCorp Vault integration (`vault.command`, expected to be a string *inside* a `vault` struct, not a bare string itself) [^42]. This was never checked against chezmoi's actual configuration-file reference when the field was originally named — the same failure class as Pass 7 (unverified syntax choice), but for config schema rather than command syntax.

**What changed as a direct result of Pass 8:** The colliding field renamed from `vault` to `opVault` in `.chezmoi.toml.tmpl`, with an inline comment explaining why the plain name is unsafe. Confirmed via full-repo search that no template anywhere actually consumed `.vault` (the 1Password vault name is hardcoded directly into `op://Developer/...` references rather than templated), so the rename carries zero downstream impact. Recovery guidance added for the specific state a failed `chezmoi init` leaves behind: the source directory (`~/.local/share/chezmoi`) is already cloned successfully by the time this error occurs, since the failure happens during config decode, after clone and before the apply phase — so recovery is `chezmoi git pull` (or `chezmoi update`) to pull the fix into the existing clone, followed by re-running `chezmoi init --apply`, not a full re-clone.

**Pass 9 scope — no new citation, a mechanical bug caught via direct simulation:** A fourth real execution failure, after the `opVault` fix was pushed and applied cleanly, but a *different* template — `dot_gitconfig.tmpl` — then failed with `map has no entry for key "name"`. Root cause: `.chezmoi.toml.tmpl` chained three `{{- promptStringOnce ... -}}` lines with aggressive trim markers on both sides, and nothing separated that chain from `[data]` below it except a single blank line. Go template trim markers strip *all* whitespace back to the previous non-whitespace character — the trimming reached past the blank line into the preceding comment block, gluing `[data]` onto the end of the last `#` comment line. Since `#` runs to end-of-line in TOML, `[data]` was silently swallowed into the comment and never parsed as a real table header — `name`/`email`/`profile` landed outside `[data]` entirely, so `.name` genuinely didn't exist for any template that referenced it. This was diagnosed by simulating Go's actual template trim rules in Python against the real file content, rather than reasoning about the behavior abstractly — a direct lesson from Pass 8's mistake of trusting reasoning over verification.

**What changed as a direct result of Pass 9:** A `{{/* ... */}}` comment block (no trim markers) inserted between the prompt lines and `[data]`, acting as a hard whitespace boundary the preceding `-}}` chain cannot reach past. Verified mechanically, twice — the fix was checked with a Python simulation of Go's trim rules before being handed over, and a bug in the first attempt at the fix (comment block adjacent to `[data]` without an intervening blank line) was caught by that same verification step before shipping, not after.

**Pass 10 scope (citations 43-46) — four more real execution bugs, found only because the user actually ran the corrected bootstrap end-to-end.** After Pass 9's fix, `chezmoi init --apply` progressed much further — through config decode and into `brew bundle` — before failing again. Four real, independently-verified Brewfile bugs surfaced in a single run: (1) `brew "1password-cli"` doesn't exist — it's a cask, not a formula, confirmed against Homebrew's own formula/cask index [^43]; (2) `brew "fast-syntax-highlighting"` doesn't exist — the real name is `zsh-fast-syntax-highlighting`, also confirmed against Homebrew's index [^43]; (3) `brew "terraform"` was disabled by Homebrew's own core tap on April 12, 2025 after HashiCorp relicensed Terraform to BUSL (no longer open source) — it will not return under that name, and the fix is HashiCorp's own tap [^44]; (4) `brew "codebase-memory-mcp"` was never installable via Homebrew at all — confirmed via the project's own open, unresolved GitHub issue explicitly requesting this support [^45]. A fifth issue was not a Brewfile bug but an ecosystem change: Homebrew 6.0.0 (June 11, 2026) introduced "tap trust," blocking third-party tap code by default — surfaced as `Error: Refusing to load cask entireio/tap/entire from untrusted tap`, fixed with `trusted: true` on both the affected `tap` lines and, redundantly for resilience, on the individual `brew`/`cask` entries themselves, matching Homebrew's own documented `brew bundle dump` pattern [^46]. A sixth warning (`Cask linear-linear was renamed to linear`) was checked at the time and concluded to be a false alarm based on Homebrew's cask source as it existed then — **this conclusion did not hold up and was corrected in Pass 12** (see below); the rename is real and was completed by Homebrew afterward.

**What changed as a direct result of Pass 10:** All four real Brewfile bugs corrected with inline comments explaining each one. `trusted: true` added to both third-party taps and their dependent packages. The `linear-linear` warning was documented as benign at the time — later found to be incorrect; see Pass 12.

**Pass 11 scope — two scope changes requested directly by the user, not new technical findings.** (1) Entire CLI moved from a Brewfile-installed, bootstrap-tapped tool to a documented recommended follow-up — the `entireio/tap` and `cask "entire", trusted: true` lines removed from the Brewfile entirely; Section 4.15 and its install instructions updated to reflect this is now something to add manually, later, if wanted, not part of `chezmoi apply`. (2) `codebase-memory-mcp`'s install method — already corrected in Pass 10 to not use a nonexistent Homebrew formula — was further changed from "run this manually, whenever" to fully automated: a new `run_onchange_after_60-install-codebase-memory-mcp.sh.tmpl` script runs the project's own install script as part of the standard bootstrap flow, positioned after secrets resolution (script 50) so `CBM_ALLOWED_ROOT` is already set before the tool is ever invoked. This script's `run_onchange_` behavior was verified directly against chezmoi's own documentation (hashing the script's own rendered content, no external include needed, since there's no external file this script reacts to) rather than assumed correct by analogy to the other scripts — the third time in this session that an assumption about chezmoi's exact behavior was checked rather than trusted, after two earlier assumptions (Pass 7's `gh:` syntax, Pass 8's `vault` key) turned out to be wrong.

**What changed as a direct result of Pass 11:** Brewfile: `entireio/tap` and `cask "entire"` removed. New `.chezmoiscripts/run_onchange_after_60-install-codebase-memory-mcp.sh.tmpl`. Bootstrap architecture diagram (Section 2), Section 9's script listing, and Section 10's file tree all updated to include script 60. Section 4.15 and 4.17 rewritten to reflect both changes with full reasoning, not just the mechanical diff.

**Pass 12 scope (citation 47) — a correction to Pass 10's own conclusion, prompted directly by the user hitting the exact warning Pass 10 had dismissed.** During further real bootstrap runs, the user kept seeing `Warning: Cask linear-linear was renamed to linear` and asked for it to be resolved. Re-checked from scratch rather than trusting the earlier "false alarm" conclusion: the original PR that created the `linear-linear` cask (Homebrew/homebrew-cask#83144) shows Homebrew's own maintainers explicitly discussing a future path to renaming it once cask-level rename support existed ("If your software becomes more popular... and we get the equivalent of formula_renames.json for casks, we can consider a switch then") [^47]. That rename has since happened — the live, repeated warning is Homebrew correctly reporting it, not a stale artifact. Pass 10's conclusion was accurate at the time it was checked but did not hold up under continued real-world use, the same lesson named in Pass 6: a claim checked once is not a claim verified permanently, especially against a fast-moving package index.

**What changed as a direct result of Pass 12:** Brewfile's cask token corrected from `linear-linear` to `linear`, both in Section 5's example and the actual shipped Brewfile. `run_onchange_after_10-install-packages.sh.tmpl` gained an automatic `brew migrate --cask linear-linear` step, run conditionally (only if the old token is actually installed) before `brew bundle` — using Homebrew's own documented command for exactly this migration scenario, rather than a manual uninstall/reinstall, since a bare Brewfile token change alone does not retroactively migrate an already-installed cask. Pass 10's own methodology note above corrected in place rather than left standing as a wrong conclusion.

**Pass 13 scope (citations 48-51) — a real execution failure, plus a scope-removal request.** The user reported `Installing 'ice' has failed!` and `brew bundle failed! 1 Brewfile dependency failed to install` during a live bootstrap run, and separately asked for CleanMyMac to be removed entirely. Investigating the Ice failure surfaced two distinct, previously undetected bugs rather than one: (1) the Brewfile's `cask "ice"` token has never existed in Homebrew — confirmed against Homebrew's own cask index, the real tokens are `jordanbaird-ice` (stable) and `jordanbaird-ice@beta` [^48]; this was a wrong token from the very first version of this document, unrelated to Tahoe compatibility. (2) Independently, and more concerning: Section 4.9's earlier claim that Ice was "confirmed working on Tahoe 26" did not hold up — two separate, independent user reports describe Ice crashing on Tahoe, one on 26.0 [^49] and one as recently as 26.5 (June 2026) [^50], both describing the same symptom (menu bar item display fails or the app crashes on interaction). A third source confirms a working fix: switching to the beta channel (`jordanbaird-ice@beta`, 0.11.13-dev.2+) resolved the identical crash for at least one affected user [^51].

**What changed as a direct result of Pass 13:** Brewfile's Ice line corrected to `cask "jordanbaird-ice@beta"` — fixing the wrong token and applying the confirmed Tahoe workaround in one change, with the reasoning for using the beta channel specifically (not just a preference) documented inline. Section 4.9 rewritten from a confident "confirmed working" claim to an accurate account of the real, documented Tahoe crash and its fix, including a note on when to revisit the stable channel. `cleanmymac` removed from the Brewfile and Section 5's example entirely per direct user request — a scope reduction, not a technical finding, consistent with how Entire CLI's removal was handled in Pass 11. **Note: this Ice fix was superseded one pass later — see Pass 14.**

**Pass 14 scope (citations 52-55) — a scope-removal request that also closed out the whole Ice saga.** The user asked to remove Ice from the dependency stack entirely, stating that macOS has replaced the need for it with a native capability. Checked directly rather than assumed correct: confirmed across four independent sources that macOS Tahoe 26 added a genuine, native Menu Bar section in System Settings (System Settings → Menu Bar → Menu Bar Controls) with per-app icon show/hide, Command-drag reordering, and auto-hide modes [^52][^53][^54] — one source stated plainly that this built-in option eliminated their need for a third-party menu bar manager [^54]. A further, forward-looking finding not directly asked for but relevant to the decision: one source reports macOS 27 Golden Gate adds a native overflow-icon expand button and breaks Bartender, Ice, Thaw, and Hidden Bar in the process [^55] — meaning this isn't just "native catches up for now," it's a trend of Apple absorbing this category of functionality across consecutive OS versions, which strengthens rather than merely permits the removal.

**What changed as a direct result of Pass 14:** Ice (`jordanbaird-ice@beta`) removed from the Brewfile entirely, in both the shipped file and Section 5's example. Section 4.9 rewritten a third time — this time to "Removed," with the prior two corrections (wrong token, then beta-channel workaround) preserved as history rather than deleted, so the reasoning trail stays intact. Runbook's installed-package summary updated to point at native Menu Bar Controls instead of listing Ice. If a genuine gap in native controls surfaces later, Section 4.9 now names Hidden Bar as the narrower, lower-risk tool to evaluate first, rather than defaulting back to a broader manager like Ice or Bartender.

**Pass 15 scope (citations 56-64) — a direct challenge from the user: if Ice's native-replacement gap existed undetected, what else in this stack has the same blind spot?** This was a request for a systematic audit, not a single fix. Every GUI cask in the current Brewfile (21 casks total) was checked against the question "does macOS Tahoe already provide this natively, and if so, does that change the recommendation?" — not just re-litigating tools already flagged, but genuinely re-examining the full list. Three categories were checked in depth with real sourcing: app launching/window management (Raycast), clipboard history (also Raycast), and disk cleanup (CleanMyMac, already removed in Pass 13 per direct request — this pass independently confirmed that removal was well-founded, since native storage tools handle the basics while dedicated cleaners fill a real, documented gap in app-leftover and deep-cache removal that native doesn't cover). The remaining 18 casks (terminal, editor, AI tooling, containers, secrets, dev tools, browsers, communication, fonts) have no plausible native-macOS overlap — they're either developer tools with no OS equivalent (Ghostty, Cursor, OrbStack, TablePlus, Proxyman) or third-party services with no first-party alternative (Slack, Notion, Linear, 1Password) — and were not re-audited in depth beyond confirming this.

**The audit's actual finding: no second Ice-class bug existed, but the reasoning for keeping Raycast had never been stated explicitly against native Tahoe features — it was previously justified in general terms ("Tahoe-compatible: confirmed working") rather than checked feature-by-feature the way Ice's removal now demands as a standard.** Launchpad's removal in Tahoe [^56][^57] doesn't create a launcher gap Raycast happens to fill — multiple sources are explicit that keyboard-first tools like Raycast and grid-first Launchpad replacements serve different user types, and this stack was already keyboard-first by design (`mise run`, `tmuxp`, alias-driven workflows throughout), so Raycast was the correct fit independent of what changed in Tahoe [^56]. Native window tiling is confirmed genuinely sufficient for basic use by an independent three-week comparison [^58], but Raycast's window management isn't a separate dependency layered on top of that gap — it's a first-party feature of the same free tier already installed for launching [^59][^60], so there's no redundant tool to remove. Same structure for clipboard history: native Tahoe clipboard history is real and confirmed working [^61][^62], but every source agrees it's deliberately basic (capped retention, no pinning) [^63][^64], and Raycast's clipboard history is the more capable option at zero marginal installation cost.

**What changed as a direct result of Pass 15:** Section 4.10 substantially expanded with explicit, sourced, feature-by-feature reasoning for why Raycast is kept despite native Tahoe overlap in exactly the categories that would have been the next likely places for an Ice-class error — rather than leaving the prior "Tahoe-compatible: confirmed working" one-liner as sufficient, which is the same level of unstated confidence that let Ice's problems go unfound for multiple passes. No packages were removed or added as a result of this pass; the audit's output is documentation rigor, not a new decision — which is itself a defensible, cited conclusion rather than an assumption that nothing else was wrong.

**Pass 16 scope (citations 65-69) — four real execution failures from getting further through the bootstrap than any prior run, three of which were genuine bugs and one of which was expected behavior mistaken for an error.** The user reported: (1) script 30 hard-failing with `Could not write domain .../Containers/com.apple.Safari/...`; (2) Ghostty refusing to start with `theme "catppuccin-mocha" not found`; (3) Starship printing `Error in 'StarshipRoot' at 'tmux_session': Unknown key` on every prompt; (4) OrbStack prompting to install Rosetta, with a direct question about whether an Apple-Silicon-only build exists. All four investigated with primary sourcing rather than assumption. (1) Safari's preferences have been sandboxed since Safari 13, living in a Container rather than the normal `~/Library/Preferences/` path `defaults write` targets by default — reaching the real location requires Full Disk Access for the calling process, and without it the write can hard-fail rather than degrade [^67]. This is genuine, documented macOS sandboxing behavior; the bug was in this stack's script, which let a single non-critical `defaults write` failure kill the entire `run_onchange_after_30` run under `set -euo pipefail`, rather than a bug in the concept of setting Safari defaults at all. (2) Ghostty 1.2.0 renamed its bundled theme files from lowercase-hyphenated (`catppuccin-mocha`) to title-case-spaced (`Catppuccin Mocha`) — a real, confirmed breaking change in Ghostty itself, documented directly by the maintainers [^68]; this stack's config used the pre-1.2.0 name. (3) `[tmux_session]` was never a real Starship module — checked directly against Starship's actual documented pattern for showing tmux session names, which is implemented via a custom module (`[custom.tmux_session]`) with a `command`, `when`, and `format`, not a bare built-in section [^69]; this was a fabricated module name introduced when this file was first written and never verified against Starship's real module list. (4) OrbStack's Rosetta requirement is expected, by-design behavior, confirmed directly from OrbStack's own documentation and a real GitHub issue describing the same prompt-gate behavior [^65][^66] — there is no Apple-Silicon-only OrbStack build that skips it, since Rosetta is what lets OrbStack run x86/Intel images at near-native speed rather than falling back to slow emulation.

**What changed as a direct result of Pass 16:** Script 30's Safari block wrapped in an `if`/`else` so a Full-Disk-Access-related failure degrades to a warning instead of killing the whole defaults run — verified this is correct, documented `set -e` behavior (commands inside an `if` condition are exempt from triggering exit-on-error), not an assumption. `dot_config/ghostty/config`'s theme value corrected to `Catppuccin Mocha`, with an inline note flagging this as a Ghostty-side breaking change to watch for again in future releases. `dot_config/starship.toml`'s fake `[tmux_session]` module replaced with the real, verified `[custom.tmux_session]` pattern, syntax-validated as parseable TOML before shipping. OrbStack's Rosetta requirement documented in Section 4.6 with citations, and folded into the runbook's Full Disk Access manual step (now also covering Safari) plus a new explicit "this is expected" note so it doesn't read as a failure on a future run.

**Pass 17 scope (citation 70) — a real execution failure from getting one phase further than Pass 16, plus two items reported for hardening that turned out to have different dispositions.** The user reported script 50 failing outright: `could not read the input file /Users/kyleturner/.config/secrets/env.global.tpl: open ... no such file or directory`. Traced precisely rather than guessed: checked chezmoi's own attribute reference directly, which states the `dot_` transformation literally — "`dot_foo` becomes `.foo`" — meaning the whole leading token gets a dot prepended, not just part of it. The source file `dot_config/secrets/dot_env.global.tpl` therefore becomes `~/.config/secrets/.env.global.tpl` (**with** a leading dot) when chezmoi applies it. Both `run_onchange_after_50-resolve-secrets.sh.tmpl` and the `resecrets` shell function in `dot_config/zsh/functions.zsh` had been written pointing at `env.global.tpl` (no leading dot) — a real bug in this stack's own scripts, not a chezmoi behavior issue, and notably a bug this document's own earlier prose (Section 4.8, and an earlier draft of this section) had already gotten *right* before the actual scripts were built, meaning the error was introduced when translating the documented design into working code, not in the design itself. Two further items reported for hardening were checked and found to have different dispositions: `mise WARN gpg not found, skipping verification` is confirmed cosmetic and non-blocking, sourced against multiple independent reports showing the identical warning immediately followed by successful tool installation [^70] — mise optionally verifies some downloads with GPG if available and simply skips the check otherwise. `mise doctor reported issues` could **not** be diagnosed in this pass — the bootstrap log only captured the generic warning line, not `mise doctor`'s actual output, and that output was requested from the user but not yet received as of this update. This is documented as a known open item rather than closed, since guessing at a fix without the real error text would risk the same class of mistake (fixing based on assumption) that caused the `env.global.tpl` bug in the first place.

**What changed as a direct result of Pass 17:** `run_onchange_after_50-resolve-secrets.sh.tmpl` corrected to reference `.env.global.tpl` (with leading dot), and hardened with an explicit `TEMPLATE_PATH` variable plus a pre-flight existence check that fails with a clear, diagnosable message if the expected file is missing — rather than surfacing only `op inject`'s bare "no such file" error, which is what made the original bug harder to immediately place. `resecrets()` in `dot_config/zsh/functions.zsh` fixed with the same path correction. Section 9's documented script content updated to match the real, corrected script, with an inline note on the bug and its cause. Section 4.4 gained a documented, sourced explanation of the `gpg` warning as safe-to-ignore, and an explicit "open item, not yet resolved" note for `mise doctor`'s output — a deliberate choice to represent it as unresolved rather than silently drop it or guess at a fix.

**Pass 18 scope (citation 71) — a real execution failure from getting one phase further than Pass 17, immediately after the `.env.global.tpl` path fix.** The user reported `op inject` failing with `invalid secret reference 'op://REFERENCES ONLY': too few '/': secret references should have at least vault, item and field specified`. Traced directly rather than assumed: the actual `.tpl` file's first line was a human-readable `#` comment — `# op:// REFERENCES ONLY — no actual secrets...` — written purely to describe the file's purpose to a future reader. `op inject` does not treat `#` as a comment marker; it scans the entire file's text for anything matching the `op://` pattern, found it inside that comment, and tried to parse the words immediately following it as a real vault/item/field path. Checked against multiple independent real-world `op inject` template examples to confirm the mechanism: none of them include explanatory comments containing the literal `op://` string, which is the community's de facto workaround for a limitation that isn't prominently documented by 1Password itself [^71]. This is the second bug found in this same file's history (after the vault-key-collision bug in `.chezmoi.toml.tmpl`, Pass 8) that came from writing a helpful comment using the exact syntax being described — a pattern worth naming explicitly as a standing risk for any templated config file, not just this one.

**What changed as a direct result of Pass 18:** `dot_config/secrets/dot_env.global.tpl`'s header comment rewritten to describe its purpose without ever writing the literal `op` immediately followed by `://`, including in the sentence describing the bug itself (split as `"op"` and `"://"` to document the finding without retriggering it). A standing rule added to Section 4.8: no file that is ever passed as `op inject -i` input may contain the literal `op://` string in prose, even to explain the syntax — confirmed which of this repo's other files reference the pattern in prose (`run_onchange_after_50`'s own comments, `.gitignore`, `.chezmoi.toml.tmpl`) and confirmed none of them are ever fed to `op inject` as input, so no further fixes were needed there.

**Pass 19 scope (citation 72) — a real execution failure of a genuinely different class than every prior pass in this section, from getting one phase further than Pass 18.** The user reported `op inject` failing with `could not find item GitHub-PAT in vault ...` — `op` had successfully authenticated and resolved the vault name, then found no item named `GitHub-PAT` inside it. Unlike Passes 6 through 18, which were all bugs in this stack's own scripts or config syntax, this failure's root cause was structural rather than a fixable typo: the item name `GitHub-PAT` was a placeholder invented when the secrets architecture was first designed, and this document has no way to inspect anyone's real 1Password vault contents to confirm such a placeholder actually exists before shipping it. The user confirmed they didn't yet have a GitHub PAT stored and chose to create one fresh, using the existing placeholder name rather than requesting a rename — meaning the fix was creating the real item, not further editing the template. While preparing the exact `op item create` command for this, a second, genuine syntax bug was caught in the same line: the field name `token` does not exist on 1Password's "API Credential" item category. Confirmed directly against 1Password's own item-category documentation, which lists `credential` as the field name for this category, and independently confirmed by a third-party guide that names this exact mistake explicitly — "provider references end in /credential, not /token" [^72]. Notably, the adjacent `ANTHROPIC_API_KEY` line in the same file already used `/credential` correctly, meaning only the `GITHUB_TOKEN` line carried the error — the two lines were evidently written with different levels of verification rather than the same mistake being made twice.

**What changed as a direct result of Pass 19:** `dot_env.global.tpl`'s `GITHUB_TOKEN` reference corrected from `/token` to `/credential`, with an inline comment naming the correct field for this item category so the mistake isn't repeated on a future secret. The exact `op item create` command needed to populate the matching real item was worked out and provided directly, using `--category "API Credential"` and `--field "credential=..."` to guarantee the created item actually matches what the corrected template expects. A new structural note added to Section 4.8: since this document cannot verify anyone's actual vault contents, any new `op://` reference should be treated as unverified until confirmed with `op item get <title> --vault <vault>` — a lightweight, one-line check named explicitly as the corrective practice this gap exposed, rather than leaving the lesson as "this specific item was wrong" without a general fix for the next one.

**Pass 20 scope — a scope-removal request, not a bug, prompted by the same class of failure as Pass 19 hitting a second placeholder.** The user hit `could not find item Claude API in vault ...` — the same failure mode as Pass 19, but for `ANTHROPIC_API_KEY` this time — and used it as the moment to state directly that this machine should not have an Anthropic API Platform key at all, given per-token pricing and overage risk, since Claude Code/Desktop/Chrome/etc. are subscription-based and don't need one. Checked Section 4.16 directly to confirm this claim rather than take it at face value: correct — nothing in that section's install method, layering notes, or recommendation references `ANTHROPIC_API_KEY` or any API-key-based authentication; every Claude surface listed there uses its own login flow. The line was removed rather than fixed. **A near-miss worth naming plainly: while writing the removal comment, the same `op://`-in-a-comment bug from Pass 18 was almost reintroduced** — an early draft of the "if this changes later" guidance included a literal example line with a real `op://` pattern inside a `#` comment, which would have broken `op inject` again the next time this file changed. Caught and corrected before shipping by re-running the same verification grep used in Pass 18, rather than assuming the standing rule written down in that pass would be followed automatically just because it existed in prose.

**What changed as a direct result of Pass 20:** `ANTHROPIC_API_KEY` removed from `dot_env.global.tpl` entirely, replaced with a comment explaining the decision and the exact steps to add it back later if ever needed (mirroring the now-corrected `GITHUB_TOKEN` pattern). The same fix applied to Section 4.8's own example block, which had been carrying the pre-Pass-19 broken field name (`/token`) in addition to the now-removed Claude API line — both corrected in the same pass rather than leaving a second stale copy of the old bug sitting in the document after the real file had already moved on.



[^1]: tech-insider.org, "Ghostty vs iTerm2 2026: 3x Throughput, 4x Memory Gap" (June 2026) — https://tech-insider.org/ghostty-vs-iterm2-2026/
[^2]: DevToolReviews, "Ghostty Terminal Review 2026: GPU-Accelerated Terminal Emulator" (May 2026) — https://www.devtoolreviews.com/reviews/ghostty-terminal-review-2026
[^3]: Sesame Disk, "Ghostty Terminal Review: Emulator Features and Performance" (March 2026) — https://sesamedisk.com/ghostty-terminal-emulator-review/
[^4]: Ghostty official release notes, "1.3.0 - Release Notes" (March 9, 2026) — https://ghostty.org/docs/install/release-notes/1-3-0 ; full release index at https://ghostty.org/docs/install/release-notes
[^5]: Releasebot, "Ghostty Release Notes - March 2026 Latest Updates" — https://releasebot.io/updates/ghostty
[^6]: Petronella Cybersecurity News, "Ghostty Terminal: Setup and Configuration Guide (2026)" — https://petronellatech.com/blog/ghostty-terminal-emulator-setup-configuration-guide-2026
[^7]: GitHub, jdx/mise official repository and README (current version 2026.7.5 as of July 9, 2026) — https://github.com/jdx/mise
[^8]: jdx/mise Releases, v2026.7.0 "Shell expansion by default, monorepo lockfiles, and task usage mounts" — https://github.com/jdx/mise/releases/tag/v2026.7.0
[^9]: mise-en-place official docs, "Bootstrap" — https://mise.jdx.dev/bootstrap.html
[^10]: jdx/mise Releases, v2026.6.14 "Bootstrap, end-to-end" — https://github.com/jdx/mise/releases/tag/v2026.6.14
[^11]: mise.usage.kdl / Arch manual pages, `mise bootstrap` subcommand reference — https://github.com/jdx/mise/blob/main/mise.usage.kdl ; https://man.archlinux.org/man/mise.1.en
[^12]: jdx/mise GitHub Discussion #10625, "Claude code install fail via mise bootstrap/brew" (community bug report, v2026.6.14) — https://github.com/jdx/mise/discussions/10625
[^13]: Codersera, "Cursor IDE Complete Guide 2026" (last updated May 1, 2026) — https://codersera.com/blog/cursor-ide-complete-guide-2026/
[^14]: Morph, "Cursor vs VS Code (2026): When Is the Fork Worth It?" (March 2026) — https://www.morphllm.com/comparisons/cursor-vs-vscode
[^15]: DataCamp, "Cursor vs. VS Code: Which One Is Right for You?" (March 2026) — https://www.datacamp.com/blog/cursor-vs-vs-code
[^16]: Uvik Software, "Claude Code vs Cursor vs Copilot vs Codex" — aggregates Stack Overflow (49,000 developers), JetBrains AI Pulse (10,000+ professional developers, January 2026), Google DORA 2025 (10,000+ respondents), Pragmatic Engineer survey (~900 senior engineers, February 2026), GitHub Octoverse, and vendor-reported metrics — https://uvik.net/blog/claude-code-vs-cursor-vs-copilot-vs-codex-2026/
[^17]: Ghostty official docs, "Terminfo" (help/terminfo) — https://ghostty.org/docs/help/terminfo
[^18]: Oleg Khomenko (Medium), "Fixing 'missing or unsuitable terminal: xterm-ghostty' when using Ghostty over SSH" (April 2026) — https://olegkhomenko.medium.com/fixing-missing-or-unsuitable-terminal-xterm-ghostty-when-using-ghostty-over-ssh-515c4a54eb72
[^19]: lzon.ca, "How to fix tmux over ssh in ghostty" (January 2026) — https://lzon.ca/posts/tips/ghostty-tmux-ssh/
[^20]: OrbStack official docs, "What's new" (release notes) — https://orbstack.dev/docs/release-notes
[^21]: Pitchfork official docs, "How Pitchfork Works" — https://pitchfork.jdx.dev/concepts/how-it-works.html ; "Quick Start" — https://pitchfork.jdx.dev/quickstart.html
[^22]: Pitchfork official docs, "mise Integration" — https://pitchfork.jdx.dev/guides/mise-integration.html
[^23]: Pitchfork official docs, "MCP Server (AI Assistants)" — https://pitchfork.jdx.dev/guides/mcp.html
[^24]: Entire CLI official GitHub repository (MIT license, v0.6.1, May 7 2026) — https://github.com/entireio/cli
[^25]: Usage Specification official docs — https://usage.jdx.dev/spec/
[^26]: Anthropic official Claude Code docs, "Advanced setup" (install methods, Homebrew channels, auto-update) — https://code.claude.com/docs/en/setup
[^27]: Homebrew Formulae index — `claude-code` cask — https://formulae.brew.sh/cask/claude-code ; `claude` (Desktop) cask — https://formulae.brew.sh/cask/claude
[^28]: DeusData/codebase-memory-mcp official GitHub repository (MIT license, v0.8.1, June 12 2026) — https://github.com/DeusData/codebase-memory-mcp
[^29]: Vogel, Meyer-Eschenbach, Kohler, Grünewald, Balzer, "Codebase-Memory: Tree-Sitter-Based Knowledge Graphs for LLM Code Exploration via MCP," arXiv:2603.27277 (submitted March 28, 2026) — https://arxiv.org/abs/2603.27277
[^30]: automationswitch.com, "Codebase Memory MCP MCP Server: Review and Connection Config" (independent third-party review citing OpenSSF Scorecard 5.8/10) — https://automationswitch.com/mcp-servers/codebase-memory-mcp
[^31]: DeusData/codebase-memory-mcp GitHub Issue #411, "index_repository(mode='moderate') silently drops entire subtrees from the indexed graph" (filed June 3, 2026) — https://github.com/DeusData/codebase-memory-mcp/issues/411
[^32]: DeusData/codebase-memory-mcp GitHub Issue #277, "New files not indexed — WAL-checkpoint blocked on successfully-indexed project" (filed April 20, 2026) — https://github.com/DeusData/codebase-memory-mcp/issues/277
[^33]: DeusData/codebase-memory-mcp GitHub Releases page, changelog crediting a "critical SQL injection and argument injection security fix" and the v0.8.1 local HTTP UI hardening (127.0.0.1 binding, strict HTTP/1.1 parsing, request limits) — https://github.com/DeusData/codebase-memory-mcp/releases
[^34]: Anthropic official Claude Code docs, "Choose a sandbox environment" — https://code.claude.com/docs/en/sandbox-environments
[^35]: DEV Community, "Running LLMs Locally on macOS: The Complete 2026 Comparison" — https://dev.to/bspann/running-llms-locally-on-macos-the-complete-2026-comparison-48fc
[^36]: Codersera, "Apple Silicon LLMs: Run AI Models on Mac (MLX, 2026)" (May 31, 2026) — https://codersera.com/blog/apple-silicon-llms-complete-guide-2026/
[^37]: 7 free AI tools that make LLM costs measurable in 2026 (ecorpit.com) — Helicone/Mintlify acquisition and maintenance-mode status; Langfuse/ClickHouse acquisition — https://ecorpit.com/free-ai-tools-measure-llm-costs-engineering-2026/
[^38]: buildmvpfast.com, "Langfuse vs Helicone vs Portkey: LLM Observability Compared" (March 29, 2026) — https://www.buildmvpfast.com/blog/llm-observability-stack-langfuse-helicone-portkey-2026
[^39]: Homebrew/brew GitHub Issue #21559, "brew bundle: use 'mas get' instead of 'mas install' for Mac App Store apps" (filed Feb 11, 2026, open/unresolved) — https://github.com/Homebrew/brew/issues/21559
[^40]: Apple Community discussion thread, "macOS Sequoia 15.7 — App Store won't install Xcode 26 (error after download completes)" (September 18, 2025) — https://discussions.apple.com/thread/256139393
[^41]: chezmoi official docs, "init" command reference — https://www.chezmoi.io/reference/commands/init/ ; "Quick start" — https://www.chezmoi.io/quick-start/
[^42]: chezmoi official docs, "Variables" (configuration file top-level keys, including the reserved `vault`/`vault.command` key for HashiCorp Vault integration) — https://www.chezmoi.io/reference/configuration-file/variables/
[^43]: Homebrew Formulae, "1password-cli" (confirms it is a cask, not a formula) — https://formulae.brew.sh/cask/1password-cli ; Homebrew Formulae, "zsh-fast-syntax-highlighting" (confirms real formula name) — https://formulae.brew.sh/formula/zsh-fast-syntax-highlighting
[^44]: Homebrew/homebrew-core, terraform.rb (disable! date: "2025-04-12", because: "changed its license to BUSL") — https://github.com/Homebrew/homebrew-core/blob/master/Formula/t/terraform.rb ; HashiCorp's own tap, hashicorp/homebrew-tap — install via `brew install hashicorp/tap/terraform`
[^45]: DeusData/codebase-memory-mcp GitHub Issue #491, "brew installation for macos?" (filed June 17, 2026, open/unresolved) — https://github.com/DeusData/codebase-memory-mcp/issues/491
[^46]: Homebrew official docs, "Tap Trust" (Homebrew 6.0.0, June 11, 2026 — third-party tap code requires explicit trust before Homebrew evaluates it; `trusted: true` syntax on `tap`/`brew`/`cask` Brewfile entries) — https://docs.brew.sh/Tap-Trust ; Homebrew Documentation, "Homebrew Bundle, brew bundle and Brewfile" — https://docs.brew.sh/Brew-Bundle-and-Brewfile
[^47]: Homebrew/homebrew-cask Pull Request #83144, "New cask: Linear.app" (original discussion establishing the `linear-linear` token and Homebrew maintainers' stated path to renaming it once cask-level rename support existed) — https://github.com/Homebrew/homebrew-cask/pull/83144 ; Homebrew Documentation, "brew(1) Manpage" (`brew migrate` command reference) — https://docs.brew.sh/Manpage
[^48]: Homebrew Formulae, "jordanbaird-ice" and "jordanbaird-ice@beta" (confirms the real cask tokens; "ice" alone has never existed as a cask) — https://formulae.brew.sh/cask/jordanbaird-ice ; https://formulae.brew.sh/cask/jordanbaird-ice@beta
[^49]: jordanbaird/Ice GitHub Issue #711, "Unable to display menu bar items" on macOS Tahoe 26.0 (25A354), Ice 0.11.13-dev.2 (filed September 25, 2025) — https://github.com/jordanbaird/Ice/issues/711
[^50]: MacPowerUsers Talk forum thread, "Is anyone else having trouble with the Ice menu bar manager?" — Ice crashing on macOS Tahoe 26.5 when clicking hidden menu bar items (June 9, 2026) — https://talk.macpowerusers.com/t/is-anyone-else-having-trouble-with-the-ice-menu-bar-manager/45789
[^51]: Jeff Triplett, "Jordan Baird's Ice beta fixed my macOS Tahoe menu bar issues" — confirms `jordanbaird-ice@beta` resolves the stable-release Tahoe crash (February 19, 2026) — https://micro.webology.dev/2026/02/19/jordan-bairds-ice-beta-fixed/
[^52]: TWiT.TV, "Take Full Control of Your macOS Tahoe Menu Bar" — native Menu Bar Controls in System Settings, no third-party app required (November 6, 2025) — https://twit.tv/posts/tech/take-full-control-your-macos-tahoe-menu-bar
[^53]: MacRumors, "10+ macOS Tahoe Features You Might Have Missed" — System Settings > Menu Bar > Menu Bar Controls walkthrough (October 3, 2025) — https://www.macrumors.com/guide/macos-tahoe-hidden-features/
[^54]: OS X Daily, "How to Declutter the Mac Menu Bar in macOS Tahoe" — user account of native controls eliminating the need for a third-party menu bar manager (May 7, 2026) — https://osxdaily.com/2026/05/07/declutter-mac-menu-bar-macos/
[^55]: Badgeify, "7 Best Free and Paid Bartender Alternatives for Mac in 2026" — native Tahoe Menu Bar Controls overview; reports macOS 27 Golden Gate adds a native overflow-icon expand button and breaks Bartender, Ice, Thaw, and Hidden Bar; Hidden Bar confirmed stable across all Tahoe betas and releases (April 17, 2026) — https://badgeify.app/top-3-bartender-free-alternatives-to-manage-your-mac-menu-bar/
[^56]: AppGrid, "Best macOS Tahoe App Launchers — Launchpad Replacements Compared" — confirms Launchpad's removal and the keyboard-first vs. grid-first launcher distinction (May 10, 2026) — https://appgridmac.com/best-app-launchers-for-macos-tahoe/
[^57]: Apple Community discussion, "New App Launcher in Tahoe 26.0.1" — confirms Launchpad replaced by Spotlight-based Apps view (October 27, 2025) — https://discussions.apple.com/thread/256174059
[^58]: Roberta Micore (Medium), "I Tested Every Mac Window Manager. Here's the One I'm Actually Using" — three-week comparison of native Tahoe tiling, Rectangle, Magnet, Moom, BetterTouchTool, and Raycast (April 2, 2026) — https://alltech.medium.com/i-tested-every-mac-window-manager-heres-the-one-i-m-actually-using-ae1f5c07a46c
[^59]: macOS WM Directory, "Raycast" — confirms Raycast's window management is a first-party built-in extension, not a separate tool — https://macoswm.com/wm/raycast
[^60]: Raycast Discount Code, "Raycast Window Management 2026: Replace Rectangle" — confirms feature coverage (halves, quarters, thirds, centering, multi-monitor) (March 2, 2026) — https://raycast-discount-code.com/blog/raycast-window-management
[^61]: MacMost, "How To Use the Spotlight Clipboard History In macOS Tahoe" (September 22, 2025) — https://macmost.com/how-to-use-the-spotlight-clipboard-history-in-macos-tahoe.html
[^62]: Cult of Mac, "Mac clipboard history: How to find and use it in macOS 26 Tahoe" (February 14, 2026) — https://www.cultofmac.com/how-to/mac-clipboard-history
[^63]: MacRumors, "Apple Expands Spotlight Clipboard Settings in macOS Tahoe 26.1" — confirms the original 8-hour cap and its extension to a configurable 30-minute/8-hour/7-day window (November 4, 2025) — https://www.macrumors.com/2025/11/04/more-spotlight-clipboard-settings-macos-26-1/
[^64]: ClipboardExtension.com, "macOS Tahoe Clipboard History" — independent review noting native clipboard history's limitations (no pinning, capped retention, basic search) relative to dedicated tools (July 8, 2025) — https://clipboardextension.com/articles/macos-tahoe-clipboard-history-review
[^65]: OrbStack official docs, "Settings" — confirms Rosetta is used by design to emulate Intel/x86 code at near-native speed on Apple Silicon — https://docs.orbstack.dev/settings
[^66]: orbstack/orbstack GitHub Issue #952, "Cannot open the app without Rosetta" — confirms OrbStack can block its own UI until Rosetta is installed (February 2, 2024) — https://github.com/orbstack/orbstack/issues/952
[^67]: lapcatsoftware.com, "macOS Containers and defaults" — explains why `defaults write com.apple.Safari` fails or silently writes to the wrong location depending on Full Disk Access, since Safari 13+ is sandboxed — https://lapcatsoftware.com/articles/containers.html
[^68]: ghostty-org/ghostty GitHub Discussion #8702, "Theme names changed in 1.2.0 breaking existing configs (catppuccin-mocha → Catppuccin Mocha)" (September 17, 2025) — https://github.com/ghostty-org/ghostty/discussions/8702
[^69]: DevToolBox Blog, "Starship Prompt Complete Guide 2026" — confirms tmux session display in Starship requires a `[custom.tmux_session]` module, not a built-in `[tmux_session]` module (February 28, 2026) — https://viadreams.cc/en/blog/starship-prompt-guide/
[^70]: jdx/mise GitHub Discussions #6796 and #5813, and sambaiz-net "Mise: the tool for managing language versions..." — confirm `gpg not found, skipping verification` is a non-blocking warning, with multiple reports showing successful installs immediately after it — https://github.com/jdx/mise/discussions/6796 ; https://github.com/jdx/mise/discussions/5813 ; https://www.sambaiz.net/en/article/536/
[^71]: 1Password Developer docs, "Use secret references with 1Password CLI"; Mykal Machon, "Setting up the 1Password CLI on WSL"; Atomic Object, "Effortlessly Generate Environment Files with 1Password" — real-world `op inject` template examples, none of which include explanatory comments containing the literal `op://` string, consistent with `op inject` text-scanning the whole file rather than respecting `#` as a comment marker — https://www.1password.dev/cli/secret-references ; https://mykalmachon.com/posts/setting-up-the-1-password-cli-on-wsl/ ; https://spin.atomicobject.com/file-generation-1password/
[^72]: 1Password Support, "1Password item categories" — confirms API Credential items include a field named `credential`, not `token` — https://support.1password.com/item-categories/ ; Ajeet Raina, "1Password + Docker Sandboxes: Keeping Secrets Out of the Box" — explicitly states "Items created as 1Password's API Credential category ... store the secret in a field literally named credential. That's why provider references end in /credential, not /token." — https://www.ajeetraina.com/securing-docker-sandboxes-a-quick-look-at-1password-credential-injection/

### Sources referenced in earlier audit passes (Tahoe/Golden Gate defaults, tool-coupling fixes) — not re-verified in this pass, retained for continuity

- macos-defaults.com (community-maintained, version-tested `defaults write` reference)
- Apple Community discussion threads, post-September 2025 (Tahoe-specific Dock/Finder/Keyboard/Trackpad regressions)
- mise-en-place official docs — Environments, Secrets, Cache Behavior, Settings, Troubleshooting, FAQs sections (https://mise.jdx.dev)
- jdx/mise GitHub Discussion #3712, "vaults/secrets management" (maintainer's direct statement on mise + 1Password architecture)
- 1Password Developer docs, "Use secret references with 1Password CLI" (https://www.1password.dev/cli/secret-references)
- kcrawford/dockutil GitHub repository (commit/PR activity through December 2025)
- Apple Developer, macOS 26 Tahoe and macOS 27 Golden Gate release notes and WWDC 2026 sessions

---

*Last updated: July 2026. Target OS: macOS Tahoe 26.5.2. Next OS audit: macOS Golden Gate 27 (September 2026). Citation audit pass: July 13, 2026 (this session).*
