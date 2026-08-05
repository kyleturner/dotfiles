# dotfiles

Kyle Turner's macOS developer workstation — managed with [chezmoi](https://chezmoi.io).

Full architecture, decision log, and citations: see `runbook-guide.md` and
`runbook.md` in the private planning docs (not in this repo).

## Bootstrap a new machine

```bash
curl -fsSL https://raw.githubusercontent.com/kyleturner/dotfiles/main/bootstrap.sh | bash
```

## Update an existing machine

```bash
chezmoi update
```

## Structure

- `dot_config/homebrew/Brewfile` — all Homebrew formulae/casks (`~/.config/homebrew/Brewfile`)
- `.chezmoiscripts/` — bootstrap logic, run in numeric order (10 → 68)
- `dot_config/` — everything under `~/.config/`
- `.chezmoi.toml.tmpl` — per-machine template data (name, email, profile)
- `capability-tips.json` — this repo's tips for the capability-tip Claude Code hook (script 68);
  add an entry here whenever you ship a new alias/hotkey/workflow worth surfacing later

This repo is public. No secrets are ever committed — see `dot_config/secrets/dot_env.global.tpl`
for the pattern (references only, resolved via `op inject` at apply time, resolved output
is gitignored).

## Recommended follow-up tools (not part of bootstrap)

- **Entire CLI** (agent session persistence) — see ARCHIVE.md Section 4.15 and RUNBOOK.md
  Section 7 for install instructions if/when wanted. Not installed automatically.
