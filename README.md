# SpDrop
SpDrop is a cross-platform peer-to-peer application for transferring files between devices and synchronizing clipboard data over local networks.

## Overview
SpDrop simplifies local file sharing and clipboard synchronization by allowing devices on the same network to discover, pair, and securely communicate with each other directly without requiring a cloud intermediary or internet connection. Built with Flutter for a responsive and modern user interface, it leverages Rust for high-performance native functionality where applicable.

## Features
*   **Peer Discovery**: Automatically discover other devices on the same local network using mDNS/UDP.
*   **Device Pairing & Trust**: Establish trust with other devices via pairing protocols, enabling seamless future connections.
*   **File Transfer**: Send and receive files directly over the local network.
*   **Clipboard Synchronization**: Share and sync clipboard data across trusted paired devices.
*   **Cross-Platform**: Natively supports Android and Windows.
*   **Settings & Privacy**: Control visibility and trusted device management.

## Supported Platforms
*   **Android**
*   **Windows**

## Architecture
SpDrop's architecture is modular and split into clear responsibility domains:
*   `lib/core/`: Application-wide state, themes, and fundamental utilities.
*   `lib/features/`: Distinct feature modules such as Discovery, Pairing, Transfer, and Clipboard synchronization.
*   `lib/services/`: Core business logic services handling local signaling, clipboard state, and device capabilities.
*   `lib/transport/`: Handles the underlying peer-to-peer communication layer over WebSockets and TCP.
*   `lib/shared/`: Shared UI components and models used across different features.
*   `lib/widgets/`: Core reusable visual elements and dialogs.
*   **Rust Integrations**: High-performance or low-level platform functionality invoked via `flutter_rust_bridge`.

## Security & Privacy
SpDrop prioritizes secure local communication:
*   **Trusted Devices**: Only paired and explicitly trusted devices can automatically sync data.
*   **Cryptographic Handshake**: Uses Ed25519 static identity keys, X25519 ephemeral session keys, HKDF-SHA256, and AES-256-GCM encryption for payload transmission (Stage 8 architectural implementation).
*   **Local Peer-to-Peer**: No cloud servers are used. Data never leaves your local network.
*   **Clipboard Protections**: Clipboard data is only synchronized to authorized, trusted devices over encrypted channels.

## Installation

### Windows
SpDrop currently needs to be built from source for Windows. A pre-compiled installer/executable is not yet available in the repository releases. See the Build From Source section below.

### Android
An APK can be built directly from the source code. Note that installing an APK built from source or obtained outside of Google Play may require enabling "Install from unknown sources" in your Android security settings. See the Build From Source section below. 

## Build From Source

Ensure you have the Flutter SDK installed and configured.

1.  **Install dependencies**:
    ```bash
    flutter pub get
    ```

2.  **Build Android APK (Release)**:
    ```bash
    flutter build apk --release
    ```

3.  **Build Windows Executable (Release)**:
    ```bash
    flutter build windows --release
    ```

## Development
To start developing on SpDrop:

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/Sourav112-droid/-SPDrop.git
    cd -SPDrop
    ```

2.  **Install dependencies**:
    ```bash
    flutter pub get
    ```

3.  **Run static analysis**:
    ```bash
    flutter analyze
    ```

4.  **Run tests**:
    ```bash
    flutter test
    ```

5.  **Run the application**:
    ```bash
    flutter run
    ```

## Project Status
SpDrop is currently under active development. The Phase 2 architecture migration has been completed and stabilized.

## Roadmap
Future improvements, optimizations, and new features will be documented as development continues.

## Screenshots
*Screenshots will be added as the UI is finalized.*

## License
No license has currently been specified for this repository.

## Contributing
As this project is in active early development, formal contribution guidelines are not yet established. For now, feel free to open issues or explore the codebase locally.

## Acknowledgements / Technologies
*   Flutter
*   Dart
*   Rust
*   Android
*   Windows
