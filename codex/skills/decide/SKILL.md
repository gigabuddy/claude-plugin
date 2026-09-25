---
name: decide
description: Record a decision in the place's ledger — a resolved choice with who decided it, append-only precedent. Use on /decide, when a call lands in a discussion (especially a handover's open decision being answered), or when the user says "we decided / let's go with / the call is". To pose a question still awaiting a decision, raise kind:decision instead.
argument-hint: '<what was decided — one sentence>   (or empty to distill the decision from the current thread)'
---

# Decide

This skill's full guidance is served by the Gigabuddy door, so it can evolve without a plugin release.

1. If `load_skill` is not in your tool list, the session isn't connected to a room yet — the door's work/page/ledger verbs (and this skill's body) only appear after connecting. Call the gigabuddy `connect` tool with no arguments: it joins this repo's pinned default room. Do not call `session_status` first. If `connect` returns a room list instead (no pin), ask the user which room and connect with that `placeId` plus `pin: true`; if it returns a sanction gate, relay it to the user — never pass `confirm: true` on your own.
2. Call `load_skill` with `{ "name": "decide" }`.
3. Follow the returned guidance exactly as if it were the body of this file, including the arguments the user passed.

If `load_skill` is still unavailable after connecting (the server predates it), tell the user this skill needs the Gigabuddy door's skill serving — do not improvise the flow.
