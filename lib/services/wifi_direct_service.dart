import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Manages Android Wi-Fi Direct (P2P) and Local-Only Hotspot platform integrations for routerless transfers.
class WifiDirectService {
  static const _channel = MethodChannel('com.example.p2p_sync_app/wifi_p2p');
  static const _hotspotChannel = MethodChannel('com.example.p2p_sync_app/wifi_direct');

  Function(bool enabled)? onWifiP2pStateChanged;
  Function(List<Map<String, dynamic>> peers)? onPeersFound;
  Function(bool isGroupOwner, String groupOwnerIp)? onConnected;
  Function()? onDisconnected;

  bool _isInitialized = false;
  bool _isGroupOwner = false;
  String? _groupOwnerIp;
  String? _hotspotSsid;
  String? _hotspotPassword;
  bool _isOfflineModeActive = false;

  bool get isGroupOwner => _isGroupOwner;
  String? get groupOwnerIp => _groupOwnerIp;
  String? get hotspotSsid => _hotspotSsid;
  String? get hotspotPassword => _hotspotPassword;
  bool get isOfflineModeActive => _isOfflineModeActive;

  /// Initializes Wi-Fi Direct platform channel listeners.
  Future<void> initialize() async {
    if (!Platform.isAndroid || _isInitialized) return;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onWifiP2pStateChanged':
          final enabled = call.arguments['enabled'] as bool;
          onWifiP2pStateChanged?.call(enabled);
          break;
        case 'onPeersFound':
          final peers = List<Map<String, dynamic>>.from(
            (call.arguments as List).map((e) => Map<String, dynamic>.from(e)),
          );
          onPeersFound?.call(peers);
          break;
        case 'onConnected':
          _isGroupOwner = call.arguments['isGroupOwner'] as bool;
          _groupOwnerIp = call.arguments['groupOwnerAddress'] as String?;
          onConnected?.call(_isGroupOwner, _groupOwnerIp ?? '192.168.49.1');
          break;
        case 'onDisconnected':
          _isGroupOwner = false;
          _groupOwnerIp = null;
          onDisconnected?.call();
          break;
      }
    });

    try {
      await _channel.invokeMethod('initialize');
      await _channel.invokeMethod('registerReceiver');
      _isInitialized = true;
    } catch (e) {
      debugPrint("Wi-Fi Direct init error: $e");
    }
  }

  /// Creates a Wi-Fi Direct group with this device acting as Group Owner (standard IP: 192.168.49.1).
  Future<Map<String, dynamic>?> createGroup() async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMethod<Map>('createGroup')
          .timeout(const Duration(seconds: 10));
      if (result != null) {
        _isGroupOwner = true;
        _isOfflineModeActive = true;
        _groupOwnerIp = result['groupOwnerIp'] as String?;
        return Map<String, dynamic>.from(result);
      }
    } on TimeoutException {
      debugPrint("Create group timed out (10s)");
      return null;
    } catch (e) {
      debugPrint("Create group error: $e");
    }
    return null;
  }

  /// Removes the active Wi-Fi Direct group.
  Future<void> removeGroup() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('removeGroup');
      _isGroupOwner = false;
      _groupOwnerIp = null;
    } catch (e) {
      debugPrint("Remove group error: $e");
    }
  }

  /// Initiates scanning for nearby Wi-Fi Direct peers.
  Future<bool> discoverPeers() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('discoverPeers') ?? false;
    } catch (e) {
      debugPrint("Discover peers error: $e");
      return false;
    }
  }

  /// Halts active Wi-Fi Direct peer discovery.
  Future<void> stopDiscovery() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopDiscovery');
    } catch (e) {
      debugPrint("Stop discovery error: $e");
    }
  }

  /// Connects to a remote peer via MAC address.
  Future<bool> connectToPeer(String deviceAddress) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('connectToPeer', {
        'deviceAddress': deviceAddress,
      }) ?? false;
    } catch (e) {
      debugPrint("Connect to peer error: $e");
      return false;
    }
  }

  /// Disconnects from the currently connected peer.
  Future<void> disconnectPeer() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('disconnect');
    } catch (e) {
      debugPrint("Disconnect error: $e");
    }
  }

  /// Starts an Android Local-Only Hotspot for routerless connection with desktop peers.
  Future<Map<String, String>?> startHotspot() async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _hotspotChannel.invokeMethod<Map>('startHotspot')
          .timeout(const Duration(seconds: 10));
      if (result != null) {
        _hotspotSsid = result['ssid'] as String?;
        _hotspotPassword = result['password'] as String?;
        _isOfflineModeActive = true;
        return {
          'ssid': _hotspotSsid ?? '',
          'password': _hotspotPassword ?? '',
        };
      }
    } on TimeoutException {
      debugPrint("Start hotspot timed out (10s)");
      return null;
    } catch (e) {
      debugPrint("Start hotspot error: $e");
    }
    return null;
  }

  /// Stops the active Local-Only Hotspot.
  Future<void> stopHotspot() async {
    if (!Platform.isAndroid) return;
    try {
      await _hotspotChannel.invokeMethod('stopHotspot');
      _hotspotSsid = null;
      _hotspotPassword = null;
      _isOfflineModeActive = false;
    } catch (e) {
      debugPrint("Stop hotspot error: $e");
    }
  }

  /// Clean up all resources
  Future<void> cleanup() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('unregisterReceiver');
    } catch (_) {}
    _isInitialized = false;
    _isGroupOwner = false;
    _groupOwnerIp = null;
    _hotspotSsid = null;
    _hotspotPassword = null;
  }
}
