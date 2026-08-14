---
name: pickup
description: Pick up a unit of work from the Gigabuddy queue — a handover (in-flight work someone paused) OR a raised issue/idea — and orient a fresh session from it. Auto-loads the linked pages/files (or the code-area), claims it, and (if a handover's origin is still in office hours) asks it clarifying questions live before it disconnects. Use when the user says /pickup <id> or /pickup <search terms>, asks to pick up / continue / take over work, or points you at a handover page id or a work_object id. Pairs with /handover and /idea + /issue.
argument-hint: '[handover-id | search terms]'
---

# Pickup

This skill's full guidance is served by the Gigabuddy door, so it can evolve without a plugin release.

1. Call the `get_skill` tool on the connected Gigabuddy MCP server with `{ "name": "pickup" }`.
2. Follow the returned guidance exactly as if it were the body of this file, including the arguments the user passed.

If `get_skill` is unavailable (not connected, or the server predates it), tell the user this skill needs the Gigabuddy door's skill serving — do not improvise the flow.
