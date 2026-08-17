import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'transport_connection.dart';
import 'transport_strategy.dart';
import 'websocket_transport_connection.dart';

class ManualTransport implements TransportStrategy {
  @override
  int get serverPort => 0;

  @override
  Stream<TransportConnection> get onIncomingConnection => const Stream.empty();

  @override
  Future<void> startListening({required String deviceName}) async {
    // Outbound-only transport strategy; inbound listening is handled by LanTransport.
  }

  @override
  Future<void> stop() async {}

  @override
  Future<TransportConnection> connect(List<String> ips, int port) async {
    bool connected = false;
    WebSocketChannel? socket;

    for (int retry = 0; retry < 5; retry++) {
      for (String ip in ips) {
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
      throw Exception("Manual Transport: Connection failed to $ips:$port");
    }

    return WebSocketTransportConnection(socket);
  }

  @override
  Future<List<String>> getLocalIps() async {
    return [];
  }
}
