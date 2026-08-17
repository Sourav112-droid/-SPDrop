import 'dart:async';

/// Represents an active transport connection (e.g., a WebSocket or raw TCP socket).
abstract class TransportConnection {
  /// The stream of incoming data (usually Strings for JSON).
  Stream<dynamic> get stream;

  /// Sends a string message over the transport.
  void send(String data);

  /// Closes the connection.
  Future<void> close();

  /// Sink for sending data, useful if you want to pipe streams
  Sink<dynamic> get sink;
}
