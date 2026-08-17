import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/peer_model.dart';
import 'discovery_strategy.dart';

/// Manages multiple discovery strategies and provides a unified, deduplicated list of peers.
class DiscoveryManager {
  final List<DiscoveryStrategy> _strategies;
  
  final Map<String, PeerModel> _discoveredPeers = {};
  final StreamController<List<PeerModel>> _peersController = StreamController<List<PeerModel>>.broadcast();

  final List<StreamSubscription> _subscriptions = [];
  Timer? _cleanupTimer;
  bool _isStopped = false;

  DiscoveryManager(this._strategies);

  Stream<List<PeerModel>> get peersStream => _peersController.stream;
  List<PeerModel> get currentPeers => _discoveredPeers.values.toList();

  Future<void> start() async {
    _isStopped = false;
    for (var strategy in _strategies) {
      if (_isStopped) break;
      _subscriptions.add(strategy.peersStream.listen(_onPeersDiscovered));
      await strategy.start();
    }

    if (_isStopped) return;

    // Periodically evict peers not seen within the stale threshold.
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _cleanupStalePeers();
    });
  }

  Future<void> stop() async {
    _isStopped = true;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    
    final futures = <Future>[];
    for (var sub in _subscriptions) {
      futures.add(sub.cancel());
    }
    _subscriptions.clear();

    for (var strategy in _strategies) {
      futures.add(strategy.stop());
    }
    
    _discoveredPeers.clear();
    _emitPeers();
    await Future.wait(futures);
  }

  /// Triggers network change rediscovery across all configured strategies.
  void refresh() {
    for (var strategy in _strategies) {
      strategy.onNetworkChanged();
    }
  }

  /// Manually registers a peer with immediate deduplication.
  void addManualPeer(PeerModel peer) {
    _mergePeer(peer);
    _emitPeers();
  }

  void _onPeersDiscovered(List<PeerModel> newPeers) {
    bool updated = false;
    for (var peer in newPeers) {
      if (_mergePeer(peer)) {
        updated = true;
      }
    }
    if (updated) {
      _emitPeers();
    }
  }

  bool _mergePeer(PeerModel peer) {
    // Index by stable device ID when available, falling back to endpoint address.
    final key = peer.deviceId.isNotEmpty ? peer.deviceId : '${peer.ips.first}:${peer.port}';

    if (_discoveredPeers.containsKey(key)) {
      final existing = _discoveredPeers[key]!;
      try {
        final merged = existing.merge(peer);
        _discoveredPeers[key] = merged;
        return true;
      } catch (e) {
        debugPrint('Failed to merge peers: $e');
        return false;
      }
    } else {
      _discoveredPeers[key] = peer;
      return true;
    }
  }

  void _cleanupStalePeers() {
    final now = DateTime.now();
    final staleThreshold = const Duration(seconds: 45);

    bool removed = false;
    _discoveredPeers.removeWhere((key, peer) {
      if (now.difference(peer.lastSeen) > staleThreshold) {
        removed = true;
        return true;
      }
      return false;
    });

    if (removed) {
      _emitPeers();
    }
  }

  void _emitPeers() {
    if (!_peersController.isClosed) {
      _peersController.add(_discoveredPeers.values.toList());
    }
  }

  void dispose() {
    stop();
    _peersController.close();
    for (var strategy in _strategies) {
      strategy.dispose();
    }
  }
}
