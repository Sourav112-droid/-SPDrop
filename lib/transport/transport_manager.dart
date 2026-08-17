import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../models/peer_model.dart';
import '../services/wifi_direct_service.dart';
import 'transport_connection.dart';
import 'lan_transport.dart';
import 'hotspot_transport.dart';
import 'wifi_direct_transport.dart';
import 'manual_transport.dart';

class TransportManager {
  final LanTransport _lanTransport = LanTransport();
  late final HotspotTransport _hotspotTransport;
  late final WifiDirectTransport _wifiDirectTransport;
  final ManualTransport _manualTransport = ManualTransport();

  final StreamController<TransportConnection> _incomingConnections = StreamController.broadcast();

  TransportManager(WifiDirectService wifiDirectService) {
    _hotspotTransport = HotspotTransport(wifiDirectService);
    _wifiDirectTransport = WifiDirectTransport(wifiDirectService);

    _lanTransport.onIncomingConnection.listen(_incomingConnections.add);
    _hotspotTransport.onIncomingConnection.listen(_incomingConnections.add);
    _wifiDirectTransport.onIncomingConnection.listen(_incomingConnections.add);
  }

  Stream<TransportConnection> get onIncomingConnection => _incomingConnections.stream;

  Future<void> startListening({required String deviceName}) async {
    await _lanTransport.startListening(deviceName: deviceName);
  }

  Future<void> startHotspot({required String deviceName}) async {
    await _hotspotTransport.startListening(deviceName: deviceName);
  }

  Future<void> startWifiDirect({required String deviceName}) async {
    await _wifiDirectTransport.startListening(deviceName: deviceName);
  }

  Future<void> stop() async {
    await _lanTransport.stop();
    await _hotspotTransport.stop();
    await _wifiDirectTransport.stop();
    await _manualTransport.stop();
  }

  int get lanServerPort => _lanTransport.serverPort;

  Future<List<String>> getLocalIps() => _lanTransport.getLocalIps();

  Future<TransportConnection> connectToPeer(PeerModel peer) async {
    debugPrint('[SP_DIAG][CLIENT] TransportManager.connectToPeer: ips=${peer.ips} port=${peer.port} sources=${peer.discoverySources}');
    if (peer.ips.isNotEmpty && _hasNonLocalhost(peer.ips)) {
      try {
        debugPrint("TransportManager: Attempting LAN connection to ${peer.ips}");
        return await _lanTransport.connect(peer.ips, peer.port);
      } catch (e) {
        debugPrint("TransportManager: LAN connection failed: $e");
      }
    }

    if (peer.discoverySources.contains(DiscoverySource.manual)) {
      try {
        debugPrint("TransportManager: Attempting Manual connection to ${peer.ips}");
        return await _manualTransport.connect(peer.ips, peer.port);
      } catch (e) {
        debugPrint("TransportManager: Manual connection failed: $e");
      }
    }

    if (peer.ips.contains("192.168.49.1")) {
      try {
        debugPrint("TransportManager: Attempting Wi-Fi Direct connection");
        return await _wifiDirectTransport.connect(peer.ips, peer.port);
      } catch (e) {
        debugPrint("TransportManager: Wi-Fi Direct connection failed: $e");
      }
    }
    
    if (peer.ips.any((ip) => ip.startsWith("192.168.43.") || ip.startsWith("192.168."))) {
        try {
          debugPrint("TransportManager: Attempting Hotspot connection");
          return await _hotspotTransport.connect(peer.ips, peer.port);
        } catch (e) {
          debugPrint("TransportManager: Hotspot connection failed: $e");
        }
    }

    debugPrint('[SP_DIAG][CLIENT] TransportManager: ALL transport strategies exhausted for ${peer.ips}:${peer.port}');
    throw Exception("TransportManager: Exhausted all transport strategies for peer ${peer.deviceId}");
  }

  bool _hasNonLocalhost(List<String> ips) {
    return ips.any((ip) => ip != "127.0.0.1" && ip != "localhost");
  }
}
