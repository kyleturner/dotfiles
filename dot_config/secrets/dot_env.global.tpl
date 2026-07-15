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
#
# NOTE: for "API Credential" category items, 1Password's actual field name is
# "credential", not "token" -- confirmed against 1Password's own item-category docs.
# GITHUB_TOKEN below was originally written with /token, which does not exist as a
# field on this item type and caused a real "could not find item" resolution failure.
#
# NOTE: ANTHROPIC_API_KEY (Claude API / Anthropic API Platform) is intentionally NOT
# included here -- removed per direct user request. This machine uses Claude Code /
# Claude Desktop / Claude in Chrome etc. (subscription-based Claude apps), not the
# pay-per-token Anthropic API Platform, and the user does not want a Claude API
# Platform key provisioned or referenced at this time given per-token pricing and
# overage risk. If this changes later, add a line here following the same pattern as
# GITHUB_TOKEN below, pointing "op" + "://" at the right vault/item/credential.

GITHUB_TOKEN=op://Developer/GitHub-PAT/credential
