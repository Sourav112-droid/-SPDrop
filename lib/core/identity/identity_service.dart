import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:p2p_sync_app/src/rust/api.dart';
import '../../features/pairing/trust_repository.dart';

/// Manages local cryptographic identity keypairs and peer verification state.
class IdentityService {
  static const _storage = FlutterSecureStorage();
  static const _privateKeyKey = 'spdrop_identity_private_key';

  static final IdentityService _instance = IdentityService._internal();
  factory IdentityService() => _instance;
  IdentityService._internal();

  Uint8List? _privateKey;
  Uint8List? _publicKey;

  String? deviceId;
  String? deviceName;

  /// Verification callback invoking UI confirmation for newly encountered or changed peer identity keys.
  Future<bool> Function(Uint8List peerPublicKey, String sas, String peerDeviceName, {bool keyChanged})? onVerifyDevice;

  Future<void> init() async {
    final existingKeyStr = await _storage.read(key: _privateKeyKey);
    if (existingKeyStr != null) {
      _privateKey = _hexToBytes(existingKeyStr);
    } else {
      _privateKey = await apiGenerateStaticKeypair();
      await _storage.write(key: _privateKeyKey, value: _bytesToHex(_privateKey!));
    }
    _publicKey = await apiGetPublicKey(privateKey: _privateKey!);
  }

  Uint8List get privateKey {
    if (_privateKey == null) throw Exception('IdentityService not initialized');
    return _privateKey!;
  }

  Uint8List get publicKey {
    if (_publicKey == null) throw Exception('IdentityService not initialized');
    return _publicKey!;
  }

  String get publicKeyFingerprint {
    return _bytesToHex(publicKey);
  }

  /// Verifies peer public key against known trusted fingerprints and flags unexpected key changes.
  Future<bool> verifySession(Uint8List peerPublicKey, String peerDeviceId, String peerDeviceName, String sas, String ip, int port) async {
    final trustRepo = TrustRepository();
    final trustedDevices = await trustRepo.getTrustedDevices();
    final fingerprint = publicKeyFingerprintBytes(peerPublicKey);
    
    bool keyChanged = false;
    bool isTrusted = false;

    // Check if the public key fingerprint is already trusted.
    for (final device in trustedDevices) {
      if (device.publicKeyFingerprint == fingerprint) {
        isTrusted = true;
        
        // Reconcile metadata if device name or ID has changed.
        if (device.stableId != peerDeviceId || device.name != peerDeviceName) {
          await trustRepo.saveTrustedDevice(
            peerDeviceName,
            ip,
            port,
            isTrusted: true,
            stableId: peerDeviceId,
            publicKeyFingerprint: fingerprint,
          );
        }
        break;
      }
    }

    // Detect if a known device ID is presenting an unrecognised public key (potential MITM or reinstall).
    if (!isTrusted) {
      for (final device in trustedDevices) {
        if (device.stableId == peerDeviceId && device.stableId != null && device.stableId!.isNotEmpty) {
          if (device.publicKeyFingerprint != null && device.publicKeyFingerprint != fingerprint) {
            keyChanged = true;
            break;
          }
        }
      }
    }

    if (!isTrusted || keyChanged) {
      if (onVerifyDevice == null) {
        throw Exception("Device verification required but no callback provided");
      }
      final userApproved = await onVerifyDevice!(peerPublicKey, sas, peerDeviceName, keyChanged: keyChanged);
      if (!userApproved) {
        throw Exception("Connection rejected by user");
      }
      await trustRepo.saveTrustedDevice(
        peerDeviceName,
        ip,
        port,
        isTrusted: true,
        stableId: peerDeviceId,
        publicKeyFingerprint: fingerprint,
      );
      return true;
    }

    return true;
  }

  Future<bool> isFingerprintTrusted(String fingerprint) async {
    final trustRepo = TrustRepository();
    final trustedDevices = await trustRepo.getTrustedDevices();
    try {
      final device = trustedDevices.firstWhere((d) => d.publicKeyFingerprint == fingerprint);
      return device.isTrusted;
    } catch (e) {
      return false;
    }
  }

  // Helpers
  String publicKeyFingerprintBytes(Uint8List bytes) {
    return _bytesToHex(bytes);
  }
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  Uint8List _hexToBytes(String hexStr) {
    if (hexStr.length % 2 != 0) throw Exception('Invalid hex string');
    var bytes = Uint8List(hexStr.length ~/ 2);
    for (var i = 0; i < hexStr.length; i += 2) {
      bytes[i ~/ 2] = int.parse(hexStr.substring(i, i + 2), radix: 16);
    }
    return bytes;
  }
}
