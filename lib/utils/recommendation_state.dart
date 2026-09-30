import 'id_utils.dart';

int? feedInt(dynamic value) => value is int ? value : int.tryParse('$value');

String? recommendationId(dynamic item) {
  String? goto, bvid, uri;
  int? aid, id, param;
  try {
    goto = item.goto;
  } catch (_) {}
  try {
    aid = feedInt(item.aid);
  } catch (_) {}
  try {
    id = feedInt(item.id);
  } catch (_) {}
  try {
    param = feedInt(item.param);
  } catch (_) {}
  try {
    bvid = item.bvid;
  } catch (_) {}
  try {
    uri = item.uri;
  } catch (_) {}
  if (goto == 'av' || goto == null) {
    if (aid != null && aid > 0) return 'av:$aid';
    if (id != null && id > 0) return 'av:$id';
    if (param != null && param > 0) return 'av:$param';
    if (bvid != null && RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid)) {
      try {
        return 'av:${IdUtils.bv2av(bvid)}';
      } catch (_) {}
    }
  } else {
    if (param != null && param > 0) return '$goto:$param';
    if (id != null && id > 0) return '$goto:$id';
  }
  return uri == null || uri.isEmpty ? null : '${goto ?? 'uri'}:$uri';
}

class RecommendationSeen {
  static const ttl = Duration(days: 7);
  static const capacity = 5000;
  final Map<String, int> entries = {};
  RecommendationSeen([dynamic saved]) {
    if (saved is Map) {
      for (final entry in saved.entries) {
        final timestamp = feedInt(entry.value);
        if (entry.key is String && timestamp != null)
          entries[entry.key as String] = timestamp;
      }
    }
  }
  void prune(int now) {
    entries.removeWhere(
        (_, value) => value > now || now - value >= ttl.inMilliseconds);
    if (entries.length > capacity) {
      final oldest = entries.keys.toList()
        ..sort((a, b) => entries[a]!.compareTo(entries[b]!));
      for (final key in oldest.take(entries.length - capacity)) {
        entries.remove(key);
      }
    }
  }

  bool contains(String key, int now) {
    final timestamp = entries[key];
    return timestamp != null &&
        timestamp <= now &&
        now - timestamp < ttl.inMilliseconds;
  }

  void mark(String key, int now) {
    entries[key] = now;
    prune(now);
  }
}

List<T> uniqueRecommendations<T>(Iterable<T> items, Set<String> excluded) {
  final batch = <String>{};
  return items.where((item) {
    final id = recommendationId(item);
    return id == null || (!excluded.contains(id) && batch.add(id));
  }).toList();
}

class AppFeedCursor {
  int head = 0, tail = 0;
  void accept(int? first, int? last, {required bool refresh}) {
    if (first != null && first > 0 && (refresh || head == 0)) head = first;
    if (last != null && last > 0) tail = last;
  }

  void reset() {
    head = 0;
    tail = 0;
  }
}
