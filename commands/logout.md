---
description: Sign out of Gigabuddy on this machine — removes the stored credential (use /gigabuddy:disconnect to just leave the place)
---

Call the `logout` tool now.

- If it reports not signed in: tell the user in one line, and stop.
- Otherwise confirm sign-out in 1-2 lines, including the tool's note about already-running sessions keeping their in-memory tokens until restart. If the user seems to have wanted to just leave the current place (not remove the credential), point them at `/gigabuddy:disconnect`.

No other tools, no extra commentary.
