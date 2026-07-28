#!/usr/bin/env bash
# ~/.claude/skills/wizard-mode/scan.sh
#
# Mechanical data-gathering pass for wizard mode. No judgment calls live
# here -- see SKILL.md for what to do with this output. This script only
# gathers facts (workmux agent registry, live tmux state, per-worktree git
# state, base pipeline stage, iOS build contention, DerivedData false-green
# risk) and does pure set-comparison against the previous pulse.
#
# Bash 3.2-safe (system bash, no Homebrew bash assumed) -- no associative
# arrays, no mapfile, no ${var,,}. Requires: git, jq, yq, tmux (optional),
# workmux (optional), lsof, ps.
#
# Emits one JSON object to stdout, and also persists it to
# ~/.wizard/state.json (rotating the previous one to state.prev.json first).
set -euo pipefail

WIZARD_DIR="$HOME/.wizard"
STATE_FILE="$WIZARD_DIR/state.json"
PREV_FILE="$WIZARD_DIR/state.prev.json"
mkdir -p "$WIZARD_DIR"

# Rotate before this pulse's new state is computed, so the diff at the end
# compares against what was true immediately before this run.
if [ -f "$STATE_FILE" ]; then
  cp "$STATE_FILE" "$PREV_FILE"
fi
[ -f "$PREV_FILE" ] || echo '{}' > "$PREV_FILE"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

now_epoch="$(date +%s)"
self_pane="${TMUX_PANE:-}"

# ---------------------------------------------------------------------------
# 1. Global, cheap, one-shot reads
# ---------------------------------------------------------------------------

if command -v tmux >/dev/null 2>&1 && [ -n "${TMUX:-}" ]; then
  tmux list-panes -a -F '#{pane_id}|#{pane_title}' > "$SCRATCH/panes.txt" 2>/dev/null || : > "$SCRATCH/panes.txt"
else
  : > "$SCRATCH/panes.txt"
fi

: > "$SCRATCH/agents_raw.jsonl"
if [ -d "$HOME/.local/state/workmux/agents" ]; then
  for f in "$HOME/.local/state/workmux/agents"/*.json; do
    [ -e "$f" ] || continue
    jq -c . "$f" >> "$SCRATCH/agents_raw.jsonl" 2>/dev/null || true
  done
fi
jq -s '.' "$SCRATCH/agents_raw.jsonl" > "$SCRATCH/agents_raw.json" 2>/dev/null || echo '[]' > "$SCRATCH/agents_raw.json"

: > "$SCRATCH/project_roots.txt"
if [ -d "$HOME/.config/tmuxp" ]; then
  for f in "$HOME/.config/tmuxp"/*.yaml; do
    [ -e "$f" ] || continue
    [ "$(basename "$f")" = "_template.yaml" ] && continue
    dir="$(yq -r '.start_directory // ""' "$f" 2>/dev/null || true)"
    [ -n "$dir" ] || continue
    printf '%s\n' "${dir/#\~/$HOME}"
  done | sort -u > "$SCRATCH/project_roots.txt"
fi

cut -d'|' -f1 "$SCRATCH/panes.txt" | jq -R -s 'split("\n") | map(select(length>0))' > "$SCRATCH/live_pane_ids.json"

# ---------------------------------------------------------------------------
# 2. Filter to "active": workmux-tracked working/waiting, pane still alive,
#    and not this invoking session itself.
# ---------------------------------------------------------------------------

jq --slurpfile panes "$SCRATCH/live_pane_ids.json" --arg self "$self_pane" '
  ($panes[0]) as $live
  | map(
      (.pane_key.pane_id // .pane_id // "") as $pid
      | select(
          (.status == "working" or .status == "waiting")
          and ($live | index($pid)) != null
          and $pid != $self
        )
      | . + {_pane_id: $pid}
    )
' "$SCRATCH/agents_raw.json" > "$SCRATCH/active_agents.json"

# Drop entries whose worktree directory no longer exists on disk (a live
# tmux pane can outlive a `workmux remove`/merge that deleted the worktree
# it was tracking -- confirmed live: a "waiting" agent can point at a
# workdir that's already gone). Keep active_agent_count consistent with
# what actually gets scanned below rather than silently over-counting.
: > "$SCRATCH/active_agents.jsonl"
n_raw_active="$(jq 'length' "$SCRATCH/active_agents.json")"
k=0
while [ "$k" -lt "$n_raw_active" ]; do
  candidate="$(jq -c ".[$k]" "$SCRATCH/active_agents.json")"
  k=$((k + 1))
  cand_workdir="$(printf '%s' "$candidate" | jq -r '.workdir // empty')"
  if [ -n "$cand_workdir" ] && [ -d "$cand_workdir" ]; then
    printf '%s\n' "$candidate" >> "$SCRATCH/active_agents.jsonl"
  fi
done
jq -s '.' "$SCRATCH/active_agents.jsonl" > "$SCRATCH/active_agents.json" 2>/dev/null || echo '[]' > "$SCRATCH/active_agents.json"

active_count="$(jq 'length' "$SCRATCH/active_agents.json")"

# ---------------------------------------------------------------------------
# 2.5 Untracked-but-active worktrees: enumerate .claude/worktrees/* directly
#     under each known project root. In-process SDLC pipeline subagents
#     (base's sdlc-kickoff, via Workflow/Agent isolation:"worktree") never
#     get a tmux pane, so workmux never tracks them -- this is the only way
#     to know they exist. There's no live "status" signal for these, so
#     "active" is a recency heuristic: most recent changed-file mtime (or
#     last commit) within WIZARD_UNTRACKED_RECENT_SECS. Purely informational
#     -- never counted toward active_agent_count, which stays keyed on
#     confirmed-live tracked agents only (that's what wind-down depends on).
# ---------------------------------------------------------------------------

UNTRACKED_RECENT_SECS="${WIZARD_UNTRACKED_RECENT_SECS:-3600}"

last_activity_ts_for() {
  local workdir="$1" newest=0 ts
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -e "$workdir/$f" ] || continue
    ts="$(stat -f %m "$workdir/$f" 2>/dev/null || echo 0)"
    [ -n "$ts" ] || ts=0
    if [ "$ts" -gt "$newest" ]; then newest="$ts"; fi
  done < <(git -C "$workdir" status --porcelain=v1 --untracked-files=normal 2>/dev/null | cut -c4- | sed 's/.* -> //')
  if [ "$newest" -eq 0 ]; then
    newest="$(git -C "$workdir" log -1 --format=%ct 2>/dev/null || echo 0)"
    [ -n "$newest" ] || newest=0
  fi
  printf '%s' "$newest"
}

jq -r '.[].workdir' "$SCRATCH/active_agents.json" > "$SCRATCH/tracked_workdirs.txt" 2>/dev/null || : > "$SCRATCH/tracked_workdirs.txt"

: > "$SCRATCH/untracked_candidates.jsonl"
while IFS= read -r root; do
  [ -n "$root" ] || continue
  [ -d "$root/.claude/worktrees" ] || continue
  for wt in "$root/.claude/worktrees"/*; do
    [ -d "$wt" ] || continue
    [ -e "$wt/.git" ] || continue
    grep -qxF "$wt" "$SCRATCH/tracked_workdirs.txt" 2>/dev/null && continue
    last_ts="$(last_activity_ts_for "$wt")"
    [ -n "$last_ts" ] || last_ts=0
    age=$((now_epoch - last_ts))
    if [ "$last_ts" -gt 0 ] && [ "$age" -le "$UNTRACKED_RECENT_SECS" ]; then
      jq -n --arg workdir "$wt" --argjson status_ts "$last_ts" \
        '{workdir:$workdir, tracked:false, pane_id:"", status:"", status_ts:$status_ts, pane_title:"", session_name:""}' \
        >> "$SCRATCH/untracked_candidates.jsonl"
    fi
  done
done < "$SCRATCH/project_roots.txt"

jq '[.[] | . + {tracked:true, pane_id: (._pane_id // "")}]' "$SCRATCH/active_agents.json" > "$SCRATCH/tracked_candidates.json" 2>/dev/null || echo '[]' > "$SCRATCH/tracked_candidates.json"
jq -s '.' "$SCRATCH/untracked_candidates.jsonl" > "$SCRATCH/untracked_candidates.json" 2>/dev/null || echo '[]' > "$SCRATCH/untracked_candidates.json"
jq -s 'add' "$SCRATCH/tracked_candidates.json" "$SCRATCH/untracked_candidates.json" > "$SCRATCH/candidates.json" 2>/dev/null || echo '[]' > "$SCRATCH/candidates.json"

# ---------------------------------------------------------------------------
# 3. Per candidate worktree (tracked + untracked-but-recent) -- mechanical
#    git / base / iOS checks
# ---------------------------------------------------------------------------

find_project_root() {
  local workdir="$1" best=""
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    case "$workdir" in
      "$root"|"$root"/*)
        if [ "${#root}" -gt "${#best}" ]; then best="$root"; fi
        ;;
    esac
  done < "$SCRATCH/project_roots.txt"
  printf '%s' "$best"
}

default_branch_for() {
  local root="$1" db=""
  db="$(git -C "$root" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  if [ -z "$db" ]; then
    if git -C "$root" show-ref --verify --quiet refs/heads/main 2>/dev/null; then
      db="main"
    elif git -C "$root" show-ref --verify --quiet refs/heads/master 2>/dev/null; then
      db="master"
    fi
  fi
  printf '%s' "$db"
}

: > "$SCRATCH/worktrees.jsonl"
: > "$SCRATCH/sim_targets.tsv"
: > "$SCRATCH/project_roots_seen.txt"

# One process-table snapshot for the whole pulse, reused by every iOS
# worktree below -- avoids re-scanning all system processes once per
# worktree when several are active at once.
ps -eo pid=,command= 2>/dev/null | grep -E 'xcodebuild|simctl' | grep -v grep > "$SCRATCH/xcode_procs.txt" || : > "$SCRATCH/xcode_procs.txt"

idx=0
count_candidates="$(jq 'length' "$SCRATCH/candidates.json")"
while [ "$idx" -lt "$count_candidates" ]; do
  entry="$(jq -c ".[$idx]" "$SCRATCH/candidates.json")"
  idx=$((idx + 1))

  workdir="$(printf '%s' "$entry" | jq -r '.workdir // empty')"
  [ -n "$workdir" ] && [ -d "$workdir" ] || continue

  tracked="$(printf '%s' "$entry" | jq -r '.tracked')"
  pane_id="$(printf '%s' "$entry" | jq -r '.pane_id // empty')"
  status="$(printf '%s' "$entry" | jq -r '.status // empty')"
  status_ts="$(printf '%s' "$entry" | jq -r '.status_ts // 0')"
  session_name="$(printf '%s' "$entry" | jq -r '.session_name // empty')"
  cached_title="$(printf '%s' "$entry" | jq -r '.pane_title // empty')"
  live_title=""
  if [ -n "$pane_id" ]; then
    live_title="$(grep -F "${pane_id}|" "$SCRATCH/panes.txt" 2>/dev/null | head -1 | cut -d'|' -f2- || true)"
  fi
  title="${live_title:-$cached_title}"
  handle="$(basename "$workdir")"

  project_root="$(find_project_root "$workdir")"
  if [ -n "$project_root" ]; then
    echo "$project_root" >> "$SCRATCH/project_roots_seen.txt"
  else
    project_root="$workdir"
  fi
  project_name="$(basename "$project_root")"

  default_branch="$(default_branch_for "$project_root")"
  branch="$(git -C "$workdir" branch --show-current 2>/dev/null || true)"
  [ -n "$branch" ] || branch="(detached)"

  # base's branch convention is {ISSUE-ID}-{type}/{slug} (e.g. ENG-132-fix/...)
  linear_issue="$(printf '%s' "$branch" | grep -oE '^[A-Z][A-Z0-9]*-[0-9]+' | head -1 || true)"

  merge_base=""
  ahead=0
  behind=0
  if [ -n "$default_branch" ]; then
    merge_base="$(git -C "$workdir" merge-base "$default_branch" HEAD 2>/dev/null || true)"
    ab="$(git -C "$workdir" rev-list --left-right --count "${default_branch}...HEAD" 2>/dev/null || true)"
    if [ -n "$ab" ]; then
      behind="$(printf '%s' "$ab" | awk '{print $1}')"
      ahead="$(printf '%s' "$ab" | awk '{print $2}')"
    fi
  fi
  [ -n "$behind" ] || behind=0
  [ -n "$ahead" ] || ahead=0

  touched_files_json="$(
    {
      git -C "$workdir" status --porcelain=v1 --untracked-files=normal 2>/dev/null | cut -c4- | sed 's/.* -> //'
      if [ -n "$merge_base" ]; then
        git -C "$workdir" diff --name-only "$merge_base" HEAD 2>/dev/null
      fi
    } | sort -u | jq -R -s 'split("\n") | map(select(length>0))'
  )"

  # base pipeline stage -- best-effort. Format varies across real plan files
  # (different stage labels, markers, sometimes an HTML-comment wrapper), so
  # we deliberately don't parse into a rigid enum -- just surface the raw
  # line plus a loosely-derived count.
  plan_file="" resolution="not base-tracked" pipeline_line=""
  if [ -n "$merge_base" ]; then
    plan_file="$(git -C "$workdir" diff --name-only "$merge_base" HEAD -- docs/plans/ 2>/dev/null | head -1 || true)"
    [ -n "$plan_file" ] && resolution="branch diff"
  fi
  if [ -z "$plan_file" ] && [ -d "$workdir/docs/plans" ]; then
    plan_file="$(cd "$workdir" && ls -t docs/plans/plan-*.md 2>/dev/null | head -1 || true)"
    [ -n "$plan_file" ] && resolution="newest plan (unconfirmed)"
  fi
  if [ -n "$plan_file" ] && [ -f "$workdir/$plan_file" ]; then
    pipeline_line="$(grep -m1 -E 'Pipeline:' "$workdir/$plan_file" 2>/dev/null || true)"
  fi
  stages_complete=0
  stages_total=0
  if [ -n "$pipeline_line" ]; then
    stages_complete="$(printf '%s' "$pipeline_line" | grep -o '✅' | wc -l | tr -d ' ')"
    stages_total="$(printf '%s' "$pipeline_line" | awk -F'·' '{print NF}')"
  fi

  # iOS/Xcode: is this worktree an Xcode project? (maxdepth 4 covers e.g.
  # turnkey/apps/baja-casas-ios/BajaCasas.xcodeproj)
  is_ios=false
  if find "$workdir" -maxdepth 4 \( -iname "*.xcodeproj" -o -iname "*.xcworkspace" -o -iname "Package.swift" \) 2>/dev/null | grep -q .; then
    is_ios=true
  fi

  sim_target=""
  false_green=false
  if [ "$is_ios" = "true" ]; then
    # Correlate any running xcodebuild/simctl process back to this worktree
    # via its cwd, and note which simulator device it's targeting.
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      pid="$(printf '%s' "$line" | awk '{print $1}')"
      [ -n "$pid" ] || continue
      cwd="$(lsof -p "$pid" -a -d cwd 2>/dev/null | awk 'NR>1{print $NF}' || true)"
      case "$cwd" in
        "$workdir"|"$workdir"/*)
          dest="$(printf '%s' "$line" | grep -oE "platform=iOS Simulator,name=[^'\"]*" | head -1 || true)"
          [ -n "$dest" ] && sim_target="$dest"
          printf '%s\t%s\t%s\n' "${sim_target:-unknown}" "$handle" "$pid" >> "$SCRATCH/sim_targets.tsv"
          ;;
      esac
    done < "$SCRATCH/xcode_procs.txt"

    # False-green signature: "TEST SUCCEEDED" co-occurring with 0 tests
    # executed -- the known DerivedData staleness trap. Needs a real pane to
    # read output from, so this only runs for tmux/workmux-tracked agents;
    # untracked (in-process subagent) worktrees have no terminal to capture.
    if [ "$tracked" = "true" ]; then
      capture=""
      if [ -n "$pane_id" ] && command -v tmux >/dev/null 2>&1; then
        capture="$(tmux capture-pane -p -t "$pane_id" -S -300 2>/dev/null || true)"
      fi
      if [ -z "$capture" ] && command -v workmux >/dev/null 2>&1; then
        capture="$(workmux capture "$handle" -n 300 2>/dev/null || true)"
      fi
      if printf '%s' "$capture" | grep -q 'TEST SUCCEEDED' && printf '%s' "$capture" | grep -qE 'Executed 0 tests'; then
        false_green=true
      fi
    fi
  fi

  jq -n \
    --argjson tracked "$tracked" \
    --arg workdir "$workdir" --arg handle "$handle" --arg pane_id "$pane_id" \
    --arg status "$status" --argjson status_ts "${status_ts:-0}" --arg title "$title" \
    --arg session_name "$session_name" --arg project_root "$project_root" --arg project_name "$project_name" \
    --arg default_branch "$default_branch" --arg branch "$branch" --arg linear_issue "$linear_issue" \
    --argjson ahead "$ahead" --argjson behind "$behind" \
    --argjson touched_files "$touched_files_json" \
    --arg plan_file "$plan_file" --arg pipeline_line "$pipeline_line" --arg resolution "$resolution" \
    --argjson stages_complete "${stages_complete:-0}" --argjson stages_total "${stages_total:-0}" \
    --argjson is_ios "$is_ios" --arg sim_target "$sim_target" --argjson false_green "$false_green" \
    --argjson now "$now_epoch" \
    '{
      workdir: $workdir, handle: $handle, tracked: $tracked,
      pane_id: ($pane_id | if length>0 then . else null end),
      status: ($status | if length>0 then . else null end),
      status_ts: $status_ts,
      title: ($title | if length>0 then . else null end),
      session_name: ($session_name | if length>0 then . else null end),
      project_root: $project_root, project_name: $project_name,
      default_branch: ($default_branch | if length>0 then . else null end),
      linear_issue: ($linear_issue | if length>0 then . else null end),
      branch: $branch, ahead: $ahead, behind: $behind,
      touched_files: $touched_files,
      base: {
        plan_file: ($plan_file | if length>0 then . else null end),
        pipeline_line: ($pipeline_line | if length>0 then . else null end),
        resolution: $resolution,
        stages_complete: $stages_complete, stages_total: $stages_total
      },
      ios: {
        is_ios: $is_ios,
        sim_target: ($sim_target | if length>0 then . else null end),
        false_green_risk: $false_green
      },
      elapsed_secs: ($now - $status_ts)
    }' >> "$SCRATCH/worktrees.jsonl"
done

jq -s '.' "$SCRATCH/worktrees.jsonl" > "$SCRATCH/worktrees.json" 2>/dev/null || echo '[]' > "$SCRATCH/worktrees.json"

# ---------------------------------------------------------------------------
# 4. Per project root (once) -- total worktree count, local-main-behind-origin
# ---------------------------------------------------------------------------

sort -u "$SCRATCH/project_roots_seen.txt" > "$SCRATCH/project_roots_unique.txt" 2>/dev/null || : > "$SCRATCH/project_roots_unique.txt"

: > "$SCRATCH/projects.jsonl"
while IFS= read -r root; do
  [ -n "$root" ] || continue
  total_worktrees="$(git -C "$root" worktree list --porcelain 2>/dev/null | grep -c '^worktree ' || true)"
  [ -n "$total_worktrees" ] || total_worktrees=0
  db="$(default_branch_for "$root")"
  local_behind_origin=0
  if [ -n "$db" ]; then
    local_behind_origin="$(git -C "$root" rev-list --count "HEAD..origin/${db}" 2>/dev/null || true)"
    [ -n "$local_behind_origin" ] || local_behind_origin=0
  fi
  active_here="$(jq --arg root "$root" '[.[] | select(.project_root == $root)] | length' "$SCRATCH/worktrees.json")"
  tracked_active_here="$(jq --arg root "$root" '[.[] | select(.project_root == $root and .tracked==true)] | length' "$SCRATCH/worktrees.json")"
  untracked_active_here="$(jq --arg root "$root" '[.[] | select(.project_root == $root and .tracked==false)] | length' "$SCRATCH/worktrees.json")"
  jq -n --arg name "$(basename "$root")" --arg root "$root" --arg db "$db" \
    --argjson total "$total_worktrees" --argjson local_behind "$local_behind_origin" --argjson active "$active_here" \
    --argjson tracked_active "$tracked_active_here" --argjson untracked_active "$untracked_active_here" \
    '{name:$name, root:$root, default_branch:($db|if length>0 then . else null end), total_worktrees:$total, local_main_behind_origin:$local_behind, active_worktrees:$active, tracked_active_worktrees:$tracked_active, untracked_active_worktrees:$untracked_active}' \
    >> "$SCRATCH/projects.jsonl"
done < "$SCRATCH/project_roots_unique.txt"
jq -s '.' "$SCRATCH/projects.jsonl" > "$SCRATCH/projects.json" 2>/dev/null || echo '[]' > "$SCRATCH/projects.json"

# ---------------------------------------------------------------------------
# 5. Collision detection: Tier 1 (same file touched in >=2 worktrees of the
#    same repo) -> Tier 2 (do their changed line-ranges actually overlap?)
# ---------------------------------------------------------------------------

is_noise() {
  case "$1" in
    package-lock.json|yarn.lock|pnpm-lock.yaml|bun.lock|bun.lockb|Cargo.lock|go.sum|Gemfile.lock|poetry.lock|uv.lock|.DS_Store) return 0 ;;
    dist/*|build/*|.next/*|coverage/*|*/dist/*|*/build/*|*/.next/*|*/coverage/*) return 0 ;;
    *.generated.*) return 0 ;;
    *) return 1 ;;
  esac
}

hunk_bounds() {
  # "@@ -a,b +c,d @@" -> "c c+d" (1-indexed start, exclusive end)
  local line="$1" plus start len
  plus="$(printf '%s' "$line" | grep -oE '\+[0-9]+(,[0-9]+)?' | head -1)"
  start="${plus#+}"
  case "$start" in
    *,*) len="${start#*,}"; start="${start%,*}" ;;
    *) len=1 ;;
  esac
  printf '%s %s\n' "$start" "$((start + len))"
}

# Tier-2 detail (git diff -U0 per file) is the expensive part -- with
# several concurrently active worktrees in one repo sharing large
# overlapping touched-file sets (confirmed live: turnkey regularly has 10+
# active baja-casas-ios worktrees at once), a naive per-pair-per-file diff
# is O(worktrees^2 * files) subprocess spawns and can run for minutes. Two
# mitigations: (1) cache each (workdir, file) hunk-range computation once
# and reuse it across every pair that needs it, instead of recomputing per
# pair; (2) cap Tier-2 detail to the first WIZARD_COLLISION_FILE_CAP
# overlapping files per pair -- files beyond the cap are still reported as
# Tier-1 collisions (severity "low"), just tagged detail_skipped so nothing
# silently vanishes from the dashboard, only the line-level confirmation.
COLLISION_FILE_CAP="${WIZARD_COLLISION_FILE_CAP:-25}"
mkdir -p "$SCRATCH/rangecache"

ranges_for() {
  local workdir="$1" mergebase="$2" file="$3" key h cachefile
  key="${workdir}|${file}"
  h="$(printf '%s' "$key" | cksum | awk '{print $1}')"
  cachefile="$SCRATCH/rangecache/$h"
  if [ ! -f "$cachefile" ]; then
    if [ -n "$mergebase" ]; then
      git -C "$workdir" diff -U0 --no-color "$mergebase" -- "$file" 2>/dev/null | grep -E '^@@' > "$cachefile" || : > "$cachefile"
    else
      : > "$cachefile"
    fi
  fi
  cat "$cachefile"
}

n_wt="$(jq 'length' "$SCRATCH/worktrees.json")"
: > "$SCRATCH/collisions.jsonl"

i=0
while [ "$i" -lt "$n_wt" ]; do
  j=$((i + 1))
  while [ "$j" -lt "$n_wt" ]; do
    a="$(jq -c ".[$i]" "$SCRATCH/worktrees.json")"
    b="$(jq -c ".[$j]" "$SCRATCH/worktrees.json")"
    root_a="$(printf '%s' "$a" | jq -r '.project_root')"
    root_b="$(printf '%s' "$b" | jq -r '.project_root')"
    if [ "$root_a" = "$root_b" ]; then
      handle_a="$(printf '%s' "$a" | jq -r '.handle')"
      workdir_a="$(printf '%s' "$a" | jq -r '.workdir')"
      db_a="$(printf '%s' "$a" | jq -r '.default_branch // empty')"
      handle_b="$(printf '%s' "$b" | jq -r '.handle')"
      workdir_b="$(printf '%s' "$b" | jq -r '.workdir')"
      db_b="$(printf '%s' "$b" | jq -r '.default_branch // empty')"

      # Merge-base only depends on the pair, not the file -- compute once
      # per pair instead of once per (pair, file).
      mb_a=""; mb_b=""
      [ -n "$db_a" ] && mb_a="$(git -C "$workdir_a" merge-base "$db_a" HEAD 2>/dev/null || true)"
      [ -n "$db_b" ] && mb_b="$(git -C "$workdir_b" merge-base "$db_b" HEAD 2>/dev/null || true)"

      files_a="$(printf '%s' "$a" | jq -r '.touched_files[]' 2>/dev/null || true)"
      file_count=0
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        is_noise "$f" && continue
        if ! printf '%s' "$b" | jq -e --arg f "$f" '.touched_files | index($f) != null' >/dev/null 2>&1; then
          continue
        fi
        low_signal="false"
        [ "$f" = "docs/routing-ledger.jsonl" ] && low_signal="true"
        file_count=$((file_count + 1))

        severity="low"
        detail_skipped="false"
        if [ "$file_count" -gt "$COLLISION_FILE_CAP" ]; then
          detail_skipped="true"
        elif [ -n "$mb_a" ] && [ -n "$mb_b" ]; then
          ranges_for "$workdir_a" "$mb_a" "$f" > "$SCRATCH/ranges_a.txt"
          ranges_for "$workdir_b" "$mb_b" "$f" > "$SCRATCH/ranges_b.txt"
          if [ -s "$SCRATCH/ranges_a.txt" ] && [ -s "$SCRATCH/ranges_b.txt" ]; then
            overlap="false"
            while IFS= read -r ra; do
              [ -n "$ra" ] || continue
              read -r sa ea <<< "$(hunk_bounds "$ra")"
              while IFS= read -r rb; do
                [ -n "$rb" ] || continue
                read -r sb eb <<< "$(hunk_bounds "$rb")"
                if [ "$sa" -lt "$eb" ] && [ "$sb" -lt "$ea" ]; then
                  overlap="true"
                fi
              done < "$SCRATCH/ranges_b.txt"
            done < "$SCRATCH/ranges_a.txt"
            [ "$overlap" = "true" ] && severity="high"
          fi
        fi

        jq -n --arg project "$root_a" --arg pname "$(basename "$root_a")" --arg file "$f" \
          --arg ha "$handle_a" --arg hb "$handle_b" --arg sev "$severity" --argjson low "$low_signal" \
          --argjson skipped "$detail_skipped" \
          '{project_root:$project, project_name:$pname, file:$file, worktrees:[$ha,$hb], severity:$sev, low_signal: $low, detail_skipped: $skipped}' \
          >> "$SCRATCH/collisions.jsonl"
      done <<EOF
$files_a
EOF
    fi
    j=$((j + 1))
  done
  i=$((i + 1))
done
jq -s '.' "$SCRATCH/collisions.jsonl" > "$SCRATCH/collisions.json" 2>/dev/null || echo '[]' > "$SCRATCH/collisions.json"

# ---------------------------------------------------------------------------
# 6. iOS simulator contention: same sim target, >=2 distinct worktrees
# ---------------------------------------------------------------------------

: > "$SCRATCH/sim_contention.jsonl"
if [ -s "$SCRATCH/sim_targets.tsv" ]; then
  cut -f1 "$SCRATCH/sim_targets.tsv" | sort -u > "$SCRATCH/sim_targets_unique.txt"
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    awk -F'\t' -v t="$target" '$1==t{print $2}' "$SCRATCH/sim_targets.tsv" | sort -u > "$SCRATCH/sim_handles.txt"
    count="$(grep -c . "$SCRATCH/sim_handles.txt" || true)"
    [ -n "$count" ] || count=0
    if [ "$count" -gt 1 ]; then
      handles_json="$(jq -R -s 'split("\n")|map(select(length>0))' "$SCRATCH/sim_handles.txt")"
      first_handle="$(head -1 "$SCRATCH/sim_handles.txt")"
      jq -n --arg target "$target" --argjson worktrees "$handles_json" --arg first "$first_handle" \
        '{sim_target:$target, worktrees:$worktrees, remediation: ("xcrun simctl clone \"<booted-udid-for-" + $target + ">\" \"wizard-" + $first + "\"")}' \
        >> "$SCRATCH/sim_contention.jsonl"
    fi
  done < "$SCRATCH/sim_targets_unique.txt"
fi
jq -s '.' "$SCRATCH/sim_contention.jsonl" > "$SCRATCH/sim_contention.json" 2>/dev/null || echo '[]' > "$SCRATCH/sim_contention.json"

# ---------------------------------------------------------------------------
# 7. Staleness / false-green / waiting-too-long alerts (from worktrees.json)
# ---------------------------------------------------------------------------

jq --argjson now "$now_epoch" '
  [ .[] |
    (
      (if (.ahead > 0 and .behind > 0) then
        [{type:"diverged", severity:"high", project:.project_name, worktree:.handle,
          message:("diverged: " + (.ahead|tostring) + " ahead / " + (.behind|tostring) + " behind " + (.default_branch // "default branch")),
          remediation:("rebase or merge " + (.default_branch // "main") + " into " + .branch)}]
       else [] end)
      + (if (.behind >= 100) then
          [{type:"stale_hard", severity:"high", project:.project_name, worktree:.handle,
            message:((.behind|tostring) + " behind " + (.default_branch // "default branch") + " -- significantly stale"),
            remediation:"consider rebasing or abandoning this branch"}]
         elif (.behind >= 20) then
          [{type:"stale_soft", severity:"low", project:.project_name, worktree:.handle,
            message:((.behind|tostring) + " behind " + (.default_branch // "default branch")),
            remediation:"consider rebasing"}]
         else [] end)
      + (if (.status=="done" and .ahead>0 and (($now - .status_ts) > 86400)) then
          [{type:"finished_unmerged", severity:"medium", project:.project_name, worktree:.handle,
            message:"finished over 24h ago but never merged",
            remediation:("workmux send " + .handle + " \"/merge\"")}]
         else [] end)
      + (if (.status=="waiting" and (($now - .status_ts) > 600)) then
          [{type:"waiting_too_long", severity:"medium", project:.project_name, worktree:.handle,
            message:("waiting on you for " + ((($now - .status_ts)/60)|floor|tostring) + "m"),
            remediation:("workmux capture " + .handle)}]
         else [] end)
      + (if .ios.false_green_risk then
          [{type:"false_green", severity:"high", project:.project_name, worktree:.handle,
            message:"TEST SUCCEEDED with 0 tests executed -- likely stale/corrupted DerivedData",
            remediation:("rm -rf " + .workdir + "/DerivedData  # then rebuild clean (do not run this on another agent'"'"'s in-flight worktree without checking first)")}]
         else [] end)
    )
  ] | flatten
' "$SCRATCH/worktrees.json" > "$SCRATCH/staleness_alerts.json" 2>/dev/null || echo '[]' > "$SCRATCH/staleness_alerts.json"

jq -n --slurpfile a "$SCRATCH/staleness_alerts.json" --slurpfile c "$SCRATCH/collisions.json" --slurpfile s "$SCRATCH/sim_contention.json" '
  ($a[0]) as $stale
  | ($c[0] | map({type:"collision", severity:.severity, project:.project_name, worktree:(.worktrees|join(" + ")),
      message:("file collision: " + .file + (if .low_signal then " (low-signal: append-only)" else "" end)),
      remediation:"review both diffs before either merges"})) as $coll
  | ($s[0] | map({type:"sim_contention", severity:"high", project:"-", worktree:(.worktrees|join(" + ")),
      message:("simulator contention on " + .sim_target), remediation:.remediation})) as $sim
  | ($stale + $coll + $sim)
' > "$SCRATCH/alerts.json"

# ---------------------------------------------------------------------------
# 8. Diff vs. previous pulse -- pure set comparison, mechanical
# ---------------------------------------------------------------------------

prev_active="$(jq '.active_agent_count // 0' "$PREV_FILE" 2>/dev/null || echo 0)"
[ -n "$prev_active" ] || prev_active=0
jq '[(.alerts // [])[] | (.type + "|" + .project + "|" + .worktree + "|" + .message)]' "$PREV_FILE" > "$SCRATCH/prev_alert_keys.json" 2>/dev/null || echo '[]' > "$SCRATCH/prev_alert_keys.json"

jq --slurpfile prevkeys "$SCRATCH/prev_alert_keys.json" '
  ($prevkeys[0]) as $pk
  | map(select((.type + "|" + .project + "|" + .worktree + "|" + .message) as $k | ($pk | index($k)) == null))
' "$SCRATCH/alerts.json" > "$SCRATCH/new_alerts.json" 2>/dev/null || echo '[]' > "$SCRATCH/new_alerts.json"

# ---------------------------------------------------------------------------
# 9. Final assembly -- write state.json and emit to stdout
# ---------------------------------------------------------------------------

untracked_active_count="$(jq '[.[] | select(.tracked==false)] | length' "$SCRATCH/worktrees.json")"

jq -n \
  --argjson generated_at "$now_epoch" \
  --arg self_pane "$self_pane" \
  --argjson active_agent_count "$active_count" \
  --argjson untracked_active_count "$untracked_active_count" \
  --slurpfile worktrees "$SCRATCH/worktrees.json" \
  --slurpfile projects "$SCRATCH/projects.json" \
  --slurpfile collisions "$SCRATCH/collisions.json" \
  --slurpfile alerts "$SCRATCH/alerts.json" \
  --slurpfile new_alerts "$SCRATCH/new_alerts.json" \
  --argjson prev_active_count "$prev_active" \
  '{
    generated_at: $generated_at,
    self_pane_id: $self_pane,
    active_agent_count: $active_agent_count,
    untracked_active_count: $untracked_active_count,
    worktrees: $worktrees[0],
    projects: $projects[0],
    collisions: $collisions[0],
    alerts: $alerts[0],
    diff: {
      active_count_prev: $prev_active_count,
      active_count_delta: ($active_agent_count - $prev_active_count),
      new_alerts: $new_alerts[0]
    }
  }' | tee "$STATE_FILE"
