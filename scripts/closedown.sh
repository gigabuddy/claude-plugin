#!/usr/bin/env bash
#
# Gigabuddy — Stop hook: closedown BACKSTOP (advisory)
#
# The common closedown case is caught in-flow by activity-nudge.sh, which nudges
# reflect + complete the moment a PR is opened / pushed / merged (the natural
# lifecycle signals), while the agent is still working. This Stop hook is the
# backstop ONLY for sessions those signals never fired in: investigation/doc
# work, a PR made via the web, a session that just ends. If any in-flow lifecycle
# nudge already fired this session, this hook stays silent — the agent was
# already reminded at a better moment, and Stop fires at the end of EVERY turn
# (not "session end"), so re-nudging here lands mid-work far more often than at
# a real wrap-up.
#
# The reminder itself is advisory, not a directive: stopping with an open
# activity is often correct (work in flight, awaiting review, blocked on a
# human). It only asks for reflect + complete when the work has actually landed
# and the agent is walking away — that's the orphaned-activity case this exists
# to catch.
#
# Bounded: at most ONE forced continuation per session — it respects
# `stop_hook_active` and a one-shot flag, so the agent is never trapped in a loop.
#
# Best-effort and connected-only, like the other hooks: silent when there's no
# inbox (not in a place) or no open activity.

set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$SESSION_ID" ] && exit 0

# Already continuing from a previous stop-hook block → let it stop (loop guard).
STOP_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Repo-root anchored so worktrees share one state dir with the MCP server.
# shellcheck source=lib/gigabuddy-dir.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/gigabuddy-dir.sh"
MYC_DIR="$(gigabuddy_dir)"
SDIR="$MYC_DIR/sessions/cc_$SESSION_ID"
INBOX="$SDIR/inbox.json"
[ -f "$INBOX" ] || exit 0

ACTIVITY_ID=$(jq -r '.self.activityId // empty' "$INBOX" 2>/dev/null || true)
[ -z "$ACTIVITY_ID" ] && exit 0   # no open activity → clean stop

# If an in-flow lifecycle nudge (activity-nudge.sh) already fired this session,
# the agent has already been reminded at a better-timed moment — stay silent.
for NUDGED in "$SDIR/closedown-nudge.json" \
              "$SDIR/prreflect-nudge.json" \
              "$SDIR/reflect-nudge.json"; do
  [ -f "$NUDGED" ] && exit 0
done

# One-shot: only ever nudge once per session, so we never trap the agent.
SN="$SDIR/stop-nudge.json"
[ -f "$SN" ] && exit 0
printf '{"ts":%s}\n' "$(date +%s)" > "$SN.tmp" 2>/dev/null && mv "$SN.tmp" "$SN" 2>/dev/null || true

LABEL=$(jq -r '.self.activityLabel // "your activity"' "$INBOX" 2>/dev/null || echo "your activity")
REASON="Heads-up, not a to-do: this session still has an open Gigabuddy activity, \"$LABEL\". An open activity at stop time is often correct — if the work is still in flight (awaiting review, blocked on a person, a monitor armed, or you're just pausing), leave it open and simply stop; no reflection or completion is needed now. Only if the work has LANDED (merged, or a human confirmed it's done) and you're wrapping up for good: reflect_activity, then complete_activity with a short plain-language \`summary\`. If you're ending for good mid-work, prefer /handover so the next session can pick it up. Subagents: never complete or post — report to your orchestrator. (Fires once per session; stopping again immediately with no action is a fine response.)"

ESCAPED=$(printf '%s' "$REASON" | jq -Rs .)
printf '{"decision":"block","reason":%s}\n' "$ESCAPED"
exit 0
