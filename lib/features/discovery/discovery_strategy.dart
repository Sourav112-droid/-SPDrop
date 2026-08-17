import 'dart:async';
import '../../models/peer_model.dart';

/// Contract for peer discovery mechanisms (mDNS, UDP broadcast, cached probing).
abstract class DiscoveryStrategy {
  final StreamController<List<PeerModel>> _peersController = StreamController<List<PeerModel>>.broadcast();

  /// Stream of discovered peers emitted by this strategy.
  Stream<List<PeerModel>> get peersStream => _peersController.stream;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  /// Starts peer discovery.
  Future<void> start();

  /// Stops peer discovery and releases resources.
  Future<void> stop();

  /// Emits discovered peers to subscribers.
  void emitPeers(List<PeerModel> peers) {
    if (!_peersController.isClosed) {
      _peersController.add(peers);
    }
  }

  /// Notifies the strategy that local network configuration has changed.
  Future<void> onNetworkChanged() async {}

  /// Updates active scanning state.
  void setScanning(bool scanning) {
    _isScanning = scanning;
  }

  /// Releases stream and internal resources.
  void dispose() {
    _peersController.close();
  }
}
