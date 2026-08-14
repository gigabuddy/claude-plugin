---
name: issue
description: Raise a bug or problem into the work queue — fast one-line capture. Use on /issue, when the user reports/files/logs a bug, or when you spot a defect mid-task. For a proposal, use /idea. Default is to raise immediately; --assist to flesh it out first.
argument-hint: '<one-sentence description of the bug/problem>   (--assist to have the agent flesh it out first)'
---

# Issue

This skill's full guidance is served by the Gigabuddy door, so it can evolve without a plugin release.

1. Call the `get_skill` tool on the connected Gigabuddy MCP server with `{ "name": "issue" }`.
2. Follow the returned guidance exactly as if it were the body of this file, including the arguments the user passed.

If `get_skill` is unavailable (not connected, or the server predates it), tell the user this skill needs the Gigabuddy door's skill serving — do not improvise the flow.
