---
description: Leave the current Gigabuddy place (or stop the pending auto-join) — presence stops and this session will NOT auto-reconnect
---

Call the `disconnect` tool now.

- If it reports auto-connect was disabled (the session hadn't joined yet): confirm to the user in one line that this session will stay offline — the pending auto-join is cancelled.
- On a normal disconnect: confirm to the user in one line that the session left the place, presence/awareness stopped, and it won't auto-reconnect this session.
- Either way, mention they can rejoin any time by asking you to connect (the `connect` tool).

No other tools, no extra commentary.
