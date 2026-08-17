import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/identity/identity_service.dart';
import '../transport/transport_manager.dart';
import '../transport/transport_connection.dart';
import '../transport/websocket_transport_connection.dart';
import '../features/discovery/discovery_manager.dart';
import '../features/discovery/mdns_discovery_strategy.dart';
import '../features/discovery/udp_discovery_strategy.dart';
import '../features/discovery/cached_peer_strategy.dart';
import '../models/peer_model.dart';
import '../features/pairing/trust_repository.dart';
import '../features/pairing/pairing_service.dart';
import '../shared/utils/network_utils.dart' as network_utils;

import '../features/discovery/models/discovered_device.dart';
export '../features/discovery/models/discovered_device.dart';

class LocalSignalingService {
  // Callbacks
  Future<bool> Function(String senderName, String batchManifest, int totalSize)?
  onConnectionRequest;
  Function(int port, String ip)? onFileTransferApproved;
  Function()? onTransferAccepted;
  Function(int)? onPortFallback;
  Function(
    String text, 
    String? html, 
    String? eventId, 
    String? originDeviceId, 
    int? timestamp, 
    String? contentHash
  )? onClipboardReceived;
  Function()? onConnectionLocked;
  Function(double, double)? onRemoteProgressReceived;
  Function(String)? onConnectionDeclined;

  // New callbacks
  Function(String deviceName, String platform)? onDeviceConnected;
  Function()? onDeviceDisconnected;
  Function(Map<String, dynamic>)? onNotificationReceived;
  Function(List<DiscoveredDevice>)? onDevicesUpdated;

  // Connection diagnostics callback
  Function(String errorDetail)? onConnectionDiagnostic;

  // Server & Socket
  HttpServer? _server;
  TransportConnection? _socket;
  TransportManager? _transportManager;

  // Pairing service — lazily initialized with access to signaling internals
  PairingService? _pairingService;

  /// Provides access to the pairing orchestration service.
  PairingService get pairingService {
    _pairingService ??= PairingService(
      sendMessage: _sendSignalingMessage,
      getDeviceName: () => _myDeviceName ?? 'Device',
      getPlatform: () => _currentPlatform,
    );
    return _pairingService!;
  }

  void setTransportManager(TransportManager tm) {
    _transportManager = tm;
    _transportManager!.onIncomingConnection.listen(_handleIncomingConnection);
  }

  void _handleIncomingConnection(TransportConnection conn) {
    if (_isPersistentConnection && _socket != null) {
      conn.close();
      return;
    }
    _socket = conn;
    _isPersistentConnection = true;
    _disconnecting = false;
    _startPingTimer();
    _socket!.stream.listen(
      (message) {
        try {
          var decoded = jsonDecode(message);
          if (decoded['type'] == 'ping') {
            _sendSignalingMessage({'type': 'pong'});
            return;
          } else if (decoded['type'] == 'pong') {
            _pongReceived = true;
            return;
          }
          _handleSignalingMessage(decoded);
        } catch (e) {
          debugPrint("Signaling Parse Error: $e");
        }
      },
      onError: (e) {
        debugPrint("Transport error: $e");
        _handleDisconnect();
      },
      onDone: () {
        _handleDisconnect();
      },
    );
  }

  bool _isPersistentConnection = false;
  String? _connectedDeviceName;
  String? _connectedDevicePlatform;

  // mDNS & Discovery
  Registration? _registration;

  // Replace old mDNS Discovery with DiscoveryManager
  DiscoveryManager? _discoveryManager;
  StreamSubscription<List<PeerModel>>? _discoverySubscription;
  List<DiscoveredDevice> _devices = [];

  // Server & Connection State
  int get serverPort =>
      _transportManager?.lanServerPort ?? (_server?.port ?? 0);
  bool get isConnected => _socket != null && _isPersistentConnection;
  String? get connectedDeviceName => _connectedDeviceName;
  String? get connectedDevicePlatform => _connectedDevicePlatform;
  bool get isRunning => _isRunning;

  // Heartbeat
  Timer? _pingTimer;
  final Map<Timer, Completer<void>> _activeDelays = {};

  Future<void> _safeDelay(Duration duration) async {
    if (!_isRunning) return;
    final completer = Completer<void>();
    final timer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    _activeDelays[timer] = completer;
    try {
      await completer.future;
    } finally {
      _activeDelays.remove(timer);
    }
  }
  bool _pongReceived = true;
  int _missedPongs = 0; // Track consecutive missed pongs
  bool _isRunning = false;
  bool _disconnecting = false; // Guard against double-disconnect
  bool _postTransferGrace = false; // Grace period after transfer

  // Transfer-aware ping
  bool transferInProgress = false;
  // Public setter for post-transfer grace period
  set postTransferGrace(bool value) => _postTransferGrace = value;

  // Self-discovery filter
  String? _myLocalIp;
  // ignore: unused_field
  List<String> _myLocalIps =
      []; // No longer used for self-filter, kept for diagnostics

  // Stable device ID for deduplication
  String? _stableDeviceId;

  // Connection persistence don't disconnect on background
  bool _keepAliveInBackground = true;
  bool _isPaused = false;

  // Reconnection state
  String? _myDeviceName;
  
  // Connected peer's public key fingerprint (from handshake)
  String? connectedPeerPublicKeyFingerprint;
  String? _lastPeerIp;
  int? _lastPeerPort;
  int? get lastPeerPort => _lastPeerPort;
  bool _shouldReconnect = false;
  Timer? _reconnectTimer;

  // Set stable device ID from SharedPreferences
  void setStableDeviceId(String id) {
    _stableDeviceId = id;
  }

  String? get stableDeviceId => _stableDeviceId;

  // : Keep mDNS registration alive in background.
  // Don't stop scanning completely the device must remain discoverable.
  Timer? _reRegistrationTimer;
  Timer? _networkCheckTimer;
  Timer? _disconnectGuardTimer;
  String? _lastAdvertisedIps;

  void pauseService() {
    _isPaused = true;
    // Keep mDNS registration alive only pause discovery scanning
    // but keep the service registered so other devices can find us
    stopScanning();
    // Start periodic re-registration to combat OS killing mDNS
    _reRegistrationTimer?.cancel();
    _reRegistrationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isRunning && _myDeviceName != null) {
        _reRegisterMdns(_myDeviceName!);
      }
    });
  }

  void resumeService(String deviceName) async {
    _isPaused = false;
    _myDeviceName = deviceName;
    // Cancel background re-registration timer
    _reRegistrationTimer?.cancel();

    // Refresh local IPs to handle DHCP changes during background
    _myLocalIp = await getLocalIp();
    _myLocalIps = await getAllLocalIps();

    // Force-reset scanning state and restart discovery.
    await stopScanning();
    await startScanning();
  }

  // Keep connection alive flag
  void setKeepAliveInBackground(bool keepAlive) {
    _keepAliveInBackground = keepAlive;
  }

  Completer<void>? _registrationLock;
  String? _registeredName; // Track what name we registered with

  // Expose connected peer's real IP for trusted device updates
  String? connectedPeerIp;
  // Expose connected peer's stableId for deduplication
  String? connectedPeerStableId;

  // Platform detection
  String get _currentPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }

  // Bidirectional Mode Run BOTH server + scanner simultaneously

  Future<void> startService(String deviceName) async {
    // Stronger guard skip if already running with same name AND registration is active
    if (_isRunning && _registration != null && _registeredName == deviceName) {
      debugPrint('startService: already running as "$deviceName", skipping');
      return;
    }
    _isRunning = true;
    _myDeviceName = deviceName;
    _myLocalIp = await getLocalIp();
    _myLocalIps = await getAllLocalIps();
    if (!_isRunning) return;
    await _startServer(deviceName);
    if (!_isRunning) return;
    await startScanning();
  }

  // 1. Host Mode (Server accepts incoming connections)

  Future<void> _startServer(String deviceName) async {
    // Acquire registration lock to prevent cloning
    if (_registrationLock != null && !_registrationLock!.isCompleted) {
      await _registrationLock!.future;
    }
    if (!_isRunning) return;
    _registrationLock = Completer<void>();

    try {
      // Start listening via TransportManager instead of direct shelf_io
      if (_transportManager != null) {
        await _transportManager!.startListening(deviceName: deviceName);
      }
      int port = serverPort;
      debugPrint('[SP_DIAG][SERVER] Server started on port $port');

      // Skip re-registration if already registered with same name
      // This is the key fix for the cloning issue
      if (_registration != null && _registeredName == deviceName) {
        debugPrint(
          '_startServer: already registered as "$deviceName", skipping re-registration',
        );
        return;
      }

      // Unregister any stale registration
      await _safeUnregister();

      // Brief delay for mDNS cache propagation
      await _safeDelay(const Duration(milliseconds: 300));

      // Advertise ALL local IPs
      final allIps = await getAllLocalIps();
      final ip = await getLocalIp();
      final ipStr = allIps.isNotEmpty ? allIps.join('|') : ip;

      final service = Service(
        name: deviceName,
        type: '_p2psync._tcp',
        port: port,
        txt: {
          'ip': utf8.encode(ipStr),
          'platform': utf8.encode(_currentPlatform),
          'id': utf8.encode(_stableDeviceId ?? ''),
        },
      );
      debugPrint('[SP_DIAG][MDNS] Registering mDNS: name=$deviceName port=$port ips=$ipStr');
      _registration = await register(service);
      _registeredName = deviceName;
    } catch (e) {
      debugPrint("mDNS Server Error: $e");
    } finally {
      if (_registrationLock != null && !_registrationLock!.isCompleted) {
        _registrationLock!.complete();
      }
    }
  }

  /// Safe unregister that handles errors gracefully
  Future<void> _safeUnregister() async {
    if (_registration != null) {
      try {
        await unregister(_registration!);
      } catch (_) {}
      _registration = null;
      _registeredName = null;
    }
  }

  // : Re-register mDNS in background to stay discoverable.
  Future<void> _reRegisterMdns(String deviceName) async {
    // Use serverPort instead of _server?.port
    // _server is null after TransportManager refactor; serverPort reads from TransportManager.
    final port = serverPort;
    if (port == 0) return; // No server listening yet
    try {
      final allIps = await getAllLocalIps();
      final ipStr = allIps.join('|');
      if (_registration == null) {
        final service = Service(
          name: deviceName,
          type: '_p2psync._tcp',
          port: port,
          txt: {
            'ip': utf8.encode(ipStr),
            'platform': utf8.encode(_currentPlatform),
            'id': utf8.encode(_stableDeviceId ?? ''),
          },
        );
        debugPrint('[SP_DIAG][MDNS] Re-registering mDNS: port=$port ips=$ipStr');
        _registration = await register(service);
        _registeredName = deviceName;
        debugPrint('Re-registered mDNS in background');
      }
    } catch (e) {
      debugPrint('mDNS re-registration failed: $e');
    }
  }

  // Keep legacy methods working
  Future<void> startReceiving(String deviceName) async {
    await startService(deviceName);
  }

  Future<void> startScanning() async {
    if (!_isRunning) return;
    if (_discoveryManager != null) {
      debugPrint('startScanning: already scanning, skipping');
      return;
    }

    try {
      // 1. Initialize TrustRepository for CachedPeerStrategy
      final trustRepository = TrustRepository();

      // 2. Initialize Strategies
      final stableId = _stableDeviceId ?? '';

      final mdnsStrategy = MdnsDiscoveryStrategy(stableId);

      final udpStrategy = UdpDiscoveryStrategy(
        stableDeviceId: stableId,
        getDeviceName: () => _myDeviceName ?? 'Unknown',
        platform: _currentPlatform,
        getTcpPort: () => serverPort,
        discoveryPort: 45454, // Configurable constant
      );

      final cachedStrategy = CachedPeerStrategy(trustRepository);

      // 3. Start DiscoveryManager
      _discoveryManager = DiscoveryManager([
        mdnsStrategy,
        udpStrategy,
        cachedStrategy,
      ]);

      _discoverySubscription = _discoveryManager!.peersStream.listen((peers) {
        // Convert PeerModel to DiscoveredDevice for backward compatibility
        _devices = peers
            .map(
              (p) => DiscoveredDevice(
                name: p.name,
                ips: p.ips,
                port: p.port,
                platform: p.platform,
                stableId: p.deviceId,
              ),
            )
            .toList();

        // Multi-layered self-device filter (still required in facade)
        final filtered = _devices.where((d) => !_isSelfDevice(d)).toList();

        if (onDevicesUpdated != null) {
          onDevicesUpdated!(filtered);
        }
      });

      await _discoveryManager!.start();
    } catch (e) {
      debugPrint("Discovery Scan Error: $e");
    }
  }

  /// Check if a discovered device is actually THIS device (self-filtering)
  bool _isSelfDevice(DiscoveredDevice d) {
    // 1. Primary: filter by stable device ID (most reliable)
    if (_stableDeviceId != null &&
        _stableDeviceId!.isNotEmpty &&
        d.stableId != null &&
        d.stableId!.isNotEmpty &&
        d.stableId == _stableDeviceId) {
      return true;
    }

    // 2. Secondary: filter by name
    if (_myDeviceName != null && d.name == _myDeviceName) {
      return true;
    }

    // 3. Fallback: filter by IP if device ID and name check passed (unlikely but safe)
    if (_myLocalIp != null && d.ips.contains(_myLocalIp)) {
      return true;
    }

    return false;
  }

  Future<void> stopScanning() async {
    if (_discoveryManager != null) {
      await _discoveryManager!.stop();
      _discoveryManager = null;
      _discoverySubscription?.cancel();
      _discoverySubscription = null;
    }
  }

  // IP Lookup Multi-IP support


  Future<String> getLocalIp() => network_utils.getLocalIp();
  Future<List<String>> getAllLocalIps() => network_utils.getAllLocalIps();
  // Connection Management Improved reliability

  Future<void> connectToDevice(
    List<String> ips,
    int port,
    String myDeviceName,
  ) async {
    _myDeviceName = myDeviceName;
    bool connected = false;

    debugPrint('[SP_DIAG][CLIENT] connectToDevice: ips=$ips port=$port');
    if (_transportManager != null) {
      final peer = PeerModel(
        deviceId: stableDeviceId ?? "unknown",
        name: connectedDeviceName ?? "unknown",
        platform: 'unknown',
        ips: ips,
        port: port,
        discoverySources: {DiscoverySource.manual},
        lastSeen: DateTime.now(),
      );
      // connectToPeer throws on failure (never returns null).
      // Wrap in try-catch so that failure flows through to _diagnoseConnection
      // and onConnectionDeclined, instead of escaping as an uncaught exception.
      try {
        final conn = await _transportManager!.connectToPeer(peer);
        _socket = conn;
        _lastPeerIp = ips.first;
        _lastPeerPort = port;
        connected = true;
        debugPrint('[SP_DIAG][CLIENT] connectToPeer succeeded to $ips:$port');
      } catch (e) {
        debugPrint('[SP_DIAG][CLIENT] connectToPeer failed: $e');
        // Fall through to diagnostic block below
      }
    } else {
      // Fallback
      for (int retry = 0; retry < 5; retry++) {
        for (String ip in ips) {
          if (ip == "127.0.0.1" && ips.length > 1) continue;
          try {
            final uri = Uri.parse('ws://$ip:$port');
            final wsConn = WebSocketChannel.connect(uri);
            await wsConn.ready.timeout(const Duration(milliseconds: 8000));
            _socket = WebSocketTransportConnection(wsConn);
            _lastPeerIp = ip;
            _lastPeerPort = port;
            connected = true;
            break;
          } catch (e) {
            debugPrint("Connection attempt $ip:$port failed: $e");
          }
        }
        if (connected) break;
        await _safeDelay(Duration(milliseconds: 1000 * (retry + 1)));
      }
    }

    if (!connected || _socket == null) {
      // Better error diagnostics
      final diagnostic = await _diagnoseConnection(ips, port);
      if (onConnectionDeclined != null) {
        onConnectionDeclined!(diagnostic);
      }
      throw Exception("Connection failed: $diagnostic");
    }

    _startPingTimer();

    _socket!.stream.listen(
      (message) {
        var decoded = jsonDecode(message);
        if (decoded['type'] == 'ping') {
          _sendSignalingMessage({'type': 'pong'});
          return;
        } else if (decoded['type'] == 'pong') {
          _pongReceived = true;
          return;
        }
        _handleSignalingMessage(decoded);
      },
      onError: (e) {
        _stopPingTimer();
        _handleDisconnect();
      },
      onDone: () {
        _stopPingTimer();
        _handleDisconnect();
      },
    );

    // Send connection handshake with platform info AND our real IP/port
    final myIp = await getLocalIp();
    _sendSignalingMessage({
      'type': 'connect',
      'deviceName': myDeviceName,
      'platform': _currentPlatform,
      'ip': myIp,
      'port': serverPort, // Use actual server port, not null _server
      'stableId': _stableDeviceId ?? '', // Include for dedup
      'publicKeyFingerprint': IdentityService().publicKeyFingerprint,
    });
  }

  /// Connection diagnostic provides actionable error info
  Future<String> _diagnoseConnection(List<String> ips, int port) async {
    final List<String> issues = [];

    for (var ip in ips) {
      if (ip == "127.0.0.1") continue;
      try {
        // Try raw TCP connection
        final socket = await Socket.connect(
          ip,
          port,
          timeout: const Duration(seconds: 2),
        );
        await socket.close();
        issues.add(
          "TCP reachable on $ip but WebSocket failed Ã¢â‚¬â€ possible firewall or protocol issue",
        );
      } catch (e) {
        if (e.toString().contains('Connection refused')) {
          issues.add(
            "Port $port is closed on $ip Ã¢â‚¬â€ app may not be running on peer",
          );
        } else if (e.toString().contains('timed out') ||
            e.toString().contains('Timeout')) {
          issues.add(
            "$ip unreachable Ã¢â‚¬â€ devices may not be on the same network",
          );
        } else {
          issues.add(
            "Cannot reach device at $ip:$port Ã¢â‚¬â€ Network error or firewall block.",
          );
        }
      }
    }

    if (issues.isEmpty) {
      return "No IPs available for connection";
    }
    return issues.first;
  }

  // Legacy method wraps connectToDevice + sends transfer request
  Future<void> requestConnection(
    List<String> ips,
    int port,
    String myDeviceName,
    String batchManifest,
    int totalSize,
  ) async {
    if (!_isPersistentConnection || _socket == null) {
      await connectToDevice(ips, port, myDeviceName);
    }

    _sendSignalingMessage({
      'type': 'offer_with_request',
      'senderName': myDeviceName,
      'batchManifest': batchManifest,
      'totalSize': totalSize,
    });
  }

  // Added _disconnecting guard to prevent double-disconnect
  // from onError+onDone firing simultaneously on socket close.
  void _handleDisconnect() {
    // Don't process disconnect after stop() has been called.
    if (!_isRunning) return;
    // Prevent double-disconnect from simultaneous onError+onDone
    if (_disconnecting) return;
    _disconnecting = true;

    final wasConnected = _isPersistentConnection;
    _isPersistentConnection = false;
    _connectedDeviceName = null;
    _connectedDevicePlatform = null;
    _socket = null;
    _stopPingTimer();
    _missedPongs = 0;

    onDeviceDisconnected?.call();

    // Auto-reconnect for trusted devices
    if (wasConnected && _shouldReconnect && _lastPeerIp != null) {
      _startReconnectTimer();
    }

    // Reset guard after processing
    _disconnectGuardTimer?.cancel();
    if (_isRunning) {
      _disconnectGuardTimer = Timer(const Duration(milliseconds: 100), () {
        _disconnecting = false;
      });
    } else {
      _disconnecting = false;
    }
  }

  void _startReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_isPersistentConnection || !_shouldReconnect) {
        timer.cancel();
        return;
      }
      try {
        await connectToDevice(
          [_lastPeerIp!],
          _lastPeerPort!,
          _myDeviceName ?? 'Device',
        );
        timer.cancel();
      } catch (_) {
        // Will retry on next timer tick
      }
    });
  }

  void enableAutoReconnect(bool enable) {
    _shouldReconnect = enable;
    if (!enable) _reconnectTimer?.cancel();
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _isPersistentConnection = false;
    _connectedDeviceName = null;
    _connectedDevicePlatform = null;
    _sendSignalingMessage({'type': 'disconnect'});
    _socket?.close();
    _socket = null;
    _stopPingTimer();
    onDeviceDisconnected?.call();
  }

  // Pairing — delegated to PairingService
  // See lib/features/pairing/pairing_service.dart

  // Messaging

  void _sendSignalingMessage(Map<String, dynamic> data) {
    if (_socket != null) {
      try {
        _socket!.send(jsonEncode(data));
      } catch (e) {
        debugPrint("Send failed: $e");
      }
    }
  }

  void _startPingTimer() {
    _pongReceived = true;
    _missedPongs = 0; // Reset counter
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      // Skip timeout check during active file transfers
      // Also skip during post-transfer grace period
      if (transferInProgress || _postTransferGrace) {
        _pongReceived = true;
        _missedPongs = 0;
        _sendSignalingMessage({'type': 'ping'});
        return;
      }
      if (!_pongReceived) {
        _missedPongs++;
        // Require 2 consecutive missed pongs before disconnect
        // This prevents spurious disconnects from single delayed pongs
        if (_missedPongs >= 2) {
          debugPrint(
            "Ping timeout Ã¢â‚¬â€ peer unresponsive ($_missedPongs missed pongs)",
          );
          _handleDisconnect();
          return;
        }
        debugPrint("Ping: missed pong $_missedPongs/2, retrying...");
      } else {
        _missedPongs = 0;
      }
      _pongReceived = false;
      _sendSignalingMessage({'type': 'ping'});
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
  }

  VoidCallback? _discoveryListener;

  void _handleSignalingMessage(Map<String, dynamic> data) async {
    String type = data['type'];

    switch (type) {
      case 'connect':
        // Incoming persistent connection
        final deviceName = data['deviceName'] ?? 'Unknown';
        final platform = data['platform'] ?? 'unknown';
        _isPersistentConnection = true;
        _connectedDeviceName = deviceName;
        _connectedDevicePlatform = platform;
        // Store peer's real IP from handshake
        connectedPeerIp = data['ip'] as String?;
        if (data['port'] != null) {
          _lastPeerPort = data['port'] as int?;
        }
        if (connectedPeerIp != null) {
          _lastPeerIp = connectedPeerIp;
        }
        // Store peer's stableId for deduplication
        connectedPeerStableId = data['stableId'] as String?;
        // Store peer's public key fingerprint
        connectedPeerPublicKeyFingerprint = data['publicKeyFingerprint'] as String?;
        // Send back our info with our real IP/port
        final myIpForAck = _myLocalIp ?? await getLocalIp();
        _sendSignalingMessage({
          'type': 'connect_ack',
          'deviceName': _myDeviceName ?? 'Device',
          'platform': _currentPlatform,
          'ip': myIpForAck,
          'port': serverPort, // Use actual server port, not null _server
          'stableId': _stableDeviceId ?? '',
          'publicKeyFingerprint': IdentityService().publicKeyFingerprint,
        });
        onDeviceConnected?.call(deviceName, platform);
        break;

      case 'connect_ack':
        final deviceName = data['deviceName'] ?? 'Unknown';
        final platform = data['platform'] ?? 'unknown';
        _isPersistentConnection = true;
        _connectedDeviceName = deviceName;
        _connectedDevicePlatform = platform;
        // Store peer's real IP from handshake
        connectedPeerIp = data['ip'] as String?;
        if (data['port'] != null) {
          _lastPeerPort = data['port'] as int?;
        }
        if (connectedPeerIp != null) {
          _lastPeerIp = connectedPeerIp;
        }
        // Store peer's stableId for deduplication
        connectedPeerStableId = data['stableId'] as String?;
        // Store peer's public key fingerprint
        connectedPeerPublicKeyFingerprint = data['publicKeyFingerprint'] as String?;
        onDeviceConnected?.call(deviceName, platform);
        break;

      case 'disconnect':
        _handleDisconnect();
        break;

      case 'offer_with_request':
        String senderName = data['senderName'] ?? 'Unknown Device';
        String batchManifest = data['batchManifest'] ?? '[]';
        int totalSize = data['totalSize'] ?? 0;

        bool accepted = true;
        if (onConnectionRequest != null) {
          accepted = await onConnectionRequest!(
            senderName,
            batchManifest,
            totalSize,
          );
        }

        if (accepted) {
          _sendSignalingMessage({'type': 'accepted'});
        } else {
          _sendSignalingMessage({'type': 'declined'});
        }
        break;

      case 'accepted':
        onTransferAccepted?.call();
        break;

      case 'tcp_port':
        onConnectionLocked?.call();
        if (onFileTransferApproved != null) {
          final peerIp = data['ip'] as String? ?? '';
          onFileTransferApproved!(data['port'], peerIp);
        }
        break;

      case 'declined':
        onConnectionDeclined?.call("Transfer declined by peer");
        break;

      case 'clipboard':
        onClipboardReceived?.call(
          data['text'] ?? '', 
          data['html'],
          data['eventId'],
          data['originDeviceId'],
          data['createdAt'],
          data['contentHash'],
        );
        break;

      case 'progress':
        onRemoteProgressReceived?.call(
          data['value']?.toDouble() ?? 0.0,
          data['speed']?.toDouble() ?? 0.0,
        );
        break;

      // Pairing messages — delegated to PairingService
      case 'pair_request':
      case 'pair_response':
      case 'pair_confirmed':
        pairingService.handlePairingMessage(data);
        break;

      // Notification forwarding
      case 'notification':
        onNotificationReceived?.call({
          'package': data['package'] ?? '',
          'title': data['title'] ?? '',
          'text': data['text'] ?? '',
        });
        break;
    }
  }

  // Clipboard & Progress & Notifications

  void sendClipboardText(
    String text, 
    {String? html, 
    String? eventId, 
    String? originDeviceId, 
    int? timestamp, 
    String? contentHash}
  ) {
    _sendSignalingMessage({
      'type': 'clipboard', 
      'text': text, 
      'html': html,
      'eventId': eventId,
      'originDeviceId': originDeviceId,
      'createdAt': timestamp,
      'contentHash': contentHash,
      'contentType': 'text',
    });
  }

  void sendProgress(double progress, double speed) {
    _sendSignalingMessage({
      'type': 'progress',
      'value': progress,
      'speed': speed,
    });
  }

  Future<void> sendTcpPort(int port) async {
    final ip = await getLocalIp();
    _sendSignalingMessage({'type': 'tcp_port', 'port': port, 'ip': ip});
  }

  void sendNotification(String package, String title, String text) {
    _sendSignalingMessage({
      'type': 'notification',
      'package': package,
      'title': title,
      'text': text,
    });
  }

  // Session Lock (during file transfer keep connection but stop discovery)

  Future<void> lockSession() async {
    await _safeUnregister();
    try {
      await stopScanning();
    } catch (_) {}
  }

  Future<void> unlockSession(String deviceName) async {
    // Use registration lock to prevent cloning
    if (_registrationLock != null && !_registrationLock!.isCompleted) {
      await _registrationLock!.future;
    }
    _registrationLock = Completer<void>();

    _myDeviceName = deviceName;
    try {
      // Always unregister old registration first to prevent cloning
      await _safeUnregister();

      // Brief delay for mDNS cache propagation
      await _safeDelay(const Duration(milliseconds: 300));

      final allIps = await getAllLocalIps();
      final ipStr = allIps.join('|');
      final port = _server?.port ?? 8888;

      final service = Service(
        name: deviceName,
        type: '_p2psync._tcp',
        port: port,
        txt: {
          'ip': utf8.encode(ipStr),
          'platform': utf8.encode(_currentPlatform),
          'id': utf8.encode(_stableDeviceId ?? ''),
        },
      );
      _registration = await register(service);
      _registeredName = deviceName;
      _lastAdvertisedIps = ipStr;

      // Only restart scanning if not already running
      if (_discoveryManager == null) {
        await startScanning();
      }
    } catch (e) {
      debugPrint("Failed to re-register mDNS: $e");
    } finally {
      if (_registrationLock != null && !_registrationLock!.isCompleted) {
        _registrationLock!.complete();
      }
    }
  }

  // Lifecycle

  Future<void> stop() async {
    _isRunning = false;
    _reRegistrationTimer?.cancel();
    _stopPingTimer();
    _reconnectTimer?.cancel();
    _networkCheckTimer?.cancel();
    _disconnectGuardTimer?.cancel();
    
    for (var entry in _activeDelays.entries) {
      if (entry.key.isActive) entry.key.cancel();
      if (!entry.value.isCompleted) entry.value.complete();
    }
    _activeDelays.clear();

    await stopScanning();

    _isRunning = false;
    _shouldReconnect = false;
    _isPersistentConnection = false;
    _connectedDeviceName = null;
    _connectedDevicePlatform = null;
    _registeredName = null;
    await lockSession();
    _server?.close();
    _server = null;
    _socket?.close();
    _socket = null;
  }
}

