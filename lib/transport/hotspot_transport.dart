import 'dart:async';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:io';

import '../services/wifi_direct_service.dart';
import 'transport_connection.dart';
import 'transport_strategy.dart';
import 'websocket_transport_connection.dart';

class HotspotTransport implements TransportStrategy {
  final WifiDirectService _wifiDirectService;
  HttpServer? _server;
  final StreamController<TransportConnection> _incomingController = StreamController.broadcast();

  HotspotTransport(this._wifiDirectService);

  @override
  int get serverPort => _server?.port ?? 0;

  @override
  Stream<TransportConnection> get onIncomingConnection => _incomingController.stream;

  @override
  Future<void> startListening({required String deviceName}) async {
    if (_server != null) return;
    
    final hotspotInfo = await _wifiDirectService.startHotspot();
    if (hotspotInfo == null) {
      throw Exception("Failed to start Hotspot");
    }

    var handler = webSocketHandler((webSocket) {
      final conn = WebSocketTransportConnection(webSocket);
      _incomingController.add(conn);
    });

    try {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8888);
    } catch (e) {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
    }
  }

  @override
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    await _wifiDirectService.stopHotspot();
  }

  @override
  Future<TransportConnection> connect(List<String> ips, int port) async {
    bool connected = false;
    WebSocketChannel? socket;

    for (int retry = 0; retry < 5; retry++) {
      for (String ip in ips) {
        if (ip == "127.0.0.1") continue;
        try {
          final uri = Uri.parse('ws://$ip:$port');
          socket = WebSocketChannel.connect(uri);
          await socket.ready.timeout(const Duration(milliseconds: 8000));
          connected = true;
          break;
        } catch (e) {
          socket?.sink.close();
          socket = null;
        }
      }
      if (connected) break;
      await Future.delayed(Duration(milliseconds: 1000 * (retry + 1)));
    }

    if (!connected || socket == null) {
      throw Exception("Hotspot Transport: Connection failed to $ips:$port");
    }

    return WebSocketTransportConnection(socket);
  }

  @override
  Future<List<String>> getLocalIps() async {
    final List<String> result = [];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: true,
      );
      for (var interface_ in interfaces) {
        String name = interface_.name.toLowerCase();
        if (name.contains('wlan') || name.contains('ap') || name.contains('hotspot')) {
          for (var addr in interface_.addresses) {
            result.add(addr.address);
          }
        }
      }
    } catch (_) {}
    return result;
  }
}
