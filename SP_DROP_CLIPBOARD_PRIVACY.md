# SP Drop Clipboard Privacy Architecture

## Problem Statement

Clipboard synchronization in SpDrop presents a significant privacy risk. Clipboard contents often contain highly sensitive data such as:
- Passwords and OTP codes
- Cryptographic keys (SSH keys, JWTs, API tokens)
- Financial information (Credit Card numbers, UPI IDs)
- Personally Identifiable Information (PII)

Broadcasting this data unconditionally to any connected peer—even if paired—creates an attack vector for passive exfiltration or accidental data leakage.

## Privacy-First Architecture

We redesigned the clipboard synchronization to operate on a strict, privacy-first model.

### 1. Cryptographic Identity & Trust
- **Public Key Fingerprinting**: 
  - Instead of relying on user-provided or ephemeral device names (`deviceName`), clipboard trust is now anchored to Ed25519 cryptographic identities (`IdentityService`).
  - During the `LocalSignalingService` handshake, devices exchange their `publicKeyFingerprint`. This fingerprint is verified against the local trusted keystore.
  - Clipboard data is only sent to devices whose fingerprint matches a known, trusted identity.

### 2. Strict Opt-In Policy
- **Global Clipboard Sync Toggle**:
  - `clipboard_sync_enabled` is now **false by default**.
  - Users are never silently migrated to an enabled state. They must explicitly navigate to Settings and enable the feature.
- **Per-Device Allow-Listing**:
  - Simply pairing a device is no longer sufficient to grant it clipboard access.
  - Users must explicitly approve each trusted device for clipboard synchronization through the new **"Selected Devices"** UI.
  - Devices missing from the allow-list (stored locally via `ClipboardPrivacyService`) are strictly blocked from receiving clipboard updates.

### 3. Heuristic Sensitive Content Filtering
- **Pre-Network Filtering**:
  - All clipboard contents are scanned locally on the device **before** serialization and transmission over the network.
  - The `ClipboardPrivacyService` uses regex heuristics to detect structured sensitive data.
- **High-Confidence Patterns**:
  - **Cryptographic Keys**: `-----BEGIN .* KEY-----` and `ssh-(rsa|ed25519|dss) AAAA[0-9A-Za-z+/]+[=]{0,3}`
  - **JWTs**: `eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`
  - **Credit Cards**: `\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|6(?:011|5[0-9]{2})[0-9]{12}|(?:2131|1800|35\d{3})\d{11})\b`
  - **OTP/2FA Codes**: Standalone 6-8 digit numeric codes (e.g., `^\\d{6,8}$`).

*Note: Sensitive-content detection is inherently a heuristic. While it reliably blocks structured credentials, it cannot guarantee detection of all arbitrary sensitive data (such as raw, unstructured passwords).*

### 4. Implementation Details

- **`ClipboardPrivacyService`**: Manages the clipboard allow-list (keyed by `publicKeyFingerprint`) and executes the heuristic filtering logic.
- **`IdentityService`**: Exposes the local `publicKeyFingerprint` and provides the `isFingerprintTrusted` validation function.
- **`LocalSignalingService`**: Modified to embed `publicKeyFingerprint` in `connect` and `connect_ack` payloads to reliably identify the remote peer cryptographically.
- **`ClipboardService`**: Acts as the gatekeeper. It intercepts clipboard updates, checks `ClipboardPrivacyService.canSyncToDevice`, runs the heuristic filter, and only then forwards the data to the signaling channel.
- **`main.dart`**: Provides the UI for toggling the global opt-in (`_clipboardSyncEnabled`) and the "Selected Devices" modal to manage the allow-list.

## Conclusion
This architecture ensures that SpDrop's clipboard synchronization is explicit, user-controlled, and robust against unauthorized interception, meeting the P0/P1 Privacy Goal requirements while preserving the real-time convenience of the feature.
