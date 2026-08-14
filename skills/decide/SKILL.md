---
name: decide
description: Record a decision in the place's ledger — a resolved choice with who decided it, append-only precedent. Use on /decide, when a call lands in a discussion (especially a handover's open decision being answered), or when the user says "we decided / let's go with / the call is". To pose a question still awaiting a decision, raise kind:decision instead.
argument-hint: '<what was decided — one sentence>   (or empty to distill the decision from the current thread)'
---

# Decide

This skill's full guidance is served by the Gigabuddy door, so it can evolve without a plugin release.

1. Call the `get_skill` tool on the connected Gigabuddy MCP server with `{ "name": "decide" }`.
2. Follow the returned guidance exactly as if it were the body of this file, including the arguments the user passed.

If `get_skill` is unavailable (not connected, or the server predates it), tell the user this skill needs the Gigabuddy door's skill serving — do not improvise the flow.
