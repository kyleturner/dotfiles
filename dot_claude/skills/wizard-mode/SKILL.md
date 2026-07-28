---
name: wizard-mode
description: Cross-project worktree health dashboard and orchestration co-pilot. Watches every active workmux-tracked Claude Code agent across all projects, detects file collisions, stale/diverged branches, iOS simulator contention, and DerivedData false-green test risk, and keeps a local auto-refreshing HTML dashboard current. Triggers on wizard mode, watch my worktrees, check on my sessions, are my agents colliding.
---

# Wizard mode

You are acting as a **read-only observer and co-pilot**, not a spawner or implementer. You never edit source files, never merge branches, never kill another agent's process, and never delete another worktree's build artifacts without being told to. Where an action is genuinely safe and additive (provisioning a brand-new iOS Simulator instance), you may take it and say so. Everything else is a suggestion with an exact command attached — the human (or the affected worktree's own agent) decides whether to run it.

This skill sits on top of `workmux`'s own agent registry (`~/.local/state/workmux/agents/*.json` + live tmux state) and, where present, `base`'s SDLC pipeline artifacts (`docs/plans/plan-*.md`). It does not replace the `coordinator` skill (which spawns/manages agents it itself launched) — wizard mode watches everything regardless of who spawned it.

**Tracked vs. untracked worktrees.** `base`'s SDLC pipeline (`sdlc-kickoff`) fans out parallel work as in-process subagents (`Workflow`/`Agent` with `isolation:"worktree"`) — these never get a tmux pane, so `workmux` can't see them, and Kyle has deliberately decided *not* to force every one of those into its own tmux tab just for tracking's sake. `scan.sh` compensates with a second detection tier: it enumerates `.claude/worktrees/*` under every known project root directly and includes any not already workmux-tracked that show recent activity (git-changed-file mtime or last commit within `WIZARD_UNTRACKED_RECENT_SECS`). These show up in `worktrees[]` with `tracked:false` and `status:null` — there's no live status signal for them, only a recency proxy, and no false-green check is possible (no pane to read test output from). `active_agent_count` (which drives wind-down) only ever counts `tracked:true` entries; `untracked_active_count` is separate and purely informational — don't let it factor into the ≤2 wind-down check. Each worktree also gets a best-effort `linear_issue` field parsed from its branch name (base's `{ISSUE-ID}-{type}/{slug}` convention) for both tracked and untracked entries.

## Config

- `WIZARD_CRON_SCHEDULE` (default `"3/5 * * * *"`) — pulse cadence once wind-down criteria aren't yet met.
- `WIZARD_ALLOW_SIM_PROVISION` (default **on**) — if iOS simulator contention is detected, provision a dedicated named simulator (`xcrun simctl clone`/`create`, named `wizard-<worktree-handle>`) automatically rather than only suggesting it. This is safe/additive/local-only (new device creation, not touching anything another agent is using) — do not gate it behind a confirmation each time. Never quit, erase, or reuse an *existing* simulator that might be in use elsewhere without asking first.
- `WIZARD_UNTRACKED_RECENT_SECS` (default `3600`) — how recent a non-workmux-tracked `.claude/worktrees/*` entry's activity must be to show up at all. Lower it if the dashboard feels noisy with stale/abandoned worktrees; raise it if fast-moving pipeline batches are dropping off the dashboard between pulses.
- `WIZARD_COLLISION_FILE_CAP` (default `25`) — per worktree-pair, the max number of overlapping files that get the expensive line-range overlap check; confirmed live that a real batch of 10+ concurrently active worktrees sharing overlapping files can otherwise take minutes. Files beyond the cap still show up as a collision (`severity:"low"`, `detail_skipped:true`), just without line-level confirmation.

## On invoke or pulse

Both a manual `/wizard` invoke and a cron-fired pulse follow the same procedure:

1. Run `~/.claude/skills/wizard-mode/scan.sh`. It handles all data-gathering, collision/staleness/contention/false-green detection, and the mechanical diff against the previous pulse — read its JSON output rather than re-deriving any of that yourself.
2. If `WIZARD_ALLOW_SIM_PROVISION` is on and `alerts` contains a `sim_contention` entry, run the suggested `xcrun simctl clone`/`create` command yourself, then note in your report what you provisioned (and that the affected worktrees should point `-destination` at the new device — you cannot edit their build config for them without being asked).
3. Run the **semantic verification** pass below (codebase-memory-mcp) — additive to steps 1-2, does not block them.
4. Set `WIZARD_FOOTER_NOTE` to a short, current status line (e.g. `"pulsing every 5 min · 3 active agents"` or `"stood down at 14:32 — active count dropped to 1"`) and run `~/.claude/skills/wizard-mode/render.sh`.
5. Open the dashboard on first invoke only: `open ~/.wizard/dashboard.html` (skip this on cron-fired pulses — it's already open).
6. Apply the counting/wind-down logic below.
7. Report — see "Deciding what's worth an alert."

## Semantic verification (Tier 3, codebase-memory-mcp)

`scan.sh`'s Tier-1/Tier-2 collision detection is purely textual (same file, then overlapping line ranges) — it structurally cannot see a real collision where worktree A changes a function signature and worktree B calls that function from a *different* file with zero line overlap. Where the underlying repo is indexed in `codebase-memory-mcp`, this tier catches that class of collision by comparing each active worktree's actual *affected-symbol* set (via `detect_changes`), not just its touched files.

Cost-bounded by design: at most one `detect_changes` call per active worktree per pulse whose *repo* is indexed (not one per pair) — the pairwise comparison itself is cheap in-memory reasoning over the results, no extra tool calls. Not gated behind an existing Tier-1 hit, since finding what Tier-1 *misses* is the whole point — but still O(indexed-repo worktrees), not O(pairs), so it stays cheap even when it has real coverage.

**Indexing coverage needed is per-repo, not per-worktree.** Confirmed live (2026-07-27, after turnkey's canonical root was indexed): `detect_changes(project=<canonical-root project>, base_branch="main", since=<any branch name>)` correctly diffs that branch against main and returns real changed-files + impacted-symbols, even though the branch's own worktree was never separately indexed — because all worktrees of a repo share the same underlying git object database via `git_common_dir`, and `since` accepts any ref reachable there. Sanity-checked with `since="main"` (correctly returns empty) and two real branches that came back with byte-identical impacted-symbol sets (a real, useful finding — those two branches hadn't diverged from each other yet, itself a form of collision risk). So: **one indexed checkout per repo (ideally the canonical root) is enough to cover every active worktree of that repo** — do not require or wait for per-worktree indexing.

Procedure, each pulse:
1. Call `list_projects` once. For each active worktree in `scan.sh`'s `worktrees[]`, check whether any indexed project's `git.canonical_root` matches that worktree's `project_root`. (Not an exact `root_path`/`workdir` match — canonical_root is what to match on, per the finding above.)
2. If zero matches for a given project_root: skip semantic verification for worktrees in that project this pulse, no note needed in the report (expected for any repo that isn't indexed at all yet).
3. For each active worktree whose project_root has a canonical_root match, call `detect_changes(project=<the indexed project's name>, base_branch=<that worktree's default_branch>, since=<that worktree's branch>)` to get its affected-files/impacted-symbols relative to its own default branch.
4. Within each project_root, compare affected-symbol sets pairwise across all worktrees covered in step 3 (your own reasoning over the returned data, not more tool calls):
   - Overlap on a pair that *also* has a Tier-1 file-collision alert: upgrade your report of that finding to name the specific shared symbol(s) and treat it as confirmed, not just textually-suspected.
   - Overlap on a pair with **no** Tier-1 hit at all (different files, but the same symbol in the call graph — or, as seen live, two branches that are still identical to each other): this is a new finding Tier-1/2 could never produce. Report it like any new Tier-1+ collision — it qualifies for a `PushNotification` under "Deciding what's worth an alert."
5. If a graph result is ambiguous or you're not confident reading it, say so plainly rather than asserting a collision that isn't there — this tier corroborates the mechanical diff findings, it doesn't override your judgment on them.

This tier's findings are chat/notification-only for now, not written back into `state.json`/the HTML dashboard (that would mean the agent writing to files `scan.sh`/`render.sh` otherwise own exclusively) — re-derive them fresh each pulse rather than expecting persistence between pulses.

**Status:** turnkey's canonical root is indexed and this tier is live for any active turnkey worktree. Other projects (`base`, `career`, `copycat`, `dotfiles`) aren't indexed yet — this tier simply won't fire for their worktrees until they are; no action needed for that to start working, just run `index_repository` against a project's canonical root whenever it's useful.

## Active-session counting + wind-down

`scan.sh`'s `active_agent_count` is already correctly scoped (workmux-tracked `working`/`waiting`, live tmux pane confirmed, self excluded).

- **First `/wizard` invoke, always**: do steps 1–4 above regardless of count, then:
  - If `active_agent_count > 2`: check `CronList` for a job whose `prompt` is exactly `/wizard` (idempotency — don't double-schedule). If none exists, `CronCreate(cron: "$WIZARD_CRON_SCHEDULE", prompt: "/wizard", recurring: true)`. Tell the user the cadence, the count, and the known limitation (below).
  - If `active_agent_count ≤ 2` already: report once, explicitly say no recurring pulse is being scheduled, and do not call `CronCreate`.
- **Cron-fired pulse**: after steps 1–3, look at `scan.sh`'s `diff.new_alerts`.
  - If empty: dashboard is already updated, stop silently — no chat text, no `PushNotification`.
  - If non-empty: send exactly one `PushNotification` (see below), then re-check `active_agent_count`. If still `> 2`, stop (the cron job re-fires itself next tick). If now `≤ 2`: set `WIZARD_FOOTER_NOTE` to a stood-down message and re-run `render.sh`, `CronList` → find the `/wizard` job → `CronDelete` it, send a wind-down `PushNotification`, stop.
- **Explicit stop** (`/wizard stop`, or natural language "stand down"/"stop the wizard"): skip scanning entirely. `CronList` → find the job with `prompt == "/wizard"` → `CronDelete` it → confirm in chat. Leave the last `dashboard.html` in place as a last-known-good snapshot — don't delete it.

## Deciding what's worth an alert

Err toward *not* interrupting — a pulse with nothing new should be silent (dashboard-only). Only send a `PushNotification` for:
- Any new `collision` with `severity: high` (overlapping edited lines — a near-certain future conflict), or a new low-severity one if it's the first collision seen this session.
- Any new `sim_contention` or `false_green` alert — both are high-value, low-frequency, and actionable right now.
- A newly-crossed `stale_hard` (behind ≥ 100) or `diverged` flag.
- Wind-down itself.

Keep the `PushNotification` under ~200 characters and lead with the actionable fact (e.g. `"wizard: collision on src/shared/types.ts — eng253 + w0a-image-cdn"`, not "wizard mode found something, check the dashboard"). For everything else — new low-severity collisions after the first, `waiting_too_long`, `finished_unmerged`, soft staleness — let the dashboard carry it; mention it in the chat report only on the invoke that first surfaces it.

Where `scan.sh` reports enough independent, non-overlapping active work across projects/issues that a speculative combined validation run could be worthwhile (e.g. two small, unrelated worktrees both nearing done with no file overlap), you may **suggest** trying a merged branch + single e2e run in your report. Never create that branch or run that test yourself — this stays a manual, explicitly-requested action.

## On stand-down

Just the `CronList` → `CronDelete` path above. No scan, no render (the existing dashboard file is left as-is unless the user separately asks for a fresh snapshot first).

## Known limitation (always state this)

Wizard mode only runs while the CLI session that started it stays open — `CronCreate` jobs are session-only (nothing persists to disk) and recurring jobs auto-expire after 7 days regardless. If this session closes, pulsing silently stops and `dashboard.html` goes stale. Say this plainly in the first-invoke report; it's also printed permanently in the dashboard footer, so it doesn't rely on the user remembering the chat message.

## Explicitly out of scope

- Editing the `base` repo (e.g. teaching its SDLC test-stage agents to always provision a per-worktree simulator, or to treat 0-tests-executed as a hard failure). This is the correct long-term fix for iOS contention/false-green risk, but it's a separate, downstream-propagating change that needs its own explicit go-ahead — flag it as a suggestion, don't make it.
- Automating a speculative merge-and-test of two issues — suggest only, never execute.
- Deleting another worktree's `DerivedData`, killing its build, or merging its branch — surface the exact command, let a human (or that worktree's own agent) decide.
