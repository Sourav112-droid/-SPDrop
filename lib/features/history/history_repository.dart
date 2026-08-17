import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../transfer/models/transfer_record.dart';

class HistoryRepository {
  static const String _keyHistory = 'transfer_history';

  Future<List<TransferRecord>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_keyHistory);
    if (jsonList == null) return [];

    return jsonList
        .map((str) => TransferRecord.fromJson(jsonDecode(str)))
        .toList()
        .reversed
        .toList();
  }

  /// Appends a transfer record to persistent history with a rolling limit of 200 entries.
  Future<void> logTransfer(
    String filename,
    String direction, {
    String? filePath,
    int? fileSize,
    String? peerDevice,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_keyHistory) ?? [];

    final record = TransferRecord(
      filename: filename,
      direction: direction,
      timestamp: DateTime.now(),
      filePath: filePath,
      fileSize: fileSize,
      peerDevice: peerDevice,
    );
    jsonList.add(jsonEncode(record.toJson()));

    if (jsonList.length > 200) { // Increased history limit
      jsonList.removeAt(0);
    }

    await prefs.setStringList(_keyHistory, jsonList);
  }

  /// Clears all transfer history entries.
  Future<void> clearAllHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyHistory, []);
  }

  /// Deletes a history record by comparing timestamp millisecond values to avoid timezone string mismatches.
  Future<void> deleteRecord(String filename, DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_keyHistory) ?? [];
    final targetMs = timestamp.millisecondsSinceEpoch;

    jsonList.removeWhere((str) {
      final d = jsonDecode(str);
      if (d['filename'] != filename) return false;
      try {
        final recordMs = DateTime.parse(d['timestamp']).millisecondsSinceEpoch;
        // Allow 1-second tolerance for rounding
        return (recordMs - targetMs).abs() < 1000;
      } catch (_) {
        return false;
      }
    });

    await prefs.setStringList(_keyHistory, jsonList);
  }
}
