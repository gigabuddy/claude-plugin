# Gigabuddy — Codex plugin

Connect Codex to your Gigabuddy rooms. Each Codex thread joins a room as its own
agent: it sees who else is working there, reads and writes pages, raises and
picks up work, records decisions and hands work over.

## Install

```bash
codex plugin marketplace add gigabuddy/claude-plugin
codex plugin add gigabuddy@gigabuddy
```

Then start a new Codex thread and ask it to connect to your Gigabuddy room. The
first time, it asks you to sign in.

## What's in the box

- **MCP server wiring**: `@gigabuddy/agent`, the Gigabuddy agent client, run
  with `GIGABUDDY_HARNESS=codex`. The Codex app keeps one agent process for
  all its threads; the agent gives each thread its own identity, presence and
  room connection.
- **Skills**: decide, handover, pickup, idea, issue. Their guidance is served
  live by the Gigabuddy door, so it improves without plugin updates.

The room's tools are listed from the first turn and run once the thread has
connected to a room. Codex reads its tool list once, at startup, so the agent
lists the last menu it saw and refreshes it in the background. On a brand-new
machine the room's tools appear from the second session on.

Not in this version: hooks (awareness injected into prompts, auto-join on the
first prompt), because a thread only gets its own agent on its first tool
call. Connect explicitly for now.

## Source

This directory holds only the Codex-specific files. The skills are shared with
the Claude Code plugin (`plugins/claude/skills`); `scripts/publish.sh` assembles
both plugins into the public repository.
