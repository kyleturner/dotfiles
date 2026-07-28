#!/usr/bin/env bash
# ~/.claude/skills/wizard-mode/render.sh
#
# Pure templating -- no judgment calls. Reads ~/.wizard/state.json (written
# by scan.sh) and writes a self-contained, auto-refreshing HTML dashboard to
# ~/.wizard/dashboard.html. Safe to run standalone against a stale
# state.json (e.g. to re-render the "stood down" footer without a new scan).
#
# Optional env vars, set by the SKILL.md-driven judgment layer:
#   WIZARD_FOOTER_NOTE   -- one-line status, e.g. "pulsing every 5 min" or
#                           "stood down at 14:32 -- active count dropped to 1"
set -euo pipefail

WIZARD_DIR="$HOME/.wizard"
STATE_FILE="$WIZARD_DIR/state.json"
OUT_FILE="$WIZARD_DIR/dashboard.html"
mkdir -p "$WIZARD_DIR"

if [ ! -f "$STATE_FILE" ]; then
  echo "render.sh: no $STATE_FILE yet -- run scan.sh first" >&2
  exit 1
fi

FOOTER_NOTE="${WIZARD_FOOTER_NOTE:-no pulse schedule reported}"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

JQ_PROGRAM="$SCRATCH/render.jq"
cat > "$JQ_PROGRAM" <<'JQ'
def esc: (. // "") | tostring | @html;

def sevColor:
  if . == "high" then "#e5484d"
  elif . == "medium" then "#f5a623"
  else "#8a8f98"
  end;

def statusLabel:
  if . == "working" then "🟢 working"
  elif . == "waiting" then "🟡 waiting"
  elif . == "done" then "⚪ done"
  else "❓ " + (. // "unknown")
  end;

def fmtElapsed:
  . as $s
  | if $s < 60 then ($s|tostring) + "s"
    elif $s < 3600 then (($s/60)|floor|tostring) + "m"
    else (($s/3600)|floor|tostring) + "h"
    end;

def worktreeCard($self):
  "<div class=\"card\">"
  + "<div class=\"card-head\"><span class=\"branch\">" + (.branch|esc) + "</span>"
  + (if .pane_id == $self then " <span class=\"tag self\">self</span>" else "" end)
  + "</div>"
  + "<div class=\"meta\">" + (.status|statusLabel) + " &middot; " + (.title|esc) + " &middot; " + (.elapsed_secs|fmtElapsed) + " elapsed</div>"
  + "<div class=\"meta\">"
  + (if .default_branch then
      ((.behind|tostring) + " behind / " + (.ahead|tostring) + " ahead " + (.default_branch|esc))
    else "no default branch detected" end)
  + "</div>"
  + (if .base.pipeline_line then
      "<div class=\"meta base\">base: <code>" + (.base.pipeline_line|esc) + "</code> ("
      + (.base.stages_complete|tostring) + "/" + (.base.stages_total|tostring)
      + " &middot; " + (.base.resolution|esc) + ")</div>"
    else
      "<div class=\"meta dim\">base: " + (.base.resolution|esc) + "</div>"
    end)
  + (if .ios.is_ios then
      "<div class=\"meta\">iOS: "
      + (if .ios.sim_target then (.ios.sim_target|esc) else "no active build detected" end)
      + (if .ios.false_green_risk then " <span class=\"tag high\">possible false-green</span>" else "" end)
      + "</div>"
    else "" end)
  + "<div class=\"files\">"
  + (.touched_files | if length == 0 then "no touched files"
     else (map(esc) | join(", ")) end)
  + "</div>"
  + "</div>";

def alertRow:
  "<tr><td><span class=\"badge\" style=\"background:" + (.severity|sevColor) + "\">" + (.severity|esc) + "</span></td>"
  + "<td>" + (.project|esc) + "</td>"
  + "<td>" + (.worktree|esc) + "</td>"
  + "<td>" + (.message|esc) + "</td>"
  + "<td><code>" + (.remediation|esc) + "</code></td></tr>";

. as $state
| ($state.self_pane_id // "") as $self
| ($state.alerts // []) as $alerts
| ($state.worktrees // []) as $worktrees
| ($state.projects // [] | map(
      . as $p
      | $p + {worktrees: ($worktrees | map(select(.project_root == $p.root)))}
    )
    | map(select(.worktrees | length > 0))
  ) as $activeProjects
| (if ($alerts | map(select(.severity=="high")) | length) > 0 then "high"
   elif ($alerts | length) > 0 then "medium"
   else "none" end) as $bannerLevel
| ($activeProjects | map(
      "<section class=\"project\"><h2>" + (.name|esc) + "</h2>"
      + "<div class=\"project-meta\">default: " + (.default_branch // "unknown"|esc)
      + " &middot; " + (.active_worktrees|tostring) + " active / " + (.total_worktrees|tostring) + " total worktrees"
      + (if .local_main_behind_origin > 0 then
          " &middot; local main " + (.local_main_behind_origin|tostring) + " behind origin (fetch before rebasing)"
        else "" end)
      + "</div>"
      + "<div class=\"cards\">" + (.worktrees | map(worktreeCard($self)) | join("")) + "</div>"
      + "</section>"
    ) | join("")
  ) as $projectsHtml
| 40 as $alertCap
| ($alerts | sort_by(.severity == "high" | not)) as $sortedAlerts
| (
  if ($alerts | length) == 0 then
    "<p class=\"dim\">No active collisions, contention, or false-green flags.</p>"
  else
    (if ($alerts | length) > $alertCap then
      "<p class=\"dim\">showing " + ($alertCap|tostring) + " of " + ($alerts|length|tostring)
      + " total (highest severity first) &mdash; " + (($alerts|length) - $alertCap|tostring)
      + " more truncated for display, full list in ~/.wizard/state.json</p>"
    else "" end)
    + "<table class=\"alerts\"><thead><tr><th>severity</th><th>project</th><th>worktree(s)</th><th>finding</th><th>suggested remediation</th></tr></thead><tbody>"
    + ($sortedAlerts[0:$alertCap] | map(alertRow) | join(""))
    + "</tbody></table>"
  end
  ) as $alertsHtml
| ($state.active_agent_count // 0) as $activeCount
| {
    bannerLevel: $bannerLevel,
    activeCount: $activeCount,
    projectsHtml: (if ($activeProjects|length) == 0 then "<p class=\"dim\">No active workmux-tracked agents right now.</p>" else $projectsHtml end),
    alertsHtml: $alertsHtml,
    generatedAt: ($state.generated_at // 0)
  }
JQ

RENDER_DATA="$(jq -f "$JQ_PROGRAM" "$STATE_FILE")"

banner_level="$(printf '%s' "$RENDER_DATA" | jq -r '.bannerLevel')"
active_count="$(printf '%s' "$RENDER_DATA" | jq -r '.activeCount')"
projects_html="$(printf '%s' "$RENDER_DATA" | jq -r '.projectsHtml')"
alerts_html="$(printf '%s' "$RENDER_DATA" | jq -r '.alertsHtml')"
generated_at="$(printf '%s' "$RENDER_DATA" | jq -r '.generatedAt')"
generated_human="$(date -r "$generated_at" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)"

case "$banner_level" in
  high) banner_class="banner-high"; banner_text="⚠ collisions/contention/false-green flags active" ;;
  medium) banner_class="banner-medium"; banner_text="findings need a look" ;;
  *) banner_class="banner-ok"; banner_text="no active collisions" ;;
esac

cat > "$OUT_FILE" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="30">
<title>Wizard Dashboard</title>
<style>
  :root { color-scheme: light dark; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    margin: 0; padding: 2rem; line-height: 1.45;
    background: #f7f7f8; color: #1a1a1a;
  }
  @media (prefers-color-scheme: dark) {
    body { background: #16161a; color: #e6e6e6; }
    .card, .project { background: #1f1f24; border-color: #333; }
    table.alerts { background: #1f1f24; }
    table.alerts th { background: #26262c; }
    code { background: #0d0d10; }
  }
  h1 { font-size: 1.3rem; margin: 0 0 0.5rem; }
  h2 { font-size: 1.05rem; margin: 0 0 0.5rem; }
  .banner {
    padding: 0.75rem 1rem; border-radius: 8px; font-weight: 600; margin-bottom: 1.5rem;
  }
  .banner-ok { background: #1e7d3226; border: 1px solid #1e7d3260; }
  .banner-medium { background: #f5a62326; border: 1px solid #f5a62360; }
  .banner-high { background: #e5484d26; border: 1px solid #e5484d60; }
  .project {
    border: 1px solid #ddd; border-radius: 10px; padding: 1rem; margin-bottom: 1.5rem; background: #fff;
  }
  .project-meta, .meta { font-size: 0.85rem; color: #666; margin: 0.15rem 0; }
  @media (prefers-color-scheme: dark) { .project-meta, .meta { color: #999; } }
  .cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 0.75rem; margin-top: 0.75rem; }
  .card { border: 1px solid #e2e2e2; border-radius: 8px; padding: 0.75rem; background: #fafafa; }
  .card-head { font-weight: 600; margin-bottom: 0.25rem; }
  .branch { font-family: ui-monospace, monospace; }
  .files { font-size: 0.78rem; color: #888; margin-top: 0.4rem; word-break: break-word; }
  .tag { font-size: 0.72rem; padding: 0.1rem 0.4rem; border-radius: 4px; }
  .tag.self { background: #4a90e2; color: #fff; }
  .tag.high { background: #e5484d; color: #fff; }
  .badge { color: #fff; font-size: 0.75rem; padding: 0.1rem 0.5rem; border-radius: 4px; }
  table.alerts { border-collapse: collapse; width: 100%; background: #fff; border-radius: 8px; overflow: hidden; }
  table.alerts th, table.alerts td { text-align: left; padding: 0.5rem 0.6rem; border-bottom: 1px solid #eee; font-size: 0.85rem; vertical-align: top; }
  table.alerts th { background: #f0f0f0; }
  code { background: #eee; padding: 0.1rem 0.3rem; border-radius: 4px; font-size: 0.8rem; }
  footer { margin-top: 2rem; font-size: 0.78rem; color: #888; }
  .dim { color: #888; }
</style>
</head>
<body>
<h1>🧙 Wizard Dashboard</h1>
<div class="banner ${banner_class}">${banner_text} &middot; ${active_count} active agent(s)</div>

<h2>Active worktrees</h2>
${projects_html}

<h2>Alerts</h2>
${alerts_html}

<footer>
  generated ${generated_human} &middot; ${FOOTER_NOTE}<br>
  wizard mode only runs while its invoking CLI session stays open (cron pulses are session-only and auto-expire after 7 days) -- a stale timestamp above means it stopped, not that everything is fine.
</footer>
</body>
</html>
HTML

echo "$OUT_FILE"
