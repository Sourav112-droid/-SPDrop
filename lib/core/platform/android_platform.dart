import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:workmanager/workmanager.dart';
import 'package:android_intent_plus/android_intent.dart' as android_intent;

import 'platform_service.dart';

// WorkManager callback for periodic background reconnect
@pragma('vm:entry-point')
void workManagerCallback() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    // This runs in a background isolate — just notify the main app to reconnect
    return true;
  });
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(SpDropTaskHandler());
}

class SpDropTaskHandler extends TaskHandler {
  SendPort? _sendPort;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    _sendPort = sendPort;
  }
  
  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'send_clip') {
      try {
        final intent = android_intent.AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.example.p2p_sync_app',
          componentName: 'com.example.p2p_sync_app.InvisibleClipboardActivity',
          flags: <int>[268435456, 536870912], // FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_SINGLE_TOP
        );
        intent.launch();
        
        // Wait 500ms for Activity to read clipboard and write to file
        Future.delayed(const Duration(milliseconds: 500), () {
          _sendPort?.send('send_clipboard_buffer');
        });
      } catch (e) {
        debugPrint('Error launching intent: $e');
      }
    } else if (id == 'disconnect') {
      _sendPort?.send('disconnect');
    } else if (id == 'quick_send') {
      _sendPort?.send('quick_send');
    }
  }

  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    _sendPort = sendPort;
    // Periodic background check — triggers auto-reconnect to last trusted device
    _sendPort?.send('check_reconnect');
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    _sendPort = sendPort;
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {
  }
}

class AndroidPlatform implements PlatformService {
  @override
  Future<void> initialize() async {
    // Initialize WorkManager for periodic background reconnect
    try {
      await Workmanager().initialize(
        workManagerCallback,
      );
    } catch (e) {
      debugPrint("Workmanager init error: \$e");
    }
  }

  @override
  Future<bool> requestPermissions() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    List<Permission> permissions = [
      Permission.storage,
      Permission.manageExternalStorage,
    ];

    if (sdkInt >= 33) {
      permissions.addAll([Permission.nearbyWifiDevices, Permission.location, Permission.notification]);
    } else {
      permissions.add(Permission.location);
    }

    await permissions.request();
    return true;
  }

  /// Request ignore battery optimization separately if needed
  Future<void> requestBatteryOptimization() async {
    try {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (_) {}
  }

  /// Request foreground task notification permission if needed
  Future<void> requestForegroundNotificationPermission() async {
    NotificationPermission notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  @override
  Future<void> setupBackgroundTasks() async {
    _initForegroundTask();

    // Register periodic reconnect task
    try {
      await Workmanager().registerPeriodicTask(
        'spdrop-reconnect',
        'spdrop-reconnect',
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
        ),
      );
    } catch (e) {
      debugPrint("Workmanager periodic task error: \$e");
    }
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'spdrop_foreground',
        channelName: 'SpDrop Connection',
        channelDescription: 'Keeps SpDrop connected to your devices in the background',
        // LOW importance = persistent silent notification (like Phone Link)
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        buttons: [
          const NotificationButton(id: 'send_clip', text: 'Send Clip'),
          const NotificationButton(id: 'quick_send', text: 'Quick Send'),
          const NotificationButton(id: 'disconnect', text: 'Disconnect'),
        ],
        iconData: const NotificationIconData(
          resType: ResourceType.drawable,
          resPrefix: ResourcePrefix.ic,
          name: 'notification',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true, playSound: false),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: true, // Auto-run on boot for always-ready experience
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  @override
  Future<void> handlePlatformArgs(List<String> args, {required void Function(List<String>) onArgsReceived}) async {
    // Usually no-op on Android, unless we have custom intent args passed via launch
  }
}
