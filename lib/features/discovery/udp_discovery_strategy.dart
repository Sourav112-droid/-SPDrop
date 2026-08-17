import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/peer_model.dart';
import 'discovery_strategy.dart';

/// Discovers peers by broadcasting UDP datagrams on the local network segment.
class UdpDiscoveryStrategy extends DiscoveryStrategy {
  static const int _maxPacketSize = 512;
  
  final String _stableDeviceId;
  final String Function() _getDeviceName;
  final String _platform;
  final int Function() _getTcpPort;
  final int _discoveryPort;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  bool _isStopped = false;

  UdpDiscoveryStrategy({
    required this._stableDeviceId,
    required this._getDeviceName,
    required this._platform,
    required this._getTcpPort,
    this._discoveryPort = 45454,
  });

  @override
  Future<void> start() async {
    if (isScanning && _socket != null) return;
    _isStopped = false;

    try {
      await stop();
      _isStopped = false;

      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _discoveryPort, reuseAddress: true, reusePort: true);
      if (_isStopped) {
        _socket?.close();
        _socket = null;
        return;
      }
      _socket!.broadcastEnabled = true;

      _socket!.listen(_onRawData, onError: (e) {
        debugPrint('UDP Discovery Error: $e');
      });

      setScanning(true);

      _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _broadcastPresence();
      });
      _broadcastPresence();
    } catch (e) {
      debugPrint('Failed to start UDP discovery: $e');
    }
  }

  void _broadcastPresence() {
    if (_socket == null) return;
    
    final payload = {
      'type': 'SPDROP_DISCOVERY',
      'id': _stableDeviceId,
      'name': _getDeviceName(),
      'platform': _platform,
      'port': _getTcpPort(),
    };

    try {
      final data = utf8.encode(jsonEncode(payload));
      if (data.length <= _maxPacketSize) {
        _socket!.send(data, InternetAddress('255.255.255.255'), _discoveryPort);
      }
    } catch (e) {
      debugPrint('UDP broadcast error: $e');
    }
  }

  void _onRawData(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final datagram = _socket?.receive();
      if (datagram == null) return;

      // Drop oversized datagrams to prevent unbounded memory allocation.
      if (datagram.data.length > _maxPacketSize) return;

      try {
        final message = utf8.decode(datagram.data);
        final payload = jsonDecode(message);

        if (payload is Map<String, dynamic> && payload['type'] == 'SPDROP_DISCOVERY') {
          final deviceId = payload['id'] as String?;
          final name = payload['name'] as String?;
          final platform = payload['platform'] as String?;
          final port = payload['port'] as int?;

          if (deviceId == null || name == null || port == null) return;
          if (deviceId == _stableDeviceId) return; // Filter out self
          if (deviceId.length > 100 || name.length > 100) return;
          if (port <= 0 || port > 65535) return;

          final peer = PeerModel(
            deviceId: deviceId,
            name: name,
            platform: platform ?? 'unknown',
            ips: [datagram.address.address],
            port: port,
            discoverySources: {DiscoverySource.udp},
            lastSeen: DateTime.now(),
          );

          emitPeers([peer]);
        }
      } catch (_) {
        // Discard malformed or untrusted packets silently.
      }
    }
  }

  @override
  Future<void> stop() async {
    _isStopped = true;
    setScanning(false);
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _socket?.close();
    _socket = null;
  }
}
