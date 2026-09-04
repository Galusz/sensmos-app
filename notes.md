## SENSMOS 1.5.53

**Requires node firmware 1.01.** Nodes receive it automatically over the air; until a node is updated, the tunnel will not open for it.

- The tunnel (terminal, Home Assistant panel, LAN panels) now requires node firmware 1.01 — nodes receive it automatically, and the tunnel will not open until a node is updated
- A node PIN can be set over Bluetooth: when adding a node, the PIN you type becomes the one in force, and service mode has a separate “Set a new PIN” action
- Changing the PIN is a full screen with two fields — current and new — and when the node refuses you see the reason instead of a bare error code
- When adding a node, the wallet copy kept on it is always re-encrypted with the current PIN, and if it cannot be read the app asks for the previous PIN instead of aborting
