# SP Drop - Discovery Architecture

## Overview
SP Drop uses a **multi-strategy discovery architecture** designed to ensure reliable peer discovery across real-world network conditions. Rather than relying on a single mechanism like mDNS (which can fail due to multicast filtering, VPNs, or guest network isolation), the system runs parallel strategies that feed into a central `DiscoveryManager`.

> **CRITICAL SECURITY BOUNDARY:**
> **DISCOVERY ≠ TRUST.**
> Discovery mechanisms only yield *peer candidates* (endpoints). The discovery layer has zero authority over trust, authentication, or cryptographic key exchange. Every connection attempt still goes through the standard SP Drop authentication handshake.

## Components

### 1. DiscoveryManager
The central orchestration layer (`lib/services/discovery/discovery_manager.dart`).
- **Lifecycle:** Starts and stops all underlying discovery strategies.
- **Aggregation:** Subscribes to the peer streams of all strategies.
- **Deduplication:** Merges peers discovered across multiple strategies into a single `PeerModel`. Deduplication is performed primarily using a `deviceId` (stable identity). If missing, it falls back to endpoint correlation (IP + port).
- **Stale Peer Cleanup:** Runs a periodic timer (10s) to prune peers that haven't been seen recently.

### 2. PeerModel
A unified representation of a discovered device (`lib/models/peer_model.dart`).
- Contains the device's stable ID, name, platform, IPs, port, and the set of `DiscoverySource`s it was found through.
- Contains the `merge()` logic ensuring that newer timestamps take precedence and multiple IP paths are preserved.

### 3. Discovery Strategies

All strategies extend `DiscoveryStrategy` and emit lists of `PeerModel`.

#### MdnsDiscoveryStrategy
- **Source:** `DiscoverySource.mDNS`
- **Mechanism:** Uses the `nsd` package to broadcast and browse for `_p2psync._tcp` services.
- **Role:** The primary zero-configuration discovery method. Highly effective on simple, unmanaged local networks.

#### UdpDiscoveryStrategy
- **Source:** `DiscoverySource.udp`
- **Mechanism:** Periodically broadcasts and listens for lightweight JSON datagrams on UDP port 45454.
- **Role:** Fallback for networks where multicast/mDNS is disabled or filtered but standard UDP broadcasts are allowed.
- **Security:** Strict packet size limits (512 bytes) and JSON field validation to prevent buffer bloat and malformed data crashes.

#### CachedPeerStrategy
- **Source:** `DiscoverySource.cached`
- **Mechanism:** Reads previously authenticated trusted devices from `HistoryService`.
- **Role:** Provides endpoints for devices that are physically nearby or accessible (e.g., across a VPN or subnet) but where broadcast packets cannot reach.

#### Manual IP Connection (UI)
- **Mechanism:** Users can tap the "Connect via IP" button in the UI.
- **Role:** The ultimate fallback. Directly initiates a connection to a specific IP and port, relying on the authentication layer to verify the endpoint.

## Deduplication Logic
Since a device might broadcast over mDNS and UDP simultaneously, the `DiscoveryManager` must prevent UI duplication.
1. **Primary Match (Stable ID):** If two peers share the same `deviceId` (generated from `SharedPreferences`), they are merged.
2. **Fallback Match (Endpoint):** If `deviceId` is missing, peers are matched based on identical Port and intersecting IP addresses.
3. **Name Match Warning:** Device names are explicitly **not** used as a primary deduplication or trust key, as they are easily spoofed or duplicated by the OS (e.g., "Device (2)").

## Lifecycle Management
- When the app is paused (moved to background on Android), the `DiscoveryManager` pauses discovery scanning to save battery, but the underlying service (mDNS registration) is kept alive via `LocalSignalingService`'s periodic background timers to remain discoverable to other devices.
- On resume, the manager restarts strategies and clears the stale cache.
