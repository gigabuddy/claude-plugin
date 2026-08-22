#!/usr/bin/env bash
#
# Gigabuddy — Stop hook: the staged session's end-of-turn prompt
#
# Session kernel (decision:85dxOsnuuz2L; plan page:o2nInoTllp4w §7): an agent
# conversation working inside a STAGED SESSION produces pages / ideas /
# decisions that stay with the session until it publishes ONE digest to the
# room. "Conversation end" for an agent is the end of a turn — there is no
# later moment the model can still act in (SessionEnd cannot inject context).
# So at Stop, when the focused activity is a staged session, nudge the three
# ways forward: session_publish / keep open / complete_activity. Close ≠
# discard: nothing here ever closes or deletes anything — sessions are
# durable handles; leaving one open is always safe.
#
# Rate-limited (one nudge per 10 minutes per session) so a long working
# conversation isn't nagged every turn, and silent when the session isn't
# staged or not connected. Reads only the inbox file the MCP server writes —
# hooks have no network and no MCP access.

set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$SESSION_ID" ] && exit 0

# shellcheck source=lib/gigabuddy-dir.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/gigabuddy-dir.sh"
MYC_DIR="$(gigabuddy_dir)"
SDIR="$MYC_DIR/sessions/cc_$SESSION_ID"
INBOX="$SDIR/inbox.json"
[ -f "$INBOX" ] || exit 0   # not connected → nothing to say

MODE=$(jq -r '.self.sessionMode // empty' "$INBOX" 2>/dev/null || true)
[ "$MODE" = "staged" ] || exit 0
ACTIVITY_ID=$(jq -r '.self.activityId // empty' "$INBOX" 2>/dev/null || true)
LABEL=$(jq -r '.self.activityLabel // empty' "$INBOX" 2>/dev/null || true)
[ -n "$ACTIVITY_ID" ] || exit 0

NOW=$(date +%s)
NS="$SDIR/session-close-nudge.json"
LAST=0
[ -f "$NS" ] && LAST=$(jq -r '.ts // 0' "$NS" 2>/dev/null || echo 0)
[ "$(( NOW - LAST ))" -ge 600 ] || exit 0
printf '{"ts":%s}\n' "$NOW" > "$NS.tmp" 2>/dev/null && mv "$NS.tmp" "$NS" 2>/dev/null || true

MSG="Staged session open: \"$LABEL\" ($ACTIVITY_ID). Anything you produced in it is not in the room yet. Before you stop: session_review $ACTIVITY_ID to see the change set, then either session_publish $ACTIVITY_ID (ONE digest lands in the room; default set = everything pending, session_annotate to opt items out), keep it open (it is durable — nothing is lost; publish later), or complete_activity when the work has landed (it refuses while change is unpublished unless allowUnpublished:true). Never discard — unpublished work stays attributed to the session."

jq -n --arg msg "$MSG" '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":$msg}}' 2>/dev/null || true
exit 0
