import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:p2p_sync_app/src/rust/api.dart';
import '../core/identity/identity_service.dart';

import '../features/transfer/models/sp_drop_file.dart';
export '../features/transfer/models/sp_drop_file.dart';
class SessionKeys {
  final List<int> txKey;
  final List<int> rxKey;
  SessionKeys(this.txKey, this.rxKey);
}

/// High-performance chunked file transfer engine using 4-byte length-prefixed framing over TCP,
/// with optional AES-256-GCM encryption, streaming SHA-256 verification, and chunk resume support.

class RustFileService {
  Function(double progress, double speedMBps, int etaSeconds)? onProgress;
  Function(List<String>)? onFilesSent;
  Function(List<String>)? onFilesReceived;
  Function()? onTransferStarted;
  Function(String errorMessage)? onTransferError;
  Function(String stage)? onTransferStage;
  Function()? onTransferComplete;
  Function(File file)? onClipboardFileReceived;

  ServerSocket? _serverSocket;
  Directory? _downloadsDir;
  String? get saveDirectory => _downloadsDir?.path;
  bool _cancelled = false;
  bool _isSending = false;
  bool _isReceiving = false;

  bool get isTransferring => _isSending || _isReceiving;

  static const int _chunk = 4 * 1024 * 1024; // 4 MB chunk size
  static const int _encryptedFrameOverhead = 8 + 16; // 8-byte nonce counter + 16-byte MAC
  static const int _maxFrame = _chunk + _encryptedFrameOverhead;
  static const int _maxFile = 1024 * 1024 * 1024 * 1024; // 1 TB safety threshold
  static const int _socketBufferSize = 2 * 1024 * 1024; // 2 MB OS send/receive socket buffers

  int _lastProgressMs = 0;
  double _maxProgress = 0.0;

  // Platform-specific socket option constants for SO_SNDBUF and SO_RCVBUF.
  static const int _solSocketLinux = 1;       // SOL_SOCKET on Linux/Android
  static const int _solSocketWin   = 0xFFFF;  // SOL_SOCKET on Windows
  static const int _soSndbufLinux  = 7;       // SO_SNDBUF on Linux/Android
  static const int _soRcvbufLinux  = 8;       // SO_RCVBUF on Linux/Android
  static const int _soSndbufWin    = 0x1001;  // SO_SNDBUF on Windows
  static const int _soRcvbufWin    = 0x1002;  // SO_RCVBUF on Windows

  /// Configures TCP socket with tcpNoDelay and enlarged OS send/receive buffers.
  static void _configureSocket(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);

    try {
      final level  = Platform.isWindows ? _solSocketWin : _solSocketLinux;
      final sndbuf = Platform.isWindows ? _soSndbufWin  : _soSndbufLinux;
      final rcvbuf = Platform.isWindows ? _soRcvbufWin  : _soRcvbufLinux;
      final sizeBytes = _intToBytes(_socketBufferSize);
      socket.setRawOption(RawSocketOption(level, sndbuf, sizeBytes));
      socket.setRawOption(RawSocketOption(level, rcvbuf, sizeBytes));
    } catch (_) {
      // Platform may disallow raw socket option manipulation; tcpNoDelay remains active.
    }
  }

  static Uint8List _intToBytes(int value) {
    return (ByteData(4)..setInt32(0, value, Endian.host)).buffer.asUint8List();
  }

  /// Resolves the storage download directory with fallback paths across platforms.
  Future<Directory> _resolveDownloadsDir() async {
    if (_downloadsDir != null) return _downloadsDir!;

    if (Platform.isAndroid) {
      final primaryDir = Directory('/storage/emulated/0/Download/SpDrop');
      try {
        if (!await primaryDir.exists()) {
          await primaryDir.create(recursive: true);
        }
        _downloadsDir = primaryDir;
      } catch (_) {}

      if (_downloadsDir == null) {
        try {
          final d = await getDownloadsDirectory();
          if (d != null) {
            _downloadsDir = Directory(path.join(d.path, 'SpDrop'));
          }
        } catch (_) {}
      }
      
      if (_downloadsDir == null) {
        try {
          final d = await getExternalStorageDirectory();
          if (d != null) {
            _downloadsDir = Directory(path.join(d.path, 'SpDrop'));
          }
        } catch (_) {}
      }
      
      _downloadsDir ??= primaryDir;
    } else if (Platform.isWindows) {
      final d = await getDownloadsDirectory();
      _downloadsDir = Directory(path.join(d!.path, 'SpDrop'));
    } else {
      final d = await getApplicationDocumentsDirectory();
      _downloadsDir = Directory(path.join(d.path, 'SpDrop'));
    }

    if (!await _downloadsDir!.exists()) {
      await _downloadsDir!.create(recursive: true);
    }

    return _downloadsDir!;
  }

  /// Writes a 4-byte length-prefixed frame to the socket.
  static Future<void> _writeFrame(Socket socket, Uint8List bytes, {bool flush = false}) async {
    if (bytes.length > _maxFrame) {
      throw Exception('Frame too large: ${bytes.length} bytes (max $_maxFrame)');
    }
    final lenBuf = ByteData(4)..setUint32(0, bytes.length, Endian.big);
    socket.add(lenBuf.buffer.asUint8List());
    socket.add(bytes);
    if (flush) await socket.flush();
  }

  static crypto.HashSink _newSha256Sink() {
    return crypto.Sha256().toSync().newHashSink();
  }

  static String _hexDigest(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<String> _hashFile(File file, int fileSize, int totalSize) async {
    return await Isolate.run(() async {
      final stream = file.openRead();
      final sink = crypto.Sha256().toSync().newHashSink();
      await for (final chunk in stream) {
        sink.add(chunk);
      }
      sink.close();
      final hash = await sink.hash();
      return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    });
  }

  /// Throttles UI progress notification to approximately 30 FPS to minimize rendering overhead.
  void _throttledProgress(double progress, double speed, int eta) {
    if (progress < _maxProgress) progress = _maxProgress;
    _maxProgress = progress;
    progress = progress.clamp(0.0, 1.0);

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastProgressMs < 33) return;
    _lastProgressMs = now;
    onProgress?.call(progress, speed, eta);
  }

  static Future<SessionKeys> _handshakeInitiator(
    Socket socket,
    _FramedSocketReader stream,
  ) async {
    debugPrint('[SP_DIAG] Initiator: TCP connection established. Starting handshake.');
    try {
      final identity = IdentityService();
      final startRes = await apiHandshakeInitiatorStart(privateKey: identity.privateKey);
      final msg1Bytes = startRes.msg1Bytes;
      await _writeFrame(socket, msg1Bytes, flush: true);
      debugPrint('[SP_DIAG] Initiator: msg1 sent');

      final msg2Bytes = await stream.readFrame();
      debugPrint('[SP_DIAG] Initiator: msg2 received');
      final finishRes = await apiHandshakeInitiatorFinish(
        privateKey: identity.privateKey,
        ephemeralSecretBytes: startRes.ephemeralSecret,
        msg1Bytes: msg1Bytes,
        msg2Bytes: msg2Bytes,
      );

      await _writeFrame(socket, finishRes.msg3Bytes, flush: true);
      debugPrint('[SP_DIAG] Initiator: msg3 sent');

      final sessionKeys = SessionKeys(finishRes.sessionKeyTx, finishRes.sessionKeyRx);
      debugPrint('[SP_DIAG] Initiator: AES session keys derived');
      int nonceCounter = 0;

      // Exchange Encrypted Hello
      final myHello = jsonEncode({
        'deviceId': identity.deviceId ?? 'unknown',
        'deviceName': identity.deviceName ?? 'Unknown Device',
      });
      
      await _writeEncryptedFrame(socket, sessionKeys.txKey, nonceCounter++, utf8.encode(myHello));
      debugPrint('[SP_DIAG] Initiator: Hello sent');
      
      final peerHelloBytes = await _readEncryptedFrame(stream, sessionKeys.rxKey);
      debugPrint('[SP_DIAG] Initiator: Hello received/decrypted');
      final peerHello = jsonDecode(utf8.decode(peerHelloBytes));
      final peerDeviceId = peerHello['deviceId'] as String;
      final peerDeviceName = peerHello['deviceName'] as String;

      debugPrint('[SP_DIAG] Initiator: Identity verification reached');
      await identity.verifySession(
        finishRes.peerStaticPub,
        peerDeviceId,
        peerDeviceName,
        finishRes.sas,
        socket.remoteAddress.address,
        socket.remotePort,
      );
      debugPrint('[SP_DIAG] Initiator: SAS/trust reached and verified');

      return sessionKeys;
    } catch (e, stack) {
      debugPrint('[SP_DIAG] Initiator exception: $e\n$stack');
      rethrow;
    }
  }

  static Future<SessionKeys> _handshakeResponder(
    _FramedSocketReader stream,
    Socket socket,
  ) async {
    debugPrint('[SP_DIAG] Responder: TCP connection established. Waiting for msg1.');
    try {
      final peerPayloadBytes = await stream.readFrame();
      debugPrint('[SP_DIAG] Responder: msg1 received');

      final identity = IdentityService();
      final startRes = await apiHandshakeResponderStart(
          privateKey: identity.privateKey,
          msg1Bytes: peerPayloadBytes);

      await _writeFrame(socket, startRes.msg2Bytes, flush: true);
      debugPrint('[SP_DIAG] Responder: msg2 sent');

      final msg3Bytes = await stream.readFrame();
      debugPrint('[SP_DIAG] Responder: msg3 received');
      await apiHandshakeResponderFinish(
          peerStaticPubBytes: startRes.peerStaticPub,
          expectedMsg3Hash: startRes.expectedMsg3Hash,
          msg3Bytes: msg3Bytes);
      debugPrint('[SP_DIAG] Responder: msg3 verified');

      final sessionKeys = SessionKeys(startRes.sessionKeyTx, startRes.sessionKeyRx);
      debugPrint('[SP_DIAG] Responder: AES session keys derived');
      int nonceCounter = 0;

      // Read Initiator's Hello
      final peerHelloBytes = await _readEncryptedFrame(stream, sessionKeys.rxKey);
      debugPrint('[SP_DIAG] Responder: Hello received/decrypted');
      final peerHello = jsonDecode(utf8.decode(peerHelloBytes));
      final peerDeviceId = peerHello['deviceId'] as String;
      final peerDeviceName = peerHello['deviceName'] as String;

      // Send our Hello
      final myHello = jsonEncode({
        'deviceId': identity.deviceId ?? 'unknown',
        'deviceName': identity.deviceName ?? 'Unknown Device',
      });
      await _writeEncryptedFrame(socket, sessionKeys.txKey, nonceCounter++, utf8.encode(myHello));
      debugPrint('[SP_DIAG] Responder: Hello sent');

      debugPrint('[SP_DIAG] Responder: Identity verification reached');
      await identity.verifySession(
        startRes.peerStaticPub,
        peerDeviceId,
        peerDeviceName,
        startRes.sas,
        socket.remoteAddress.address,
        socket.remotePort,
      );
      debugPrint('[SP_DIAG] Responder: SAS/trust reached and verified');

      return sessionKeys;
    } catch (e, stack) {
      debugPrint('[SP_DIAG] Responder exception: $e\n$stack');
      rethrow;
    }
  }

  /// E2EE encrypt+send — offloaded to compute() isolate for large chunks
  static Future<void> _writeEncryptedFrame(
    Socket socket,
    List<int> sessionKey,
    int nonceCounter,
    List<int> plaintext,
  ) async {
    final encrypted = await compute(_encryptInIsolate, {
      'key': sessionKey,
      'nonce': nonceCounter,
      'data': plaintext,
    });
    await _writeFrame(socket, encrypted);
  }

  /// Runs in a separate isolate to avoid blocking UI thread
  static Future<Uint8List> _encryptInIsolate(Map<String, dynamic> args) async {
    final sessionKey = List<int>.from(args['key']);
    final nonceCounter = args['nonce'] as int;
    final plaintext = List<int>.from(args['data']);

    final algorithm = crypto.AesGcm.with256bits();
    final secretKey = crypto.SecretKey(sessionKey);

    final nonceBuf = ByteData(12);
    nonceBuf.setUint64(4, nonceCounter, Endian.big);
    final nonce = nonceBuf.buffer.asUint8List().toList();

    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );

    final counterBuf = ByteData(8)..setUint64(0, nonceCounter, Endian.big);
    final out = BytesBuilder(copy: false);
    out.add(counterBuf.buffer.asUint8List());
    out.add(secretBox.cipherText);
    out.add(secretBox.mac.bytes);

    return out.toBytes();
  }

  static Future<Uint8List> _readEncryptedFrame(
    _FramedSocketReader stream,
    List<int> sessionKey,
  ) async {
    final encrypted = await stream.readFrame();

    if (encrypted.length < 8) throw Exception('Encrypted frame too short');

    // Decrypt in isolate for large payloads
    return await compute(_decryptInIsolate, {
      'key': sessionKey,
      'data': encrypted,
    });
  }

  /// Runs in a separate isolate to avoid blocking UI thread
  static Future<Uint8List> _decryptInIsolate(Map<String, dynamic> args) async {
    final sessionKey = List<int>.from(args['key']);
    final encrypted = Uint8List.fromList(List<int>.from(args['data']));

    final counter = ByteData.sublistView(encrypted, 0, 8).getUint64(0, Endian.big);
    final ciphertext = encrypted.sublist(8);

    final algorithm = crypto.AesGcm.with256bits();
    final secretKey = crypto.SecretKey(sessionKey);

    final nonceBuf = ByteData(12);
    nonceBuf.setUint64(4, counter, Endian.big);
    final nonce = nonceBuf.buffer.asUint8List().toList();

    if (ciphertext.length < 16) throw Exception('Ciphertext missing MAC');
    final actualCiphertext = ciphertext.sublist(0, ciphertext.length - 16);
    final macBytes = ciphertext.sublist(ciphertext.length - 16);

    final secretBox = crypto.SecretBox(
      actualCiphertext,
      nonce: nonce,
      mac: crypto.Mac(macBytes),
    );

    final plaintext = await algorithm.decrypt(secretBox, secretKey: secretKey);
    return Uint8List.fromList(plaintext);
  }

  // SENDER: Connect to receiver, stream files with framed protocol

  Future<void> sendDirectory(
    Directory dir,
    String ip,
    int port, {
    bool useE2ee = true,
  }) async {
    final List<SpDropFile> spFiles = [];
    int totalSize = 0;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final pathStr = entity.path;
        final rel = path.relative(pathStr, from: dir.path);
        final normalizedRel = rel.replaceAll(path.separator, '/');
        spFiles.add(SpDropFile(entity, relativePath: normalizedRel));
        totalSize += await entity.length();
      }
    }

    await sendFiles(spFiles, totalSize, ip, port, useE2ee: useE2ee);
  }

  Future<void> sendFiles(
    List<SpDropFile> files,
    int totalSize,
    String ip,
    int port, {
    bool useE2ee = true,
  }) async {
    _cancelled = false;
    _isSending = true;
    _lastProgressMs = 0;
    _maxProgress = 0.0;
    onTransferStarted?.call();

    int sentBytes = 0;
    final stopwatch = Stopwatch()..start();
    final List<String> sentNames = [];

    try {
      for (final spFile in files) {
        if (_cancelled) break;

        final file = spFile.file;
        final fileName = file.path.split(Platform.pathSeparator).last;
        final fileSize = await file.length();
        onTransferStage?.call('Preparing $fileName...');
        final fileHash = await _hashFile(file, fileSize, totalSize);
        onTransferStage?.call('Connecting to receiver...');

        // Connect with tcpNoDelay
        Socket socket;
        try {
          socket = await Socket.connect(
            ip,
            port,
            timeout: const Duration(seconds: 10),
          );
          debugPrint('[SP_DIAG] TCP Connection established to $ip:$port');
          _configureSocket(socket);
        } catch (e) {
          final msg = "Connection to device failed. Please ensure both devices are active.";
          debugPrint(msg);
          onTransferError?.call(msg);
          throw Exception(msg);
        }

        final stream = _FramedSocketReader(socket);

        try {
          // Handshake if E2EE
          SessionKeys? sessionKeys;
          int nonceCounter = 0;
          if (useE2ee) {
            sessionKeys = await _handshakeInitiator(socket, stream);
            nonceCounter = 1; // Hello frame used nonce 0
          }

          // Step 1: Send offer frame (JSON)
          final offer = {
            'name': fileName,
            'size': fileSize,
            'sha256': fileHash,
            'relative_path': spFile.relativePath,
            'is_clipboard': spFile.isClipboard,
          };

          final offerJson = utf8.encode(jsonEncode(offer));
          if (useE2ee) {
            await _writeEncryptedFrame(socket, sessionKeys!.txKey, nonceCounter++, offerJson);
          } else {
            await _writeFrame(socket, Uint8List.fromList(offerJson), flush: true);
          }

          // Step 2: Wait for ACCEPT or RESUME
          final response = useE2ee
              ? await _readEncryptedFrame(stream, sessionKeys!.rxKey)
              : await stream.readFrame();

          final responseStr = utf8.decode(response);
          int resumeOffset = 0;
          if (responseStr.startsWith('RESUME:')) {
            resumeOffset = int.parse(responseStr.substring(7));
          } else if (responseStr != 'ACCEPT') {
            throw Exception('Receiver rejected transfer: $responseStr');
          }

          // Step 3: Stream file in 4 MB chunks
          onTransferStage?.call('Sending $fileName...');
          final raf = await file.open(mode: FileMode.read);
          try {
            if (resumeOffset > 0) {
              await raf.setPosition(resumeOffset);
              sentBytes += resumeOffset;
            }
            final buf = Uint8List(_chunk);
            while (!_cancelled) {
              final n = await raf.readInto(buf);
              if (n == 0) break;

              final chunk = n == _chunk ? buf : Uint8List.sublistView(buf, 0, n);
              if (useE2ee) {
                await _writeEncryptedFrame(socket, sessionKeys!.txKey, nonceCounter++, chunk);
              } else {
                await _writeFrame(socket, chunk);
              }

              sentBytes += n;

              // Report progress (throttled to 30fps)
              if (onProgress != null && totalSize > 0) {
                final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
                final speed = elapsedSeconds > 0
                    ? (sentBytes / 1024 / 1024) / elapsedSeconds
                    : 0.0;
                final remainingBytes = totalSize - sentBytes;
                final eta = speed > 0
                    ? (remainingBytes / 1024 / 1024 / speed).round()
                    : 0;
                final progress = (sentBytes / totalSize).clamp(0.0, 1.0);
                _throttledProgress(progress, speed, eta);
              }
            }

            // Flush everything at end-of-file (stream batching)
            if (!_cancelled) {
              await socket.flush();
            }
          } finally {
            await raf.close();
          }

          // Step 4: Clean shutdown
          await socket.close();

          // Brief delay between files
          if (files.indexOf(spFile) < files.length - 1) {
            await Future.delayed(const Duration(milliseconds: 150));
          }

          sentNames.add(fileName);
        } catch (e) {
          socket.destroy();
          rethrow;
        } finally {
          stream.dispose();
          socket.destroy();
        }
      }

      stopwatch.stop();
      _isSending = false;
      onFilesSent?.call(sentNames);
      onTransferComplete?.call();
    } catch (e) {
      debugPrint("RustFileService send error: $e");
      _isSending = false;
      onTransferError?.call("Transfer interrupted. Network connection lost.");
      stopwatch.stop();
    }
  }

  // RECEIVER: Start TCP server, accept and verify

  Future<int> startReceivingServer(
    String batchManifest,
    int totalSize, {
    bool useE2ee = true,
  }) async {
    _cancelled = false;
    _isReceiving = true;
    _lastProgressMs = 0;
    _maxProgress = 0.0;
    onTransferStarted?.call();

    final manifest = List<Map<String, dynamic>>.from(jsonDecode(batchManifest));
    final downloadsDir = await _resolveDownloadsDir();

    final bindAddress = InternetAddress.anyIPv4;
    debugPrint('[RustFileService] Binding receiver to 0.0.0.0 (anyIPv4)');

    try {
      _serverSocket = await ServerSocket.bind(bindAddress, 0);
    } catch (e) {
      final msg = "Could not start receiving service. Port may be in use.";
      debugPrint(msg);
      onTransferError?.call(msg);
      rethrow;
    }

    final port = _serverSocket!.port;
    debugPrint('[RustFileService] Receiver listening on port $port');

    _acceptConnections(manifest, totalSize, downloadsDir, useE2ee);

    return port;
  }

  Future<void> _acceptConnections(
    List<Map<String, dynamic>> manifest,
    int totalSize,
    Directory downloadsDir,
    bool useE2ee,
  ) async {
    final stopwatch = Stopwatch()..start();
    int totalReceived = 0;
    final List<String> receivedPaths = [];

    try {
      int fileIndex = 0;
      await for (final Socket client in _serverSocket!) {
        debugPrint('[SP_DIAG] ServerSocket accepted new incoming TCP connection');
        if (_cancelled || fileIndex >= manifest.length) {
          client.destroy();
          break;
        }

        // Configure incoming socket for high throughput
        _configureSocket(client);

        final i = fileIndex;
        fileIndex++;
        debugPrint('[RustFileService] Client connected');

        final stream = _FramedSocketReader(client);

        try {
          // Step 0: Handshake
          SessionKeys? sessionKeys;
          int nonceCounter = 0;
          if (useE2ee) {
            sessionKeys = await _handshakeResponder(stream, client);
            nonceCounter = 1; // Hello frame used nonce 0
          }

          // Step 1: Read offer frame
          final offerBytes = useE2ee
              ? await _readEncryptedFrame(stream, sessionKeys!.rxKey)
              : await stream.readFrame();

          final offer = jsonDecode(utf8.decode(offerBytes)) as Map<String, dynamic>;
          final fileName = _sanitizeFilename(offer['name'] as String);
          final fileSize = offer['size'] as int;
          final expectedHash = (offer['sha256'] as String).toLowerCase();
          final relativePath = offer['relative_path'] as String?;
          final isClipboard = offer['is_clipboard'] as bool? ?? false;

          if (fileSize > _maxFile) throw Exception('File too large: $fileSize bytes');
          if (fileName.isEmpty) throw Exception('Invalid file name');

          String targetDir = downloadsDir.path;
          if (isClipboard) {
             final tempDir = await getTemporaryDirectory();
             targetDir = tempDir.path;
          } else if (relativePath != null) {
            final parentDir = path.dirname(relativePath);
            if (parentDir != '.') {
              targetDir = path.join(downloadsDir.path, parentDir);
            }
          }
          await Directory(targetDir).create(recursive: true);
          final finalPath = path.join(targetDir, fileName);

          // Resume state
          final cleanHash = expectedHash.replaceAll(RegExp(r'[^a-f0-9]'), '');
          final resumeStatePath = path.join(downloadsDir.path, '.$cleanHash.spdrop_resume');
          final resumeFile = File(resumeStatePath);

          int resumeOffset = 0;
          File tmpFile = File(
            path.join(targetDir, '.${DateTime.now().millisecondsSinceEpoch}_$i.part'),
          );

          if (await resumeFile.exists()) {
            try {
              final stateData = jsonDecode(await resumeFile.readAsString());
              if (stateData['sha256'] == expectedHash) {
                final partPath = stateData['part_file_path'];
                final existingPart = File(partPath);
                if (await existingPart.exists()) {
                  final len = await existingPart.length();
                  if (len <= fileSize && len == stateData['bytes_received']) {
                    resumeOffset = len;
                    tmpFile = existingPart;
                  }
                }
              }
            } catch (_) {}
          }

          // Step 2: Send ACCEPT or RESUME
          if (resumeOffset > 0) {
            final resp = utf8.encode('RESUME:$resumeOffset');
            if (useE2ee) {
              await _writeEncryptedFrame(client, sessionKeys!.txKey, nonceCounter++, resp);
            } else {
              await _writeFrame(client, Uint8List.fromList(resp), flush: true);
            }
          } else {
            final resp = utf8.encode('ACCEPT');
            if (useE2ee) {
              await _writeEncryptedFrame(client, sessionKeys!.txKey, nonceCounter++, resp);
            } else {
              await _writeFrame(client, Uint8List.fromList(resp), flush: true);
            }
            await resumeFile.writeAsString(jsonEncode({
              'file_name': fileName,
              'sha256': expectedHash,
              'bytes_received': 0,
              'total_size': fileSize,
              'part_file_path': tmpFile.path,
            }));
          }

          // Step 3: Receive chunks
          final sink = tmpFile.openWrite(
            mode: resumeOffset > 0 ? FileMode.append : FileMode.write,
          );
          final hasher = _newSha256Sink();

          if (resumeOffset > 0) {
            final reader = tmpFile.openRead();
            await for (final chunk in reader) {
              hasher.add(chunk);
            }
          }

          int remaining = fileSize - resumeOffset;
          int currentReceived = resumeOffset;

          try {
            while (remaining > 0 && !_cancelled) {
              final chunk = useE2ee
                  ? await _readEncryptedFrame(stream, sessionKeys!.rxKey)
                  : await stream.readFrame();

              if (chunk.isEmpty || chunk.length > remaining) {
                throw Exception('Bad chunk: len=${chunk.length}, remaining=$remaining');
              }

              sink.add(chunk);
              hasher.add(chunk);
              remaining -= chunk.length;
              totalReceived += chunk.length;
              currentReceived += chunk.length;

              // Atomic resume state write — write to .tmp then
              // rename to prevent truncated JSON on crash/power loss.
              if (currentReceived % (50 * 1024 * 1024) == 0) {
                final tmpResumePath = '${resumeFile.path}.tmp';
                try {
                  await File(tmpResumePath).writeAsString(jsonEncode({
                    'file_name': fileName,
                    'sha256': expectedHash,
                    'bytes_received': currentReceived,
                    'total_size': fileSize,
                    'part_file_path': tmpFile.path,
                  }));
                  await File(tmpResumePath).rename(resumeFile.path);
                } catch (_) {
                  // Non-fatal — transfer continues even if resume state fails
                }
              }

              // Report progress (throttled)
              if (onProgress != null && totalSize > 0) {
                final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
                final speed = elapsedSeconds > 0
                    ? (totalReceived / 1024 / 1024) / elapsedSeconds
                    : 0.0;
                final remainingBytes = totalSize - totalReceived;
                final eta = speed > 0
                    ? (remainingBytes / 1024 / 1024 / speed).round()
                    : 0;
                _throttledProgress(totalReceived / totalSize, speed, eta);
              }
            }

            await sink.flush();
            await sink.close();

            // Step 4: Verify SHA-256
            hasher.close();
            final computedHash = _hexDigest((await hasher.hash()).bytes);
            if (computedHash != expectedHash) {
              await tmpFile.delete();
              throw Exception(
                'SHA-256 mismatch for $fileName: expected $expectedHash, got $computedHash',
              );
            }

            // Step 5: Atomic rename
            await tmpFile.rename(finalPath);
            if (await resumeFile.exists()) {
              await resumeFile.delete();
            }
            if (isClipboard) {
               onClipboardFileReceived?.call(File(finalPath));
               // We do not add it to receivedPaths so it doesn't trigger standard UI notifications for normal files.
            } else {
               receivedPaths.add(finalPath);
            }

            debugPrint('[RustFileService] File received and verified');
          } catch (e) {
            await sink.close();
            if (await tmpFile.exists()) {
              await tmpFile.delete();
            }
            rethrow;
          }
        } finally {
          stream.dispose();
          client.destroy();
        }

        if (fileIndex >= manifest.length) {
          break;
        }
      }

      if (receivedPaths.length != manifest.length) {
        throw Exception(
          'Transfer ended early: received ${receivedPaths.length}/${manifest.length} files',
        );
      }

      stopwatch.stop();
      _serverSocket?.close();
      _serverSocket = null;
      _isReceiving = false;
      onFilesReceived?.call(receivedPaths);
      onTransferComplete?.call();
    } catch (e) {
      stopwatch.stop();
      debugPrint('[RustFileService] Receive error: $e');
      _isReceiving = false;
      onTransferError?.call('File receive failed. Connection was lost or canceled.');
      _serverSocket?.close();
      _serverSocket = null;
    }
  }

  // Filename sanitization

  static String _sanitizeFilename(String name) {
    String clean = name.replaceAll(RegExp(r'[/\\:\0]'), '_');
    clean = clean.replaceAll(RegExp(r'^\.+'), '');
    clean = clean.replaceAll(RegExp(r'[\. ]+$'), '');
    if (clean.length > 255) clean = clean.substring(0, 255);
    return clean.isEmpty ? 'unnamed_file' : clean;
  }

  // Lifecycle

  void stop() {
    _serverSocket?.close();
    _serverSocket = null;
  }

  void cancelTransfer() {
    _cancelled = true;
    _isSending = false;
    _isReceiving = false;
    stop();
  }

  /// Resets transfer state flags without shutting down active server socket.
  Future<void> resetAfterTransfer() async {
    _cancelled = false;
    _isSending = false;
    _isReceiving = false;
    _lastProgressMs = 0;
    _maxProgress = 0.0;
  }
}

/// Buffered frame reader using a contiguous buffer with amortized O(1) growth for zero-copy reads.
class _FramedSocketReader {
  final Socket _socket;
  Uint8List _buf = Uint8List(8 * 1024 * 1024); // 8 MB initial buffer allocation
  int _writePos = 0;
  int _readPos = 0;

  StreamSubscription? _subscription;
  Completer<void>? _dataCompleter;
  bool _done = false;

  _FramedSocketReader(this._socket) {
    _subscription = _socket.listen(
      (Uint8List data) {
        _ensureCapacity(data.length);
        _buf.setRange(_writePos, _writePos + data.length, data);
        _writePos += data.length;
        _dataCompleter?.complete();
        _dataCompleter = null;
      },
      onError: (e) {
        _done = true;
        _dataCompleter?.completeError(e);
        _dataCompleter = null;
      },
      onDone: () {
        _done = true;
        _dataCompleter?.complete();
        _dataCompleter = null;
      },
    );
  }

  int get _available => _writePos - _readPos;

  void _ensureCapacity(int additionalBytes) {
    final needed = _writePos + additionalBytes;
    if (needed <= _buf.length) return;

    if (_readPos > 0) {
      _buf.setRange(0, _available, _buf, _readPos);
      _writePos = _available;
      _readPos = 0;
    }

    if (_writePos + additionalBytes > _buf.length) {
      int newSize = _buf.length;
      while (newSize < _writePos + additionalBytes) {
        newSize *= 2;
      }
      final newBuf = Uint8List(newSize);
      newBuf.setRange(0, _writePos, _buf);
      _buf = newBuf;
    }
  }

  Future<void> _waitForBytes(int needed) async {
    while (_available < needed) {
      if (_done) {
        throw Exception('Socket closed: needed $needed bytes, have $_available');
      }
      _dataCompleter = Completer<void>();
      await _dataCompleter!.future;
    }
  }

  Future<Uint8List> readFrame() async {
    await _waitForBytes(4);

    final len = ByteData.sublistView(_buf, _readPos, _readPos + 4)
        .getUint32(0, Endian.big);

    if (len > RustFileService._maxFrame) {
      throw Exception('Frame too large: $len bytes');
    }

    await _waitForBytes(4 + len);

    final frame = Uint8List.fromList(_buf.sublist(_readPos + 4, _readPos + 4 + len));
    _readPos += 4 + len;

    return frame;
  }

  void dispose() {
    _subscription?.cancel();
  }
}
