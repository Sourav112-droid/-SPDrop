import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_sync_app/services/clipboard_service.dart';

void main() {
  group('ClipboardEventCache Loop Prevention Tests', () {
    test('duplicate eventId is rejected', () {
      final cache = ClipboardEventCache();
      cache.markProcessed('event-123');
      expect(cache.isProcessed('event-123'), isTrue);
    });

    test('same content with different eventIds is allowed', () {
      final cache = ClipboardEventCache();
      cache.markProcessed('event-123');
      // different eventId but let's assume same content text. The cache only checks eventId.
      expect(cache.isProcessed('event-456'), isFalse);
    });

    test('cache size limit evicts oldest', () {
      final cache = ClipboardEventCache();
      
      // max size is 100, insert 105
      for (var i = 0; i < 105; i++) {
        cache.markProcessed('event-$i');
      }

      // First 5 should be evicted
      expect(cache.isProcessed('event-0'), isFalse);
      expect(cache.isProcessed('event-4'), isFalse);
      
      // Last 100 should be kept
      expect(cache.isProcessed('event-5'), isTrue);
      expect(cache.isProcessed('event-104'), isTrue);
    });
  });
}
