import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'transport_connection.dart';
import 'transport_strategy.dart';
import 'websocket_transport_connection.dart';

class LanTransport implements TransportStrategy {
  HttpServer? _server;
  final StreamController<TransportConnection> _incomingController = StreamController.broadcast();
  
  @override
  int get serverPort => _server?.port ?? 0;

  @override
  Stream<TransportConnection> get onIncomingConnection => _incomingController.stream;

  @override
  Future<void> startListening({required String deviceName}) async {
    if (_server != null) return;

    var handler = webSocketHandler((webSocket) {
      final conn = WebSocketTransportConnection(webSocket);
      _incomingController.add(conn);
    });

    try {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8888);
      debugPrint('[SP_DIAG][SERVER] LanTransport bound to port ${_server!.port}');
    } catch (e) {
      debugPrint('[SP_DIAG][SERVER] LanTransport port 8888 failed ($e), falling back to OS-assigned port');
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
      debugPrint('[SP_DIAG][SERVER] LanTransport bound to fallback port ${_server!.port}');
    }
  }
  
  @override
  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  @override
  Future<TransportConnection> connect(List<String> ips, int port) async {
    bool connected = false;
    WebSocketChannel? socket;

    for (int retry = 0; retry < 5; retry++) {
      for (String ip in ips) {
        if (ip == "127.0.0.1" && ips.length > 1) continue;
        try {
          final uri = Uri.parse('ws://$ip:$port');
          debugPrint('[SP_DIAG][CLIENT] LanTransport connecting to $uri (retry=$retry)');
          socket = WebSocketChannel.connect(uri);
          await socket.ready.timeout(const Duration(milliseconds: 8000));
          connected = true;
          debugPrint('[SP_DIAG][CLIENT] LanTransport connected to $uri');
          break;
        } catch (e) {
          debugPrint('[SP_DIAG][CLIENT] LanTransport connect failed to ws://$ip:$port: $e');
          socket?.sink.close();
          socket = null;
        }
      }
      if (connected) break;
      await Future.delayed(Duration(milliseconds: 1000 * (retry + 1)));
    }

    if (!connected || socket == null) {
      throw Exception("LAN Transport: Connection failed to $ips:$port");
    }

    return WebSocketTransportConnection(socket);
  }

  @override
  Future<List<String>> getLocalIps() async {
    final List<String> result = [];
    try {
      final info = NetworkInfo();
      var wifiIP = await info.getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty && wifiIP != "127.0.0.1") {
        result.add(wifiIP);
      }
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: true,
      );
      for (var interface_ in interfaces) {
        String name = interface_.name.toLowerCase();
        if (name.contains('virtual') || name.contains('docker') || name.contains('vpn')) continue;
        for (var addr in interface_.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4 && !result.contains(addr.address)) {
            result.add(addr.address);
          }
        }
      }
    } catch (_) {}
    return result.isEmpty ? ["127.0.0.1"] : result;
  }
}
