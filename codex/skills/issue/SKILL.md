---
name: issue
description: Raise a bug or problem into the work queue — fast one-line capture. Use on /issue, when the user reports/files/logs a bug, or when you spot a defect mid-task. For a proposal, use /idea. Default is to raise immediately; --assist to flesh it out first.
argument-hint: '<one-sentence description of the bug/problem>   (--assist to have the agent flesh it out first)'
---

# Issue

This skill's full guidance is served by the Gigabuddy door, so it can evolve without a plugin release.

1. If `load_skill` is not in your tool list, the session isn't connected to a room yet — the door's work/page/ledger verbs (and this skill's body) only appear after connecting. Call the gigabuddy `connect` tool with no arguments: it joins this repo's pinned default room. Do not call `session_status` first. If `connect` returns a room list instead (no pin), ask the user which room and connect with that `placeId` plus `pin: true`; if it returns a sanction gate, relay it to the user — never pass `confirm: true` on your own.
2. Call `load_skill` with `{ "name": "issue" }`.
3. Follow the returned guidance exactly as if it were the body of this file, including the arguments the user passed.

If `load_skill` is still unavailable after connecting (the server predates it), tell the user this skill needs the Gigabuddy door's skill serving — do not improvise the flow.
