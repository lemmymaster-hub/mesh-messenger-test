import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_test/services/processed_message_cache.dart';

void main() {
  group('ProcessedMessageCache', () {
    test('prepoznaje duplikat unutar TTL perioda', () {
      final cache = ProcessedMessageCache(
        timeToLive: const Duration(minutes: 5),
      );
      final now = DateTime(2026, 8, 20, 12);

      expect(cache.markIfNew('message-1', now: now), isTrue);
      expect(
        cache.markIfNew(
          'message-1',
          now: now.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });

    test('dozvoljava isti ID nakon isteka TTL perioda', () {
      final cache = ProcessedMessageCache(
        timeToLive: const Duration(minutes: 5),
      );
      final now = DateTime(2026, 8, 20, 12);

      expect(cache.markIfNew('message-1', now: now), isTrue);
      expect(
        cache.markIfNew(
          'message-1',
          now: now.add(const Duration(minutes: 6)),
        ),
        isTrue,
      );
    });

    test('izbacuje najstariji unos kada dostigne limit', () {
      final cache = ProcessedMessageCache(
        maxEntries: 2,
        timeToLive: const Duration(hours: 1),
      );
      final now = DateTime(2026, 8, 20, 12);

      expect(cache.markIfNew('message-1', now: now), isTrue);
      expect(cache.markIfNew('message-2', now: now), isTrue);
      expect(cache.markIfNew('message-3', now: now), isTrue);
      expect(cache.length, 2);
      expect(cache.markIfNew('message-1', now: now), isTrue);
    });
  });
}
