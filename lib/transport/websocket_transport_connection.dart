import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'transport_connection.dart';

class WebSocketTransportConnection implements TransportConnection {
  final WebSocketChannel _channel;
  final StreamController<dynamic> _streamController = StreamController<dynamic>.broadcast();

  WebSocketTransportConnection(this._channel) {
    _channel.stream.listen(
      (data) {
        if (!_streamController.isClosed) {
          _streamController.add(data);
        }
      },
      onError: (e) {
        if (!_streamController.isClosed) {
          _streamController.addError(e);
        }
      },
      onDone: () {
        if (!_streamController.isClosed) {
          _streamController.close();
        }
      },
    );
  }

  @override
  Stream<dynamic> get stream => _streamController.stream;

  @override
  void send(String data) {
    _channel.sink.add(data);
  }

  @override
  Future<void> close() async {
    await _channel.sink.close();
    if (!_streamController.isClosed) {
      await _streamController.close();
    }
  }

  @override
  Sink<dynamic> get sink => _channel.sink;
}
