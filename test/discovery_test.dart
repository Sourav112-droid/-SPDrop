import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_sync_app/models/peer_model.dart';
import 'package:p2p_sync_app/features/discovery/discovery_manager.dart';
import 'package:p2p_sync_app/features/discovery/discovery_strategy.dart';

class MockDiscoveryStrategy extends DiscoveryStrategy {
  void emit(List<PeerModel> peers) {
    emitPeers(peers);
  }

  @override
  Future<void> start() async {
    setScanning(true);
  }

  @override
  Future<void> stop() async {
    setScanning(false);
  }
}

void main() {
  group('PeerModel tests', () {
    test('merge identical deviceId preserves latest lastSeen and merges sources', () {
      final p1 = PeerModel(
        deviceId: 'id1',
        name: 'Device A',
        platform: 'android',
        ips: ['192.168.1.5'],
        port: 8888,
        discoverySources: {DiscoverySource.mDNS},
        lastSeen: DateTime(2023, 1, 1),
      );

      final p2 = PeerModel(
        deviceId: 'id1',
        name: 'Device A Updated',
        platform: 'android',
        ips: ['192.168.1.6'],
        port: 8889,
        discoverySources: {DiscoverySource.udp},
        lastSeen: DateTime(2023, 1, 2),
      );

      final merged = p1.merge(p2);

      expect(merged.deviceId, 'id1');
      expect(merged.name, 'Device A Updated'); // took newest
      expect(merged.port, 8889); // took newest
      expect(merged.ips, containsAll(['192.168.1.5', '192.168.1.6']));
      expect(merged.discoverySources, containsAll([DiscoverySource.mDNS, DiscoverySource.udp]));
      expect(merged.lastSeen, DateTime(2023, 1, 2));
    });

    test('equality uses deviceId if present', () {
      final p1 = PeerModel(
        deviceId: 'id1',
        name: 'A',
        platform: 'android',
        ips: ['1.1.1.1'],
        port: 8888,
        discoverySources: {},
        lastSeen: DateTime.now(),
      );

      final p2 = PeerModel(
        deviceId: 'id1',
        name: 'B',
        platform: 'windows',
        ips: ['2.2.2.2'],
        port: 9999,
        discoverySources: {},
        lastSeen: DateTime.now(),
      );

      expect(p1 == p2, isTrue);
      expect(p1.hashCode, p2.hashCode);
    });

    test('equality falls back to IP and port if deviceId is empty', () {
      final p1 = PeerModel(
        deviceId: '',
        name: 'A',
        platform: 'android',
        ips: ['1.1.1.1', '10.0.0.1'],
        port: 8888,
        discoverySources: {},
        lastSeen: DateTime.now(),
      );

      final p2 = PeerModel(
        deviceId: '',
        name: 'B',
        platform: 'windows',
        ips: ['1.1.1.1'],
        port: 8888,
        discoverySources: {},
        lastSeen: DateTime.now(),
      );

      expect(p1 == p2, isTrue);
    });
  });

  group('DiscoveryManager deduplication', () {
    test('merges peers from different strategies with same deviceId', () async {
      final s1 = MockDiscoveryStrategy();
      final s2 = MockDiscoveryStrategy();
      final manager = DiscoveryManager([s1, s2]);
      
      await manager.start();

      s1.emit([
        PeerModel(
          deviceId: 'id_123',
          name: 'MyPhone',
          platform: 'android',
          ips: ['192.168.1.100'],
          port: 8888,
          discoverySources: {DiscoverySource.mDNS},
          lastSeen: DateTime.now(),
        )
      ]);

      s2.emit([
        PeerModel(
          deviceId: 'id_123',
          name: 'MyPhone',
          platform: 'android',
          ips: ['192.168.1.100'],
          port: 8888,
          discoverySources: {DiscoverySource.udp},
          lastSeen: DateTime.now().add(const Duration(seconds: 1)),
        )
      ]);

      // Allow streams to process
      await Future.delayed(const Duration(milliseconds: 100));

      final peers = manager.currentPeers;
      expect(peers.length, 1);
      expect(peers.first.deviceId, 'id_123');
      expect(peers.first.discoverySources.length, 2);
      expect(peers.first.discoverySources, containsAll([DiscoverySource.mDNS, DiscoverySource.udp]));
      
      await manager.stop();
    });
  });
}
