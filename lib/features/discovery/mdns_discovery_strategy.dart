import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart';
import '../../models/peer_model.dart';
import 'discovery_strategy.dart';

/// Discovers local network peers broadcasting via multicast DNS (_p2psync._tcp).
class MdnsDiscoveryStrategy extends DiscoveryStrategy {
  Discovery? _discovery;
  Timer? _debounceTimer;
  final String _stableDeviceId; // Used to filter out self-advertised services
  bool _isStopped = false;

  MdnsDiscoveryStrategy(this._stableDeviceId);

  @override
  Future<void> start() async {
    if (isScanning && _discovery != null) {
      return;
    }
    _isStopped = false;

    try {
      await stop();
      _isStopped = false;

      var discovery = await startDiscovery('_p2psync._tcp', autoResolve: true);
      if (_isStopped) {
        await stopDiscovery(discovery);
        return;
      }
      _discovery = discovery;
      setScanning(true);

      _discovery!.addListener(_onServicesUpdated);
    } catch (e) {
      debugPrint("MdnsDiscoveryStrategy Error starting: $e");
    }
  }

  void _onServicesUpdated() {
    if (_discovery == null) return;
    
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      final peers = <PeerModel>[];

      for (var s in _discovery!.services) {
        final peer = _parseService(s);
        if (peer != null && peer.deviceId != _stableDeviceId) {
          peers.add(peer);
        }
      }

      emitPeers(peers);
    });
  }

  PeerModel? _parseService(Service s) {
    List<String> ips = [];
    String platform = 'unknown';
    String? deviceId;

    if (s.txt != null) {
      if (s.txt!['ip'] != null) {
        try {
          String txtIp = utf8.decode(s.txt!['ip']!);
          if (txtIp.contains('|')) {
            for (var singleIp in txtIp.split('|')) {
              if (singleIp.isNotEmpty && singleIp != "127.0.0.1") {
                ips.add(singleIp);
              }
            }
          } else if (txtIp.isNotEmpty && txtIp != "127.0.0.1") {
            ips.add(txtIp);
          }
        } catch (e) {
          debugPrint("TXT IP decode error: $e");
        }
      }
      if (s.txt!['platform'] != null) {
        try {
          platform = utf8.decode(s.txt!['platform']!);
        } catch (_) {}
      }
      if (s.txt!['id'] != null) {
        try {
          deviceId = utf8.decode(s.txt!['id']!);
        } catch (_) {}
      }
    }

    if (s.addresses != null) {
      for (var addr in s.addresses!) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          if (!ips.contains(addr.address)) {
            ips.add(addr.address);
          }
        }
      }
    }
    
    if (ips.isEmpty) return null;

    final name = s.name ?? 'Unknown';

    return PeerModel(
      deviceId: deviceId ?? '',
      name: name,
      platform: platform,
      ips: ips,
      port: s.port ?? 0,
      discoverySources: {DiscoverySource.mDNS},
      lastSeen: DateTime.now(),
    );
  }

  @override
  Future<void> stop() async {
    _isStopped = true;
    setScanning(false);
    _debounceTimer?.cancel();
    if (_discovery != null) {
      try {
        _discovery!.removeListener(_onServicesUpdated);
        await stopDiscovery(_discovery!);
      } catch (e) {
        debugPrint("MdnsDiscoveryStrategy Error stopping: $e");
      }
      _discovery = null;
    }
  }
}
