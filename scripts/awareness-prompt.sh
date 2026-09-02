#!/usr/bin/env bash
#
# Gigabuddy — UserPromptSubmit hook
#
# Runs at the start of each turn. Three jobs:
#   1. Register this Claude Code session so the MCP server can auto-connect
#      with a stable identity (writes a pending-connect file the server polls).
#   2. Re-baseline the agent on the full current peer state of the place.
#   3. First-run onboarding nudges: not-signed-in (once per session) and
#      statusline-not-configured (once ever) — both agent-mediated offers,
#      since neither can be automated at plugin-install time.
#
# Best-effort throughout: never fail the prompt. The scratch dir is shared
# with the MCP server and is computed identically (project-local .gigabuddy).

set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$SESSION_ID" ] && exit 0

# Repo-root anchored so worktrees share one state dir with the MCP server.
# shellcheck source=lib/gigabuddy-dir.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/gigabuddy-dir.sh"
MYC_DIR="$(gigabuddy_dir)"
# This session's own dir — every per-session file lives here (one id scheme,
# the host session id verbatim; mirrors sessionDir() in scratch.ts).
SDIR="$MYC_DIR/sessions/cc_$SESSION_ID"

# --- 0. A real prompt ends any unattended lockdown ---------------------------
# The channel bridge stamps unattended.json before waking an idle session;
# channel-guard.sh confines the woken turn until the human types again. THIS
# is "types again" — unless the prompt itself is the injected channel event
# (guarded in case the harness routes those through this hook too).
{
  PROMPT_HEAD=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null | head -c 12 || true)
  case "$PROMPT_HEAD" in
    "<channel"*) : ;;
    *) rm -f "$SDIR/unattended.json" 2>/dev/null || true ;;
  esac
} || true

# --- 1. Register session for the server's deferred auto-connect -------------
{
  if [ -d "$MYC_DIR" ]; then
    mkdir -p "$SDIR" 2>/dev/null || true
    PC="$SDIR/pending-connect.json"
    printf '{"claudeSessionId":"%s","ts":"%s"}\n' \
      "$SESSION_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PC.tmp" 2>/dev/null \
      && mv "$PC.tmp" "$PC" 2>/dev/null || true
    # A prompt is activity: touch the outbox ts so lastActiveAt (peers' idle
    # clock, and the cache-warmth proxy) updates on prompts too, not only on
    # tool calls. Without this a conversational session reads as idle forever.
    # Same atomic tmp+mv as the PreToolUse writer; last writer wins, both fine.
    OB="$SDIR/outbox.json"
    TS_NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ -f "$OB" ]; then
      jq --arg ts "$TS_NOW" '.ts = $ts' "$OB" > "$OB.tmp" 2>/dev/null \
        && mv "$OB.tmp" "$OB" 2>/dev/null || true
    else
      printf '{"ts":"%s"}\n' "$TS_NOW" > "$OB.tmp" 2>/dev/null \
        && mv "$OB.tmp" "$OB" 2>/dev/null || true
    fi
  fi
} || true

# --- 2. Inject the full peer baseline ---------------------------------------
# Read the inbox for THIS session, not a stale one from a dead session.
INBOX="$SDIR/inbox.json"
if [ ! -f "$INBOX" ]; then
  # Not connected. Usually the server is just booting — but a user who has
  # never signed in will NEVER connect, and nothing tells them why (the
  # server's stderr hint is invisible in normal use, and the login tool may
  # be deferred out of the agent's visible tool list). Surface it once per
  # session so the agent offers the in-chat `login` flow.
  if [ ! -f "$HOME/.gigabuddy/credentials.json" ] && [ ! -f "$HOME/.gigabuddy/credentials.staging.json" ]; then
    NUDGE_FLAG="${TMPDIR:-/tmp}/gigabuddy-login-nudge-$SESSION_ID"
    if [ ! -f "$NUDGE_FLAG" ]; then
      : > "$NUDGE_FLAG" 2>/dev/null || true
      NUDGE="Gigabuddy is installed but not signed in, so awareness/presence is inactive. At a natural moment this turn, offer to sign the user in: call the gigabuddy \`login\` tool and relay the URL + code it returns (the gigabuddy tools exist but may be deferred — find them via tool search, never by searching the filesystem). One-time setup. If the user declines, drop it — this hint is once per session."
      ESCAPED=$(printf '%s' "$NUDGE" | jq -Rs . 2>/dev/null) \
        && printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$ESCAPED"
    fi
    exit 0
  fi

  # Signed in but not connected. Usually a join is seconds away (the server
  # auto-joins the repo's pinned room on this very prompt) — say nothing. But a
  # repo with NO pin and no cached place of its own never auto-joins, and
  # nothing used to tell the agent, so it ran the whole session with only the
  # pre-connect tool list (issue:4C85a7IYkilv). The server writes its
  # resolution to autoconnect.json at boot; fall back to the pin file if that
  # hasn't landed yet. Once per session.
  AC_KIND=$(jq -r '.kind // empty' "$SDIR/autoconnect.json" 2>/dev/null || true)
  if [ -z "$AC_KIND" ]; then
    [ -f "$MYC_DIR/default-place.json" ] && AC_KIND="pinned" || AC_KIND="none"
  fi
  if [ "$AC_KIND" = "none" ] || [ "$AC_KIND" = "ambiguous" ]; then
    NUDGE_FLAG="${TMPDIR:-/tmp}/gigabuddy-connect-nudge-$SESSION_ID"
    if [ ! -f "$NUDGE_FLAG" ]; then
      : > "$NUDGE_FLAG" 2>/dev/null || true
      KNOWN=$(jq -r '[.places[]? | "\(.placeName // .placeId) (\(.placeId))"] | join(", ")' \
        "$MYC_DIR/sanctioned-places.json" 2>/dev/null || true)
      LAST=$(jq -r 'if .placeId then "\(.placeName // .placeId) (\(.placeId))" else empty end' \
        "$MYC_DIR/connection.json" 2>/dev/null || true)
      NUDGE="Gigabuddy: signed in but NOT connected, and this repo has no pinned room, so no auto-join will happen. The work/page/ledger verbs (search, read_work, raise, decide, load_skill, pickup_work, …) only appear once connected."
      [ -n "$LAST" ] && NUDGE="$NUDGE Last room used here: $LAST."
      [ -n "$KNOWN" ] && NUDGE="$NUDGE Rooms this repo has used: $KNOWN."
      NUDGE="$NUDGE Before doing anything that needs those verbs, connect: call the gigabuddy \`connect\` tool with the placeId (add pin: true so future sessions auto-join it — the gigabuddy tools may be deferred; find them via tool search). If the user's request doesn't need Gigabuddy, mention the offline state in one line and carry on. Once per session."
      ESCAPED=$(printf '%s' "$NUDGE" | jq -Rs . 2>/dev/null) \
        && printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$ESCAPED"
    fi
  fi
  exit 0
fi

INBOX_JSON=$(cat "$INBOX" 2>/dev/null || echo '{}')
SEQ=$(printf '%s' "$INBOX_JSON" | jq -r '.seq // 0' 2>/dev/null || echo 0)
EVENT_COUNT=$(printf '%s' "$INBOX_JSON" | jq '.events | length' 2>/dev/null || echo 0)

# Read place name from connection.json if available
PLACE_NAME=""
CONN_FILE="$MYC_DIR/connection.json"
if [ -f "$CONN_FILE" ]; then
  PLACE_NAME=$(jq -r '.placeName // empty' "$CONN_FILE" 2>/dev/null || true)
fi

SELF_REPO=$(jq -r '.repo // empty' "$SDIR/outbox.json" 2>/dev/null || true)
# When THIS server process booted (it stamps autoconnect.json at startup).
BOOT_TS=$(jq -r '.ts // empty' "$SDIR/autoconnect.json" 2>/dev/null || true)
CONTEXT=$(printf '%s' "$INBOX_JSON" | jq -r --arg placeName "$PLACE_NAME" --arg selfRepo "$SELF_REPO" --arg bootTs "$BOOT_TS" --argjson now "$(date +%s)" '
  # Snapshot freshness: inbox.json is rewritten whenever any peer frame arrives
  # (at least every heartbeat while the socket lives), so a snapshot minutes old
  # means something is off — everything below is then a guess, and saying so
  # beats rendering stale peers as live. Two distinct causes, told apart by the
  # server boot stamp:
  #   - server booted AFTER the snapshot → a previous process of this same
  #     session wrote it (claude --resume, /reload-plugins, a crash or reboot);
  #     the new server rejoins the room at boot, so the join is landing NOW —
  #     not a dead connection, and never grounds to declare Gigabuddy offline;
  #   - same server → OUR socket is down; the sidecar reconnects on its own
  #     heartbeat, and session_status is the live truth, not this file.
  def iso: sub("\\.[0-9]+";"") | try fromdateiso8601 catch null;
  ((.ts // "") | iso) as $snapTs |
  ($now - ($snapTs // $now)) as $snapAge |
  (($bootTs | iso) as $boot | $boot != null and $snapTs != null and $boot > $snapTs) as $restarted |
  "You are " + .self.displayName
  + (if $placeName != "" then " in " + $placeName else "" end)
  + ( if $restarted then
        "\nℹ The Gigabuddy server restarted after this snapshot (session resumed / plugin reloaded) and is rejoining the room now — the door verbs reappear once joined. Do NOT treat Gigabuddy as offline: if a verb you need is missing, call session_status and retry. Peer info below is from before the restart."
      elif $snapAge >= 180 then
        "\n⚠ Awareness snapshot is " + (($snapAge/60)|floor|tostring) + "m old — the live socket may be down (it reconnects on its own heartbeat). Call session_status before treating Gigabuddy as offline; peer info below may be stale."
      else "" end )
  + "\n"
  # Peer ROSTER RETIRED (2026-08-22, idea:OJuidt4hrY_b): the full per-turn
  # listing (every peer, absolute `touching:` paths, idle clocks) cost ~10 KB a
  # turn in a busy room with near-zero actionable content. Until the awareness
  # digest lands (page:OaPM-L3NmeCg), render ONE summary line — counts plus the
  # live peers sharing this repo — and point at get_awareness for the roster.
  # Conflict events still arrive via the PreToolUse hook; events render below.
  + ( (.peers // []) as $ps
      | ([ $ps[] | select(
            ( (.beatAt == null) or (($now * 1000 - .beatAt) < 90000) )
            and ( (.lastActiveAt == null)
                  or (($now - ( .lastActiveAt | sub("\\.[0-9]+";"") | try fromdateiso8601 catch $now )) < (.coldSecs // 3600)) )
          ) ]) as $live
      | ([ $live[] | select($selfRepo != "" and .repo == $selfRepo) | .displayName ]) as $here
      | "Peers: " + ($ps | length | tostring) + " in the room · " + ($live | length | tostring) + " live"
        + (if ($here | length) > 0 then " · live in this repo: " + ($here | join(", ")) else "" end)
        + " (get_awareness for the full roster)" )
  # House rules: standing directives for this place, re-stamped every turn
  # (headlines only — the connect briefing carried the full block).
  + ( if ((.houseRules // []) | length) > 0 then
      "\nHouse rules here (standing directives):\n"
      + ([.houseRules[] | "  ▸ " + .] | join("\n"))
    else "" end )
  + ( if (.events | length) > 0 then
      "\nRecent activity:\n" + ([.events[-8:][] |
        if .type == "peer_joined" then "  → \(.peer) joined"
        elif .type == "peer_left" then "  ← \(.peer) left"
        elif .type == "peer_changed" then "  △ \(.peer): \(.detail)"
        elif .type == "conflict" then "  ⚠ \(.peer) also editing \(.files | join(", "))"
        elif .type == "page_updated" then "  📄 \(.detail) updated by \(.peer)"
        elif .type == "attachment" then "  📎 \(.peer) attached \(.detail) to your activity"
        elif .type == "mention" then "  💬 \(.peer) mentioned you: \(.detail)" + (if .threadId then " [reply in thread \(.threadId)]" else "" end)
        elif .type == "thread_reply" then "  💬 \(.peer) replied in a thread you follow: \(.detail // "")" + (if .threadId then " [thread \(.threadId)]" else "" end)
        elif .type == "ask" then "  📨 ASK for you from \(.peer): \(.detail // "")" + (if .threadId then " [discuss in thread \(.threadId)]" else "" end)
        else "  \(.type): \(.peer)" end
      ] | join("\n"))
    else "" end )
' 2>/dev/null || true)

# --- 3. One-time statusline setup offer --------------------------------------
# Claude Code does NOT apply a plugin settings.json `statusLine` (only the
# `agent`/`subagentStatusLine` keys are honored from plugin settings), so the
# gigabuddy status bar needs an entry in the USER's own settings. If no
# statusLine is configured anywhere, nudge the agent ONCE EVER (persistent
# flag) to offer wiring it up in-chat. Any existing statusLine — gigabuddy or
# not — means stay silent: never offer to clobber the user's own status bar.
if [ -n "$CONTEXT" ] && [ ! -f "$HOME/.gigabuddy/statusline-nudge-shown" ]; then
  if ! grep -qs '"statusLine"' \
      "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" \
      "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/settings.json" \
      "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/settings.local.json"; then
    mkdir -p "$HOME/.gigabuddy" 2>/dev/null || true
    : > "$HOME/.gigabuddy/statusline-nudge-shown" 2>/dev/null || true
    SL_NUDGE=""
    # Quoted heredoc: the snippet must land verbatim (no expansion here).
    IFS= read -r -d '' SL_NUDGE <<'SLEOF' || true
One-time setup offer — the Gigabuddy status bar isn't wired up (Claude Code ignores plugin statusline settings, so it needs one entry in the user's own settings). At a natural moment, offer it: a live status line showing place, peers, current activity, and idle time at the bottom of the terminal. If the user wants it, merge this top-level key into ~/.claude/settings.json (preserve their other settings) and tell them to restart Claude Code:

  "statusLine": {
    "type": "command",
    "command": "bash -c 'script=$(ls -td ~/.claude/plugins/cache/gigabuddy/gigabuddy/*/scripts/statusline.sh 2>/dev/null | head -1); [ -f \"$script\" ] && exec \"$script\" || echo \"🍄 no plugin\"'",
    "refreshInterval": 5
  }

If they decline, drop it — this offer never repeats.
SLEOF
    [ -n "$SL_NUDGE" ] && CONTEXT="$CONTEXT

$SL_NUDGE"
  fi
fi

# Baseline the seq so the PreToolUse hook only injects deltas from here on.
mkdir -p "$SDIR" 2>/dev/null || true
printf '{"lastSeenSeq":%s,"lastEventCount":%s}\n' "$SEQ" "$EVENT_COUNT" \
  > "$SDIR/hook-state.json.tmp" 2>/dev/null \
  && mv "$SDIR/hook-state.json.tmp" "$SDIR/hook-state.json" 2>/dev/null || true

if [ -n "$CONTEXT" ]; then
  ESCAPED=$(printf 'Gigabuddy awareness —\n%s' "$CONTEXT" | jq -Rs .)
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$ESCAPED"
fi

exit 0
