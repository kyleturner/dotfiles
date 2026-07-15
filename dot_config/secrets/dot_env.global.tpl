# dot_config/secrets/dot_env.global.tpl
# Contains 1Password secret references only -- no actual secrets. Safe to commit to a
# public repo. NOTE: do not write the literal "op" followed by "://" anywhere in a
# comment in this file -- op inject scans the whole file for that pattern and will try
# to parse anything after it as a real vault/item/field reference, even inside a "#"
# comment line. This caused a real "invalid secret reference" error on first run, when
# an earlier version of this file's own comment described the file using that exact
# string. Resolved into ~/.config/secrets/.env.global via `op inject`, run by
# .chezmoiscripts/run_onchange_after_50-resolve-secrets.sh.tmpl. The resolved output
# file is gitignored -- see the repo's .gitignore.
#
# Vault: "Developer" -- see macos-dev-workstation-ARCHIVE.md Section 4.8.

GITHUB_TOKEN=op://Developer/GitHub-PAT/token
ANTHROPIC_API_KEY=op://Developer/Claude API/credential
