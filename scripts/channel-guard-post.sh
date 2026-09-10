#!/usr/bin/env bash
#
# Gigabuddy — PostToolUse hook: the other half of the UNATTENDED LOCKDOWN.
#
# channel-guard.sh (PreToolUse) confines a channel-started turn and, for a
# sponsor or trusted wake, escalates each tool call to an "ask" — Claude Code's
# permission dialog, relayed to the sponsor as a consent request. Two people
# can answer that dialog: the sponsor from the card in the room (the bridge
# then emits the verdict over the channel), or the human AT THE KEYBOARD.
#
# The second one is the point of this hook. A human pressing "Yes" on this
# machine is exactly the "user next types" signal the lockdown waits for —
# they are here, watching the turn — but a dialog answer is not a prompt, so
# awareness-prompt.sh never sees it. Without this hook the human sits through
# an approval per tool call for the rest of a turn they are supervising.
#
# HOW it tells them apart — the call that just ran must be the one the guard
# escalated (asked.json: tool, tool_use_id, agent_id, when), and:
#   - the bridge recorded an allow verdict for that tool at or after the ask
#     (relay-verdict.json, written by channel.ts before it answers the
#     prompt) → the SPONSOR answered from the room. One verdict, one call:
#     the lockdown stands, the marker is consumed.
#   - no such verdict → nobody but the keyboard could have approved it. The
#     human is present: clear the stamps exactly as a prompt would.
# A "No" never reaches here (a denied tool does not run), so nothing lifts on
# a refusal. A tool the policy allows outright was never asked, so it does not
# lift either — asked.json is written only on an ask.
#
# Best-effort and fail-OPEN like every gigabuddy hook: PostToolUse cannot
# block, and an error here must leave the stamps exactly as they were.

set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$SESSION_ID" ] && exit 0

# shellcheck source=lib/gigabuddy-dir.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/gigabuddy-dir.sh"
GB_DIR="$(gigabuddy_dir)"
SDIR="$GB_DIR/sessions/cc_$SESSION_ID"

# Only inside a lockdown (same two-file test as the PreToolUse guard).
[ -f "$SDIR/unattended.json" ] || exit 0
[ -f "$SDIR/turn-ended.json" ] || exit 0
ASKED="$SDIR/asked.json"
[ -f "$ASKED" ] || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[ -z "$TOOL_NAME" ] && exit 0
TOOL_USE_ID=$(printf '%s' "$INPUT" | jq -r '.tool_use_id // empty' 2>/dev/null || true)
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null || true)

ASK=$(cat "$ASKED" 2>/dev/null || echo '{}')
A_TOOL=$(printf '%s' "$ASK" | jq -r '.tool // empty' 2>/dev/null || true)
A_USE=$(printf '%s' "$ASK" | jq -r '.toolUseId // empty' 2>/dev/null || true)
A_AGENT=$(printf '%s' "$ASK" | jq -r '.agentId // empty' 2>/dev/null || true)
A_TS=$(printf '%s' "$ASK" | jq -r '.ts // empty' 2>/dev/null || true)

# The call that ran must be the call that was asked: same tool, same thread
# (main turn vs a specific subagent), and the same tool_use_id when the
# harness gives us one on both sides.
[ "$A_TOOL" = "$TOOL_NAME" ] || exit 0
[ "$A_AGENT" = "$AGENT_ID" ] || exit 0
if [ -n "$A_USE" ] && [ -n "$TOOL_USE_ID" ] && [ "$A_USE" != "$TOOL_USE_ID" ]; then exit 0; fi

# Did the sponsor answer it from the room? The bridge writes relay-verdict.json
# for every allow it emits, before emitting it.
RV="$SDIR/relay-verdict.json"
if [ -f "$RV" ]; then
  R_TOOL=$(jq -r '.toolName // empty' "$RV" 2>/dev/null || true)
  R_TS=$(jq -r '.ts // empty' "$RV" 2>/dev/null || true)
  RELAYED=$(jq -n --arg a "$A_TS" --arg r "$R_TS" '
    def iso: sub("\\.[0-9]+"; "") | try fromdateiso8601 catch null;
    (($a | iso) as $ask | ($r | iso) as $rv | $ask != null and $rv != null and $rv >= $ask)' 2>/dev/null || echo false)
  if [ "$R_TOOL" = "$TOOL_NAME" ] && [ "$RELAYED" = "true" ]; then
    # Relayed: one verdict covered one call. The human is still away.
    rm -f "$RV" "$ASKED" 2>/dev/null || true
    exit 0
  fi
fi

# Nobody else could have pressed Yes: the human is at the keyboard. Lift the
# lockdown exactly as their next prompt would (awareness-prompt.sh step 0).
WHO=$(jq -r '.from // "someone"' "$SDIR/unattended.json" 2>/dev/null || echo someone)
rm -f "$SDIR/unattended.json" "$SDIR/turn-ended.json" "$SDIR/locked-spawn.json" "$ASKED" "$RV" 2>/dev/null || true

MSG="Unattended lockdown lifted: the user approved that $TOOL_NAME call at the keyboard, so they are present — this turn (started by a wake from $WHO) now runs with the session's normal permissions, the same as if they had typed. Treat their approval as sponsorship of the work you are doing, not as a blanket for unrelated actions."
ESCAPED=$(printf '%s' "$MSG" | jq -Rs . 2>/dev/null) || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$ESCAPED"
exit 0
