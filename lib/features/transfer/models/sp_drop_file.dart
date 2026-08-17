import 'dart:io';

/// High-performance chunked file transfer engine using 4-byte length-prefixed framing over TCP,
/// with optional AES-256-GCM encryption, streaming SHA-256 verification, and chunk resume support.
class SpDropFile {
  final File file;
  final String? relativePath;
  final bool isClipboard;

  SpDropFile(this.file, {this.relativePath, this.isClipboard = false});
}
