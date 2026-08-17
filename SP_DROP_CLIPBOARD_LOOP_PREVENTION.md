# SP Drop Clipboard Loop Prevention & Event Identity

This document details the architecture for robust clipboard synchronization loop prevention inside SP Drop (Solving Problem #5).

## Core Philosophy

Clipboard synchronization must be EVENT-BASED, not CONTENT-COMPARISON-BASED. 
If a user copies the exact same text twice intentionally, they are two distinct events and must both be synchronized.

## Architecture

Every new local clipboard event generates a robust cryptographic identity:

- `eventId`: A unique UUID v4 generated upon each new local clipboard copy.
- `originDeviceId`: The stable Device ID of the device that originally copied the content.
- `timestamp`: (Optional/Diagnostic) The time the event occurred.
- `contentHash`: (Optional/Diagnostic) A hash of the content to assist with legacy fallbacks or OS-echo suppression.

These fields are transmitted alongside the clipboard payload within the **EXISTING authenticated and encrypted SP Drop session**.

### 1. `ClipboardEventCache` (The Bounded Event History)

To prevent infinite synchronization loops (e.g., A → B → C → A), each device maintains a memory-safe `ClipboardEventCache`.

- **Maximum Entries:** 100
- **TTL (Time-To-Live):** 1 Hour
- **Eviction Strategy:** When the maximum size is reached, the oldest processed events are evicted first. Expired events are also aggressively purged on every interaction.
- **Concurrency Safety:** Synchronous Map-based storage tied to the single-threaded Dart isolate event loop.

When a remote clipboard event is received:
1. If `originDeviceId` matches the local `stableDeviceId`, the event is rejected as self-echo.
2. If `eventId` exists in the `ClipboardEventCache`, the event is rejected as a duplicate.
3. Otherwise, the event is marked as processed, and applied to the local OS clipboard.

### 2. OS Echo Suppression (Windows)

When a remote clipboard payload is applied to the local Windows OS clipboard, the OS subsequently fires a `onClipboardChanged` event back into the application. 
To prevent this echo from generating a *new* local event, we utilize `_expectedEchoHash` and `_expectedEchoTime`.

This mechanism suppresses the immediate echo for up to 3 seconds. It is strictly an OS-echo suppression tool and is NOT the primary loop prevention mechanism across the network.

### 3. Repeated Polling Prevention (Android)

Because Android lacks robust foreground background-clipboard event listeners in modern SDKs, the app relies on a 2-second periodic polling timer. 
To prevent this timer from generating an infinite stream of new events for the same content, `_lastLocalTextHash` is utilized. 

This ensures that only actual *changes* to the local clipboard are packaged into new `eventId` payloads.

### 4. Image Events

Image sync identity is maintained by embedding the `eventId` and `originDeviceId` into the temporary filename transferred between devices:
`clipboard_image_{eventId}_{originDeviceId}.png`

When received, the filename is parsed to extract the event identity and subjected to the same origin and cache checks before being applied.

## Testing Strategy

Targeted unit tests in `test/clipboard_service_test.dart` validate:
1. Duplicate `eventId`s are correctly rejected.
2. Identical content with different `eventId`s are successfully allowed.
3. The cache strictly adheres to the 100-item maximum size, automatically evicting oldest items.

## Privacy & Security

This architecture completely operates *on top* of the Problem #4 (Privacy/Trust) mechanisms. Sensitive text filters, targeted device sync constraints, and authenticated transfer channels remain wholly untouched and fully active.
