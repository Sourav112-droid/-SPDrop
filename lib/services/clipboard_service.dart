import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:uuid/uuid.dart';
import 'local_signaling_service.dart';

import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'clipboard_privacy_service.dart';

import '../features/clipboard/models/clipboard_event_cache.dart';
export '../features/clipboard/models/clipboard_event_cache.dart';

/// Service managing bidirectional clipboard synchronization across connected peers.
class ClipboardService with ClipboardListener {
  LocalSignalingService? _signalingService;
  Timer? _timer;
  
  String _lastLocalTextHash = "";
  String _lastLocalImageHash = "";
  bool _isSyncing = false;
  bool _isRemoteUpdate = false;

  final ClipboardEventCache _eventCache = ClipboardEventCache();
  String? _expectedEchoHash;
  DateTime? _expectedEchoTime;

  bool Function()? _isTransferActive;
  
  void Function(List<File> files)? onSendClipboardFiles;

  void setSignalingService(LocalSignalingService service) {
    _signalingService = service;
  }

  void setIsolationCallback(bool Function() callback) {
    _isTransferActive = callback;
  }
  
  void setFileTransferCallback(void Function(List<File> files) callback) {
    onSendClipboardFiles = callback;
  }

  bool get isSyncing => _isSyncing;

  void startSync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    
    if (Platform.isWindows) {
      clipboardWatcher.addListener(this);
      clipboardWatcher.start();
    } else {
      _timer = Timer.periodic(const Duration(seconds: 2), _pollClipboard);
    }
  }

  void stopSync() {
    _isSyncing = false;
    if (Platform.isWindows) {
      clipboardWatcher.removeListener(this);
      clipboardWatcher.stop();
    } else {
      _timer?.cancel();
      _timer = null;
    }
    _debounceTimer?.cancel();
    _remoteUpdateResetTimer?.cancel();
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _remoteUpdateResetTimer = null;
  }
  
  Timer? _debounceTimer;
  Timer? _remoteUpdateResetTimer;

  @override
  void onClipboardChanged() async {
    if (!_isSyncing) return;
    // Debounce to allow OS clipboard write operations to finalize.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      _checkClipboardContent();
    });
  }

  bool _isReading = false;

  Future<void> _pollClipboard(Timer timer) async {
    await _checkClipboardContent();
  }

  Future<void> _checkClipboardContent() async {
    if (!_isSyncing || _isRemoteUpdate || _isReading || (_isTransferActive?.call() ?? false)) return;
    if (_signalingService == null || !_signalingService!.isConnected) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('clipboard_sync_enabled') != true) return;

    final isAuthorized = await ClipboardPrivacyService.canSyncToDevice(
      _signalingService!.connectedPeerPublicKeyFingerprint,
      _signalingService!.connectedDeviceName ?? 'Unknown Device',
    );
    if (!isAuthorized) return;

    _isReading = true;
    try {
      final reader = await ClipboardReader.readClipboard();
      
      if (reader.canProvide(Formats.png)) {
         final completer = Completer<void>();
         reader.getFile(Formats.png, (file) async {
            try {
              final pngBytes = await file.readAll();
              if (pngBytes.isNotEmpty) {
                 final hash = "img_${pngBytes.length}_${pngBytes.take(100).join()}";
                 if (hash != _lastLocalImageHash) {
                    _lastLocalImageHash = hash;
                    final tempDir = await getTemporaryDirectory();
                    final eventId = const Uuid().v4();
                    final originDeviceId = _signalingService!.stableDeviceId ?? 'unknown';
                    _eventCache.markProcessed(eventId);
                    // Embed metadata into filename for receiver deduplication.
                    final tempFile = File('${tempDir.path}/clipboard_image_${eventId}_$originDeviceId.png');
                    await tempFile.writeAsBytes(pngBytes);
                    onSendClipboardFiles?.call([tempFile]);
                 }
              }
            } finally {
              if (!completer.isCompleted) completer.complete();
            }
         }, onError: (e) {
            if (!completer.isCompleted) completer.complete();
         });
         
         await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {});
      }
      
      String? plainText;
      String? htmlText;

      if (reader.canProvide(Formats.htmlText)) {
        htmlText = await reader.readValue(Formats.htmlText);
      }
      if (reader.canProvide(Formats.plainText)) {
        plainText = await reader.readValue(Formats.plainText);
      }

      if ((plainText != null && plainText.isNotEmpty) || (htmlText != null && htmlText.isNotEmpty)) {
        if (plainText != null && ClipboardPrivacyService.isContentSensitive(plainText)) {
          return;
        }
        
        final hash = "txt_${plainText?.hashCode ?? 0}_${htmlText?.hashCode ?? 0}";
        
        // Suppress OS echo resulting from programmatic remote clipboard update.
        if (_expectedEchoHash == hash && _expectedEchoTime != null && DateTime.now().difference(_expectedEchoTime!) < const Duration(seconds: 3)) {
          _expectedEchoHash = null;
          return;
        }

        bool isNewCopy = false;
        if (Platform.isWindows) {
           isNewCopy = true;
        } else {
           isNewCopy = hash != _lastLocalTextHash;
        }

        if (isNewCopy) {
           _lastLocalTextHash = hash;
           final eventId = const Uuid().v4();
           final originDeviceId = _signalingService!.stableDeviceId ?? 'unknown';
           _eventCache.markProcessed(eventId);
           _signalingService!.sendClipboardText(
             plainText ?? '', 
             html: htmlText, 
             eventId: eventId, 
             originDeviceId: originDeviceId, 
             timestamp: DateTime.now().millisecondsSinceEpoch,
             contentHash: hash
           );
        }
      }

    } catch (e) {
      debugPrint('Clipboard sync error: $e');
    } finally {
      _isReading = false;
    }
  }

  void onRemoteClipboardReceived(
    String text, 
    {String? html, 
    String? eventId, 
    String? originDeviceId, 
    int? timestamp, 
    String? contentHash}
  ) async {
    if (text.isEmpty && (html == null || html.isEmpty)) return;
    final hash = contentHash ?? "txt_${text.hashCode}_${html?.hashCode ?? 0}";

    if (eventId != null && eventId.isNotEmpty && originDeviceId != null && originDeviceId.isNotEmpty) {
      if (originDeviceId == (_signalingService?.stableDeviceId ?? 'unknown')) {
        debugPrint("CLIPBOARD_EVENT_SELF_ORIGIN: Ignored event from self");
        return;
      }

      if (_eventCache.isProcessed(eventId)) {
        debugPrint("CLIPBOARD_EVENT_DUPLICATE: Ignored already seen event");
        return;
      }
      
      _eventCache.markProcessed(eventId);
      debugPrint("CLIPBOARD_EVENT_RECEIVED: Processing remote event $eventId");
    } else {
      // Fallback hash check when event ID is absent.
      if (hash == _lastLocalTextHash) return;
    }
    
    _isRemoteUpdate = true;
    _expectedEchoHash = hash;
    _expectedEchoTime = DateTime.now();
    _lastLocalTextHash = hash;
    
    try {
      final item = DataWriterItem();
      if (html != null && html.isNotEmpty) {
        item.add(Formats.htmlText(html));
      }
      if (text.isNotEmpty) {
        item.add(Formats.plainText(text));
      }
      await ClipboardWriter.instance.write([item]);
      debugPrint("CLIPBOARD_EVENT_APPLIED: Clipboard updated");
    } catch (e) {
      debugPrint('Error setting clipboard text: $e');
    }
    
    _remoteUpdateResetTimer?.cancel();
    _remoteUpdateResetTimer = Timer(const Duration(seconds: 3), () => _isRemoteUpdate = false);
  }
  
  void onRemoteClipboardImageReceived(File imageFile) async {
    final fileName = imageFile.uri.pathSegments.last;
    
    String? eventId;
    String? originDeviceId;
    
    if (fileName.startsWith('clipboard_image_')) {
      final parts = fileName.split('_');
      if (parts.length >= 4) {
        eventId = parts[2];
        originDeviceId = parts[3].replaceAll('.png', '');
      }
    }

    if (eventId != null && originDeviceId != null) {
      if (originDeviceId == (_signalingService?.stableDeviceId ?? 'unknown')) {
        debugPrint("CLIPBOARD_EVENT_SELF_ORIGIN (Image): Ignored event from self");
        return;
      }

      if (_eventCache.isProcessed(eventId)) {
        debugPrint("CLIPBOARD_EVENT_DUPLICATE (Image): Ignored already seen event");
        return;
      }
      _eventCache.markProcessed(eventId);
    }

    _isRemoteUpdate = true;
    try {
      final bytes = await imageFile.readAsBytes();
      final hash = "img_${bytes.length}_${bytes.take(100).join()}";
      _lastLocalImageHash = hash;
      
      final item = DataWriterItem()..add(Formats.png(bytes));
      await ClipboardWriter.instance.write([item]);
      
      try {
        await imageFile.delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('Error setting clipboard image: $e');
    }
    _remoteUpdateResetTimer?.cancel();
    _remoteUpdateResetTimer = Timer(const Duration(seconds: 3), () => _isRemoteUpdate = false);
  }

  Future<String> getClipboard() async {
    try {
      final reader = await ClipboardReader.readClipboard();
      if (reader.canProvide(Formats.plainText)) {
        return (await reader.readValue(Formats.plainText)) ?? '';
      }
    } catch (_) {}
    return '';
  }
}
