import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_animate/flutter_animate.dart';

import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:convert';
import 'dart:async';


import 'src/rust/frb_generated.dart';
import 'services/local_signaling_service.dart';
import 'transport/transport_manager.dart';
import 'services/rust_file_service.dart';
import 'services/clipboard_service.dart';
import 'services/history_service.dart';
import 'features/history/history_repository.dart';
import 'features/pairing/trust_repository.dart';
import 'services/notification_service.dart';
import 'services/wifi_direct_service.dart';
import 'core/theme/theme_service.dart';
import 'services/system_tray_service.dart';
import 'core/identity/identity_service.dart';


import 'core/platform/platform_service.dart';
import 'core/platform/stub_platform.dart';
import 'core/platform/android_platform.dart';
import 'core/platform/windows_platform.dart';

import 'shared/widgets/glass_card.dart';
import 'shared/widgets/pulse_indicator.dart';
import 'widgets/device_card.dart';
import 'widgets/transfer_overlay.dart';
import 'widgets/pairing_dialog.dart';
import 'widgets/trust_device_dialog.dart';
import 'widgets/incoming_transfer_dialog.dart';
import 'widgets/settings_drawer.dart';

final StreamController<List<String>> singleInstanceArgsStream = StreamController<List<String>>.broadcast();

PlatformService getPlatformService() {
  if (Platform.isAndroid) return AndroidPlatform();
  if (Platform.isWindows) return WindowsPlatform();
  return StubPlatform();
}
final platformService = getPlatformService();

// Android background entry points moved to android_platform.dart

// Global theme service instance
final ThemeService themeService = ThemeService();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Removed FlutterForegroundTask.initCommunicationPort() since it does not exist in
  
  try {
    await themeService.initialize();
  } catch (e) {
    debugPrint("Theme init error: $e");
  }

  try {
    await RustLib.init();
  } catch (e) {
    debugPrint("RustLib init error: $e");
  }

  try {
    await IdentityService().init();
  } catch (e) {
    debugPrint("IdentityService init error: $e");
  }
  
  // Initialize WorkManager for periodic background reconnect
  await platformService.initialize();
  await platformService.setupBackgroundTasks();
  
  // Detect --tray mode (used by Windows auto-start and boot)
  final bool startInTray = args.contains('--tray');
  
  await platformService.handlePlatformArgs(args, onArgsReceived: (newArgs) {
    singleInstanceArgsStream.add(newArgs);
  });

  runApp(SpDropApp(args: args, startInTray: startInTray));
}

// Windows auto-start logic moved to windows_platform.dart

class SpDropApp extends StatelessWidget {
  final List<String> args;
  final bool startInTray;
  const SpDropApp({super.key, this.args = const [], this.startInTray = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) {
        final td = themeService.themeData;
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            ColorScheme lightColorScheme;
            ColorScheme darkColorScheme;

            if (lightDynamic != null && darkDynamic != null) {
              lightColorScheme = lightDynamic.harmonized();
              darkColorScheme = darkDynamic.harmonized();
            } else {
              lightColorScheme = ColorScheme.fromSeed(
                seedColor: td.primary,
                brightness: Brightness.light,
              );
              darkColorScheme = ColorScheme.fromSeed(
                seedColor: td.primary,
                brightness: Brightness.dark,
              );
            }

            final isDark = td.brightness == Brightness.dark;
            return SpDropThemeProvider(
              themeData: td,
              child: MaterialApp(
                title: 'SpDrop',
                theme: ThemeData(
                  useMaterial3: true,
                  colorScheme: lightColorScheme,
                  brightness: Brightness.light,
                ),
                darkTheme: ThemeData(
                  useMaterial3: true,
                  colorScheme: darkColorScheme,
                  brightness: Brightness.dark,
                ),
                themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
                home: MainScreen(args: args, startInTray: startInTray),
                debugShowCheckedModeBanner: false,
              ),
            );
          },
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  final List<String> args;
  final bool startInTray;
  const MainScreen({super.key, this.args = const [], this.startInTray = false});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  Timer? _disconnectRestartTimer;
  final Set<Timer> _delayedTimers = {};

  void _safeDelayed(Duration duration, void Function() callback) {
    late Timer timer;
    timer = Timer(duration, () {
      _delayedTimers.remove(timer);
      if (mounted) callback();
    });
    _delayedTimers.add(timer);
  }

  // â” â” Services â” â”
  final LocalSignalingService _signalingService = LocalSignalingService();
  final RustFileService _fileService = RustFileService();
  final ClipboardService _clipboardService = ClipboardService();
  final HistoryService _historyService = HistoryService();
  final HistoryRepository _historyRepository = HistoryRepository();
  final TrustRepository _trustRepository = TrustRepository();
  final NotificationService _notificationService = NotificationService();
  final WifiDirectService _wifiDirectService = WifiDirectService();
  late TransportManager _transportManager;
  final SystemTrayService _systemTrayService = SystemTrayService(); // System tray

  // â” â” State â” â”
  String _connectionStatus = 'Initializing...';
  bool _isWindowClosing = false; // Re-entrant guard for window close
  final bool _isQuitting = false;
  double _fileProgress = 0.0;
  double _speedMBps = 0.0;
  String _currentTransferFile = '';
  String _transferStage = '';
  bool _isFileTransferring = false;
  bool _isTransferComplete = false;

  List<DiscoveredDevice> _nearbyDevices = [];
  String _deviceName = "Device_${DateTime.now().millisecondsSinceEpoch % 1000}";

  final List<SpDropFile> _pendingFiles = [];
  int _etaSeconds = 0;

  // Persistent connection state
  bool _isConnected = false;
  String? _connectedDeviceName;
  String? _connectedDevicePlatform;

  // Offline mode
  bool _isOfflineMode = false;
  bool _isOfflineModeLoading = false; // Loading guard
  
  bool _clipboardSyncEnabled = false; // Opt-in clipboard sync
  List<Map<String, dynamic>> _wifiDirectPeers = [];

  // Trusted devices
  List<TrustedDevice> _trustedDevices = [];

  // Pairing
  String? _wifiDirectGroupOwnerIp;

  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  // Notification forwarding
  bool _notificationsEnabled = false;

  DateTime _lastProgressUpdate = DateTime.now();

  static const qsChannel = MethodChannel('com.example.p2p_sync_app/quick_settings');
  StreamSubscription? _singleInstanceSub;
  StreamSubscription? _mediaStreamSub;

  @override
  void initState() {
    super.initState();
    _transportManager = TransportManager(_wifiDirectService);
    _signalingService.setTransportManager(_transportManager);
    WidgetsBinding.instance.addObserver(this);

    _clipboardService.setSignalingService(_signalingService);
    _clipboardService.setIsolationCallback(() => _isFileTransferring);
    _clipboardService.setFileTransferCallback((files) async {
       final ip = _signalingService.connectedPeerIp;
       final port = _signalingService.lastPeerPort;
       if (ip != null && port != null) {
          final spFiles = files.map((f) => SpDropFile(f, isClipboard: true)).toList();
          await _fileService.sendFiles(spFiles, 0, ip, port, useE2ee: true);
       }
    });
    _notificationService.setSignalingService(_signalingService);

    _loadTrustedDevices();

    // Initialize system tray on Windows
    if (Platform.isWindows) {
      windowManager.addListener(this);
      _initSystemTray();
    }

    // Handle files passed via command line args on Windows
    if (Platform.isWindows) {
      _handleWindowsShareArgs(widget.args); // use widget.args directly
      
      _singleInstanceSub = singleInstanceArgsStream.stream.listen((newArgs) {
        _handleWindowsShareArgs(newArgs);
      });
    }

    // Quick Settings channel handler
    qsChannel.setMethodCallHandler((call) async {
      if (call.method == 'triggerReceiveMode') {
        _startService();
      } else if (call.method == 'toggleConnection') {
        _handleQuickSettingsToggle();
      }
    });

    // Handle share intents for ALL file types
    if (Platform.isAndroid || Platform.isIOS) {
      _mediaStreamSub = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
        _handleSharedMedia(value);
      });

      ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
        if (!mounted) return;
        if (value.isNotEmpty) {
          _safeDelayed(const Duration(seconds: 1), () => _handleSharedMedia(value));
        }
      });
    }

    _requestPermissions().then((_) async {
      if (!mounted) return;
      // Generate stable device ID for clone prevention
      final stableId = await _getOrCreateStableDeviceId();
      _signalingService.setStableDeviceId(stableId);

      IdentityService().deviceId = stableId;
      IdentityService().deviceName = _deviceName;

      // Setup Identity Verification Callback
      IdentityService().onVerifyDevice = (peerPublicKey, sas, peerDeviceName, {bool keyChanged = false}) async {
        if (!mounted) return false;
        return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => TrustDeviceDialog(
            deviceName: peerDeviceName,
            platform: 'Unknown',
            peerPublicKey: peerPublicKey,
            sas: sas,
            keyChanged: keyChanged,
          ),
        ) ?? false;
      };

      String? savedName = await _historyService.getSavedName();
      if (savedName != null && savedName.isNotEmpty) {
        _deviceName = savedName;
      }
      
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _clipboardSyncEnabled = prefs.getBool('clipboard_sync_enabled') ?? false;
      setState(() {});
      if (_clipboardSyncEnabled) {
        _clipboardService.startSync();
      }

      if (Platform.isAndroid) {
        qsChannel.invokeMethod<bool>('checkPendingReceiveMode').then((shouldStart) {
          if (!mounted) return;
          if (shouldStart == true) _startService();
        });
        // Initialize Wi-Fi Direct
        _wifiDirectService.initialize();
      }

      // Start bidirectional service only if not already running
      if (!_signalingService.isRunning) {
        _startService();
      }
    });

    _setupServiceCallbacks();
  }

  // System tray initialization
  Future<void> _initSystemTray() async {
    _systemTrayService.onShowWindow = () {
      _showWindowFromTray(); // Reset close guard when window is shown
    };
    _systemTrayService.onQuickSend = () {
      _pickAndSendFiles(); // Quick send from tray
    };
    _systemTrayService.onConnectLastDevice = () async {
      // Connect to last trusted device from tray
      final lastDevice = await _historyService.getLastConnected();
      if (lastDevice != null) {
        final device = await _trustRepository.getTrustedDevice(lastDevice);
        if (device != null && device.ip.isNotEmpty) {
          try {
            await _signalingService.connectToDevice(
              [device.ip], device.port, _deviceName,
            );
            _showSnackBar('Connected to ${device.name}', isSuccess: true);
          } catch (e) {
            _showSnackBar('Connection failed. Please ensure the target device is reachable on the network.', isError: true);
          }
        }
      }
    };
    _systemTrayService.onDisconnect = () {
      if (_isConnected) {
        _signalingService.disconnect();
      }
    };
    _systemTrayService.onQuit = () {
      _clipboardService.stopSync();
      _signalingService.stop();
    };
    await _systemTrayService.initialize();
  }

  // Handle Windows share args
  // Distinguishes between share-target activation (background/silent) and
  // normal launches (SendTo, command line, etc.)
  void _handleWindowsShareArgs(List<String> argsToHandle) {
    if (argsToHandle.isEmpty) return;
    
    final bool isShareTarget = argsToHandle.contains('--share-target');
    List<SpDropFile> newFiles = [];
    for (var arg in argsToHandle) {
      // Skip control flags
      if (arg == '--tray' || arg == '--share-target') continue;
      
      // Handle text share
      if (arg.startsWith('--text-share=')) {
        final text = arg.substring('--text-share='.length);
        _clipboardService.onRemoteClipboardReceived(text);
        if (_signalingService.isConnected) {
          _signalingService.sendClipboardText(text);
        }
        continue;
      }
      
      // Handle file paths â ” from share-target (prefixed) or SendTo (raw paths)
      String filePath = arg;
      if (arg.startsWith('--share-file=')) {
        filePath = arg.substring('--share-file='.length);
      }
      if (filePath.startsWith('"') && filePath.endsWith('"')) {
        filePath = filePath.substring(1, filePath.length - 1);
      } else if (filePath.startsWith("'") && filePath.endsWith("'")) {
        filePath = filePath.substring(1, filePath.length - 1);
      }
      final file = File(filePath);
      if (file.existsSync()) {
        newFiles.add(SpDropFile(file));
      } else {
        final dir = Directory(filePath);
        if (dir.existsSync()) {
          // Handle directories if needed
        }
      }
    }
    
    if (newFiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _pendingFiles.addAll(newFiles);
        });
        
        // Auto-send if already connected
        if (_isConnected && _connectedDeviceName != null) {
          _autoSendToConnectedDevice();
        } else if (isShareTarget) {
          // Share-target activation â ” stay hidden, show toast, try auto-connect
          _notificationService.showShareQueuedNotification(newFiles.length);
          _tryConnectDefaultDeviceForShare();
        } else {
          _showSnackBar('Added ${newFiles.length} file(s) for sharing');
          if (Platform.isWindows) {
            windowManager.show();
            windowManager.focus();
          }
        }
      });
    }
  }

  Future<void> _tryConnectDefaultDeviceForShare() async {
    final defaultDevice = await _trustRepository.getDefaultDevice();
    final lastConnected = await _historyService.getLastConnected();
    final targetName = defaultDevice?.name ?? lastConnected;
    if (targetName == null) return;
    
    final device = await _trustRepository.getTrustedDevice(targetName);
    if (device != null && device.ip.isNotEmpty) {
      try {
        await _signalingService.connectToDevice(
          [device.ip], device.port, _deviceName,
        );
        // onDeviceConnected callback will auto-send pending files
      } catch (_) {
        // Will auto-send when device is discovered via mDNS
      }
    }
  }

  /// Cleans up temporary staging directory created by Windows Share Target activation.
  void _cleanupShareStagingFiles() {
    if (!Platform.isWindows) return;
    try {
      final tempBase = Platform.environment['TEMP'] ?? Platform.environment['TMP'];
      if (tempBase == null) return;
      final stagingDir = Directory('$tempBase\\SpDrop_Share');
      if (stagingDir.existsSync()) {
        stagingDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Silent fail â ” temp cleanup is best-effort
    }
  }

// _createWindowsSendToShortcut moved to WindowsPlatform

  // WindowListener — minimize to tray on close.
  // CRITICAL: Do NOT reset _isWindowClosing in finally. The old code
  // raced with the OS WM_CLOSE handler: the flag was cleared before the
  // hide animation completed, allowing a second close event to crash.
  // The flag is reset only when the window is explicitly shown again
  // (via system tray → _showWindow).
  @override
  void onWindowClose() async {
    if (_isWindowClosing || _isQuitting) return;
    _isWindowClosing = true;
    try {
      if (Platform.isWindows) {
        await windowManager.hide();
      }
    } catch (e) {
      debugPrint('onWindowClose error: $e');
      _isWindowClosing = false; // Only reset on error so retry is possible
    }
    // Intentionally NOT resetting _isWindowClosing on success.
    // It's reset in _showWindowFromTray() when user clicks "Show SpDrop".
  }

  /// Resets the close guard so subsequent X-clicks work correctly.
  void _showWindowFromTray() {
    _isWindowClosing = false;
    if (mounted) setState(() {});
  }
  // Ensure signaling service is running before handling share.
  // Without this, files shared via Android share sheet would be queued but never sent.
  void _handleSharedMedia(List<SharedMediaFile> media) {
    if (media.isEmpty) return;

    setState(() {
      for (var item in media) {
        if (item.type == SharedMediaType.text) {
          // Handle shared text as clipboard
          _clipboardService.onRemoteClipboardReceived(item.path);
          if (_signalingService.isConnected) {
            _signalingService.sendClipboardText(item.path);
          }
        } else {
          // Handle files, images, videos
          final file = File(item.path);
          if (file.existsSync()) {
            _pendingFiles.add(SpDropFile(file));
          }
        }
      }
    });

    if (_pendingFiles.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_pendingFiles.length} files ready to send'),
            backgroundColor: const Color(0xFF4F8EF7),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }

      // If connected to trusted device, auto-send
      if (_isConnected && _connectedDeviceName != null) {
        _autoSendToConnectedDevice();
      } else {
        // Trusted device quick-share on intent
        // Load trusted devices first in case they haven't loaded yet
        _loadTrustedDevices().then((_) {
          if (mounted) _showTrustedDeviceQuickShare();
        });
      }
    }
  }

  void _showTrustedDeviceQuickShare() {
    if (_trustedDevices.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Send to Trusted Device', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _trustedDevices.length,
                  itemBuilder: (ctx, idx) {
                    final d = _trustedDevices[idx];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.devices)),
                      title: Text(d.name),
                      subtitle: const Text('Tap to connect & send'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _connectAndSendToTrusted(d);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _connectAndSendToTrusted(TrustedDevice device) async {
    if (device.ip.isEmpty) {
      _showSnackBar('Device IP not known yet. Please connect manually first.', isWarning: true);
      return;
    }
    _showSnackBar('Connecting to ${device.name}...');
    try {
      int totalSize = 0;
      List<Map<String, dynamic>> manifest = [];
      for (var f in _pendingFiles) {
        int size = await f.file.length();
        totalSize += size;
        manifest.add({
          "name": f.file.path.split(Platform.pathSeparator).last,
          "size": size,
          "relative_path": f.relativePath,
        });
      }

      await _signalingService.requestConnection(
        [device.ip],
        device.port,
        _deviceName,
        jsonEncode(manifest),
        totalSize,
      );
    } catch (e) {
      _showSnackBar('Connection failed. Please ensure the target device is reachable on the network.', isError: true);
    }
  }

  Future<void> _pickAndSendFiles() async {
    // Quick send from tray/notification
    FilePickerResult? result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null && mounted) {
      setState(() {
        for (var file in result.files) {
          if (file.path != null) _pendingFiles.add(SpDropFile(File(file.path!)));
        }
      });
      if (_isConnected) {
        await _autoSendToConnectedDevice();
      } else {
        _showSnackBar('Files ready. Connect to a device to send.', isError: false);
      }
    }
  }

  Future<void> _autoSendToConnectedDevice() async {
    if (_pendingFiles.isEmpty || !_isConnected) return;
    // Use actual connected peer's IP and port from signaling
    int totalSize = 0;
    List<Map<String, dynamic>> manifest = [];
    for (var f in _pendingFiles) {
      int size = await f.file.length();
      totalSize += size;
      manifest.add({
        "name": f.file.path.split(Platform.pathSeparator).last,
        "size": size,
        "relative_path": f.relativePath,
      });
    }
    // Reuse the existing persistent connection.
    try {
      await _signalingService.requestConnection(
        [], 0, _deviceName, jsonEncode(manifest), totalSize,
      );
    } catch (e) {
      if (mounted) _showSnackBar('Auto-send failed', isError: true);
    }
  }

  Future<void> _loadTrustedDevices() async {
    final devices = await _trustRepository.getTrustedDevices();
    if (mounted) setState(() => _trustedDevices = devices);
  }

  void _setupServiceCallbacks() {
    _signalingService.onTransferAccepted = () {
      if (mounted) {
        setState(() {
          _connectionStatus = "Transfer Accepted";
          if (_pendingFiles.isNotEmpty) _isFileTransferring = true;
        });
      }
    };

    _signalingService.onFileTransferApproved = (port, peerIp) async {
      String? targetIp = peerIp.isNotEmpty ? peerIp : null;
      if (_pendingFiles.isNotEmpty && targetIp != null) {
        if (Platform.isAndroid) {
          FlutterForegroundTask.updateService(
            notificationTitle: 'SpDrop â€” Sending Files',
            notificationText: 'Transfer in progress...',
          );
        }
        int totalSize = 0;
        for (var f in _pendingFiles) {
          totalSize += await f.file.length();
        }
        try {
          await _fileService.sendFiles(
            _pendingFiles, totalSize, targetIp, port, useE2ee: true,
          );
        } catch (e) {
          if (mounted) {
            _showSnackBar('An error occurred during file transfer. Please try again.', isError: true);
            setState(() {
              _isFileTransferring = false;
              _pendingFiles.clear();
              _connectionStatus = _isConnected ? "Connected" : "Ready";
            });
          }
        }
      }
    };

    _signalingService.onConnectionDeclined = (reason) {
      if (!mounted) return;
      setState(() => _connectionStatus = "Declined");
      _showSnackBar(reason, isError: true);
      _safeDelayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _connectionStatus = _isConnected ? "Connected" : "Ready");
      });
    };

    _signalingService.onPortFallback = (port) {
      if (mounted) _showSnackBar("Port 8888 busy. Using: $port", isWarning: true);
    };

    // Auto-accept for trusted devices
    _signalingService.onConnectionRequest = (senderName, batchManifestStr, totalSize) async {
      List<dynamic> manifest = [];
      try { manifest = jsonDecode(batchManifestStr); } catch (_) {}

      // Check if sender is trusted — auto-accept
      bool isTrusted = await _trustRepository.isDeviceTrusted(senderName);
      bool accepted;

      if (isTrusted) {
        accepted = true;
        if (mounted) {
          _showSnackBar("Auto-accepted from $senderName", isSuccess: true);
        }
      } else {
        String previewText = "${manifest.length} files (${(totalSize / 1024 / 1024).toStringAsFixed(2)} MB)";
        if (manifest.isNotEmpty) {
          previewText += "\n\n• ${manifest.first['name']}";
          if (manifest.length > 1) previewText += "\n• ...and ${manifest.length - 1} more";
        }

        if (!mounted) return false;
        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false,
          builder: (context) => IncomingTransferDialog(
            senderName: senderName,
            previewText: previewText,
          ),
        );
        
        accepted = result?['accepted'] ?? false;
        bool trust = result?['trust'] ?? false;
        
        if (accepted && trust) {
          await _trustRepository.saveTrustedDevice(
            senderName,
            _signalingService.connectedPeerIp ?? '',
            _signalingService.serverPort,
            isTrusted: true,
            stableId: _signalingService.connectedPeerPublicKeyFingerprint,
          );
        }
      }

      if (accepted && manifest.isNotEmpty) {
        if (Platform.isAndroid) {
          FlutterForegroundTask.updateService(
            notificationTitle: 'SpDrop — Receiving Files',
            notificationText: 'Transfer in progress...',
          );
        }
        int port = await _fileService.startReceivingServer(
          batchManifestStr, totalSize, useE2ee: true,
        );
        _signalingService.sendTcpPort(port);
        _signalingService.lockSession();
      }

      return accepted;
    };

    _signalingService.onConnectionLocked = () {
      _signalingService.lockSession();
    };

    _signalingService.onRemoteProgressReceived = (progress, speedMBps) {
      if (Platform.isWindows && progress > 0.01 && progress < 0.99) {
        // Send a native Windows progress toast
        _notificationService.showWindowsProgressToast(
          'Sending to ${_signalingService.connectedPeerIp}', 
          '${speedMBps.toStringAsFixed(1)} MB/s', 
          progress, 
          'transfer'
        );
      }
      
      if (mounted) {
        setState(() {
          _fileProgress = progress;
          _speedMBps = speedMBps;
          _isFileTransferring = true;
        });
      }
    };

    _signalingService.onDevicesUpdated = (devices) async {
      if (!mounted) return;
      
      // Removed redundant `d.name != _deviceName` filter.
      // The service layer's _isSelfDevice() already filters by stableId, IP,
      // AND name+suffix patterns. The old name-only check here missed clones
      // like "Sp 2" or "Sp (1)" that mDNS auto-generates on collision.
      // Devices arriving here are already self-filtered.
      setState(() {
        _nearbyDevices = devices;
      });

      // Auto-connect to last trusted device or default device if not connected
      if (!_isConnected && devices.isNotEmpty) {
        final defaultDevice = await _trustRepository.getDefaultDevice();
        final lastConnected = await _historyService.getLastConnected();

        for (var device in devices) {
          bool isTrusted = await _trustRepository.isDeviceTrusted(device.name);
          bool isTargetDevice = false;
          
          if (defaultDevice != null) {
            isTargetDevice = (device.name == defaultDevice.name);
          } else if (lastConnected != null) {
            isTargetDevice = (device.name == lastConnected);
          } else {
            isTargetDevice = isTrusted; // fallback if no history
          }

          if (isTrusted && isTargetDevice && !_isConnected) {
            try {
              await _signalingService.connectToDevice(
                device.ips, device.port, _deviceName,
              );
              break;
            } catch (_) {}
          }
        }
      }
    };

    _signalingService.onClipboardReceived = (text, html, eventId, originDeviceId, timestamp, contentHash) {
      if (!_clipboardSyncEnabled) return;
      _clipboardService.onRemoteClipboardReceived(
        text, 
        html: html,
        eventId: eventId,
        originDeviceId: originDeviceId,
        timestamp: timestamp,
        contentHash: contentHash,
      );
      if (mounted) {
        _showSnackBar('📋 Clipboard synced', isSuccess: true);
      }
    };

    // Persistent connection callbacks
    _signalingService.onDeviceConnected = (deviceName, platform) async {
      if (mounted) {
        setState(() {
          _isConnected = true;
          _connectedDeviceName = deviceName;
          _connectedDevicePlatform = platform;
          _connectionStatus = "Connected to $deviceName";
        });
      }

      // Save last connected device
      await _historyService.saveLastConnected(deviceName);

      // Update trusted device IP with the real peer IP from the handshake
      final peerIp = _signalingService.connectedPeerIp;
      if (peerIp != null && peerIp.isNotEmpty) {
        // Pass stableId for deduplication on rename
        await _trustRepository.saveTrustedDevice(
          deviceName, peerIp, _signalingService.serverPort,
          platform: platform,
          stableId: _signalingService.connectedPeerStableId,
        );
      }

      // Update Android foreground notification to reflect persistent connection.
      // "Connected to {device}" with Manage/Disconnect buttons (Phone Link style)
      if (Platform.isAndroid) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'SpDrop — Connected',
          notificationText: 'Connected to $deviceName • Tap Manage to open app',
        );
        qsChannel.invokeMethod('updateTileState', {
          'isConnected': true,
          'deviceName': deviceName,
        });
      }

      // Update system tray on Windows
      if (Platform.isWindows) {
        _systemTrayService.updateStatus(isConnected: true, deviceName: deviceName);
      }

      // Auto-start clipboard sync for ALL connected devices
      _clipboardService.startSync();

      // Enable auto-reconnect for trusted devices
      bool isTrusted = await _trustRepository.isDeviceTrusted(deviceName);
      if (isTrusted) {
        _signalingService.enableAutoReconnect(true);
      }

      // Auto-enable notification forwarding to Windows
      if (Platform.isAndroid && platform == 'windows') {
        final prefs = await SharedPreferences.getInstance();
        bool hasPrompted = prefs.getBool('notif_prompt_windows') ?? false;
        if (!hasPrompted) {
          _notificationService.openNotificationSettings();
          await prefs.setBool('notif_prompt_windows', true);
        }
        
        if (mounted) {
          setState(() {
            _notificationsEnabled = true;
          });
        }
        _notificationService.startListening();
      } else if (Platform.isAndroid && _notificationsEnabled) {
        _notificationService.startListening();
      }

      _loadTrustedDevices();

      // Auto-send queued files on ALL platforms (not just Windows)
      if (_pendingFiles.isNotEmpty) {
        _safeDelayed(const Duration(milliseconds: 500), () {
          _autoSendToConnectedDevice();
        });
      }
    };

    _signalingService.onDeviceDisconnected = () {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _connectedDeviceName = null;
          _connectedDevicePlatform = null;
          _connectionStatus = "Disconnected";
        });
      }

      _clipboardService.stopSync();
      _notificationService.stopListening();

      // Retain the Android foreground service across disconnects.
      // Instead, update notification to "Reconnecting..." so the app stays alive
      // in background. Only stop when user explicitly disconnects via notification button.
      if (Platform.isAndroid && _isServiceRunning) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'SpDrop',
          notificationText: 'Disconnected • Scanning for devices...',
        );
        qsChannel.invokeMethod('updateTileState', {
          'isConnected': false,
          'deviceName': '',
        });
      }

      // Update system tray on Windows
      if (Platform.isWindows) {
        _systemTrayService.updateStatus(isConnected: false);
      }

      // Re-start service after brief delay ONLY if it's meant to be running
      _disconnectRestartTimer?.cancel();
      _disconnectRestartTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && !_isConnected && _isServiceRunning) {
          setState(() => _connectionStatus = "Ready");
          _startService();
        }
      });
    };

    // Pairing callbacks — wired to PairingService
    _signalingService.pairingService.onPairingRequest = (deviceName, code) {
      _showPairingVerificationDialog(deviceName, code);
    };

    // Handle pairing response from the responder device
    _signalingService.pairingService.onPairingResponse = (deviceName, code) {
      // This is called on the initiator when the responder sends back the code
      // The initiator should verify and confirm
    };

    _signalingService.pairingService.onPairingConfirmed = (deviceName) async {
      // Persist trusted peer with verified remote IP and port.
      final peerIp = _signalingService.connectedPeerIp;
      await _trustRepository.saveTrustedDevice(
        deviceName,
        peerIp ?? '',
        _signalingService.lastPeerPort ?? 8888,
        isTrusted: true,
        platform: _connectedDevicePlatform ?? 'unknown',
        stableId: _signalingService.connectedPeerStableId,
      );
      await _loadTrustedDevices();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        _showSnackBar('✅ Paired with $deviceName', isSuccess: true);
      }
    };

    // Notification forwarding
    _signalingService.onNotificationReceived = (data) {
      _notificationService.handleRemoteNotification(data);
    };

    // — — — File Service callbacks — —
    _fileService.onProgress = (progress, speedMBps, etaSeconds) {
      if (_fileService.isTransferring) {
        _signalingService.sendProgress(progress, speedMBps);
      }
      final now = DateTime.now();
      if (now.difference(_lastProgressUpdate).inMilliseconds < 200 && progress < 0.99) return;
      _lastProgressUpdate = now;

      if (Platform.isAndroid && progress > 0.01) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'SpDrop — ${(progress * 100).toStringAsFixed(0)}%',
          notificationText: '${speedMBps.toStringAsFixed(1)} MB/s • ETA: ${etaSeconds}s',
        );
      } else if (Platform.isWindows && progress > 0.01 && progress < 0.99) {
        _notificationService.showWindowsProgressToast(
          'Receiving Files', 
          '${speedMBps.toStringAsFixed(1)} MB/s • ETA: ${etaSeconds}s', 
          progress, 
          'transfer'
        );
      }
      
      if (mounted) {
        setState(() {
          _fileProgress = progress;
          _speedMBps = speedMBps;
          _etaSeconds = etaSeconds;
          _isFileTransferring = true;
        });
      }
    };

    _fileService.onTransferStage = (stage) {
      if (!mounted) return;
      setState(() => _transferStage = stage);
    };

    _fileService.onTransferStarted = () {
      WakelockPlus.enable();
      _signalingService.transferInProgress = true; // Pause heartbeat timeout during active transfer
      if (mounted) setState(() => _isFileTransferring = true);
    };

    // Resets state, records transfer history metadata, and updates notifications on completion.
    _fileService.onFilesSent = (filenames) {
      WakelockPlus.disable();
      // Update foreground notification status.
      if (Platform.isAndroid && _isServiceRunning) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'SpDrop Active',
          notificationText: 'Ready to receive files and sync clipboard',
        );
      }
      // Enhanced history logging with device name
      for (var name in filenames) {
        _historyRepository.logTransfer(
          name, "Sent",
          peerDevice: _connectedDeviceName,
        );
      }
      // Transfer completion notification
      if (Platform.isWindows) _notificationService.hideWindowsToast('transfer');
      _notificationService.showTransferCompleteNotification(
        filenames.length,
        _connectedDeviceName ?? 'Device',
        'Sent',
      );
      _fileService.resetAfterTransfer();
      // Post-transfer grace period — keeps connection alive for 5s
      // after transfer to prevent spurious ping timeout disconnects.
      _signalingService.transferInProgress = false;
      _signalingService.postTransferGrace = true;
      _safeDelayed(const Duration(seconds: 5), () {
        _signalingService.postTransferGrace = false;
      });
      // Clean up share target staging files
      _cleanupShareStagingFiles();
      if (!mounted) return;
      setState(() {
        _fileProgress = 1.0;
        _isTransferComplete = true;
        _currentTransferFile = '${filenames.length} files sent';
        _pendingFiles.clear();
      });
      // Auto-dismiss transfer overlay after 3 seconds
      _safeDelayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isFileTransferring = false;
            _isTransferComplete = false;
            _fileProgress = 0.0;
            _speedMBps = 0.0;
            _etaSeconds = 0;
            _connectionStatus = _isConnected ? "Connected to $_connectedDeviceName" : "Ready";
          });
          _signalingService.unlockSession(_deviceName);
        }
      });
    };

    _fileService.onClipboardFileReceived = (file) {
      if (mounted) {
        _clipboardService.onRemoteClipboardImageReceived(file);
      }
    };

    _fileService.onFilesReceived = (paths) {
      WakelockPlus.disable();
      // Update foreground notification status.
      if (Platform.isAndroid && _isServiceRunning) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'SpDrop Active',
          notificationText: 'Ready to receive files and sync clipboard',
        );
      }
      // Enhanced history logging with file path and device name
      for (var p in paths) {
        final name = p.split(Platform.pathSeparator).last;
        _historyRepository.logTransfer(
          name, "Received",
          filePath: p,
          peerDevice: _connectedDeviceName,
        );
      }
      // Transfer completion notification
      if (Platform.isWindows) _notificationService.hideWindowsToast('transfer');
      _notificationService.showTransferCompleteNotification(
        paths.length,
        _connectedDeviceName ?? 'Device',
        'Received',
        payload: paths.length == 1 ? paths.first : _fileService.saveDirectory,
      );
      _fileService.resetAfterTransfer();
      // Post-transfer grace period — keeps connection alive for 5s
      _signalingService.transferInProgress = false;
      _signalingService.postTransferGrace = true;
      _safeDelayed(const Duration(seconds: 5), () {
        _signalingService.postTransferGrace = false;
      });
      final names = paths.map((p) => p.split(Platform.pathSeparator).last).toList();
      if (!mounted) return;
      setState(() {
        _fileProgress = 1.0;
        _isTransferComplete = true;
        _currentTransferFile = '${names.length} files received';
      });
      // Auto-dismiss
      _safeDelayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isFileTransferring = false;
            _isTransferComplete = false;
            _fileProgress = 0.0;
            _speedMBps = 0.0;
            _etaSeconds = 0;
            _connectionStatus = _isConnected ? "Connected to $_connectedDeviceName" : "Ready";
          });
          _signalingService.unlockSession(_deviceName);
        }
      });
    };

    _fileService.onTransferError = (errorMsg) {
      // Update foreground notification status.
      if (Platform.isAndroid && _isServiceRunning) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'SpDrop Active',
          notificationText: 'Ready to receive files and sync clipboard',
        );
      }
      _fileService.resetAfterTransfer();
      _signalingService.transferInProgress = false; // Resume normal heartbeat checks
      if (mounted) {
        _showSnackBar(errorMsg, isError: true);
        setState(() {
          _isFileTransferring = false;
          _isTransferComplete = false;
          _fileProgress = 0.0;
          _speedMBps = 0.0;
          _etaSeconds = 0;
          _pendingFiles.clear();
          _connectionStatus = _isConnected ? "Connected to $_connectedDeviceName" : "Ready";
        });
        _signalingService.unlockSession(_deviceName);
      }
    };
  }

// _initForegroundTask moved to AndroidPlatform

  // Fixed — only request battery optimization ONCE ever
  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid && platformService is AndroidPlatform) {
      final androidPlatform = platformService as AndroidPlatform;
      await androidPlatform.requestPermissions();

      final prefs = await SharedPreferences.getInstance();

      // Fixed — only ask ONCE, never again
      final batteryPromptCount = prefs.getInt('battery_prompt_count') ?? 0;
      if (batteryPromptCount < 1) {
        await androidPlatform.requestBatteryOptimization();
        await prefs.setInt('battery_prompt_count', batteryPromptCount + 1);
      }

      // Fixed — only ask notification permission ONCE
      final notifPromptCount = prefs.getInt('notif_prompt_count') ?? 0;
      if (notifPromptCount < 1) {
        await androidPlatform.requestForegroundNotificationPermission();
        await prefs.setInt('notif_prompt_count', notifPromptCount + 1);
      }
      return true;
    }
    return true;
  }

  bool _isServiceRunning = false;
  StreamSubscription? _fgPortSubscription;

  // Background auto-reconnect to last trusted device
  Future<void> _handleBackgroundReconnect() async {
    if (_isConnected) return;
    final lastDevice = await _historyService.getLastConnected();
    if (lastDevice == null) return;
    final device = await _trustRepository.getTrustedDevice(lastDevice);
    if (device == null || device.ip.isEmpty) return;
    try {
      await _signalingService.connectToDevice(
        [device.ip], device.port, _deviceName,
      );
      if (mounted) {
        _showSnackBar('Reconnected to ${device.name}', isSuccess: true);
      }
    } catch (_) {
      // Silent fail - will retry on next interval
    }
  }

  // Bidirectional service - both send + receive simultaneously
  void _startService() async {
    if (_isServiceRunning) return;
    _isServiceRunning = true;
    
    if (Platform.isAndroid) {
      await FlutterForegroundTask.startService(
        notificationTitle: 'SpDrop Active',
        notificationText: 'Ready to receive files and sync clipboard',
        callback: startCallback,
      );
      await _fgPortSubscription?.cancel();
      _fgPortSubscription = FlutterForegroundTask.receivePort?.listen((message) {
        if (message == 'disconnect') {
          _stopService();
        } else if (message == 'check_reconnect') {
          _handleBackgroundReconnect();
        } else if (message == 'quick_send') {
          // Quick send from notification
          if (mounted) _pickAndSendFiles();
        } else if (message == 'send_clipboard_buffer') {
          _readAndSendClipboardBuffer();
        }
      });
    }
    
    await _requestPermissions();
    if (!mounted) return;
    setState(() => _connectionStatus = 'Ready');
    await _signalingService.startService(_deviceName);
    
    qsChannel.invokeMethod('updateTileState', {
      'isConnected': true,
      'deviceName': _connectedDeviceName ?? _deviceName,
    });
  }

  Future<void> _readAndSendClipboardBuffer() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final file = File('${supportDir.path}/clipboard_buffer.txt');
      if (await file.exists()) {
        final text = await file.readAsString();
        if (text.isNotEmpty && _signalingService.isConnected) {
          _signalingService.sendClipboardText(text);
          debugPrint('Sent clipboard from invisible activity buffer');
          await file.writeAsString('');
        }
      }
    } catch (e) {
      debugPrint('Error reading clipboard buffer: $e');
    }
  }

  Future<String> _getOrCreateStableDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('stable_device_id');
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString('stable_device_id', id);
    }
    return id;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep connection alive in background, only pause mDNS discovery
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _signalingService.pauseService();
    } else if (state == AppLifecycleState.resumed && mounted) {
      _signalingService.resumeService(_deviceName);
      setState(() {}); // Refresh UI with current state
    }
  }

  void _stopService() {
    if (!_isServiceRunning) return;
    _isServiceRunning = false;
    _signalingService.stop();
    if (Platform.isAndroid) {
      _fgPortSubscription?.cancel();
      FlutterForegroundTask.stopService();
    }
    setState(() {
      _connectionStatus = 'Offline';
      _isConnected = false;
    });
    qsChannel.invokeMethod('updateTileState', {
      'isConnected': false,
      'deviceName': '',
    });
  }

  // Ensures toggle actually toggles state properly.
  // Toggle OFF: Stop service completely if running or connected
  // Toggle ON: Start service first, THEN try connecting to last device
  void _handleQuickSettingsToggle() async {
    if (_isServiceRunning || _isConnected) {
      // Currently active/connected - stop service and turn off
      _stopService();
    } else {
      // Not running - start service first, then try to connect
      _startService();
      _safeDelayed(const Duration(milliseconds: 500), () async {
        final lastDevice = await _historyService.getLastConnected();
        if (lastDevice != null) {
          final device = await _trustRepository.getTrustedDevice(lastDevice);
          if (device != null && device.ip.isNotEmpty) {
            try {
              await _signalingService.connectToDevice(
                [device.ip], device.port, _deviceName,
              );
            } catch (_) {}
          }
        }
      });
    }
  }

  void _changeDeviceName() {
    final controller = TextEditingController(text: _deviceName);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Device Name", style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 18, fontWeight: FontWeight.w700,
              )),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Enter name",
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF4F8EF7)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("Cancel", style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4F8EF7)),
                    onPressed: () async {
                      final newName = controller.text.trim();
                      if (newName.isNotEmpty) {
                        await _historyService.saveName(newName);
                        if (!context.mounted) return;
                        setState(() => _deviceName = newName);
                        Navigator.pop(context);
                        // Force-restart service so mDNS
                        // re-registers with the new name. Without this,
                        // _startService() returns early because _isServiceRunning
                        // is already true.
                        _isServiceRunning = false;
                        _startService();
                      }
                    },
                    child: const Text("Save", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _initiateTransfer(List<String> ips, int port) async {
    if (_pendingFiles.isEmpty) return;

    int totalSize = 0;
    List<Map<String, dynamic>> manifest = [];
    for (var f in _pendingFiles) {
      int size = await f.file.length();
      totalSize += size;
      manifest.add({
        "name": f.file.path.split(Platform.pathSeparator).last,
        "size": size,
        "relative_path": f.relativePath,
      });
    }

    setState(() => _connectionStatus = "Connecting...");

    try {
      await _signalingService.requestConnection(
        ips, port, _deviceName, jsonEncode(manifest), totalSize,
      );
    } catch (e) {
      if (mounted) {
        _showSnackBar('Connection failed', isError: true);
        setState(() => _connectionStatus = _isConnected ? "Connected" : "Ready");
      }
    }
  }

  /// Wi-Fi Direct and Local-Only Hotspot offline mode handler.
  void _toggleOfflineMode() async {
    if (_isOfflineModeLoading) return; // Prevent double-tap
    
    if (_isOfflineMode) {
      // Stop offline mode
      setState(() => _isOfflineModeLoading = true);
      await _wifiDirectService.removeGroup();
      await _wifiDirectService.stopHotspot();
      setState(() {
        _isOfflineMode = false;
        _isOfflineModeLoading = false;
        _wifiDirectPeers.clear();
      });
      _startService();
    } else {
      // Start offline mode — create Wi-Fi Direct group + LocalOnlyHotspot
      setState(() {
        _isOfflineMode = true;
        _isOfflineModeLoading = true;
        _connectionStatus = "Starting Offline Mode...";
      });

      if (Platform.isAndroid) {
        try {
          // Try Wi-Fi Direct first
          final result = await _wifiDirectService.createGroup();
          if (result != null) {
            setState(() {
              _connectionStatus = "Offline Mode • Wi-Fi Direct";
              _isOfflineModeLoading = false;
            });

            // Also start mDNS on the P2P interface
            await _signalingService.stop();
            await _signalingService.startService(_deviceName);

            // Discover peers
            _wifiDirectService.onPeersFound = (peers) {
              if (mounted) setState(() => _wifiDirectPeers = peers);
            };
            _wifiDirectService.onConnected = (isGO, ip) {
              if (mounted) {
                setState(() => _connectionStatus = "Offline • Connected ($ip)");
                _startService();
              }
            };
            await _wifiDirectService.discoverPeers();
          } else {
            // Fallback to LocalOnlyHotspot (works with Windows)
            final hotspot = await _wifiDirectService.startHotspot();
            if (hotspot != null) {
              setState(() {
                _connectionStatus = "Offline Mode • Hotspot Active";
                _isOfflineModeLoading = false;
              });
              await _signalingService.stop();
              await _signalingService.startService(_deviceName);
              _showHotspotInfoDialog(hotspot['ssid'] ?? '', hotspot['password'] ?? '');
            } else {
              setState(() {
                _isOfflineMode = false;
                _isOfflineModeLoading = false;
                _connectionStatus = "Offline Mode Failed";
              });
              _showSnackBar("Could not start offline mode", isError: true);
            }
          }
        } catch (e) {
          // Catch any errors including timeout
          debugPrint("Offline mode error: $e");
          setState(() {
            _isOfflineMode = false;
            _isOfflineModeLoading = false;
            _connectionStatus = "Offline Mode Failed";
          });
          _showSnackBar("Could not start offline mode. Please check network permissions.", isError: true);
        }
      } else {
        _showSnackBar("Offline mode is Android-only", isWarning: true);
        setState(() {
          _isOfflineMode = false;
          _isOfflineModeLoading = false;
        });
      }
    }
  }

  void _showHotspotInfoDialog(String ssid, String password) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(24),
          borderColor: const Color(0xFFFFB347).withValues(alpha: 0.3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_tethering, color: Color(0xFFFFB347), size: 40),
              const SizedBox(height: 16),
              Text("Offline Hotspot", style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 20, fontWeight: FontWeight.w700,
              )),
              const SizedBox(height: 16),
              _infoRow("Network", ssid),
              const SizedBox(height: 8),
              _infoRow("Password", password),
              const SizedBox(height: 16),
              Text(
                "Connect your Windows PC to this network, then open SpDrop on both devices.",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFB347)),
                onPressed: () => Navigator.pop(context),
                child: const Text("Got it", style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
          SelectableText(value, style: const TextStyle(
            color: Color(0xFFFFB347), fontWeight: FontWeight.w600, fontSize: 14,
          )),
        ],
      ),
    );
  }

  // OTP Pairing
  void _startPairing(DiscoveredDevice device) async {
    // Connect to device first
    try {
      await _signalingService.connectToDevice(device.ips, device.port, _deviceName);
      await _trustRepository.saveTrustedDevice(
              device.name,
              device.ips.first,
              device.port,
              platform: device.platform,
              stableId: _signalingService.connectedPeerPublicKeyFingerprint ?? device.stableId,
            );
    } catch (e) {
      _showSnackBar("Failed to connect for pairing", isError: true);
      return;
    }

    // Generate and show pairing code
    final code = _historyService.generatePairingCode();

    _signalingService.pairingService.sendPairingRequest(code);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PairingDialog(
        pairingCode: code,
        deviceName: device.name,
        onCancel: () {
          Navigator.pop(context);
        },
      ),
    );
  }

  bool _isPairingDialogShowing = false;

  void _showPairingVerificationDialog(String deviceName, String expectedCode) {
    if (_isPairingDialogShowing) return;
    _isPairingDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PairingDialog(
        deviceName: deviceName,
        onCodeEntered: (enteredCode) async {
          if (enteredCode == expectedCode) {
            // Pairing successful â ” let onPairingConfirmed callback handle the save on initiator side
            _signalingService.pairingService.confirmPairing();
            
            // Save trusted device on responder side
            final peerIp = _signalingService.connectedPeerIp;
            await _trustRepository.saveTrustedDevice(
              deviceName,
              peerIp ?? '',
              _signalingService.lastPeerPort ?? 8888,
              isTrusted: true,
              platform: _connectedDevicePlatform ?? 'unknown',
            );
            await _loadTrustedDevices();

            if (!context.mounted) return;
            Navigator.pop(context);
            if (mounted) _showSnackBar('âœ… Paired with $deviceName', isSuccess: true);
          } else {
            Navigator.pop(context);
            if (mounted) _showSnackBar('Wrong code. Pairing failed.', isError: true);
          }
        },
        onCancel: () => Navigator.pop(context),
      ),
    ).then((_) {
      _isPairingDialogShowing = false;
    });
  }

  void _showManualIpDialog() {
    final ipController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Connect via IP", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: ipController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g. 192.168.1.5 or 192.168.1.5:9000',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("Cancel", style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final input = ipController.text.trim();
                      if (input.isNotEmpty) {
                        Navigator.pop(context);
                        // Parse IP:PORT syntax.
                        // Default to 8888 if no port specified.
                        String ip = input;
                        int port = 8888;
                        if (input.contains(':')) {
                          final parts = input.split(':');
                          ip = parts[0];
                          final parsed = int.tryParse(parts[1]);
                          if (parsed != null && parsed > 0 && parsed <= 65535) {
                            port = parsed;
                          }
                        }
                        _signalingService.connectToDevice([ip], port, _deviceName).catchError((e) {
                          _showSnackBar("Failed to connect to $ip:$port", isError: true);
                        });
                      }
                    },
                    child: const Text("Connect"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Checks whether Windows firewall rule already exists before requesting elevation.
  /// UAC elevation prompt. Previously this ran 'RunAs' on every launch,
  /// showing a UAC popup even when the rule was already in place.
  void _autoFixFirewall() async {
    if (Platform.isWindows && platformService is WindowsPlatform) {
      (platformService as WindowsPlatform).fixFirewall();
    }
  }

  void _showSnackBar(String message, {bool isError = false, bool isWarning = false, bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor: isError ? Colors.red.shade700 : isWarning ? Colors.orange.shade700 : isSuccess ? const Color(0xFF3DD68C) : const Color(0xFF4F8EF7),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // Each cleanup wrapped in try-catch to prevent cascade failures
  // that caused the lag/crash on Windows close.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try { _fgPortSubscription?.cancel(); } catch (_) {}
    try { qsChannel.setMethodCallHandler(null); } catch (_) {}
    if (Platform.isWindows) {
      try { windowManager.removeListener(this); } catch (_) {}
      try { _systemTrayService.dispose(); } catch (_) {}
    }
    try { _singleInstanceSub?.cancel(); } catch (_) {}
    try { _disconnectRestartTimer?.cancel(); } catch (_) {}
    for (var t in _delayedTimers) {
      try { t.cancel(); } catch (_) {}
    }
    _delayedTimers.clear();
    try { _mediaStreamSub?.cancel(); } catch (_) {}
    try { _stopService(); } catch (_) {}
    try { _clipboardService.stopSync(); } catch (_) {}
    try { _notificationService.stopListening(); } catch (_) {}
    try { _wifiDirectService.cleanup(); } catch (_) {}
    try { _signalingService.stop(); } catch (_) {}
    if (Platform.isAndroid) {
      try { FlutterForegroundTask.stopService(); } catch (_) {}
    }
    super.dispose();
  }

  // UI BUILD â ” Premium Dark Glassmorphism

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: (detail) {
        setState(() {
          for (var file in detail.files) {
            _pendingFiles.add(SpDropFile(File(file.path)));
          }
        });
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        endDrawer: SettingsDrawer(
          deviceName: _deviceName,
          connectedDeviceName: _signalingService.connectedDeviceName,
          isConnected: _isConnected,
          isOfflineMode: _isOfflineMode,
          isOfflineModeLoading: _isOfflineModeLoading,
          notificationsEnabled: _notificationsEnabled,
          clipboardSyncEnabled: _clipboardSyncEnabled,
          trustedDevices: _trustedDevices,
          onToggleOfflineMode: _toggleOfflineMode,
          onNotificationsChanged: (val) {
            setState(() => _notificationsEnabled = val);
            if (val) {
              _notificationService.startListening();
            } else {
              _notificationService.stopListening();
            }
          },
          onOpenNotificationSettings: _notificationService.openNotificationSettings,
          onClipboardSyncChanged: (val) {
            setState(() => _clipboardSyncEnabled = val);
            if (val) {
              _clipboardService.startSync();
            } else {
              _clipboardService.stopSync();
            }
          },
          onDisconnectDevice: (device) {
            _signalingService.disconnect();
          },
          onConnectDevice: (device) {
            if (device.ip.isNotEmpty) {
              _signalingService.connectToDevice([device.ip], device.port, _deviceName);
            } else {
              _showSnackBar("No IP address known for this device.", isError: true);
            }
          },
          onSetDefaultDevice: (name) async {
            await _trustRepository.setDefaultDevice(name);
            _loadTrustedDevices();
          },
          onRemoveTrustedDevice: (name) async {
            await _trustRepository.removeTrustedDevice(name);
            _loadTrustedDevices();
          },
          onDeleteHistoryRecord: (filename, timestamp) async {
            await _historyRepository.deleteRecord(filename, timestamp);
          },
          onClearHistory: () async {
            await _historyRepository.clearAllHistory();
            setState(() {});
          },
          getHistory: _historyRepository.getHistory,
          onThemeChanged: (theme) {
            themeService.setTheme(theme);
            setState(() {});
          },
        ),
        body: Stack(
          children: [
            // Theme-aware background gradient
            Builder(
              builder: (context) {
                final td = SpDropThemeProvider.of(context);
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [td.scaffoldBg, td.surfaceBg, td.scaffoldBg.withValues(alpha: 0.9)],
                    ),
                  ),
                );
              },
            ),

            // Main content
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          _buildHeroSection(),
                          const SizedBox(height: 20),
                          _buildActionCards(),
                          const SizedBox(height: 20),
                          _buildFilePickerSection(),
                          const SizedBox(height: 16),
                          _buildDevicesSection(),
                          const SizedBox(height: 16),
                          _buildManualConnectionSection(),
                          const SizedBox(height: 16),
                          if (Platform.isWindows) _buildFirewallCard(),
                          _buildFooter(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Transfer progress overlay
            if (_isFileTransferring)
              TransferOverlay(
                progress: _fileProgress,
                speedMBps: _speedMBps,
                etaSeconds: _etaSeconds,
                currentFile: _currentTransferFile.isNotEmpty
                    ? _currentTransferFile
                    : (_transferStage.isNotEmpty ? _transferStage : 'Preparing...'),
                statusLabel: _transferStage.isNotEmpty ? _transferStage : 'Transferring',
                isCompleted: _isTransferComplete,
                onCancel: () {
                  _fileService.cancelTransfer();
                  WakelockPlus.disable();
                  // Update foreground notification status.
                  setState(() {
                    _isFileTransferring = false;
                    _isTransferComplete = false;
                    _fileProgress = 0.0;
                    _speedMBps = 0.0;
                    _pendingFiles.clear();
                    _connectionStatus = _isConnected ? "Connected" : "Ready";
                  });
                  _signalingService.unlockSession(_deviceName);
                },
                onDone: () {
                  setState(() {
                    _isFileTransferring = false;
                    _isTransferComplete = false;
                    _fileProgress = 0.0;
                    _speedMBps = 0.0;
                    _etaSeconds = 0;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  // â” â” Top Bar â” â”
  Widget _buildTopBar() {
    final td = SpDropThemeProvider.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // App name
          Text(
            'SpDrop',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              letterSpacing: 0.5,
              color: td.textPrimary,
            ),
          ),
          const Spacer(),
          // Connection status pill
          if (_isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: td.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: td.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const StatusDot(size: 6, pulse: true),
                  const SizedBox(width: 6),
                  Text(
                    _connectedDeviceName != null 
                        ? '$_connectedDeviceName (${_isOfflineMode ? "Direct" : "LAN"})' 
                        : 'Connected',
                    style: TextStyle(
                      color: td.success.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.1),
          const SizedBox(width: 8),
          // Device name pill
          GestureDetector(
            onTap: _changeDeviceName,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: td.textPrimary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: td.textPrimary.withValues(alpha: 0.08)),
              ),
              child: Text(
                _deviceName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: td.textPrimary.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Drawer
          Builder(
            builder: (ctx) => IconButton(
              icon: Icon(Icons.menu_rounded, color: td.textPrimary.withValues(alpha: 0.5), size: 22),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
    );
  }

  // â” â” Hero Section â” â”
  Widget _buildHeroSection() {
    final td = SpDropThemeProvider.of(context);
    if (_isConnected) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            PulseIndicator(
              size: 130,
              color: td.success,
              isActive: true,
              child: Icon(
                _connectedDevicePlatform == 'android' ? Icons.phone_android
                  : _connectedDevicePlatform == 'windows' ? Icons.laptop_windows
                  : Icons.devices,
                color: td.success,
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _connectedDeviceName ?? 'Connected',
              style: TextStyle(
                color: td.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Clipboard toggle button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_clipboardService.isSyncing) {
                        _clipboardService.stopSync();
                      } else {
                        _clipboardService.startSync();
                      }
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _clipboardService.isSyncing ? Icons.content_paste : Icons.content_paste_off,
                        size: 12,
                        color: _clipboardService.isSyncing
                          ? td.success.withValues(alpha: 0.7)
                          : td.textSecondary.withValues(alpha: 0.3),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _clipboardService.isSyncing ? 'Clipboard ON' : 'Clipboard OFF',
                        style: TextStyle(
                          color: _clipboardService.isSyncing
                            ? td.success.withValues(alpha: 0.7)
                            : td.textSecondary.withValues(alpha: 0.3),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                GestureDetector(
                  onTap: () => _signalingService.disconnect(),
                  child: Text(
                    'Disconnect',
                    style: TextStyle(color: td.error.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          RadarScan(
            size: 150,
            color: td.primary,
            isScanning: !_isOfflineMode,
          ),
          const SizedBox(height: 12),
          Text(
            _connectionStatus,
            style: TextStyle(
              color: td.textSecondary.withValues(alpha: 0.6),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  // â” â” Action Cards â” â”
  Widget _buildActionCards() {
    final td = SpDropThemeProvider.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: GlassActionCard(
              icon: Icons.send_rounded,
              label: 'Send Files',
              subtitle: '${_pendingFiles.length} ready',
              iconColor: td.primary,
              onTap: () async {
                FilePickerResult? result = await FilePicker.platform.pickFiles(allowMultiple: true);
                if (result != null) {
                  setState(() {
                    for (var file in result.files) {
                      if (file.path != null) _pendingFiles.add(SpDropFile(File(file.path!)));
                    }
                  });
                }
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GlassActionCard(
              icon: Icons.wifi_tethering,
              label: 'Offline',
              subtitle: _isOfflineMode ? 'Active' : 'Wi-Fi Direct',
              iconColor: td.warning,
              isActive: _isOfflineMode,
              onTap: _toggleOfflineMode,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GlassActionCard(
              icon: Icons.notifications_outlined,
              label: 'Notifications',
              subtitle: _notificationsEnabled ? 'On' : 'Off',
              iconColor: td.error,
              isActive: _notificationsEnabled,
              onTap: () {
                setState(() => _notificationsEnabled = !_notificationsEnabled);
                if (_notificationsEnabled && Platform.isAndroid) {
                  _notificationService.startListening();
                } else {
                  _notificationService.stopListening();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // â” â” File Picker Section â” â”
  Widget _buildFilePickerSection() {
    if (_pendingFiles.isEmpty) return const SizedBox.shrink();

    final td = SpDropThemeProvider.of(context);
    return GlassCard(
      borderColor: td.primary.withValues(alpha: 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_pendingFiles.length} FILES READY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: td.primary.withValues(alpha: 0.8),
                  letterSpacing: 1.5,
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _pendingFiles.clear()),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Clear', style: TextStyle(color: td.error.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _pendingFiles.take(5).map((f) {
              final name = f.file.path.split(Platform.pathSeparator).last;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insert_drive_file, size: 14, color: td.textSecondary.withValues(alpha: 0.4)),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Text(
                        name,
                        style: TextStyle(color: td.textPrimary.withValues(alpha: 0.7), fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          if (_pendingFiles.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '+${_pendingFiles.length - 5} more',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.05);
  }

  // â” â” Devices Section â” â”
  Widget _buildDevicesSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NEARBY DEVICES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.35),
                  letterSpacing: 1.5,
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: _showManualIpDialog,
                    child: Icon(Icons.add_link_rounded, color: Colors.white.withValues(alpha: 0.35), size: 18),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () async {
                      setState(() => _nearbyDevices.clear());
                      await _signalingService.stopScanning();
                      _signalingService.startScanning();
                    },
                    child: Icon(Icons.refresh_rounded, color: Colors.white.withValues(alpha: 0.35), size: 18),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Builder(
            builder: (context) {
              final List<Map<String, dynamic>> combined = [];
              for (final d in _nearbyDevices) {
                combined.add({
                  'name': d.name,
                  'platform': d.platform,
                  'ips': d.ips,
                  'port': d.port,
                  'isOffline': false,
                  'device': d,
                });
              }
              for (final td in _trustedDevices) {
                if (td.isTrusted && !_nearbyDevices.any((d) => d.name == td.name)) {
                  combined.add({
                    'name': td.name,
                    'platform': td.platform,
                    'ips': [td.ip],
                    'port': td.port,
                    'isOffline': true,
                    'device': null,
                  });
                }
              }

              if (combined.isEmpty) {
                return GlassCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      RadarScan(size: 80, color: Colors.white.withValues(alpha: 0.2), isScanning: true),
                      const SizedBox(height: 8),
                      Text(
                        'Scanning for devices...',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Make sure both devices are on the same network (Wi-Fi or Hotspot)',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 11),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: combined.asMap().entries.map((entry) {
                  final i = entry.key;
                  final deviceMap = entry.value;
                  final isTrusted = _trustedDevices.any((d) => d.name == deviceMap['name'] && d.isTrusted);
                  final isThisConnected = _isConnected && _connectedDeviceName == deviceMap['name'];
                  final isOffline = deviceMap['isOffline'] as bool;
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 0),
                    child: DeviceCard(
                      name: deviceMap['name'],
                      platform: deviceMap['platform'],
                      isTrusted: isTrusted,
                      isConnected: isThisConnected,
                      isOffline: isOffline,
                      // Open file picker if no files queued
                      onSend: isOffline ? null : () async {
                        if (_pendingFiles.isEmpty) {
                          await _pickAndSendFiles();
                          if (_pendingFiles.isEmpty) return; // User cancelled
                        }
                        _initiateTransfer(deviceMap['ips'], deviceMap['port']);
                      },
                      onPair: isOffline || deviceMap['device'] == null ? null : () => _startPairing(deviceMap['device']),
                      onConnect: isOffline ? null : () async {
                        try {
                          await _signalingService.connectToDevice(
                            deviceMap['ips'], deviceMap['port'], _deviceName,
                          );
                        } catch (e) {
                          _showSnackBar("Failed to connect", isError: true);
                        }
                      },
                      onDisconnect: () => _signalingService.disconnect(),
                    ).animate(delay: Duration(milliseconds: 80 * i))
                        .fadeIn(duration: 300.ms)
                        .slideX(begin: 0.05),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // Manual Connection Section
  Widget _buildManualConnectionSection() {
    return FutureBuilder<List<String>>(
      future: _signalingService.getAllLocalIps(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
        final ips = snapshot.data!;
        final port = _signalingService.serverPort;
        if (port == 0) return const SizedBox.shrink();

        final activeIp = ips.firstWhere((ip) => ip != "127.0.0.1", orElse: () => ips.first);
        final otherIps = ips.where((ip) => ip != activeIp && ip != "127.0.0.1").toList();

        final td = SpDropThemeProvider.of(context);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CONNECTION ADDRESS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.35),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              GlassCard(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('For Manual Connection', style: TextStyle(color: td.textSecondary, fontSize: 12)),
                                const SizedBox(height: 4),
                                SelectableText(
                                  '$activeIp:$port',
                                  style: TextStyle(color: td.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.copy, size: 18, color: td.primary),
                                tooltip: 'Copy IP',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: activeIp));
                                  _showSnackBar('IP Address copied to clipboard');
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.copy_all, size: 18, color: td.primary),
                                tooltip: 'Copy IP:Port',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: '$activeIp:$port'));
                                  _showSnackBar('IP:Port copied to clipboard');
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (otherIps.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Additional Addresses:', style: TextStyle(color: td.textSecondary, fontSize: 12)),
                        for (var ip in otherIps)
                          SelectableText(
                            '$ip:$port',
                            style: TextStyle(color: td.textSecondary.withValues(alpha: 0.8), fontSize: 13, fontFamily: 'monospace'),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Firewall Card (Windows only)
  Widget _buildFirewallCard() {
    return GlassCard(
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Colors.orangeAccent, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text("Firewall blocking?",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
          ),
          GestureDetector(
            onTap: () {
              _autoFixFirewall();
              _showSnackBar('Firewall rule requested', isWarning: true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text("Fix", style: TextStyle(
                color: Colors.orangeAccent, fontWeight: FontWeight.w600, fontSize: 12,
              )),
            ),
          ),
        ],
      ),
    );
  }

  // â” â” Footer â” â”
  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        children: [
          Text(
            "SpDrop",
            style: TextStyle(
              color: const Color(0xFF4F8EF7).withValues(alpha: 0.6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            "Developed By Sourav\nRegistration Id PIET25EC024",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: 10,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

}
