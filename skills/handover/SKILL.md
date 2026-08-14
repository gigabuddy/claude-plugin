---
name: handover
description: Hand off your current work to a future agent session as a typed, claimable Gigabuddy handover — then hold "office hours" to answer the picker's questions live. Use when the user says /handover, asks to hand off / pass on / write up work for the next session, or when you're nearing the end of a session with unfinished work someone else (or a fresh you) will continue. Pairs with /pickup.
---

# Handover

This skill's full guidance is served by the Gigabuddy door, so it can evolve without a plugin release.

1. Call the `get_skill` tool on the connected Gigabuddy MCP server with `{ "name": "handover" }`.
2. Follow the returned guidance exactly as if it were the body of this file, including the arguments the user passed.

If `get_skill` is unavailable (not connected, or the server predates it), tell the user this skill needs the Gigabuddy door's skill serving — do not improvise the flow.
