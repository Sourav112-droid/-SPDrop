import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/history/history_repository.dart';
import '../features/pairing/trust_repository.dart';

import '../features/transfer/models/transfer_record.dart';
export '../features/transfer/models/transfer_record.dart';
import '../features/pairing/models/trusted_device.dart';
export '../features/pairing/models/trusted_device.dart';

/// Compatibility facade for legacy consumers.
/// Delegates transfer history and peer trust to focused repositories.
class HistoryService {
  final HistoryRepository _historyRepository = HistoryRepository();
  final TrustRepository _trustRepository = TrustRepository();

  static const String _keyName = 'device_name';
  static const String _keyLastConnected = 'last_connected_device';

  // ── Delegated Transfer History ──
  Future<List<TransferRecord>> getHistory() => _historyRepository.getHistory();
  Future<void> logTransfer(String filename, String direction, {String? filePath, int? fileSize, String? peerDevice}) =>
      _historyRepository.logTransfer(filename, direction, filePath: filePath, fileSize: fileSize, peerDevice: peerDevice);
  Future<void> clearAllHistory() => _historyRepository.clearAllHistory();
  Future<void> deleteRecord(String filename, DateTime timestamp) => _historyRepository.deleteRecord(filename, timestamp);

  // ── Delegated Trusted Devices ──
  Future<List<TrustedDevice>> getTrustedDevices() => _trustRepository.getTrustedDevices();
  Future<void> saveTrustedDevice(String name, String ip, int port, {String platform = 'unknown', bool? isTrusted, bool? notificationsEnabled, bool isDefault = false, String? stableId, String? publicKeyFingerprint}) =>
      _trustRepository.saveTrustedDevice(name, ip, port, platform: platform, isTrusted: isTrusted, notificationsEnabled: notificationsEnabled, isDefault: isDefault, stableId: stableId, publicKeyFingerprint: publicKeyFingerprint);
  Future<void> removeTrustedDevice(String name) => _trustRepository.removeTrustedDevice(name);
  Future<bool> isDeviceTrusted(String name) => _trustRepository.isDeviceTrusted(name);
  Future<TrustedDevice?> getTrustedDevice(String name) => _trustRepository.getTrustedDevice(name);
  Future<void> updateNotificationSetting(String name, bool enabled) => _trustRepository.updateNotificationSetting(name, enabled);
  Future<void> setDefaultDevice(String? name) => _trustRepository.setDefaultDevice(name);
  Future<TrustedDevice?> getDefaultDevice() => _trustRepository.getDefaultDevice();

  // ── Retained Methods (To be extracted in later stages) ──
  Future<String?> getSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyName);
  }
  
  Future<void> saveName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, name);
  }
  
  String generatePairingCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }
  
  Future<void> saveLastConnected(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastConnected, name);
  }
  
  Future<String?> getLastConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastConnected);
  }
}
