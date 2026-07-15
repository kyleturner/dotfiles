# dot_config/secrets/dot_env.global.tpl
# op:// REFERENCES ONLY — no actual secrets. Safe to commit to a public repo.
# Resolved into ~/.config/secrets/.env.global via `op inject`, run by
# .chezmoiscripts/run_onchange_after_50-resolve-secrets.sh.tmpl. The resolved output
# file is gitignored — see the repo's .gitignore.
#
# Vault: "Developer" — see macos-dev-workstation-ARCHIVE.md Section 4.8.

GITHUB_TOKEN=op://Developer/GitHub-PAT/token
ANTHROPIC_API_KEY=op://Developer/Claude API/credential
