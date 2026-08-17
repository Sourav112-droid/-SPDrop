# SP Drop Security & Authentication Architecture

## Overview
SP Drop implements a robust cryptographically secure Device Authentication mechanism designed to prevent Man-in-the-Middle (MITM) attacks during local peer-to-peer file transfers. This document details the cryptographic primitives, the authentication handshake protocol, and the required user verification steps.

## Cryptographic Primitives
*   **Static Identity Key:** Ed25519 (generated on first launch, stored via `flutter_secure_storage`).
*   **Ephemeral Session Keys:** X25519 (generated per-session).
*   **Session Key Derivation:** HKDF-SHA256 (extract and expand with salt and info context).
*   **Transcript Hashing:** SHA256 over a canonical deterministic transcript.
*   **Payload Encryption:** AES-256-GCM (with independent transmit `tx` and receive `rx` keys).

## Handshake Protocol (3-Message AKE)
The protocol cryptographically binds the static identities to the ephemeral session and derives the Short Authentication String (SAS).

### Transcript Elements
The canonical transcript is constructed deterministically and includes:
1. Protocol Version
2. Initiator Static Public Key
3. Responder Static Public Key
4. Initiator Ephemeral Public Key
5. Responder Ephemeral Public Key

### Protocol Flow
**Message 1 (Initiator -> Responder)**
*   Sends Initiator Ephemeral Public Key + Initiator Static Public Key

**Message 2 (Responder -> Initiator)**
*   Sends Responder Ephemeral Public Key + Responder Static Public Key
*   Sends Responder Signature: `Ed25519_sign(Responder Static Private Key, Transcript)`

**Message 3 (Initiator -> Responder)**
*   Sends Initiator Signature: `Ed25519_sign(Initiator Static Private Key, Transcript)`

### Post-Handshake Verification
Both sides independently derive the SAS (Short Authentication String) from the shared X25519 secret and the deterministic transcript.

## User Verification (SAS)
To protect against active MITM on the first pairing:
1. Both devices derive an identical 4-character SAS code.
2. If the peer device is unknown (not in `SharedPreferences` trusted devices list), a UI dialog is shown.
3. The user MUST visually compare the SAS displayed on both screens.
4. The user must actively check a confirmation box indicating the codes match.
5. Only upon explicit manual acceptance is the peer's Static Public Key marked as trusted for future connections.

## Manual Testing & Validation
To validate this architecture, perform the following tests:
1. **Legitimate Pairing:**
   * Run SP Drop on two devices.
   * Initiate a transfer.
   * Verify both devices display the exact same SAS.
   * Accept the connection on both devices.
   * Verify subsequent connections do not prompt the SAS dialog.
2. **MITM Simulation:**
   * Introduce a modified build that intercepts the handshake and proxies it with different ephemeral keys.
   * Verify the SAS generated on Device A differs from Device B.
   * Reject the connection.
   * Verify no data is transmitted and the keys are not added to the trusted list.
