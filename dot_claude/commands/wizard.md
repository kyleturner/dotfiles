---
description: Start/report/stop wizard mode -- cross-project worktree health dashboard and orchestration co-pilot
argument-hint: "[stop]"
allowed-tools: Bash(~/.claude/skills/wizard-mode/*.sh), Bash(tmux:*), Bash(git:*), Bash(jq:*), Bash(yq:*), Bash(workmux:*), Bash(xcrun:*), Bash(ps:*), Bash(lsof:*), Bash(open:*), CronCreate, CronList, CronDelete, PushNotification
---

If `$ARGUMENTS` matches "stop", "stand down", or similar: follow the **On stand-down** section of `~/.claude/skills/wizard-mode/SKILL.md` only. Do not scan.

Otherwise: this is either the first manual invoke or a cron-fired pulse (same procedure either way). Follow `~/.claude/skills/wizard-mode/SKILL.md`'s **On invoke or pulse** section in full, including the active-session counting/wind-down logic and the alert-worthiness judgment calls it describes. Use the `wizard-mode` skill for all of the mechanics -- this command file is just the entry point.
