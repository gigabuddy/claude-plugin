#!/usr/bin/env bash
#
# Gigabuddy — PreToolUse hook: UNATTENDED LOCKDOWN after a channel wake.
#
# A Claude Code channel event (a mention, ask, or thread reply addressed to
# this agent — see the agent server's channel bridge) starts a turn while the
# user is away, and it does so with the session's FULL permissions: channels
# have no unattended-mode concept of their own. This hook is the enforced
# half of the safety model. It is active only between a wake (the server
# stamps `unattended.json` BEFORE emitting the channel event) and the user's
# next real prompt (awareness-prompt.sh clears the stamp). While active, the
# woken turn is limited to conversation and read-only tools: it can read the
# thread, reply, and capture work with `raise` — it cannot edit files, run
# shell commands, or reach anything outside the plugin's collaboration
# surface. "A mention can get you an answer, but can't get your laptop to do
# things."
#
# HARD-DENY hook: unlike the other gigabuddy hooks this one intentionally
# blocks tool calls. It must therefore fail OPEN on its own errors (a broken
# guard must never brick an attended session) — every parse falls back to
# "allow".
#
# Lifted from PR #2516's oncall-guard.sh; the waiter that armed it there is
# replaced by the harness channel.

set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$SESSION_ID" ] && exit 0

# shellcheck source=lib/gigabuddy-dir.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/gigabuddy-dir.sh"
GB_DIR="$(gigabuddy_dir)"
SDIR="$GB_DIR/sessions/cc_$SESSION_ID"

# Not in an unattended window → allow (the common case, cheap).
[ -f "$SDIR/unattended.json" ] || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[ -z "$TOOL_NAME" ] && exit 0

# Allowlist: conversation + read-only.
case "$TOOL_NAME" in
  mcp__*gigabuddy*__*|mcp__*mycelium*__*) exit 0 ;;  # place collaboration tools (chat, raise, log, answer, …)
  Read|Grep|Glob|ToolSearch|TaskOutput|ListAgents|AskUserQuestion) exit 0 ;;
esac

REASON="Unattended lockdown: this turn was started by a channel event (someone addressed you in your Gigabuddy room) while the user is away, so only conversation and read-only tools are allowed — the gigabuddy tools, Read/Grep/Glob. Reply in the thread, capture any requested work with \`raise\`, and stop. The lockdown lifts when the user next types in this session. (Set GIGABUDDY_CHANNEL_GUARD=open before launching to disable it.)"
ESCAPED=$(printf '%s' "$REASON" | jq -Rs . 2>/dev/null) || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$ESCAPED"
exit 0
