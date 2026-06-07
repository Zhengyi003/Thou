# Thou

Thou is an iPhone companion for OpenClaw.

The first public release is intentionally narrow. It focuses on one mobile job only: connect to a Mac running OpenClaw, choose an agent, choose a session, read history, and send messages from iPhone.

## MVP boundary

The current release boundary is:

1. Connect Thou to a Mac-hosted OpenClaw bridge.
2. Load agent list and switch into one agent inbox.
3. Load sessions for that agent.
4. Read history and send messages with streaming replies.

The current release does not promise:

1. Agent creation from iPhone.
2. Session creation as a separate mobile workflow.
3. Alice product flows in the public UI.
4. Group chat or meeting workflows.

## Current network stance

- Tailnet is the primary remote path.
- LAN remains a lower-level fallback, not the main first-run path.
- The current development bridge still uses `ws://`, so the iOS app keeps ATS relaxed during this stage.

## Repository layout

- [Thou/](Thou) contains the iOS app source.
- [Thou.xcodeproj/](Thou.xcodeproj) contains the Xcode project.
- [Thou (iOS)/说明.md](Thou%20(iOS)/说明.md), [Thou (iOS)/进度.md](Thou%20(iOS)/进度.md), and [Thou (iOS)/发现.md](Thou%20(iOS)/发现.md) store the project state anchor for agent handoff.

## Validation focus

Before a public release or TestFlight build, verify:

1. real-device build, install, and launch
2. OpenClaw connect -> agent -> session -> history -> send main path
3. foreground resume and controlled reconnect behavior
4. device trust recovery when development signing expires

## Known limits

- The app still keeps ATS broadly relaxed while the bridge uses plaintext WebSocket.
- App Store review prep is not complete in this repository state.
- Alice code assets may remain in source as future material, but the public shell is narrowed to OpenClaw companion flow.
