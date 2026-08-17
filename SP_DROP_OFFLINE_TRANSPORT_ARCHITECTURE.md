# SP Drop Offline & Local Transport Architecture

## Executive Summary
This document outlines the refactored Transport Architecture for SP Drop, enabling reliable connections across normal LANs, Hotspots, Wi-Fi Direct groups, and manual IP links, while strictly preserving existing mDNS discovery and Rust-based cryptographic authentication. 

The core of this architecture is the newly introduced `TransportManager`, which separates connectivity establishment from signaling logic and discovery mechanisms.

## Core Abstractions (Control Plane)

The connectivity layer for the signaling plane (WebSocket) has been isolated into a strategy pattern:

### 1. `TransportConnection`
An interface representing an active transport connection for signaling. It wraps standard streams/sinks (such as `WebSocketChannel`) and exposes unified `stream`, `send()`, and `close()` methods.

### 2. `TransportStrategy`
Defines a specific mode of connectivity. Each strategy implements:
- `startListening()`: Binds a server.
- `onIncomingConnection`: Yields `TransportConnection` streams.
- `connect(List<String> ips, int port)`: Dials out to a peer.

### 3. `TransportManager`
Orchestrates the active strategies and forwards all incoming `TransportConnection` events to the signaling service. It applies a deterministic fallback policy when connecting to peers.

## Transport Modes

### Mode A: LAN Transport (`LanTransport`)
- **Use Case**: Default mode for devices on the same router/switch.
- **Server**: Binds a `shelf_io` WebSocket server to `InternetAddress.anyIPv4` on port `8888` (or fallback).
- **Client**: Connects directly to the discovered IP.

### Mode B/D: Offline P2P Transports
Leverages Android platform capabilities via `WifiDirectService`.
- **`HotspotTransport`**: Leverages the `LocalOnlyHotspot` Android API to spawn an infrastructure hotspot. Clients (including Windows/iOS) join using a generated SSID/Password and connect to the gateway IP.
- **`WifiDirectTransport`**: Leverages Wi-Fi Direct P2P Groups, establishing the Group Owner at `192.168.49.1`.

### Mode C: Manual Transport (`ManualTransport`)
- **Use Case**: When automated discovery fails but users know the exact IP address.
- **Client**: Forcefully dials the provided IP/Port.

## Separation of Concerns & Data Path

The new architecture strictly delineates phases:

1. **Discovery (Unchanged)**: `DiscoveryManager` and `MdnsDiscoveryStrategy` handle network scanning and advertisement. mDNS advertisement occurs immediately after `TransportManager` yields a valid listener port, ensuring Discovery retains ownership of identity.
2. **Connectivity (New)**: `TransportManager` applies its fallback logic (LAN → Cached → Wi-Fi Direct → Hotspot) to establish a raw `TransportConnection`.
3. **Signaling / Control Plane (Refactored)**: `LocalSignalingService` accepts the abstract `TransportConnection` instead of raw WebSockets, handling JSON protocols (Ping/Pong, offer/accept).
4. **Authentication & Session (Unchanged)**: Problem #1 cryptographic handshakes occur over the Control Plane.
5. **Data Plane (Unchanged)**: Upon mutual authentication, `RustFileService` establishes an independent, high-throughput TCP connection utilizing the peer's validated IP.

## Deterministic Fallback Policy
`TransportManager.connectToPeer` executes the following ordered attempts:
1. **LAN Attempt**: If the `PeerModel` contains typical LAN IPs (non-localhost), connection is attempted via `LanTransport`.
2. **Manual/Cached Attempt**: If the peer is marked manual, try `ManualTransport`.
3. **Wi-Fi Direct Attempt**: If the IP contains `192.168.49.1` (Android Group Owner standard), use `WifiDirectTransport`.
4. **Hotspot Attempt**: If the IP contains typical hotspot ranges (e.g., `192.168.43.x`), use `HotspotTransport`.

*Note: The creation of a Hotspot or Wi-Fi Direct group is explicit (`startHotspot()`, `startWifiDirect()`) and not aggressively auto-created on every LAN failure to prevent network disruption.*

## Future Extension: Relay
The `mesh.rs` backend can be integrated in the future by adding a `RelayTransport` that implements `TransportStrategy` and delegates stream routing over the relay node. This will seamlessly plug into `TransportManager` without altering signaling or auth logic.
