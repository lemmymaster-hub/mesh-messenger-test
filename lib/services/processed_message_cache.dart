import 'dart:collection';

/// Ograničen cache već viđenih poruka koji sprečava relay petlje bez
/// beskonačnog rasta memorije tokom dugog rada aplikacije.
class ProcessedMessageCache {
  ProcessedMessageCache({
    this.maxEntries = 10000,
    this.timeToLive = const Duration(hours: 1),
  }) : assert(maxEntries > 0),
       assert(timeToLive > Duration.zero);

  final int maxEntries;
  final Duration timeToLive;
  final LinkedHashMap<String, DateTime> _entries = LinkedHashMap();

  int get length => _entries.length;

  /// Vraća `true` samo prvi put kada se važeći ID vidi unutar TTL perioda.
  bool markIfNew(String messageId, {DateTime? now}) {
    final normalizedId = messageId.trim();
    if (normalizedId.isEmpty) return false;

    final currentTime = now ?? DateTime.now();
    _removeExpired(currentTime);

    if (_entries.containsKey(normalizedId)) {
      return false;
    }

    _entries[normalizedId] = currentTime;

    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }

    return true;
  }

  void clear() => _entries.clear();

  void _removeExpired(DateTime now) {
    while (_entries.isNotEmpty) {
      final firstId = _entries.keys.first;
      final seenAt = _entries[firstId]!;

      if (now.difference(seenAt) <= timeToLive) {
        break;
      }

      _entries.remove(firstId);
    }
  }
}
