import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/peer_model.dart';
import '../../features/pairing/trust_repository.dart';
import 'discovery_strategy.dart';

/// Probes previously known trusted endpoints to detect available peers on the current network.
/// Uses bounded attempts with exponential backoff to avoid continuous network polling.
class CachedPeerStrategy extends DiscoveryStrategy {
  final TrustRepository _trustRepository;
  
  bool _isProbing = false;
  int _probeAttempt = 0;
  static const int _maxProbeAttempts = 3;
  static const Duration _baseBackoff = Duration(seconds: 2);

  CachedPeerStrategy(this._trustRepository);

  @override
  Future<void> start() async {
    if (isScanning) return;
    setScanning(true);
    _startBoundedProbing();
  }

  @override
  Future<void> stop() async {
    setScanning(false);
    _isProbing = false;
    _probeAttempt = 0;
    _delayTimer?.cancel();
    _delayTimer = null;
    if (!(_delayCompleter?.isCompleted ?? true)) _delayCompleter?.complete();
  }

  @override
  Future<void> onNetworkChanged() async {
    if (isScanning) {
      _probeAttempt = 0;
      _startBoundedProbing();
    }
  }

  /// Manually triggers a probing pass across cached peers.
  void refresh() {
    if (isScanning) {
      _probeAttempt = 0;
      _startBoundedProbing();
    }
  }

  Timer? _delayTimer;
  Completer<void>? _delayCompleter;

  Future<void> _startBoundedProbing() async {
    if (_isProbing || !isScanning) return;
    
    _isProbing = true;

    try {
      while (_probeAttempt < _maxProbeAttempts && isScanning) {
        _probeAttempt++;
        await _probeCachedPeers();

        if (_probeAttempt < _maxProbeAttempts && isScanning) {
          // Exponential backoff between probe rounds: 2s, 4s, 8s.
          final backoffDuration = _baseBackoff * (1 << (_probeAttempt - 1));
          
          _delayCompleter = Completer<void>();
          _delayTimer = Timer(backoffDuration, () {
            if (!(_delayCompleter?.isCompleted ?? true)) _delayCompleter?.complete();
          });
          await _delayCompleter?.future;
          _delayTimer = null;
        }
      }
    } finally {
      _isProbing = false;
    }
  }

  Future<void> _probeCachedPeers() async {
    try {
      final trustedDevices = await _trustRepository.getTrustedDevices();
      if (trustedDevices.isEmpty) return;

      final discoveredPeers = <PeerModel>[];

      await Future.wait(trustedDevices.map((device) async {
        if (!isScanning) return;
        
        final isAlive = await _checkEndpoint(device.ip, device.port);
        if (isAlive) {
          discoveredPeers.add(
            PeerModel(
              deviceId: device.stableId ?? '',
              name: device.name,
              platform: device.platform,
              ips: [device.ip],
              port: device.port,
              discoverySources: {DiscoverySource.cached},
              lastSeen: DateTime.now(),
            )
          );
        }
      }));

      if (discoveredPeers.isNotEmpty && isScanning) {
        emitPeers(discoveredPeers);
      }
    } catch (e) {
      debugPrint('Error probing cached peers: $e');
    }
  }

  Future<bool> _checkEndpoint(String ip, int port) async {
    try {
      // Verifies endpoint reachability via a lightweight TCP connection attempt.
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 1));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
