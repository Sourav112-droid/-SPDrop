/// Bounded cache preventing duplicate processing of identical clipboard events.
class ClipboardEventCache {
  final Map<String, DateTime> _processedIds = {};
  static const int _maxSize = 100;

  bool isProcessed(String eventId) {
    _cleanup();
    return _processedIds.containsKey(eventId);
  }

  void markProcessed(String eventId) {
    _processedIds[eventId] = DateTime.now();
    _cleanup();
  }

  void _cleanup() {
    final now = DateTime.now();
    _processedIds.removeWhere((key, value) => now.difference(value).inHours >= 1);
    
    if (_processedIds.length > _maxSize) {
      final sortedKeys = _processedIds.keys.toList()
        ..sort((a, b) => _processedIds[a]!.compareTo(_processedIds[b]!));
      for (var i = 0; i < sortedKeys.length - _maxSize; i++) {
        _processedIds.remove(sortedKeys[i]);
      }
    }
  }
}
