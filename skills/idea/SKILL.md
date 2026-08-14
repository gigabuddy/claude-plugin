---
name: idea
description: Raise a proposal or improvement into the work queue — fast one-line capture, the "I have an idea" door. Use on /idea, when the user floats a "we should…" / "what if…", or when you spot an improvement mid-task. For a bug, use /issue. Default is to raise immediately; --assist to flesh it out first.
argument-hint: '<one-sentence idea>   (--assist to have the agent flesh it out first)'
---

# Idea

This skill's full guidance is served by the Gigabuddy door, so it can evolve without a plugin release.

1. Call the `get_skill` tool on the connected Gigabuddy MCP server with `{ "name": "idea" }`.
2. Follow the returned guidance exactly as if it were the body of this file, including the arguments the user passed.

If `get_skill` is unavailable (not connected, or the server predates it), tell the user this skill needs the Gigabuddy door's skill serving — do not improvise the flow.
