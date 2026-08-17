import 'dart:math';

/// Orchestrates the OTP-based pairing ceremony between two connected devices.
///
/// This service owns the pairing protocol messages (pair_request, pair_response,
/// pair_confirmed) and their corresponding callbacks. It delegates the actual
/// signaling transport to a send-function injected at construction time.
///
/// It does NOT own:
/// - Cryptographic identity (IdentityService)
/// - Trusted device persistence (TrustRepository)
/// - WebSocket / connection lifecycle (LocalSignalingService)
class PairingService {
  /// Sends a signaling message via the parent signaling service.
  final void Function(Map<String, dynamic> data) _sendMessage;

  /// Returns the current device name.
  final String Function() _getDeviceName;

  /// Returns the current platform string.
  final String Function() _getPlatform;

  // Callbacks — same signature as previously on LocalSignalingService
  Function(String deviceName, String code)? onPairingRequest;
  Function(String deviceName)? onPairingConfirmed;
  Function(String deviceName, String code)? onPairingResponse;

  PairingService({
    required this._sendMessage,
    required this._getDeviceName,
    required this._getPlatform,
  });

  /// Generates a cryptographically secure 6-digit pairing code.
  String generatePairingCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  /// Sends a pairing request with the given code to the connected peer.
  void sendPairingRequest(String code) {
    _sendMessage({
      'type': 'pair_request',
      'deviceName': _getDeviceName(),
      'code': code,
      'platform': _getPlatform(),
    });
  }

  /// Sends a pairing response with the given code to the connected peer.
  void sendPairingResponse(String code) {
    _sendMessage({
      'type': 'pair_response',
      'deviceName': _getDeviceName(),
      'code': code,
      'platform': _getPlatform(),
    });
  }

  /// Confirms the pairing ceremony with the connected peer.
  void confirmPairing() {
    _sendMessage({
      'type': 'pair_confirmed',
      'deviceName': _getDeviceName(),
    });
  }

  /// Handles incoming pairing-related signaling messages.
  ///
  /// Returns `true` if the message was a pairing message and was handled,
  /// `false` if the message type is not pairing-related.
  bool handlePairingMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    switch (type) {
      case 'pair_request':
        final deviceName = data['deviceName'] ?? 'Unknown';
        final code = data['code'] ?? '';
        onPairingRequest?.call(deviceName, code);
        return true;

      case 'pair_response':
        final deviceName = data['deviceName'] ?? 'Unknown';
        final code = data['code'] ?? '';
        onPairingResponse?.call(deviceName, code);
        return true;

      case 'pair_confirmed':
        final deviceName = data['deviceName'] ?? 'Unknown';
        onPairingConfirmed?.call(deviceName);
        return true;

      default:
        return false;
    }
  }
}
