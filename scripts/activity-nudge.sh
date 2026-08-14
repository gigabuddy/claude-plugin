#!/usr/bin/env bash
#
# Gigabuddy — PostToolUse hook: activity lifecycle nudges
#
# Deterministically nudges the agent to track real work as a Gigabuddy activity.
# Guidance alone doesn't fire reliably — the incident this fixes was a whole PR
# shipped with zero activity: no live log, no joinability, no handover surface,
# no closedown reflection. A hook fires regardless of what the model remembers.
#
# Two nudges, both best-effort (never block a tool), both rate-limited:
#   1. start     — a work-start signal fired AND no current activity is open
#                  → suggest start_activity.
#   2. midflight — an activity IS open AND the server says we should hand off
#                  soon (context filling) → suggest a midflight reflect_activity.
#
# Connected-only: the inbox file only exists when this session is in a Gigabuddy
# place, so the hook is silent everywhere else. `self.activityId` is the source
# of truth for "is there a current activity"; `self.shouldHandoff` triggers the
# midflight nudge. The scratch dir is shared with the MCP server, computed
# identically (project-local .gigabuddy), mirroring the awareness hooks.

set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$SESSION_ID" ] && exit 0

# Repo-root anchored so worktrees share one state dir with the MCP server.
# shellcheck source=lib/gigabuddy-dir.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/gigabuddy-dir.sh"
MYC_DIR="$(gigabuddy_dir)"
SDIR="$MYC_DIR/sessions/cc_$SESSION_ID"
INBOX="$SDIR/inbox.json"
[ -f "$INBOX" ] || exit 0   # not connected to a place → nothing to nudge

ACTIVITY_ID=$(jq -r '.self.activityId // empty' "$INBOX" 2>/dev/null || true)

NOW=$(date +%s)
NUDGE=""

if [ -z "$ACTIVITY_ID" ]; then
  # ---- (1) start nudge: detect a work-start signal --------------------------
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
  SIGNAL=""
  case "$TOOL_NAME" in
    TaskCreate)
      SIGNAL="a task list" ;;
    Edit|Write|MultiEdit)
      # Reuse the awareness outbox's deduped editedFiles list (written PreToolUse)
      # rather than recomputing — nudge once edits span a few files, since a
      # single one-file tweak rarely warrants an activity.
      OB="$SDIR/outbox.json"
      EDIT_COUNT=$(jq -r '(.editedFiles // []) | length' "$OB" 2>/dev/null || echo 0)
      [ "${EDIT_COUNT:-0}" -ge 3 ] 2>/dev/null && SIGNAL="edits across $EDIT_COUNT files"
      ;;
    Bash)
      CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
      case "$CMD" in
        *"git checkout -b"*|*"git switch -c"*) SIGNAL="a new branch" ;;
        *"git worktree add"*)                  SIGNAL="a new worktree" ;;
        *"git commit"*)                        SIGNAL="a commit" ;;
        *"gh pr create"*)                      SIGNAL="a pull request" ;;
      esac
      ;;
  esac

  if [ -n "$SIGNAL" ]; then
    # Rate-limit: at most 2 start nudges per session, >= 8 min apart, so a
    # deliberate "no activity" choice isn't nagged.
    NS="$SDIR/work-nudge.json"
    COUNT=0; LAST=0
    if [ -f "$NS" ]; then
      COUNT=$(jq -r '.count // 0' "$NS" 2>/dev/null || echo 0)
      LAST=$(jq -r '.ts // 0' "$NS" 2>/dev/null || echo 0)
    fi
    if [ "${COUNT:-0}" -lt 2 ] 2>/dev/null && [ "$(( NOW - LAST ))" -ge 480 ]; then
      NUDGE="You appear to be starting real work — $SIGNAL — but no Gigabuddy activity is open. Start one with start_activity (a short label) so peers can see and join the work, there's a live decision log, and a handover surface exists if this session ends mid-flight. If this isn't multi-step work, ignore this."
      printf '{"count":%s,"ts":%s}\n' "$(( COUNT + 1 ))" "$NOW" \
        > "$NS.tmp" 2>/dev/null && mv "$NS.tmp" "$NS" 2>/dev/null || true
    fi
  fi
else
  # An activity IS open. Three nudges, each one-shot:
  #   (2) closedown — the work LANDING (gh pr merge) is the wrap-up moment.
  #       Catching it here — while the agent is still working — means the Stop
  #       hook almost never has to block.
  #   (2b) warm-reflect — opening a PR / pushing is NOT a done signal (review
  #       hasn't happened), but it IS the last moment the context is warm, so
  #       nudge a reflection only. Deliberately does not consume the closedown
  #       one-shot: the merge (often a later session) still gets its nudge.
  #       This is the moment PR #1064 should have reflected but didn't.
  #   (3) midflight — context filling (server's shouldHandoff) → reflect before
  #       it's lost.
  LABEL=$(jq -r '.self.activityLabel // "your activity"' "$INBOX" 2>/dev/null || echo "your activity")

  DONE_SIGNAL=""
  LANDED=""
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
  if [ "$TOOL_NAME" = "Bash" ]; then
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
    case "$CMD" in
      *"gh pr merge"*)                  DONE_SIGNAL="merging a PR"; LANDED=1 ;;
      *"gh pr create"*|*"gh pr ready"*) DONE_SIGNAL="opening a PR" ;;
      *"git push"*)                     DONE_SIGNAL="pushing" ;;
    esac
  fi

  CS="$SDIR/closedown-nudge.json"
  PS="$SDIR/prreflect-nudge.json"
  RS="$SDIR/reflect-nudge.json"
  if [ -n "$LANDED" ] && [ ! -f "$CS" ]; then   # one-shot per session
    NUDGE="You're $DONE_SIGNAL with activity \"$LABEL\" still open — the work has landed. reflect_activity (assumptions, decisions, risks) then complete_activity with a 1-2 sentence plain-language summary (what changed from the reader's point of view — no PR numbers, deploy status, or component names; engineering detail goes in technicalSummary). If you're not actually done, ignore this. Subagents: ignore this entirely — report to your orchestrator, don't post."
    printf '{"ts":%s}\n' "$NOW" > "$CS.tmp" 2>/dev/null && mv "$CS.tmp" "$CS" 2>/dev/null || true
  elif [ -n "$DONE_SIGNAL" ] && [ ! -f "$PS" ]; then   # one-shot per session
    NUDGE="You're $DONE_SIGNAL with activity \"$LABEL\" still open. That is NOT a done signal — the work lands when the PR merges or a human signs off, so don't complete the activity or post any wrap-up to the place yet. It IS the moment your context is warmest: capture a reflection now (reflect_activity — assumptions, decisions, risks), then keep the activity open while the work is reviewed, or /handover if someone else will finish. Subagents: ignore this entirely — report to your orchestrator, don't post."
    printf '{"ts":%s}\n' "$NOW" > "$PS.tmp" 2>/dev/null && mv "$PS.tmp" "$PS" 2>/dev/null || true
  else
    SHOULD_HANDOFF=$(jq -r '.self.shouldHandoff // false' "$INBOX" 2>/dev/null || echo false)
    if [ "$SHOULD_HANDOFF" = "true" ] && [ ! -f "$RS" ]; then   # one-shot per session
      NUDGE="Your context is filling while activity \"$LABEL\" is still open. Capture a midflight reflection now (reflect_activity, trigger: midflight) so assumptions/decisions/risks aren't lost, and consider /handover if you won't finish this session."
      printf '{"ts":%s}\n' "$NOW" > "$RS.tmp" 2>/dev/null && mv "$RS.tmp" "$RS" 2>/dev/null || true
    fi
  fi
fi

if [ -n "$NUDGE" ]; then
  ESCAPED=$(printf 'Gigabuddy —\n%s' "$NUDGE" | jq -Rs .)
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$ESCAPED"
fi

exit 0
