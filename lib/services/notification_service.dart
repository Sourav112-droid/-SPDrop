import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart';
import 'local_signaling_service.dart';

/// Forwards system notifications between connected platforms and handles desktop toast alerts.
class NotificationService {
  static const _eventChannel = EventChannel('com.example.p2p_sync_app/notifications');
  static const _methodChannel = MethodChannel('com.example.p2p_sync_app/notification_settings');

  LocalSignalingService? _signalingService;
  bool _isListening = false;
  bool _isEnabled = false;

  final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isLocalNotificationsInitialized = false;

  NotificationService() {
    _initLocalNotifications();
  }

  Future<void> _initLocalNotifications() async {
    if (!Platform.isAndroid) return;
    try {
      const AndroidInitializationSettings initSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      final InitializationSettings initSettings =
          InitializationSettings(android: initSettingsAndroid);

      await _localNotificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) async {
          if (response.payload != null && response.payload!.isNotEmpty) {
            await OpenFilex.open(response.payload!);
          }
        },
      );
      _isLocalNotificationsInitialized = true;
    } catch (e) {
      debugPrint("Failed to initialize local notifications: $e");
    }
  }

  // Notification history (in-memory, last 50)
  final List<Map<String, dynamic>> _notificationHistory = [];
  List<Map<String, dynamic>> get notificationHistory =>
      List.unmodifiable(_notificationHistory);

  // Callback for UI updates
  Function(Map<String, dynamic>)? onLocalNotification;
  Function(Map<String, dynamic>)? onRemoteNotification;

  // Package filter (null = forward all)
  Set<String>? _allowedPackages;

  void setSignalingService(LocalSignalingService service) {
    _signalingService = service;
  }

  bool get isEnabled => _isEnabled;

  /// Start listening for local notifications (Android only)
  void startListening() {
    if (!Platform.isAndroid || _isListening) return;
    _isListening = true;
    _isEnabled = true;

    _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final notification = Map<String, dynamic>.from(event);
          final packageName = notification['package'] as String? ?? '';

          // Apply package filter
          if (_allowedPackages != null &&
              !_allowedPackages!.contains(packageName)) {
            return;
          }

          // Skip our own notifications
          if (packageName == 'com.example.p2p_sync_app') return;

          // Add to history
          notification['timestamp'] = DateTime.now().toIso8601String();
          _notificationHistory.insert(0, notification);
          if (_notificationHistory.length > 50) {
            _notificationHistory.removeLast();
          }

          // Notify local UI
          onLocalNotification?.call(notification);

          // Forward to connected device
          if (_signalingService != null && _signalingService!.isConnected) {
            _signalingService!.sendNotification(
              notification['package'] ?? '',
              notification['title'] ?? '',
              notification['text'] ?? '',
            );
          }
        }
      },
      onError: (e) {
        debugPrint("Notification stream error: $e");
      },
    );
  }

  /// Handle a notification received from a remote device
  void handleRemoteNotification(Map<String, dynamic> data) {
    final notification = {
      'package': data['package'] ?? '',
      'title': data['title'] ?? '',
      'text': data['text'] ?? '',
      'timestamp': DateTime.now().toIso8601String(),
      'isRemote': true,
    };

    _notificationHistory.insert(0, notification);
    if (_notificationHistory.length > 50) {
      _notificationHistory.removeLast();
    }

    onRemoteNotification?.call(notification);

    // On Windows, show a desktop notification
    if (Platform.isWindows) {
      _showWindowsNotification(
        notification['title'] as String,
        notification['text'] as String,
      );
    }
  }

  static const MethodChannel _toastChannel = MethodChannel('com.example.p2psyncapp/toast');

  void showWindowsProgressToast(String title, String status, double progress, String tag) {
    if (!Platform.isWindows) return;
    try {
      _toastChannel.invokeMethod('showProgressToast', {
        'title': title,
        'status': status,
        'progress': progress,
        'tag': tag,
      });
    } catch (e) {
      debugPrint("Windows toast error: $e");
    }
  }

  void hideWindowsToast(String tag) {
    if (!Platform.isWindows) return;
    try {
      _toastChannel.invokeMethod('hideToast', {'tag': tag});
    } catch (e) {
      debugPrint("Windows hide toast error: $e");
    }
  }

  /// Show a Windows desktop notification (toast)
  void _showWindowsNotification(String title, String text) {
    // We can also route this to the new C++ channel if we want, or keep PowerShell.
    // To minimize risk, we keep PowerShell for simple text toasts for now.
    if (!Platform.isWindows) return;
    
    String escapeXml(String input) {
      return input
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&apos;');
    }
    
    final safeTitle = escapeXml(title);
    final safeText = escapeXml(text);
    
    try {
      Process.run('powershell', [
        '-Command',
        '''
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
        \$xml = [Windows.Data.Xml.Dom.XmlDocument]::new()
        \$template = "<toast><visual><binding template='ToastText02'><text id='1'>$safeTitle</text><text id='2'>$safeText</text></binding></visual></toast>"
        \$xml.LoadXml(\$template)
        \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("SpDrop").Show(\$toast)
        '''
      ]);
    } catch (e) {
      debugPrint("Windows notification error: $e");
    }
  }

  /// Open Android notification listener settings
  Future<void> openNotificationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _methodChannel.invokeMethod('openNotificationSettings');
    } catch (e) {
      debugPrint("Open notification settings error: $e");
    }
  }

  /// Set package filter (null = allow all)
  void setAllowedPackages(Set<String>? packages) {
    _allowedPackages = packages;
  }

  void stopListening() {
    _isListening = false;
    _isEnabled = false;
  }

  void clearHistory() {
    _notificationHistory.clear();
  }

  // ---------------------------------------------------------------------------
  // Transfer completion notifications
  // ---------------------------------------------------------------------------

  /// Displays system notification when a file transfer operation completes.
  void showTransferCompleteNotification(int fileCount, String deviceName, String direction, {String? payload}) {
    final title = 'Transfer Complete';
    final text = direction == 'Sent'
        ? '$fileCount file${fileCount > 1 ? 's' : ''} sent to $deviceName'
        : '$fileCount file${fileCount > 1 ? 's' : ''} received from $deviceName';

    if (Platform.isWindows) {
      _showWindowsNotification(title, text);
    }
    
    if (Platform.isAndroid && _isLocalNotificationsInitialized) {
      _localNotificationsPlugin.show(
        0,
        title,
        text,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'transfer_complete',
            'Transfer Complete',
            channelDescription: 'Notifications for completed file transfers',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: payload,
      );
    }
  }

  /// Show notification for incoming transfer request
  void showTransferRequestNotification(String senderName, int fileCount) {
    if (Platform.isWindows) {
      _showWindowsNotification(
        'Incoming Transfer',
        '$senderName wants to send $fileCount file${fileCount > 1 ? 's' : ''}',
      );
    }
  }

  /// Show notification when files are queued from Windows Share Target
  void showShareQueuedNotification(int fileCount) {
    if (Platform.isWindows) {
      _showWindowsNotification(
        'Files Queued',
        '$fileCount file${fileCount > 1 ? 's' : ''} ready to send. Will transfer when device connects.',
      );
    }
  }
}
