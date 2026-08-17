import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/trusted_device.dart';

class TrustRepository {
  static const String _keyTrustedDevices = 'trusted_devices';

  // ── Trusted Devices ──

  Future<List<TrustedDevice>> getTrustedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_keyTrustedDevices);
    if (jsonList == null) return [];

    return jsonList
        .map((str) => TrustedDevice.fromJson(jsonDecode(str)))
        .toList();
  }

  /// Persists a trusted device entry, preserving existing trust flags and cryptographic fingerprints across IP updates.
  Future<void> saveTrustedDevice(
    String name,
    String ip,
    int port, {
    String platform = 'unknown',
    bool? isTrusted,
    bool? notificationsEnabled,
    bool isDefault = false,
    String? stableId,
    String? publicKeyFingerprint,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_keyTrustedDevices) ?? [];

    bool existingTrusted = false;
    bool existingNotifs = false;
    bool existingDefault = false;
    String? existingStableId;
    String? existingFingerprint;
    for (final str in jsonList) {
      final d = jsonDecode(str);
      if ((stableId != null && d['stableId'] == stableId) || d['name'] == name) {
        existingTrusted = d['isTrusted'] == true;
        existingNotifs = d['notificationsEnabled'] == true;
        existingStableId = d['stableId'] as String?;
        existingFingerprint = d['publicKeyFingerprint'] as String?;
        existingDefault = d['isDefault'] == true;
        break;
      }
    }

    jsonList.removeWhere((str) {
      final d = jsonDecode(str);
      if (stableId != null && d['stableId'] == stableId) return true;
      return d['name'] == name;
    });

    final device = TrustedDevice(
      name: name,
      ip: ip,
      port: port,
      lastSeen: DateTime.now(),
      platform: platform,
      isTrusted: isTrusted ?? existingTrusted,
      notificationsEnabled: notificationsEnabled ?? existingNotifs,
      isDefault: isDefault ? true : existingDefault,
      stableId: stableId ?? existingStableId,
      publicKeyFingerprint: publicKeyFingerprint ?? existingFingerprint,
    );
    jsonList.add(jsonEncode(device.toJson()));

    if (jsonList.length > 20) {
      jsonList.removeAt(0);
    }

    await prefs.setStringList(_keyTrustedDevices, jsonList);
  }

  Future<void> removeTrustedDevice(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_keyTrustedDevices) ?? [];

    jsonList.removeWhere((str) {
      final d = jsonDecode(str);
      return d['name'] == name;
    });

    await prefs.setStringList(_keyTrustedDevices, jsonList);
  }

  /// Checks whether a peer device is marked as trusted.
  Future<bool> isDeviceTrusted(String name) async {
    final devices = await getTrustedDevices();
    return devices.any((d) => d.name == name && d.isTrusted);
  }

  /// Looks up a specific trusted device entry by name.
  Future<TrustedDevice?> getTrustedDevice(String name) async {
    final devices = await getTrustedDevices();
    try {
      return devices.firstWhere((d) => d.name == name);
    } catch (_) {
      return null;
    }
  }

  /// Updates the notification permission flag for a trusted peer.
  Future<void> updateNotificationSetting(String name, bool enabled) async {
    final devices = await getTrustedDevices();
    final device = devices.where((d) => d.name == name).firstOrNull;
    if (device != null) {
      await saveTrustedDevice(
        device.name,
        device.ip,
        device.port,
        platform: device.platform,
        isTrusted: device.isTrusted,
        notificationsEnabled: enabled,
      );
    }
  }

  Future<void> setDefaultDevice(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_keyTrustedDevices) ?? [];
    List<String> newList = [];
    for (var str in jsonList) {
      final d = jsonDecode(str);
      d['isDefault'] = (d['name'] == name);
      newList.add(jsonEncode(d));
    }
    await prefs.setStringList(_keyTrustedDevices, newList);
  }
  
  Future<TrustedDevice?> getDefaultDevice() async {
    final devices = await getTrustedDevices();
    try {
      return devices.firstWhere((d) => d.isDefault);
    } catch (_) {
      return null;
    }
  }
}
