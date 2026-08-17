import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

/// Manages Windows system tray integration, window minimize-to-tray lifecycle, and context menu actions.
class SystemTrayService {
  SystemTray? _systemTray;
  bool _isInitialized = false;
  bool _isClosing = false;

  VoidCallback? onShowWindow;
  VoidCallback? onQuickSend;
  VoidCallback? onConnectLastDevice;
  VoidCallback? onDisconnect;
  VoidCallback? onQuit;
  final bool _isConnected = false;
  String? _connectedDeviceName;

  bool get isInitialized => _isInitialized;

  /// Initializes the system tray icon and attaches context menu handlers.
  Future<void> initialize() async {
    if (!Platform.isWindows) return;

    try {
      await windowManager.ensureInitialized();

      _systemTray = SystemTray();

      String iconPath = _resolveIconPath();
      debugPrint('System tray icon path: [PATH_REDACTED]');

      await _systemTray!.initSystemTray(
        title: 'SpDrop',
        iconPath: iconPath,
        toolTip: 'SpDrop — Ready',
      );

      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(
          label: 'Show SpDrop',
          onClicked: (_) => _showWindow(),
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: 'Quick Send File',
          onClicked: (_) => onQuickSend?.call(),
        ),
        MenuItemLabel(
          label: 'Connect to Last Device',
          onClicked: (_) => onConnectLastDevice?.call(),
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: 'Disconnect',
          onClicked: (_) => onDisconnect?.call(),
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: 'Quit SpDrop',
          onClicked: (_) => _quit(),
        ),
      ]);

      await _systemTray!.setContextMenu(menu);

      // Show window on left click; display context menu on right click.
      _systemTray!.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) {
          _showWindow();
        } else if (eventName == kSystemTrayEventRightClick) {
          _systemTray!.popUpContextMenu();
        }
      });

      _isInitialized = true;
    } catch (e) {
      debugPrint('System tray init error: $e');
      _isInitialized = false;
    } finally {
      // Prevent default window destruction to allow minimizing to tray.
      await windowManager.setPreventClose(true);
    }
  }

  /// Updates tray tooltip reflecting current peer connection or file transfer status.
  Future<void> updateStatus({
    bool isConnected = false,
    String? deviceName,
    bool isTransferring = false,
  }) async {
    if (!_isInitialized || _systemTray == null) return;

    String tooltip;
    if (isTransferring) {
      tooltip = 'SpDrop — Transferring files...';
    } else if (isConnected && deviceName != null) {
      tooltip = 'SpDrop — Connected to $deviceName';
    } else if (isConnected) {
      tooltip = 'SpDrop — Connected';
    } else {
      tooltip = 'SpDrop — Ready';
    }

    try {
      await _systemTray!.setToolTip(tooltip);
    } catch (_) {}
  }

  void _showWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
      onShowWindow?.call();
    } catch (e) {
      debugPrint('System tray show window error: $e');
    }
  }

  /// Sequential teardown stopping services, disposing tray icon, and destroying window.
  void _quit() async {
    if (_isClosing) return;
    _isClosing = true;
    try {
      onQuit?.call();
      await _destroy();
      await Future.delayed(const Duration(milliseconds: 50));
    } catch (e) {
      debugPrint('System tray quit error: $e');
    } finally {
      try {
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
      } catch (_) {
        // Fallback to process exit if window destruction throws.
      }
      exit(0);
    }
  }

  Future<void> _destroy() async {
    if (_systemTray != null) {
      try {
        await _systemTray!.destroy();
      } catch (_) {}
      _systemTray = null;
    }
  }

  /// Intercepts window close requests to hide window to system tray.
  Future<bool> handleWindowClose() async {
    if (_isClosing) return false;
    if (!Platform.isWindows) return true;
    try {
      _isClosing = true;
      await windowManager.hide();
    } catch (e) {
      debugPrint('System tray handleWindowClose error: $e');
    } finally {
      _isClosing = false;
    }
    return false;
  }

  /// Resolve the best available icon path for the system tray.
  /// Checks multiple candidate locations since the asset layout differs
  /// between debug and release builds.
  String _resolveIconPath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    // Candidate paths in priority order:
    final candidates = [
      // Release build: assets bundled inside data/flutter_assets/
      '$exeDir/data/flutter_assets/assets/icon.ico',
      '$exeDir/data/flutter_assets/assets/icon.png',
      // Debug build: assets relative to project root (rare)
      'assets/icon.ico',
      'assets/icon.png',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        debugPrint('System tray: found icon at [PATH_REDACTED]');
        return path;
      }
    }

    // Last resort: use the default Flutter app icon
    debugPrint('System tray: no icon found, using default');
    return Platform.isWindows ? 'app_icon.ico' : 'assets/icon.png';
  }

  /// Safe dispose — guards against double-dispose and async errors.
  Future<void> dispose() async {
    try {
      await _destroy();
    } catch (e) {
      debugPrint('System tray dispose error: $e');
    }
  }
}
