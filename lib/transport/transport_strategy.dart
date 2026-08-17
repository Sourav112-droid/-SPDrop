import 'dart:async';
import 'transport_connection.dart';

/// Defines a mode of connectivity (e.g. LAN, Hotspot, Manual).
abstract class TransportStrategy {
  /// The port the server is currently listening on, or 0 if not listening.
  int get serverPort;

  /// Stream of incoming connections from peers.
  Stream<TransportConnection> get onIncomingConnection;

  /// Starts listening for incoming connections on this transport.
  Future<void> startListening({required String deviceName});

  /// Stops listening and cleans up any transport-specific resources (e.g. hotspot).
  Future<void> stop();

  /// Attempts to connect to a peer given a list of IPs and a port.
  Future<TransportConnection> connect(List<String> ips, int port);

  /// Helper to get IPs advertised by this transport.
  Future<List<String>> getLocalIps();
}
