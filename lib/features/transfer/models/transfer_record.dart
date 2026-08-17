/// Represents a completed file transfer entry in persistent history.
class TransferRecord {
  final String filename;
  final String direction; // 'Sent' or 'Received'
  final DateTime timestamp;
  final String? filePath; // actual file path for "Open File"
  final int? fileSize; // file size in bytes
  final String? peerDevice; // device name of sender/receiver

  TransferRecord({
    required this.filename,
    required this.direction,
    required this.timestamp,
    this.filePath,
    this.fileSize,
    this.peerDevice,
  });

  Map<String, dynamic> toJson() => {
    'filename': filename,
    'direction': direction,
    'timestamp': timestamp.toIso8601String(),
    'filePath': filePath,
    'fileSize': fileSize,
    'peerDevice': peerDevice,
  };

  factory TransferRecord.fromJson(Map<String, dynamic> json) {
    return TransferRecord(
      filename: json['filename'],
      direction: json['direction'],
      timestamp: DateTime.parse(json['timestamp']),
      filePath: json['filePath'],
      fileSize: json['fileSize'], // backward compatible (nullable)
      peerDevice: json['peerDevice'], // backward compatible (nullable)
    );
  }

  /// Returns the lowercase file extension for asset and icon resolution.
  String get fileExtension {
    final parts = filename.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  /// Formats byte size into human-readable unit notation.
  String get formattedSize {
    if (fileSize == null) return '';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    if (fileSize! < 1024 * 1024 * 1024) return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(fileSize! / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Formats timestamp into contextual relative time (e.g., "Today 2:30 PM", "Yesterday 10:15 AM").
  String get formattedDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recordDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (recordDate == today) {
      return 'Today ${_formatTime(timestamp)}';
    } else if (recordDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday ${_formatTime(timestamp)}';
    } else if (now.difference(timestamp).inDays < 7) {
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[timestamp.weekday - 1]} ${_formatTime(timestamp)}';
    } else {
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                       'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[timestamp.month - 1]} ${timestamp.day} ${_formatTime(timestamp)}';
    }
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }

  /// Categorizes record into chronological display groups.
  String get dateGroup {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recordDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (recordDate == today) return 'Today';
    if (recordDate == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (now.difference(timestamp).inDays < 7) return 'This Week';
    if (now.difference(timestamp).inDays < 30) return 'This Month';
    return 'Older';
  }
}
