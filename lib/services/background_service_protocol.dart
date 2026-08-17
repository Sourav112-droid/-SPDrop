/// Message protocol defining RPC commands and events exchanged between the UI and background isolate.
library;

enum RpcCommand {
  startDiscovery,
  stopDiscovery,
  connect,
  disconnect,
  sendClipboard,
  autoSendFiles,
  updateState
}

enum RpcEvent {
  devicesUpdated,
  connectionStateChanged,
  clipboardReceived,
  fileProgress,
  transferStage,
  filesReceived,
  filesSent,
  notification
}

class RpcMessage {
  final String type;
  final Map<String, dynamic> payload;

  RpcMessage(this.type, this.payload);

  Map<String, dynamic> toJson() => {'type': type, 'payload': payload};
  
  factory RpcMessage.fromJson(Map<String, dynamic> json) {
    return RpcMessage(json['type'], json['payload']);
  }
}
